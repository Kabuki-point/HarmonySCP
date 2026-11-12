"""Loopback SSH service for public-key validation on the emulator.

STATUS: prepared but not yet usable end to end. The ohosTest module (entry_test)
does not ship libentry.so, so device-side cases currently bind the preview mock
and never reach this server. Keep this file for plan A, where a UI entry point
lets the installed app be driven through the real page.

Advertises only publickey and accepts exactly one synthetic key. Writes the
host fingerprint and the accepted/rejected key names to build/ssh-gui so the
device side can be compared with what the server saw. No real credentials.
"""
import argparse
import base64
import hashlib
import json
import logging
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
    host_key = paramiko.RSAKey.generate(2048)
    fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(host_key.asbytes()).digest()).decode().rstrip('=')
    # Two synthetic client keys: one authorised, one deliberately not.
    allowed = paramiko.RSAKey.generate(2048)
    denied = paramiko.RSAKey.generate(2048)
    lock = threading.Lock()
    events = []

    def record(kind, connection, detail=''):
        with lock:
            events.append({'event': kind, 'connection': connection, 'detail': detail})
            target = DATA / 'status.tmp'
            target.write_text(json.dumps({
                'fingerprint': fingerprint,
                'port': HOST_PORT,
                'allowed': allowed.get_base64(),
                'denied': denied.get_base64(),
                'events': events,
            }), encoding='utf-8')
            target.replace(DATA / 'status.json')

    class Server(paramiko.ServerInterface):
        def __init__(self, connection):
            self.connection = connection

        def get_allowed_auths(self, username):
            return 'publickey'

        def check_auth_publickey(self, username, key):
            offered = key.get_base64()
            match = offered == allowed.get_base64()
            record('key_offered', self.connection, 'allowed' if match else 'denied')
            if not match:
                # Enforce here: Paramiko still calls this when only password is advertised.
                record('auth_failed', self.connection, 'unknown key')
                return paramiko.AUTH_FAILED
            record('auth_success', self.connection)
            return paramiko.AUTH_SUCCESSFUL

        def check_auth_password(self, username, password):
            record('password_attempt', self.connection)
            return paramiko.AUTH_FAILED

    def serve(sock, connection):
        transport = None
        try:
            record('accepted', connection)
            transport = paramiko.Transport(sock)
            transport.add_server_key(host_key)
            transport.start_server(server=Server(connection))
            record('handshake_done', connection)
            while transport.is_active():
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
    try:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', HOST_PORT))
        listener.listen(8)
        # Write the synthetic client keys to the ignored build directory so the device
        # side can load the same material; they are deleted when the server stops.
        allowed.write_private_key_file(str(DATA / 'allowed_key'))
        denied.write_private_key_file(str(DATA / 'denied_key'))
        record('ready', 0)
        print('Public-key SSH test server ready; fingerprints written under build/ssh-gui', flush=True)
        connection = 0
        while True:
            sock, _ = listener.accept()
            connection += 1
            threading.Thread(target=serve, args=(sock, connection), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        listener.close()
        for name in ('allowed_key', 'denied_key'):
            (DATA / name).unlink(missing_ok=True)


if __name__ == '__main__':
    main()
