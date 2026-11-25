// Turns a state snapshot into 24 RGB triples.
//
// This is the single source of truth for the ring's look: the app preview just
// displays these frames, and the ESP32 pushes the same bytes to the strip.
// Layout mode, per-state effects, accent palette, gamma, night mode and the
// power budget all live here so the preview cannot drift from the hardware.

import { AMBER, GREEN, LED_COUNT, RED, colorFor } from './protocol.mjs'
import { DEFAULTS, isInNightWindow, parseHex } from './config.mjs'
import { PALETTES } from './effects.mjs'

/** Rough per-channel current of a WS2812B at full duty. */
const MA_PER_CHANNEL = 20

/**
 * Parsed stops for every curated ramp. The catalogue owns the hex values, so
 * the app tiles and the rendered LEDs cannot drift.
 */
const PALETTE_STOPS = Object.freeze(
  Object.fromEntries(
    Object.values(PALETTES)
      .filter((option) => option.kind === 'ramp' && option.colors.length > 0)
      .map((option) => [option.id, option.colors.map((hex) => parseHex(hex)).filter(Boolean)]),
  ),
)

export function renderFrame(snap, { leds = LED_COUNT, config, now = Date.now() } = {}) {
  const cfg = config ?? DEFAULTS
  const out = new Uint8Array(leds * 3)
  const t = snap.ts / 1000

  const agents = selectAgents(snap.agents, cfg, now)
  if (agents.length === 0) {
    return renderStandby(out, cfg, now)
  }

  const lit = new Map()
  if (cfg.layout.mode === 'split' && agents.length > 1) {
    // Distribute the remainder instead of giving every spare LED to the last
    // agent: 24 LEDs across 5 agents should be 5/5/5/5/4, not 4/4/4/4/8.
    const segments = agents.length
    const baseSpan = Math.floor(leds / segments)
    const extra = leds % segments
    let start = 0
    agents.forEach((agent, segment) => {
      const span = Math.max(1, baseSpan + (segment < extra ? 1 : 0))
      const usable = Math.max(1, span - cfg.layout.gapLeds)
      for (let j = 0; j < usable; j++) {
        lit.set((start + j) % leds, lightFor(agent, j, usable, t, cfg, segment, segments))
      }
      start += span
    })
  } else {
    const agent = agents[0]
    for (let j = 0; j < leds; j++) {
      lit.set(j, lightFor(agent, j, leds, t, cfg, 0, 1))
    }
  }

  const brightness = effectiveBrightness(cfg, now)
  const channels = new Float64Array(leds * 3)
  let estimatedMa = 0

  for (const [index, entry] of lit) {
    // Gamma shapes the perceived fade; brightness then scales the result so
    // low levels still fall off smoothly instead of clipping to 0.
    const shaped = Math.pow(Math.max(0, entry.level), cfg.display.gamma) * brightness
    for (let c = 0; c < 3; c++) {
      const value = Math.min(1, (entry.color[c] / 255) * shaped)
      channels[index * 3 + c] = value
      estimatedMa += value * MA_PER_CHANNEL
    }
  }

  const budget = Number(cfg.display.currentLimitMa)
  const scale = estimatedMa > budget ? budget / estimatedMa : 1

  for (let i = 0; i < channels.length; i++) {
    out[i] = Math.round(channels[i] * scale * 255)
  }
  return out
}

// MARK: - Standby

function standbyIndex(slot, leds) {
  let index = Math.floor(hash01(slot * 37 + 11) * leds) % leds
  if (slot > 0) {
    const previous = Math.floor(hash01((slot - 1) * 37 + 11) * leds) % leds
    if (index === previous) index = (index + 1) % leds
  }
  return index
}

/// One LED is always visible while no agent is working. Motion and colour are
/// separate axes: the mode decides what the light does, the palette decides
/// what colour it is. Every mode keeps exactly one LED lit and follows night
/// mode.
function renderStandby(out, cfg, now) {
  const leds = out.length / 3
  if (leds < 1) return out
  const brightness = effectiveBrightness(cfg, now)
  const t = now / 1000
  const speed = cfg.display.standbySpeed ?? 1
  const mode = cfg.display.standby || 'dot'
  const spec = PALETTES[cfg.display.standbyPalette] || PALETTES.mono
  const baseColor = parseHex(cfg.display.standbyColor) || [180, 190, 255]

  if (mode === 'orbit') {
    // A short comet rather than one hard-stepping pixel: a fractional head
    // splits over two LEDs, with two dim tail LEDs behind it. At 24 LEDs and
    // ~30 fps this reads as continuous rotation instead of discrete jumps.
    const pos = (t * speed * 4) % leds
    const tailLength = Math.min(2.5, leds - 1)
    for (let i = 0; i < leds; i++) {
      const behind = (pos - i + leds) % leds
      let level = 0
      if (behind <= tailLength) {
        const x = 1 - behind / tailLength
        const smooth = x * x * (3 - 2 * x)
        level = 0.08 + 0.92 * smooth
      }

      // Sub-LED head: split the peak between the two nearest LEDs.
      let delta = i - pos
      if (delta > leds / 2) delta -= leds
      if (delta < -leds / 2) delta += leds
      const head = Math.exp(-(delta * delta) / (2 * 0.42 * 0.42))
      level = Math.max(level, head)
      if (level <= 0.01) continue

      // The LED just ahead of the head shares the head colour; only the tail
      // travels along the palette ramp.
      const tail = behind <= tailLength ? behind / tailLength : 0
      paint(out, i, orbitColor(spec, baseColor, tail, t, speed), level * brightness)
    }
    return out
  }

  if (mode === 'breathe') {
    // Each breath lasts 1/0.95 slots, so the next LED starts while the
    // previous breath is at ~5% intensity. The overlap is a crossfade, not a
    // dark gap. The floor keeps one LED alive exactly at the slot boundary.
    const slotSeconds = 2.8
    const slotFloat = (t * speed) / slotSeconds
    const slot = Math.floor(slotFloat)
    const progress = (slotFloat - slot) * 0.95
    const levelAt = (p) => 0.03 + 0.87 * Math.pow(Math.sin(Math.PI * p), 2)

    const index = standbyIndex(slot, leds)
    paint(out, index, ambientColor(spec, baseColor, index, leds, t, speed), levelAt(progress) * brightness)
    if (slot > 0) {
      const previousProgress = progress + 0.95
      if (previousProgress < 1) {
        const previous = standbyIndex(slot - 1, leds)
        paint(
          out,
          previous,
          ambientColor(spec, baseColor, previous, leds, t, speed),
          levelAt(previousProgress) * brightness,
        )
      }
    }
    return out
  }

  // dot (default): the original single dim marker.
  paint(out, 0, ambientColor(spec, baseColor, 0, leds, t, speed), 0.12 * brightness)
  return out
}

/// Colour of the comet at `tail` (0 = head, 1 = end of the tail).
function orbitColor(spec, baseColor, tail, t, speed) {
  if (spec.kind === 'hue') {
    // Keep the old rainbow cadence: the hue drifts with time and shifts a
    // little along the short tail so the comet does not look monochrome.
    return hsv((t * speed * 60 + tail * 43) % 360, 0.9, 1)
  }
  if (spec.kind === 'ramp') return sampleRamp(PALETTE_STOPS[spec.id], tail, false) || baseColor
  return baseColor
}

/// Colour of a single standby light at ring position `index`.
function ambientColor(spec, baseColor, index, leds, t, speed) {
  if (spec.kind === 'hue') {
    return hsv((t * speed * 60 + (index / leds) * 360) % 360, 0.9, 1)
  }
  if (spec.kind === 'ramp') {
    // Ping-pong the gradient around the ring so the last LED meets the first
    // without a colour seam at twelve o'clock.
    const position = 0.5 - 0.5 * Math.cos((index / leds) * Math.PI * 2)
    return sampleRamp(PALETTE_STOPS[spec.id], position) || baseColor
  }
  return baseColor
}

/// Interpolate a ramp at `position` (0..1). Cyclic ramps wrap last→first, which
/// is what the ring needs; a linear ramp is used along a comet tail.
function sampleRamp(stops, position, cyclic = true) {
  if (!stops || stops.length === 0) return null
  if (stops.length === 1) return stops[0]

  const n = stops.length
  const p = Math.max(0, Math.min(1, position))
  const x = cyclic ? (((p % 1) + 1) % 1) * n : p * (n - 1)
  const floor = Math.floor(x)
  const index = cyclic ? floor % n : Math.min(n - 2, floor)
  const k = x - floor
  const from = stops[index]
  const to = stops[cyclic ? (index + 1) % n : index + 1]
  return [
    from[0] + (to[0] - from[0]) * k,
    from[1] + (to[1] - from[1]) * k,
    from[2] + (to[2] - from[2]) * k,
  ]
}

// MARK: - Selection

function selectAgents(all, cfg, now) {
  let agents = all.filter((agent) => {
    const source = cfg.sources?.[agent.source]
    if (source && source.enabled === false) return false
    if (agent.state === 'idle' && !cfg.layout.showIdle) return false
    return agent.state !== 'offline' && agent.state !== 'unknown'
  })

  agents = agents.slice(0, Math.max(1, Math.round(cfg.layout.maxAgents)))
  if (agents.length === 0) return []

  if (cfg.layout.mode === 'focus') return agents.slice(0, 1)
  if (cfg.layout.mode === 'rotate') {
    const slot = Math.floor(now / 1000 / cfg.layout.rotateSeconds)
    return [agents[slot % agents.length]]
  }
  return agents
}

function effectiveBrightness(cfg, now) {
  const night = cfg.display.nightMode
  if (night?.enabled) {
    const date = new Date(now)
    const minute = date.getHours() * 60 + date.getMinutes()
    if (isInNightWindow(minute, night.startMinute, night.endMinute)) {
      return Math.min(cfg.display.brightness, night.brightness)
    }
  }
  return cfg.display.brightness
}

// MARK: - Effects

function lightFor(agent, j, size, t, cfg, segment, segments) {
  const source = cfg.sources?.[agent.source]
  // `colorFor` used to be called with a single hex instead of a map, so the
  // per-source colour wells in the app never reached the LEDs. A configured
  // hex now wins; the brand colour is only the fallback.
  const sourceColor = hexToRgb(source?.color) || colorFor(agent.source)
  const speed = cfg.motion.speeds?.[agent.state] ?? 1
  const localT = t * speed
  const span = Math.max(1, size)
  const semantic = (name, fallback) => hexToRgb(cfg.stateColors?.[name]) || fallback

  // The accent palette decides the "busy" colour. Waiting / done / error pass
  // their semantic accent to `effectOf`, which overrides this base entirely.
  const base = accentColor(cfg, { state: agent.state, segment, segments, j, size: span, t: localT, sourceColor })
  const since = agent.sinceMs / 1000

  switch (agent.state) {
    case 'thinking':
      return effectOf(cfg.motion.effects.thinking, base, { j, size: span, t: localT, speed })
    case 'tool':
      return effectOf(cfg.motion.effects.tool, base, { j, size: span, t: localT, speed })
    case 'editing':
      return effectOf(cfg.motion.effects.editing, base, {
        j,
        size: span,
        t: localT,
        speed,
        seed: hashString(agent.key || agent.source || ''),
      })
    case 'waiting':
      return effectOf(cfg.motion.effects.waiting, base, {
        j,
        size: span,
        t: localT,
        speed,
        accent: semantic('waiting', AMBER),
      })
    case 'error':
      return effectOf(cfg.motion.effects.error, base, {
        j,
        size: span,
        t: localT,
        speed,
        accent: semantic('error', RED),
      })
    case 'done':
      return effectOf(cfg.motion.effects.done, base, {
        j,
        size: span,
        t: localT,
        speed,
        accent: semantic('done', GREEN),
        since,
      })
    default:
      return { color: base, level: 0.08 }
  }
}

/**
 * Resolve what colour a running session's LED gets from `display.accent`.
 *
 * - `state` / `source`: identity palettes (state wells / tool colours);
 * - curated ramps: the stops are spread around the whole ring, so a 4-agent
 *   ring shows four slices of one palette and a lone agent shows all of it;
 * - `rainbow`: the hue wheel rotates with `rainbowSpeed`.
 */
function accentColor(cfg, { state, segment, segments, j, size, t, sourceColor }) {
  const spec = PALETTES[cfg.display.accent] || PALETTES.state
  if (spec.kind === 'state') {
    return hexToRgb(cfg.stateColors?.[state]) || sourceColor
  }
  if (spec.kind === 'source') return sourceColor
  if (spec.kind === 'hue') {
    const position = ringPosition(segment, segments, j, size)
    return hsv((position * 360 + t * cfg.display.rainbowSpeed * 60) % 360, 0.85, 1)
  }
  if (spec.kind === 'ramp') {
    return sampleRamp(PALETTE_STOPS[spec.id], ringPosition(segment, segments, j, size)) || sourceColor
  }
  return hexToRgb(cfg.stateColors?.[state]) || sourceColor
}

/// Where an LED sits on the whole ring, 0..1, so a palette wraps without a
/// colour seam at twelve o'clock.
function ringPosition(segment, segments, j, size) {
  const count = Math.max(1, segments)
  const within = size <= 1 ? 0.5 : (j + 0.5) / size
  return (((segment + within) / count) % 1 + 1) % 1
}

function hexToRgb(hex) {
  const parsed = parseHex(hex)
  return parsed || null
}

function hash01(n) {
  let x = Math.imul(n ^ 0x9e3779b9, 0x85ebca6b) >>> 0
  x ^= x >>> 13
  x = Math.imul(x, 0xc2b2ae35) >>> 0
  x ^= x >>> 16
  return (x >>> 0) / 4294967296
}

function hashString(text) {
  let h = 2166136261
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

function hsv(h, s, v) {
  const c = v * s
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  const m = v - c
  let rgb
  if (h < 60) rgb = [c, x, 0]
  else if (h < 120) rgb = [x, c, 0]
  else if (h < 180) rgb = [0, c, x]
  else if (h < 240) rgb = [0, x, c]
  else if (h < 300) rgb = [x, 0, c]
  else rgb = [c, 0, x]
  return rgb.map((value) => (value + m) * 255)
}

function effectOf(effect, baseColor, { j, size, t, accent, since = 0, seed = 0, speed = 1 }) {
  const color = accent || baseColor
  const span = size

  switch (effect) {
    case 'solid':
      return { color, level: 0.6 }

    case 'pulse': {
      const wave = 0.5 + 0.5 * Math.sin(t * 2 * Math.PI * 0.6)
      // Deep breath: bottom out near off instead of stopping at 30%.
      return { color, level: 0.04 + 0.9 * Math.pow(wave, 1.2) }
    }

    case 'blink':
      return { color, level: Math.floor(t * 2.2) % 2 === 0 ? 1 : 0.06 }

    case 'breathe': {
      const wave = 0.5 + 0.5 * Math.sin(t * 2 * Math.PI * 1.1)
      return { color, level: 0.03 + 0.92 * Math.pow(wave, 1.3) }
    }

    case 'flash': {
      if (since > 8) return { color, level: 0 }
      if (since < 1.5) {
        return { color, level: Math.floor(since * 6 * speed) % 2 === 0 ? 1 : 0.15 }
      }
      return { color, level: 0.4 }
    }

    case 'patches':
      // WLED's "Rain" adapted to a stateless renderer: random drops appear,
      // drift clockwise, and fade with a short soft trail.
      return { color, level: rainLevel(j, span, t, seed) }

    case 'comet':
    default: {
      const head = (t * 5) % span
      const tail = Math.max(2, Math.round(span / 4))

      // Signed distance so the head can glow slightly ahead of the peak.
      let delta = j - head
      if (delta > span / 2) delta -= span
      if (delta < -span / 2) delta += span

      // A soft sub-LED head keeps the peak moving between LEDs instead of
      // jumping from one to the next; the smoothstep tail has no hard kink.
      const sigma = 0.7
      const headGlow = Math.exp(-(delta * delta) / (2 * sigma * sigma))
      let tailGlow = 0
      if (delta < 0) {
        const x = 1 + delta / tail
        if (x > 0) tailGlow = x * x * (3 - 2 * x)
      }

      const shape = Math.max(headGlow, tailGlow)
      // Keep the unlit part of the arc almost black. A brighter ambient ring
      // makes the moving head read as a static glow instead of rotation.
      const base = span >= 8 ? 0.05 : 0.09
      const floor = base * 0.45
      return { color, level: floor + (1 - floor) * shape }
    }
  }
}

/// WLED "Rain" (1D) adapted to a stateless renderer. Each drop is born from a
/// time slot, drifts clockwise around its segment and fades. Multiple slots
/// overlap so the field never feels like a single repeating comet.
function rainLevel(j, span, t, seed) {
  const floor = span >= 8 ? 0.025 : 0.018
  let level = floor
  const dropCount = Math.max(1, Math.min(4, Math.round(span / 6)))
  const period = 1.2
  const life = 1.1
  const speed = span / 5
  const trailLength = Math.max(1.2, Math.min(3.2, span * 0.36))

  // A per-segment phase keeps split arcs from raining in lockstep.
  const segmentPhase = hash01(seed * 31 + 5) * period
  for (let k = 0; k < dropCount; k++) {
    // A per-stream phase offset keeps spawns from marching in lockstep.
    const shifted =
      t + segmentPhase + (k * period) / dropCount + hash01(k * 19 + 7) * 0.22
    const cycle = Math.floor(shifted / period)
    const age = shifted - cycle * period
    if (age >= life) continue

    const dropSeed = cycle * 97 + k * 53 + seed * 17 + 11
    const fadeIn = Math.min(1, age / 0.08)
    const fadeOut = Math.pow(Math.max(0, 1 - age / life), 1.25)
    const strength = (0.65 + 0.35 * hash01(dropSeed + 1)) * fadeIn * fadeOut
    if (strength <= 0.01) continue

    const pos = (hash01(dropSeed) * span + speed * age) % span
    // Signed distance on the ring: negative is behind the drifting head.
    let delta = j - pos
    if (delta > span / 2) delta -= span
    if (delta < -span / 2) delta += span

    const head = Math.exp(-(delta * delta) / (2 * 0.55 * 0.55))
    let trail = 0
    if (delta < 0) {
      const x = 1 + delta / trailLength
      if (x > 0) trail = 0.75 * x * x * (3 - 2 * x)
    }
    level = Math.max(level, (head + trail) * strength)
  }

  return Math.min(1, level)
}

function paint(out, index, color, level) {
  const o = index * 3
  out[o] = Math.round(color[0] * level)
  out[o + 1] = Math.round(color[1] * level)
  out[o + 2] = Math.round(color[2] * level)
}
