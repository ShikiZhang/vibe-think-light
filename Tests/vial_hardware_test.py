# SPDX-License-Identifier: GPL-2.0-or-later
"""Explicit opt-in; temporary RAM changes only, never save/flash/remap."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

if sys.argv[1:] != ['--allow-light-changes']:
    raise SystemExit('Use --allow-light-changes to briefly change Apollo80 lighting and restore it.')
root = Path(__file__).resolve().parents[1]
cli = root / 'dist/Keyboard Light.app/Contents/MacOS/KeyboardLight'
def call(*args):
    result = subprocess.run([str(cli), '--cli', *args], capture_output=True, text=True, timeout=2.5)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)
devices = [d for d in call('list') if d['backend'] == 'vial']
assert len(devices) == 1, 'Requires one Apollo80 R2'
device = devices[0]['id']
def command(*args): return call(*args, '--device', device)
baseline = command('status')
assert not baseline['notifying'], 'Wait for current notification to end'
journal = Path.home() / 'Library/Caches/KeyboardLight/vial' / (device + '.json')
def record(): return json.loads(journal.read_text())
def notify(pattern, seconds='1.2', color='#FFFF00', period='1.2'):
    start = time.monotonic()
    state = command('notify', '--color', color, '--brightness', '65', '--seconds', seconds, '--pattern', pattern, '--period', period)
    assert time.monotonic() - start < 2.5
    assert state['notifying'] and state['hue'] == baseline['hue']
    return record()['notice']
def wait_worker():
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if record().get('notice') is None: return
        time.sleep(0.05)
    raise AssertionError('Worker failed to restore without a CLI status call')
def assert_baseline():
    state = command('status')
    assert state == baseline, (baseline, state)
try:
    notify('blink')
    wait_worker(); assert_baseline()
    print('PASS: CLI returns promptly; detached worker restores without GUI/status polling', flush=True)
    first = notify('blink', seconds='3')
    time.sleep(0.2)
    second = notify('breathe', color='#00FF00', period='1')
    assert first['baseline'] == second['baseline']
    wait_worker(); assert_baseline()
    print('PASS: replacement preserves baseline and old worker cannot overwrite it', flush=True)
    notify('breathe', seconds='5', color='#00FF00', period='1')
    command('restore'); time.sleep(0.15); assert_baseline()
    print('PASS: explicit cancellation', flush=True)
    notice = notify('blink', seconds='5')
    # Kill only the exact worker pid returned by our own notification journal.
    assert notice['workerPID'] > 0
    os.kill(notice['workerPID'], signal.SIGKILL)
    time.sleep(0.2)
    assert_baseline()
    print('PASS: killed worker recovers from journal on next command', flush=True)
    command('set', '--power', 'off')
    off = command('status'); assert not off['enabled']
    skipped = command('notify', '--color', '#00FF00', '--seconds', '0.5', '--pattern', 'breathe', '--period', '1')
    assert skipped == off and record().get('notice') is None
    assert command('status') == off
    print('PASS: disabled lighting skips notification without spawning a worker', flush=True)
finally:
    command('restore')
    # Preserve HSV exactly through the SET packet rather than RGB conversion.
    # Tests only changed power/temporary notifications, so turning it back on is enough.
    command('set', '--power', 'on' if baseline['enabled'] else 'off')
    assert_baseline()
print('PASS: final original state restored; no EEPROM writes')
