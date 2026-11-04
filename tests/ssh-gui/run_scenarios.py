"""Run seven SSH scenarios against the real simulator UI and a local test server."""
import argparse
import json
import time

from config import BUNDLE, DATA, REFUSED_PORT
import ui_driver as ui


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    if not (DATA / 'credentials.json').exists():
        raise RuntimeError('Start tests/ssh-gui/ssh_server.py and configure hdc rport first')
    results = []  # Each invocation must run the tests, never reuse an earlier pass.
    result_file = DATA / 'results.json'
    result_file.write_text('[]', encoding='utf-8')

    def events():
        return json.loads((DATA / 'status.json').read_text(encoding='utf-8'))['events']

    def latest():
        return max(event['connection'] for event in events())

    def kinds(connection):
        return [event['event'] for event in events() if event['connection'] == connection]

    def expect(text, timeout=8):
        ui.top()
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            if text in ui.state():
                return
            time.sleep(.2)
        raise AssertionError('Expected UI state: ' + text)

    def closed(connection):
        until = time.monotonic() + 5
        while time.monotonic() < until:
            if 'closed' in kinds(connection):
                return
            time.sleep(.1)
        raise AssertionError('Connection was not closed')

    def require(condition, message):
        if not condition:
            raise AssertionError(message)

    def record(name, connection, elapsed=None):
        result = {'scenario': name, 'result': 'passed', 'server_events': kinds(connection)}
        if elapsed is not None:
            result['elapsed_from_fingerprint_approval_start_seconds'] = round(elapsed, 2)
        results.append(result)
        result_file.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
        print(name + ': PASSED', flush=True)

    def begin(mode='normal', wrong=False):
        (DATA / 'mode').write_text(mode, encoding='utf-8')
        previous = latest()
        ui.fill(wrong)
        ui.button('连接服务器')
        expect('核对服务器身份')
        connection = latest()
        require(connection > previous, 'No new server connection')
        require('password_attempt' not in kinds(connection), 'Authentication happened before fingerprint approval')
        return connection

    try:
        ui.shell('aa', 'force-stop', BUNDLE)
        ui.shell('aa', 'start', '-a', 'EntryAbility', '-b', BUNDLE)
        expect('准备连接')
        connection = begin()
        ui.trust()
        expect('已安全连接')
        require(kinds(connection).count('auth_success') == 1, 'Server did not authenticate exactly once')
        ui.button('断开连接')
        expect('准备连接')
        closed(connection)
        record('successful-login-and-disconnect', connection)

        connection = begin()
        ui.button('拒绝并断开')
        expect('准备连接')
        closed(connection)
        require('password_attempt' not in kinds(connection), 'Password sent after fingerprint rejection')
        record('reject-fingerprint-without-authentication', connection)

        connection = begin(wrong=True)
        ui.trust()
        expect('连接失败')
        closed(connection)
        require(kinds(connection).count('auth_failed') == 1 and 'auth_success' not in kinds(connection),
                'Wrong-password authentication result mismatch')
        record('wrong-password', connection)

        connection = begin('remote-close')
        started = time.monotonic()
        ui.trust()
        expect('连接失败', timeout=30)
        closed(connection)
        require('auth_success' in kinds(connection) and 'server_close' in kinds(connection),
                'Server did not close an authenticated connection')
        record('server-close-after-login', connection, time.monotonic() - started)

        (DATA / 'mode').write_text('stall', encoding='utf-8')
        previous = latest()
        ui.fill()
        ui.button('连接服务器')
        expect('安全握手')
        connection = latest()
        require(connection > previous, 'No new stalled connection')
        ui.button('取消连接')
        expect('准备连接')
        closed(connection)
        require('password_attempt' not in kinds(connection), 'Password sent during handshake cancellation')
        record('cancel-during-handshake', connection)

        (DATA / 'mode').write_text('normal', encoding='utf-8')
        previous = latest()
        ui.fill(port=REFUSED_PORT)
        ui.button('连接服务器')
        expect('连接失败')
        require(latest() == previous, 'Unavailable-port test reached the test SSH server')
        record('unavailable-port', 0)

        connection = begin()
        ui.trust()
        expect('已安全连接')
        ui.shell('uitest', 'uiInput', 'keyEvent', 'Home')
        closed(connection)
        ui.shell('aa', 'start', '-a', 'EntryAbility', '-b', BUNDLE)
        expect('准备连接')
        record('disconnect-on-background-and-return', connection)
    finally:
        # Clear synthetic form contents even when a test fails. Never stop a system SSH service.
        ui.shell('aa', 'force-stop', BUNDLE)
        ui.shell('aa', 'start', '-a', 'EntryAbility', '-b', BUNDLE)
    print('All 7 emulator UI SSH scenarios passed', flush=True)


if __name__ == '__main__':
    main()
