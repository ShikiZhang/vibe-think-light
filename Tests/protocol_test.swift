// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import AppKit
@main struct ProtocolTests {
 static func main() throws {
  let packet = LightProtocol.request(3, seconds: 60, sequence: 73)
  precondition(packet.count == 32 && packet[11] == 96 && packet[12] == 234 && packet[5] == 73)
  precondition(LightProtocol.request(3, seconds: .nan).count == 32)
  var reply = [UInt8](repeating: 0, count: 32)
  reply.replaceSubrange(0..<4, with: Array("KLT1".utf8));reply[4]=0x81;reply[5]=73
  reply[7]=1;reply[8]=5;reply[9]=85;reply[10]=255;reply[11]=75;reply[12]=150;reply[13]=6;reply[14]=255;reply[15]=255;reply[20]=255;reply[21]=255;reply[22]=255;reply[23]=3
  let state = try LightProtocol.parse(reply, command: 1, sequence: 73)
  precondition(state.percent == 50 && state.effect == 5 && state.effectMask == (1 << 42) - 1 && state.ledCount == 6)
  precondition(state.notificationMask == 7) // Legacy firmware advertises zero.
  reply[24] = 127
  let extended = try LightProtocol.parse(reply, command: 1, sequence: 73)
  precondition(extended.notificationMask == 127)
  for pattern in 0...6 {
    let notice = LightProtocol.request(3, state: state, seconds: 15, pattern: pattern)
    precondition(notice[13] == pattern && notice[11] == 152 && notice[12] == 58)
  }
  precondition(!extended.adjustableNotificationTiming)
  reply[25] = 1
  let timed = try LightProtocol.parse(reply, command: 1, sequence: 73)
  precondition(timed.adjustableNotificationTiming)
  let customCycle = LightProtocol.request(3, seconds: 5, pattern: 2, period: 1.2)
  precondition(customCycle[14] == 176 && customCycle[15] == 4 && customCycle[11] == 136 && customCycle[12] == 19)
  func rejected(_ packet: [UInt8], _ seq: UInt8 = 73) {
   do { _ = try LightProtocol.parse(packet, command: 1, sequence: seq); fatalError("accepted invalid response") } catch {}
  }
  rejected(Array(reply.dropLast()));rejected(reply, 74)
  var bad=reply;bad[6]=3;rejected(bad);bad=reply;bad[12]=0;rejected(bad);bad=reply;bad[11]=151;rejected(bad)
  let black = LightProtocol.applying(try LightProtocol.color("#000000"), to: state)
  precondition(black.brightness == 0)
  let green = LightProtocol.applying(try LightProtocol.color("#00FF00"), to: state)
  precondition(abs(green.hue - 85) <= 1 && green.saturation == 255 && green.brightness == 75)
  do { _ = try LightProtocol.color("bad");fatalError("accepted invalid color") } catch {}
  print("PASS: Swift protocol encoding, response validation, sequence matching, brightness, color parsing")
 }
}
