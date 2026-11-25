# AgentRing bridge

[中文](DETAIL.zh.md) · [English](DETAIL.md)

Reports the lifecycle of every live DeepSeek Harness agent to the AgentRing daemon so a
24-LED WS2812B ring can show what the machine is doing at a glance.

## What it reports

| Harness event | Ring state | Meaning |
|---|---|---|
| `agent/created` | idle | a session opened but no turn is running |
| `agent/status` → `running` | thinking | the agent is producing output or calling tools |
| `tools/pre-execute` | tool / editing + tool name | a tool call starts; writing tools become editing |
| `tools/post-execute` | thinking | the call finished; the tool name is cleared |
| `approval/request` | waiting | the agent is blocked on a permission question |
| `user-questions/request` | waiting | the agent is blocked on `ask_user_question` |
| `agent/status` → `idle` | done | the turn finished (green flash, then dim) |
| `agent/error` | error | the turn or step failed; stays red until the next turn |
| `agent/disposed` | — | the session closed and its arc is released |

A heartbeat (`control`) is sent every 30 seconds for live agents so a long, quiet turn is
not mistaken for a stale one, and so the daemon can reconcile after a restart. All events
share one keep-alive HTTP connection, which also preserves their order.

### Waterfall interactions

`approval/request` and `user-questions/request` are Cordis waterfall events: the first
listener that returns an outcome claims the request and short-circuits every listener behind
it. The desktop window's forwarding answerer is registered during the base bundle, before
this profile plugin, so a normal listener here never sees a prompt. Both observers are
therefore registered with `prepend` and immediately call `next()`: the ring reports
`waiting` while the UI still owns the actual decision, and reports `thinking` again in a
`finally` block once the answer arrives.

## Requirements

The daemon must be listening on `127.0.0.1:7801` (override with the `AGENTRING_PORT`
environment variable in the Harness process). Start it from the repository:

```sh
node daemon/bin/agentringd.mjs
```

## Reconciliation

State changes alone are not enough: a session that already existed when the plugin (or the
daemon) started would stay invisible until its next transition. Every 30 seconds the plugin
therefore compares `ctx.agents.list()` with the daemon's `/state`:

- a session the daemon does not know is announced with its real state (`thinking` or `idle`);
- a session the daemon does know only receives a heartbeat, which keeps it from being pruned
  as idle without changing what the ring shows;
- after a daemon restart (empty state) every live session is announced again.

## Limits

- Tool arguments and token streams are not sent; only the tool name and lifecycle state.
- Events are fire-and-forget with a 400 ms timeout and no retry, so events emitted while the
  daemon is down are lost (reconciliation restores the session, not the missed detail).
- The daemon binds `0.0.0.0` so the ESP32 can poll `/frame`; mutating endpoints accept
  loopback connections only.
