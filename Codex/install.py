#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Opt-in installer. Merge hooks; preserve user config, settings and trust decisions."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import sys

START = '<!-- vibe-think-light:start -->'
END = '<!-- vibe-think-light:end -->'
EVENTS = ('PreToolUse', 'PermissionRequest', 'PostToolUse', 'UserPromptSubmit', 'Stop')

def remove_block(text):
    if START not in text:
        return text
    if END not in text:
        raise ValueError('Incomplete vibe-think-light AGENTS block; repair it before installing')
    a = text.index(START)
    b = text.index(END, a) + len(END)
    return text[:a] + text[b:]

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    if path.exists():
        backup = path.with_name(path.name + '.vibe-think-light.bak')
        if not backup.exists():
            shutil.copy2(path, backup)
    temporary = path.with_name(path.name + '.vibe-think-light.tmp')
    temporary.write_text(text)
    temporary.replace(path)

def install(home, app, uninstall=False):
    home = home.expanduser().resolve()
    source = Path(__file__).resolve().parent
    target = home / 'hooks/vibe-think-light-hook.py'
    # Bind CODEX_HOME explicitly because alternate Codex homes may not be exported to hooks.
    command = ' '.join(shlex.quote(x) for x in ['env', 'CODEX_HOME=' + str(home), sys.executable, str(target)])
    hooks_path = home / 'hooks.json'
    data = json.loads(hooks_path.read_text()) if hooks_path.exists() else {'hooks': {}}
    if not isinstance(data, dict) or not isinstance(data.get('hooks', {}), dict):
        raise ValueError('hooks.json must contain a hooks object')
    groups = data.setdefault('hooks', {})
    agents_path = home / 'AGENTS.md'
    old_agents = agents_path.read_text() if agents_path.exists() else ''
    clean_agents = remove_block(old_agents)
    # Remove our exact executable from prior installs, retaining siblings in mixed groups.
    def owned(hook):
        try:
            return hook.get('type') == 'command' and str(target) in shlex.split(hook.get('command', ''))
        except ValueError:
            return False
    for event in EVENTS:
        kept = []
        for group in groups.get(event, []):
            item = dict(group)
            original = item.get('hooks', [])
            remaining = [hook for hook in original if not owned(hook)]
            if remaining or not original:
                item['hooks'] = remaining
                kept.append(item)
        if kept or event in groups:
            groups[event] = kept
        if not uninstall:
            group = {'hooks': [{'type': 'command', 'command': command, 'timeout': 4}]}
            if event == 'PreToolUse':
                group['matcher'] = r'(^|[._:])request_user_input(_async)?$'
            groups.setdefault(event, []).append(group)
    block = f'''{START}
## Think6.5 V3 light reminders
Lifecycle hooks signal approval requests, structured user questions, and completed turns.
Immediately before yielding a plain-text question or physical-action request that requires a reply,
run `{command} --waiting`. Do not repeat this for structured question tools or optional offers.
The Stop hook handles completion; do not send duplicate completion reminders.
Reminder failures must never block work or act as approval decisions.
{END}'''
    if uninstall:
        new_agents = clean_agents
    elif START in old_agents:
        a = old_agents.index(START); b = old_agents.index(END, a) + len(END)
        new_agents = old_agents[:a] + block + old_agents[b:]
    else:
        new_agents = old_agents + ('\n\n' if old_agents else '') + block + '\n'
    if not uninstall:
        write(target, (source / 'keyboard-light-hook.py').read_text())
        settings_path = home / 'keyboard-light.json'
        if not settings_path.exists():
            settings = json.loads((source / 'settings.json').read_text())
            settings['app'] = str(app.expanduser().resolve())
            write(settings_path, json.dumps(settings, indent=2) + '\n')
    write(hooks_path, json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    if new_agents != old_agents:
        write(agents_path, new_agents)
    if uninstall and target.exists():
        target.unlink()
    return command

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--codex-home', type=Path, default=Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))))
    parser.add_argument('--app', type=Path, default=Path.home() / 'Applications/Keyboard Light.app/Contents/MacOS/KeyboardLight')
    parser.add_argument('--uninstall', action='store_true')
    args = parser.parse_args()
    if not args.uninstall and not args.app.expanduser().is_file():
        parser.error('Build/install the Mac app first, or pass --app /absolute/path/to/KeyboardLight')
    command = install(args.codex_home, args.app, args.uninstall)
    print('Removed only vibe-think-light hooks and AGENTS block; kept settings/backups.' if args.uninstall else
          'Installed. Review and trust these hooks in Codex /hooks, then fully quit and reopen the desktop app.\n' + command)
    print('config.toml and hook trust were not modified.')

if __name__ == '__main__':
    main()
