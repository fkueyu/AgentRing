// leds.cpp — WS2812B RMT output and offline/config-mode fallbacks.

#include <Arduino.h>
#include <math.h>

#include "driver/rmt_tx.h"
#include "config.h"
#include "leds.h"

static rmt_channel_handle_t s_channel = nullptr;
static rmt_encoder_handle_t s_encoder = nullptr;
static uint8_t s_grb[LED_COUNT * 3];

void ledsBegin() {
  rmt_tx_channel_config_t tx = {};
  tx.gpio_num = (gpio_num_t)LED_GPIO;
  tx.clk_src = RMT_CLK_SRC_DEFAULT;
  tx.resolution_hz = 10 * 1000 * 1000;  // 10 MHz -> 0.1us/tick
  tx.mem_block_symbols = 64;
  tx.trans_queue_depth = 2;
  ESP_ERROR_CHECK(rmt_new_tx_channel(&tx, &s_channel));

  rmt_bytes_encoder_config_t bytes = {};
  bytes.bit0.level0 = 1; bytes.bit0.duration0 = 3;  // T0H 0.3us
  bytes.bit0.level1 = 0; bytes.bit0.duration1 = 9;  // T0L 0.9us
  bytes.bit1.level0 = 1; bytes.bit1.duration0 = 9;  // T1H 0.9us
  bytes.bit1.level1 = 0; bytes.bit1.duration1 = 3;  // T1L 0.3us
  bytes.flags.msb_first = 1;
  ESP_ERROR_CHECK(rmt_new_bytes_encoder(&bytes, &s_encoder));
  ESP_ERROR_CHECK(rmt_enable(s_channel));
}

// 输入 RGB，输出 GRB（WS2812B 的字节序）。
void ledsShow(const uint8_t *rgb) {
  for (int i = 0; i < LED_COUNT; i++) {
    s_grb[i * 3 + 0] = rgb[i * 3 + 1];
    s_grb[i * 3 + 1] = rgb[i * 3 + 0];
    s_grb[i * 3 + 2] = rgb[i * 3 + 2];
  }
  rmt_transmit_config_t tx = {};
  tx.loop_count = 0;
  rmt_transmit(s_channel, s_encoder, s_grb, sizeof(s_grb), &tx);
  rmt_tx_wait_all_done(s_channel, 50);
}

// 断网兜底：暗蓝慢呼吸，至少看得出设备还活着。
void showOffline(uint32_t now) {
  static uint8_t rgb[LED_COUNT * 3];
  float phase = (now % 4000) / 4000.0f;
  float level = 0.04f + 0.10f * (0.5f + 0.5f * sinf(phase * 2 * PI));
  for (int i = 0; i < LED_COUNT; i++) {
    rgb[i * 3 + 0] = (uint8_t)(30 * level);
    rgb[i * 3 + 1] = (uint8_t)(45 * level);
    rgb[i * 3 + 2] = (uint8_t)(160 * level);
  }
  ledsShow(rgb);
}

// 配网模式：紫色呼吸，和断网（蓝色）区分开。
void showConfigMode(uint32_t now) {
  static uint8_t rgb[LED_COUNT * 3];
  float phase = (now % 2000) / 2000.0f;
  float level = 0.08f + 0.25f * (0.5f + 0.5f * sinf(phase * 2 * PI));
  for (int i = 0; i < LED_COUNT; i++) {
    rgb[i * 3 + 0] = (uint8_t)(110 * level);
    rgb[i * 3 + 1] = (uint8_t)(45 * level);
    rgb[i * 3 + 2] = (uint8_t)(190 * level);
  }
  ledsShow(rgb);
}

// 当前该显示哪种兜底动画：配网模式紫色，其余蓝色。
void showStatus(uint32_t now, bool portal) {
  if (portal) {
    showConfigMode(now);
  } else {
    showOffline(now);
  }
}
