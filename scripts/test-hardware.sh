#!/bin/zsh
set -eu
cd -- "${0:A:h:h}"
if [[ "${1:-}" != '--allow-light-changes' ]]; then
    print -u2 'Temporarily changes one connected keyboard; no flash or EEPROM save. Run with --allow-light-changes.'
    exit 2
fi
kbl_test_dir=$(mktemp -d)
trap 'rm -rf -- "$kbl_test_dir"' EXIT
xcrun swiftc Sources/Protocol.swift Sources/HIDTransport.swift Tests/hardware_test.swift -framework AppKit -framework IOKit -o "$kbl_test_dir/hardware-test"
"$kbl_test_dir/hardware-test"
