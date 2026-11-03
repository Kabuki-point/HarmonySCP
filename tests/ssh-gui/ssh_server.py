"""Loopback-only SSH service with synthetic credentials; stop with Ctrl+C."""
import argparse
import base64
import hashlib
import json
import logging
import os
import secrets
import signal
import socket
import threading
import time

import paramiko

from config import DATA, HOST_PORT


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    logging.getLogger('paramiko').setLevel(logging.CRITICAL)
    DATA.mkdir(parents=True, exist_ok=True)
    credential_file = DATA / 'credentials.json'
    if credential_file.exists():
        raise RuntimeError('Test credentials already exist; stop any previous test server before removing them')
    key = paramiko.RSAKey.generate(2048)
    fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')
    credentials = {'username': 'emulator_tester', 'password': secrets.token_hex(12)}
    lock = threading.Lock()
    events = []

    def record(kind, connection):
        with lock:
            events.append({'event': kind, 'connection': connection})
            temporary = DATA / 'status.tmp'
            temporary.write_text(json.dumps({'fingerprint': fingerprint, 'port': HOST_PORT, 'events': events}), encoding='utf-8')
            temporary.replace(DATA / 'status.json')

    class Server(paramiko.ServerInterface):
        def __init__(self, connection):
            self.connection = connection

        def get_allowed_auths(self, username):
            return 'password'

        def check_auth_password(self, username, password):
            record('password_attempt', self.connection)
            valid = username == credentials['username'] and secrets.compare_digest(password, credentials['password'])
            record('auth_success' if valid else 'auth_failed', self.connection)
            return paramiko.AUTH_SUCCESSFUL if valid else paramiko.AUTH_FAILED

    def serve(sock, connection):
        transport = None
        try:
            mode = (DATA / 'mode').read_text(encoding='utf-8').strip()
            record('accepted', connection)
            if mode == 'stall':
                sock.settimeout(20)
                while sock.recv(4096):
                    pass
                return
            transport = paramiko.Transport(sock)
            transport.add_server_key(key)
            transport.start_server(server=Server(connection))
            record('handshake_done', connection)
            while transport.is_active():
                if mode == 'remote-close' and transport.is_authenticated():
                    time.sleep(1)
                    record('server_close', connection)
                    break
                time.sleep(0.05)
        except (EOFError, OSError, paramiko.SSHException):
            record('transport_ended', connection)
        finally:
            if transport:
                transport.close()
            sock.close()
            record('closed', connection)

    def stop(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    listener = socket.socket()
    created_credentials = False
    try:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', HOST_PORT))
        listener.listen(8)
        # Create with restrictive permissions before writing the random test password.
        fd = os.open(credential_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        created_credentials = True
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            json.dump(credentials, output)
        (DATA / 'mode').write_text('normal', encoding='utf-8')
        record('ready', 0)
        print('Loopback SSH test server ready; credentials are not logged', flush=True)
        connection = 0
        while True:
            sock, _ = listener.accept()
            connection += 1
            threading.Thread(target=serve, args=(sock, connection), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        listener.close()
        if created_credentials:
            credential_file.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
