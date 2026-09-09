// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <stdint.h>
#include <stdbool.h>
#define RGBLIGHT_LIMIT_VAL 150
#define RGBLIGHT_LED_COUNT 6
#define RGBLIGHT_LAYERS
#define KBL_CAPSLOCK_LAYER 0
#define RGBLIGHT_EFFECT_BREATHING
#define RGBLIGHT_EFFECT_RAINBOW_MOOD
#define RGBLIGHT_EFFECT_RAINBOW_SWIRL
#define RGBLIGHT_EFFECT_SNAKE
#define RGBLIGHT_EFFECT_KNIGHT
#define RGBLIGHT_EFFECT_STATIC_GRADIENT
#define RGBLIGHT_MODE_STATIC_LIGHT 1
#define RGBLIGHT_MODE_BREATHING 2
#define RGBLIGHT_MODE_RAINBOW_MOOD 6
#define RGBLIGHT_MODE_RAINBOW_SWIRL 9
#define RGBLIGHT_MODE_SNAKE 15
#define RGBLIGHT_MODE_KNIGHT 21
#define RGBLIGHT_MODE_STATIC_GRADIENT 25
typedef union { uint64_t raw; struct { bool enable:1; bool velocikey:1; uint8_t mode:6; uint8_t hue,sat,val,speed; }; } rgblight_config_t;
typedef struct { bool caps_lock; } led_t;
uint64_t rgblight_read_qword(void);
void rgblight_update_qword(uint64_t);
void rgblight_sethsv_noeeprom(uint8_t,uint8_t,uint8_t);
void rgblight_set_layer_state(uint8_t,bool);
void eeconfig_update_rgblight_current(void);
void rgblight_reload_from_eeprom(void);
led_t host_keyboard_led_state(void);
uint32_t timer_read32(void);
uint32_t timer_elapsed32(uint32_t);

#define RGBLIGHT_EFFECT_CHRISTMAS
#define RGBLIGHT_EFFECT_RGB_TEST
#define RGBLIGHT_EFFECT_ALTERNATING
#define RGBLIGHT_EFFECT_TWINKLE
#define RGBLIGHT_MODE_CHRISTMAS 24
#define RGBLIGHT_MODE_RGB_TEST 35
#define RGBLIGHT_MODE_ALTERNATING 36
#define RGBLIGHT_MODE_TWINKLE 37
