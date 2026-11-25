import test from 'node:test'
import assert from 'node:assert/strict'

import {
  ACCENT_CATALOG,
  ACCENT_MODES,
  EFFECT_CATALOG,
  EFFECTS,
  EFFECT_DEFAULTS,
  PALETTES,
  STANDBY_CATALOG,
  STANDBY_MODES,
  STANDBY_PALETTES,
  STANDBY_PALETTE_MODES,
  capabilities,
} from '../src/effects.mjs'
import { EFFECTS as CONFIG_EFFECTS } from '../src/config.mjs'

test('the effect catalogue is internally consistent', () => {
  for (const [state, group] of Object.entries(EFFECT_CATALOG)) {
    assert.ok(group.options.length > 0, `${state} has options`)
    const ids = group.options.map((option) => option.id)
    assert.equal(new Set(ids).size, ids.length, `${state} option ids are unique`)
    assert.ok(ids.includes(group.default), `${state} default is an option`)
    for (const option of group.options) {
      assert.ok(option.label.length > 0, `${state}/${option.id} has a label`)
      assert.ok(option.hint.length > 0, `${state}/${option.id} has a hint`)
    }
  }
  assert.deepEqual(EFFECTS, Object.fromEntries(
    Object.entries(EFFECT_CATALOG).map(([state, group]) => [state, group.options.map((option) => option.id)]),
  ))
  assert.deepEqual(EFFECT_DEFAULTS, Object.fromEntries(
    Object.entries(EFFECT_CATALOG).map(([state, group]) => [state, group.default]),
  ))
})

test('the per-state motion presets match the product spec', () => {
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(EFFECT_CATALOG).map(([state, group]) => [
        state,
        group.options.map((option) => option.id),
      ]),
    ),
    {
      thinking: ['breathe', 'comet'],
      tool: ['breathe', 'comet', 'pulse'],
      editing: ['patches', 'pulse'],
      waiting: ['breathe', 'blink'],
      done: ['flash', 'solid'],
      error: ['blink', 'solid'],
    },
  )
  assert.deepEqual(
    Object.fromEntries(Object.entries(EFFECT_CATALOG).map(([state, group]) => [state, group.default])),
    { thinking: 'breathe', tool: 'comet', editing: 'patches', waiting: 'breathe', done: 'flash', error: 'blink' },
  )
  assert.equal(EFFECT_CATALOG.thinking.options[1].label, '巡游')
  assert.equal(EFFECT_CATALOG.editing.options[0].label, '雨滴')
})

test('the standby catalogue is internally consistent', () => {
  const ids = STANDBY_CATALOG.options.map((option) => option.id)
  assert.deepEqual(STANDBY_MODES, ids)
  assert.equal(new Set(ids).size, ids.length)
  assert.ok(ids.includes(STANDBY_CATALOG.default))
  for (const option of STANDBY_CATALOG.options) assert.ok(option.label.length > 0)

  // Colour is a separate axis now: the two orbit variants that only differed
  // in colour were merged into one motion.
  assert.deepEqual(ids, ['dot', 'orbit', 'breathe'])
})

test('the session accent catalogue is internally consistent', () => {
  const ids = ACCENT_CATALOG.options.map((option) => option.id)
  assert.deepEqual(ACCENT_MODES, ids)
  assert.equal(new Set(ids).size, ids.length)
  assert.ok(ids.includes(ACCENT_CATALOG.default))
  assert.deepEqual(ids, [
    'state',
    'source',
    'neon',
    'sunset',
    'mint',
    'aurora',
    'ember',
    'rainbow',
  ])
  for (const option of ACCENT_CATALOG.options) {
    assert.ok(option.label.length > 0, `${option.id} has a label`)
    assert.ok(option.blurb.length > 0, `${option.id} has a blurb`)
    assert.ok(['state', 'source', 'ramp', 'hue'].includes(option.kind), `${option.id} kind`)
    for (const hex of option.colors) assert.match(hex, /^#[0-9a-f]{6}$/i)
  }
  assert.equal(ACCENT_CATALOG.options.find((option) => option.id === 'state').colors.length, 0)
  assert.equal(ACCENT_CATALOG.options.find((option) => option.id === 'rainbow').kind, 'hue')
})

test('the standby palette shares the curated ramps but adds mono', () => {
  const ids = STANDBY_PALETTES.options.map((option) => option.id)
  assert.deepEqual(STANDBY_PALETTE_MODES, ids)
  assert.equal(new Set(ids).size, ids.length)
  assert.ok(ids.includes(STANDBY_PALETTES.default))
  assert.deepEqual(ids, ['mono', 'neon', 'sunset', 'mint', 'aurora', 'ember', 'rainbow'])
  for (const option of STANDBY_PALETTES.options) {
    assert.ok(option.label.length > 0, `${option.id} has a label`)
    for (const hex of option.colors) assert.match(hex, /^#[0-9a-f]{6}$/i)
  }
  // Only mono is user-coloured; the rest are curated.
  assert.equal(STANDBY_PALETTES.options.find((option) => option.id === 'mono').colors.length, 0)
  for (const id of ['neon', 'sunset', 'mint', 'aurora', 'ember']) {
    const accent = ACCENT_CATALOG.options.find((option) => option.id === id)
    const standby = STANDBY_PALETTES.options.find((option) => option.id === id)
    assert.equal(standby, accent, `${id} must be the same object in both pickers`)
    assert.ok(standby.colors.length >= 3, `${id} provides ramp stops`)
  }
})

test('every palette id resolves through one lookup', () => {
  for (const id of [...ACCENT_MODES, ...STANDBY_PALETTE_MODES]) {
    assert.ok(PALETTES[id], `${id} missing from PALETTES`)
  }
})

test('the config and capabilities endpoints share the catalogue', () => {
  assert.deepEqual(CONFIG_EFFECTS, EFFECTS)
  const snapshot = capabilities()
  assert.equal(snapshot.version, 2)
  assert.deepEqual(snapshot.standby, STANDBY_CATALOG)
  assert.deepEqual(snapshot.accents, ACCENT_CATALOG)
  assert.deepEqual(snapshot.standbyPalettes, STANDBY_PALETTES)
  for (const [state, group] of Object.entries(EFFECT_CATALOG)) {
    assert.deepEqual(snapshot.effects[state], { default: group.default, options: group.options })
  }
})
