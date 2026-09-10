// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import IOKit
import IOKit.hid

/// Select a backend by USB identity, then let that backend validate its protocol.
/// Unknown VIA/Vial devices are deliberately not treated as Apollo80 RGBLight.
final class HIDTransport {
    private let klt = KLTTransport()
    func devices() -> [LightDevice] { (klt.devices() + ApolloHID.devices()).sorted { $0.id < $1.id } }
    func think65Present() -> Bool { klt.think65Present() }
    func transact(_ packet: [UInt8], deviceID: String?) throws -> LightState {
        let candidates = devices().filter { deviceID == nil || $0.id == deviceID }
        guard let target = candidates.first else { throw LightError.message("未找到支持的键盘，请检查 USB 连接。") }
        guard candidates.count == 1 else { throw LightError.message("连接了多把支持的键盘，请选择设备或传入 --device ID。") }
        if target.backend == "vial" { return try VialHost.transact(packet, deviceID: target.id) }
        return try klt.transact(packet, deviceID: target.id)
    }
}

private final class VialInbox { var report: [UInt8]? }

/// One non-exclusive Raw HID session, restricted to the tested Apollo80 R2 interface.
final class ApolloHID {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let inbox = VialInbox()
    private let loop: CFRunLoop
    private static let matching: [String: Any] = [kIOHIDVendorIDKey: 0x4753, kIOHIDProductIDKey: 0x3080,
        kIOHIDPrimaryUsagePageKey: 0xFF60, kIOHIDPrimaryUsageKey: 0x61]

    private static func enumerate() -> (IOHIDManager, [IOHIDDevice]) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        return (manager, Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []))
    }
    private static func id(_ device: IOHIDDevice) -> String {
        var value: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &value)
        return String(value)
    }
    static func devices() -> [LightDevice] {
        let (manager, devices) = enumerate()
        defer { withExtendedLifetime(manager) {} }
        return devices.map { LightDevice(id: id($0), name: "Apollo80 R2", vendorID: 0x4753, productID: 0x3080, backend: "vial") }
    }
    init(deviceID: String) throws {
        let (manager, devices) = Self.enumerate()
        guard let device = devices.first(where: { Self.id($0) == deviceID }) else {
            buffer.deallocate()
            throw LightError.message("Apollo80 已断开；通知不会转移到其他键盘。")
        }
        self.manager = manager; self.device = device; self.loop = CFRunLoopGetCurrent()!
        let result = IOHIDDeviceOpen(device, 0)
        guard result == kIOReturnSuccess else {
            buffer.deallocate()
            throw LightError.message("无法打开 Apollo80 灯光接口，请关闭占用设备的工具后重试。")
        }
        buffer.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, report, count in
            guard let context, result == kIOReturnSuccess, count == 32 else { return }
            Unmanaged<VialInbox>.fromOpaque(context).takeUnretainedValue().report = Array(UnsafeBufferPointer(start: report, count: count))
        }, Unmanaged.passUnretained(inbox).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
    }
    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, 0); buffer.deallocate()
    }
    func exchange(_ prefix: [UInt8], matches: ([UInt8]) -> Bool) throws -> [UInt8] {
        guard prefix.count <= 32 else { throw LightError.message("Vial 指令长度错误。") }
        // Drain unsolicited/stale input before installing this request's response slot.
        CFRunLoopRunInMode(.defaultMode, 0.001, false)
        inbox.report = nil
        let packet = prefix + [UInt8](repeating: 0, count: 32 - prefix.count)
        let sent = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, 32) }
        guard sent == kIOReturnSuccess else { throw LightError.message("Vial 灯光通信中断。") }
        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            if let response = inbox.report {
                inbox.report = nil
                if matches(response) { return response }
            }
            CFRunLoopRunInMode(.defaultMode, 0.002, false)
        }
        throw LightError.message("Vial 未确认灯光指令，请关闭其他调灯工具后重试。")
    }
    func verify() throws {
        let version = try exchange([1]) { $0[0] == 1 }
        let identity = try exchange([0xfe, 0]) { Array($0.prefix(4)) == [6, 0, 0, 0] }
        guard version[1] == 0, version[2] == 9,
              Array(identity[4..<12]) == [0xd0, 0x75, 0x79, 0xbf, 0x01, 0x05, 0xac, 0xd2] else {
            throw LightError.message("这版 Apollo80 固件尚未适配，未修改灯光。")
        }
    }
    func get(_ field: UInt8) throws -> [UInt8] {
        for sentinel: [UInt8] in [[0xa5, 0x5a], [0x5a, 0xa5]] {
            let response = try exchange([8, field] + sentinel) { $0[0] == 8 && $0[1] == field }
            if Array(response[2..<4]) != sentinel { return Array(response[2...]) }
        }
        throw LightError.message("固件未开放所需 RGBLight 接口。")
    }
    func read() throws -> VialSettings {
        let brightness = try get(0x80)[0], effect = try get(0x81)[0]
        let speed = try get(0x82)[0], color = try get(0x83)
        return VialSettings(effect: Int(effect), hue: Int(color[0]), saturation: Int(color[1]), brightness: Int(brightness), speed: Int(speed))
    }
    private func set(_ field: UInt8, _ values: [Int]) throws {
        let prefix = [UInt8(7), field] + values.map { UInt8(clamping: $0) }
        _ = try exchange(prefix) { Array($0.prefix(prefix.count)) == prefix }
    }
    static func writes(_ settings: VialSettings, previous: VialSettings?) -> [(UInt8, [Int])] {
        var commands: [(UInt8, [Int])] = []
        let colorChanged = previous?.hue != settings.hue || previous?.saturation != settings.saturation
        let brightnessChanged = previous?.brightness != settings.brightness
        let stageSolid = previous?.effect != 1 && (colorChanged || brightnessChanged)
        // RGBLight ignores HSV while disabled, hue in rainbow and value in breathing.
        // The first mode command may only enable the old mode; the second selects solid.
        if stageSolid { commands += [(0x81, [1]), (0x81, [1])] }
        if colorChanged { commands.append((0x83, [settings.hue, settings.saturation])) }
        if brightnessChanged { commands.append((0x80, [settings.brightness])) }
        if previous?.speed != settings.speed { commands.append((0x82, [settings.speed])) }
        if settings.effect != (stageSolid ? 1 : (previous?.effect ?? -1)) {
            commands.append((0x81, [settings.effect]))
            if !stageSolid && previous?.effect == 0 && settings.effect > 0 { commands.append((0x81, [settings.effect])) }
        }
        return commands
    }
    func apply(_ settings: VialSettings, previous: VialSettings? = nil) throws {
        for (field, values) in Self.writes(settings, previous: previous) { try set(field, values) }
    }
    func save() throws { _ = try exchange([9]) { $0[0] == 9 } }
}
