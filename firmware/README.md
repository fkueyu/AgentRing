# Firmware

`esp32/agentring_ring/` is an Arduino sketch for an ESP32-C3 driving a
24-LED WS2812B ring. The sketch is split into small modules:

| File | Responsibility |
|---|---|
| `agentring_ring.ino` | Setup/loop, Wi-Fi provisioning portal, serial commands |
| `leds.h` / `leds.cpp` | RMT output and offline/config-mode fallbacks |
| `portal_ui.h` / `portal_ui.cpp` | Captive-portal HTML |
| `ring_client.h` / `ring_client.cpp` | mDNS discovery and persistent TCP frame stream |
| `config.h` | Board/host/timing defaults |

- LED data: **GPIO10**
- Onboard LED: GPIO3 (not driven)
- Frame format: 72 bytes RGB from the daemon's TCP frame stream (port 7802)
- Wi-Fi: NVS credentials + SoftAP/captive-portal provisioning; serial fallback

See [docs/hardware.md](../docs/hardware.md) for wiring, power, build and flash
instructions. Compile check:

```sh
arduino-cli compile \
  --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" \
  esp32/agentring_ring
```
