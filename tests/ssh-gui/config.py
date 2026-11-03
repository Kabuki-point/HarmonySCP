"""Local configuration shared by the SSH service and simulator UI driver."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'build' / 'ssh-gui'
HOST_PORT = int(os.environ.get('SSH_GUI_HOST_PORT', '23222'))
DEVICE_PORT = int(os.environ.get('SSH_GUI_DEVICE_PORT', '2222'))
REFUSED_PORT = int(os.environ.get('SSH_GUI_REFUSED_PORT', '2223'))
BUNDLE = 'com.example.har_scp'


def hdc(*args):
    executable = os.environ.get('HDC', 'hdc')
    target = os.environ.get('HDC_TARGET')
    command = [executable] + (['-t', target] if target else [])
    try:
        result = subprocess.run(command + list(map(str, args)), text=True, encoding='utf-8',
                                capture_output=True, timeout=20)
    except FileNotFoundError:
        raise RuntimeError('Set HDC to the SDK hdc executable, or add it to PATH') from None
    except subprocess.TimeoutExpired:
        raise RuntimeError('HDC operation timed out; check device connection') from None
    output = result.stdout.strip()
    if result.returncode or output.startswith(('[Fail]', '[Error]', 'Error:', 'Illegal argument')):
        # UI input failures may include entered text; never echo commands or raw output.
        raise RuntimeError('HDC operation failed; check device connection and UI test support')
    return result.stdout
