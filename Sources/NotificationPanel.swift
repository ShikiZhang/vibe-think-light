// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

struct NotificationPanel: View {
    @ObservedObject var model: LightController
    @AppStorage("notice.pattern") private var pattern = 1
    @AppStorage("notice.color") private var colorHex = "34D399"
    @AppStorage("notice.brightness") private var brightness = 70.0
    @AppStorage("notice.seconds") private var seconds = 5.0
    @AppStorage("notice.period") private var period = 0.0
    private let presets = [("完成", "34D399"), ("待确认", "FBBF24"), ("错误", "F87171"), ("消息", "60A5FA"), ("自选紫", "A78BFA")]
    private var supported: Bool { (0...6).contains(pattern) && model.state.notificationMask & (1 << pattern) != 0 && (pattern == 0 || period == 0 || model.state.adjustableNotificationTiming) }
    private var color: NSColor { (try? LightProtocol.color(colorHex)) ?? .systemGreen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("提醒灯效", systemImage: "bell.badge").font(.headline)
                Spacer()
                if model.state.notifying {
                    Text("正在提醒").font(.caption).foregroundStyle(.orange)
                    Button("结束提醒") { model.send(4) }
                }
                Button(model.state.notifying ? "替换提醒" : "试播提醒", action: play).disabled(!supported || model.busy)
            }
            HStack(spacing: 12) {
                Text("样式").frame(width: 38, alignment: .leading)
                Picker("提醒样式", selection: $pattern) {
                    ForEach(LightProtocol.notifications, id: \.0) { id, title, _ in Text(title).tag(id) }
                }.labelsHidden().frame(maxWidth: .infinity)
                Picker("持续时间", selection: $seconds) {
                    ForEach([2.0, 5, 10, 15, 30, 60], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                }.frame(width: 158)
            }
            if pattern != 0 {
                HStack(spacing: 12) {
                    Text("周期").frame(width: 38, alignment: .leading)
                    Picker("提醒周期", selection: $period) {
                        Text("默认节奏").tag(0.0)
                        ForEach([0.5, 0.8, 1.2, 2.0, 3.0, 4.0, 6.0, 10.0], id: \.self) { value in
                            Text("\(value, specifier: "%.1f") 秒 / 轮").tag(value)
                        }
                    }.labelsHidden().frame(width: 150).disabled(!model.state.adjustableNotificationTiming)
                    Text("数值越小，播放越快").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack(spacing: 12) {
                Text("颜色").frame(width: 38, alignment: .leading)
                ColorPicker("提醒颜色", selection: Binding(get: { Color(nsColor: color) }, set: { value in
                    let rgb = NSColor(value).usingColorSpace(.sRGB) ?? .systemGreen
                    colorHex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                }), supportsOpacity: false).labelsHidden().disabled(pattern == 5)
                ForEach(presets, id: \.0) { title, hex in
                    Button { colorHex = hex } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color(nsColor: (try? LightProtocol.color(hex)) ?? .white)).frame(width: 10, height: 10)
                            Text(title).font(.caption)
                        }
                    }.buttonStyle(.borderless).disabled(pattern == 5)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text("亮度").frame(width: 38, alignment: .leading)
                Slider(value: $brightness, in: 1...100).accessibilityLabel("提醒亮度")
                Text("\(Int(brightness.rounded()))%").monospacedDigit().font(.caption).frame(width: 38, alignment: .trailing)
            }
            Text(model.state.backend == "vial" && !model.state.enabled ? "日常灯光已关闭，提醒将自动跳过。" : !supported ? "所选样式或自定义周期需要更新配套固件。" : pattern == 5 ? "彩虹自动变色；计时结束恢复原灯光。选择设置后点击试播。" : "提醒颜色和亮度独立设置，计时结束恢复原灯光。选择设置后点击试播。")
                .font(.caption).foregroundStyle(supported ? Color.secondary : .orange)
        }.padding(16).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)).disabled(!model.connected)
    }
    private func play() {
        guard supported else { return }
        var appearance = LightProtocol.applying(color, to: model.state)
        appearance.brightness = Int((max(1, min(100, brightness)) * Double(appearance.maxBrightness) / 100).rounded())
        model.send(3, seconds: max(1, min(60, seconds)), pattern: pattern, notice: appearance, period: pattern != 0 && period > 0 ? period : nil)
    }
}
