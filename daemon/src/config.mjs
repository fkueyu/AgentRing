// Ring display settings.
//
// The daemon owns the whole look: `/frame` is what the preview shows and what
// the ESP32 pushes to the strip, so every option here has one implementation
// instead of two.
//
// v3 keeps one colour axis. `display.accent` decides what a running session is
// coloured by (state / source / a curated ramp / rainbow); the idle ring picks
// from the same palette catalogue via `display.standbyPalette`. Themes were
// removed because they were macros that silently rewrote unrelated fields.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import {
  ACCENT_MODES,
  EFFECTS,
  EFFECT_DEFAULTS,
  STANDBY_CATALOG,
  STANDBY_MODES,
  STANDBY_PALETTE_MODES,
} from './effects.mjs'

export const CONFIG_DIR = path.join(os.homedir(), '.agentring')
export const CONFIG_PATH = path.join(CONFIG_DIR, 'config.json')
export const CONFIG_VERSION = 3

export { EFFECTS }
export const LAYOUT_MODES = ['split', 'focus', 'rotate']

export const DEFAULTS = Object.freeze({
  version: CONFIG_VERSION,
  display: {
    // What a running session's arc is coloured by. `state` and `source` are
    // identity palettes; neon / sunset / mint / aurora / ember are curated
    // ramps; rainbow flows the hue wheel.
    accent: 'state',
    // Hue travel of the rainbow palette (accent only).
    rainbowSpeed: 0.35,
    brightness: 0.5,
    // What a single dim LED does while no agent is working, and the palette it
    // draws with. `standbyColor` is the mono palette only.
    standby: STANDBY_CATALOG.default,
    standbyPalette: 'mono',
    standbySpeed: 1,
    standbyColor: '#b4beff',
    // 1.0 keeps the hand-tuned levels; raising it darkens mid-tones and makes
    // fades punchier (FastLED-style gamma).
    gamma: 1,
    // WS2812B budget: 24 LEDs at full white ≈ 1.44 A. The renderer scales the
    // frame down when the estimated draw exceeds this.
    currentLimitMa: 900,
    nightMode: {
      enabled: false,
      startMinute: 23 * 60,
      endMinute: 7 * 60,
      brightness: 0.08,
    },
  },
  layout: {
    mode: 'split',
    maxAgents: 4,
    gapLeds: 1,
    showIdle: false,
    rotateSeconds: 8,
  },
  motion: {
    speeds: {
      thinking: 1,
      tool: 1,
      editing: 1,
      waiting: 1,
      done: 1,
      error: 1,
    },
    effects: { ...EFFECT_DEFAULTS },
    doneHoldSeconds: 8,
    staleMinutes: 10,
  },
  // Semantic state palette: distinct at a glance, and configurable for the
  // ring's physical appearance. Waiting / done / error always use these, in
  // every accent palette.
  stateColors: {
    thinking: '#4d6bfe',
    tool: '#2e9bff',
    editing: '#a855f7',
    waiting: '#ffaa28',
    done: '#28dc6e',
    error: '#ff3030',
  },
  sources: {
    codex: { enabled: true, color: '#10a37f' },
    dsh: { enabled: true, color: '#4d6bfe' },
    claude: { enabled: true, color: '#d97757' },
    gemini: { enabled: true, color: '#4a8cff' },
    cursor: { enabled: true, color: '#8b5cf6' },
    opencode: { enabled: true, color: '#10b981' },
    qwen: { enabled: true, color: '#6366f1' },
    kimi: { enabled: true, color: '#22d3ee' },
    grok: { enabled: true, color: '#e5e7eb' },
    pi: { enabled: true, color: '#f472b6' },
    omp: { enabled: true, color: '#fbbf24' },
    qoder: { enabled: true, color: '#34d399' },
    factory: { enabled: true, color: '#fb7185' },
    codebuddy: { enabled: true, color: '#60a5fa' },
    zcode: { enabled: true, color: '#f59e0b' },
    hermes: { enabled: true, color: '#a78bfa' },
    trae: { enabled: true, color: '#ff4d4d' },
    workbuddy: { enabled: true, color: '#ff9f0a' },
  },
})

const HEX = /^#?([0-9a-f]{6})$/i

export function parseHex(hex) {
  if (typeof hex !== 'string') return null
  const m = HEX.exec(hex.trim())
  if (!m) return null
  const n = parseInt(m[1], 16)
  return [n >> 16, (n >> 8) & 0xff, n & 0xff]
}

export function toHex([r, g, b]) {
  return (
    '#' +
    [r, g, b]
      .map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0'))
      .join('')
  )
}

function num(value, min, max, fallback) {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

function minutes(value, fallback) {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.min(1439, Math.max(0, Math.round(n)))
}

function oneOf(value, allowed, fallback) {
  return allowed.includes(value) ? value : fallback
}

/** v1 stored a flat brightness/tempo/colors object; v2 grouped it. */
function liftV1(input) {
  if (input.version >= 2 || input.display || input.layout || input.motion || input.sources) {
    return input
  }
  const carried = {}
  if (typeof input.brightness === 'number') carried.brightness = input.brightness
  const tempo = typeof input.tempo === 'number' ? num(input.tempo, 0.2, 3, 1) : null
  const colors = {}
  if (input.colors && typeof input.colors === 'object') {
    for (const [key, value] of Object.entries(input.colors)) {
      if (parseHex(value)) colors[key] = { enabled: true, color: toHex(parseHex(value)) }
    }
  }
  return {
    version: 2,
    display: { brightness: carried.brightness },
    motion:
      tempo === null
        ? {}
        : {
            // The old global tempo seeded every state before per-state speeds
            // existed; keep the pace through the migration.
            speeds: Object.fromEntries(
              Object.keys(EFFECTS).map((state) => [state, Math.round(tempo * 10) / 10]),
            ),
          },
    sources: colors,
  }
}

/**
 * v2 split colour into `theme` + `colorMode` + `solidColorBy` + `gradientTo`,
 * but only one combination reached the LEDs (solid/state ignored the theme
 * entirely). The migration keeps the visible result:
 *
 * - rainbow mode → the rainbow palette;
 * - a gradient built from a curated theme → that ramp;
 * - everything else → the identity palette that was actually in use.
 */
function liftV2(input) {
  const display = input.display
  if (!display || display.accent !== undefined) return input
  const legacy = ['theme', 'colorMode', 'gradientTo', 'solidColorBy']
  if (!legacy.some((key) => key in display)) return input

  const identity = display.solidColorBy === 'source' ? 'source' : 'state'
  let accent = identity
  if (display.colorMode === 'rainbow') accent = 'rainbow'
  else if (
    display.colorMode === 'gradient' &&
    ['neon', 'sunset', 'mint'].includes(display.theme)
  ) {
    accent = display.theme
  }

  const rest = { ...display }
  for (const key of legacy) delete rest[key]
  return { ...input, version: CONFIG_VERSION, display: { ...rest, accent } }
}

/**
 * Build a valid v3 config from an arbitrary partial object.
 *
 * The app posts its whole config on every edit, so every field is read as a
 * plain value: there is no "did the caller mean to change this?" heuristic and
 * no theme that overwrites other fields.
 */
export function sanitize(rawInput = {}, base = DEFAULTS) {
  const input = rawInput && typeof rawInput === 'object' ? liftV2(liftV1(rawInput)) : {}
  const display = input.display || {}
  const layout = input.layout || {}
  const motion = input.motion || {}
  const night = display.nightMode || {}

  // `rainbow` used to be a standby mode, but it drew exactly the same comet as
  // `orbit` and only changed the colour. Old configs (and old app builds) are
  // lifted to the merged motion plus the rainbow palette.
  const legacyRainbow = display.standby === 'rainbow'
  const standby = oneOf(legacyRainbow ? 'orbit' : display.standby, STANDBY_MODES, base.display.standby)
  const requestedPalette =
    legacyRainbow && display.standbyPalette === undefined ? 'rainbow' : display.standbyPalette

  const config = {
    version: CONFIG_VERSION,
    display: {
      accent: oneOf(display.accent, ACCENT_MODES, base.display.accent),
      rainbowSpeed: num(display.rainbowSpeed, 0, 2, base.display.rainbowSpeed),
      brightness: num(display.brightness, 0.05, 1, base.display.brightness),
      standby,
      standbyPalette: oneOf(requestedPalette, STANDBY_PALETTE_MODES, base.display.standbyPalette),
      standbySpeed: num(display.standbySpeed, 0.2, 3, base.display.standbySpeed),
      standbyColor: parseHex(display.standbyColor)
        ? toHex(parseHex(display.standbyColor))
        : base.display.standbyColor,
      gamma: num(display.gamma, 0.8, 2.6, base.display.gamma),
      currentLimitMa: num(display.currentLimitMa, 300, 2000, base.display.currentLimitMa),
      nightMode: {
        enabled: Boolean(night.enabled ?? base.display.nightMode.enabled),
        startMinute: minutes(night.startMinute, base.display.nightMode.startMinute),
        endMinute: minutes(night.endMinute, base.display.nightMode.endMinute),
        brightness: num(night.brightness, 0.02, 0.5, base.display.nightMode.brightness),
      },
    },
    layout: {
      mode: oneOf(layout.mode, LAYOUT_MODES, base.layout.mode),
      // Counts and second/minute durations are integers; the old sliders
      // persisted values like 4.32 and 1.18, which the pickers now round for
      // display but the renderer should not have to guess about.
      maxAgents: Math.round(num(layout.maxAgents, 1, 8, base.layout.maxAgents)),
      gapLeds: Math.round(num(layout.gapLeds, 0, 3, base.layout.gapLeds)),
      showIdle: Boolean(layout.showIdle ?? base.layout.showIdle),
      rotateSeconds: Math.round(num(layout.rotateSeconds, 3, 60, base.layout.rotateSeconds)),
    },
    motion: {
      speeds: Object.fromEntries(
        Object.entries(EFFECTS).map(([state]) => {
          const prior = base.motion.speeds?.[state]
          const value = num(motion.speeds?.[state], 0.2, 3, num(prior, 0.2, 3, 1))
          return [state, Math.round(value * 10) / 10]
        }),
      ),
      effects: Object.fromEntries(
        Object.entries(EFFECTS).map(([state, allowed]) => {
          // An effect removed from a state (e.g. the old thinking pulse) must
          // land on that state's new default, not on an invalid base value.
          const prior = base.motion.effects?.[state]
          const fallback = allowed.includes(prior) ? prior : EFFECT_DEFAULTS[state]
          return [state, oneOf(motion.effects?.[state], allowed, fallback)]
        }),
      ),
      doneHoldSeconds: Math.round(num(motion.doneHoldSeconds, 2, 30, base.motion.doneHoldSeconds)),
      staleMinutes: Math.round(num(motion.staleMinutes, 2, 60, base.motion.staleMinutes)),
    },
    sources: {},
  }

  config.stateColors = { ...base.stateColors }
  if (input.stateColors && typeof input.stateColors === 'object') {
    for (const key of Object.keys(config.stateColors)) {
      const hex = parseHex(input.stateColors[key])
      if (hex) config.stateColors[key] = toHex(hex)
    }
  }

  const incoming = input.sources && typeof input.sources === 'object' ? input.sources : {}
  for (const key of new Set([...Object.keys(base.sources), ...Object.keys(incoming)])) {
    const prior = base.sources[key] || { enabled: true, color: '#8c8ca0' }
    const next = incoming[key] || {}
    config.sources[key] = {
      enabled: Boolean(next.enabled ?? prior.enabled),
      color: parseHex(next.color) ? toHex(parseHex(next.color)) : prior.color,
    }
  }

  return config
}

export function loadConfig() {
  try {
    const raw = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'))
    const config = sanitize(raw)
    // Persist the migrated shape once, so the file stops carrying the v2
    // theme/colorMode keys that no longer do anything.
    if (raw?.version !== CONFIG_VERSION) {
      try {
        saveConfig(config)
      } catch {}
    }
    return config
  } catch {
    return sanitize({})
  }
}

export function saveConfig(config) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true })
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2) + '\n')
  return config
}

/** Minutes-of-day helper shared by the renderer and the UI. */
export function isInNightWindow(minuteOfDay, startMinute, endMinute) {
  if (startMinute === endMinute) return false
  if (startMinute < endMinute) return minuteOfDay >= startMinute && minuteOfDay < endMinute
  return minuteOfDay >= startMinute || minuteOfDay < endMinute
}
