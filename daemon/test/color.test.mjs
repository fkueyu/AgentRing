import test from 'node:test'
import assert from 'node:assert/strict'

import { ACCENT_MODES } from '../src/effects.mjs'
import { sanitize } from '../src/config.mjs'
import { renderFrame } from '../src/frame.mjs'

// 227 ms is a breathe peak, so an accent test sees every LED at full geometry
// instead of a dim trough.
const snapshot = (state = 'thinking', source = 'dsh') => ({
  ts: 227,
  agents: [{ key: `${source}:1`, source, label: 'x', cwd: '/tmp/x', state, sinceMs: 0, updatedMs: 0 }],
})

function pixels(config, state = 'thinking', source = 'dsh', ts = 227) {
  const snap = snapshot(state, source)
  const frame = renderFrame({ ...snap, ts }, { config: sanitize(config) })
  return Array.from({ length: 24 }, (_, i) => [frame[i * 3], frame[i * 3 + 1], frame[i * 3 + 2]])
}

function brightest(leds) {
  return leds.slice().sort((a, b) => b[0] + b[1] + b[2] - (a[0] + a[1] + a[2]))[0]
}

test('the state palette paints the state colour', () => {
  const leds = pixels({
    display: { accent: 'state', brightness: 0.6 },
    stateColors: { thinking: '#0000ff' },
  })
  const [r, g, b] = brightest(leds)
  assert.ok(b > g && b > r, `expected blue, got ${r},${g},${b}`)

  const red = pixels({
    display: { accent: 'state', brightness: 0.6 },
    stateColors: { thinking: '#ff0000' },
  })
  const [rr, rg, rb] = brightest(red)
  assert.ok(rr > rg && rr > rb, `expected red, got ${rr},${rg},${rb}`)
})

test('the source palette paints the tool colour', () => {
  const leds = pixels({
    display: { accent: 'source', brightness: 0.6 },
    stateColors: { thinking: '#0000ff' },
    sources: { dsh: { enabled: true, color: '#00ff00' } },
  })
  const [r, g, b] = brightest(leds)
  assert.ok(g > r && g > b, `expected green, got ${r},${g},${b}`)
})

test('a curated accent spreads its stops around the ring', () => {
  const leds = pixels({ display: { accent: 'neon', brightness: 0.6 } })
  const buckets = new Set(
    leds.map(([r, g, b]) => `${Math.round(r / 24)}-${Math.round(g / 24)}-${Math.round(b / 24)}`),
  )
  assert.ok(buckets.size >= 6, `expected a ramp, got ${buckets.size} buckets`)

  // A single agent owns the whole ring, so both ends of the ramp are visible.
  const first = leds[0]
  const last = leds[23]
  assert.notDeepEqual(first, last)
})

test('split segments show different slices of one ramp', () => {
  const config = sanitize({
    display: { accent: 'sunset', brightness: 0.6 },
    layout: { maxAgents: 4, gapLeds: 1 },
  })
  const agents = [0, 1].map((index) => ({
    key: `agent-${index}`,
    source: 'dsh',
    state: 'thinking',
    sinceMs: 0,
    updatedMs: 0,
  }))
  const frame = renderFrame({ ts: 227, agents }, { config })
  const first = [frame[0], frame[1], frame[2]]
  const second = [frame[12 * 3], frame[12 * 3 + 1], frame[12 * 3 + 2]]
  assert.notDeepEqual(first, second)
})

test('rainbow flows the hue over time and around the ring', () => {
  const a = pixels({ display: { accent: 'rainbow', brightness: 0.6 } }, 'thinking', 'dsh', 0)
  const b = pixels({ display: { accent: 'rainbow', brightness: 0.6 } }, 'thinking', 'dsh', 1000)
  assert.notDeepEqual(a[0], b[0], 'the hue should drift with time')
  assert.notDeepEqual(a[0], a[23], 'the hue should travel along the ring')
})

test('waiting, done and error ignore the accent palette', () => {
  for (const state of ['waiting', 'done', 'error']) {
    const neon = pixels({ display: { accent: 'neon', brightness: 0.6 } }, state, 'dsh', 0)
    const rainbow = pixels({ display: { accent: 'rainbow', brightness: 0.6 } }, state, 'dsh', 0)
    assert.deepEqual(brightest(neon), brightest(rainbow), `${state} changed with the accent`)
  }

  const waiting = brightest(pixels({ display: { accent: 'neon', brightness: 0.6 } }, 'waiting', 'dsh', 0))
  assert.ok(waiting[0] > waiting[2], `waiting should stay amber, got ${waiting}`)
  const error = brightest(pixels({ display: { accent: 'aurora', brightness: 0.6 } }, 'error', 'dsh', 0))
  assert.ok(error[0] > error[1] && error[0] > error[2], `error should stay red, got ${error}`)
})

test('every accent renders a lit frame without throwing', () => {
  for (const accent of ACCENT_MODES) {
    const leds = pixels({ display: { accent, brightness: 0.6 } })
    const total = leds.reduce((sum, [r, g, b]) => sum + r + g + b, 0)
    assert.ok(total > 0, `${accent} rendered a black frame`)
  }
})

test('the power budget still scales a fully lit ring', () => {
  const frame = renderFrame(snapshot(), {
    config: sanitize({ display: { brightness: 1, currentLimitMa: 300 } }),
  })
  const total = Array.from(frame).reduce((sum, value) => sum + value, 0)
  // 24 LEDs at white would be 24 * 3 * 255 ≈ 18k; a 300 mA cap must cut hard.
  assert.ok(total < 6000, `expected the frame to be scaled down, got ${total}`)
})
