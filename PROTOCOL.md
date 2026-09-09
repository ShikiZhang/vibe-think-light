# Keyboard Light USB protocol, KLT1

Think6.5 V3 only (USB VID `0x4753`, PID `0x4003`). Native HID, vendor usage page `0xFF60`, usage `0x62`, 32-byte output/input reports, no report-ID byte. The Mac application opens only this collection. Firmware must explicitly implement this protocol; ordinary QMK, VIA or Vial firmware is not automatically compatible.

All multibyte integers are little-endian. Reserved bytes must be zero. Requests with wrong magic or length are ignored. Other errors receive a response. No command enters Boot or changes key bindings.

Request bytes:

| Bytes | Meaning |
|---|---|
| 0–3 | ASCII KLT1 |
| 4 | Command: 1 status, 2 set, 3 notify, 4 cancel, 5 save, 6 reload saved |
| 5 | Sequence, echoed in response |
| 6 | Normal power, 0 or 1, for set |
| 7 | Stable effect ID 0–41; 255 preserves current mode |
| 8–10 | Hue, saturation, brightness, each 0–255; firmware clamps brightness to board limit |
| 11–12 | Notification duration in ms, 1–60000 |
| 14–15 | Optional animation period in ms, 500–10000; zero keeps the style default; solid rejects nonzero periods |
| 13 | Notification pattern: 0 solid, 1 blink, 2 breathe, 3 double flash, 4 heartbeat, 5 rainbow, 6 slow blink |

Response bytes:

| Bytes | Meaning |
|---|---|
| 0–3 | ASCII KLT1 |
| 4 | Request command OR 0x80 |
| 5 | Echoed sequence |
| 6 | Error: 0 success, 1 unknown command, 2 unsupported/invalid argument, 3 saving during notification |
| 7–11 | Normal power, stable effect ID, hue, saturation, brightness |
| 12 | Board brightness limit |
| 13 | LED count (up to 255) |
| 14–15 | Supported-effect bitmask bits 0–15 |
| 16 | Notification active, 0 or 1 |
| 17 | Host Caps Lock state, 0 or 1 |
| 18–19 | Remaining notification ms |
| 20–23 | Supported-effect bitmask bits 16–47 |
| 24 | Notification support bitmask, bits 0–6. Zero means legacy firmware supporting only 0–2. |
| 25 | Bit 0: custom notification cycle supported |

Stable IDs match the complete standard QMK RGBLight catalog, zero-based: 0 static; 1–4 breathing; 5–7 rainbow mood; 8–13 rainbow swirl; 14–19 snake; 20–22 knight; 23 Christmas; 24–33 static gradient; 34 RGB test; 35 alternating; 36–41 twinkle. Each range retains QMK's original variant order. The firmware maps these IDs to the compiled QMK enum, so disabling an effect does not shift protocol IDs. The application filters using the returned mask. See `keyboardlight effects` for exact CLI names.

SET changes RAM only. SAVE explicitly persists the normal state; built-in Fn controls retain their original QMK persistence behavior. Notifications capture the full RGBLight config (including power, mode, HSV, speed) once. Replacement notifications retain that baseline. Timeout, CANCEL, or a manual underglow key restores it; a subsequent SET applies a new normal state. Restoration restarts the built-in animation and does not preserve its phase. Normal state is reported while a notification is active. Notifications temporarily suppress the Think6.5 V3 Caps Lock overlay, then restore its current host state.

Scope: this repository supports Think6.5 V3 RGBLight only. It does not implement RGB Matrix, VIA/Vial key remapping, or arbitrary keyboard support. The custom Raw HID collection uses usage `0x62` instead of VIA’s default `0x61`. No HTTP server or network listener is used.

Default cycles (ms): blink 800, breathe 2000, double 1600, heartbeat 1800, rainbow 4000, slow blink 2400. Setting a custom cycle scales the whole animation while keeping its shape/duty cycle. Duration is independent. Solid has no animation cycle.
