"""Local-only SSH integration server. Run with a Python env containing paramiko.
Usage: python integration.py /absolute/path/to/ssh_client_test
Test credentials below are synthetic and only accepted on loopback.
"""
import base64
import hashlib
import logging
import socket
import subprocess
import sys
import threading
import time
import paramiko

logging.getLogger('paramiko').setLevel(logging.CRITICAL)
key = paramiko.RSAKey.generate(2048)
fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')

class Server(paramiko.ServerInterface):
    def __init__(self):
        self.attempts = 0
    def get_allowed_auths(self, username):
        return 'password'
    def check_auth_password(self, username, password):
        self.attempts += 1
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ('tester', 'secret') else paramiko.AUTH_FAILED

for mode in ('ok', 'bad', 'reject', 'remote-close', 'stall', 'refused'):
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    port = listener.getsockname()[1]
    server = Server()
    stop = threading.Event()
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
        elif mode in ('ok', 'bad', 'remote-close'):
            assert server.attempts == 1, 'Unexpected authentication attempt count'
    finally:
        stop.set()
        listener.close()
        if thread: thread.join(timeout=2)
print('All 6 native integration scenarios passed')
