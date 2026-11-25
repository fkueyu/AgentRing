import test from 'node:test'
import assert from 'node:assert/strict'

import { DEFAULTS, isInNightWindow, sanitize } from '../src/config.mjs'

test('clamps values that matter for hardware safety', () => {
  assert.equal(sanitize({ display: { brightness: 9 } }).display.brightness, 1)
  assert.equal(sanitize({ display: { brightness: 0 } }).display.brightness, 0.05)
  assert.equal(sanitize({ display: { currentLimitMa: 99999 } }).display.currentLimitMa, 2000)
  assert.equal(sanitize({ display: { rainbowSpeed: 9 } }).display.rainbowSpeed, 2)
  assert.equal(sanitize({ motion: { staleMinutes: 999 } }).motion.staleMinutes, 60)
  assert.equal(sanitize({ layout: { maxAgents: 99 } }).layout.maxAgents, 8)
})

test('rejects unknown layout modes and effects instead of breaking', () => {
  const cfg = sanitize({ layout: { mode: 'lava' }, motion: { effects: { tool: 'disco' } } })
  assert.equal(cfg.layout.mode, 'split')
  assert.equal(cfg.motion.effects.tool, 'comet')
  assert.equal(cfg.motion.effects.thinking, 'breathe')
})

test('lifts a v1 config into v3 and keeps the old pace per state', () => {
  const cfg = sanitize({ brightness: 0.3, tempo: 2, colors: { codex: 'ff0000', dsh: 'nope' } })
  assert.equal(cfg.version, 3)
  assert.equal(cfg.display.brightness, 0.3)
  assert.equal(cfg.motion.speeds.thinking, 2)
  assert.equal(cfg.motion.speeds.error, 2)
  assert.equal(cfg.motion.tempo, undefined)
  assert.equal(cfg.sources.codex.color, '#ff0000')
  assert.equal(cfg.sources.dsh.color, DEFAULTS.sources.dsh.color)
})

test('integer counts and durations survive fractional legacy values', () => {
  const cfg = sanitize({
    layout: { maxAgents: 4.6, gapLeds: 1.4, rotateSeconds: 8.5 },
    motion: { doneHoldSeconds: 8.7, staleMinutes: 9.6 },
  })
  assert.equal(cfg.layout.maxAgents, 5)
  assert.equal(cfg.layout.gapLeds, 1)
  assert.equal(cfg.layout.rotateSeconds, 9)
  assert.equal(cfg.motion.doneHoldSeconds, 9)
  assert.equal(cfg.motion.staleMinutes, 10)
})

test('partial updates keep the rest of the base config', () => {
  const base = sanitize({ display: { brightness: 0.3 }, layout: { mode: 'focus' } })
  const next = sanitize({ display: { rainbowSpeed: 1.5 } }, base)
  assert.equal(next.display.brightness, 0.3)
  assert.equal(next.layout.mode, 'focus')
  assert.equal(next.display.rainbowSpeed, 1.5)
})

test('night window wraps midnight', () => {
  assert.equal(isInNightWindow(23 * 60 + 30, 23 * 60, 7 * 60), true)
  assert.equal(isInNightWindow(3 * 60, 23 * 60, 7 * 60), true)
  assert.equal(isInNightWindow(12 * 60, 23 * 60, 7 * 60), false)
  assert.equal(isInNightWindow(600, 600, 600), false)
})

test('effects removed from a state migrate to its new default', () => {
  const cfg = sanitize({
    motion: {
      effects: {
        thinking: 'pulse',
        tool: 'solid',
        editing: 'comet',
        waiting: 'solid',
      },
    },
  })
  assert.equal(cfg.motion.effects.thinking, 'breathe')
  assert.equal(cfg.motion.effects.tool, 'comet')
  assert.equal(cfg.motion.effects.editing, 'patches')
  assert.equal(cfg.motion.effects.waiting, 'breathe')
})

test('editing defaults to the read/write patches effect', () => {
  assert.equal(sanitize({}).motion.effects.editing, 'patches')
  assert.ok(sanitize({ motion: { effects: { editing: 'patches' } } }).motion.effects.editing === 'patches')
})

test('standby modes fall back to the single-dot default', () => {
  assert.equal(sanitize({}).display.standby, 'dot')
  assert.equal(sanitize({ display: { standby: 'orbit' } }).display.standby, 'orbit')
  assert.equal(sanitize({ display: { standby: 'laser' } }).display.standby, 'dot')
  assert.equal(sanitize({}).display.standbySpeed, 1)
  assert.equal(sanitize({ display: { standbySpeed: 0.1 } }).display.standbySpeed, 0.2)
  assert.equal(sanitize({ display: { standbySpeed: 4 } }).display.standbySpeed, 3)
  assert.equal(sanitize({}).display.standbyColor, '#b4beff')
  assert.equal(sanitize({ display: { standbyColor: '#ff0000' } }).display.standbyColor, '#ff0000')
  assert.equal(sanitize({ display: { standbyColor: 'red' } }).display.standbyColor, '#b4beff')
})

test('standby palettes default to mono and reject unknown ids', () => {
  assert.equal(sanitize({}).display.standbyPalette, 'mono')
  assert.equal(sanitize({ display: { standbyPalette: 'aurora' } }).display.standbyPalette, 'aurora')
  assert.equal(sanitize({ display: { standbyPalette: 'neon' } }).display.standbyPalette, 'neon')
  assert.equal(sanitize({ display: { standbyPalette: 'state' } }).display.standbyPalette, 'mono')
})

test('a legacy rainbow standby becomes the merged orbit with the rainbow palette', () => {
  const cfg = sanitize({ display: { standby: 'rainbow', standbyColor: '#00ff00' } })
  assert.equal(cfg.display.standby, 'orbit')
  assert.equal(cfg.display.standbyPalette, 'rainbow')
  // The old mono colour survives in case the user switches back to mono.
  assert.equal(cfg.display.standbyColor, '#00ff00')
})

test('an explicit palette wins over the legacy rainbow mapping', () => {
  const cfg = sanitize({ display: { standby: 'rainbow', standbyPalette: 'ember' } })
  assert.equal(cfg.display.standby, 'orbit')
  assert.equal(cfg.display.standbyPalette, 'ember')
})
