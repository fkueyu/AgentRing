#!/usr/bin/env node
// Keep the AgentRing menu-bar app running across logins and crashes.
//
//   node scripts/install-app.mjs            # install + start
//   node scripts/install-app.mjs --uninstall

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const LABEL = 'com.agentring.app'
const APP = process.env.AGENTRING_APP || '/Applications/AgentRing.app'
const PLIST = path.join(os.homedir(), 'Library', 'LaunchAgents', `${LABEL}.plist`)
const uid = process.getuid()
const domain = `gui/${uid}`

const uninstall = process.argv.includes('--uninstall')

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
}

/** bootout + bootstrap can race; launchd returns EIO while the old job tears down. */
function bootstrap() {
  for (let attempt = 0; ; attempt++) {
    try {
      return run('launchctl', ['bootstrap', domain, PLIST])
    } catch (err) {
      if (attempt >= 4) throw err
      sleep(500)
    }
  }
}

function run(cmd, args, { ignore = false } = {}) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (err) {
    if (!ignore) throw err
    return ''
  }
}

if (uninstall) {
  run('launchctl', ['bootout', `${domain}/${LABEL}`], { ignore: true })
  fs.rmSync(PLIST, { force: true })
  console.log(`[agentring] removed ${LABEL}`)
  process.exit(0)
}

if (!fs.existsSync(path.join(APP, 'Contents', 'MacOS', 'AgentRing'))) {
  console.error(`[agentring] app not found at ${APP} — build and install it first`)
  process.exit(1)
}

fs.mkdirSync(path.dirname(PLIST), { recursive: true })

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${path.join(APP, 'Contents', 'MacOS', 'AgentRing')}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
`

fs.writeFileSync(PLIST, plist)
run('launchctl', ['bootout', `${domain}/${LABEL}`], { ignore: true })
bootstrap()
run('launchctl', ['enable', `${domain}/${LABEL}`], { ignore: true })
console.log(`[agentring] installed ${PLIST}`)
