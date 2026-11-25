// Event vocabulary + per-agent state machine.
//
// Adapters translate their own hook payloads into the small vocabulary below:
//   session-start | turn-start | tool-start | tool-end | waiting | turn-end | error | session-end
// The store turns that into one record per live session, which the renderer and
// the HTTP API both read.

import { STATE_PRIORITY } from './protocol.mjs'

export const DONE_HOLD_MS = 8000
export const STALE_MS = 10 * 60 * 1000
export const IDLE_TTL_MS = 45 * 60 * 1000
// Codex closes a session at the end of a turn and opens a new one for the next,
// so deleting the record on `session-end` makes the ring flicker. Keep it as a
// finished session for a few minutes instead.
export const SESSION_END_GRACE_MS = 3 * 60 * 1000
export const DONE_REGRESSION_GUARD_MS = 45 * 1000

/** States that mean "a turn is actively working" for the silence guard. */
const ACTIVE_STATES = new Set(['thinking', 'tool', 'editing'])

const STATE_BY_EVENT = {
  'session-start': 'idle',
  // A turn started: the model is preparing / waiting for the first reply.
  'turn-start': 'thinking',
  thinking: 'thinking',
  'tool-start': 'tool',
  'tool-end': 'thinking',
  waiting: 'waiting',
  'turn-end': 'done',
  error: 'error',
  control: null,
  unknown: null,
}

/** Tool name → finer state. Editing gets its own colour on the ring. */
export function classifyTool(name) {
  const tool = String(name || '').toLowerCase()
  if (!tool) return 'tool'
  if (/(apply_patch|edit|write|patch|create_file|str_replace|multi_edit|insert)/.test(tool)) return 'editing'
  return 'tool'
}

export function labelFor(cwd) {
  if (!cwd || typeof cwd !== 'string') return 'session'
  const parts = cwd.replace(/\/+$/, '').split('/')
  return parts[parts.length - 1] || '/'
}

/** Codex / Claude-style hook payload (stdin JSON) -> unified event. */
export function mapHookPayload(p = {}) {
  const sessionId = p.session_id || p.sessionId || undefined
  const cwd = p.cwd || undefined
  const tool = p.tool_name || p.toolName || undefined
  const common = { source: 'codex', sessionId, cwd, tool, message: p.message }
  const name = p.hook_event_name || p.hookEventName || ''

  if (name === 'Notification') {
    const kind = p.notification_type || p.notificationType || ''
    return { ...common, event: kind === 'idle_prompt' ? 'turn-end' : 'waiting' }
  }

  const event = {
    SessionStart: 'session-start',
    UserPromptSubmit: 'turn-start',
    PreToolUse: 'tool-start',
    PostToolUse: 'tool-end',
    PermissionRequest: 'waiting',
    Stop: 'turn-end',
    StopFailure: 'error',
    SessionEnd: 'session-end',
  }[name]

  return { ...common, event: event || 'unknown', raw: name }
}

export function createStore({ now = () => Date.now() } = {}) {
  /** @type {Map<string, any>} */
  const agents = new Map()

  function keyOf(ev) {
    const ident = ev.sessionId || ev.cwd || 'default'
    return `${ev.source}:${ident}`
  }

  function ingest(ev) {
    if (!ev || !ev.source) return { ok: false, reason: 'missing source' }
    const ts = now()

    const key = keyOf(ev)
    let a = agents.get(key)

    // Heartbeats only refresh liveness: they must not create a record, revive an
    // ended one, or change what the ring shows.
    if (ev.event === 'control') {
      if (!a) return { ok: true, ignored: true }
      a.updated = ts
      return { ok: true, state: a.state, heartbeat: true }
    }

    if (ev.event === 'session-end') {
      if (!a) return { ok: true, removed: true }
      a.state = 'done'
      a.since = ts
      a.updated = ts
      a.ended = ts
      a.tool = undefined
      return { ok: true, state: 'done' }
    }

    if (!a) {
      a = {
        key,
        source: ev.source,
        sessionId: ev.sessionId,
        cwd: ev.cwd,
        label: ev.label || labelFor(ev.cwd),
        state: 'idle',
        tool: undefined,
        since: ts,
        updated: ts,
      }
      agents.set(key, a)
    }

    if (ev.cwd) a.cwd = ev.cwd
    if (ev.label) a.label = ev.label
    else if (ev.cwd) a.label = labelFor(ev.cwd)
    a.updated = ts
    a.ended = undefined

    // A late tool event (out-of-order PostToolUse) must not flip a finished turn
    // back to running.
    if (
      a.state === 'done' &&
      (ev.event === 'tool-start' || ev.event === 'tool-end') &&
      ts - a.since < DONE_REGRESSION_GUARD_MS
    ) {
      return { ok: true, state: 'done', ignored: true }
    }

    // DSH reports a failed turn and an idle status back to back; the idle
    // status must not paint the failure green. Keep red until the next turn.
    if (ev.event === 'turn-end' && a.state === 'error') {
      return { ok: true, state: 'error', ignored: true }
    }

    const next = STATE_BY_EVENT[ev.event]
    if (ev.event === 'tool-start' && ev.tool) a.tool = ev.tool
    if (ev.event === 'waiting' && ev.tool) a.tool = ev.tool
    if (ev.event === 'turn-start' || ev.event === 'turn-end' || ev.event === 'session-start') a.tool = undefined

    const target =
      ev.event === 'tool-start' ? ev.kind || classifyTool(ev.tool) : next
    if (target && target !== a.state) {
      a.state = target
      a.since = ts
    }
    return { ok: true, state: a.state }
  }

  function snapshot({
    doneHoldMs = DONE_HOLD_MS,
    staleMs = STALE_MS,
    endedGraceFor = () => SESSION_END_GRACE_MS,
  } = {}) {
    const ts = now()
    const list = []
    for (const a of agents.values()) {
      let state = a.state
      if (state === 'done' && ts - a.since > doneHoldMs) state = 'idle'
      // A turn that stops reporting is not proof of work: degrade it instead of
      // pinning the ring on "running" forever after a plugin crash. `waiting`
      // is exempt because a pending approval may legitimately wait for hours.
      if (ACTIVE_STATES.has(state) && ts - a.updated > staleMs) state = 'idle'
      const grace = typeof endedGraceFor === 'function' ? endedGraceFor(a.source) : endedGraceFor
      if (a.ended && ts - a.ended > grace) {
        agents.delete(a.key)
        continue
      }
      if (state === 'idle' && ts - a.updated > IDLE_TTL_MS) {
        agents.delete(a.key)
        continue
      }
      list.push({
        key: a.key,
        source: a.source,
        sessionId: a.sessionId,
        label: a.label,
        cwd: a.cwd,
        tool: a.tool,
        state,
        sinceMs: ts - a.since,
        updatedMs: ts - a.updated,
      })
    }
    list.sort(
      (x, y) => (STATE_PRIORITY[y.state] || 0) - (STATE_PRIORITY[x.state] || 0) || y.updatedMs - x.updatedMs,
    )
    return {
      ts,
      leds: 24,
      active: list.filter((a) => a.state !== 'idle').length,
      agents: list,
    }
  }

  function forget(sessionId) {
    let removed = 0
    for (const [key, agent] of agents) {
      if (agent.sessionId === sessionId) {
        agents.delete(key)
        removed++
      }
    }
    return removed
  }

  /** Plain-JSON snapshot for disk persistence across daemon restarts. */
  function serialize() {
    return [...agents.values()].map((a) => ({
      key: a.key,
      source: a.source,
      sessionId: a.sessionId,
      cwd: a.cwd,
      label: a.label,
      state: a.state,
      tool: a.tool,
      since: a.since,
      updated: a.updated,
      ended: a.ended,
    }))
  }

  function hydrate(records) {
    if (!Array.isArray(records)) return
    for (const record of records) {
      if (!record || typeof record.key !== 'string') continue
      agents.set(record.key, {
        key: record.key,
        source: record.source || 'unknown',
        sessionId: record.sessionId,
        cwd: record.cwd,
        label: record.label || labelFor(record.cwd),
        // Sessions persisted before the vocabulary split still say "running";
        // treat them as a tool call until their next event arrives.
        state: record.state === 'running' ? 'tool' : record.state || 'idle',
        tool: record.tool,
        since: Number(record.since) || now(),
        updated: Number(record.updated) || now(),
        ended: record.ended,
      })
    }
  }

  function clear() {
    const count = agents.size
    agents.clear()
    return count
  }

  return { ingest, snapshot, forget, clear, serialize, hydrate, get size() { return agents.size } }
}
