// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "quantum.h"
void keyboard_light_receive(uint8_t *data, uint8_t length);
void keyboard_light_task(void);
void keyboard_light_cancel(void);
bool keyboard_light_indicator_allowed(void);
