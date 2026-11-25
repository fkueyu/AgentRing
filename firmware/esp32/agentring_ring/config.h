#pragma once

// ---- 网络 ----
// Wi-Fi 通过串口配置并保存在 NVS，不需要改这里。
// 如果想让固件自带一份兜底配置（例如没有 NVS 的板子），可以填下面两项；
// 留空时首次启动会提示用串口执行 `wifi` 配网。
#define WIFI_SSID ""
#define WIFI_PASS ""
#define WIFI_CONNECT_TIMEOUT_MS 15000

// 配网热点：没连上 Wi-Fi 时自动开启。SSID 会加 MAC 后缀，例如 AgentRing-A7F2。
// AP_PASSWORD 留空 = 开放热点（配网页只在配网期间存在）。
#define AP_SSID_PREFIX "AgentRing"
#define AP_PASSWORD ""

// Mac 的地址。留空则用 mDNS 自动发现局域网里的 AgentRing daemon
// （服务类型 _agentring._tcp）。发现失败时才回退到这里的静态 IP。
#define AGENTRING_HOST ""
// Daemon TCP frame stream (72-byte RGB frames over one connection).
#define AGENTRING_STREAM_PORT 7802

// ---- 硬件 ----
#define LED_GPIO 10         // 灯环 DIN（实物接 IO10；避开 strapping 2/8/9 和 USB 18/19）
#define LED_COUNT 24

// 板载单色 LED（IO3）目前不驱动，留给以后做配网/连接状态指示。
// 需要时再打开，并按板子确认极性：
// #define STATUS_LED_GPIO 3
// #define STATUS_LED_ACTIVE_LOW 0

// ---- 行为 ----
#define FRAME_INTERVAL_MS 33   // ~30 fps（圆环扫动更顺滑）
#define STREAM_READ_TIMEOUT_MS 2000
#define OFFLINE_AFTER_FAILURES 5
