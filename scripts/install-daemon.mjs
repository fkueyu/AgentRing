#!/usr/bin/env node
// Keep the AgentRing daemon running across logins with a user LaunchAgent.
//
//   node scripts/install-daemon.mjs            # install + start
//   node scripts/install-daemon.mjs --uninstall
//
// Logs go to ~/.agentring/daemon.log.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(HERE, '..')
const LABEL = 'com.agentring.daemon'
const PLIST = path.join(os.homedir(), 'Library', 'LaunchAgents', `${LABEL}.plist`)
const LOG = path.join(os.homedir(), '.agentring', 'daemon.log')

// Pinning launchd to the versioned Cellar path breaks on `brew upgrade node`,
// which deletes the old prefix. Prefer Homebrew's stable bin symlink when this
// process itself is a Homebrew Cellar build.
const NODE = process.env.AGENTRING_NODE || stableNode()

function stableNode() {
  const match = /^(\/opt\/homebrew|\/usr\/local)\/Cellar\/node\/[^/]+\/bin\/node$/.exec(process.execPath)
  const wrapper = match && path.join(match[1], 'bin', 'node')
  return wrapper && fs.existsSync(wrapper) ? wrapper : process.execPath
}

const uninstall = process.argv.includes('--uninstall')
const uid = process.getuid()
const domain = `gui/${uid}`

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

fs.mkdirSync(path.dirname(PLIST), { recursive: true })
fs.mkdirSync(path.dirname(LOG), { recursive: true })

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE}</string>
    <string>${path.join(ROOT, 'daemon', 'bin', 'agentringd.mjs')}</string>
  </array>
  <key>WorkingDirectory</key><string>${ROOT}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG}</string>
  <key>StandardErrorPath</key><string>${LOG}</string>
</dict>
</plist>
`

fs.writeFileSync(PLIST, plist)
run('launchctl', ['bootout', `${domain}/${LABEL}`], { ignore: true })
bootstrap()
run('launchctl', ['enable', `${domain}/${LABEL}`], { ignore: true })
console.log(`[agentring] installed ${PLIST}`)
console.log(`[agentring] logs: ${LOG}`)
