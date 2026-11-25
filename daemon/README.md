# AgentRing daemon

[中文](README.zh.md) · [English](README.md)

The local bridge daemon: ingests agent events, keeps one record per session,
renders the ring and serves the HTTP API on `127.0.0.1:7801`.

```sh
npm start                 # from this directory
# or from the repository root:
node daemon/bin/agentringd.mjs --port 7801
```

| Path | Purpose |
|---|---|
| `bin/agentringd.mjs` | Entry point: listen on `0.0.0.0:7801`, advertise mDNS |
| `bin/agentring-hook.sh` | Optional curl shim for Codex hooks |
| `src/state.mjs` | Event vocabulary, state machine, TTLs |
| `src/frame.mjs` | Pure 24×RGB renderer |
| `src/config.mjs` | v2 config, themes, sanitization |
| `src/server.mjs` | HTTP routes and persistence triggers |
| `src/stream.mjs` | Persistent 72-byte TCP frame stream on port 7802 |
| `src/persist.mjs` | Atomic `state.json` writes |
| `src/host.mjs` | Codex Desktop liveness probe |
| `src/protocol.mjs` | Shared constants |
| `test/` | `node --test` suite |
| `preview/index.html` | Browser preview served at `/` |

Configuration and API details: [docs/configuration.md](../docs/configuration.md).
