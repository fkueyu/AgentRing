// Agent source detection.
//
// The ring can only show an agent that reports to the daemon, so the Sources
// page answers two separate questions per tool: is the tool installed, and is
// AgentRing's bridge installed (a DSH profile bundle, a Codex hooks file, …)?
//
// Detection is advisory and filesystem-first: it reads the manifests the tool
// already owns and never invokes the tool's CLI, installs anything or edits a
// profile. That keeps a status refresh cheap and independent of tool versions.
// Adding a new agent later means adding one probe to SOURCE_REGISTRY.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFile } from 'node:child_process'

const APP_DIRS = ['/Applications']
const CLI_DIRS = ['/opt/homebrew/bin', '/usr/local/bin']

/**
 * AgentRing-owned installers, keyed by source. These are the only commands the
 * app may run on the user's behalf; the copy-only `command` in a probe may be
 * a package-manager operation and is never executed by the daemon.
 */
export const BRIDGE_INSTALLERS = Object.freeze({
  codex: 'scripts/install-codex-hooks.mjs',
  claude: 'scripts/install-claude-hooks.mjs',
})

const installing = new Set()

export const SOURCE_REGISTRY = Object.freeze([
  { id: 'dsh', probe: inspectDsh },
  { id: 'codex', probe: inspectCodex },
  { id: 'claude', probe: inspectClaude },
])

/**
 * Inspect every registered source. `runtime`, `appDirs` and `cliDirs` are
 * injectable so tests never read the machine they run on.
 */
export async function inspectSources({
  home = os.homedir(),
  runtime,
  repoRoot = null,
  appDirs = APP_DIRS,
  cliDirs = CLI_DIRS,
  now = Date.now(),
} = {}) {
  const resolved = runtime ?? (await probeRuntime())
  const entries = SOURCE_REGISTRY.map(({ id, probe }) => {
    try {
      return { id, ...probe({ home, runtime: resolved, repoRoot, appDirs, cliDirs }) }
    } catch (error) {
      return { id, detected: false, install: null, bridge: null, error: String(error?.message || error) }
    }
  })
  return { checkedAt: now, entries }
}

/**
 * Processes that decide "running" and which DSH profile is live. Async on
 * purpose: `ps` takes tens of milliseconds, and the daemon also renders the
 * 30 fps frame stream on this event loop.
 */
export async function probeRuntime() {
  const [ps, codex] = await Promise.all([
    run('/bin/ps', ['-axo', 'pid=,command=']),
    pgrep('ChatGPT'),
  ])
  return { dsh: parseDshProcess(ps), codex: { running: codex } }
}

function run(file, args) {
  return new Promise((resolve) => {
    execFile(
      file,
      args,
      { encoding: 'utf8', timeout: 1500, maxBuffer: 4 * 1024 * 1024 },
      (error, stdout) => resolve(error ? '' : stdout),
    )
  })
}

function pgrep(name) {
  return new Promise((resolve) => {
    execFile('/usr/bin/pgrep', ['-x', name], { timeout: 1500 }, (error) => resolve(!error))
  })
}

/** Absolute installer script for a source, when it exists in this checkout. */
export function installerFor(id, repoRoot) {
  const relative = BRIDGE_INSTALLERS[id]
  if (!relative || !repoRoot) return null
  const script = path.join(repoRoot, relative)
  return exists(script) ? script : null
}

/**
 * Run AgentRing's bridge installer for one source. Only scripts from
 * BRIDGE_INSTALLERS are allowed; a probe's display command is never executed.
 * Returns `{ ok, output }` or `{ ok: false, status, error }`.
 */
export async function installBridge({ id, repoRoot }) {
  const script = installerFor(id, repoRoot)
  if (!script) return { ok: false, status: 400, error: `no installer for "${id}"` }
  if (installing.has(id)) return { ok: false, status: 409, error: 'installer is already running' }

  installing.add(id)
  try {
    const result = await runNode(script, repoRoot)
    if (result.code !== 0) {
      const message = (result.stderr || result.stdout || `installer exited ${result.code}`).trim()
      return { ok: false, status: 500, error: message.slice(-800) }
    }
    return { ok: true, output: result.stdout.trim() }
  } finally {
    installing.delete(id)
  }
}

function runNode(script, cwd) {
  return new Promise((resolve) => {
    execFile(
      process.execPath,
      [script],
      { cwd, timeout: 30_000, maxBuffer: 1024 * 1024, env: process.env },
      (error, stdout, stderr) =>
        resolve({
          code: error ? Number(error.code) || 1 : 0,
          stdout: stdout || '',
          stderr: stderr || error?.message || '',
        }),
    )
  })
}

/**
 * The DSH desktop host passes its profile directory (`~/.dsh/profiles/<name>`)
 * on the command line, so the running profile is visible without asking DSH.
 */
export function parseDshProcess(ps) {
  let running = false
  let profile = null
  for (const line of String(ps || '').split('\n')) {
    if (!line.includes('DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness')) continue
    running = true
    const found = /\/\.dsh\/profiles\/([^/\s]+)/.exec(line)
    if (found) {
      profile = found[1]
      break
    }
  }
  return { running, profile }
}

// MARK: - DSH

function inspectDsh({ home, runtime, repoRoot, appDirs, cliDirs }) {
  const bundle = appBundle(home, 'DeepSeek Harness.app', appDirs)
  const dshHome = path.join(home, '.dsh')
  if (!bundle && !exists(dshHome)) {
    return { detected: false, install: null, bridge: null }
  }

  const active = runtime?.dsh ?? { running: false, profile: null }
  const install = {
    path: bundle || dshHome,
    version: appVersion(bundle),
    running: Boolean(active.running),
    profile: active.profile ?? null,
  }

  const profiles = dshProfiles(home)
  const enabled = profiles.filter((entry) => entry.enabled)
  const linked = profiles.filter((entry) => entry.linked)

  if (enabled.length > 0) {
    const names = enabled.map((entry) => entry.profile).join(' / ')
    if (active.profile && !enabled.some((entry) => entry.profile === active.profile)) {
      return {
        detected: true,
        install,
        bridge: {
          state: 'mismatch',
          kind: 'plugin',
          detail: `插件装在 ${names}，当前运行 ${active.profile} 配置`,
          command: null,
        },
      }
    }
    return {
      detected: true,
      install,
      bridge: {
        state: 'installed',
        kind: 'plugin',
        detail: `${names} 配置 · ${enabled[0].bundle}`,
        command: null,
      },
    }
  }

  if (linked.length > 0) {
    return {
      detected: true,
      install,
      bridge: {
        state: 'disabled',
        kind: 'plugin',
        detail: `已安装到 ${linked[0].profile}，但未在插件列表启用`,
        command: null,
      },
    }
  }

  const profile = profiles[0]?.profile ?? active.profile ?? 'desktop'
  return {
    detected: true,
    install,
    bridge: {
      state: 'missing',
      kind: 'plugin',
      detail: profiles.length > 0 ? '插件已登记，但依赖尚未安装' : 'DSH 配置里没有 AgentRing 插件',
      command: dshInstallCommand(profile, repoRoot),
      installable: false,
    },
  }
}

function dshProfiles(home) {
  const root = path.join(home, '.dsh', 'profiles')
  const profiles = []
  for (const entry of listDir(root)) {
    if (!entry.isDirectory()) continue
    const dir = path.join(root, entry.name)
    const manifest = readJson(path.join(dir, 'package.json'))
    if (!manifest) continue

    const dependencies =
      manifest.dependencies && typeof manifest.dependencies === 'object' ? manifest.dependencies : {}
    const bundles = Array.isArray(manifest.dsh?.profile?.bundles) ? manifest.dsh.profile.bundles : []
    const bundle = [...bundles, ...Object.keys(dependencies)].find(
      (name) => typeof name === 'string' && /agentring/i.test(name),
    )
    if (!bundle) continue

    const linkedPath = path.join(dir, 'node_modules', ...bundle.split('/'))
    profiles.push({
      profile: entry.name,
      bundle,
      listed: bundles.includes(bundle),
      linked: exists(linkedPath),
      enabled: bundles.includes(bundle) && exists(linkedPath),
    })
  }
  return profiles
}

function dshInstallCommand(profile, repoRoot) {
  const pluginDir = repoRoot ? path.join(repoRoot, 'packages', 'dsh-plugin') : null
  if (!pluginDir || !exists(pluginDir)) return null
  return `dsh plugin --profile ${profile} add ${pluginDir}`
}

// MARK: - Codex

function inspectCodex({ home, runtime, repoRoot, appDirs, cliDirs }) {
  const bundle = appBundle(home, 'ChatGPT.app', appDirs)
  const codexHome = path.join(home, '.codex')
  const binary = cli(home, 'codex', cliDirs)
  if (!bundle && !exists(codexHome) && !binary) {
    return { detected: false, install: null, bridge: null }
  }

  const install = {
    path: bundle || binary || codexHome,
    version: appVersion(bundle),
    running: Boolean(runtime?.codex?.running),
    profile: null,
  }

  const hooks = countAgentringHooks(readJson(path.join(codexHome, 'hooks.json')))
  const shim = path.join(home, '.agentring', 'hook.sh')
  const installer = installerFor('codex', repoRoot)
  const command = installer ? `node ${installer}` : null

  if (hooks > 0 && exists(shim)) {
    return {
      detected: true,
      install,
      bridge: {
        state: 'installed',
        kind: 'hooks',
        detail: `${hooks} 个 hook · ~/.codex/hooks.json`,
        command: null,
      },
    }
  }

  const detail =
    hooks > 0
      ? 'hooks.json 已登记，但 ~/.agentring/hook.sh 不存在'
      : exists(shim)
        ? 'hook.sh 已就绪，但 hooks.json 未登记'
        : '~/.codex/hooks.json 中没有 AgentRing hook'
  return {
    detected: true,
    install,
    bridge: { state: 'missing', kind: 'hooks', detail, command, installable: Boolean(installer) },
  }
}

// MARK: - Claude Code

function inspectClaude({ home, repoRoot, appDirs, cliDirs }) {
  const claudeHome = path.join(home, '.claude')
  const binary = cli(home, 'claude', cliDirs)
  if (!exists(claudeHome) && !binary) {
    return { detected: false, install: null, bridge: null }
  }

  const install = { path: binary || claudeHome, version: null, running: null, profile: null }
  const hooks = countAgentringHooks(readJson(path.join(claudeHome, 'settings.json')))
  if (hooks > 0) {
    return {
      detected: true,
      install,
      bridge: {
        state: 'installed',
        kind: 'hooks',
        detail: `${hooks} 个 hook · ~/.claude/settings.json`,
        command: null,
      },
    }
  }

  const installer = installerFor('claude', repoRoot)
  const command = installer ? `node ${installer}` : null
  return {
    detected: true,
    install,
    bridge: {
      state: 'missing',
      kind: 'hooks',
      detail: '~/.claude/settings.json 中没有 AgentRing hook',
      command,
      installable: Boolean(installer),
    },
  }
}

// MARK: - Filesystem helpers

function exists(file) {
  try {
    fs.accessSync(file)
    return true
  } catch {
    return false
  }
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    return null
  }
}

function listDir(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true })
  } catch {
    return []
  }
}

function firstExisting(candidates) {
  for (const candidate of candidates) {
    if (candidate && exists(candidate)) return candidate
  }
  return null
}

function appBundle(home, name, appDirs) {
  return firstExisting([...appDirs, path.join(home, 'Applications')].map((dir) => path.join(dir, name)))
}

function cli(home, name, cliDirs) {
  return firstExisting([
    ...cliDirs.map((dir) => path.join(dir, name)),
    path.join(home, '.local', 'bin', name),
  ])
}

function appVersion(bundle) {
  if (!bundle) return null
  try {
    const plist = fs.readFileSync(path.join(bundle, 'Contents', 'Info.plist'), 'utf8')
    return /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]*)<\/string>/.exec(plist)?.[1] ?? null
  } catch {
    return null
  }
}

/** Count JSON strings that point at an AgentRing hook command. */
function countAgentringHooks(node) {
  let count = 0
  const visited = new Set()
  const walk = (value) => {
    if (!value || typeof value !== 'object' || visited.has(value)) return
    visited.add(value)
    if (Array.isArray(value)) {
      for (const item of value) walk(item)
      return
    }
    for (const item of Object.values(value)) {
      if (typeof item === 'string') {
        if (/agentring/i.test(item)) count++
      } else {
        walk(item)
      }
    }
  }
  walk(node)
  return count
}
