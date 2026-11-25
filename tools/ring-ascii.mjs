#!/usr/bin/env node
// Print the current ring as ASCII blocks plus the per-agent table.
//
//   node tools/ring-ascii.mjs [--watch] [--port 7801]

const args = process.argv.slice(2)
const portFlag = args.indexOf('--port')
const port = portFlag >= 0 ? Number(args[portFlag + 1]) : Number(process.env.AGENTRING_PORT || 7801)
const base = `http://127.0.0.1:${port}`

async function draw() {
  const [stateRes, frameRes] = await Promise.all([fetch(`${base}/state`), fetch(`${base}/frame`)])
  const state = await stateRes.json()
  const frame = new Uint8Array(await frameRes.arrayBuffer())

  const rows = []
  const perRow = 12
  for (let start = 0; start < frame.length / 3; start += perRow) {
    let line = ''
    for (let i = start; i < start + perRow; i++) {
      const r = frame[i * 3]
      const g = frame[i * 3 + 1]
      const b = frame[i * 3 + 2]
      line += `\x1b[38;2;${r};${g};${b}m██\x1b[0m`
    }
    rows.push(line)
  }

  const table = state.agents.map(
    (a) =>
      `  ${a.source.padEnd(5)} ${a.state.padEnd(8)} ${String(a.tool || '').padEnd(12)} ${a.label}`,
  )

  console.clear()
  console.log(`LEDs (${frame.length / 3}) — active: ${state.active}`)
  rows.forEach((r) => console.log('  ' + r))
  console.log('')
  console.log(table.length ? table.join('\n') : '  (no sessions)')
}

if (args.includes('--watch')) {
  setInterval(() => draw().catch((e) => console.log('daemon not reachable:', e.message)), 120)
} else {
  draw().catch((e) => {
    console.error('daemon not reachable:', e.message)
    process.exit(1)
  })
}
