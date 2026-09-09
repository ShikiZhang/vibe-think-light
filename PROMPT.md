# 让代码助手复现和测试 Vibe Think Light

将下面的 Prompt 复制给 Codex 或其他能读取仓库、执行终端命令的助手。默认只进行软件测试；实体键盘测试和安装/刷机属于不同步骤，必须明确选择。不要把仓库以前的验证记录当作本次实测。

## 可直接复制的 Prompt

```text
你正在检查 vibe-think-light：Think6.5 V3 专用的 macOS 菜单栏灯光程序、CLI、QMK 固件和可选 Codex hooks。
请读取 README.md、Firmware/README.md、Codex/README.md、PROTOCOL.md 和本文件，然后按下面要求完成复现和测试。

本次模式：软件测试（默认）。
目标：验证新使用者从这个 checkout 构建并运行的流程，报告真实证据；修复阻碍复现的问题。

1. 识别操作系统、架构、Swift/Clang/Python 版本和 git 状态。保留现有未提交改动。
2. 运行 ./test.sh，记录退出码及每组 PASS/失败。它包含固件 UBSan、Swift 协议、hook、安装器、Mac 构建和 CLI 参数检查。
3. 检查 dist/Keyboard Light.app 的 Info.plist、架构及 ad-hoc 签名。运行 ./keyboardlight --help 和 effects；核对 42 个稳定效果 ID、7 种通知样式。
4. 检查设备发现和发送路径都匹配 Think6.5 V3 VID 0x4753 / PID 0x4003 及 Raw HID usage 0xFF60:0x62；不得打开普通键盘输入接口。
5. 检查全部代码和文档没有依赖作者的绝对路径、内部域名、私人备份、真实聊天日志或凭据。工具链和依赖必须来自锁定的官方来源。
6. 固件构建可在具备依赖时运行 Firmware/setup.sh 和 Firmware/build-firmware.sh；它们不刷机。记录 QMK 提交、GCC 14.2.1、产物大小和 SHA-256。若无法下载/无工具链，说明阻碍，不得把 C stub 测试说成完整 QMK 编译。
7. 不自动安装真实 Codex hooks，不改用户 config.toml、信任记录、EEPROM、键位或固件；不进入 Boot。安装器验证只能使用临时目录。不要发送实际灯光命令，除非本次模式明确允许。
8. 给出最终报告：代码改动、执行命令、PASS/FAIL/SKIP、证据、未验证平台，以及下一步需要的实体操作。任何未运行的检查标为 SKIP，不能推测通过。

功能和关键不变量见本文件后半部分，请逐项对照实现。若需要用户执行物理操作，清楚说明到哪一步再等待，不要提前假设已完成。
```

## 实现功能与代码入口

| 功能 | 入口与关键细节 |
| --- | --- |
| 菜单栏和控制窗口 | `Sources/App.swift`，SwiftUI + AppKit，首开 GET，每 2 秒同步，不用初始 UI 值 SET 键盘 |
| 临时通知界面 | `Sources/NotificationPanel.swift`，7 样式、独立 HSV/亮度/时长/周期；本机 AppStorage 预设 |
| 命令行 | `Sources/main.swift`，参数先验证再访问 USB；设备命令 JSON，effects 为 TSV；失败非零退出 |
| 通信 | `Sources/HIDTransport.swift`，只开 V3 专用 Raw HID，32 字节、无报告 ID 前缀；匹配 magic/命令/序号；ACK 等待上限约 1.2 秒 |
| 协议 | `Sources/Protocol.swift` + `PROTOCOL.md`，稳定 ID、不随 QMK 编译枚举偏移；mask 表示支持能力；旧通知 mask=0 回退为前三种 |
| 固件状态机 | `Firmware/keyboard_light.c`，保存完整日常 RGBLight config；所有通知恢复由键盘端计时执行 |
| Mac 键位 | `Firmware/keymap.c`，两层 LAYOUT_all，两个 Enter 槽均 KC_ENT；Fn=MO(1)，Fn+右上反引号为 Boot |
| Codex 事件 | `Codex/keyboard-light-hook.py`，等待/完成去重、异步等待保留、跨任务黄灯优先、有限锁等待、异常不阻塞 |
| 安装与卸载 | `Codex/install.py`，合并自身定义，保留其他 hook/设置，幂等，可选 CODEX_HOME；不自动信任 |

## 不变量与验收要点

1. **仅 Think6.5 V3。** VID/PID 和专用 usage 同时过滤；不能宣传支持初代/V2/其他 QMK 键盘。
2. **日常效果一致。** 42 个 ID 0–41，原生 QMK RGBLight 算法不做宿主端重绘。原生呼吸仍控制自身亮度，通知呼吸单独实现。
3. **读取不写入。** 打开窗口、GET、轮询都不覆盖设备；SET 只改 RAM；SAVE 是明确的 EEPROM 操作；通知时 SAVE 返回错误。
4. **可靠恢复。** 通知 replacement 保留最初 baseline；超时/CANCEL/手动灯光键恢复；SET 应用新 baseline。关灯状态、速度和 Caps Lock 指示层也应正确处理。恢复的是设置，不要求动画相位连续。
5. **计时独立。** 总时长 1–60000 ms；动态周期 500–10000 ms，0 表示样式默认；solid 拒绝非零周期。毫秒计时器回绕也应恢复。
6. **亮度限制。** API/CLI 100% 按 maxBrightness=150 换算。绿色和黄色配置均 full saturation；不要将板级亮度上限改成 255。
7. **参数安全。** 非有限数字、超范围值、未知选项/效果、重复参数、坏报文均失败；不发送无效 USB 请求。不执行事件携带的 prompt 或工具正文。
8. **提醒不决定审批。** hooks 只通知，输出 `{}`，出错不阻塞工作。异步提问 PostToolUse 不代表用户已回答；Stop 不应覆盖本轮待确认黄灯。Stop 是一轮回复结束，不是多轮目标完成判定。
9. **默认预设。** waiting=#FFFF00/double/100%/5s/1s；complete=#00FF00/breathe/100%/3s/1s。GUI 预设与 hook 配置独立。
10. **编译兼容。** 固定 QMK 和 GCC 14.2.1；不要升级到此前在该板观察到灯光异常的 GCC 15。不能仅凭编译通过断言波形正确。

## 可选模式：实体 USB 测试

在 Prompt 开头补充：

```text
本次允许对一把已刷本项目固件的 Think6.5 V3 进行短暂灯光测试；不允许刷机或写 EEPROM。
先读取并记录 baseline。运行 ./scripts/test-hardware.sh --allow-light-changes。
确认 SET/GET 回读、提醒期间返回日常 baseline、超时恢复，并在 finally/defer 中恢复原设置。
在没有其他通知干扰时，逐一验证 7 种样式和 6 种自定义周期；与用户核对真实颜色和节奏。
普通 set/notify 的成功 ACK 不代表灯珠肉眼效果已验证。
如果键盘断开、多设备无法确定、当前通知未结束，停止硬件部分并解释原因。
```

手动最小验收：绿色呼吸持续 3s/周期 1s；黄色双闪持续 5s/周期 1s；二者到期均恢复。测 Caps Lock 开/关、日常关灯、连续替换提醒和 Fn 调灯取消。每次只测一项，避免互相覆盖；不要调用 SAVE。软件脚本无法确认用户实际看到的颜色，应在报告中分开记录 USB 证据与肉眼确认。

## 可选模式：真实 Codex 生命周期测试

```text
本次允许按 Codex/README.md 安装本项目 hooks，保留已有配置，并帮助我完成信任审阅。
你不能自行写入 hook 信任哈希或绕过信任。安装完成后告诉我何时完全退出/重启 Codex。
重启后分别验证一个真实 Stop 和一个真实需要交互的事件；核对事件日志 exit=0、去重和灯光。
模拟 stdin 或 mock 测试只证明脚本逻辑，不算真实生命周期已触发。
普通文本问题应按安装后的 AGENTS 说明调用 --waiting；结构化问题已有 hook 时不手动重复。
```

## 可选模式：固件刷机

```text
本次明确需要给实体 Think6.5 V3 刷本项目固件。先核对键盘型号、keymap、工具链和构建哈希。
构建完成、固件在 QMK Toolbox 中选择正确、旧固件恢复来源已确认后，再告诉我进入 Boot。
等我回复并实际检测到 DFU 设备后才刷入。刷完核对打字、Enter/Fn、GET 能力和真实灯效。
不要把 Boot 作为普通调灯步骤，也不要因为没有键盘而伪造刷机结果。
```

## 报告模板

```text
环境：OS / 架构 / Swift / Clang / Python /（可选）GCC / QMK commit
软件测试：PASS/FAIL + 命令和实际输出摘要
Mac app：构建、签名、架构；GUI 是否实际打开验证
固件编译：PASS/FAIL/SKIP；文件大小、SHA-256、依赖来源
实体 USB：PASS/FAIL/SKIP；原始状态是否恢复；是否写过 EEPROM
肉眼灯光：用户确认 / 未确认（颜色、持续时间、周期）
真实 Codex hooks：PASS/FAIL/SKIP；事件来源、退出码、是否重启并信任
隐私与发布：已检查范围，不包含用户路径/日志/凭据
改动与剩余问题：具体文件和原因
```
