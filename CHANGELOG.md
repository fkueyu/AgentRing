# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Added

- `AgentRingCore`, a Swift 6 port of the daemon state model. The first slice is
  the per-session state machine with tests for the done hold, stale fallback,
  session-end grace, out-of-order guards and persistence.
- Hardware photos of the assembled 24-LED ring and the PCB dimensions under
  `hardware/photos/`, linked from both hardware guides and used on the website.
- `scripts/build-firmware.mjs` builds the USB app/merged images and publishes a
  SHA-256 manifest under the website's `/agentring/firmware/` path.
- An Xcode App Store target (`macos/AgentRing.xcodeproj`) with App Sandbox,
  network/USB entitlements, Hardened Runtime, a privacy manifest, an asset
  catalog and the AppIcon. This is build scaffolding: the self-contained Swift
  daemon and USB firmware flasher are still being ported, so do not submit it
  yet. The existing `build.sh` direct-download build is unchanged.

### Changed

- The macOS app, `AgentRingCore` and the Xcode App Store target now use the
  Swift 6 language mode.
- Documentation is now bilingual: the root README, every guide under `docs/`,
  the component READMEs, the enclosure print/assembly notes, `CONTRIBUTING`,
  `SECURITY` and `CODE_OF_CONDUCT` have Chinese and English versions. The
  official site is linked from the README and the repository homepage.

## [0.4.0] - 2026-11-25

A bilingual interface and a more comfortable sidebar header.

### Added

- The app interface can switch between Simplified Chinese and English in
  **通用 → 语言**, or follow the system language. The choice applies immediately
  and is saved per user; it does not affect the daemon or the ring protocol.

### Fixed

- The sidebar logo and title now use the same wider inset as the navigation
  icons, instead of sitting against the window edge.

## [0.3.0] - 2026-11-25

One palette model, a Sources page that detects and installs agent bridges, and
effect previews that mirror to the physical ring.

### Added

- The Sources page is its own sidebar section (⌘3): it detects whether
  DeepSeek Harness / Codex / Claude Code are installed, and whether AgentRing is
  connected (a DSH profile plugin, a Codex / Claude hooks file). Missing hooks
  can be installed with one click: the daemon runs AgentRing's own installer
  (`scripts/install-codex-hooks.mjs`, new
  `scripts/install-claude-hooks.mjs`), which merges into the tool's config,
  keeps existing hooks and writes a timestamped backup. The Claude installer
  includes `StopFailure`, so failed turns reach the red error state. The command is still
  shown for manual use, and DSH's package-manager command stays copy-only. New
  agents are added by registering one probe and, optionally, one installer in
  `daemon/src/sources.mjs`.
- The state table previews the selected state/effect in the left ring rail and
  on the physical ring through the daemon's preview override. Each effect option
  carries a one-line hint, and the done/stale timing controls use steppers
  instead of tick-marked sliders.
- Dev-only screenshot hooks: `AGENTRING_WINDOW_HEIGHT` fits a long page into one
  capture, and `AGENTRING_BASE` points the app at a lab daemon so the live ring
  is untouched.

### Changed

- Effect previews in 灯光 → 状态 now mirror to the physical ring. The daemon
  holds a temporary preview override (`POST /preview`) that `/frame` and the TCP
  stream serve; the app refreshes its 45 s TTL every 15 s while auditioning and
  `DELETE`s it when the preview closes, the section changes or the window goes
  away. The ring rail also reads `/frame`, so the screen and the hardware cannot
  disagree; a preview that outlives its client expires and returns to live.
- Source toggles and colours moved off 灯光 → 状态 to the new 来源 page, and the
  lighting page is colour + motion only. 通用 moves to ⌘4, so the sidebar is now
  four pages (⌘1 预览, ⌘2 灯光, ⌘3 来源, ⌘4 通用).
- Colour is now one vocabulary instead of four. `display.accent` picks what a
  running session is coloured by — 状态色 / 来源色 / the curated 霓虹、日落、薄荷、
  极光、暖光 ramps / 彩虹 — and the idle ring picks from the same catalogue
  (单色 + the same ramps and rainbow). Waiting, done and error always keep their
  reminder colour, whatever the accent is. Selecting a palette is a value change
  and never rewrites other fields.
- The Lights page is down to four sections: 显示 / 待机 / 布局 / 状态. Colour and
  motion now share the 状态 section — one accent picker, then one row per state
  with its effect and speed, then the source list and timing — so the two are no
  longer edited on separate pages. The colour wells shown are only the ones the
  renderer actually reads: six state wells for 状态色, three reminder wells for a
  ramp, and per-source wells only under 来源色. The old 主题, 色彩模式 and
  单色用色 controls are gone.
- The rail's overview card follows the selection: accent swatches plus the three
  reminder states, and the layout schematic now uses the accent palette instead
  of always drawing the six state colours.
- Standby no longer conflates motion with colour: 单点转圈 and 彩虹转圈 drew the
  identical comet, so they are merged into one 巡游 mode. Standby colour lives in
  the shared palette catalogue (单色 / 霓虹 / 日落 / 薄荷 / 极光 / 暖光 / 彩虹),
  and the colour well only appears for 单色. Legacy `standby: "rainbow"` configs
  migrate to 巡游 + 彩虹 and keep their look.
- Layout uses equal-width segmented pickers for 最多分段 (1–8) and 分段间隔
  (0–3) instead of sliders; rotate/hold/stale duration sliders snap to whole
  seconds or minutes. Fractional legacy values are normalized to integers.
- Motion presets are now per-state: 彗星 is renamed 巡游, 随机读写 is renamed
  雨滴, and 常亮 is offered only for done/error. Thinking moves from 脉冲 to
  呼吸; tool offers 呼吸/巡游/脉冲; editing offers 雨滴/脉冲; waiting keeps
  呼吸/闪烁. Effects removed from a state migrate to its new default.
- 雨滴 (`patches`) now follows WLED's 1D Rain instead of random breathing
  patches: drops spawn at random offsets, drift clockwise with short fading
  trails, and each split segment gets its own phase.
- Motion speed is now per-state (`motion.speeds.<state>`): every row in the
  state table has its own 0.2–3.0× control, and standby speed is independent of
  motion speed. The old global `motion.tempo` is removed; a v1 config seeds the
  per-state values from it once.
- The macOS settings window is now a 920×680 sidebar app with a calm neutral
  palette, a vector brand mark, live daemon/ring status in the sidebar and a
  hidden title bar that keeps the chrome seamless in light and dark mode.
  Keyboard shortcuts (⌘1–⌘4) switch pages.
- The Lights page is a lighting studio instead of a ten-section scrolling form:
  a persistent live ring rail with a section-specific overview, full-width
  sliders, palette tiles and a state table instead of a wall of pickers.
- Preview is a two-column hero with a state-tinted aura around the ring; Sessions
  and General share the same card layout, page headers and alignment.
- The separate Sessions page was folded into Preview: the ring hero moved up and
  the lower half now holds the live session list, so Sessions no longer needs a
  sidebar entry of its own.
- The ESP32 config portal now runs on 2.4 GHz channel 6 instead of the default
  channel 1. The setup AP sits inches from the ring, so sharing channel 1 with
  the router could mask the router's 2.4 GHz BSSID and jam the ring's own
  station association attempts. The portal log now prints its channel.

### Removed

- Configuration v3 drops `display.theme`, `display.colorMode`,
  `display.gradientTo`, `display.solidColorBy` and `motion.tempo`. v2 configs
  are migrated on load by following the result that was actually visible
  (rainbow → rainbow; a gradient built from a curated theme → that ramp;
  otherwise the state/source palette that was in use). The file is rewritten in
  place once on the next daemon start.

### Fixed

- Custom source colours never reached the LEDs. `renderFrame` passed a single
  hex string to `colorFor`, which expects a `{source: hex}` map, so every source
  silently fell back to its brand colour. Configured hexes now win, with the
  brand colour only as the fallback.
- Selecting 薄荷 or 霓虹 while 单色 / 按状态 was active changed nothing visible:
  the theme only rewrote source colours and the colour mode, neither of which
  the renderer read in that combination. The v3 accent palette makes every
  selection immediately visible.
- The DSH bridge now reports `waiting` for approvals and `ask_user_question`.
  `approval/request` and `user-questions/request` are waterfall events, and the
  desktop forwarding answerer was registered before the plugin, so the bridge's
  observer never ran. It now registers with `prepend` and delegates with
  `next()`, keeping the client as the actual answerer.

## [0.2.0] - 2026-11-24

### Added

- Runtime Wi-Fi provisioning: an `AgentRing-XXXX` SoftAP, captive portal at
  `http://192.168.4.1/`, and serial commands (`wifi`, `wifi portal`,
  `wifi status`, `wifi clear`, `info`, `reboot`).
- Ring-liveness status in the app (`/health` LAN frame counters) and an fps
  readout in the preview.
- Preview attention chips for waiting approvals and errors; menu-bar hand/alert
  indicators and project-first session labels.
- Destructive-action confirmations for clearing sessions and restoring defaults.
- Sub-LED comet head, deeper pulse/breathe troughs, and a 30 fps frame loop.
- Comet background is much darker so the rotating head stands out.
- File editing uses a new `patches` effect: a quiet 0.05/0.04 ambient floor
  with two or three adjacent LEDs breathing at random offsets on large
  segments, and one or two on small segments.
- The preview, `/state`, `/config` and all mutations are loopback-only; only
  `/frame` and `/health` are reachable from the LAN.
- Config reset is daemon-owned (`POST /config/reset`), so the app no longer
  overwrites the full source palette with its offline fallback.
- Effect IDs, labels and defaults now come from `daemon/src/effects.mjs`; the
  app fetches them through `GET /capabilities` instead of duplicating pickers
  and labels in Swift.
- Added HTTP integration tests for local/LAN route access, `/config/reset`,
  `/capabilities`, malformed JSON and oversized bodies.
- CI now compiles the ESP32 firmware with the documented FQBN and cached core.
- Split the 700-line SettingsView into per-tab files plus shared controls.
- Split the ESP32 sketch into `leds`, `portal_ui` and `ring_client` modules;
  `agentring_ring.ino` now only owns setup/loop, provisioning and serial commands.
- Added a single `VERSION` source; `npm run version:sync` updates package
  versions and the app build reads it for `Info.plist`.
- Recorded transport and firmware decisions (polling, blocking /frame, local-only
  control plane) in `docs/decisions.md`.
- Added configurable standby modes: a single static dot, a single-colour orbit,
  a rainbow orbit, or a randomly positioned breathing dot; selectable in the app.
- Random breathing crossfades: the next LED starts while the previous breath is
  nearly out, and `standbySpeed` controls orbit and breath speed.
- Standby dot/orbit colours are configurable; orbit/rainbow use a fractional
  head and a short tail so rotation no longer looks like discrete jumps.
- `/health` reports `lanLastFrameFrom`; the app shows the ring IP in General.
- Replaced per-frame HTTP polling with a persistent raw TCP frame stream on
  port 7802; firmware reads 72-byte frames continuously and reconnects on a
  short read. The App still uses `/frame` for its preview.
- Paced firmware display to 33 ms, drops stale buffered frames, tolerates 2 s
  stream stalls, and excludes localhost test clients from ring liveness.
- App icon generated from the brand ring in `macos/Resources/Logo.png`.
- Menu bar item uses a template silhouette of the brand ring, generated at build time.
- Settings uses one page tint across all tabs; Sessions is a grouped form like
  Lights/General. The preview uses a narrow circular track, with the LEDs on
  its centreline and their glow spilling over both edges.

### Changed

- Repository reorganized into `daemon/`, `macos/`, `packages/dsh-plugin/`,
  `firmware/esp32/`, `scripts/` and `docs/`; the macOS app now builds with SPM.
- Settings tab renamed from “设置” to “灯光”; unused sources collapse into a
  disclosure group; gamma/stale controls have explanatory captions.
- `/state` no longer carries the full config; the app fetches `/config` on
  connect, and `/health` is polled for ring liveness.
- Mutating daemon endpoints are loopback-only and CORS wildcards were removed.

### Fixed

- `/frame` now sends `Content-Length`; the firmware also accepts chunked
  responses, so the ring actually receives 72-byte frames.
- mDNS resolution picks a same-subnet IPv4 instead of `0.0.0.0` or a Tailscale
  address on multi-interface Macs.
- A failed `/frame` request drops the stale keep-alive client, so the ring
  recovers after a daemon restart.
- Stale sessions now degrade after `staleMinutes`; `waiting` is exempt.
- An errored turn stays red until the next turn instead of turning green.
- Split layouts distribute leftover LEDs evenly (5 agents: 4/4/4/4/3).
- Full-config posts from the app apply a newly selected theme.
- Normal app quit no longer gets relaunched by launchd.

## [0.1.0] - 2026-11-23

Initial local prototype: state daemon, 24-LED renderer, preview page, Codex hooks,
DSH Host plugin, native SwiftUI menu-bar app and ESP32-C3 firmware.
