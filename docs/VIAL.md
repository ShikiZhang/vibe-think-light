# Apollo80 R2 Vial 支持

## 设备和能力

- USB VID/PID：`0x4753:0x3080`；Raw HID usage：`0xFF60:0x61`。
- 已验证固件：Vial 协议 6、VIA 协议 9；UID 字节 `d0 75 79 bf 01 05 ac d2`。
- 从设备读取并解压的 Vial definition 声明 `lighting: qmk_rgblight`，名称 `apollo80_r2`。
- 未检测到有效 VialRGB 能力，因此使用传统 RGBLight 协议，不发送逐灯 RGB Matrix 指令。
- 只适配这一设备配置；同 VID/PID 但协议或 UID 不匹配时拒绝写入。不自动刷固件或修改键位。

参考：[Vial 灯光文档](https://get.vial.today/docs/lighting.html)、[Vial QMK via.c](https://github.com/vial-kb/vial-qmk/blob/vial/quantum/via.c)、[RGBLight 实现](https://github.com/vial-kb/vial-qmk/blob/vial/quantum/rgblight/rgblight.c)。

## 通信

每条请求/应答为 32 字节，不含报告 ID 前缀。传统灯光 GET `0x08`、SET `0x07` 的第二字节是字段 ID：亮度 `0x80`、效果 `0x81`、速度 `0x82`、HSV 中的 HS `0x83`。保存 `0x09` 仅用于用户显式调用 `save`。所有动画和恢复使用 RAM 操作，不写 EEPROM。

连接后读取真实参数。效果 0 表示关闭、1 表示常亮；其他效果保留其原始编号，不套用 KLT1 的完整效果表。`status` 的 `nativeEffect` 保留原始编号，`effect: 255` 表示未映射的原有灯效。`backend` 为 `vial`，`canReloadSaved` 为 `false`。`ledCount: 0` 表示协议无法查询数量，界面显示一块颜色示意。

程序将普通设置/通知亮度限制在 150/255，这是保守的软件上限，不能视为通过协议发现的 PCB 上限。恢复使用通知前的原始亮度。原生灯光效果可能忽略颜色/亮度设置，所以完整恢复先进入常亮、设置 HSV/速度，再恢复原始效果。关闭状态下第一次设置效果可能只开启旧效果，第二次设置才切换到常亮。

协议没有读取 EEPROM 灯光设置的命令，`reset` 返回明确错误，界面禁用“恢复已保存”。`effects` 仍列出 KLT1 的完整灯效目录，实际可选效果以设备 `effectMask` 为准；Apollo80 只接受 `solid` 或保留原有灯效。

## 通知生命周期

1. `HIDTransport` 按设备路由；Think6.5 继续调用 `KLTTransport`，数据包和固件不变。
2. Apollo80 的每次操作取得该 USB 连接 ID 对应的文件锁，再读取真实灯光和通知日志。
3. **Vial 日常开关关闭时不写灯光、不启动后台进程，直接返回未在通知的状态。** 亮度为 0 与开关关闭不同。Think6.5 不应用这一规则。
4. 第一条通知先把完整可读状态（效果、HSV、速度）写入日志，再写通知首帧，启动同一可执行文件的内部 `--vial-worker` 模式。CLI 立即返回，子进程标准流与父进程分离。
5. 工作进程约每 40 ms 加上 USB 往返时间更新一次。闪烁、呼吸、双闪、心跳、彩虹和慢闪由电脑计算，周期与总时长独立。
6. 后续通知保留最初 baseline，替换 generation；旧工作进程发现 generation 不匹配就退出。
7. 到期或 `restore` 恢复 baseline；`set` 先结束通知，再应用新的日常设置。通知期间拒绝 `save`。

Vial 的通知不是实时硬件动画，节奏精度受 macOS 调度和 USB 延迟影响。内置动画恢复后重新开始相位。没有固件级 Caps Lock 指示层覆盖控制，其他固件指示层可能影响肉眼颜色。

## 并发与异常

状态放在 `~/Library/Caches/KeyboardLight/vial/<USB连接ID>.json`，锁为同名 `.lock`。GUI、CLI 和工作进程共用锁，写日志使用原子替换，锁文件描述符不传给子进程。一个进程的旧通知不能清除另一个进程的新通知。

- GUI/CLI 正常退出：已启动的工作进程继续运行，结束后自行退出；无需网络服务或 GUI 常驻。
- 电脑休眠：动画暂停；唤醒后按原到期时间恢复，不重新播放整段通知。
- USB 拔出：工作进程停止；重连后是新的连接 ID，重新读取设备，不将旧通知恢复到新设备。拔插不是持续通知承诺。
- 工作进程异常退出：日志保留；下次访问同一连接时检测 PID/到期状态并尝试恢复。完全没有后续访问时不能保证自动恢复。
- 部分 USB 写入失败：日志保留待恢复标记；尽力立即恢复，失败时下次访问再恢复。
- Fn/Vial 外部改灯：检测到状态与上一帧不同就结束通知，保留外部的新状态。两个程序同时持续写灯无法可靠协调，应避免并行使用。
- 多把支持的键盘：CLI 要求 `--device ID`，界面提供选择；仅连接一把时自动选择。ID 拔插后会变，hook 的固定 `device` 需更新。

## 验证

`./test.sh` 包含注入模拟灯光接口的通知状态机测试：连续替换、旧工作进程退出、取消、原始效果/速度恢复、进程启动失败、部分 USB 失败、进程中断恢复、外部手动改灯、关灯跳过、动画边界及 RGBLight 指令顺序。

`python3 Tests/vial_hardware_test.py --allow-light-changes` 使用实体 Apollo80 检查 CLI 返回时限、后台独立恢复（在任何 `status` 前检查日志已结束）、替换、取消、杀死测试工作进程后的恢复和关灯跳过。脚本最后恢复原始状态；不保存 EEPROM、不刷机、不改键。节奏和颜色的肉眼确认单独进行。
