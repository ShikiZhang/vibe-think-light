// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Darwin

struct VialSettings: Codable, Equatable {
    var effect: Int
    var hue: Int
    var saturation: Int
    var brightness: Int
    var speed: Int

    func state() -> LightState {
        var state = LightState()
        state.enabled = effect != 0
        // Legacy RGBLight has no effect enumeration. Only solid is portable;
        // all other firmware-specific effect numbers are preserved verbatim.
        state.effect = effect == 1 ? 0 : 255
        state.nativeEffect = effect
        state.hue = hue; state.saturation = saturation; state.brightness = brightness
        state.maxBrightness = max(150, brightness) // conservative host ceiling, not a queried PCB limit
        state.ledCount = 0 // legacy protocol does not report the LED count
        state.effectMask = 1
        state.adjustableNotificationTiming = true
        state.backend = "vial"; state.canReloadSaved = false
        return state
    }
}

struct HostNotice: Codable {
    var generation: String
    var baseline: VialSettings
    var appearance: VialSettings
    var started: Date
    var seconds: Double
    var pattern: Int
    var period: Double
    var expected: VialSettings?
    var workerPID: Int32 = 0

    func remaining(at now: Date) -> Int { max(0, Int((seconds - now.timeIntervalSince(started)) * 1000)) }
    func frame(at now: Date) -> VialSettings {
        let elapsed = max(0, now.timeIntervalSince(started))
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        var result = appearance
        result.effect = 1
        var level = 1.0
        switch pattern {
        case 1, 6: level = phase < 0.5 ? 1 : 0
        case 2: level = 0.15 + 0.85 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2)
        case 3: level = phase < 0.1 || (phase >= 0.2 && phase < 0.3) ? 1 : 0
        case 4:
            let ms = phase * 1800
            if ms < 300 { level = (ms < 150 ? ms : 300 - ms) / 150 }
            else if ms >= 420 && ms < 720 { level = (ms < 570 ? ms - 420 : 720 - ms) / 150 * 0.7 }
            else { level = 0 }
        case 5: result.hue = (appearance.hue + Int(phase * 256)) % 256; result.saturation = 255
        default: break
        }
        result.brightness = Int(Double(appearance.brightness) * level)
        return result
    }
}

struct VialRecord: Codable {
    var notice: HostNotice?
    var lastEnabledEffect = 1
}

protocol VialLighting {
    func read() throws -> VialSettings
    func apply(_ settings: VialSettings, previous: VialSettings?) throws
    func save() throws
}
extension ApolloHID: VialLighting {}

/// State machine shared by CLI, GUI and the worker. The caller holds the per-device lock.
final class VialNotificationEngine {
    var record: VialRecord
    let lighting: VialLighting
    let persist: (VialRecord) throws -> Void
    init(record: VialRecord, lighting: VialLighting, persist: @escaping (VialRecord) throws -> Void) {
        self.record = record; self.lighting = lighting; self.persist = persist
    }
    private func store() throws { try persist(record) }
    private func remember(_ state: VialSettings) {
        if state.effect > 0 { record.lastEnabledEffect = state.effect }
    }
    /// Preserve a manual Fn/Vial change instead of overwriting it with an old baseline.
    func reconcile(now: Date, workerAlive: Bool) throws -> VialSettings {
        var actual = try lighting.read()
        if let notice = record.notice {
            if let expected = notice.expected, actual != expected {
                record.notice = nil
                remember(actual)
                try store()
            } else if notice.remaining(at: now) == 0 || !workerAlive || notice.expected == nil {
                try lighting.apply(notice.baseline, previous: nil)
                actual = try lighting.read()
                guard actual == notice.baseline else { throw LightError.message("Vial 未能恢复原灯光，将在下次连接时重试。") }
                record.notice = nil; remember(actual); try store()
            }
        }
        remember(actual)
        return actual
    }
    func status(actual: VialSettings, now: Date) -> LightState {
        var result = (record.notice?.baseline ?? actual).state()
        result.notifying = record.notice != nil
        result.remainingMS = record.notice?.remaining(at: now) ?? 0
        return result
    }
    func cancel() throws -> VialSettings {
        if let notice = record.notice {
            record.notice?.expected = nil; try store()
            try lighting.apply(notice.baseline, previous: nil)
            let restored = try lighting.read()
            guard restored == notice.baseline else { throw LightError.message("Vial 恢复尚未完成，请重试。") }
            record.notice = nil; remember(restored); try store()
            return restored
        }
        return try lighting.read()
    }
    func set(_ packet: [UInt8]) throws -> VialSettings {
        guard packet[7] == 0 || packet[7] == 255 else {
            throw LightError.message("Apollo80 暂只支持选择常亮或保留原灯效；其他日常灯效请在 Vial 中选择。")
        }
        let original = try cancel()
        let effect = packet[7] == 255 ? (original.effect > 0 ? original.effect : record.lastEnabledEffect) : 1
        let desired = VialSettings(effect: packet[6] == 0 ? 0 : effect, hue: Int(packet[8]), saturation: Int(packet[9]),
                                   brightness: min(150, Int(packet[10])), speed: original.speed)
        try lighting.apply(desired, previous: original)
        let actual = try lighting.read()
        guard actual == desired else { throw LightError.message("Vial 未应用全部灯光设置。") }
        if packet[6] == 0 { record.lastEnabledEffect = effect } else { remember(actual) }
        try store()
        return actual
    }
    func begin(_ packet: [UInt8], actual: VialSettings, now: Date, launch: (String) throws -> Int32) throws -> LightState {
        let seconds = Double(Int(packet[11]) | Int(packet[12]) << 8) / 1000
        let customPeriod = Int(packet[14]) | Int(packet[15]) << 8
        let pattern = Int(packet[13])
        guard (0...6).contains(pattern), seconds > 0, seconds <= 60,
              customPeriod == 0 || (pattern != 0 && (500...10000).contains(customPeriod)) else {
            throw LightError.message("无效的提醒参数。")
        }
        let baseline = record.notice?.baseline ?? actual
        guard baseline.effect != 0 else { return status(actual: actual, now: now) }
        let appearance = VialSettings(effect: 1, hue: Int(packet[8]), saturation: Int(packet[9]), brightness: min(150, Int(packet[10])), speed: baseline.speed)
        let defaults = [1.0, 0.8, 2.0, 1.6, 1.8, 4.0, 2.4]
        let generation = UUID().uuidString
        record.notice = HostNotice(generation: generation, baseline: baseline, appearance: appearance, started: now,
                                   seconds: seconds, pattern: pattern, period: customPeriod == 0 ? defaults[pattern] : Double(customPeriod) / 1000)
        try store() // journal the original appearance before the first USB write
        do {
            let frame = record.notice!.frame(at: now)
            try lighting.apply(frame, previous: nil)
            guard try lighting.read() == frame else { throw LightError.message("Vial 未应用提醒灯光。") }
            record.notice?.expected = frame
            record.notice?.workerPID = try launch(generation)
            try store()
        } catch {
            _ = try? cancel()
            throw error
        }
        return status(actual: actual, now: now)
    }
    func tick(generation: String, now: Date) throws -> Bool {
        guard record.notice?.generation == generation else { return false }
        _ = try reconcile(now: now, workerAlive: true)
        guard let notice = record.notice else { return false }
        let frame = notice.frame(at: now)
        if frame != notice.expected {
            record.notice?.expected = nil; try store() // recover even after a partial USB update
            try lighting.apply(frame, previous: notice.expected)
            guard try lighting.read() == frame else { throw LightError.message("Vial 提醒灯光写入不一致。") }
            record.notice?.expected = frame; try store()
        }
        return true
    }
}

/// A journal and advisory lock per USB connection; unplug/replug yields a new id.
/// No lock descriptor or standard stream is inherited by the background process.
final class VialJournal {
    let directory: URL
    let stateURL: URL
    let lockURL: URL
    init(deviceID: String) throws {
        guard !deviceID.isEmpty, deviceID.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw LightError.message("无效设备 ID。") }
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("KeyboardLight/vial")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        stateURL = directory.appendingPathComponent(deviceID + ".json")
        lockURL = directory.appendingPathComponent(deviceID + ".lock")
    }
    func withLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LightError.message("无法打开 Vial 通知锁。") }
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(1)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, Date() < deadline else { throw LightError.message("Vial 正在处理其他灯光指令，请重试。") }
            Thread.sleep(forTimeInterval: 0.005)
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    func load() throws -> VialRecord {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return VialRecord() }
        return try JSONDecoder().decode(VialRecord.self, from: Data(contentsOf: stateURL))
    }
    func store(_ record: VialRecord) throws {
        try JSONEncoder().encode(record).write(to: stateURL, options: .atomic)
    }
}

enum VialHost {
    static func alive(_ pid: Int32) -> Bool { pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) }
    static func transact(_ packet: [UInt8], deviceID: String) throws -> LightState {
        guard packet.count == 32, Array(packet.prefix(4)) == Array("KLT1".utf8), (1...6).contains(packet[4]) else {
            throw LightError.message("无效灯光指令。")
        }
        if packet[4] == 6 { throw LightError.message("Vial 没有读取已保存灯光的接口；可使用“结束提醒”恢复通知前状态。") }
        let journal = try VialJournal(deviceID: deviceID)
        return try journal.withLock {
            let hid = try ApolloHID(deviceID: deviceID)
            try hid.verify()
            let record = try journal.load()
            let engine = VialNotificationEngine(record: record, lighting: hid, persist: journal.store)
            let now = Date()
            var actual = try engine.reconcile(now: now, workerAlive: alive(record.notice?.workerPID ?? 0))
            switch packet[4] {
            case 2: actual = try engine.set(packet)
            case 3:
                return try engine.begin(packet, actual: actual, now: now) { generation in
                    let process = Process()
                    process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
                    process.arguments = ["--vial-worker", deviceID, generation]
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    return process.processIdentifier
                }
            case 4: actual = try engine.cancel()
            case 5:
                guard engine.record.notice == nil else { throw LightError.message("请先结束临时提醒，再保存常用灯效。") }
                try hid.save()
            default: break
            }
            return engine.status(actual: actual, now: now)
        }
    }
    static func runWorker(deviceID: String, generation: String) {
        _ = setsid()
        do {
            let journal = try VialJournal(deviceID: deviceID)
            // Each tick reopens this exact USB connection, never a newly plugged keyboard.
            while try journal.withLock({
                let record = try journal.load()
                guard record.notice?.generation == generation else { return false }
                let hid = try ApolloHID(deviceID: deviceID)
                let engine = VialNotificationEngine(record: record, lighting: hid, persist: journal.store)
                do { return try engine.tick(generation: generation, now: Date()) }
                catch { _ = try? engine.cancel(); throw error }
            }) { Thread.sleep(forTimeInterval: 0.04) }
        } catch {
            // Journal survives a crash/USB failure. A subsequent command can recover
            // the same connection; a new connection is never given a stale baseline.
            let log = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KeyboardLight/vial/last-error.txt")
            try? "\(Date()): \(error.localizedDescription)\n".write(to: log, atomically: true, encoding: .utf8)
        }
    }
}
