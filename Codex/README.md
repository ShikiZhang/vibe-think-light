# Codex 灯光通知

这是可选集成，单独调灯不需要安装它。需要本机可执行的 Keyboard Light、支持的键盘（Think6.5 V3 KLT1 v1.2 或 Apollo80 R2 Vial），以及支持 lifecycle hooks 的 Codex 版本。

程序根据设备自动选择通知实现，hook 命令保持相同。Apollo80 由短时后台进程执行，CLI 在 hook 的 2.5 秒超时前返回；日常灯光关闭时跳过提醒。Think6.5 继续由固件播放。连接多把支持的键盘时，在配置中设置 `device`，避免提醒错误的设备；拔插后需重新取得 ID。

## 安装与启用

```sh
# 默认调用 ~/Applications/Keyboard Light.app 中的可执行文件
python3 Codex/install.py

# 或指定 app / Codex home；路径可以包含空格
python3 Codex/install.py --app '/absolute/path/Keyboard Light.app/Contents/MacOS/KeyboardLight' --codex-home "$HOME/.codex"
```

安装器做以下修改，重复运行不会叠加自己的 hook：

- `hooks/vibe-think-light-hook.py`：复制通知处理脚本。
- `hooks.json`：合并 5 个事件定义，保留其他定义及同组中的其他命令。
- `AGENTS.md`：追加专属注释区块，指导模型在普通文本问题/物理操作请求前发出黄灯。
- `keyboard-light.json`：仅不存在时创建默认设置，包含实际 app 可执行文件路径。
- 修改的已有文件首次备份为 `*.vibe-think-light.bak`。不修改 `config.toml` 或 hook 信任记录。

根据 [OpenAI 官方 hooks 文档](https://learn.chatgpt.com/docs/hooks)，非托管 hooks 要先审阅并信任。在支持该功能的 Codex CLI 中输入 `/hooks`，查看命令后信任新增定义。更改 hook 定义后可能需要重新信任。桌面端首次配置后请 **Cmd+Q 完全退出再打开**；项目实测中，仅新建一轮对话不足以让旧进程加载新 hooks。

如果 `config.toml` 中已经设置 `[features] hooks = false`，请在现有 `[features]` 段内改为 `hooks = true`，不要重复创建该段。组织策略关闭 hooks 时，此集成无法绕过策略。

## 参数热更新

编辑 `${CODEX_HOME:-$HOME/.codex}/keyboard-light.json`：

```json
{
  "enabled": true,
  "waiting": {
    "color": "#FFFF00", "pattern": "blink", "seconds": 5,
    "brightness": 100, "period": 1.2
  },
  "complete": {
    "color": "#00FF00", "pattern": "breathe", "seconds": 5,
    "brightness": 100, "period": 1
  }
}
```

安装器会额外写入 `app`，指向实际可执行文件；请保留该字段，或让程序安装在默认路径。也可以通过 `KEYBOARD_LIGHT_APP` 提供默认路径。可选 `device` 指定某一把 V3，但 ID 可能在拔插后改变。

设置每次事件读取，无需重启/重刷。`enabled: false` 暂停提醒。常亮样式需删掉 `period`；旧固件不支持周期时也需删掉它。GUI 手动预设不会自动更新这个 JSON。

## 事件规则

| 事件 | 行为 |
| --- | --- |
| `PreToolUse` 调用 `request_user_input` / `_async` | 黄色待交互 |
| `PermissionRequest` | 黄色待确认；只通知，不影响审批决定 |
| `PostToolUse` | 清理已完成的同步等待；异步提问立即返回时仍保持等待 |
| `UserPromptSubmit` | 清理等待状态 |
| `Stop` | 一轮回复完成后绿色提醒；本轮仍待交互时不发绿色 |
| 模型执行脚本 `--waiting` | 普通文字提问或实体 Boot 操作需要回复时，标记等待并黄灯 |

`Stop` 代表一轮回复结束，并不自动理解整个多轮任务目标是否完成。跨任务中，刚发出的黄灯在其通知时长内优先于绿色；完成事件按 turn 去重。当前没有自动“失败”“开始工作”分类。

脚本通过 argv 调用本地 CLI，不执行对话文本。锁超时约 0.4 秒，USB 子进程超时 2.5 秒，hook 超时 4 秒；断连或配置错误不阻塞 Codex，也不会生成批准/拒绝决定。

## 验证

1. 先手动运行 README 中的绿色/黄色 `notify` 命令，确认 USB、固件与灯光。
2. 运行 `python3 Codex/test_hook.py`，这是模拟事件单元测试，不等于真实 Codex 已触发。
3. 信任并重启后，在 Codex 发“你好，请只回复一句话”。回复结束应出现 5 秒绿色呼吸。
4. 请 Codex 发起一个需要实际回答的结构化问题；应出现 5 秒黄色闪烁，周期 1.2 秒。回复前不应该被同一轮完成绿灯覆盖。
5. 查看 `~/Library/Caches/KeyboardLight/codex-events.jsonl`。真实事件应有 `event: Stop` / `PreToolUse` / `PermissionRequest`、`action` 和 `exit: 0`。没有记录通常说明 hook 没执行；`exit != 0` 检查 app 路径、键盘连接和参数。

日志只记录时间、事件名、哈希后的任务 ID、动作、退出码，不记录聊天内容；超过约 100 KB 轮转一次。状态文件只保留去重和等待元数据。日志存在也不能代替肉眼确认实际颜色/节奏。

## 卸载

```sh
python3 Codex/install.py --uninstall
```

若安装时用了其他 home，卸载时传相同 `--codex-home`。只移除本项目脚本、对应 hook 条目和 AGENTS 区块；保留其他 hooks、用户设置、备份及日志，不修改已安装 Mac app 或键盘固件。若曾安装过其他名称的旧版通知脚本，请自行核对是否同时启用，以免重复提醒。
