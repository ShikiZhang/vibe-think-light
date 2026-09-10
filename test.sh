#!/bin/zsh
set -eu
cd -- "${0:A:h}"
kbl_test_dir=$(mktemp -d)
trap 'rm -rf -- "$kbl_test_dir"' EXIT
xcrun clang -Wall -Wextra -Werror -fsanitize=undefined -I Tests/stubs Firmware/keyboard_light.c Tests/firmware_test.c -o "$kbl_test_dir/firmware-test"
"$kbl_test_dir/firmware-test"
xcrun swiftc Sources/Protocol.swift Tests/protocol_test.swift -framework AppKit -o "$kbl_test_dir/protocol-test"
"$kbl_test_dir/protocol-test"
xcrun swiftc Sources/Protocol.swift Sources/HIDTransport.swift Sources/VialTransport.swift Sources/HostNotification.swift Tests/vial_test.swift -framework AppKit -framework IOKit -o "$kbl_test_dir/vial-test"
"$kbl_test_dir/vial-test"
python3 Codex/test_hook.py
python3 Codex/test_install.py
./build.sh
python3 Tests/cli_test.py
