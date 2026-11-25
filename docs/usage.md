# Using AgentRing

[中文](usage.zh.md) · [English](usage.md)

This guide covers the app and the ring from day to day. For installation see
[Installation](installation.md); for every config key and HTTP route see
[Configuration](configuration.md).

## Menu bar

AgentRing is a menu-bar utility with no Dock icon. The item shows:

- the number of sessions that are not idle;
- a raised-hand icon when a session is waiting for approval;
- a warning triangle when a session is in error.

Its menu opens the settings window (`⌘,`), lists up to five sessions with their
state, restarts the daemon, opens the browser preview, and quits the app. A
clean quit is not relaunched by launchd; a crash is.

## The settings window

Four pages, switchable with `⌘1`–`⌘4`:

| Page | Shortcut | What it is for |
|---|---|---|
| Preview | `⌘1` | What the ring is showing right now, plus the session list |
| Lighting | `⌘2` | Brightness, standby, layout and per-state appearance |
| Sources | `⌘3` | Which agents are installed, connected and shown |
| General | `⌘4` | Daemon/ring diagnostics, maintenance and versions |

The sidebar footer always shows whether the daemon is connected and whether the
physical ring is receiving frames.

### Preview

![Preview page](images/settings-preview.png)

The ring hero is rendered from the daemon's `/frame` bytes — the same bytes the
ESP32 receives. Below it you get:

- the session count and active count;
- attention chips when sessions are waiting or in error;
- a legend of the six states and their current effects;
- the live session list, where each row shows label, source, state and tool.

Right-click a session to remove a stale record. The footer shows the silence
timeout that returns a quiet session to idle. Sessions are ordered by urgency:
`waiting > error > editing > tool > thinking > done > idle`.

### Lighting

A live ring rail on the left, controls on the right. The rail's overview card
follows the selected section.

**Display**

- **Brightness**: global output scale (5–100%).
- **Gamma**: 1.0 preserves the renderer's levels; higher values deepen shadows
  and harden fades.
- **Current limit**: the renderer scales the whole frame down when the estimated
  WS2812 current exceeds this budget (300–2000 mA). 24 LEDs at full white draw
  about 1.44 A.
- **Night mode**: a local-time window that caps brightness at a lower value.

**Standby**

What one LED does when no session is running:

| Mode | Behaviour |
|---|---|
| Steady dot | A still dim LED |
| Orbit | A short comet slowly circles the ring |
| Soft breathing | A randomly placed LED fades in and out, overlapping the next |

The standby palette is independent of the session palette: **Mono** uses the
colour well below, while **Neon / Sunset / Mint / Aurora / Ember / Rainbow** are curated.
Standby speed (0.2–3×) only affects standby, not the session effects. Night mode
also applies to standby.

**Layout**

How sessions share the ring:

- **Split**: one segment per session.
- **Focus**: only the most urgent session is shown.
- **Rotate**: one session at a time, changing every 3–60 seconds.

`Max segments` (1–8), `Segment gap` (0–3 dark LEDs), and `Idle sessions also take a segment` control how
the ring is divided. Idle sessions are hidden unless that toggle is on.

**States**

![Lighting → States](images/settings-states.png)

This is where colour and motion meet. One accent palette, then one row per
state:

- **Session palette**: State colours / Source colours / Neon / Sunset / Mint / Aurora / Ember / Rainbow.
  It decides the **running** look only.
- **State colours** (for State colours): the six state wells. The first three are the running
  colours; the last three are also the reminder colours.
- **Reminder colours** (for any other accent): the three colours used by waiting, done and
  error. They are never overridden by the accent.
- **State effects**: effect + speed (0.2–3×) per state. Click the state name or pick
  an effect to audition it; see previews below.
- **Timing**: how long the done flash is held (2–30 s) and how long a silent
  session may run before it degrades to idle (2–60 min). Waiting is exempt from
  the silence timeout.

The one rule to remember: **waiting / done / error always use their reminder
colours**, whatever the accent is. The accent only changes the busy look.

#### Effect previews on the ring

![Effect preview](images/settings-preview-sync.png)

When you audition an effect in States, the physical ring shows the same synthetic
frame: the daemon holds a temporary preview override and serves it on `/frame`
and the TCP stream. The rail reads `/frame` too, so the screen and the ring
cannot disagree. The card then says “Effect preview · synced to ring”.

- The preview is refreshed every 15 s while the page is open and expires after
  45 s.
- **Back to live preview**, changing the lighting section, or closing the settings
  window clears it immediately.
- While a preview is active the ring shows that state instead of the live
  sessions; leaving the preview restores them.
- If the app crashes or is killed, the preview expires within 45 s.

### Sources

![Sources page](images/settings-sources.png)

One row per supported agent, with an installation and connection status:

| Status | Meaning |
|---|---|
| Wired | The tool and its AgentRing bridge are present |
| Not wired | The tool is installed but its hook/plugin is missing |
| Not installed | The tool was not detected on this Mac |
| Disabled | The plugin is installed but not enabled in its profile |
| Mismatch | The plugin is installed in a different profile than the running tool |
| Manual setup | The protocol is supported but no installer is registered |
| Unknown | The daemon is offline, so detection could not run |

Each row shows the tool version, the install path, the running profile and the
current session count. Two actions are available for a missing bridge:

- **Connect** — runs AgentRing's own installer for Codex or Claude Code. It
  merges the hooks into the tool's config, preserves other hooks, writes a
  timestamped backup and is idempotent. Only AgentRing's allowlisted scripts can
  be run this way; DSH's package-manager command is copy-only.
- **Copy command** — the same installer as a terminal command, for manual use or
  when the daemon cannot run it.

The switch controls whether that source appears on the ring at all. The colour
well sets the tool colour: it drives arcs under the Source colours accent and is the
fallback for a state without a dedicated colour (such as idle). When the accent
is not Source colours it does not drive running arcs; the page subtitle says so.

**Other sources** lists the tools that are configured but not auto-detected. They can
still be wired through `/ingest` (see [Other agents](installation.md#other-agents));
they take effect on the ring as soon as events arrive.

### General

- **Connection**: daemon address, ring IP, fps, restart daemon and open the browser
  preview.
- **Language**: switch the interface between 中文 and English, or follow the system.
  Applies immediately and only affects the app; the daemon and the frame
  protocol are unchanged.
- **Maintenance**: clear all session records (useful after an agent is killed without
  sending its end event).
- **About**: app version, daemon version, hardware summary, menu-bar behaviour.

## States, colours and timing

| State | Label | When | Colour behaviour |
|---|---|---|---|
| `thinking` | Thinking | Turn running, no tool yet | Accent palette |
| `tool` | Running tool | A tool is running | Accent palette |
| `editing` | Editing | An edit/write tool is running | Accent palette |
| `waiting` | Waiting | Approval or user question pending | Reminder amber, always |
| `done` | Done | Turn finished; held for `Done hold` | Reminder green, always |
| `error` | Error | Turn/tool failure | Reminder red, always |
| `idle` | Idle | Session exists, no active turn | Hidden unless enabled, dim |

The ring gives the most urgent session its space first. The priority is
`waiting > error > editing > tool > thinking > done > idle`.

Two timeouts keep the ring honest:

- a session that reports no activity for `Stale fallback` minutes is treated as idle;
  waiting is exempt;
- a finished session remains for `Done hold` seconds, then becomes idle.

## Colour model

Since AgentRing 0.3, there is one palette model:

- `Session palette` (the accent) decides the running look. **State colours** uses the six state
  colours; **Source colours** uses each tool's colour; **Neon / Sunset / Mint / Aurora /
  Ember** are curated ramps spread around the ring; **Rainbow** flows the hue wheel.
- **Reminder colours** are independent and always win for waiting/done/error.
- **Standby palette** is separate: mono plus the same curated ramps and rainbow. It only
  affects the ring when no session is shown.

Selecting a palette only changes that one field. It never rewrites colours,
speeds or other settings. The daemon still owns rendering, so the app preview,
the browser preview and the hardware always show the same frame.

## Sessions and the menu bar

The menu-bar count is the number of sessions that are not idle. Sessions are
reported by the agent integrations and expire automatically:

- finished sessions linger briefly so Codex does not flicker between turns;
- idle sessions disappear after 45 minutes without an event;
- **General → Clear all session records** removes stale records immediately.

Use the context menu in Preview to remove a single record. Nothing is deleted from
the agent itself.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘1` / `⌘2` / `⌘3` / `⌘4` | Preview / Lighting / Sources / General |
| `⌘,` | Open the settings window |

## Configuration and reset

Settings are stored in `~/.agentring/config.json` (v3). The daemon is the source
of truth and sanitizes every update. The default palette, layout, motion and
source list can be restored with the **Restore default lighting…** link at the bottom of
the Lighting page; it covers display, layout, motion, colours and sources, not the
agent hooks.

When upgrading from 0.2.x, the daemon migrates the old theme/colour-mode config
to v3 on startup and rewrites the file once. Back up `~/.agentring/config.json`
before a cross-minor upgrade if you have custom colours.

## Frequently asked

**I picked a palette but waiting/done/error did not change.**
They intentionally keep the reminder colours; the accent only affects running
sessions (and the idle ring uses its own standby palette).

**The ring shows an effect instead of my sessions.**
A preview from Lighting → States is active. Press Back to live preview, change section, close the
window, or wait 45 s.

**Codex sessions do not appear.**
Open Sources; Codex should be **Wired**. Codex asks once to trust hooks; cloud tasks
do not run locally and never trigger local hooks.

**Claude sessions never show Error.**
Re-run **Connect** for Claude Code (or `npm run install:claude`). The installer
adds the `StopFailure` hook, which drives the red state; installations made
before 0.3.0 only had the seven lifecycle events.

**The app says the ring is not connected.**
Check `/health` for `streamClients: 1` and a growing `streamFrames`; allow TCP
7802 and mDNS through the Mac firewall; make sure the ring and Mac are on the
same subnet, or set `AGENTRING_HOST` in `config.h`.

**Nothing lights up.**
Check the 5 V supply and common ground, confirm DIN is on GPIO10, then run `info`
over serial at 115200. See [Hardware](hardware.md).
