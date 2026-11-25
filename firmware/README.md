# Firmware

[中文](README.zh.md) · [English](README.md)

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
instructions.

## Release build and hosting

The app downloads USB images from the official site. Build and publish both the
normal app image and the full recovery image with a SHA-256 manifest:

```sh
node scripts/build-firmware.mjs --public-dir ../web/public/agentring/firmware
```

This writes `manifest.json` plus `agentring-<version>-app.bin` (offset
`0x10000`, keeps NVS/Wi-Fi) and `agentring-<version>-merged.bin` (offset `0x0`,
blank board/recovery). The manifest is published at
`https://ainx.ink/agentring/firmware/manifest.json`.

Compile check:

```sh
arduino-cli compile \
  --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" \
  esp32/agentring_ring
```
