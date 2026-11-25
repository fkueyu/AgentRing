# Contributing to AgentRing

Thanks for taking the time to improve AgentRing. This project has four moving
parts; keep changes scoped so it stays easy to review and test.

## Repository layout

| Path | What it is |
|---|---|
| `daemon/` | Node.js state machine, frame renderer, HTTP API and tests |
| `macos/` | Native SwiftUI menu-bar app (Swift Package Manager) |
| `packages/dsh-plugin/` | DeepSeek Harness Host plugin |
| `firmware/esp32/agentring_ring/` | ESP32-C3 Arduino sketch |
| `scripts/` | launchd and Codex/Claude hook install helpers |
| `docs/` | Installation, usage, architecture, configuration, hardware, development and decisions |
| `tools/` | Small local utilities (ASCII ring preview, PNG renderer) |

## Requirements

- macOS 14 or newer for the app and daemon.
- Node.js 22+ for the daemon and scripts (no `npm install` is needed; the
  daemon is dependency-free).
- Xcode command line tools for `swift build`, plus Python 3 + Pillow
  (`python3 -m pip install pillow`) for the app icon pipeline.
- Arduino IDE 2.x with **esp32 by Espressif 3.x** for firmware work.
- DeepSeek Harness CLI (`dsh`) only when developing the DSH plugin.

## Setup

```sh
git clone <repo-url> AgentRing
cd AgentRing
npm test                        # daemon + DSH plugin tests
npm start                       # run the daemon on 127.0.0.1:7801
./macos/build.sh                # build dist/AgentRing.app
```

The app reads the daemon at `http://127.0.0.1:7801`. Install the user
LaunchAgents only when you want them running in the background:

```sh
node scripts/install-daemon.mjs
node scripts/install-app.mjs
```

## Code style

- **JavaScript**: ES modules, two-space indent, no semicolons are fine, but keep
  the existing style within a file. Prefer small pure functions in `daemon/src/`
  so the state machine and renderer stay testable without HTTP or timers.
- **Swift**: four-space indent, `///` documentation for non-obvious public
  behavior, `// MARK:` sections in long files. Keep the app native: no web view,
  no third-party UI dependency.
- **Firmware**: two-space indent, comments explaining hardware behavior rather
  than restating the code. Keep the sketch dependency-free beyond the official
  esp32 core.
- **Markdown**: wrap prose at a reasonable width; use relative links.
- Never commit Wi-Fi credentials, API keys, tokens or signing material. Wi-Fi is
  provisioned at runtime and stored in NVS.

## Tests

- Daemon + plugin: `npm test` (runs `daemon/test/` and
  `packages/dsh-plugin/test/`). Add a regression test for every state-machine,
  config, renderer, source-detection or installer fix.
- App: `swift build -c release --package-path macos` and a manual pass through
  **预览 / 灯光 / 来源 / 通用**.
- Firmware: `arduino-cli compile --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" firmware/esp32/agentring_ring`
  and, when hardware is available, a flash + serial check. CI does the compile
  with ESP32 core 3.3.12.

## DSH plugin changes

The plugin is installed into a DSH profile from this checkout:

```sh
dsh plugin --profile desktop add "$PWD/packages/dsh-plugin"
```

Host plugins are loaded in-process. After editing `index.js`, either restart DSH
or toggle the bundle off/on in Plugins to reload it. Verify with:

```sh
grep -c 'ingest dsh/tool-start' ~/.agentring/daemon.log
```

## Hook installer changes

Codex and Claude Code share the same hook shim (`daemon/bin/agentring-hook.sh`)
but have separate installers:

- `scripts/install-codex-hooks.mjs` → `~/.codex/hooks.json`
- `scripts/install-claude-hooks.mjs` → `~/.claude/settings.json`

Keep both installers idempotent, preserve hooks from other integrations, write a
timestamped backup before changing a file, and support `--uninstall` and
`--dry-run`. `daemon/test/installers.test.mjs` exercises the merge, idempotence
and uninstall paths; the install route is covered in
`daemon/test/server-api.test.mjs`. The Sources page can run only the scripts
listed in `BRIDGE_INSTALLERS` in `daemon/src/sources.mjs`.

## Documentation

- Update `README.md`, `docs/` and `CHANGELOG.md` for user-visible changes.
- A new config field or HTTP route belongs in `docs/configuration.md`; a design
  decision that would otherwise be re-litigated belongs in `docs/decisions.md`.
- Deployment, upgrade and setup troubleshooting belong in
  `docs/installation.md`; interface and daily behaviour belong in
  `docs/usage.md`.
- Screenshots live in `docs/images/`. Rebuild the app first so the version in the
  sidebar is current; the `AGENTRING_TAB`, `AGENTRING_BASE` and
  `AGENTRING_WINDOW_HEIGHT` hooks are documented in
  [Development](docs/development.md).
- The root README is Chinese; `docs/` is English. Keep that split unless a
  documentation overhaul is explicitly scoped.

## Firmware changes

- Keep `LED_GPIO`/`LED_COUNT` and the provisioning flow documented in
  `docs/hardware.md`.
- Compile before committing. Do not commit generated `.bin` files.
- If a change affects the serial protocol or NVS keys, call it out in the PR and
  update `CHANGELOG.md`.

## Releasing

1. Set `VERSION`, move `[Unreleased]` in `CHANGELOG.md` to a dated `[x.y.z]`
   section, update the supported-version table in `SECURITY.md`, then run
   `npm run version:sync`.
2. `npm test`, `npm run version:check`, and a release build of the app.
3. Install the app and confirm **通用 → 关于** shows the new app and daemon
   versions; flash firmware if its protocol changed.
4. Refresh screenshots and every doc that mentions the version or the UI.
5. Tag the release (`vX.Y.Z`) and attach artifacts only if you are distributing
   a signed build.

## Commits and pull requests

- Keep one logical change per commit.
- Use an imperative subject, for example `fix(daemon): keep error state until the next turn`.
- In the body explain **why**, not just what changed.
- Update `CHANGELOG.md` for user-visible changes.
- Include the commands you ran and the result in the PR description.

## License

By contributing you agree that your contribution is licensed under the MIT
License in `LICENSE`.
