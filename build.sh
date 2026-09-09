#!/bin/zsh
set -eu
cd -- "${0:A:h}"
kbl_arch="${ARCH:-$(uname -m)}"
case "$kbl_arch" in arm64|x86_64) ;; *) print -u2 'Unsupported architecture'; exit 1;; esac
kbl_app='dist/Keyboard Light.app'
mkdir -p "$kbl_app/Contents/MacOS"
cp Resources/Info.plist "$kbl_app/Contents/Info.plist"
xcrun swiftc -O -target "${kbl_arch}-apple-macosx13.0" Sources/Protocol.swift Sources/HIDTransport.swift Sources/NotificationPanel.swift Sources/App.swift Sources/main.swift -framework AppKit -framework SwiftUI -framework IOKit -o "$kbl_app/Contents/MacOS/KeyboardLight"
/usr/bin/plutil -lint "$kbl_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$kbl_app"
print "Built $kbl_app ($kbl_arch, local ad-hoc signature)"
