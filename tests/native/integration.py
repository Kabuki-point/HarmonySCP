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
# One authorised client key per run; the public halves are handed to the client under test
# as OpenSSH files inside a temporary directory that is removed after the run.
client_key = paramiko.RSAKey.generate(2048)
other_key = paramiko.RSAKey.generate(2048)
encrypted_key = paramiko.RSAKey.generate(2048)
CLIENT_PASSPHRASE = 'test-passphrase-9f2'
client_pubkey = client_key.get_name() + ' ' + client_key.get_base64()

class Server(paramiko.ServerInterface):
    def __init__(self, sftp_enabled, auth_mode='password'):
        self.attempts = 0
        self.key_attempts = 0
        self.sftp_enabled = sftp_enabled
        self.auth_mode = auth_mode
    def check_channel_request(self, kind, chanid):
        if self.sftp_enabled and kind == 'session':
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
    def get_allowed_auths(self, username):
        return self.auth_mode
    def check_auth_password(self, username, password):
        self.attempts += 1
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ('tester', 'secret') else paramiko.AUTH_FAILED
    def check_auth_publickey(self, username, server_key):
        self.key_attempts += 1
        if username != 'tester':
            return paramiko.AUTH_FAILED
        return paramiko.AUTH_SUCCESSFUL if server_key.asbytes() == client_key.asbytes() else paramiko.AUTH_FAILED

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


for mode in ('ok', 'bad', 'reject', 'remote-close', 'stall', 'refused', 'sftp',
             'pubkey-ok', 'pubkey-wrong', 'pubkey-encrypted', 'pubkey-password-only'):
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    port = listener.getsockname()[1]
    server = Server(mode == 'sftp', 'publickey' if mode.startswith('pubkey') and mode != 'pubkey-password-only'
                    else 'password')
    stop = threading.Event()
    temporary = tempfile.TemporaryDirectory() if mode == 'sftp' else None
    keyring = None
    if mode.startswith('pubkey'):
        keyring = tempfile.TemporaryDirectory()
        directory = Path(keyring.name)
        client_key.write_private_key_file(str(directory / 'id_rsa'))
        (directory / 'id_rsa.pub').write_text(client_pubkey + '\n', encoding='utf-8')
        other_key.write_private_key_file(str(directory / 'id_other'))
        encrypted_key.write_private_key_file(str(directory / 'id_encrypted'), password=CLIENT_PASSPHRASE)
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
        argument = [sys.argv[1], str(port), mode, fingerprint]
        if keyring:
            argument += [keyring.name, CLIENT_PASSPHRASE]
        subprocess.run(argument, check=True, timeout=30)
        if mode in ('reject', 'stall', 'refused'):
            assert server.attempts == 0 and server.key_attempts == 0, 'Credentials sent before trust approval'
        elif mode in ('ok', 'bad', 'remote-close', 'sftp'):
            assert server.attempts == 1, 'Unexpected authentication attempt count'
        elif mode == 'pubkey-ok' or mode == 'pubkey-encrypted':
            assert server.key_attempts >= 1 and server.attempts == 0, 'Key authentication did not reach the server'
        elif mode == 'pubkey-wrong':
            assert server.key_attempts == 1, 'Unexpected key attempt count'
        elif mode == 'pubkey-password-only':
            # The server advertises password only, so the key attempt is refused without reaching the
            # key check and no password is ever offered by a key-only client.
            assert server.key_attempts == 0 and server.attempts == 0, 'Unexpected attempt on password-only server'
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
        if keyring: keyring.cleanup()
print('All 6 SSH scenarios, 4 public key scenarios, and SFTP upload/download, '
      'file management, failure and cancellation checks passed')
