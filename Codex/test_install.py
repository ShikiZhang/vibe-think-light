# SPDX-License-Identifier: GPL-2.0-or-later
import importlib.util
import json
from pathlib import Path
import shlex
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('installer',Path(__file__).with_name('install.py'))
installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)

class TestInstaller(unittest.TestCase):
    def test_merge_idempotent_uninstall_and_spaces(self):
        with tempfile.TemporaryDirectory(prefix='keyboard light ') as d:
            home=Path(d).resolve(); app=home/'custom app/KeyboardLight'
            existing={'description':'mine','hooks':{'Stop':[{'hooks':[{'type':'command','command':'echo keep','timeout':2}]}]}}
            (home/'hooks.json').write_text(json.dumps(existing))
            (home/'AGENTS.md').write_text('My existing instructions.\n')
            (home/'config.toml').write_text('notify = ["keep"]\n')
            command=installer.install(home,app)
            self.assertIn(str(home/'hooks/vibe-think-light-hook.py'),shlex.split(command))
            self.assertIn('CODEX_HOME='+str(home),shlex.split(command))
            first={p:p.read_bytes() for p in (home/'hooks.json',home/'AGENTS.md')}
            installer.install(home,app)
            for p,content in first.items():self.assertEqual(p.read_bytes(),content)
            hooks=json.loads((home/'hooks.json').read_text())
            self.assertEqual(hooks['hooks']['Stop'][0],existing['hooks']['Stop'][0])
            self.assertEqual(len(hooks['hooks']['Stop']),2)
            self.assertEqual(json.loads((home/'keyboard-light.json').read_text())['app'],str(app))
            installer.install(home,app,uninstall=True)
            hooks=json.loads((home/'hooks.json').read_text())
            self.assertEqual(hooks['hooks']['Stop'],existing['hooks']['Stop'])
            self.assertNotIn(installer.START,(home/'AGENTS.md').read_text())
            self.assertIn('My existing instructions.',(home/'AGENTS.md').read_text())
            self.assertEqual((home/'config.toml').read_text(),'notify = ["keep"]\n')
            self.assertFalse((home/'hooks/vibe-think-light-hook.py').exists())

    def test_existing_settings_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d).resolve(); raw='{"enabled":false,"complete":{"seconds":2}}'
            (home/'keyboard-light.json').write_text(raw)
            installer.install(home,home/'app')
            self.assertEqual((home/'keyboard-light.json').read_text(),raw)

    def test_invalid_hooks_not_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d).resolve();(home/'hooks.json').write_text('not json')
            with self.assertRaises(ValueError):installer.install(home,home/'app')
            self.assertEqual((home/'hooks.json').read_text(),'not json')
            self.assertFalse((home/'hooks/vibe-think-light-hook.py').exists())

if __name__=='__main__':unittest.main()
