#!/bin/zsh
# Downloads public build dependencies; never opens or flashes a keyboard.
set -eu
cd -- "${0:A:h:h}"
if [[ "$(uname -s)-$(uname -m)" != Darwin-arm64 ]]; then
    print -u2 'Automatic dependency setup supports Apple Silicon macOS. See Firmware/README.md for manual setup.'
    exit 1
fi
mkdir -p .deps
kbl_root="$PWD"
kbl_pin=$(python3 -c 'import json; print(json.load(open("Firmware/dependencies.json"))["qmk_commit"])')
if [[ ! -d .deps/qmk/.git ]]; then
    git init .deps/qmk
    git -C .deps/qmk remote add origin https://github.com/qmk/qmk_firmware.git
    git -C .deps/qmk fetch --depth 1 origin "$kbl_pin"
    git -C .deps/qmk checkout --detach FETCH_HEAD
fi
[[ "$(git -C .deps/qmk rev-parse HEAD)" == "$kbl_pin" ]] || { print -u2 'QMK commit differs from pin'; exit 1; }
git -C .deps/qmk submodule update --init --depth 1 lib/chibios lib/chibios-contrib lib/printf lib/lufa
kbl_archive="$kbl_root/.deps/arm-gcc14.tar.xz"
kbl_url=$(python3 -c 'import json; print(json.load(open("Firmware/dependencies.json"))["toolchain_url"])')
if [[ ! -f "$kbl_archive" ]]; then
    curl --fail --location --retry 3 "$kbl_url" -o "$kbl_archive.partial"
    mv "$kbl_archive.partial" "$kbl_archive"
fi
python3 - <<'PY'
import hashlib,json
from pathlib import Path
p=Path('.deps/arm-gcc14.tar.xz')
assert hashlib.sha256(p.read_bytes()).hexdigest() == json.load(open('Firmware/dependencies.json'))['toolchain_sha256'], 'Toolchain checksum mismatch; remove .deps/arm-gcc14.tar.xz and retry'
PY
if [[ ! -d .deps/arm-gnu-toolchain-14.2.rel1-darwin-arm64-arm-none-eabi ]]; then
    tar -xJf "$kbl_archive" -C .deps
fi
python3 -m venv .deps/venv
.deps/venv/bin/python -m pip install 'qmk==1.2.0' -r .deps/qmk/requirements.txt
print 'Dependencies ready. Run Firmware/build-firmware.sh; flashing is a separate manual action.'
