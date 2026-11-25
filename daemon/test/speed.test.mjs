import test from 'node:test'
import assert from 'node:assert/strict'

import { sanitize } from '../src/config.mjs'
import { renderFrame } from '../src/frame.mjs'

function frame({ state = 'tool', ms = 1000, display = {}, motion = {} } = {}) {
  const config = sanitize({ display: { brightness: 0.8, ...display }, motion })
  return renderFrame(
    { ts: ms, agents: [{ source: 'dsh', state, sinceMs: ms, updatedMs: 0 }] },
    { config, now: ms },
  )
}

function brightestIndex(bytes) {
  let index = 0
  let value = -1
  for (let i = 0; i < bytes.length / 3; i++) {
    const level = Math.max(bytes[i * 3], bytes[i * 3 + 1], bytes[i * 3 + 2])
    if (level > value) {
      value = level
      index = i
    }
  }
  return index
}

test('each state has its own effect speed', () => {
  const slow = frame({ motion: { speeds: { tool: 1 } } })
  const fast = frame({ motion: { speeds: { tool: 2 } } })
  assert.notEqual(brightestIndex(slow), brightestIndex(fast))

  const thinkingWithFastTool = frame({
    state: 'thinking',
    motion: { speeds: { thinking: 1, tool: 2 } },
  })
  const thinkingControl = frame({ state: 'thinking', motion: { speeds: { thinking: 1, tool: 1 } } })
  assert.deepEqual(Array.from(thinkingWithFastTool), Array.from(thinkingControl))
})

test('standby speed is independent of the per-state motion speeds', () => {
  const make = (motion, standbySpeed) => {
    const config = sanitize({
      display: { standby: 'orbit', standbySpeed, brightness: 0.8 },
      motion,
    })
    return Array.from(renderFrame({ ts: 1000, agents: [] }, { config, now: 1000 }))
  }

  const control = make({ speeds: { thinking: 1, tool: 1, editing: 1, waiting: 1, done: 1, error: 1 } }, 1.5)
  const fastMotion = make({ speeds: { thinking: 3, tool: 3, editing: 3, waiting: 3, done: 3, error: 3 } }, 1.5)
  assert.deepEqual(control, fastMotion)

  assert.notDeepEqual(make({}, 0.5), make({}, 2))
})

test('per-state speeds clamp and round to tenths', () => {
  const cfg = sanitize({ motion: { speeds: { thinking: 0.05, tool: 9, editing: 1.26 } } })
  assert.equal(cfg.motion.speeds.thinking, 0.2)
  assert.equal(cfg.motion.speeds.tool, 3)
  assert.equal(cfg.motion.speeds.editing, 1.3)
  assert.equal(cfg.motion.speeds.waiting, 1)
})
