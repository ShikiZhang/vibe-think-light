# Vibe Think Light

**让键盘灯光跟着你的工作状态变化。**

支持 Think6.5 V3（配套 QMK 固件）和 Apollo80 R2（已适配 Vial 固件）的 macOS 菜单栏程序。平时用窗口自由调灯；需要时由 CLI 或 Codex hooks 播放提醒，结束后自动恢复原来的灯效。日常灯效沿用键盘内置的 QMK RGBLight 算法。

A native macOS light controller for Think6.5 V3 (KLT1 firmware) and Apollo80 R2 (Vial RGBLight), with temporary notifications and optional Codex integration.

[下载源码并构建](#开始使用) · [固件与刷机](Firmware/README.md) · [Codex 联动](Codex/README.md) · [测试 Prompt](PROMPT.md) · [USB 协议](PROTOCOL.md)

## 能做什么

- **手动调灯**：开关、颜色、亮度；Think6.5 支持 42 种内置灯效及其速度/方向变体，Apollo80 支持常亮及保留当前灯效。没有通知事件时也能独立使用。
- **读取真实状态**：打开程序先读键盘，每 2 秒同步；不会用窗口的初始值覆盖键盘。
- **临时提醒**：常亮、闪烁、呼吸、双闪、心跳、彩虹、慢闪，共 7 种。颜色、亮度、总时长独立设置；6 种动画支持 0.5–10 秒周期。
- **自动恢复**：通知结束或取消后恢复日常设置；连续通知保留最初状态。Think6.5 按 Fn 灯光键先恢复再调灯；Apollo80 检测到外部调灯时结束通知并保留新设置。
- **命令行与 Codex**：任何本地脚本都可以调用 CLI。可选 hooks 在需要交互时黄灯闪烁，在一轮回复完成时绿灯呼吸。
- **本地通信**：通过 USB Raw HID 直接控制，不需要云服务、API key、HTTP 服务或常驻网络端口。CLI 无需 GUI 常驻。

## 支持范围

程序自动识别当前连接的设备，并选择不同的通知实现：

| 键盘 | 通知执行位置 | 固件要求 |
| --- | --- | --- |
| Think6.5 V3 | 键盘固件，自行计时恢复 | 本项目 KLT1 固件 |
| Apollo80 R2 | 电脑上的短时后台进程 | 已验证的 Vial 6 / VIA 9，RGBLight，VID `0x4753` / PID `0x3080` |

Apollo80 不用重新刷机，原有 Vial 改键功能保留。CLI 发起通知后立即返回，后台进程完成动画和恢复，GUI 不必常驻。**仅 Apollo80：日常灯光开关关闭时跳过提醒**，Think6.5 行为保持原样。普通 VIA/Vial 键盘不会自动视为兼容。

Apollo80 的日常灯效只开放“常亮”和“保留当前灯效”，其他效果请在 Vial 中选择；7 种通知动画由电脑生成。普通设置和通知亮度限制在 150/255（保守的软件上限），恢复使用通知前的原始值。协议不报告灯珠数量、Caps Lock 覆盖状态或效果列表，窗口仅显示一块颜色示意。“恢复已保存”不可用，因为该协议没有读取已保存灯光的指令；显式“保存到键盘”仍可用。

电脑休眠期间 Vial 动画暂停，过期通知在唤醒后恢复；拔插后按新连接读取，不把旧通知恢复到新设备。后台进程被强制结束时，下次访问同一连接会尝试恢复。通知中通过 Fn/Vial 调灯会停止通知并保留检测到的新状态；不要同时用多个程序持续调灯。详情见 [Vial 通信与恢复](docs/VIAL.md)。

以下是 Think6.5 V3 固件的具体要求：

| 项目 | 要求 / 范围 |
| --- | --- |
| 键盘 | **GrayStudio Think6.5 V3**，QMK `gray_studio/think65v3`，STM32F072 |
| 灯光 | 6 颗 WS2812，QMK RGBLight；100% 对应 PCB 上限 150/255 |
| 连接 | USB，VID `0x4753` / PID `0x4003`，灯光 usage `0xFF60:0x62` |
| Mac | 最低部署版本 macOS 13；本次验证为 Apple Silicon / macOS 26 / Swift 6.2.3 |
| Intel Mac | 构建脚本接受 `ARCH=x86_64`，尚未在 Intel 实机验证 |
| 固件 | 本项目的 KLT1 固件；普通 QMK / VIA / Vial 固件无法直接通信 |

**Think6.5 固件不能刷入初代、V2、Apollo80 或其他型号。** 本项目的 Think6.5 固件不提供 VIA/Vial 动态改键；附带的是固定 Mac 键位，修改键位需要编辑 `Firmware/keymap.c` 后重新编译。灯光调整和通知参数修改不需要反复刷机。

## 开始使用

本项目提供源码，请下载仓库后在自己的 Mac 上构建。可以点击 GitHub 的 **Code → Download ZIP** 并解压，也可以使用下面的 `git clone` 命令。ZIP 下载方式请先在终端进入解压后的仓库目录，再从 `./build.sh` 开始执行。

### 1. 构建 Mac 程序

先安装 [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/)（`xcode-select --install`），确保 `xcrun swiftc --version` 可用。纯 Mac 程序不需要 Homebrew、QMK 或 Python 第三方包。

```sh
git clone https://github.com/shikizhang/vibe-think-light.git
cd vibe-think-light
./build.sh
mkdir -p "$HOME/Applications"
ditto 'dist/Keyboard Light.app' "$HOME/Applications/Keyboard Light.app"
open "$HOME/Applications/Keyboard Light.app"
```

这是原生菜单栏小程序，应用名为 **Keyboard Light / 键盘灯光**。从顶部菜单栏图标打开控制窗口；关闭窗口不会退出菜单栏程序，菜单中可退出。构建脚本使用本地 ad-hoc 签名，没有 Apple 开发者公证。本项目以源码形式发布，按以上步骤在本机编译使用。

### 2. 给 Think6.5 V3 刷一次通信固件

Apollo80 R2 使用已适配的 Vial 固件时跳过此步骤。Think6.5 首次使用请按 [固件说明](Firmware/README.md) 构建并用 QMK Toolbox 刷入。已经刷过本项目 v1.2 固件的键盘可以直接跳过。

**仅在刷固件时进入 Boot。** 日常调灯时键盘应处于能正常打字的状态；刷机成功后通常自动退出 Boot。软件不会自动进入 Boot 或自动刷机。

### 3. 调整日常灯光

连接键盘后窗口显示当前灯光。选择效果、颜色和亮度即可立即生效。

- **保存到键盘**：明确写入 EEPROM，下次上电可保留。
- **恢复已保存设置**：读取上次保存值，不是恢复出厂设置。
- **临时提醒 / 恢复原灯光**：覆盖一段时间后自动回到日常设置，不写 EEPROM。
- 原生呼吸灯效自行控制亮度曲线，窗口会禁用该模式的日常亮度滑块；通知呼吸的亮度可单独设置。
- 窗口中的六块颜色是示意，不是灯珠逐帧动画预览。

## CLI 用法

仓库内的 `./keyboardlight` 默认调用 `dist/Keyboard Light.app`。离开仓库后也可以调用已安装的可执行文件：

```sh
"$HOME/Applications/Keyboard Light.app/Contents/MacOS/KeyboardLight" --cli status
```

```sh
./keyboardlight list
./keyboardlight status
./keyboardlight effects
./keyboardlight set --color '#8B5CF6' --brightness 60 --effect solid --power on

# 完成：高饱和绿色呼吸，100% 亮度，持续 5 秒，每周期 1 秒
./keyboardlight notify --color '#00FF00' --brightness 100 --pattern breathe --seconds 5 --period 1

# 待确认：高饱和黄色闪烁，100% 亮度，持续 5 秒，每周期 1.2 秒
./keyboardlight notify --color '#FFFF00' --brightness 100 --pattern blink --seconds 5 --period 1.2

./keyboardlight restore  # 取消临时提醒
./keyboardlight save     # 显式保存日常灯光
./keyboardlight reset    # 重新读取已保存灯光
```

设备命令返回 JSON，失败以非零状态退出。`effects` 输出制表符分隔的 ID / 命令名 / 中文名，`--help` 输出帮助。`list` 返回设备 ID；连接多把支持的键盘时给设备命令加 `--device ID`。ID 来自系统注册表，拔插后可能变化。

| 参数 | 范围 |
| --- | --- |
| `--color` | 六位十六进制 RGB，如 `'#FFFF00'`；请保留引号 |
| `--brightness` | 0–100，按 PCB 安全上限换算 |
| `--seconds` | 通知总时长 0.001–60 秒 |
| `--pattern` | `solid` / `blink` / `breathe` / `double` / `heartbeat` / `rainbow` / `slow-blink` |
| `--period` | 动画周期 0.5–10 秒；不传则沿用该样式默认周期；常亮不接受周期 |

周期和总时长是两个参数，例如 3 秒总时长、1 秒周期表示约 3 个完整周期。彩虹通知会循环色相。修改普通颜色保留当前灯效；`#000000` 会将亮度设为 0。`set` 本身只改 RAM，内置 Fn 灯光键保留 QMK 原本的保存行为。

## Codex 联动

安装程序后，在仓库运行：

```sh
python3 Codex/install.py
```

安装器合并 `~/.codex/hooks.json`，追加一个专属 `AGENTS.md` 区块，写入 hook 脚本，并在不存在时创建 `keyboard-light.json`。支持 `CODEX_HOME` 或 `--codex-home`。已有设置、其他 hooks、`notify` 配置和信任记录会保留；安装器不会自动批准 hook。

在支持 hooks 的 Codex CLI 中打开 `/hooks`，检查并信任新增定义；桌面端首次配置后**完全退出再打开**。如果显式禁用了 hooks，需要自己在配置中开启。安装过程、卸载、事件解释和实测方法见 [Codex/README.md](Codex/README.md)。

| 事件 | 默认提醒 |
| --- | --- |
| 需要交互 / 权限确认 | 黄色 `#FFFF00` 闪烁，100%，5 秒，周期 1.2 秒 |
| 一轮回复结束 | 绿色 `#00FF00` 呼吸，100%，5 秒，周期 1 秒 |

这些默认值可在 `keyboard-light.json` 随时修改，下次事件立即读取。GUI 的手动通知预设与 Codex 的配置互相独立。当前只自动区分“待交互”和“回复完成”；其他用途可以自己从脚本调用 CLI。

## 附带 Mac 键位

右侧 Fn 为 `MO(1)`，按住后临时进入第 1 层。

| 按法 | 功能 |
| --- | --- |
| 底排左侧 Ctrl / Option / Command | Mac 修饰键顺序 |
| Fn + `1`…`0`、`-`、`=` | F1…F12（标准 F 键，系统快捷功能取决于 macOS 设置） |
| Fn + Q / W | 灯光开关 / 下一个内置效果 |
| Fn + E / R | 色相增加 / 减少 |
| Fn + T / Y | 饱和度增加 / 减少 |
| Fn + U / I | 亮度增加 / 减少 |
| Fn + P | 静音 |
| Fn + `[` / `]` | 音量减 / 加 |
| Fn + N | NKRO 切换 |
| Fn + 顶排最右侧的反引号键（` / ~） | **进入 Boot，准备刷机** |

布局使用 `LAYOUT_all`，兼容位置中的两个 Enter 槽都映射为回车，避免回车错变成反斜杠。请先核对 [keymap.c](Firmware/keymap.c) 是否符合自己的实际配列。

## 测试和参与开发

```sh
./test.sh
```

包含 C 固件状态机 + UBSan、Swift 协议与 Vial 通知状态机、Python hook 和安装器、Mac 程序构建、CLI 参数验证。默认不刷机、不改实际灯光、不安装用户 hooks。

实体 USB 回归需单独选择：

```sh
./scripts/test-hardware.sh --allow-light-changes
```

它要求恰好连接一把兼容 Think6.5 键盘，会短暂调光并恢复；不会保存 EEPROM。Apollo80 实体回归使用 `python3 Tests/vial_hardware_test.py --allow-light-changes`，验证后台恢复、替换、取消、进程异常恢复和关灯跳过。硬件颜色和节奏仍需肉眼确认。把 [PROMPT.md](PROMPT.md) 交给 Codex 或其他代码助手，可以按同一验收流程复现。实际验证范围见 [测试记录](docs/VALIDATION.md)。

## 常见问题

**能打字，但程序没找到灯光接口？** Think6.5 需要 KLT1 固件；Apollo80 必须匹配已适配的 Vial 固件。其他型号暂不支持。不要为日常调灯进入 Boot；关闭可能占用 USB 的工具后重试。

**一直白色？** 先检查 Caps Lock：V3 原生大写指示层会覆盖普通灯色，通知期间会临时隐藏它。若刷完后任何灯效都不变化，核对是否误用了 GCC 15；本项目实测 GCC 14.2.1 正常、GCC 15.2 构建曾出现 WS2812 常白。详见固件说明。

**手动 CLI 能亮，Codex 没反应？** CLI 成功只证明 USB 链路；还需要确认 hooks 已信任、桌面进程已重启，并查看本地事件日志。详细步骤见 Codex 文档。

**提示需要动态调速固件？** `--period` 需要 v1.2 协议能力。升级到本项目当前固件；旧版应先去掉周期参数。

**退出程序后提醒能恢复吗？** Think6.5 的倒计时在键盘固件上运行；Apollo80 使用独立的短时后台进程。两者都允许 GUI/CLI 退出后继续播放，但 Apollo80 需要电脑保持运行；强制终止后台进程后须再次访问设备才能恢复。恢复内置动画时从新的动画相位开始。

## 项目结构与许可

```text
Sources/       SwiftUI/AppKit 菜单栏程序、CLI、IOKit USB 通信
Firmware/      Think6.5 V3 keymap、KLT1、依赖锁定和构建脚本
Codex/         可选事件 hook、可重复安装/卸载脚本、默认设置
Tests/         固件/协议/CLI/实体 USB 测试
PROTOCOL.md    32 字节协议与状态恢复语义
PROMPT.md      可直接交给代码助手执行的复现与验收说明
```

本项目自有源码使用 **GPL-2.0-or-later**，见 [LICENSE](LICENSE) 和 [第三方说明](THIRD_PARTY_NOTICES.md)。QMK 及其依赖保留各自许可证；包含 Think6.5 V3 板级代码的固件按 GPLv2 及相关依赖条款分发。本仓库包含项目全部自有源码；QMK 和编译依赖由脚本从固定的官方版本获取。不代表或隶属于 GrayStudio、QMK 或 OpenAI。
