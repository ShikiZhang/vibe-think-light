# SPDX-License-Identifier: GPL-2.0-or-later
"""Every invalid case must fail during parsing, before USB discovery."""
import json
from pathlib import Path
import subprocess

cli = str(Path(__file__).resolve().parents[1] / 'keyboardlight')
result = subprocess.run([cli, 'effects'], text=True, capture_output=True, check=True)
assert len(result.stdout.strip().splitlines()) == 42
cases = [(['set', '--brightness', '101'], '亮度'),
         (['set', '--color', 'not-hex'], '颜色'),
         (['notify', '--seconds', 'nan'], '时长'),
         (['notify', '--period', '0.49'], '--period'),
         (['notify', '--pattern', 'solid', '--period', '1'], '--period'),
         (['set', '--power', 'maybe'], 'power'),
         (['save', '--seconds', '3'], '无效参数'),
         (['status', '--device', 'a', '--device', 'b'], '重复参数')]
for args, expected in cases:
    result = subprocess.run([cli] + args, text=True, capture_output=True)
    assert result.returncode != 0 and expected in result.stderr, (args, result.stdout, result.stderr)
print('PASS: 42 CLI effects and 8 invalid-argument paths (no USB writes)')
