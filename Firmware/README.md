# Think6.5 V3 固件

仅用于 `gray_studio/think65v3`（STM32F072，USB VID 4753 / PID 4003）。不适用于初代、V2 或任何其他键盘。Mac 程序只控制灯光，固件中的 Mac 键位来自本目录 `keymap.c`；刷入会替换原先键位，不能把旧 VIA/Vial 的动态配置视为仍然可用。

## 从源码构建（Apple Silicon macOS）

需要 Xcode Command Line Tools、Git、Python 3 和网络。安装 [Homebrew](https://brew.sh/) 后可以安装 QMK 使用的工具：

```sh
brew install dfu-util
# 在仓库根目录执行
./Firmware/setup.sh
./Firmware/build-firmware.sh
```

`setup.sh` 将依赖放在可删除的 `.deps/`，克隆官方 QMK 固定提交及本键盘用到的 ChibiOS、ChibiOS-Contrib、printf、LUFA 子模块，校验 Arm 工具链 SHA-256，创建独立 Python venv。它不触碰 USB。

输出：`dist/think65v3-keyboard-light.bin`。构建脚本打印 SHA-256，**不会刷机**。QMK/Python 包的传递依赖未逐一锁定，因此不承诺不同系统逐字节复现；QMK 源码、子模块提交和编译器版本被锁定。

关键依赖见 [dependencies.json](dependencies.json)：

- QMK `08c662f286ddfd12a985f57b584b02eca5af0ae6`
- QMK CLI `1.2.0`
- Arm GNU Toolchain `14.2.Rel1`，GCC `14.2.1`
- macOS arm64 工具链 SHA-256：`c7c78ffab9bebfce91d99d3c24da6bf4b81c01e16cf551eb2ff9f25b9e0a3818`

必须保留 GCC 14.2.1：这块板的 WS2812 使用 bitbang 驱动，实测 GCC 15.2 编译版本出现常白/灯效不动。版本检查会阻止误用，原生 QMK `rgblight.c` 未修改。

已有干净、固定版本依赖时，可以指定绝对路径：

```sh
QMK_HOME='/path/to/qmk' \
ARM_GCC_BIN='/path/to/arm-gnu-toolchain/bin' \
QMK_CLI='/path/to/venv/bin/qmk' \
./Firmware/build-firmware.sh
```

自动下载器只支持 Apple Silicon macOS；其他环境需自己提供对应平台 GCC 14.2.1 和依赖，目前未验证。构建会覆盖指定 QMK 工作树中的 `keymaps/keyboard_light` 目录里的 5 个本项目文件，请使用专用 checkout。

## 刷入（一次性物理操作）

1. 确认实体键盘是 **Think6.5 V3**。保留当前固件的可用备份/下载地址，并核对新 `keymap.c`；本程序不能从键盘导出完整旧固件。
2. 安装官方 [QMK Toolbox](https://github.com/qmk/qmk_toolbox/releases)，选择构建产物 `dist/think65v3-keyboard-light.bin`。关闭 Auto-Flash，以便先核对设备。
3. 让键盘进入 Boot：已刷本项目键位时，按 **Fn + 顶排最右侧的反引号键（` / ~）**。其他固件的 Boot 位置可能不同；可用 PCB Reset 按钮，或尝试拔线、按住 Esc 插回并等待 2 秒后松开（取决于原固件 Bootmagic 支持）。
4. Toolbox 应显示 STM32 DFU 设备（通常 `0483:DF11`）。确认目标后点击 Flash，等待完成，不要中途断线。
5. 刷完通常自动重新连接并恢复打字。仍停留在 DFU 时正常拔插一次。用 `./keyboardlight status` 核对 `ledCount: 6`、完整 effect mask 和 `adjustableNotificationTiming: true`。

Boot 期间固件程序不运行，不能打字/调灯。日常使用无需进入 Boot；改颜色、提醒时长、周期也不需要重新编译。

## 固件设计

`RAW_ENABLE = yes`，专属 usage 为 `0xFF60:0x62`。32 字节 KLT1 请求包含命令、序号和灯光参数，键盘返回确认与实际状态；见 [PROTOCOL.md](../PROTOCOL.md)。

日常灯效仍由 QMK 原生算法运行。提醒临时保存完整 RGBLight config（电源、模式、HSV、速度）；超时/取消恢复。连续通知不把上一条通知当作日常设置。按原生灯光键先取消提醒再执行按键动作；SET 会结束提醒并应用新的日常设置。通知不隐式写 EEPROM，SAVE 在提醒中被拒绝。

Caps Lock 白色指示层来自 V3 板级实现；提醒时暂时抑制，结束按当前 Caps Lock 状态恢复。UI/CLI 100% 亮度对应板级上限 150，并非将 PCB 限值改为 255。

## 分发对应源码

发布预编译 `.bin` 时，同时提供依赖源码、许可证和构建说明。完成 setup/build 后在根目录运行：

```sh
python3 scripts/package-source.py
```

得到 `dist/vibe-think-light-corresponding-source.tar.gz`，包含本项目源码、固定版本 QMK 和参与本次构建的子模块源码及许可证，排除 Git 历史、构建缓存和本机配置。可在解压后按 `BUILD.txt` 编译。工具链仍按锁定 URL 和哈希独立获取。不要只发布二进制而省略对应源码。
