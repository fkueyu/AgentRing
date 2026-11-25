#!/usr/bin/env node
// Merge AgentRing into ~/.codex/hooks.json without touching other hooks.
//
//   node scripts/install-codex-hooks.mjs            # add entries (idempotent)
//   node scripts/install-codex-hooks.mjs --uninstall
//   node scripts/install-codex-hooks.mjs --dry-run
//
// A timestamped backup is written next to hooks.json before every change.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const SOURCE_SHIM = path.join(HERE, '..', 'daemon', 'bin', 'agentring-hook.sh')
// Agents run hooks through a shell, so the installed path must not contain
// spaces (the repository may live under one). Install a copy to a stable,
// space-free location and point every hook at that.
const SHIM_DIR = path.join(os.homedir(), '.agentring')
const SHIM = path.join(SHIM_DIR, 'hook.sh')
const MARKER = '.agentring/hook.sh'

const EVENTS = [
  'SessionStart',
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Stop',
  'SessionEnd',
]

const args = process.argv.slice(2)
const uninstall = args.includes('--uninstall')
const dryRun = args.includes('--dry-run')
const hooksPath = process.env.CODEX_HOOKS || path.join(os.homedir(), '.codex', 'hooks.json')

function log(m) {
  console.log(`[agentring:codex] ${m}`)
}

const raw = fs.existsSync(hooksPath) ? fs.readFileSync(hooksPath, 'utf8') : '{"hooks":{}}'
const doc = JSON.parse(raw)
doc.hooks ||= {}

const before = JSON.stringify(doc)

if (uninstall) {
  for (const event of Object.keys(doc.hooks)) {
    const groups = doc.hooks[event]
    if (!Array.isArray(groups)) continue
    doc.hooks[event] = groups
      .map((g) => ({
        ...g,
        hooks: (g.hooks || []).filter((h) => {
          const cmd = String(h.command || '')
          return !(cmd.includes('agentring-hook.sh') || cmd.includes('.agentring/hook.sh'))
        }),
      }))
      .filter((g) => (g.hooks || []).length > 0)
    if (doc.hooks[event].length === 0) delete doc.hooks[event]
  }
} else {
  fs.mkdirSync(SHIM_DIR, { recursive: true })
  fs.copyFileSync(SOURCE_SHIM, SHIM)
  fs.chmodSync(SHIM, 0o755)
  for (const event of EVENTS) {
    const groups = doc.hooks[event] || (doc.hooks[event] = [])
    const exists = groups.some((g) => (g.hooks || []).some((h) => String(h.command || '').includes('.agentring/hook.sh')))
    if (exists) continue
    groups.push({
      matcher: '',
      hooks: [{ type: 'command', command: `'${SHIM}' --source codex`, timeout: 5 }],
    })
  }
  // Keep the file's key order stable and readable.
  doc.hooks = Object.fromEntries(Object.entries(doc.hooks).sort(([a], [b]) => a.localeCompare(b)))
}

const after = JSON.stringify(doc)
if (before === after) {
  log('already up to date, nothing to write')
  process.exit(0)
}

if (dryRun) {
  log('dry run — would write:')
  console.log(JSON.stringify(doc, null, 2))
  process.exit(0)
}

fs.mkdirSync(path.dirname(hooksPath), { recursive: true })
if (fs.existsSync(hooksPath)) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  const backup = `${hooksPath}.agentring-${stamp}`
  fs.copyFileSync(hooksPath, backup)
  log(`backup: ${backup}`)
}
fs.writeFileSync(hooksPath, JSON.stringify(doc, null, 2) + '\n')
log(`${uninstall ? 'removed from' : 'installed into'} ${hooksPath}`)
if (!uninstall) log('new hooks may need a one-time trust confirmation in the Codex TUI')
