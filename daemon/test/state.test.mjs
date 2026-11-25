import test from 'node:test'
import assert from 'node:assert/strict'

import { createStore, mapHookPayload } from '../src/state.mjs'
import { sanitize } from '../src/config.mjs'
import { renderFrame } from '../src/frame.mjs'

function clock(start = 1_700_000_000_000) {
  let t = start
  return { now: () => t, advance: (ms) => (t += ms) }
}

test('maps codex hook payloads to the unified vocabulary', () => {
  assert.equal(mapHookPayload({ hook_event_name: 'SessionStart' }).event, 'session-start')
  assert.equal(mapHookPayload({ hook_event_name: 'UserPromptSubmit' }).event, 'turn-start')
  assert.equal(mapHookPayload({ hook_event_name: 'PreToolUse', tool_name: 'Bash' }).event, 'tool-start')
  assert.equal(mapHookPayload({ hook_event_name: 'PermissionRequest' }).event, 'waiting')
  assert.equal(mapHookPayload({ hook_event_name: 'Stop' }).event, 'turn-end')
  assert.equal(mapHookPayload({ hook_event_name: 'SessionEnd' }).event, 'session-end')
  assert.equal(mapHookPayload({ hook_event_name: 'Notification', notification_type: 'idle_prompt' }).event, 'turn-end')
  assert.equal(mapHookPayload({ hook_event_name: 'Nope' }).event, 'unknown')
})

test('one session walks idle -> thinking -> tool -> waiting -> done', () => {
  const c = clock()
  const store = createStore({ now: c.now })
  const base = { source: 'codex', sessionId: 's1', cwd: '/tmp/project' }

  store.ingest({ ...base, event: 'session-start' })
  assert.equal(store.snapshot().agents[0].state, 'idle')
  assert.equal(store.snapshot().agents[0].label, 'project')

  store.ingest({ ...base, event: 'turn-start' })
  assert.equal(store.snapshot().agents[0].state, 'thinking')

  store.ingest({ ...base, event: 'tool-start', tool: 'bash' })
  assert.equal(store.snapshot().agents[0].state, 'tool')

  store.ingest({ ...base, event: 'waiting', tool: 'Bash' })
  assert.equal(store.snapshot().agents[0].state, 'waiting')
  assert.equal(store.snapshot().agents[0].tool, 'Bash')

  store.ingest({ ...base, event: 'turn-end' })
  assert.equal(store.snapshot().agents[0].state, 'done')

  c.advance(9000)
  assert.equal(store.snapshot().agents[0].state, 'idle')
})

test('session-end keeps a finished record for a grace period, then drops it', () => {
  const c = clock()
  const store = createStore({ now: c.now })
  store.ingest({ source: 'dsh', sessionId: 'x', event: 'session-start' })
  store.ingest({ source: 'dsh', sessionId: 'x', event: 'session-end' })

  const soon = store.snapshot().agents
  assert.equal(soon.length, 1)
  assert.equal(soon[0].state, 'done')

  c.advance(4 * 60 * 1000)
  assert.equal(store.snapshot().agents.length, 0)
})

test('waiting outranks a running tool in the ring order', () => {
  const store = createStore()
  store.ingest({ source: 'codex', sessionId: 'a', event: 'tool-start', tool: 'bash' })
  store.ingest({ source: 'dsh', sessionId: 'b', event: 'waiting' })
  assert.deepEqual(
    store.snapshot().agents.map((a) => a.state),
    ['waiting', 'tool'],
  )
})

test('editing tools get their own state', () => {
  const store = createStore()
  store.ingest({ source: 'dsh', sessionId: 'e1', event: 'tool-start', tool: 'apply_patch' })
  assert.equal(store.snapshot().agents[0].state, 'editing')
  store.ingest({ source: 'dsh', sessionId: 'e1', event: 'tool-start', tool: 'bash' })
  assert.equal(store.snapshot().agents[0].state, 'tool')
})

test('frame is 24 RGB triples and two agents split the ring', () => {
  const store = createStore()
  store.ingest({ source: 'codex', sessionId: 'a', event: 'turn-start' })
  store.ingest({ source: 'dsh', sessionId: 'b', event: 'turn-start' })

  const frame = renderFrame(store.snapshot())
  assert.equal(frame.length, 72)
  const lit = Array.from({ length: 24 }, (_, i) => frame[i * 3] + frame[i * 3 + 1] + frame[i * 3 + 2])
  assert.ok(lit.filter((v) => v > 0).length >= 4, 'both arcs should light at least a few LEDs')
  assert.ok(lit.every((v) => v <= 255 * 3))
})

test('empty ring renders a single standby dot', () => {
  const frame = renderFrame(createStore().snapshot())
  const lit = Array.from({ length: 24 }, (_, i) => frame[i * 3] + frame[i * 3 + 1] + frame[i * 3 + 2])
  assert.equal(lit.filter((v) => v > 0).length, 1)
})

test('state survives a restart through serialize/hydrate', () => {
  const store = createStore()
  store.ingest({ source: 'codex', sessionId: 'p1', cwd: '/tmp/p1', event: 'tool-start', tool: 'Bash' })
  const saved = JSON.parse(JSON.stringify(store.serialize()))

  const restored = createStore()
  restored.hydrate(saved)
  const agent = restored.snapshot().agents[0]
  assert.equal(agent.label, 'p1')
  assert.equal(agent.state, 'tool')
  assert.equal(agent.tool, 'Bash')
})

test('a finished session lingers while the desktop app is open', () => {
  const c = clock()
  const store = createStore({ now: c.now })
  store.ingest({ source: 'codex', sessionId: 'd1', cwd: '/tmp/d1', event: 'session-start' })
  store.ingest({ source: 'codex', sessionId: 'd1', event: 'session-end' })

  // Desktop app running: keep it much longer than the default grace.
  c.advance(20 * 60 * 1000)
  const kept = store.snapshot({ endedGraceFor: () => 45 * 60 * 1000 })
  assert.equal(kept.agents.length, 1)
  assert.equal(kept.agents[0].state, 'idle')
})

test('a late tool event does not flip a finished turn back to running', () => {
  const c = clock()
  const store = createStore({ now: c.now })
  store.ingest({ source: 'codex', sessionId: 'g1', event: 'turn-start' })
  store.ingest({ source: 'codex', sessionId: 'g1', event: 'turn-end' })
  assert.equal(store.snapshot().agents[0].state, 'done')

  c.advance(5000)
  store.ingest({ source: 'codex', sessionId: 'g1', event: 'tool-end' })
  assert.equal(store.snapshot().agents[0].state, 'done')

  // A genuinely new turn still starts.
  c.advance(60_000)
  store.ingest({ source: 'codex', sessionId: 'g1', event: 'turn-start' })
  assert.equal(store.snapshot().agents[0].state, 'thinking')
})

test('a silent working session degrades after staleMs; waiting is exempt', () => {
  const c = clock()
  const store = createStore({ now: c.now })
  store.ingest({ source: 'dsh', sessionId: 's', event: 'tool-start', tool: 'bash' })
  c.advance(11 * 60 * 1000)
  assert.equal(store.snapshot({ staleMs: 10 * 60 * 1000 }).agents[0].state, 'idle')

  store.ingest({ source: 'dsh', sessionId: 'w', event: 'waiting' })
  c.advance(60 * 60 * 1000)
  const waiting = store.snapshot({ staleMs: 10 * 60 * 1000 }).agents.find((a) => a.sessionId === 'w')
  assert.equal(waiting.state, 'waiting')
})

test('an idle status after a failure does not paint the error green', () => {
  const store = createStore()
  store.ingest({ source: 'dsh', sessionId: 'e', event: 'tool-start', tool: 'bash' })
  store.ingest({ source: 'dsh', sessionId: 'e', event: 'error' })
  store.ingest({ source: 'dsh', sessionId: 'e', event: 'turn-end' })
  assert.equal(store.snapshot().agents[0].state, 'error')

  store.ingest({ source: 'dsh', sessionId: 'e', event: 'turn-start' })
  assert.equal(store.snapshot().agents[0].state, 'thinking')
})

test('a heartbeat does not create or revive a session', () => {
  const store = createStore()
  store.ingest({ source: 'dsh', sessionId: 'ghost', event: 'control' })
  assert.equal(store.snapshot().agents.length, 0)

  store.ingest({ source: 'dsh', sessionId: 'x', event: 'session-start' })
  store.ingest({ source: 'dsh', sessionId: 'x', event: 'session-end' })
  store.ingest({ source: 'dsh', sessionId: 'x', event: 'control' })
  assert.equal(store.snapshot().agents[0].state, 'done')
})

test('split mode distributes leftover LEDs instead of dumping them on the last agent', () => {
  const cfg = sanitize({ layout: { maxAgents: 5, gapLeds: 1 } })
  const agents = Array.from({ length: 5 }, () => ({
    source: 'dsh',
    state: 'thinking',
    sinceMs: 0,
    updatedMs: 0,
  }))
  const now = 1_700_000_000_000
  const frame = renderFrame({ ts: now, agents }, { leds: 24, config: cfg, now })
  const runs = []
  let run = 0
  for (let i = 0; i < 24; i++) {
    const lit = frame[i * 3] + frame[i * 3 + 1] + frame[i * 3 + 2] > 0
    if (lit) run++
    else if (run) {
      runs.push(run)
      run = 0
    }
  }
  if (run) runs.push(run)
  assert.deepEqual(runs, [4, 4, 4, 4, 3])
})
