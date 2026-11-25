// Shared constants for the AgentRing bridge.

export const DEFAULT_PORT = 7801
export const DEFAULT_STREAM_PORT = 7802
export const LED_COUNT = 24

/** Display priority: the higher the number, the more the ring wants to show it. */
export const STATE_PRIORITY = {
  waiting: 7,
  error: 6,
  editing: 5,
  tool: 4,
  thinking: 3,
  done: 2,
  idle: 1,
}

/** Fully saturated colours; scaling happens in the frame renderer. */
export const SOURCE_COLORS = {
  codex: [16, 163, 127],
  dsh: [77, 107, 254],
  claude: [217, 119, 87],
  trae: [255, 77, 77],
  workbuddy: [255, 159, 10],
  default: [140, 140, 160],
}

export const AMBER = [255, 170, 40]
export const RED = [255, 48, 48]
export const GREEN = [40, 220, 110]

export function colorFor(source, colors = {}) {
  const custom = colors && colors[source]
  if (typeof custom === 'string' && /^#[0-9a-f]{6}$/i.test(custom)) {
    const n = parseInt(custom.slice(1), 16)
    return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
  }
  return SOURCE_COLORS[source] || SOURCE_COLORS.default
}
