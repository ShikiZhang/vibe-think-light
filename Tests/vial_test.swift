// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

final class FakeVial: VialLighting {
    var actual: VialSettings
    var writes = 0
    var saves = 0
    var failNext = false
    init(_ settings: VialSettings) { actual = settings }
    func read() throws -> VialSettings { actual }
    func apply(_ settings: VialSettings, previous: VialSettings?) throws {
        writes += 1
        if failNext { failNext = false; actual.hue = settings.hue; throw LightError.message("partial USB failure") }
        actual = settings
    }
    func save() throws { saves += 1 }
}

@main struct VialTests {
    static func main() throws {
        let baseline = VialSettings(effect: 17, hue: 104, saturation: 247, brightness: 150, speed: 3)
        let now = Date(timeIntervalSince1970: 1000)
        let fake = FakeVial(baseline)
        var journal = VialRecord()
        let engine = VialNotificationEngine(record: journal, lighting: fake) { journal = $0 }
        let color = LightState(hue: 43, saturation: 255, brightness: 120)
        let blink = LightProtocol.request(3, state: color, seconds: 5, pattern: 1, period: 1.2)
        _ = try engine.begin(blink, actual: baseline, now: now) { _ in 123 }
        let first = engine.record.notice!.generation
        assert(journal.notice!.baseline == baseline)
        assert(fake.actual.brightness == 120 && fake.actual.effect == 1)
        assert(tryTick(engine, first, now.addingTimeInterval(0.7)))
        assert(fake.actual.brightness == 0)
        assert(tryTick(engine, first, now.addingTimeInterval(1.3)))
        assert(fake.actual.brightness == 120)
        let status = engine.status(actual: fake.actual, now: now.addingTimeInterval(1.3))
        assert(status.notifying && status.nativeEffect == 17 && status.brightness == 150)
        // Replacements keep the very first baseline. Old workers cannot overwrite them.
        _ = try engine.begin(LightProtocol.request(3, state: color, seconds: 3, pattern: 2, period: 1), actual: fake.actual, now: now.addingTimeInterval(2)) { _ in 124 }
        let second = engine.record.notice!.generation
        assert(engine.record.notice!.baseline == baseline)
        assert(!tryTick(engine, first, now.addingTimeInterval(2.1)))
        assert(tryTick(engine, second, now.addingTimeInterval(2.5)))
        assert(fake.actual.brightness == 120)
        assert(!tryTick(engine, second, now.addingTimeInterval(6)))
        assert(fake.actual == baseline && journal.notice == nil)
        // A killed worker is recovered from the journal on the next request.
        _ = try engine.begin(blink, actual: baseline, now: now) { _ in 123 }
        let recovered = VialNotificationEngine(record: journal, lighting: fake) { journal = $0 }
        _ = try recovered.reconcile(now: now.addingTimeInterval(1), workerAlive: false)
        assert(fake.actual == baseline && journal.notice == nil)
        // Manual Fn/Vial changes win over the notification, including at expiry.
        _ = try recovered.begin(blink, actual: baseline, now: now) { _ in 123 }
        fake.actual = VialSettings(effect: 8, hue: 9, saturation: 10, brightness: 11, speed: 2)
        let manual = fake.actual
        _ = try recovered.reconcile(now: now.addingTimeInterval(10), workerAlive: true)
        assert(fake.actual == manual && journal.notice == nil)
        // Disabled lights skip the notification without a USB write or worker.
        let off = VialSettings(effect: 0, hue: 3, saturation: 4, brightness: 5, speed: 2)
        fake.actual = off
        let beforeSkip = fake.writes
        let skipped = try recovered.begin(blink, actual: off, now: now) { _ in fatalError("must not spawn") }
        assert(!skipped.notifying && !skipped.enabled && fake.writes == beforeSkip && journal.notice == nil)
        // Process launch failure and partial USB failure both roll back.
        fake.actual = baseline
        do { _ = try recovered.begin(blink, actual: baseline, now: now) { _ in throw LightError.message("spawn") }; assertionFailure() } catch {}
        assert(fake.actual == baseline && journal.notice == nil)
        fake.failNext = true
        do { _ = try recovered.begin(blink, actual: baseline, now: now) { _ in 123 }; assertionFailure() } catch {}
        assert(fake.actual == baseline && journal.notice == nil)
        // A journal interrupted between USB writes has expected=nil and must recover.
        _ = try recovered.begin(blink, actual: baseline, now: now) { _ in 123 }
        journal.notice!.expected = nil
        let partial = VialNotificationEngine(record: journal, lighting: fake) { journal = $0 }
        _ = try partial.reconcile(now: now.addingTimeInterval(0.1), workerAlive: true)
        assert(fake.actual == baseline && journal.notice == nil)
        // SET after a notice preserves the original native mode and speed.
        fake.actual = baseline
        _ = try partial.begin(blink, actual: baseline, now: now) { _ in 123 }
        var changed = baseline.state(); changed.hue = 77
        let set = try partial.set(LightProtocol.request(2, state: changed))
        assert(set.effect == 17 && set.speed == 3 && set.hue == 77 && journal.notice == nil)
        changed.effect = 2
        do { _ = try partial.set(LightProtocol.request(2, state: changed)); assertionFailure() } catch {}
        // Complete cycles and default patterns stay within the brightness ceiling.
        for pattern in 0...6 {
            var note = HostNotice(generation: "test", baseline: off, appearance: baseline, started: now, seconds: 5, pattern: pattern, period: 1.2)
            for step in 0...120 {
                let frame = note.frame(at: now.addingTimeInterval(Double(step)/100))
                assert((0...150).contains(frame.brightness) && (0...255).contains(frame.hue))
            }
            note.pattern = 1
            assert(note.frame(at: now).brightness == 150)
            assert(note.frame(at: now.addingTimeInterval(0.61)).brightness == 0)
        }
        let fromOff = ApolloHID.writes(baseline, previous: off)
        assert(fromOff[0].0 == 0x81 && fromOff[0].1 == [1])
        assert(fromOff[1].0 == 0x81 && fromOff[1].1 == [1])
        assert(fromOff.last!.0 == 0x81 && fromOff.last!.1 == [17])
        let delta = ApolloHID.writes(VialSettings(effect: 1, hue: 1, saturation: 2, brightness: 3, speed: 0), previous: VialSettings(effect: 1, hue: 1, saturation: 2, brightness: 4, speed: 0))
        assert(delta.count == 1 && delta[0].0 == 0x80 && delta[0].1 == [3])
        assert(fake.saves == 0)
        print("Vial notification state machine: passed (replacement, cancellation, manual edits, worker/USB failure, off state, cycles)")
    }
    static func tryTick(_ engine: VialNotificationEngine, _ generation: String, _ now: Date) -> Bool {
        do { return try engine.tick(generation: generation, now: now) } catch { fatalError("\(error)") }
    }
}
