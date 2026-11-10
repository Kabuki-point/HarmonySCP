"""Local-only SSH integration server. Run with a Python env containing paramiko.
Usage: python integration.py /absolute/path/to/ssh_client_test
Test credentials below are synthetic and only accepted on loopback.
"""
import base64
import hashlib
import errno
import logging
import os
import posixpath
from queue import Empty, Queue
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import paramiko

logging.getLogger('paramiko').setLevel(logging.CRITICAL)
key = paramiko.RSAKey.generate(2048)
fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')

class Server(paramiko.ServerInterface):
    def __init__(self, mode):
        self.attempts = 0
        self.mode = mode
        self.shells = Queue()
        self.pty_requests = []
        self.window_changes = []

    def check_channel_request(self, kind, chanid):
        if self.mode in ('sftp', 'terminal') and kind == 'session':
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
    def get_allowed_auths(self, username):
        return 'password'
    def check_auth_password(self, username, password):
        self.attempts += 1
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ('tester', 'secret') else paramiko.AUTH_FAILED

    def check_channel_pty_request(self, channel, term, width, height, pixelwidth, pixelheight, modes):
        self.pty_requests.append((term, width, height))
        return self.mode == 'terminal' and width != 42

    def check_channel_shell_request(self, channel):
        if self.mode != 'terminal':
            return False
        self.shells.put(channel)
        return True

    def check_channel_window_change_request(self, channel, width, height, pixelwidth, pixelheight):
        self.window_changes.append((width, height))
        return self.mode == 'terminal'


def echo_shell(channel):
    """Deterministic byte echo. No commands are executed by the fixture."""
    pending = bytearray()
    try:
        channel.settimeout(8)
        channel.sendall(b'fixture-ready\r\n')
        while data := channel.recv(4096):
            pending.extend(data)
            while b'\r' in pending:
                end = pending.index(b'\r') + 1
                line = bytes(pending[:end])
                del pending[:end]
                if line == b'fixture-exit\r':
                    channel.sendall(b'x' * 40000 + b'fixture-end')
                    channel.shutdown_write()
                    return
                channel.sendall(line)
    except (EOFError, OSError):
        pass
    finally:
        channel.close()


class SlowFile(paramiko.SFTPHandle):
    def stat(self):
        stream = getattr(self, 'readfile', None) or self.writefile
        return paramiko.SFTPAttributes.from_stat(os.fstat(stream.fileno()))

    def read(self, offset, length):
        time.sleep(0.02)
        return super().read(offset, length)

    def write(self, offset, data):
        time.sleep(0.02)
        return super().write(offset, data)


class SftpFixture(paramiko.SFTPServerInterface):
    def __init__(self, server, root):
        super().__init__(server)
        self.root = root.resolve()

    def canonicalize(self, path):
        return posixpath.normpath(path if path.startswith('/') else '/work/' + path)

    def local(self, path):
        if '..' in path.split('/') or path.startswith('/denied'):
            raise PermissionError(errno.EACCES, 'Path is outside the test fixture')
        local = self.root / path.lstrip('/')
        if not local.parent.resolve().is_relative_to(self.root) and local != self.root:
            raise PermissionError(errno.EACCES, 'Path is outside the test fixture')
        return local

    def list_folder(self, path):
        try:
            result = []
            for item in self.local(path).iterdir():
                entry = paramiko.SFTPAttributes.from_stat(item.lstat(), item.name)
                result.append(entry)
            return result
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def lstat(self, path):
        try:
            return paramiko.SFTPAttributes.from_stat(self.local(path).lstat())
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def mkdir(self, path, attr):
        try:
            self.local(path).mkdir(mode=attr.st_mode)
            return paramiko.SFTP_OK
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def rmdir(self, path):
        try:
            self.local(path).rmdir()
            return paramiko.SFTP_OK
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def open(self, path, flags, attr):
        try:
            fd = os.open(self.local(path), flags, 0o600)
            writing = bool(flags & os.O_WRONLY)
            stream = os.fdopen(fd, 'wb' if writing else 'rb')
            handle = SlowFile(flags)
            if writing:
                handle.writefile = stream
            else:
                handle.readfile = stream
            return handle
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def stat(self, path):
        try:
            return paramiko.SFTPAttributes.from_stat(self.local(path).stat())
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def rename(self, oldpath, newpath):
        try:
            old = self.local(oldpath)
            new = self.local(newpath)
            if old.is_dir():
                if os.path.lexists(new):
                    raise FileExistsError(errno.EEXIST, 'Destination already exists')
                old.rename(new)
            else:
                os.link(old, new)
                old.unlink()
            return paramiko.SFTP_OK
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def remove(self, path):
        try:
            self.local(path).unlink()
            return paramiko.SFTP_OK
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)


for mode in ('ok', 'bad', 'reject', 'remote-close', 'stall', 'refused', 'sftp', 'terminal'):
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    port = listener.getsockname()[1]
    server = Server(mode)
    stop = threading.Event()
    temporary = tempfile.TemporaryDirectory() if mode in ('sftp', 'terminal') else None
    if temporary:
        root = Path(temporary.name)
        work = root / 'work'
        work.mkdir()
        (work / 'keep.txt').write_bytes(b'keep')
        (work / 'link').symlink_to('keep.txt')
        (root / 'large.bin').write_bytes(b'x' * (2 * 1024 * 1024))
    def serve():
        transport = None
        connection = None
        try:
            connection, _ = listener.accept()
            if mode == 'stall':
                stop.wait(5)
            else:
                transport = paramiko.Transport(connection)
                transport.add_server_key(key)
                if temporary:
                    transport.set_subsystem_handler('sftp', paramiko.SFTPServer, SftpFixture, root)
                transport.start_server(server=server)
                while not stop.wait(0.02) and transport.is_active():
                    try:
                        shell = server.shells.get_nowait()
                    except Empty:
                        pass
                    else:
                        threading.Thread(target=echo_shell, args=(shell,), daemon=True).start()
                    if mode == 'remote-close' and transport.is_authenticated():
                        time.sleep(0.2)
                        transport.close()
        except (EOFError, OSError, paramiko.SSHException):
            pass
        finally:
            if transport: transport.close()
            if connection: connection.close()
    if mode == 'refused':
        listener.close()
        thread = None
    else:
        listener.listen(2)
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
    try:
        subprocess.run([sys.argv[1], str(port), mode, fingerprint], check=True, timeout=30)
        if mode in ('reject', 'stall', 'refused'):
            assert server.attempts == 0, 'Password sent before trust approval'
        elif mode in ('ok', 'bad', 'remote-close', 'sftp', 'terminal'):
            assert server.attempts == 1, 'Unexpected authentication attempt count'
        if mode == 'terminal':
            assert server.pty_requests == [(b'xterm-256color', 42, 24)] + [(b'xterm-256color', 80, 24)] * 3
            assert server.window_changes == [(120, 36)]
        if mode == 'sftp':
            expected = bytes(i % 251 for i in range(180000))
            assert (root / '文件 with spaces.bin').read_bytes() == expected
            assert (root / 'after-cancel').read_bytes() == expected
            assert (root / 'empty').stat().st_size == 0
            assert not (root / 'cancelled').exists()
            assert sorted(item.name for item in work.iterdir()) == ['keep.txt', 'link']
            assert (work / 'keep.txt').read_bytes() == b'keep'
            assert (work / 'link').is_symlink()
            assert not list(root.glob('.harmonyscp-*.part'))
    finally:
        stop.set()
        listener.close()
        if thread: thread.join(timeout=2)
        if temporary: temporary.cleanup()
print('All SSH, SFTP and PTY scenarios passed')
