# SPDX-License-Identifier: GPL-2.0-or-later
import importlib.util
from pathlib import Path
import tempfile
import unittest
s=importlib.util.spec_from_file_location('hook',Path(__file__).with_name('keyboard-light-hook.py'));hook=importlib.util.module_from_spec(s);s.loader.exec_module(hook)
class TestHook(unittest.TestCase):
 def event(self,name,**kw): return dict(hook_event_name=name,session_id='thread',turn_id='turn',**kw)
 def test_completion_dedup(self):
  state={};e=self.event('Stop');self.assertEqual(hook.classify(e,state,100)[0],'complete');self.assertIsNone(hook.classify(e,state,101)[0]);self.assertIsNone(hook.classify(self.event('Stop',stop_hook_active=True),{},100)[0])
 def test_async_question_not_completion(self):
  state={};tool='functions.request_user_input_async'
  self.assertEqual(hook.classify(self.event('PreToolUse',tool_name=tool),state,100)[0],'waiting')
  hook.classify(self.event('PostToolUse',tool_name=tool),state,101)
  self.assertIsNone(hook.classify(self.event('Stop'),state,102)[0])
  hook.classify(self.event('UserPromptSubmit'),state,103)
  self.assertEqual(hook.classify(self.event('Stop'),state,104)[0],'complete')
 def test_permission_resolved(self):
  state={};self.assertEqual(hook.classify(self.event('PermissionRequest',tool_name='Bash'),state,100)[0],'waiting')
  hook.classify(self.event('PostToolUse',tool_name='Bash'),state,101)
  self.assertEqual(hook.classify(self.event('Stop'),state,120)[0],'complete')
 def test_plain_question(self):
  state={};e=self.event('InteractionNeeded');e.pop('turn_id');hook.classify(e,state,100)
  self.assertIsNone(hook.classify(self.event('Stop'),state,110)[0])
 def test_other_tools_do_not_notify(self):
  for tool in ['Bash','exec','web_search','request_user_input_async_fake']:
   self.assertIsNone(hook.classify(self.event('PreToolUse',tool_name=tool),{},100)[0])
 def test_emit_and_priority(self):
  with tempfile.TemporaryDirectory() as d:
   commands=[];emit=lambda argv: (commands.append(argv) or 0)
   hook.process(self.event('PermissionRequest',tool_name='Bash'),Path(d),hook.DEFAULTS,emit)
   other=self.event('Stop');other['session_id']='other'
   hook.process(other,Path(d),hook.DEFAULTS,emit)
   self.assertEqual(len(commands),1);self.assertIn('double',commands[0]);self.assertNotIn('Bash',commands[0])
 def test_period_argument(self):
  cfg={"complete":dict(hook.DEFAULTS["complete"],period=1.2)}
  args=hook.command_for("complete",cfg);self.assertEqual(args[-2:],["--period","1.2"])
 def test_disabled(self):
  with tempfile.TemporaryDirectory() as d:
   self.assertIsNone(hook.process(self.event('Stop'),Path(d),{'enabled':False},lambda _: self.fail()))
unittest.main()
