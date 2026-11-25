# AgentRingCore

[中文](README.zh.md) · [English](README.md)

Swift port of AgentRing's state model, shared by the App Store app. The first
slice is the per-session state machine; the frame renderer, HTTP/TCP server and
demo clock follow.

```sh
swift test --package-path macos/AgentRingCore
```

The store accepts the same unified event vocabulary as the daemon
(`session-start`, `turn-start`, `tool-start`, `tool-end`, `waiting`, `turn-end`,
`error`, `session-end`, `control`) and implements the daemon's done hold, stale
fallback, idle TTL, session-end grace and out-of-order guards.
