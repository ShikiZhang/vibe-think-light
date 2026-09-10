// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
@main struct HardwareTest {
 static func main() throws {
  let transport = KLTTransport()
  let devices = transport.devices()
  guard devices.count == 1 else { throw LightError.message("Hardware test requires exactly one compatible keyboard") }
  let device = devices[0].id
  func send(_ command: UInt8, _ state: LightState = LightState(), seconds: Double = 5) throws -> LightState {
   try transport.transact(LightProtocol.request(command, state: state, seconds: seconds, pattern: 1, sequence: UInt8.random(in: 1...254)), deviceID: device)
  }
  let baseline = try send(1)
  guard !baseline.notifying else { throw LightError.message("Wait until the current notification ends") }
  defer { do { _ = try send(2, baseline) } catch { fputs("RESTORE FAILED: \(error)\n", stderr) } }
  var adjusted = baseline; adjusted.brightness = baseline.maxBrightness / 2
  let changed = try send(2, adjusted)
  guard changed.brightness == adjusted.brightness, changed.effect == baseline.effect else { throw LightError.message("SET acknowledgment did not match") }
  let readBack = try send(1)
  guard readBack == changed else { throw LightError.message("Read-after-write mismatch") }
  _ = try send(2, baseline)
  var notice = baseline; notice.hue = 85; notice.saturation = 255; notice.brightness = min(100, baseline.maxBrightness)
  let notified = try send(3, notice, seconds: 5)
  guard notified.notifying, notified.effect == baseline.effect, notified.brightness == baseline.brightness else { throw LightError.message("Notification baseline mismatch") }
  Thread.sleep(forTimeInterval: 5.4)
  let restored = try send(1)
  guard restored == baseline else { throw LightError.message("Automatic restoration did not match original settings") }
  _ = try send(2, baseline)
  let verified = try send(1)
  guard verified == baseline else { throw LightError.message("Final restoration mismatch") }
  let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
  print(String(decoding: try encoder.encode(baseline), as: UTF8.self))
  print("PASS: real USB SET/GET acknowledgment, temporary notification, firmware automatic restoration; no EEPROM write")
 }
}
