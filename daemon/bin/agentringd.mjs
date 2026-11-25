#!/usr/bin/env node
// agentringd — local bridge daemon.
//
//   node daemon/bin/agentringd.mjs [--port 7801] [--quiet]

import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { DEFAULT_PORT, DEFAULT_STREAM_PORT } from '../src/protocol.mjs'
import { createServer } from '../src/server.mjs'

// launchd appends to daemon.log forever; cap it on startup. The descriptor is
// opened in append mode, so truncating here keeps the next write at offset 0.
const LOG_PATH = path.join(os.homedir(), '.agentring', 'daemon.log')
try {
  if (fs.statSync(LOG_PATH).size > 10 * 1024 * 1024) fs.truncateSync(LOG_PATH, 0)
} catch {
  // Missing file/permissions are fine: logging is best-effort.
}

const args = process.argv.slice(2)
const portFlag = args.indexOf('--port')
const port = portFlag >= 0 ? Number(args[portFlag + 1]) : Number(process.env.AGENTRING_PORT || DEFAULT_PORT)
const streamFlag = args.indexOf('--stream-port')
const streamPort = streamFlag >= 0
  ? Number(args[streamFlag + 1])
  : Number(process.env.AGENTRING_STREAM_PORT || DEFAULT_STREAM_PORT)
const quiet = args.includes('--quiet') || process.env.AGENTRING_QUIET === '1'

const stamp = () => new Date().toTimeString().slice(0, 8)
const log = quiet ? () => {} : (m) => console.log(`[agentring ${stamp()}] ${m}`)
const { server, stream } = createServer({ port, streamPort, log })

if (stream) {
  stream.server.on('error', (err) => {
    console.error(`[agentring] stream port ${streamPort}: ${err.message}`)
    process.exit(1)
  })
}

// Advertise `_agentring._tcp` so the ESP32 can find this Mac without a
// hard-coded IP. dns-sd ships with macOS; without it the firmware falls back to
// a static address from its config.h.
let mdns = null
function startMdns() {
  if (process.env.AGENTRING_NO_MDNS === '1') return
  mdns = spawn('/usr/bin/dns-sd', ['-R', 'AgentRing', '_agentring._tcp', '.', String(port)], {
    stdio: 'ignore',
  })
  mdns.on('error', () => {
    log('mDNS advertisement unavailable (static IP in firmware config still works)')
    mdns = null
  })
  mdns.on('exit', (code) => {
    if (code && code !== 0) log('mDNS advertiser exited')
    mdns = null
  })
}

function stopMdns() {
  if (mdns) {
    mdns.kill()
    mdns = null
  }
}

server.listen(port, '0.0.0.0', () => {
  log(`listening on http://0.0.0.0:${port}  (preview: http://127.0.0.1:${port}/)`)
  startMdns()
  if (stream) log(`frame stream on tcp://0.0.0.0:${streamPort}`)
})

server.on('error', (err) => {
  console.error(`[agentring] ${err.message}`)
  process.exit(1)
})

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    stopMdns()
    server.close(() => process.exit(0))
  })
}

process.on('exit', stopMdns)
