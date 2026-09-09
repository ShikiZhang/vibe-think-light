// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

final class LightController: ObservableObject {
    @Published var state = LightState()
    @Published var devices: [LightDevice] = []
    @Published var selectedID = ""
    @Published var connected = false
    @Published var status = "正在查找键盘…"
    @Published var message = ""
    @Published var busy = false
    let demo: Bool
    private let queue = DispatchQueue(label: "local.keyboardlight.hid")
    private let transport = HIDTransport()
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var dirty = false
    private var revision = 0
    private var demoBaseline: LightState?
    private var demoSaved = LightState()
    private var demoExpiry: DispatchWorkItem?

    init(demo: Bool) {
        self.demo = demo
        if demo {
            devices = [LightDevice(id: "demo", name: "Think6.5 V3", vendorID: 0x4753, productID: 0x4003)]
            selectedID = "demo"; connected = true; status = "界面预览 · 不会控制键盘"
        } else { refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func select(_ id: String) {
        pending?.cancel(); dirty = false; revision += 1; selectedID = id
        connected = false; message = ""; refresh()
    }

    func refresh() {
        guard !demo, !busy, !dirty else { return }
        busy = true
        let requestedID = selectedID
        queue.async {
            let found = self.transport.devices()
            let selected = found.first(where: { $0.id == requestedID }) ?? found.first
            var received: LightState?
            var problem: String?
            if let selected {
                do { received = try self.transport.transact(LightProtocol.request(1, sequence: UInt8.random(in: 1...254)), deviceID: selected.id) }
                catch { problem = error.localizedDescription }
            } else {
                problem = self.transport.think65Present() ? "已检测到 Think6.5 V3，等待通信固件升级。" : "请通过 USB 连接 Think6.5 V3。"
            }
            DispatchQueue.main.async {
                self.busy = false; self.devices = found
                // A user may have changed the selection while discovery was running.
                guard self.selectedID == requestedID else { return }
                self.selectedID = selected?.id ?? ""
                if let received {
                    self.connected = true
                    if !self.dirty { self.state = received }
                    self.status = "已连接 · \(selected!.name)"
                } else { self.connected = false; self.status = problem ?? "未连接" }
            }
        }
    }

    func edit(_ change: (inout LightState) -> Void) {
        guard connected else { return }
        change(&state); revision += 1; dirty = true; message = ""
        scheduleSet()
    }

    private func scheduleSet() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.busy { self.scheduleSet(); return }
            self.send(2)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    func chooseColor(_ color: NSColor) {
        edit { s in s = LightProtocol.applying(color, to: s); s.enabled = true }
    }

    func send(_ command: UInt8, seconds: Double = 5, pattern: Int = 1, notice: LightState? = nil, period: Double? = nil) {
        guard connected else { return }
        if busy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.send(command, seconds: seconds, pattern: pattern, notice: notice, period: period) }
            return
        }
        pending?.cancel()
        let captured = state, target = selectedID, version = revision
        let commitPending = dirty && (command == 3 || command == 5)
        dirty = false; busy = true
        if demo {
            if command == 3 {
                if demoBaseline == nil { demoBaseline = state }
                state.notifying = true
                demoExpiry?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.send(4) }
                demoExpiry = work
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
            } else if command == 4 {
                if let baseline = demoBaseline { state = baseline }; demoBaseline = nil; demoExpiry?.cancel()
            } else if command == 2 {
                demoBaseline = nil; demoExpiry?.cancel(); state.notifying = false
            } else if command == 5 { demoSaved = state }
            else if command == 6 { state = demoSaved; demoBaseline = nil; demoExpiry?.cancel() }
            message = "预览模式：未向键盘发送指令。"; busy = false; return
        }
        queue.async {
            let result = Result {
                if commitPending { _ = try self.transport.transact(LightProtocol.request(2, state: captured, sequence: UInt8.random(in: 1...254)), deviceID: target) }
                return try self.transport.transact(LightProtocol.request(command, state: command == 3 ? (notice ?? captured) : captured, seconds: seconds, pattern: pattern, sequence: UInt8.random(in: 1...254), period: period), deviceID: target) }
            DispatchQueue.main.async {
                self.busy = false
                guard self.selectedID == target else { return }
                switch result {
                case .success(let received):
                    if self.revision == version { self.state = received }
                    self.message = command == 5 ? "已保存到键盘，断电后仍保留。" : command == 6 ? "已恢复上次保存的灯光。" : command == 3 ? "临时灯效结束后会自动恢复。" : ""
                case .failure(let error):
                    self.message = error.localizedDescription
                    self.connected = false
                }
            }
        }
    }
}

struct LightPanel: View {
    @ObservedObject var model: LightController
    @State private var hex = ""
    @State private var hexError = ""
    @State private var showAutomation = false
    private let presets = [("暖白", "FFE5BE"), ("薄荷", "56E5B4"), ("海蓝", "529BFF"), ("紫罗兰", "A584FF"), ("珊瑚", "FF817D")]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(LinearGradient(colors: [Color(red: 0.30, green: 0.39, blue: 0.90), Color(red: 0.55, green: 0.34, blue: 0.83)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("键盘灯光").font(.system(size: 25, weight: .semibold))
                    Text("随手调光，即刻生效").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showAutomation.toggle() } label: { Label("自动化接口", systemImage: "terminal") }
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 9) {
                Circle().fill(model.connected ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.status).font(.system(size: 12)).lineLimit(2)
                Spacer()
                if model.devices.count > 1 {
                    Picker("键盘", selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                        ForEach(model.devices) { Text("\($0.name) · \($0.id.suffix(4))").tag($0.id) }
                    }.labelsHidden().frame(width: 180)
                }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("重新检测键盘")
            }.padding(12).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("日常灯光", systemImage: "sun.max").font(.headline)
                    Spacer()
                    Toggle("开启灯光", isOn: Binding(get: { model.state.enabled }, set: { v in model.edit { $0.enabled = v } })).toggleStyle(.switch)
                }
                HStack(spacing: 12) {
                    ForEach(0..<min(model.state.ledCount, 12), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: model.state.color).opacity(model.state.enabled ? max(0.12, model.state.percent / 100) : 0.08))
                            .frame(height: 36).shadow(color: Color(nsColor: model.state.color).opacity(model.state.enabled ? 0.22 : 0), radius: 8)
                    }
                }.padding(.vertical, 3).accessibilityLabel("灯光颜色示意")
                HStack(spacing: 12) {
                    Text("颜色").frame(width: 38, alignment: .leading)
                    ColorPicker("选择颜色", selection: Binding(get: { Color(nsColor: model.state.color) }, set: { model.chooseColor(NSColor($0)) }), supportsOpacity: false).labelsHidden()
                    ForEach(presets, id: \.0) { name, value in
                        Button { if let color = try? LightProtocol.color(value) { model.chooseColor(color) } } label: {
                            Circle().fill(Color(nsColor: (try? LightProtocol.color(value)) ?? .white)).frame(width: 24, height: 24).overlay(Circle().strokeBorder(.primary.opacity(0.12)))
                        }.buttonStyle(.plain).help(name).accessibilityLabel(name)
                    }
                    Spacer()
                    TextField("#8B5CF6", text: $hex).textFieldStyle(.roundedBorder).frame(width: 96).onSubmit(applyHex)
                    Button("应用", action: applyHex)
                }
                HStack {
                    Text("亮度").frame(width: 38, alignment: .leading)
                    Slider(value: Binding(get: { model.state.percent }, set: { v in model.edit { $0.brightness = Int((v * Double($0.maxBrightness) / 100).rounded()) } }), in: 0...100).disabled((1...4).contains(model.state.effect))
                    Text("\(Int(model.state.percent.rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Text("灯效").frame(width: 38, alignment: .leading)
                    Picker("灯效", selection: Binding(get: { model.state.effect }, set: { v in model.edit { $0.effect = v; $0.enabled = true } })) {
                        ForEach(LightProtocol.effects.filter { model.state.effectMask & (1 << $0.0) != 0 }, id: \.0) { id, title, _ in Text(title).tag(id) }
                        if model.state.effect == 255 { Text("键盘原有灯效").tag(255) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                Text(model.state.capsLock && !model.state.notifying ? "Caps Lock 已开启，键盘的白色指示灯可能覆盖当前颜色。" : (1...4).contains(model.state.effect) ? "内置呼吸灯效自行控制明暗，保持键盘原有行为。" : "使用键盘原有灯效；彩虹和测试模式自行生成颜色。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .disabled(!model.connected)

            NotificationPanel(model: model)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hexError.isEmpty ? model.message : hexError).font(.caption).foregroundStyle(hexError.isEmpty ? Color.secondary : Color.orange).lineLimit(2)
                    Text("保存后，拔线或关闭程序也能保留当前灯光。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("恢复已保存") { model.send(6) }.disabled(!model.connected || model.busy)
                Button("保存到键盘") { model.send(5) }.buttonStyle(.borderedProminent).tint(.indigo).disabled(!model.connected || model.state.notifying || model.busy)
            }
        }
        .padding(26).frame(width: 648)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showAutomation) { automationSheet }
    }

    private func applyHex() {
        do { model.chooseColor(try LightProtocol.color(hex)); hexError = "" }
        catch { hexError = error.localizedDescription }
    }

    private var automationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("给脚本和其他软件的灯光接口").font(.title2.bold())
            Text("独立于 Codex，控制程序不打开窗口也可以执行。把 keyboardlight 路径替换为下载文件夹中的实际位置。").foregroundStyle(.secondary)
            Text("keyboardlight set --color '#8B5CF6' --brightness 60 --effect solid\n\nkeyboardlight notify --color '#34D399' --seconds 5 --pattern blink\n\nkeyboardlight restore\n\nkeyboardlight status")
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            Text("notify 的计时和恢复由键盘完成；脚本退出后仍会自动恢复。status 返回 JSON，便于其他程序读取。").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("完成") { showAutomation = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 570)
    }
}

final class LightAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var item: NSStatusItem!
    var controller: LightController!
    let demo: Bool
    init(demo: Bool) { self.demo = demo }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = LightController(demo: demo)
        let panel = LightPanel(model: controller)
        let panelHeight = NSHostingView(rootView: panel).fittingSize.height
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        let content = NSHostingView(rootView: ScrollView { panel }.frame(width: 648, height: min(panelHeight, visibleHeight - 80)))
        let size = content.fittingSize
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: size.height), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "键盘灯光"; window.contentView = content; window.delegate = self
        window.isReleasedWhenClosed = false; window.center()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "键盘灯光")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开灯光面板", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "开启／关闭灯光", action: #selector(toggleLight), keyEquivalent: "")
        menu.addItem(withTitle: "结束临时灯效", action: #selector(restoreLight), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出键盘灯光", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        let main = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出键盘灯光", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""), edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        showPanel()
    }
    @objc func showPanel() { controller.refresh(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleLight() { controller.edit { $0.enabled.toggle() } }
    @objc func restoreLight() { controller.send(4) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
