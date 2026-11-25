// leds.h — LED output used by the sketch.

#pragma once

#include <stdint.h>

void ledsBegin();
void ledsShow(const uint8_t *rgb);
void showOffline(uint32_t now);
void showConfigMode(uint32_t now);
void showStatus(uint32_t now, bool portal);
