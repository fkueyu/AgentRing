# Architecture decisions

[中文](decisions.zh.md) · [English](decisions.md)

Small, local tool: prefer the simplest design that keeps the ring responsive and
the API surface boring. These notes record the decisions that would otherwise be
re-litigated.

## ADR-001: Keep HTTP polling between the daemon and the menu-bar app

**Status:** accepted, 2026-11-24.

The app needs a menu-bar count even when the preview window is closed. Today it
polls `/state` every 1.5 s and `/health` every 3 s; the preview fetches `/frame`
at 30 fps only while visible.

| Option | Tradeoff |
|---|---|
| Polling (current) | Stateless, easy to recover, no long-lived server state; up to 1.5 s state latency |
| Server-Sent Events | Lower latency and fewer requests; needs reconnect/backoff, event IDs and an app-side long-lived task |
| WebSocket | Bidirectional overkill for a one-way status feed |

**Decision:** keep polling for now. The state transitions that matter (waiting,
error) are also visible on the physical ring, and 1.5 s is well below the time a
person needs to notice a menu-bar change. Revisit if latency becomes a stated
requirement, if the app runs on a battery-sensitive machine, or if several
clients make polling measurable.

## ADR-003: The daemon is the only renderer and the only effect catalogue

**Status:** accepted, 2026-11-24.

`renderFrame` is the single visual contract: the app preview reads it over
`/frame` and the ESP32 reads the same 72-byte bytes over the TCP stream. Effect
IDs, labels and defaults live in `daemon/src/effects.mjs`; the app fetches them from `GET /capabilities` instead
of maintaining a second picker/label table.

**Tradeoff:** the app has a small offline fallback so settings still render when
the daemon is down; adding an effect while offline is not meaningful. The
renderer switch still needs a code branch per effect, but config validation and
UI options come from one catalogue.

## ADR-004: The control plane is loopback-only

**Status:** accepted, 2026-11-24.

Only `/frame`, `/health` and the read-only 7802 frame stream are reachable from
the LAN (the ESP32 needs them).
The preview, `/state`, `/config`, `/config/reset` and all mutations are
loopback-only. `/state` contains cwd paths, so exposing it to the LAN was both a
privacy and an unnecessary attack-surface problem.

**Tradeoff:** a browser preview from another machine no longer works. If remote
preview is needed later, add a read-only, redacted `/public/state` rather than
opening the existing endpoints.

## ADR-005: Push frames over a persistent raw TCP stream

**Status:** accepted, 2026-11-24.

The ring only needs a read-only visual feed. Rather than one HTTP request per
frame, the daemon listens on TCP 7802 and writes one 72-byte frame per 33 ms
tick to every connected client. The firmware keeps one `WiFiClient` open and
reads exact 72-byte frames; a short read drops the socket and triggers
re-resolution/reconnect. The renderer and preview remain in the daemon, so
`/frame` and the stream still share one `renderFrame` result.

**Measured:** the stream ran at ~29-30 fps versus ~22-23 fps with HTTP polling.

**Robustness:** the firmware keeps a 2 s stream-read timeout (system load can
stall the Node timer briefly) and paces LED updates to `FRAME_INTERVAL_MS`,
dropping already-buffered stale frames in favour of the newest one. A local
stream client is excluded from the `/health` LAN counters.

**Tradeoffs:** a second LAN port must be allowed through the firewall; the
protocol has no per-frame error correction (a dropped TCP connection simply
reconnects); and the App must read `streamFrames`/`streamLastFrameAt` in
`/health`, falling back to `lanFrames` for older firmware. The App preview
continues to use `/frame`, which keeps its 30 fps local path independent.

## ADR-006: Standby motion and colour are separate axes

**Status:** accepted, 2026-11-24.

`orbit` and `rainbow` were two standby modes that rendered exactly the same
comet; only the colour differed. That made the user choose the same motion
twice and kept a duplicated branch in the renderer. Standby is now motion
(`dot` / `orbit` / `breathe`) × palette (`mono` / `rainbow` / `aurora` /
`ember`). Only `mono` exposes a colour well; the other palettes are curated, so
the colour picker cannot fight a preset.

**Tradeoff:** this ADR deliberately left the running states on their own
`colorMode` (solid/gradient/rainbow), so the app had two colour vocabularies:
one for the idle ring and one for active sessions. [ADR-008](#adr-008-one-palette-vocabulary-a-palette-is-a-value-not-a-macro)
folds both into one catalogue, so the two pickers now speak the same language.
`standby: "rainbow"` configs are migrated to `orbit` + `standbyPalette:
"rainbow"` so existing installs look unchanged.

## ADR-007: Effect previews use a synthetic loopback frame

**Status:** accepted, 2026-11-24.

The motion page needs to show effects that are not currently on the ring. The
app deliberately does not render them locally: `/preview?state=&effect=` builds
a one-agent synthetic snapshot and runs the same `renderFrame`, returning the
usual 72-byte frame. It never touches the live snapshot or the physical ring's
stream, and the app points its rail at that URL until the user returns to live.

**Tradeoff:** one more loopback route and a second frame-fetch loop while the
motion page previews. In exchange, an effect preview cannot drift from the
hardware renderer, and previewing never changes what the real ring shows.

**Superseded in part by ADR-010 (2026-11-25):** previews now mirror to the
physical ring for a short TTL, by request; `GET /preview` remains the one-off
frame described here.

## ADR-008: One palette vocabulary; a palette is a value, not a macro

**Status:** accepted, 2026-11-25. Supersedes the colour halves of the v2 theme
model.

v2 had four overlapping colour systems: a theme preset (source colours + colour
mode + gradient target), a colour mode (solid/gradient/rainbow), a solid colour
source (state/source), and standby palettes with their own vocabulary. Only some
combinations reached the LEDs — with Mono / by state, picking Mint changed nothing
visible. Two bugs hid the rest: the renderer passed a single hex string to
`colorFor`, which expects a map, so **every custom source colour was ignored**;
and the app's motion page showed state-coloured dots even when the ring was
coloured by source or a preset. The palette page ended up with five theme tiles,
three mode tiles, a two-way state/source switch, six state wells and eighteen
source rows.

**Decision:** one `display.accent` value selects the running colour from a
single palette catalogue; the idle ring picks from the same catalogue (`mono` +
the curated ramps + `rainbow`). `state` and `source` are identity palettes;
`neon` / `sunset` / `mint` / `aurora` / `ember` are curated ramps whose stops
are spread around the ring; `rainbow` is the drifting hue wheel. Waiting / done
/ error always keep their `stateColors` entry. A palette is a value: selecting
one never rewrites another field. Themes, `colorMode`, `gradientTo`,
`solidColorBy` and `motion.tempo` are removed, and v2 configs are migrated by
following what was visible (see [Configuration](configuration.md#migration-to-v3)).

The app goes from five lighting sections to four. Colour and motion now share
the **States** section: one accent picker with only the colour wells that the
renderer actually reads, then one row per state with its effect and speed, and
finally the source list. The left rail summarises the accent and the attention
colours.

**Tradeoffs:**

- The “state colour fading to a chosen second colour” look is gone. Curated
  ramps provide gradient looks; identity palettes stay flat, which is what makes
  them readable on 6-LED arcs. A v2 gradient with a custom theme migrates to a
  flat identity palette.
- The renderer resolves the accent per LED and needs the segment index, so
  `lightFor` takes `(segment, segments)`. Negligible at 24 LEDs / 30 fps.
- `stateColors` and `sources` remain maps, but their wells are now only shown
  where they are used: six wells for the state palette, three reminder wells for
  a ramp, and per-source wells under the source card (enabled by the source
  palette).
- One more dev-only app hook (`AGENTRING_BASE`) lets screenshots run against a
  lab daemon instead of the live ring.

## ADR-009: Detect agent wiring from manifests, not CLIs

**Status:** accepted, 2026-11-25.

The Sources page needs to say whether an agent tool and its AgentRing bridge are
installed. The three options:

| Option | Tradeoff |
|---|---|
| Run each tool's CLI (`dsh plugin list`, …) | Authoritative, but slow, may initialize a profile or hang, and the output is not a stable API |
| Read the manifests each tool owns (chosen) | Cheap, offline, version-agnostic; heuristic and only as good as the files we know about |
| Infer from traffic only | Proves a working bridge, but shows nothing before the first session and cannot explain what is missing |

**Decision:** a registry of filesystem probes in `daemon/src/sources.mjs`, one
per agent, served by the loopback-only `GET /sources`. A probe reports installed
(app bundle / data directory / CLI), bridge state (`installed`, `missing`,
`disabled`, `mismatch`, `manual`), `installable`, and the exact command. The
running DSH profile is parsed from the desktop host process arguments, so a
plugin installed in a different profile is a visible mismatch instead of a
false success.

The app re-reads the report every 10 s. For Codex and Claude, `installable` is
true and `POST /sources/<id>/install` runs AgentRing's own installer script; the
script merges into the tool's config, keeps foreign hooks, backs up the original
and is idempotent. Only scripts in `BRIDGE_INSTALLERS` are runnable: a probe's
display command (DSH's package-manager command) remains copy-only, so the
endpoint can never be used to run an arbitrary command. Activity is deliberately
not part of the payload; the page joins `/sources` with the sessions from
`/state`.

**Tradeoffs:** a bundle disabled by a loader patch row is invisible to the probe
(only the profile bundle list is checked), external changes lag by up to the
poll interval, and installing a hook still needs the tool's own one-time trust
confirmation before it fires. A new agent needs a probe (and an installer if it
gets one-click support) rather than just an `/ingest` call; `/ingest` remains
the generic contract, and the probe only explains the setup.

## ADR-010: Effect previews mirror to the physical ring with a TTL

**Status:** accepted, 2026-11-25.

Auditioning an effect only on the screen was not enough: the user wants the
physical ring to show the same synthetic frame while choosing an effect. The app
therefore asks the daemon to hold a temporary preview override:
`POST /preview {state, effect, ttlMs}`. `/frame`, the browser preview and the raw
TCP stream all serve the synthetic frame while the override is active;
`DELETE /preview` restores the live snapshot. The app refreshes the TTL (45 s
default, 15 s heartbeat) while the preview is open and clears it when the
preview closes, the section changes or the window disappears. An expired
override falls back to live, so a crashed client cannot pin the ring.

**Tradeoffs:** the ring stops showing live sessions while auditioning (the app
labels this), any loopback client can change what the ring shows (there is one
local user), and the frame source checks one expiry per tick. The preview still
runs through the normal renderer, so gamma, the current limit and night mode
apply exactly as they do live.
