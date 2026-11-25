#!/usr/bin/env node
// Merge AgentRing into ~/.claude/settings.json without touching other hooks.
//
//   node scripts/install-claude-hooks.mjs            # add entries (idempotent)
//   node scripts/install-claude-hooks.mjs --uninstall
//   node scripts/install-claude-hooks.mjs --dry-run
//
// A timestamped backup is written next to settings.json before every change.
// Claude Code hooks use the same stdin payload shape as Codex hooks, so the
// shared shim only needs a different source name.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const SOURCE_SHIM = path.join(HERE, '..', 'daemon', 'bin', 'agentring-hook.sh')
// Hook commands run through a shell, so the installed path must not contain
// spaces (the repository may live under one). Match the Codex installer and
// point every hook at the stable copy.
const SHIM_DIR = path.join(os.homedir(), '.agentring')
const SHIM = path.join(SHIM_DIR, 'hook.sh')
const MARKER = '.agentring/hook.sh'

// Claude Code dispatches PermissionRequest for approvals and StopFailure for a
// failed turn, so the ring can show the error state as well.
const EVENTS = [
  'SessionStart',
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Stop',
  'StopFailure',
  'SessionEnd',
]

const args = process.argv.slice(2)
const uninstall = args.includes('--uninstall')
const dryRun = args.includes('--dry-run')
const settingsPath =
  process.env.CLAUDE_SETTINGS || path.join(os.homedir(), '.claude', 'settings.json')

function log(m) {
  console.log(`[agentring:claude] ${m}`)
}

function isOurs(hook) {
  const command = String(hook?.command || '')
  return command.includes(MARKER) || command.includes('agentring-hook.sh')
}

let doc = {}
if (fs.existsSync(settingsPath)) {
  doc = JSON.parse(fs.readFileSync(settingsPath, 'utf8'))
}
doc.hooks ||= {}

const before = JSON.stringify(doc)

if (uninstall) {
  for (const event of Object.keys(doc.hooks)) {
    const groups = doc.hooks[event]
    if (!Array.isArray(groups)) continue
    doc.hooks[event] = groups
      .map((group) => ({
        ...group,
        hooks: (group.hooks || []).filter((hook) => !isOurs(hook)),
      }))
      .filter((group) => (group.hooks || []).length > 0)
    if (doc.hooks[event].length === 0) delete doc.hooks[event]
  }
} else {
  fs.mkdirSync(SHIM_DIR, { recursive: true })
  fs.copyFileSync(SOURCE_SHIM, SHIM)
  fs.chmodSync(SHIM, 0o755)

  for (const event of EVENTS) {
    const groups = doc.hooks[event] || (doc.hooks[event] = [])
    const exists = groups.some((group) =>
      (group.hooks || []).some(isOurs),
    )
    if (exists) continue
    groups.push({
      matcher: '',
      hooks: [{ type: 'command', command: `'${SHIM}' --source claude`, timeout: 5 }],
    })
  }
  // Keep the file's key order stable and readable, like the Codex installer.
  doc.hooks = Object.fromEntries(
    Object.entries(doc.hooks).sort(([a], [b]) => a.localeCompare(b)),
  )
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

fs.mkdirSync(path.dirname(settingsPath), { recursive: true })
if (fs.existsSync(settingsPath)) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  const backup = `${settingsPath}.agentring-${stamp}`
  fs.copyFileSync(settingsPath, backup)
  log(`backup: ${backup}`)
}

fs.writeFileSync(settingsPath, JSON.stringify(doc, null, 2) + '\n')
log(`${uninstall ? 'removed from' : 'installed into'} ${settingsPath}`)
if (!uninstall) {
  log('Claude Code may ask you to trust the new hooks once; other hooks are untouched')
}
