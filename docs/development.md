# Development

[中文](development.zh.md) · [English](development.md)

## Prerequisites

- macOS 14+ (the app and LaunchAgent helpers are macOS-specific).
- Node.js 22+.
- Xcode command line tools (`swift`, `swiftc`, `iconutil`, `sips`).
- Python 3 + Pillow for `macos/make-icon.py`.
- Arduino IDE 2.x + esp32 core 3.x for firmware work.
- DeepSeek Harness CLI for plugin development (`dsh`).

## Setup

```sh
git clone <repo-url> AgentRing
cd AgentRing
npm test
npm start
```

The daemon is dependency-free: Node's built-in `http`, `fs` and `node:test` are
enough. The app is a Swift Package under `macos/`.

## Localization

The app ships Simplified Chinese and English. Static copy lives in
`macos/Resources/{en,zh-Hans}.lproj/Localizable.strings`, keyed by the Chinese
source string; `build.sh` copies both `.lproj` folders into the app bundle.
Strings assembled at runtime (counts, statuses, daemon-provided effect labels)
go through `L10n` in `Sources/AgentRing/Localization.swift`. When adding copy,
update both `.strings` files and run the app with `AGENTRING_LANGUAGE=en` to
check the English layout.

## Tests

```sh
npm test                  # daemon + DSH plugin suites
```

The suite covers the state machine, event mapping, config sanitization, the v2
→ v3 palette migration, split layouts, palette/effect ranges, agent install
detection, the bridge installers and the HTTP API (including loopback-only
reads, preview overrides and config reset). Add a regression test before fixing
a bug in `daemon/src/`.

For the app:

```sh
swift build -c release --package-path macos
./macos/build.sh
```

The build script compiles the SPM executable, packages `Info.plist`, generates
the icon and ad-hoc signs `dist/AgentRing.app`.

## Daemon development

- `daemon/src/state.mjs` — event vocabulary, state machine, TTLs.
- `daemon/src/frame.mjs` — pure renderer: layout, accent palettes, effects,
  gamma, power budget.
- `daemon/src/config.mjs` — v3 schema, defaults, v1/v2 migration, sanitization.
- `daemon/src/server.mjs` — HTTP routes, auth boundaries, persistence triggers.
- `daemon/src/persist.mjs` — atomic `state.json` writes.
- `daemon/src/host.mjs` — Codex desktop liveness probe.
- `daemon/src/sources.mjs` — per-agent install/bridge detection for `/sources`.
- `daemon/src/protocol.mjs` — shared constants.

Run the daemon in the foreground while editing:

```sh
node daemon/bin/agentringd.mjs --port 7801
```

## macOS app development

Swift files live in `macos/Sources/AgentRing/`:

- `AgentRingApp.swift` — menu bar scene, settings window, app delegate.
- `DaemonModel.swift` — `/state` (1.5 s), `/health` (3 s), config debounce.
- `SettingsView.swift` — four-page sidebar shell; `PreviewTab` (ring + session
  list), `LightingTab`, `SourcesTab` and `GeneralTab` hold the pages.
- `DesignSystem.swift` — cards, page headers, sliders, choice tiles and the ring
  stage shared by every page; `SettingsControls.swift` keeps session rows and
  badges.
- `LightingTab.swift` — the lighting studio shell: persistent live preview rail,
  section bar and the four contextual overview cards; `LightingPanels.swift`
  holds the display / standby / layout / states panels and the palette tile.
- `SourcesTab.swift` — install/connection status per agent, source toggles and
  colours, and the one-click hook installer (with a copy fallback).
- `RingLayerView.swift` — 24 CALayers driven by `/frame` at 30 fps. A preview
  override (`POST /preview`) makes `/frame` show the audited effect, so the rail
  and the physical ring stay in sync.
- `Theme.swift` — colours, labels, SF Symbols.

For screenshots and specific-page diagnosis, launch the app with
`AGENTRING_TAB=options` (or `sources`), `AGENTRING_LIGHTING_SECTION=states` and (optionally)
`AGENTRING_MOTION_PREVIEW=thinking:breathe`. `AGENTRING_LANGUAGE=en` previews the
English interface without changing the saved preference, and
`AGENTRING_WINDOW_HEIGHT=1150` makes a long page fit one screenshot.
`AGENTRING_BASE=http://127.0.0.1:7803`
points the app at a lab daemon so the live ring is untouched.

The app is a menu-bar utility (`LSUIElement`), so it has no Dock icon. If the
menu-bar icon is hidden, allow AgentRing in macOS “Menu Bar” settings and in any
menu-bar manager (Thaw, Bartender, Ice).

## DSH plugin development

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

The profile stores a symlink to this checkout. After editing `index.js`, restart
DSH or toggle the bundle off/on in Plugins. Verify tool-level events:

```sh
grep -c 'ingest dsh/tool-start' ~/.agentring/daemon.log
```

The plugin talks only to `127.0.0.1:7801`; no credentials are involved.

## Firmware development

See [Hardware](hardware.md) for wiring and flashing. Compile before committing:

```sh
arduino-cli compile --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" \
  firmware/esp32/agentring_ring
```

Do not commit `.bin` artifacts. If the serial command set or NVS keys change,
update `docs/hardware.md` and `CHANGELOG.md`.

## Style and commits

- Two-space JavaScript, four-space Swift, two-space C++.
- Keep pure logic in `daemon/src/` so it can be tested without HTTP or timers.
- Use `fix(area): …` / `feat(area): …` commit subjects; explain *why* in the body.
- CI runs `npm test` (daemon + DSH plugin), a Swift build and an ESP32 firmware
  compile; run the same locally before opening a PR.
- Do not commit Wi-Fi credentials, tokens or signing material.

## Documentation

- `README.md` (Chinese) and `README.en.md` (English) are the entry points and
  quick start; keep both in sync with the UI.
- `docs/installation.md` / `docs/installation.zh.md` own deployment, upgrade,
  uninstall and setup troubleshooting; `docs/usage.md` / `docs/usage.zh.md` own
  the interface and daily behaviour.
- Every explanatory document has an English and Chinese version; update both in
  the same change. `CHANGELOG.md` remains the English release log.
- `docs/configuration.md` / `docs/configuration.zh.md` and the relevant ADR must
  change with any config field, route or rendering rule.
- Screenshots live in `docs/images/`. Rebuild the app first so the version in the
  sidebar is current, then use the env hooks below for a deterministic capture.

## Release checklist

1. Set `VERSION`, move `CHANGELOG.md` `[Unreleased]` into a dated `[x.y.z]`
   section, update the supported-version table in `SECURITY.md`, then
   `npm run version:sync`.
2. `npm test` and `npm run version:check`.
3. `swift build -c release --package-path macos && ./macos/build.sh`, install the
   app and confirm the sidebar/About show the new app and daemon versions
   (`/health.version`).
4. Firmware compile; flash and verify `/health` `streamFrames ≈ 30/s`.
5. Refresh the screenshots and any doc that mentions the version or the UI.
6. Tag the release; attach a zipped `AgentRing.app` if distributing.
