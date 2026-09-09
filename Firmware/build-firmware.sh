#!/bin/zsh
set -eu
cd -- "${0:A:h:h}"
kbl_root="$PWD"
kbl_qmk="${QMK_HOME:-$kbl_root/.deps/qmk}"
kbl_gcc="${ARM_GCC_BIN:-$kbl_root/.deps/arm-gnu-toolchain-14.2.rel1-darwin-arm64-arm-none-eabi/bin}"
kbl_cli="${QMK_CLI:-$kbl_root/.deps/venv/bin/qmk}"
kbl_pin=$(python3 -c 'import json; print(json.load(open("Firmware/dependencies.json"))["qmk_commit"])')
[[ -x "$kbl_cli" && -x "$kbl_gcc/arm-none-eabi-gcc" ]] || { print -u2 'Missing dependencies. Run Firmware/setup.sh or set QMK_HOME, ARM_GCC_BIN and QMK_CLI.'; exit 1; }
[[ "$("$kbl_gcc/arm-none-eabi-gcc" -dumpfullversion)" == '14.2.1' ]] || { print -u2 'Use GCC 14.2.1; GCC 15 produced broken WS2812 lighting on the tested PCB.'; exit 1; }
if [[ -d "$kbl_qmk/.git" ]]; then
    [[ "$(git -C "$kbl_qmk" rev-parse HEAD)" == "$kbl_pin" ]] || { print -u2 'QMK commit differs from dependencies.json'; exit 1; }
    [[ -z "$(git -C "$kbl_qmk" diff --name-only HEAD)" ]] || { print -u2 'Tracked QMK files changed; use a clean pinned checkout.'; exit 1; }
else
    [[ "$(cat "$kbl_qmk/version.txt")" == "$kbl_pin" ]] || { print -u2 'QMK snapshot version differs from pin'; exit 1; }
fi
kbl_keymap="$kbl_qmk/keyboards/gray_studio/think65v3/keymaps/keyboard_light"
mkdir -p "$kbl_keymap" "$kbl_root/dist"
for kbl_file in keymap.c keyboard_light.c keyboard_light.h rules.mk config.h; do
    cp "$kbl_root/Firmware/$kbl_file" "$kbl_keymap/$kbl_file"
done
PATH="${kbl_cli:h}:$kbl_gcc:$PATH" QMK_HOME="$kbl_qmk" "$kbl_cli" compile -j 1 -kb gray_studio/think65v3 -km keyboard_light
cp "$kbl_qmk/gray_studio_think65v3_keyboard_light.bin" "$kbl_root/dist/think65v3-keyboard-light.bin"
shasum -a 256 "$kbl_root/dist/think65v3-keyboard-light.bin"
print 'Built firmware only. No device was flashed.'
