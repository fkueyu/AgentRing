# 固件

[中文](README.zh.md) · [English](README.md)

`esp32/agentring_ring/` 是驱动 24 颗 WS2812B 灯环的 ESP32-C3 Arduino 工程（sketch）。
它拆成了几个小模块：

| 文件 | 职责 |
|---|---|
| `agentring_ring.ino` | 初始化/主循环、Wi-Fi 配网页面、串口命令 |
| `leds.h` / `leds.cpp` | RMT 输出和离线/配置模式兜底 |
| `portal_ui.h` / `portal_ui.cpp` | 配网页面 HTML |
| `ring_client.h` / `ring_client.cpp` | mDNS 发现和持久 TCP 帧流 |
| `config.h` | 板子/主机/时序默认值 |

- LED 数据：**GPIO10**
- 板载 LED：GPIO3（未驱动）
- 帧格式：来自守护进程 TCP 帧流（端口 7802）的 72 字节 RGB
- Wi-Fi：NVS 凭据 + SoftAP/配网页面；串口后备

接线、供电、编译和烧录说明见 [docs/hardware.zh.md](../docs/hardware.zh.md)。编译检查：

```sh
arduino-cli compile \
  --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" \
  esp32/agentring_ring
```
