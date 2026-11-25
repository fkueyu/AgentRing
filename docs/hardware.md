# Hardware

[中文](hardware.zh.md) · [English](hardware.md)

For end-to-end installation (daemon, app, hooks, provisioning and verification)
see [Installation](installation.md).

## Bill of materials

- ESP32-C3 development board (4 MB flash tested; native USB-Serial/JTAG).
- 24 × WS2812B ring, 5 V.
- 5 V / 2 A supply for the ring (do **not** power the ring from 3.3 V).
- 330 Ω series resistor on DIN; 74AHCT125 level shifter recommended for 3.3 V → 5 V.
- 1000 µF electrolytic + 0.1 µF ceramic across the ring supply; common ground.

## Wiring

| Signal | Connection |
|---|---|
| Ring DIN | **GPIO10** on the ESP32-C3 |
| Onboard LED | GPIO3 (currently not driven) |
| Ring 5V | External 5 V supply positive |
| Ring GND | Supply negative + ESP32 GND |
| Ring DOUT | Not connected for a single 24-LED ring |

Avoid strapping pins GPIO2/8/9 and the USB pins GPIO18/19. GPIO10 is the data
pin used by this build; change `LED_GPIO` in `config.h` if your board differs.

## Firmware layout

```text
firmware/esp32/agentring_ring/
├── agentring_ring.ino   setup/loop, provisioning, portal routes, serial commands
├── leds.h / leds.cpp    RMT WS2812B output and offline/config fallbacks
├── portal_ui.h/.cpp     captive-portal HTML
├── ring_client.h/.cpp   mDNS discovery and raw TCP frame stream
└── config.h             optional compile-time Wi-Fi, static host, GPIO, timing
```

Wi-Fi is configured at runtime, not compiled in:

- On boot, credentials are loaded from NVS. If none exist, or the saved network
  cannot be reached, the device starts a SoftAP named `AgentRing-XXXX` (last
  four MAC digits) and a captive portal at `http://192.168.4.1/`.
- The portal scans 2.4 GHz networks, lets you pick by number or type a hidden
  SSID, then saves the credentials and closes the AP.
- Serial fallback at 115200 baud:

```text
wifi            serial provisioning
wifi portal     start the SoftAP again
wifi status     show SSID / IP / RSSI / MAC
wifi clear      erase saved Wi-Fi
info            LED pin/count, frame interval, Wi-Fi state, portal URL
reboot
```

`config.h` still supports `WIFI_SSID` / `WIFI_PASS` as a compile-time fallback.
Leave them empty for the normal flow. `AP_PASSWORD` empty means an open setup
AP; set it if you want a password.

## Build and flash

Use Arduino IDE 2.x with **esp32 by Espressif 3.x**, or the CLI bundled with the
IDE:

```sh
CLI="/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli"
FQBN="esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app"

"$CLI" compile --fqbn "$FQBN" firmware/esp32/agentring_ring
"$CLI" upload -p /dev/cu.usbmodemXXXX --fqbn "$FQBN" firmware/esp32/agentring_ring
```

- **USB CDC On Boot: Enabled** is required for `Serial` over the native USB port.
- **Huge APP (3 MB No OTA)** keeps the image around 35% of flash.
- The board auto-resets into the ROM bootloader; if upload stalls at
  “Connecting…”, hold BOOT and tap RST.
- `Serial` is 115200. The boot banner prints `LED: GPIO10 x24, frame 33ms`.

## Troubleshooting

| Symptom | Check |
|---|---|
| Ring stays dark | 5 V supply, common ground, DIN on GPIO10, 330 Ω, `info` over serial |
| Ring shows blue breathing instead of agent colours | `curl http://<mac>:7801/health` — `streamClients` should be 1 and `streamFrames` should grow ~30/s; allow TCP 7802 through the firewall |
| Ring not found after moving the Mac | mDNS chooses a same-subnet IPv4; if the Mac moved networks, give it a static IP via `AGENTRING_HOST` |
| Portal does not pop up | Connect to `AgentRing-XXXX`, open `http://192.168.4.1/` manually |
| Upload can’t find the board | Replug USB; use a data cable; check `/dev/cu.usbmodem*` |
| Colours look swapped | Verify the RGB → GRB conversion; the code uses GRB for WS2812B |
| Ring freezes after daemon restart | The firmware drops a short stream read and reconnects automatically; verify `streamClients=1` and `streamFrames` growing in `/health` |
| Ring stutters or flashes | First check `streamClients=1` and `streamFrames` ≈30/s; if the stream is stable, check the 5 V supply/ground, the 330 Ω data resistor and level shifter, and try a lower `currentLimitMa` |

## Enclosure

A printable enclosure for the ring and the ESP32-C3 board lives in
[`hardware/enclosure/`](../hardware/enclosure/): three STLs per version, the
Blender source, preview renders and print/assembly notes. Use
[hardware/README.md](../hardware/README.md) for the version summary.

## Safety

The ring can draw ~1.44 A at full white. Use a dedicated 5 V supply, keep the
ESP32 and ring grounds common, and never power 24 LEDs from the 3.3 V rail.
