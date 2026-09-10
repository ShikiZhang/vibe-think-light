// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import AppKit

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func runCLI(_ args: [String]) throws {
    let help = """
    Keyboard Light — 本地 USB 键盘灯光控制
    keyboardlight list
    keyboardlight effects    查看全部内置灯效及命令名
    keyboardlight status [--device ID]
    keyboardlight set [--color '#8B5CF6'] [--brightness 0..100] [--effect solid|breathe|rainbow|swirl|snake|knight|gradient] [--power on|off]
    keyboardlight notify [--color '#34D399'] [--brightness 0..100] [--seconds 0.001..60] [--pattern solid|blink|breathe|double|heartbeat|rainbow|slow-blink] [--period 0.5..10]
    keyboardlight restore     结束临时提醒，恢复原来的灯光
    keyboardlight save        将当前日常灯光保存到键盘
    keyboardlight reset      恢复上次保存的灯光
    所有设备指令都支持 --device ID；返回 JSON。set 不自动写入 EEPROM。
    """
    guard let command = args.first, command != "--help", command != "help" else { print(help); return }
    let allowed: [String: Set<String>] = ["list": [], "effects": [], "status": ["device"], "restore": ["device"], "save": ["device"], "reset": ["device"],
        "set": ["device", "color", "brightness", "effect", "power"], "notify": ["device", "color", "brightness", "seconds", "pattern", "period"]]
    guard let options = allowed[command] else { throw LightError.message("未知命令：\(command)。使用 --help 查看用法。") }
    var values: [String: String] = [:]
    var index = 1
    while index < args.count {
        let key = args[index]
        guard key.hasPrefix("--"), options.contains(String(key.dropFirst(2))), index + 1 < args.count else { throw LightError.message("无效参数：\(key)") }
        let name = String(key.dropFirst(2))
        guard values[name] == nil else { throw LightError.message("重复参数：\(key)") }
        values[name] = args[index + 1]; index += 2
    }
    // Validate all user input before opening a USB interface.
    let color = try values["color"].map { try LightProtocol.color($0) }
    var brightness: Double?
    if let text = values["brightness"] {
        guard let value = Double(text), value.isFinite, (0...100).contains(value) else { throw LightError.message("亮度必须在 0 到 100 之间。") }
        brightness = value
    }
    var effect: Int?
    if let text = values["effect"] {
        guard let value = LightProtocol.effects.first(where: { $0.2 == text })?.0 else { throw LightError.message("未知灯效：\(text)") }
        effect = value
    }
    if let power = values["power"], power != "on" && power != "off" { throw LightError.message("--power 只能是 on 或 off。") }
    var seconds = 5.0
    if let text = values["seconds"] {
        guard let value = Double(text), value.isFinite, (0.001...60).contains(value) else { throw LightError.message("提醒时长必须在 0.001 到 60 秒之间。") }
        seconds = value
    }
    let patterns = Dictionary(uniqueKeysWithValues: LightProtocol.notifications.map { ($0.2, $0.0) })
    guard let pattern = patterns[values["pattern"] ?? "blink"] else { throw LightError.message("未知提醒模式。") }
    var period: Double?
    if let text = values["period"] {
        guard let value = Double(text), value.isFinite, (0.5...10).contains(value), pattern != 0 else { throw LightError.message("--period 仅用于动态提醒样式，范围 0.5 到 10 秒。") }
        period = value
    }
    if command == "effects" { for (id, title, name) in LightProtocol.effects { print("\(id)\t\(name)\t\(title)") }; return }
    let transport = HIDTransport(), device = values["device"]
    if command == "list" { try printJSON(transport.devices()); return }
    func send(_ command: UInt8, _ state: LightState = LightState()) throws -> LightState {
        try transport.transact(LightProtocol.request(command, state: state, seconds: seconds, pattern: pattern, sequence: UInt8.random(in: 1...254), period: period), deviceID: device)
    }
    if command == "set" || command == "notify" {
        var state = try send(1)
        if period != nil && !state.adjustableNotificationTiming { throw LightError.message("键盘需要更新动态调速固件后才能调整提醒周期。") }
        if command == "notify", state.notificationMask & (1 << pattern) == 0 { throw LightError.message("键盘固件暂不支持这个提醒样式，请更新提醒扩展固件。") }
        if let color { state = LightProtocol.applying(color, to: state); state.enabled = true }
        if let brightness { state.brightness = Int((brightness * Double(state.maxBrightness) / 100).rounded()) }
        if let effect { state.effect = effect }
        if let power = values["power"] { state.enabled = power == "on" }
        try printJSON(send(command == "set" ? 2 : 3, state))
    } else {
        let codes: [String: UInt8] = ["status": 1, "restore": 4, "save": 5, "reset": 6]
        try printJSON(send(codes[command]!))
    }
}

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--vial-worker" {
    VialHost.runWorker(deviceID: CommandLine.arguments[2], generation: CommandLine.arguments[3])
} else if CommandLine.arguments.contains("--cli") {
    do { try runCLI(Array(CommandLine.arguments.dropFirst(2))) }
    catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
} else {
    let application = NSApplication.shared
    let delegate = LightAppDelegate(demo: Bundle.main.object(forInfoDictionaryKey: "KBLDemoMode") as? Bool == true)
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
