// SPDX-License-Identifier: GPL-2.0-or-later
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "quantum.h"
#include "../Firmware/keyboard_light.h"
static rgblight_config_t config;
static uint64_t saved;
static uint32_t now;
static unsigned writes, replies;
static bool caps, indicator_on;
static uint8_t response[32];
uint64_t rgblight_read_qword(void) { return config.raw; }
void rgblight_update_qword(uint64_t raw) { config.raw = raw; }
void rgblight_sethsv_noeeprom(uint8_t h,uint8_t s,uint8_t v) { config.hue=h;config.sat=s;config.val=v; }
void rgblight_set_layer_state(uint8_t layer,bool on) { assert(layer==0);indicator_on=on; }
void eeconfig_update_rgblight_current(void) { writes++; saved=config.raw; }
void rgblight_reload_from_eeprom(void) { config.raw=saved; }
led_t host_keyboard_led_state(void) { return (led_t){.caps_lock=caps}; }
uint32_t timer_read32(void) { return now; }
uint32_t timer_elapsed32(uint32_t start) { return now-start; }
void raw_hid_send(uint8_t *data,uint8_t length) { assert(length==32);memcpy(response,data,32);replies++; }
static void send(uint8_t command,uint8_t effect,uint8_t brightness,uint16_t duration,uint8_t pattern) {
 uint8_t p[32]={'K','L','T','1',command,77,1,effect,85,255,brightness,duration&255,duration>>8,pattern};
 keyboard_light_receive(p,32);assert(response[4]==(command|0x80));assert(response[5]==77);
}
int main(void) {
 config=(rgblight_config_t){.enable=1,.mode=6,.hue=17,.sat=33,.val=80,.speed=2};saved=config.raw;
 uint8_t bad[32]={0};keyboard_light_receive(bad,32);memcpy(bad,"KLT1",4);keyboard_light_receive(bad,31);assert(replies==0);
 send(1,0,0,0,0);assert(response[8]==5 && response[11]==80 && response[14]==255 && response[23]==3);
 send(2,0,255,0,0);assert(config.val==150 && config.mode==1 && writes==0);
 uint64_t base=config.raw;
 send(2,99,1,0,0);assert(response[6]==2 && config.raw==base);
 send(3,0,90,0,1);assert(response[6]==2 && config.raw==base);
 caps=true;indicator_on=true;
 send(3,0,90,1000,1);assert(response[16]==1 && response[11]==150 && !indicator_on && !keyboard_light_indicator_allowed());
 now+=410;keyboard_light_task();assert(config.val==0);
 send(5,0,0,0,0);assert(response[6]==3 && writes==0);
 send(3,0,60,2000,2);assert(response[11]==150);now+=2000;keyboard_light_task();assert(config.raw==base && indicator_on && keyboard_light_indicator_allowed());
 // Timer rollover, replacement restoration, and manual control cancel semantics.
 now=UINT32_MAX-100;send(3,0,100,500,1);now+=501;keyboard_light_task();assert(config.raw==base);
 send(3,0,100,1000,1);send(2,5,70,0,0);assert(response[16]==0 && config.mode==6 && config.val==70);now+=2000;keyboard_light_task();assert(config.val==70);
 send(5,0,0,0,0);assert(writes==1);base=config.raw;send(2,0,30,0,0);send(6,0,0,0,0);assert(config.raw==base && writes==1);
 config.enable=false;base=config.raw;send(3,0,80,100,0);assert(config.enable);send(4,0,0,0,0);assert(config.raw==base);
 for (uint8_t i=0;i<42;i++) { send(2,i,80,0,0);assert(response[6]==0 && response[8]==i && config.mode==i+1); }
 // New patterns preserve normal settings and restore without a running Mac process.
 base=config.raw;
 for (uint8_t pattern=0;pattern<7;pattern++) {
   send(3,0,120,5000,pattern);assert(response[6]==0 && response[24]==127 && response[16]==1);
   uint32_t start=now;
   for (uint16_t t=20;t<5000;t+=20) { now=start+t;keyboard_light_task();assert(config.val<=120); }
   now=start+5000;keyboard_light_task();assert(config.raw==base && keyboard_light_indicator_allowed());
 }
 send(3,0,120,1000,7);assert(response[6]==2 && config.raw==base);
 send(3,0,120,5000,3);uint32_t stamp=now;now=stamp+200;keyboard_light_task();assert(config.val==0);now=stamp+340;keyboard_light_task();assert(config.val==120);keyboard_light_cancel();
 send(3,0,120,5000,4);stamp=now;now=stamp+150;keyboard_light_task();assert(config.val==120);now=stamp+570;keyboard_light_task();assert(config.val==84);now=stamp+900;keyboard_light_task();assert(config.val==0);keyboard_light_cancel();
 send(3,0,120,5000,5);stamp=now;now=stamp+1000;keyboard_light_task();assert(config.hue==149 && config.val==120 && config.sat==255);keyboard_light_cancel();
 send(3,0,120,5000,6);stamp=now;now=stamp+1300;keyboard_light_task();assert(config.val==0);keyboard_light_cancel();
 assert(config.raw==base && writes==1);
 // Every animated pattern accepts a cycle independent of total duration.
 for (uint8_t pattern=1;pattern<=6;pattern++) {
  uint8_t p[32]={'K','L','T','1',3,88,1,0,85,255,120,0x70,0x17,pattern,0xB0,0x04}; // 6s total, 1.2s cycle
  keyboard_light_receive(p,32);assert(response[6]==0 && response[25]==1);
  uint32_t start=now;now=start+600;keyboard_light_task();
  if(pattern==2) assert(config.val==120);
  if(pattern==5) assert(config.hue==213);
  now=start+1200;keyboard_light_task();
  if(pattern==1 || pattern==3 || pattern==5 || pattern==6) assert(config.val==120);
  if(pattern==2) assert(config.val==18);
  if(pattern==4) assert(config.val==0);
  now=start+6000;keyboard_light_task();assert(config.raw==base);
  p[14]=0xF3;p[15]=0x01;keyboard_light_receive(p,32);assert(response[6]==2 && config.raw==base); // 499ms rejected
  p[14]=0x11;p[15]=0x27;keyboard_light_receive(p,32);assert(response[6]==2 && config.raw==base); // 10001ms rejected
  p[14]=0xF4;p[15]=0x01;keyboard_light_receive(p,32);assert(response[6]==0);keyboard_light_cancel(); // 500ms accepted
 }
 { uint8_t p[32]={'K','L','T','1',3,88,1,0,85,255,120,0x70,0x17,0,0xB0,0x04};keyboard_light_receive(p,32);assert(response[6]==2); }
 send(99,0,0,0,0);assert(response[6]==1);
 puts("PASS: firmware state, validation, no implicit EEPROM writes, notification replacement/timeout/rollover, Caps Lock restoration, manual override, saved settings");
}
