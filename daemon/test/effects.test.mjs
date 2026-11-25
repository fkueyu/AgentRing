import test from 'node:test'
import assert from 'node:assert/strict'

import { sanitize } from '../src/config.mjs'
import { renderFrame } from '../src/frame.mjs'

function frameAt(ms, state, effects) {
  const config = sanitize({ display: { brightness: 0.6 }, motion: { effects } })
  return renderFrame(
    { ts: ms, agents: [{ source: 'dsh', state, sinceMs: ms, updatedMs: 0 }] },
    { config, now: ms },
  )
}

function peak(frame) {
  let value = 0
  for (const channel of frame) value = Math.max(value, channel)
  return value
}

test('breathing bottoms out near off and still reaches a bright peak', () => {
  const thinkingBreathe = Array.from({ length: 50 }, (_, i) =>
    peak(frameAt(i * 40, 'thinking', { thinking: 'breathe' })),
  )
  assert.ok(Math.min(...thinkingBreathe) <= 12, `thinking breathe min ${Math.min(...thinkingBreathe)}`)
  assert.ok(Math.max(...thinkingBreathe) >= 110, `thinking breathe max ${Math.max(...thinkingBreathe)}`)

  const breathe = Array.from({ length: 40 }, (_, i) => peak(frameAt(i * 30, 'waiting', { waiting: 'breathe' })))
  assert.ok(Math.min(...breathe) <= 12, `breathe min ${Math.min(...breathe)}`)
  assert.ok(Math.max(...breathe) >= 110, `breathe max ${Math.max(...breathe)}`)
})

test('editing rain keeps a dark floor and drifting drops', () => {
  const levels = (ms) => {
    const frame = frameAt(ms, 'editing', { editing: 'patches' })
    return Array.from({ length: 24 }, (_, i) =>
      Math.max(frame[i * 3], frame[i * 3 + 1], frame[i * 3 + 2]),
    )
  }
  const current = levels(900)
  const floor = Math.min(...current)
  assert.ok(floor >= 2 && floor <= 6, `ambient floor ${floor}`)
  const lit = current.filter((value) => value > floor + 10)
  assert.ok(lit.length >= 4 && lit.length <= 14, `rain drops ${lit.length}`)
  // The drops keep moving instead of leaving a static twinkle field.
  assert.notDeepEqual(current, levels(1020))
})

test('rain runs with an independent phase in each split segment', () => {
  const config = sanitize({
    display: { brightness: 0.6 },
    layout: { maxAgents: 4 },
    motion: { effects: { editing: 'patches' } },
  })
  const agents = Array.from({ length: 4 }, (_, index) => ({
    source: 'dsh',
    state: 'editing',
    sinceMs: 0,
    updatedMs: 0,
    key: `small-${index}`,
    sessionId: `small-${index}`,
    label: `small-${index}`,
  }))
  const frame = renderFrame({ ts: 400, agents }, { config, now: 400 })
  // Four agents => 6 LEDs each, one gap => 5 usable LEDs per segment.
  const segments = [0, 1, 2, 3].map((segment) =>
    Array.from({ length: 5 }, (_, index) =>
      Math.max(
        frame[(segment * 6 + index) * 3],
        frame[(segment * 6 + index) * 3 + 1],
        frame[(segment * 6 + index) * 3 + 2],
      ),
    ),
  )
  const floor = Math.min(...segments.flat())
  assert.ok(floor >= 2 && floor <= 4, `small ambient floor ${floor}`)
  for (const [index, segment] of segments.entries()) {
    assert.ok(Math.max(...segment) > floor + 10, `segment ${index} has a drop`)
  }
  assert.ok(new Set(segments.map((segment) => segment.join(','))).size > 1, 'segments rain independently')
})

test('comet head is shared by two adjacent LEDs instead of snapping', () => {
  // head = (t * 5) % 24; t = 1.1s puts it at 5.5.
  const frame = frameAt(1100, 'tool', { tool: 'comet' })
  const leds = Array.from({ length: 24 }, (_, i) =>
    Math.max(frame[i * 3], frame[i * 3 + 1], frame[i * 3 + 2]),
  )
  const max = Math.max(...leds)
  assert.ok(leds[5] > max * 0.5, `LED 5 = ${leds[5]}, max = ${max}`)
  assert.ok(leds[6] > max * 0.5, `LED 6 = ${leds[6]}, max = ${max}`)
  assert.ok(leds[0] < max * 0.2, `far LED should stay dim: ${leds[0]}`)
  assert.ok(leds[0] <= 8, `background LED should be near off: ${leds[0]}`)
})
