// SPDX-License-Identifier: GPL-2.0-or-later
// KLT1 protocol: fixed 32-byte reports; see PROTOCOL.md.
#include "keyboard_light.h"
#include "raw_hid.h"
#include <string.h>

static bool notifying;
static uint64_t baseline;
static uint32_t started, last_frame;
static uint16_t duration, notice_period;
static uint8_t notice_hue, notice_sat, notice_val, notice_pattern;

static uint8_t mode_for(uint8_t effect) {
    switch (effect) {
        case 0: return RGBLIGHT_MODE_STATIC_LIGHT + effect - 0;
#ifdef RGBLIGHT_EFFECT_BREATHING
        case 1 ... 4: return RGBLIGHT_MODE_BREATHING + effect - 1;
#endif
#ifdef RGBLIGHT_EFFECT_RAINBOW_MOOD
        case 5 ... 7: return RGBLIGHT_MODE_RAINBOW_MOOD + effect - 5;
#endif
#ifdef RGBLIGHT_EFFECT_RAINBOW_SWIRL
        case 8 ... 13: return RGBLIGHT_MODE_RAINBOW_SWIRL + effect - 8;
#endif
#ifdef RGBLIGHT_EFFECT_SNAKE
        case 14 ... 19: return RGBLIGHT_MODE_SNAKE + effect - 14;
#endif
#ifdef RGBLIGHT_EFFECT_KNIGHT
        case 20 ... 22: return RGBLIGHT_MODE_KNIGHT + effect - 20;
#endif
#ifdef RGBLIGHT_EFFECT_CHRISTMAS
        case 23: return RGBLIGHT_MODE_CHRISTMAS + effect - 23;
#endif
#ifdef RGBLIGHT_EFFECT_STATIC_GRADIENT
        case 24 ... 33: return RGBLIGHT_MODE_STATIC_GRADIENT + effect - 24;
#endif
#ifdef RGBLIGHT_EFFECT_RGB_TEST
        case 34: return RGBLIGHT_MODE_RGB_TEST + effect - 34;
#endif
#ifdef RGBLIGHT_EFFECT_ALTERNATING
        case 35: return RGBLIGHT_MODE_ALTERNATING + effect - 35;
#endif
#ifdef RGBLIGHT_EFFECT_TWINKLE
        case 36 ... 41: return RGBLIGHT_MODE_TWINKLE + effect - 36;
#endif
        default: return 0;
    }
}

static uint8_t effect_for(uint8_t mode) {
    for (uint8_t i = 0; i < 42; ++i) if (mode_for(i) && mode_for(i) == mode) return i;
    return 255; // A variant selected with the keyboard's own Fn keys.
}

static void indicator(bool suppressed) {
#if defined(RGBLIGHT_LAYERS) && defined(KBL_CAPSLOCK_LAYER)
    rgblight_set_layer_state(KBL_CAPSLOCK_LAYER, !suppressed && host_keyboard_led_state().caps_lock);
#endif
}

bool keyboard_light_indicator_allowed(void) { return !notifying; }

void keyboard_light_cancel(void) {
    if (!notifying) return;
    notifying = false;
    rgblight_update_qword(baseline);
    indicator(false);
}

void keyboard_light_task(void) {
    if (!notifying) return;
    uint32_t elapsed = timer_elapsed32(started);
    if (elapsed >= duration) { keyboard_light_cancel(); return; }
    if (timer_elapsed32(last_frame) < 20) return;
    last_frame = timer_read32();
    uint8_t val = notice_val, hue = notice_hue;
    if (notice_pattern == 1) val = (elapsed % notice_period < notice_period / 2) ? notice_val : 0;
    if (notice_pattern == 2) {
        uint16_t phase = elapsed % notice_period;
        uint16_t half = notice_period / 2;
        uint16_t level = (uint32_t)(phase < half ? phase : notice_period - phase) * 1000 / half;
        val = (uint32_t)notice_val * (150 + level * 850 / 1000) / 1000;
    }
    if (notice_pattern == 3) {
        uint16_t phase = (elapsed % notice_period) * 1600 / notice_period;
        val = (phase < 160 || (phase >= 320 && phase < 480)) ? notice_val : 0;
    }
    if (notice_pattern == 4) {
        uint16_t phase = (elapsed % notice_period) * 1800 / notice_period, level = 0;
        if (phase < 300) level = phase < 150 ? phase * 1000 / 150 : (300 - phase) * 1000 / 150;
        else if (phase >= 420 && phase < 720) level = phase < 570 ? (phase - 420) * 700 / 150 : (720 - phase) * 700 / 150;
        val = (uint32_t)notice_val * level / 1000;
    }
    if (notice_pattern == 5) hue = notice_hue + (elapsed % notice_period) * 256 / notice_period;
    if (notice_pattern == 6) val = elapsed % notice_period < notice_period / 2 ? notice_val : 0;
    rgblight_sethsv_noeeprom(hue, notice_pattern == 5 ? 255 : notice_sat, val);
}

void keyboard_light_receive(uint8_t *data, uint8_t length) {
    if (length != 32 || memcmp(data, "KLT1", 4) != 0) return;
    uint8_t command = data[4], error = 0;
    rgblight_config_t current = {.raw = rgblight_read_qword()};
    switch (command) {
        case 1: break; // Read state only.
        case 2: { // Set normal appearance; never writes EEPROM implicitly.
            uint8_t mode = data[7] == 255 ? (notifying ? ((rgblight_config_t){.raw = baseline}).mode : current.mode) : mode_for(data[7]);
            if (data[6] > 1 || !mode) { error = 2; break; }
            keyboard_light_cancel();
            current.raw = rgblight_read_qword();
            current.enable = data[6]; current.mode = mode;
            current.hue = data[8]; current.sat = data[9];
            current.val = data[10] > RGBLIGHT_LIMIT_VAL ? RGBLIGHT_LIMIT_VAL : data[10];
            rgblight_update_qword(current.raw);
            break;
        }
        case 3: { // Temporary appearance; replacement notifications share one baseline.
            uint16_t requested = data[11] | ((uint16_t)data[12] << 8);
            uint16_t period = data[14] | ((uint16_t)data[15] << 8);
            if (!requested || requested > 60000 || data[13] > 6 || (period && (data[13] == 0 || period < 500 || period > 10000))) { error = 2; break; }
            if (!notifying) baseline = current.raw;
            notifying = true; duration = requested;
            started = timer_read32(); last_frame = started - 20;
            notice_hue = data[8]; notice_sat = data[9];
            notice_val = data[10] > RGBLIGHT_LIMIT_VAL ? RGBLIGHT_LIMIT_VAL : data[10];
            static const uint16_t default_periods[] = {2000, 800, 2000, 1600, 1800, 4000, 2400};
            notice_pattern = data[13]; notice_period = period ? period : default_periods[notice_pattern];
            current.enable = true; current.mode = RGBLIGHT_MODE_STATIC_LIGHT;
            current.hue = notice_hue; current.sat = notice_sat; current.val = notice_val;
            indicator(true);
            rgblight_update_qword(current.raw);
            keyboard_light_task();
            break;
        }
        case 4: keyboard_light_cancel(); break;
        case 5:
            if (notifying) { error = 3; break; }
            eeconfig_update_rgblight_current();
            break;
        case 6: // Restore previously explicitly saved settings.
            keyboard_light_cancel(); rgblight_reload_from_eeprom();
            rgblight_update_qword(rgblight_read_qword()); // Also render saved power-off state.
            break;
        default: error = 1; break;
    }
    rgblight_config_t settings = {.raw = notifying ? baseline : rgblight_read_qword()};
    uint8_t reply[32] = {'K', 'L', 'T', '1', command | 0x80, data[5], error};
    reply[7] = settings.enable; reply[8] = effect_for(settings.mode);
    reply[9] = settings.hue; reply[10] = settings.sat; reply[11] = settings.val;
    reply[12] = RGBLIGHT_LIMIT_VAL; reply[13] = RGBLIGHT_LED_COUNT > 255 ? 255 : RGBLIGHT_LED_COUNT;
    for (uint8_t i = 0; i < 42; ++i) if (mode_for(i)) {
        uint8_t byte = i < 16 ? 14 + i / 8 : 20 + (i - 16) / 8;
        reply[byte] |= 1 << (i % 8);
    }
    reply[16] = notifying; reply[17] = host_keyboard_led_state().caps_lock;
    uint32_t elapsed = timer_elapsed32(started);
    uint16_t remaining = notifying && elapsed < duration ? duration - elapsed : 0;
    reply[18] = remaining; reply[19] = remaining >> 8;
    reply[25] = 1; // Adjustable notification period supported.
    reply[24] = 0x7F; // Notification patterns 0–6.
    raw_hid_send(reply, sizeof(reply));
}
