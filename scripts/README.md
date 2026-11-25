# Scripts

[中文](README.zh.md) · [English](README.md)

User-level install helpers for macOS. All scripts are idempotent and safe to
re-run after moving the checkout.

| Script | What it does |
|---|---|
| `install-daemon.mjs` | Writes `~/Library/LaunchAgents/com.agentring.daemon.plist` pointing at `daemon/bin/agentringd.mjs`; bootouts/bootstraps it |
| `install-app.mjs` | Writes `com.agentring.app.plist` for `/Applications/AgentRing.app`; a clean quit stays quit, a crash is relaunched |
| `install-codex-hooks.mjs` | Optional: merges the 7 Codex hook events into `~/.codex/hooks.json` (backs up first; `--uninstall`/`--dry-run`) |
| `install-claude-hooks.mjs` | Optional: merges the Claude hook events (including `StopFailure` for the error state) into `~/.claude/settings.json`, preserving other hooks (backs up first; `--uninstall`/`--dry-run`) |
| `sync-version.mjs` | Keeps package versions in sync with the root `VERSION` file (`--check` for CI) |
| `build-firmware.mjs` | Compiles the ring firmware and publishes the app/merged USB images plus a SHA-256 manifest under the website `public/agentring/firmware/` |

The daemon LaunchAgent uses the stable Homebrew `node` wrapper when available,
so `brew upgrade node` does not break the job.

`install-app.mjs` expects the app at `/Applications/AgentRing.app` (override with
`AGENTRING_APP`); run `./macos/build.sh` and copy the bundle there first. Both
launchd helpers accept `--uninstall`.

The hook installers are also available from npm:

```sh
npm run install:codex     # or uninstall:codex
npm run install:claude    # or uninstall:claude
```

The app's Sources page can run the same installers with one click; the daemon only
executes the scripts listed in `BRIDGE_INSTALLERS` in `daemon/src/sources.mjs`.
