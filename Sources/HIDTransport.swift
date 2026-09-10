// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import IOKit
import IOKit.hid

struct LightDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var vendorID: Int
    var productID: Int
    var backend: String = "klt1"
}

private final class ReportInbox {
    var report: [UInt8]?
    let command: UInt8
    let sequence: UInt8
    init(_ command: UInt8, _ sequence: UInt8) { self.command = command; self.sequence = sequence }
}

final class KLTTransport {
    // A dedicated vendor-defined collection, separate from the keyboard and VIA interfaces.
    static let usagePage = 0xFF60
    static let usage = 0x62
    static let vendorID = 0x4753
    static let productID = 0x4003

    private func matching(_ dict: [String: Any]) -> (IOHIDManager, [IOHIDDevice]) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, dict as CFDictionary)
        let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        return (manager, Array(set))
    }

    private func identity(_ device: IOHIDDevice) -> LightDevice {
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
        return LightDevice(id: String(registryID), name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Think6.5 V3",
                           vendorID: number(kIOHIDVendorIDKey), productID: number(kIOHIDProductIDKey))
    }

    func devices() -> [LightDevice] {
        let (manager, devices) = matching([kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID, kIOHIDPrimaryUsagePageKey: Self.usagePage, kIOHIDPrimaryUsageKey: Self.usage])
        defer { withExtendedLifetime(manager) {} }
        return devices.map(identity).sorted { $0.id < $1.id }
    }

    func think65Present() -> Bool {
        let (manager, devices) = matching([kIOHIDVendorIDKey: 0x4753, kIOHIDProductIDKey: 0x4003])
        defer { withExtendedLifetime(manager) {} }
        return !devices.isEmpty
    }

    func transact(_ packet: [UInt8], deviceID: String?) throws -> LightState {
        guard packet.count == 32 else { throw LightError.message("内部指令长度错误。") }
        let (manager, candidates) = matching([kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID, kIOHIDPrimaryUsagePageKey: Self.usagePage, kIOHIDPrimaryUsageKey: Self.usage])
        defer { withExtendedLifetime(manager) {} }
        let filtered = candidates.filter { deviceID == nil || identity($0).id == deviceID }
        guard let device = filtered.first else {
            throw LightError.message(think65Present() ? "已检测到 Think6.5 V3，需要刷入 Keyboard Light 通信固件。" : "未找到兼容键盘，请检查 USB 连接。")
        }
        guard filtered.count == 1 || deviceID != nil else { throw LightError.message("连接了多把键盘，请先选择设备或传入 --device。") }
        let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else { throw LightError.message(String(format: "无法打开灯光接口（0x%08x）。请检查设备是否被其他程序独占。", opened)) }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
        let inbox = ReportInbox(packet[4], packet[5])
        let context = Unmanaged.passUnretained(inbox).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, report, length in
            guard let context, result == kIOReturnSuccess, length == 32 else { return }
            let inbox = Unmanaged<ReportInbox>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            if Array(bytes.prefix(4)) == Array("KLT1".utf8), bytes[4] == inbox.command | 0x80, bytes[5] == inbox.sequence { inbox.report = bytes }
        }, context)
        let loop = CFRunLoopGetCurrent()!
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            buffer.deinitialize(count: 64); buffer.deallocate()
            withExtendedLifetime(inbox) {}
        }
        let sent = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, packet.count) }
        guard sent == kIOReturnSuccess else { throw LightError.message(String(format: "灯光指令发送失败（0x%08x）。", sent)) }
        let deadline = Date().addingTimeInterval(1.2)
        while inbox.report == nil && Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.01, false) }
        guard let reply = inbox.report else { throw LightError.message("键盘没有确认指令，请重连键盘并检查通信固件版本。") }
        return try LightProtocol.parse(reply, command: packet[4], sequence: packet[5])
    }
}
