# Architecture

[中文](architecture.zh.md) · [English](architecture.md)

AgentRing has one job: turn local agent activity into a small, legible light
signal. Everything is optimized for that path being short, observable and
testable.

## Components

| Component | Path | Responsibility |
|---|---|---|
| Daemon | `daemon/` | Accept events, keep per-session state, render 24 RGB LEDs, serve HTTP |
| DSH plugin | `packages/dsh-plugin/` | Translate DeepSeek Harness lifecycle/tool events into daemon events |
| Codex hooks | `daemon/bin/agentring-hook.sh` + `scripts/install-codex-hooks.mjs` | Optional curl-based adapter (not installed by default) |
| macOS app | `macos/` | Menu-bar presence, preview, session list, display settings, ring health |
| Firmware | `firmware/esp32/agentring_ring/` | Wi-Fi provisioning, mDNS discovery, persistent TCP frame stream, WS2812 output |
| Preview | `daemon/preview/index.html` | Browser fallback for debugging without the app |

## Data flow

```text
DSH plugin ── HTTP POST /ingest ──┐
Codex hooks ── curl ──────────────┤
                                  ▼
                          daemon/src/state.mjs
                                  │ snapshot
                                  ▼
                          daemon/src/frame.mjs
                                  │ 72 bytes
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
        macos app preview     browser preview      ESP32 TCP stream
        (URLSession 30 fps)   (canvas 20 fps)      (72B @30 fps)
```

The daemon is the only renderer. The app and the firmware both read the same
`renderFrame` bytes (the App over HTTP `/frame`, the ESP32 over the TCP stream),
so a firmware change cannot drift from the preview at the algorithm level. The app adds a glow/opacity presentation layer for the screen;
the physical strip shows raw 8-bit RGB.

## State model

`daemon/src/state.mjs` exposes a tiny vocabulary:

```text
session-start | turn-start | thinking | tool-start | tool-end
waiting | turn-end | error | session-end | control
```

A record is keyed by `source:sessionId` (falling back to cwd) and contains
`source`, `sessionId`, `cwd`, `label`, `tool`, `state`, `since`, `updated` and
`ended`. `snapshot()` applies the time-based transitions:

- `done` becomes `idle` after `doneHoldSeconds`.
- A working session (`thinking` / `tool` / `editing`) with no event for
  `staleMinutes` degrades to `idle`; `waiting` is exempt because a permission
  prompt can legitimately wait for hours.
- `session-end` keeps a finished record for a short grace period so the ring does
  not flicker when a desktop agent closes its hook session every turn.
- A heartbeat (`control`) only refreshes `updated`; it never creates or revives a
  session.

Priority for the ring is `waiting > error > editing > tool > thinking > done > idle`.

## Rendering

`daemon/src/frame.mjs` is pure: a snapshot + config + `now` goes in, a
`Uint8Array(72)` comes out.

- **Layout**: `split` divides the ring between the top N sessions, `focus` shows
  the most urgent one, `rotate` cycles one at a time.
- **Effects**: `pulse`, `breathe`, `solid`, `comet` (Orbit), `blink`, `flash`
  and `patches` (Raindrops). The comet uses a sub-LED Gaussian head and smoothstep
  tail so the peak slides between LEDs instead of snapping.
- **Colour**: one accent palette decides the running look — identity palettes
  (`state`, `source`), curated ramps spread around the ring, or the rainbow hue
  wheel. Waiting/done/error always keep their semantic state colour.
- **Power**: `currentLimitMa` scales the whole frame down when the estimated
  WS2812 current exceeds the budget.
- **Standby**: motion (`dot`, `orbit`, `breathe`) and colour (`mono` plus the
  shared curated ramps and `rainbow`) are separate axes. Orbit uses a fractional
  head and short tail; breathe overlaps consecutive breaths. Only mono exposes a
  colour well. The legacy `rainbow` mode migrates to `orbit` + the rainbow
  palette.
- **Night mode**: a local-time window multiplies the frame brightness down.
- **Effect preview**: `GET /preview?state=&effect=` renders one synthetic agent
  frame through the same pipeline. `POST /preview` installs that state/effect as
  a temporary override (TTL, refreshed by the app) that `/frame` and the 7802
  stream serve, so the physical ring mirrors the audition; `DELETE /preview`
  restores the live snapshot. The rail always reads `/frame`, so it cannot drift
  from the ring.

All output is 8-bit RGB. The firmware converts to GRB and hands the buffer to
the ESP32 RMT peripheral.

## Source detection

`daemon/src/sources.mjs` is a small registry of probes, one per agent tool. A
probe answers two independent questions: is the tool installed (an app bundle, a
data directory, a CLI), and is the bridge installed (a DSH profile bundle plus
its `node_modules` link, a Codex / Claude hooks file plus the hook shim)? It
reads files only. Missing hooks can be installed from the page: the daemon runs
AgentRing's own installer script (registered per source) and re-probes, while a
probe's display command (such as DSH's package-manager command) stays copy-only.

The running DSH desktop profile is parsed from the host process arguments, so a
plugin installed in a different profile than the active one is reported as a
mismatch instead of a false success. `GET /sources` is loopback-only because the
payload contains local paths; the Sources page joins it with `/state` to show
current sessions. Adding an agent later means one probe plus a label; `/ingest`
stays the generic, tool-agnostic event contract.

## DSH plugin

The plugin is a Host plugin; it runs in the DSH process and sends fire-and-forget
HTTP events to `127.0.0.1:7801`:

- `agent/created` → `session-start`
- `agent/status` → `thinking` while running, `turn-end` when idle
- `tools/pre-execute` / `tools/post-execute` → `tool-start` / `thinking`
- `approval/request` → `waiting`, then `thinking` after the decision
- `user-questions/request` → `waiting`, then `thinking` after the answer
- `agent/error` → `error`
- `agent/disposed` → `session-end`

Every 30 seconds it reconciles `ctx.agents.list()` with `/state` and sends a
heartbeat for known sessions. One keep-alive socket preserves event order and
avoids a TCP handshake per transition. Host plugins have no HMR: restart DSH or
toggle the bundle off/on after editing `index.js`.

## macOS app

`macos/Sources/AgentRing/` is a native SwiftUI menu-bar app:

- `AgentRingApp.swift` — `MenuBarExtra`, settings window, app delegate.
- `DaemonModel.swift` — polls `/state` every 1.5 s, `/health` every 3 s, fetches
  `/capabilities` on connect, pushes config changes with a 350 ms debounce and
  computes active/waiting/error counts.
- `AgentRingSession.swift` — ephemeral URLSession with no cache/cookies. A shared
  CFNetwork session makes macOS take short `PreventUserIdleSystemSleep`
  assertions on every request; a status app should not keep the Mac awake.
- `SettingsView.swift` — four-page sidebar shell (Preview, Lights, Sources,
  General). Preview keeps the ring hero on top and the live session list below;
  Lights keeps a live ring rail and splits its controls into display, standby,
  layout and states (accent palette + per-state effect/speed + timing); Sources
  holds per-agent install/bridge status, the on-ring toggle and the colour well.
- `RingLayerView.swift` — preview renderer using `/frame` and 24 CALayers.
- `Theme.swift` — state labels/symbols/colours and the menu-bar icon.
- `MenuBarIcon.swift` — loads the build-generated template ring for the menu bar.

The app never reads agent internals directly; it is a view over the daemon API.
`ringConnected` is derived from `/health` LAN frame counters, so “daemon is up”
and “the physical ring is receiving frames” are separate states.

## Firmware

`firmware/esp32/agentring_ring/` is an Arduino sketch for the ESP32-C3, split
into `leds`, `portal_ui` and `ring_client` modules:

- Loads Wi-Fi credentials from NVS; if none or a connection fails, starts a
  SoftAP + captive portal at `192.168.4.1`.
- Resolves `_agentring._tcp` with mDNS and chooses a **same-subnet IPv4** (the
  Mac may also expose bridge/Tailscale addresses).
- Connects once to the daemon's raw TCP frame stream on port 7802 and reads
  72-byte frames continuously; there is no HTTP request per frame.
- Reconnects on a short read; a daemon restart or network drop cannot strand
  the ring.
- Converts RGB → GRB and drives the strip through the ESP-IDF RMT peripheral.
- Falls back to a dim offline pattern when Wi-Fi or the daemon is unavailable.

See [Architecture decisions](decisions.md) for the polling, firmware HTTP and OTA tradeoffs.
