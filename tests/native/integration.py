"""Local-only SSH integration server. Run with a Python env containing paramiko.
Usage: python integration.py /absolute/path/to/ssh_client_test
Test credentials below are synthetic and only accepted on loopback.
"""
import base64
import hashlib
import logging
import os
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
    def __init__(self, sftp_enabled):
        self.attempts = 0
        self.sftp_enabled = sftp_enabled
    def check_channel_request(self, kind, chanid):
        if self.sftp_enabled and kind == 'session':
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
    def get_allowed_auths(self, username):
        return 'password'
    def check_auth_password(self, username, password):
        self.attempts += 1
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ('tester', 'secret') else paramiko.AUTH_FAILED

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
        self.root = root

    def local(self, path):
        name = path.removeprefix('/')
        if not name or '/' in name or name in ('.', '..'):
            raise PermissionError(13, 'Only fixture files are accessible')
        return self.root / name

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
            os.link(old, self.local(newpath))
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


for mode in ('ok', 'bad', 'reject', 'remote-close', 'stall', 'refused', 'sftp'):
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    port = listener.getsockname()[1]
    server = Server(mode == 'sftp')
    stop = threading.Event()
    temporary = tempfile.TemporaryDirectory() if mode == 'sftp' else None
    if temporary:
        root = Path(temporary.name)
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
                if mode == 'sftp':
                    transport.set_subsystem_handler('sftp', paramiko.SFTPServer, SftpFixture, root)
                transport.start_server(server=server)
                while not stop.wait(0.02) and transport.is_active():
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
        subprocess.run([sys.argv[1], str(port), mode, fingerprint], check=True, timeout=15)
        if mode in ('reject', 'stall', 'refused'):
            assert server.attempts == 0, 'Password sent before trust approval'
        elif mode in ('ok', 'bad', 'remote-close', 'sftp'):
            assert server.attempts == 1, 'Unexpected authentication attempt count'
        if mode == 'sftp':
            expected = bytes(i % 251 for i in range(180000))
            assert (root / '文件 with spaces.bin').read_bytes() == expected
            assert (root / 'after-cancel').read_bytes() == expected
            assert (root / 'empty').stat().st_size == 0
            assert not (root / 'cancelled').exists()
            assert not list(root.glob('.harmonyscp-*.part'))
    finally:
        stop.set()
        listener.close()
        if thread: thread.join(timeout=2)
        if temporary: temporary.cleanup()
print('All 6 SSH scenarios and SFTP upload/download, failure and cancellation checks passed')
