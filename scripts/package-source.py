#!/usr/bin/env python3
"""Package project + pinned upstream corresponding source; never include personal caches."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
QMK = ROOT / '.deps/qmk'
PIN = json.loads((ROOT / 'Firmware/dependencies.json').read_text())['qmk_commit']
MODULES = ('lib/chibios', 'lib/chibios-contrib', 'lib/printf', 'lib/lufa')

def git(*args, cwd=QMK):
    return subprocess.check_output(['git', '-C', str(cwd), *args]).decode().strip()

def tracked(base):
    raw=subprocess.check_output(['git', '-C', str(base), 'ls-files', '-z'])
    return [base / name.decode() for name in raw.split(b'\0') if name and (base/name.decode()).is_file()]

def main():
    assert git('rev-parse', 'HEAD') == PIN, 'QMK pin mismatch'
    assert not git('status', '--porcelain', '--untracked-files=no'), 'QMK tracked sources changed'
    for module in MODULES:
        expected=git('ls-tree','HEAD',module).split()[2]
        assert git('rev-parse','HEAD',cwd=QMK/module)==expected, module+' pin mismatch'
    target=ROOT/'dist/vibe-think-light-corresponding-source.tar.gz'
    target.parent.mkdir(exist_ok=True)
    with tarfile.open(target,'w:gz') as archive:
        def add(path, name):
            info=archive.gettarinfo(str(path),name)
            info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
            if info.isfile():
                with path.open('rb') as stream:archive.addfile(info,stream)
            else:archive.addfile(info)
        for path in tracked(ROOT):
            add(path,'vibe-think-light-source/project/'+str(path.relative_to(ROOT)))
        for base in (QMK, *(QMK/module for module in MODULES)):
            for path in tracked(base):add(path,'vibe-think-light-source/qmk/'+str(path.relative_to(QMK)))
        for name in ('keymap.c','keyboard_light.c','keyboard_light.h','rules.mk','config.h'):
            add(ROOT/'Firmware'/name,'vibe-think-light-source/qmk/keyboards/gray_studio/think65v3/keymaps/keyboard_light/'+name)
        build='''Corresponding source for Vibe Think Light (Think6.5 V3 only).
project/ contains the Mac application, Codex hook, firmware overlay and tests.
qmk/ contains pinned upstream QMK plus ChibiOS, ChibiOS-Contrib, printf and LUFA.
All original license files and copyright notices are retained.

Apple Silicon macOS with Xcode Command Line Tools, Python 3, Git, dfu-util:
  cd project
  ./build.sh
  ./test.sh
  ./Firmware/setup.sh
  QMK_HOME="$PWD/../qmk" ./Firmware/build-firmware.sh

Setup fetches compiler/Python dependencies and a QMK checkout; the last command
builds the bundled corresponding QMK source instead. No command flashes a device.
See project/Firmware/README.md for manual dependency paths and flashing steps.
'''
        for name,content in [('BUILD.txt',build),('qmk/version.txt',PIN+'\n')]:
            data=content.encode();info=tarfile.TarInfo('vibe-think-light-source/'+name);info.size=len(data);info.mode=0o644
            archive.addfile(info,io.BytesIO(data))
    print(target.name, target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest())

if __name__=='__main__':main()
