# License and upstream provenance

Original Vibe Think Light source (Mac application, CLI, hook scripts, tests,
documentation and firmware overlay) is licensed under **GPL-2.0-or-later**.
Copyright (c) 2026 Vibe Think Light contributors. The complete GNU GPL version 2
text is in `LICENSE`; original code may be used under that version or any later
version. Existing per-file notices remain authoritative.

The compiled keyboard firmware combines this overlay with upstream sources
whose own licensing terms remain in effect. In particular, the Think6.5 V3
board implementation declares `GPL-2.0` (version 2 only), so distributing that
combined firmware uses GPLv2-compatible terms, not a blanket relicensing of
all upstream files to later GPL versions.

| Dependency | Exact source | License information |
| --- | --- | --- |
| QMK Firmware | https://github.com/qmk/qmk_firmware/tree/08c662f286ddfd12a985f57b584b02eca5af0ae6 | Root `LICENSE` and individual source notices; GPLv2 |
| Think6.5 V3 board | `keyboards/gray_studio/think65v3` in that commit | Copyright 2023 Yizhen Liu (@edwardslau); board C file SPDX GPL-2.0 |
| ChibiOS | https://github.com/qmk/ChibiOS/tree/6170ddf92d55be54c89b708d1882eea229edeb2c | Preserve `license.txt` and individual component notices/exceptions |
| ChibiOS-Contrib | https://github.com/qmk/ChibiOS-Contrib/tree/5a9ad82b6ba4f649cdb800e8c2bbc9be2d3ce767 | Preserve bundled and per-file notices |
| printf | https://github.com/qmk/printf/tree/c2e3b4e10d281e7f0f694d3ecbd9f320977288cc | MIT; retain upstream LICENSE |
| LUFA | https://github.com/qmk/lufa/tree/549b97320d515bfca2f95c145a67bd13be968faa | Retain LUFA's license and per-file notices |

The source repository contains our overlay rather than a vendored copy of all
QMK. `Firmware/setup.sh` fetches the pinned upstream sources and Git-recorded
submodule revisions. This repository publishes source code; users build the
application and firmware locally. No original author notices are removed.

Arm GNU Toolchain 14.2.Rel1 is a separately downloaded build dependency from
Arm's official distribution, verified by SHA-256. Python/QMK build tools and
Apple SDK/frameworks are build/runtime dependencies rather than source code
copied into this repository. Their own terms apply. AppKit, SwiftUI and IOKit
are system frameworks; this project does not redistribute the macOS SDK.

Think6.5, GrayStudio, QMK and Codex are names of their respective projects or
owners; this is an independent project.
