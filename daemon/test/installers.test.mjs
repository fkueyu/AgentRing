import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const REPO_ROOT = path.resolve(import.meta.dirname, '..', '..')
const NODE = process.execPath
const SCRIPTS = path.join(REPO_ROOT, 'scripts')

function lab() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agentring-installer-'))
  return {
    home,
    path(rel) {
      return path.join(home, rel)
    },
    write(rel, value) {
      const file = path.join(home, rel)
      fs.mkdirSync(path.dirname(file), { recursive: true })
      fs.writeFileSync(file, typeof value === 'string' ? value : JSON.stringify(value, null, 2))
    },
    read(rel) {
      return JSON.parse(fs.readFileSync(path.join(home, rel), 'utf8'))
    },
    run(script, args = []) {
      return execFileSync(NODE, [path.join(SCRIPTS, script), ...args], {
        env: { ...process.env, HOME: home },
        encoding: 'utf8',
      })
    },
    cleanup() {
      fs.rmSync(home, { recursive: true, force: true })
    },
  }
}

function withLab(fn) {
  return async () => {
    const l = lab()
    try {
      await fn(l)
    } finally {
      l.cleanup()
    }
  }
}

const AGENTRING_HOOK = '.agentring/hook.sh'
const CODEX_EVENTS = [
  'SessionStart',
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Stop',
  'SessionEnd',
]
const CLAUDE_EVENTS = [...CODEX_EVENTS, 'StopFailure']

function commands(doc) {
  return Object.values(doc.hooks || {})
    .flat()
    .flatMap((group) => group.hooks || [])
    .map((hook) => String(hook.command || ''))
}

function ours(doc) {
  return commands(doc).filter((command) => command.includes(AGENTRING_HOOK))
}

test(
  'the Codex installer merges, stays idempotent and uninstalls cleanly',
  withLab((l) => {
    l.write('.codex/hooks.json', {
      hooks: {
        Stop: [
          {
            matcher: '',
            hooks: [{ type: 'command', command: '/usr/bin/other-tool' }],
          },
        ],
      },
    })

    l.run('install-codex-hooks.mjs')
    const installed = l.read('.codex/hooks.json')
    assert.deepEqual(Object.keys(installed.hooks).sort(), [...CODEX_EVENTS].sort())
    assert.equal(installed.hooks.Stop.length, 2, 'foreign Stop hook is kept')
    assert.equal(ours(installed).length, CODEX_EVENTS.length)
    assert.ok(ours(installed).every((command) => command.includes('--source codex')))
    assert.equal(fs.existsSync(l.path('.agentring/hook.sh')), true)
    assert.equal(fs.statSync(l.path('.agentring/hook.sh')).mode & 0o111, 0o111)

    const first = fs.readFileSync(l.path('.codex/hooks.json'), 'utf8')
    l.run('install-codex-hooks.mjs')
    assert.equal(fs.readFileSync(l.path('.codex/hooks.json'), 'utf8'), first, 'second run is a no-op')

    l.run('install-codex-hooks.mjs', ['--uninstall'])
    const removed = l.read('.codex/hooks.json')
    assert.equal(ours(removed).length, 0)
    assert.deepEqual(
      commands(removed).filter((command) => command.includes('other-tool')),
      ['/usr/bin/other-tool'],
    )
  }),
)

test(
  'the Claude installer keeps CodeIsland hooks and top-level settings',
  withLab((l) => {
    l.write('.claude/settings.json', {
      language: 'Chinese',
      hooks: {
        Stop: [
          {
            matcher: '',
            hooks: [{ type: 'command', command: '~/.codeisland/codeisland-hook.sh' }],
          },
        ],
        PreToolUse: [
          {
            matcher: '',
            hooks: [{ type: 'command', command: '~/.codeisland/codeisland-hook.sh' }],
          },
        ],
      },
    })

    l.run('install-claude-hooks.mjs')
    const installed = l.read('.claude/settings.json')
    assert.equal(installed.language, 'Chinese')
    assert.deepEqual(Object.keys(installed.hooks).sort(), [...CLAUDE_EVENTS].sort())
    assert.equal(installed.hooks.Stop.length, 2, 'CodeIsland Stop hook is kept')
    assert.equal(installed.hooks.PreToolUse.length, 2, 'CodeIsland PreToolUse hook is kept')
    assert.equal(ours(installed).length, CLAUDE_EVENTS.length)
    assert.ok(installed.hooks.StopFailure, 'StopFailure feeds the error state')
    assert.ok(ours(installed).every((command) => command.includes('--source claude')))
    assert.ok(
      commands(installed).some((command) => command.includes('codeisland-hook.sh')),
      'the other integration survives',
    )

    const first = fs.readFileSync(l.path('.claude/settings.json'), 'utf8')
    l.run('install-claude-hooks.mjs')
    assert.equal(fs.readFileSync(l.path('.claude/settings.json'), 'utf8'), first)

    l.run('install-claude-hooks.mjs', ['--uninstall'])
    const removed = l.read('.claude/settings.json')
    assert.equal(ours(removed).length, 0)
    assert.equal(removed.language, 'Chinese')
    assert.equal(removed.hooks.Stop.length, 1)
    assert.equal(removed.hooks.PreToolUse.length, 1)
  }),
)

test(
  'the Claude installer creates settings.json when it is missing',
  withLab((l) => {
    l.run('install-claude-hooks.mjs')
    const installed = l.read('.claude/settings.json')
    assert.deepEqual(Object.keys(installed.hooks).sort(), [...CLAUDE_EVENTS].sort())
    assert.equal(ours(installed).length, CLAUDE_EVENTS.length)
    assert.equal(
      fs.readdirSync(l.path('.claude')).some((name) => name.includes('.agentring-')),
      false,
      'no backup is written when there was no file',
    )
  }),
)
