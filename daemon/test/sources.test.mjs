import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { SOURCE_REGISTRY, inspectSources, parseDshProcess } from '../src/sources.mjs'

const REPO_ROOT = path.resolve(import.meta.dirname, '..', '..')

/**
 * A hermetic home: app bundles, CLIs and profile manifests live under a temp
 * directory, so detection never sees the machine running the tests.
 */
function lab() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agentring-sources-'))
  const appDirs = [path.join(home, 'Applications')]
  const cliDirs = [path.join(home, 'bin')]
  fs.mkdirSync(appDirs[0], { recursive: true })
  fs.mkdirSync(cliDirs[0], { recursive: true })

  const api = {
    home,
    appDirs,
    cliDirs,
    write(rel, content) {
      const file = path.join(home, rel)
      fs.mkdirSync(path.dirname(file), { recursive: true })
      fs.writeFileSync(file, typeof content === 'string' ? content : JSON.stringify(content, null, 2))
    },
    mkdir(rel) {
      fs.mkdirSync(path.join(home, rel), { recursive: true })
    },
    app(name, version = '1.0.0') {
      api.write(
        `Applications/${name}/Contents/Info.plist`,
        `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>${version}</string></dict></plist>`,
      )
    },
    async inspect(runtime = {}, extra = {}) {
      return inspectSources({
        home,
        appDirs,
        cliDirs,
        repoRoot: REPO_ROOT,
        now: 1,
        runtime: {
          dsh: { running: false, profile: null },
          codex: { running: false },
          ...runtime,
        },
        ...extra,
      })
    },
    entry(report, id) {
      return report.entries.find((entry) => entry.id === id)
    },
  }
  return api
}

function withLab(fn) {
  return async () => {
    const l = lab()
    try {
      await fn(l)
    } finally {
      fs.rmSync(l.home, { recursive: true, force: true })
    }
  }
}

function dshProfile(l, name, { listed = true, linked = true } = {}) {
  const bundle = '@local/agentring-dsh'
  l.write(`.dsh/profiles/${name}/package.json`, {
    name: `dsh-profile-${name}`,
    dependencies: { [bundle]: 'link:/tmp/agentring-dsh' },
    dsh: { profile: { bundles: listed ? [bundle] : ['@deepseek-ai/dsh-base'] } },
  })
  if (linked) l.mkdir(`.dsh/profiles/${name}/node_modules/@local/agentring-dsh`)
}

test('the registry is ordered and every entry has a probe', () => {
  assert.deepEqual(
    SOURCE_REGISTRY.map((entry) => entry.id),
    ['dsh', 'codex', 'claude'],
  )
  for (const entry of SOURCE_REGISTRY) assert.equal(typeof entry.probe, 'function')
})

test(
  'a DSH profile bundle is reported as installed and wired',
  withLab(async (l) => {
    l.app('DeepSeek Harness.app', '0.2.2-rc.5')
    dshProfile(l, 'desktop')
    const report = await l.inspect({ dsh: { running: true, profile: 'desktop' } })
    const dsh = l.entry(report, 'dsh')
    assert.equal(dsh.detected, true)
    assert.equal(dsh.install.version, '0.2.2-rc.5')
    assert.equal(dsh.install.running, true)
    assert.equal(dsh.install.profile, 'desktop')
    assert.equal(dsh.bridge.state, 'installed')
    assert.match(dsh.bridge.detail, /desktop/)
    assert.match(dsh.bridge.detail, /@local\/agentring-dsh/)
  }),
)

test(
  'a DSH install without the plugin reports the missing bridge and the command',
  withLab(async (l) => {
    l.write('.dsh/profiles/desktop/package.json', {
      dependencies: { dsh: '^1.0.1' },
      dsh: { profile: { bundles: ['@deepseek-ai/dsh-base'] } },
    })
    const report = await l.inspect({ dsh: { running: true, profile: 'desktop' } })
    const dsh = l.entry(report, 'dsh')
    assert.equal(dsh.bridge.state, 'missing')
    assert.match(dsh.bridge.command, /dsh plugin --profile desktop add /)
    assert.match(dsh.bridge.command, /packages\/dsh-plugin/)
  }),
)

test(
  'a plugin that is installed but not in the bundle list is not enabled',
  withLab(async (l) => {
    dshProfile(l, 'desktop', { listed: false })
    const report = await l.inspect({ dsh: { running: true, profile: 'desktop' } })
    assert.equal(l.entry(report, 'dsh').bridge.state, 'disabled')
  }),
)

test(
  'the running profile is compared with the profile that has the plugin',
  withLab(async (l) => {
    dshProfile(l, 'web')
    const report = await l.inspect({ dsh: { running: true, profile: 'desktop' } })
    assert.equal(l.entry(report, 'dsh').bridge.state, 'mismatch')
    assert.match(l.entry(report, 'dsh').bridge.detail, /web/)

    const runningWeb = await l.inspect({ dsh: { running: true, profile: 'web' } })
    assert.equal(l.entry(runningWeb, 'dsh').bridge.state, 'installed')
  }),
)

test(
  'an agent that is not installed reports detected:false and no bridge',
  withLab(async (l) => {
    const report = await l.inspect()
    for (const id of ['dsh', 'codex', 'claude']) {
      const entry = l.entry(report, id)
      assert.equal(entry.detected, false, id)
      assert.equal(entry.install, null, id)
      assert.equal(entry.bridge, null, id)
    }
  }),
)

test(
  'Codex needs both hooks.json entries and the hook shim',
  withLab(async (l) => {
    l.app('ChatGPT.app', '26.1117')
    l.write('.codex/hooks.json', {
      hooks: {
        Stop: [{ hooks: [{ type: 'command', command: '~/.agentring/hook.sh Stop' }] }],
      },
    })
    const withoutShim = await l.inspect({ codex: { running: true } })
    assert.equal(l.entry(withoutShim, 'codex').detected, true)
    assert.equal(l.entry(withoutShim, 'codex').bridge.state, 'missing')
    assert.match(l.entry(withoutShim, 'codex').bridge.detail, /hook\.sh/)
    assert.match(l.entry(withoutShim, 'codex').bridge.command, /install-codex-hooks\.mjs/)
    assert.equal(l.entry(withoutShim, 'codex').install.running, true)

    l.write('.agentring/hook.sh', '#!/bin/sh\n')
    const wired = await l.inspect()
    assert.equal(l.entry(wired, 'codex').bridge.state, 'installed')
    assert.match(l.entry(wired, 'codex').bridge.detail, /hooks\.json/)
  }),
)

test(
  'Claude is detected and offers the one-click installer until wired',
  withLab(async (l) => {
    l.mkdir('.claude')
    l.write('.claude/settings.json', { permissions: { allow: ['Bash'] } })
    const missing = await l.inspect()
    assert.equal(l.entry(missing, 'claude').detected, true)
    assert.equal(l.entry(missing, 'claude').bridge.state, 'missing')
    assert.equal(l.entry(missing, 'claude').bridge.installable, true)
    assert.match(l.entry(missing, 'claude').bridge.command, /install-claude-hooks\.mjs/)

    l.write('.claude/settings.json', {
      hooks: { Stop: [{ hooks: [{ type: 'command', command: '~/.agentring/hook.sh Stop' }] }] },
    })
    const wired = await l.inspect()
    assert.equal(l.entry(wired, 'claude').bridge.state, 'installed')
    assert.equal(l.entry(wired, 'claude').bridge.installable, undefined)
  }),
)

test('a CLI-only instalment is still detected', withLab(async (l) => {
  l.write('bin/claude', '#!/bin/sh\n')
  const entry = l.entry(await l.inspect(), 'claude')
  assert.equal(entry.detected, true)
  assert.match(entry.install.path, /bin\/claude$/)
}))

test('the running DSH profile is parsed from the host process args', () => {
  const ps = [
    '/Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness',
    '/Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness --expose-internals /Applications/DeepSeek Harness.app/Contents/Resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js /Users/example/.dsh/profiles/desktop /Applications/DeepSeek Harness.app/Contents/Resources/runtime',
    'node unrelated',
  ].join('\n')
  assert.deepEqual(parseDshProcess(ps), { running: true, profile: 'desktop' })
  assert.deepEqual(parseDshProcess(''), { running: false, profile: null })
})
