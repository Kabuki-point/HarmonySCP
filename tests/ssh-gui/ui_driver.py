"""Operate the actual HarmonySCP UI through hdc/uitest; never print credentials."""
import argparse
import json
import re
import time
import uuid

from config import DATA, DEVICE_PORT, hdc


def shell(*args):
    return hdc('shell', *args)


def walk(node):
    yield node.get('attributes', {})
    for child in node.get('children', []):
        yield from walk(child)


def layout():
    remote = '/data/local/tmp/harmonyscp-ssh-gui-' + uuid.uuid4().hex + '.json'
    try:
        shell('uitest', 'dumpLayout', '-p', remote)
        # Read into memory; do not retain UI dumps which can contain input text.
        return list(walk(json.loads(shell('cat', remote))))
    finally:
        shell('rm', '-f', remote)


def center(node):
    x1, y1, x2, y2 = map(int, re.findall(r'-?\d+', node['bounds']))
    return (x1 + x2) // 2, (y1 + y2) // 2


def swipe(down):
    # Scale the original tested swipe to the bounds reported by the current display.
    nodes = layout()
    bounds = [list(map(int, re.findall(r'-?\d+', n['bounds']))) for n in nodes if n.get('bounds')]
    # The first valid frame is the display/window, not a scrollable content column.
    frame = next(b for b in bounds if b[2] > b[0] and b[3] > b[1])
    width, height = frame[2] - frame[0], frame[3] - frame[1]
    x, upper, lower = int(width * .86), int(height * .18), int(height * .80)
    shell('uitest', 'uiInput', 'swipe', x, upper if down else lower,
          x, lower if down else upper, 1800)


def top():
    swipe(True)
    time.sleep(.3)


def button(text):
    for _ in range(4):
        found = [n for n in layout() if n.get('type') == 'Button' and
                 n.get('text') == text and n.get('visible') == 'true']
        if found:
            if found[0].get('enabled') != 'true':
                raise AssertionError('Button disabled: ' + text)
            shell('uitest', 'uiInput', 'click', *center(found[0]))
            time.sleep(.35)
            return
        swipe(False)
    raise AssertionError('Button not visible: ' + text)


def state():
    return [n['text'] for n in layout() if n.get('type') == 'Text' and n.get('text')]


def connection_fields():
    # A page title can appear before the rest of the form after restarting the ability.
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        nodes = [n for n in layout() if n.get('type') == 'TextInput']
        if len(nodes) == 4:
            return nodes
        time.sleep(.2)
    raise AssertionError('Expected four visible connection fields')


def fill(wrong=False, port=None):
    top()
    credentials = json.loads((DATA / 'credentials.json').read_text(encoding='utf-8'))
    values = ['127.0.0.1', str(DEVICE_PORT if port is None else port), credentials['username'],
              'invalid_test_password' if wrong else credentials['password']]
    for index, value in enumerate(values):
        nodes = connection_fields()
        shell('uitest', 'uiInput', 'click', *center(nodes[index]))
        shell('uitest', 'uiInput', 'keyEvent', 2072, 2017)  # Ctrl+A
        shell('uitest', 'uiInput', 'keyEvent', 2055)  # Delete
        shell('uitest', 'uiInput', 'text', value)
        shell('uitest', 'uiInput', 'keyEvent', 'Back')
        time.sleep(.2)
    nodes = connection_fields()
    if [n.get('originalText') for n in nodes[:3]] != values[:3]:
        raise AssertionError('Test fields do not match intended values')
    print('Synthetic connection fields entered and checked; credentials omitted', flush=True)


def trust():
    expected = json.loads((DATA / 'status.json').read_text(encoding='utf-8'))['fingerprint']
    for _ in range(4):
        if expected in [n.get('text', '') for n in layout()]:
            print('Displayed SHA256 fingerprint matches the locally generated server key', flush=True)
            button('指纹一致，确认并登录')
            return
        swipe(False)
    raise AssertionError('Displayed fingerprint does not match the trusted server key; authentication refused')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'fill', 'button', 'trust', 'top'])
    parser.add_argument('text', nargs='?', help='Button text for the button action')
    parser.add_argument('--wrong-password', action='store_true')
    parser.add_argument('--port', type=int)
    args = parser.parse_args()
    if args.action == 'inspect':
        print(json.dumps(state(), ensure_ascii=False))
    elif args.action == 'fill':
        fill(args.wrong_password, args.port)
    elif args.action == 'button':
        if not args.text:
            parser.error('button requires its text')
        button(args.text)
    elif args.action == 'trust':
        trust()
    else:
        top()


if __name__ == '__main__':
    main()
