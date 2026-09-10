#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Codex lifecycle -> Keyboard Light. Never returns approval/continuation decisions."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

APP = Path(os.environ.get('KEYBOARD_LIGHT_APP', str(Path.home() / 'Applications/Keyboard Light.app/Contents/MacOS/KeyboardLight')))
CODEX_HOME_DIR = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
SETTINGS = CODEX_HOME_DIR / 'keyboard-light.json'
CACHE = Path.home() / 'Library/Caches/KeyboardLight'
QUESTION = re.compile(r'(^|[._:])request_user_input(?:_async)?$')
DEFAULTS = {'enabled': True,
            'waiting': {'color': '#FFFF00', 'pattern': 'blink', 'seconds': 5, 'brightness': 100, 'period': 1.2},
            'complete': {'color': '#00FF00', 'pattern': 'breathe', 'seconds': 5, 'brightness': 100, 'period': 1}}

def classify(event, state, now):
    """Only event metadata is inspected; never parse prompts/tool code as commands."""
    name = event.get('hook_event_name', '')
    session = str(event.get('session_id') or os.environ.get('CODEX_THREAD_ID') or 'unknown')
    key = hashlib.sha256(session.encode()).hexdigest()[:24]
    turn = str(event.get('turn_id') or '')
    tool = str(event.get('tool_name') or '')
    sessions = state.setdefault('sessions', {})
    # Expire old per-thread bookkeeping without retaining message contents.
    for old in list(sessions):
        if now - sessions[old].get('updated', 0) > 86400: del sessions[old]
    item = sessions.setdefault(key, {'updated': now})
    item['updated'] = now
    action = None
    if name == 'UserPromptSubmit':
        item.pop('waiting', None)
    elif name == 'InteractionNeeded' or name == 'PermissionRequest' or (name == 'PreToolUse' and QUESTION.search(tool)):
        item['waiting'] = {'turn': turn, 'tool': tool, 'kind': name, 'at': now}
        # PreToolUse and PermissionRequest for the same question should not restart the light.
        if now - item.get('last_wait', 0) > 1:
            action = 'waiting'; item['last_wait'] = now
    elif name == 'PostToolUse':
        wait = item.get('waiting', {})
        # Async question tools return immediately, before the user answers.
        if wait and wait.get('tool') == tool and not tool.endswith('request_user_input_async'):
            item.pop('waiting', None)
    elif name == 'Stop':
        wait = item.get('waiting', {})
        waiting_this_turn = wait and (wait.get('turn') == turn or (not wait.get('turn') and now - wait.get('at', 0) < 3600))
        if not event.get('stop_hook_active') and not waiting_this_turn:
            marker = turn or str(int(now // 2))
            if item.get('completed_turn') != marker:
                action = 'complete'; item['completed_turn'] = marker
    return action, key

def command_for(action, settings):
    spec = settings.get(action, DEFAULTS[action])
    # Arguments are passed as an argv list. Event content is never executed.
    return [str(settings.get('app', APP)), '--cli', 'notify', '--color', str(spec.get('color', DEFAULTS[action]['color'])),
            '--pattern', str(spec.get('pattern', DEFAULTS[action]['pattern'])),
            '--seconds', str(spec.get('seconds', DEFAULTS[action]['seconds'])),
            '--brightness', str(spec.get('brightness', DEFAULTS[action]['brightness']))] + (
            ['--device', str(settings['device'])] if settings.get('device') else []) + (
            ['--period', str(spec['period'])] if 'period' in spec else [])

def process(event, cache=CACHE, settings=None, emit=None):
    if settings is None:
        settings = json.loads(SETTINGS.read_text()) if SETTINGS.exists() else DEFAULTS
    if not settings.get('enabled', True): return None
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / 'codex.lock').open('a') as lock:
        deadline = time.monotonic() + 0.4
        while True:
            try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); break
            except BlockingIOError:
                if time.monotonic() > deadline: return None
                time.sleep(0.02)
        path = cache / 'codex-state.json'
        try: state = json.loads(path.read_text())
        except (OSError, ValueError): state = {}
        now = time.time()
        action, key = classify(event, state, now)
        # A completion in a different task must not cover a current attention signal.
        if action == 'complete' and now < state.get('attention_until', 0): action = None
        outcome = None
        if action:
            argv = command_for(action, settings)
            if emit is not None: outcome = emit(argv)
            else:
                try:
                    result = subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.5)
                    outcome = result.returncode
                except (OSError, subprocess.TimeoutExpired): outcome = -1
            if action == 'waiting' and outcome == 0:
                state['attention_until'] = now + min(60, max(0, float(settings.get('waiting', {}).get('seconds', DEFAULTS['waiting']['seconds']))))
            log = cache / 'codex-events.jsonl'
            if log.exists() and log.stat().st_size > 100000: log.replace(cache / 'codex-events.previous.jsonl')
            with log.open('a') as f:
                f.write(json.dumps({'at': now, 'event': event.get('hook_event_name'), 'thread': key, 'action': action, 'exit': outcome}) + '\n')
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(state));temporary.replace(path)
        return action

def main():
    try:
        if sys.argv[1:] == ['--waiting']:
            event = {'hook_event_name': 'InteractionNeeded', 'session_id': os.environ.get('CODEX_THREAD_ID', '')}
        else:
            event = json.loads(sys.stdin.read(1048576))
        if isinstance(event, dict): process(event)
    except Exception:
        pass  # Disconnected keyboard or bad settings must never block Codex.
    print('{}')

if __name__ == '__main__': main()
