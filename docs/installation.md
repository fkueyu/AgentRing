# Installation and deployment

[中文](installation.zh.md) · [English](installation.md)

AgentRing has four pieces. You can install only the first one and use the
browser preview, but the ring needs all four.

| Component | Runs on | Purpose |
|---|---|---|
| `agentringd` daemon | Mac | State machine, renderer, HTTP API and frame stream |
| AgentRing.app | Mac | Menu-bar status, settings and preview |
| Agent integrations | Mac | Report agent activity to the daemon |
| ESP32-C3 ring | LAN | The physical 24-LED display |

For daily use see [Using AgentRing](usage.md); for the config and HTTP reference
see [Configuration](configuration.md).

## Requirements

- macOS 14 or newer (daemon, app and hook installers are macOS-specific).
- Node.js 22+ (`node --version`).
- Xcode command line tools for `swift build`.
- Python 3 with Pillow for the app icon (`python3 -m pip install pillow`).
- For firmware: Arduino IDE 2.x with **esp32 by Espressif 3.x**, or an
  `arduino-cli` with the same core.
- Hardware: ESP32-C3 board, 24 × WS2812B ring, 5 V supply, wiring as described in
  [Hardware](hardware.md).

Optional: DeepSeek Harness, ChatGPT/Codex and Claude Code for agent reporting.

```sh
git clone <repo-url> AgentRing
cd AgentRing
node --version        # v22+
npm test              # daemon + DSH plugin tests, no dependencies to install
```

## 1. Start the daemon

Foreground, for a first look:

```sh
npm start             # http://127.0.0.1:7801
curl -s http://127.0.0.1:7801/health
```

Background (recommended), via a user LaunchAgent:

```sh
node scripts/install-daemon.mjs
# logs: ~/.agentring/daemon.log
```

`/health` returns the daemon version, session count, ring stream counters and
the active preview (if any). The browser preview is at
`http://127.0.0.1:7801/` and shows the same bytes the ring receives.

The daemon and the hook installers share `~/.agentring/`:

| Path | Purpose |
|---|---|
| `config.json` | Display/layout/motion/source configuration (v3) |
| `state.json` | Last sessions, restored after a restart |
| `daemon.log` | launchd stdout/stderr, capped at 10 MB on startup |
| `hook.sh` / `hook.log` | Shared hook shim installed by the Codex/Claude installers |

The daemon binds `0.0.0.0:7801` (HTTP) and `0.0.0.0:7802` (raw frames). Only
`/frame`, `/health` and the 7802 stream are reachable from the LAN; `/state`, `/config`, `/sources`, preview mutations and
all writes are loopback-only. There is no authentication or TLS, so keep the
ports inside a trusted network. See [SECURITY.md](../SECURITY.md).

## 2. Build and install the macOS app

```sh
./macos/build.sh
cp -R dist/AgentRing.app /Applications/
open /Applications/AgentRing.app
```

`build.sh` compiles the Swift Package, writes `Info.plist` (version from
`VERSION`), generates the icon and ad-hoc signs the bundle. The app is a
menu-bar utility (`LSUIElement`), so it has no Dock icon.

Keep it running across logins (optional but recommended):

```sh
node scripts/install-app.mjs
```

If the menu-bar icon is hidden, allow AgentRing in macOS **System Settings → Menu
Bar** and in menu-bar managers such as Thaw, Bartender or Ice. The settings
window opens with `⌘,` or from the menu-bar menu.

The build is ad-hoc signed. That is fine for a locally built app; distributing a
binary to other Macs needs Developer ID signing and notarization.

Verify: the sidebar shows “Daemon connected”, and **Preview** draws the ring. The
version is shown at the bottom of the sidebar and in **General → About** (app and
daemon versions separately).

## 3. Connect agents

![Sources page](images/settings-sources.png)

Open the **Sources** page. It detects installed tools and their AgentRing bridge,
and can install the bridge for Codex and Claude Code with one click.

### DeepSeek Harness

The DSH plugin is a local bundle in this checkout:

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

Restart DSH, or toggle the bundle off/on in **Plugins**. The Sources page should
report **Wired** for DeepSeek Harness. Events can be verified with:

```sh
grep -c 'ingest dsh/' ~/.agentring/daemon.log
```

Use the profile that your DSH app actually runs (`desktop` for the desktop app);
the detection page lists every profile that has the bundle.

### Codex

If ChatGPT/Codex is installed but its hooks are missing, the Sources page shows
**Not wired** and a **Connect** button. It merges the seven AgentRing hook events into `~/.codex/hooks.json`,
backs up the file first and leaves other hooks alone. The same command is
available from a terminal:

```sh
npm run install:codex       # node scripts/install-codex-hooks.mjs
npm run uninstall:codex
```

Codex may ask once for hook trust on the next run; approve it. The hooks only
fire for locally executed tasks — cloud tasks run on the remote side and never
call local hooks.

### Claude Code

Claude Code uses the same hook payload shape, with its own settings file:

```sh
npm run install:claude      # node scripts/install-claude-hooks.mjs
npm run uninstall:claude
```

The installer merges into `~/.claude/settings.json`, keeps existing hooks
(including other integrations such as CodeIsland), writes a timestamped backup
and is idempotent. The Sources page offers the same action as **Connect**. Claude
Code may ask once to trust the new hooks.

Claude Code reports start/running/waiting/done and failed turns through
`StopFailure`, so the red error state works for Claude sessions too.

### Other agents

Any tool that can run a local command can report events:

```sh
curl -sS -X POST 'http://127.0.0.1:7801/ingest?source=myagent' \
  -H 'content-type: application/json' \
  -d '{"event":"thinking","session_id":"demo","cwd":"/tmp/demo","tool":"bash"}'
```

`event` is one of `session-start`, `turn-start`, `tool-start`, `tool-end`,
`waiting`, `turn-end`, `error`, `session-end` or `control` (liveness). Use a
`source` that already exists under `sources` in the config to get its colour and
a switch on the Sources page; an unknown source still renders with the default
colour. Events are loopback-only, so the adapter must run on the same Mac. See
[Configuration](configuration.md#configuration-groups).

## 4. Build and provision the ring

Wire the board and ring as described in [Hardware](hardware.md): ring DIN to
**GPIO10**, common ground, 5 V for the ring, 330 Ω in series and a level shifter
if needed.

Compile and flash (Arduino IDE 2.x or its bundled CLI):

```sh
CLI="/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli"
FQBN="esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app"

"$CLI" compile --fqbn "$FQBN" firmware/esp32/agentring_ring
"$CLI" upload  -p /dev/cu.usbmodemXXXX --fqbn "$FQBN" firmware/esp32/agentring_ring
```

On first boot the board starts a setup AP `AgentRing-XXXX` (channel 6) with a
captive portal at `http://192.168.4.1/`. Pick the 2.4 GHz network, save, and the
portal closes. Serial fallback at 115200:

```text
wifi            serial provisioning
wifi portal     start the setup AP again
wifi status     show SSID / IP / RSSI / MAC
wifi clear      erase saved Wi-Fi
info            LED pin/count, frame interval, Wi-Fi state, portal URL
reboot
```

The ring discovers the daemon over mDNS (`_agentring._tcp`) and picks a
same-subnet IPv4. If discovery is unreliable, set a static address:

```c
// firmware/esp32/agentring_ring/config.h
#define AGENTRING_HOST "192.168.1.20"
```

The ring and the Mac must share a subnet, and the Mac firewall must allow the
ring to reach TCP `7802` and mDNS. Verify:

```sh
curl -s http://127.0.0.1:7801/health | python3 -m json.tool
# streamClients: 1, streamFrames grows ~30/s, streamLastFrameFrom = ring IP
```

The app's **General → Connection** card shows the ring IP and fps.

## 5. Verification checklist

- [ ] `curl /health` reports `ok: true`, a version and a growing `streamFrames`.
- [ ] The sidebar shows “Daemon connected” and “Ring online”.
- [ ] **Sources** shows at least one **Wired** for the agents you use.
- [ ] **Preview** lists sessions and the ring shows their colours/motion.
- [ ] **Lighting → States** previews an effect on both the screen and the physical ring.
- [ ] The menu-bar item shows the active count and attention icons.

## 6. Upgrade

```sh
git pull
npm run version:check
npm test
./macos/build.sh
cp -R dist/AgentRing.app /Applications/       # quit the app first
node scripts/install-app.mjs                  # restart the LaunchAgent
launchctl kickstart -k gui/$(id -u)/com.agentring.daemon
```

Config v2 (AgentRing 0.2.x) is migrated to v3 automatically on the next daemon
start and rewritten in place; the old theme/colour-mode fields are dropped and
the visible look is preserved. Back up `~/.agentring/config.json` before a
cross-minor upgrade if you have custom colours. Hook installs and the DSH plugin
are independent of the daemon version; restart DSH if you updated the plugin.

## 7. Uninstall

```sh
node scripts/install-claude-hooks.mjs --uninstall    # if installed
node scripts/install-codex-hooks.mjs --uninstall     # if installed
node scripts/install-app.mjs --uninstall
node scripts/install-daemon.mjs --uninstall
rm -rf /Applications/AgentRing.app
rm -rf ~/.agentring                                  # config, state, logs, hook shim
```

Remove the DSH bundle from **Plugins** (or `dsh plugin --profile desktop remove
@local/agentring-dsh`). To decommission the ring, run `wifi clear` over serial
and reflash or erase the board.

## 8. Troubleshooting

| Symptom | Check |
|---|---|
| Daemon not running | `launchctl print gui/$(id -u)/com.agentring.daemon` and `tail -50 ~/.agentring/daemon.log` |
| App shows “Daemon offline” | `curl http://127.0.0.1:7801/health`; another process may own 7801 |
| Ring dark | 5 V supply, common ground, GPIO10, 330 Ω, `info` over serial |
| Ring shows the blue offline pattern | `/health` `streamClients` should be 1; allow TCP 7802 and mDNS through the Mac firewall; ring and Mac on the same subnet |
| Codex/Claude shows Not wired after install | Re-run detection; confirm the hooks file contains `.agentring/hook.sh`; check the tool's hook-trust prompt |
| Hooks fire but the ring stays idle | `tail ~/.agentring/hook.log` for the shim log and HTTP status; ensure the daemon is listening on 7801 |
| Gatekeeper blocks the app | Right-click → Open, or `xattr -dr com.apple.quarantine /Applications/AgentRing.app` |
| Ring stuck on a preview | Close the settings window or wait 45 s; `curl -X DELETE http://127.0.0.1:7801/preview` |
