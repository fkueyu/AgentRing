import test from 'node:test'
import assert from 'node:assert/strict'

import { ACCENT_MODES, STANDBY_PALETTE_MODES } from '../src/effects.mjs'
import { sanitize } from '../src/config.mjs'

test('the session accent defaults to the semantic state palette', () => {
  const cfg = sanitize({})
  assert.equal(cfg.version, 3)
  assert.equal(cfg.display.accent, 'state')
  assert.deepEqual(ACCENT_MODES, [
    'state',
    'source',
    'neon',
    'sunset',
    'mint',
    'aurora',
    'ember',
    'rainbow',
  ])
})

test('picking an accent is a value change, not a macro', () => {
  const base = sanitize({})
  const neon = sanitize({ display: { accent: 'neon' } }, base)
  assert.equal(neon.display.accent, 'neon')
  // A palette must not rewrite colours, modes or any other setting.
  assert.deepEqual(neon.sources, base.sources)
  assert.deepEqual(neon.stateColors, base.stateColors)
  assert.equal(neon.display.brightness, base.display.brightness)
  assert.equal(neon.display.standbyPalette, base.display.standbyPalette)
})

test('every accent id survives a sanitize round-trip', () => {
  for (const id of ACCENT_MODES) {
    assert.equal(sanitize({ display: { accent: id } }).display.accent, id)
  }
})

test('unknown accents fall back to the base', () => {
  assert.equal(sanitize({ display: { accent: 'lava' } }).display.accent, 'state')
  // `mono` only exists for standby: a single colour cannot identify a state.
  assert.equal(sanitize({ display: { accent: 'mono' } }).display.accent, 'state')
})

test('v2 solid + state migrates to the state palette', () => {
  // The v2 app let the user pick 薄荷 while 单色/按状态 was active, which did
  // not change a single LED. The migration follows what was visible, not the
  // last macro that was clicked.
  const cfg = sanitize({
    version: 2,
    display: {
      theme: 'mint',
      colorMode: 'solid',
      solidColorBy: 'state',
      gradientTo: '#a8e6cf',
      brightness: 0.8,
    },
    sources: { codex: { enabled: true, color: '#2ec4b6' } },
  })
  assert.equal(cfg.display.accent, 'state')
  assert.equal(cfg.display.theme, undefined)
  assert.equal(cfg.display.colorMode, undefined)
  assert.equal(cfg.display.gradientTo, undefined)
  assert.equal(cfg.display.solidColorBy, undefined)
  // Colours the user had already tuned survive.
  assert.equal(cfg.sources.codex.color, '#2ec4b6')
  assert.equal(cfg.display.brightness, 0.8)
})

test('v2 solid + source migrates to the source palette', () => {
  const cfg = sanitize({
    version: 2,
    display: { theme: 'sunset', colorMode: 'solid', solidColorBy: 'source' },
  })
  assert.equal(cfg.display.accent, 'source')
})

test('v2 rainbow migrates to the rainbow palette', () => {
  const cfg = sanitize({
    version: 2,
    display: { theme: 'neon', colorMode: 'rainbow', rainbowSpeed: 0.9 },
  })
  assert.equal(cfg.display.accent, 'rainbow')
  assert.equal(cfg.display.rainbowSpeed, 0.9)
})

test('v2 gradient keeps a curated ramp and otherwise falls back to identity', () => {
  assert.equal(
    sanitize({ version: 2, display: { theme: 'neon', colorMode: 'gradient' } }).display.accent,
    'neon',
  )
  assert.equal(
    sanitize({ version: 2, display: { theme: 'custom', colorMode: 'gradient' } }).display.accent,
    'state',
  )
  assert.equal(
    sanitize({
      version: 2,
      display: { theme: 'default', colorMode: 'gradient' },
    }).display.accent,
    'state',
  )
})

test('a saved v3 config reloads unchanged', () => {
  const saved = sanitize({
    display: { accent: 'aurora', standbyPalette: 'ember', brightness: 0.7 },
    sources: { codex: { enabled: false, color: '#123456' } },
    stateColors: { waiting: '#ffcc00' },
  })
  assert.deepEqual(sanitize(saved), saved)
})

test('standby palettes share the curated ramps but stay standby-only', () => {
  assert.deepEqual(STANDBY_PALETTE_MODES, [
    'mono',
    'neon',
    'sunset',
    'mint',
    'aurora',
    'ember',
    'rainbow',
  ])
  assert.equal(sanitize({ display: { standbyPalette: 'neon' } }).display.standbyPalette, 'neon')
  // `state` / `source` describe a running session, not an idle ring.
  assert.equal(sanitize({ display: { standbyPalette: 'state' } }).display.standbyPalette, 'mono')
  assert.equal(sanitize({ display: { standbyPalette: 'laser' } }).display.standbyPalette, 'mono')
})
