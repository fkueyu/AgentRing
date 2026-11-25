import test from 'node:test'
import assert from 'node:assert/strict'

import { sanitize } from '../src/config.mjs'
import { renderFrame } from '../src/frame.mjs'
import { STANDBY_PALETTE_MODES } from '../src/effects.mjs'

const CURATED = STANDBY_PALETTE_MODES.filter((id) => id !== 'mono')

function frameAt(mode, ms, extra = {}) {
  const config = sanitize({ display: { standby: mode, brightness: 0.8, ...extra } })
  return renderFrame({ ts: ms, agents: [] }, { config, now: ms })
}

function lit(frame) {
  return Array.from({ length: 24 }, (_, i) => ({
    index: i,
    value: Math.max(frame[i * 3], frame[i * 3 + 1], frame[i * 3 + 2]),
    rgb: [frame[i * 3], frame[i * 3 + 1], frame[i * 3 + 2]],
  })).filter((entry) => entry.value > 0)
}

function brightest(frame) {
  return lit(frame).sort((a, b) => b.value - a.value)[0]
}

test('standby dot keeps exactly one LED lit with every palette', () => {
  for (const palette of STANDBY_PALETTE_MODES) {
    for (const ms of [0, 900, 2400, 5100]) {
      assert.equal(
        lit(frameAt('dot', ms, { standbyPalette: palette })).length,
        1,
        `${palette} dot at ${ms}`,
      )
    }
  }
})

test('standby orbit renders a bright head and a short tail', () => {
  for (const ms of [0, 900, 2400, 5100]) {
    const entries = lit(frameAt('orbit', ms))
    assert.ok(entries.length >= 3 && entries.length <= 5, `orbit at ${ms}: ${entries.length}`)
    entries.sort((a, b) => b.value - a.value)
    assert.ok(entries[0].value > entries[entries.length - 1].value * 2, 'head is brighter than tail')
  }
})

test('orbit motion is the same in every palette; only the colour changes', () => {
  const frames = Object.fromEntries(
    STANDBY_PALETTE_MODES.map((palette) => [
      palette,
      frameAt('orbit', 1430, { standbyPalette: palette }),
    ]),
  )
  const indices = Object.fromEntries(
    Object.entries(frames).map(([palette, frame]) => [
      palette,
      lit(frame).map((entry) => entry.index).sort((a, b) => a - b),
    ]),
  )
  for (const palette of CURATED) {
    assert.deepEqual(indices[palette], indices.mono, `${palette} moved the comet`)
    assert.notDeepEqual(
      lit(frames[palette]).map((entry) => entry.rgb),
      lit(frames.mono).map((entry) => entry.rgb),
      `${palette} should recolour the comet`,
    )
  }
})

test('standby breathe never leaves the ring dark and overlaps one fade with the next', () => {
  for (let ms = 0; ms <= 6000; ms += 100) {
    assert.ok(lit(frameAt('breathe', ms)).length >= 1, `dark at ${ms}`)
  }

  // At 2.8 s the next breath starts while the previous one is almost out.
  const overlap = lit(frameAt('breathe', 2800))
  assert.equal(overlap.length, 2)
  assert.ok(overlap.every((entry) => entry.value < 40), JSON.stringify(overlap))
})

test('the rainbow palette moves its head and changes colour', () => {
  const config = { standbyPalette: 'rainbow' }
  const first = frameAt('orbit', 1000, config)
  const second = frameAt('orbit', 2000, config)
  const a = brightest(first)
  const b = brightest(second)
  assert.notEqual(a.index, b.index)
  assert.notDeepEqual(a.rgb, b.rgb)
})

test('standby random breathing changes position between slots', () => {
  const indices = new Set([500, 3400, 6200, 9000].map((ms) => brightest(frameAt('breathe', ms)).index))
  assert.ok(indices.size > 1, `positions stayed at ${[...indices]}`)
})

test('standby speed changes orbit and breath timing', () => {
  const slow = frameAt('orbit', 1000, { standbySpeed: 1 })
  const fast = frameAt('orbit', 1000, { standbySpeed: 2 })
  assert.notEqual(brightest(slow).index, brightest(fast).index)

  const slowBreathe = lit(frameAt('breathe', 2800, { standbySpeed: 1 }))
  const fastBreathe = lit(frameAt('breathe', 2800, { standbySpeed: 2 }))
  assert.notDeepEqual(slowBreathe.map((entry) => entry.index), fastBreathe.map((entry) => entry.index))
})

test('mono uses the colour well; curated palettes ignore it', () => {
  const dot = lit(frameAt('dot', 1000, { standbyColor: '#ff0000' }))[0]
  assert.deepEqual(dot.rgb, [24, 0, 0])

  for (const entry of lit(frameAt('orbit', 1000, { standbyColor: '#ff0000' }))) {
    assert.ok(entry.rgb[0] > 0)
    assert.equal(entry.rgb[1], 0)
    assert.equal(entry.rgb[2], 0)
  }

  for (const palette of CURATED) {
    const entries = lit(frameAt('orbit', 1000, { standbyPalette: palette, standbyColor: '#ff0000' }))
    assert.ok(
      entries.some((entry) => entry.rgb[1] > 0 || entry.rgb[2] > 0),
      `${palette} should not collapse to the mono colour`,
    )
  }
})

test('the aurora palette runs cool and the ember palette runs warm', () => {
  for (const ms of [1000, 2200]) {
    const aurora = brightest(frameAt('orbit', ms, { standbyPalette: 'aurora', brightness: 1 }))
    const ember = brightest(frameAt('orbit', ms, { standbyPalette: 'ember', brightness: 1 }))
    // Aurora starts teal (green/blue), ember starts cream/amber (red above blue).
    assert.ok(aurora.rgb[2] + aurora.rgb[1] > aurora.rgb[0] * 2, `aurora at ${ms}: ${aurora.rgb}`)
    assert.ok(ember.rgb[0] > ember.rgb[2], `ember at ${ms}: ${ember.rgb}`)
  }
})
