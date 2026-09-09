// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import AppKit

enum LightError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

struct LightState: Codable, Equatable {
    var enabled = true
    var effect = 0
    var hue = 145
    var saturation = 210
    var brightness = 90
    var maxBrightness = 150
    var ledCount = 6
    var effectMask = (1 << 42) - 1
    var notifying = false
    var capsLock = false
    var remainingMS = 0
    var notificationMask = 127
    var adjustableNotificationTiming = false

    var percent: Double { maxBrightness > 0 ? Double(brightness) / Double(maxBrightness) * 100 : 0 }
    var color: NSColor {
        NSColor(calibratedHue: Double(hue) / 255, saturation: Double(saturation) / 255, brightness: 1, alpha: 1)
    }
}

enum LightProtocol {
    static let notifications: [(Int, String, String)] = [
        (0, "常亮", "solid"), (1, "闪烁", "blink"), (2, "呼吸", "breathe"),
        (3, "双闪", "double"), (4, "心跳", "heartbeat"), (5, "彩虹变色", "rainbow"), (6, "慢闪", "slow-blink")
    ]
    static let effects: [(Int, String, String)] = [
        (0, "常亮", "solid"),
        (1, "呼吸 · 速度 1", "breathe"),
        (2, "呼吸 · 速度 2", "breathe-2"),
        (3, "呼吸 · 速度 3", "breathe-3"),
        (4, "呼吸 · 速度 4", "breathe-4"),
        (5, "彩虹渐变 · 速度 1", "rainbow"),
        (6, "彩虹渐变 · 速度 2", "rainbow-2"),
        (7, "彩虹渐变 · 速度 3", "rainbow-3"),
        (8, "彩虹流动 · 方向 1 / 速度 1", "swirl"),
        (9, "彩虹流动 · 方向 2 / 速度 1", "swirl-2"),
        (10, "彩虹流动 · 方向 1 / 速度 2", "swirl-3"),
        (11, "彩虹流动 · 方向 2 / 速度 2", "swirl-4"),
        (12, "彩虹流动 · 方向 1 / 速度 3", "swirl-5"),
        (13, "彩虹流动 · 方向 2 / 速度 3", "swirl-6"),
        (14, "流星 · 方向 1 / 速度 1", "snake"),
        (15, "流星 · 方向 2 / 速度 1", "snake-2"),
        (16, "流星 · 方向 1 / 速度 2", "snake-3"),
        (17, "流星 · 方向 2 / 速度 2", "snake-4"),
        (18, "流星 · 方向 1 / 速度 3", "snake-5"),
        (19, "流星 · 方向 2 / 速度 3", "snake-6"),
        (20, "往返扫描 · 速度 1", "knight"),
        (21, "往返扫描 · 速度 2", "knight-2"),
        (22, "往返扫描 · 速度 3", "knight-3"),
        (23, "圣诞红绿", "christmas"),
        (24, "静态渐变 · 范围 1 / 方向 1", "gradient"),
        (25, "静态渐变 · 范围 1 / 方向 2", "gradient-2"),
        (26, "静态渐变 · 范围 2 / 方向 1", "gradient-3"),
        (27, "静态渐变 · 范围 2 / 方向 2", "gradient-4"),
        (28, "静态渐变 · 范围 3 / 方向 1", "gradient-5"),
        (29, "静态渐变 · 范围 3 / 方向 2", "gradient-6"),
        (30, "静态渐变 · 范围 4 / 方向 1", "gradient-7"),
        (31, "静态渐变 · 范围 4 / 方向 2", "gradient-8"),
        (32, "静态渐变 · 范围 5 / 方向 1", "gradient-9"),
        (33, "静态渐变 · 范围 5 / 方向 2", "gradient-10"),
        (34, "RGB 测试", "rgb-test"),
        (35, "交替闪烁", "alternating"),
        (36, "星光闪烁 · 单色 / 速度 1", "twinkle"),
        (37, "星光闪烁 · 单色 / 速度 2", "twinkle-2"),
        (38, "星光闪烁 · 单色 / 速度 3", "twinkle-3"),
        (39, "星光闪烁 · 随机色 / 速度 1", "twinkle-4"),
        (40, "星光闪烁 · 随机色 / 速度 2", "twinkle-5"),
        (41, "星光闪烁 · 随机色 / 速度 3", "twinkle-6")
    ]
    static func request(_ command: UInt8, state: LightState = LightState(), seconds: Double = 5, pattern: Int = 1, sequence: UInt8 = 1, period: Double? = nil) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 32)
        p.replaceSubrange(0..<4, with: Array("KLT1".utf8))
        p[4] = command; p[5] = sequence; p[6] = state.enabled ? 1 : 0
        p[7] = UInt8(clamping: state.effect); p[8] = UInt8(clamping: state.hue)
        p[9] = UInt8(clamping: state.saturation); p[10] = UInt8(clamping: state.brightness)
        let ms = UInt16(seconds.isFinite ? min(60000, max(1, seconds * 1000)) : 5000)
        p[11] = UInt8(ms & 255); p[12] = UInt8(ms >> 8); p[13] = UInt8(clamping: pattern)
        if let period, period.isFinite {
            let value = UInt16(min(10000, max(500, period * 1000)))
            p[14] = UInt8(value & 255); p[15] = UInt8(value >> 8)
        }
        return p
    }

    static func parse(_ p: [UInt8], command: UInt8, sequence: UInt8) throws -> LightState {
        guard p.count == 32, Array(p.prefix(4)) == Array("KLT1".utf8), p[4] == command | 0x80, p[5] == sequence else {
            throw LightError.message("键盘返回了不匹配的数据，请检查固件版本。")
        }
        guard p[6] == 0 else {
            let reasons = [1: "固件不支持这个指令。", 2: "固件不支持所选参数或灯效。", 3: "请先结束临时提醒，再保存常用灯效。"]
            throw LightError.message(reasons[Int(p[6])] ?? "键盘拒绝了指令（\(p[6])）。")
        }
        guard p[12] > 0, p[7] < 2, p[16] < 2, p[17] < 2, p[11] <= p[12] else {
            throw LightError.message("固件返回的灯光状态无效。")
        }
        return LightState(enabled: p[7] == 1, effect: Int(p[8]), hue: Int(p[9]), saturation: Int(p[10]),
                          brightness: Int(p[11]), maxBrightness: Int(p[12]), ledCount: Int(p[13]),
                          effectMask: [14, 15, 20, 21, 22, 23].enumerated().reduce(0) { $0 | (Int(p[$1.element]) << ($1.offset * 8)) }, notifying: p[16] == 1, capsLock: p[17] == 1,
                          remainingMS: Int(p[18]) | Int(p[19]) << 8, notificationMask: p[24] == 0 ? 7 : Int(p[24]), adjustableNotificationTiming: p[25] & 1 != 0)
    }

    static func color(_ hex: String) throws -> NSColor {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }), let n = UInt32(s, radix: 16) else {
            throw LightError.message("颜色请用六位十六进制，例如 #8B5CF6。")
        }
        return NSColor(srgbRed: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, alpha: 1)
    }

    static func applying(_ color: NSColor, to original: LightState) -> LightState {
        var s = original
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        s.hue = Int((rgb.hueComponent * 255).rounded())
        s.saturation = Int((rgb.saturationComponent * 255).rounded())
        if rgb.brightnessComponent == 0 { s.brightness = 0 }
        return s
    }
}
