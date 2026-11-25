import test, { after, before } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

let server
let base
let lanBase
let tempHome
let previousHome

function nonLoopbackIPv4() {
  for (const addresses of Object.values(os.networkInterfaces())) {
    for (const address of addresses || []) {
      if (address.family === 'IPv4' && !address.internal) return address.address
    }
  }
  return null
}

async function get(pathname) {
  return fetch(`${base}${pathname}`)
}

async function post(pathname, body, headers = {}) {
  return fetch(`${base}${pathname}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

before(async () => {
  tempHome = fs.mkdtempSync(path.join(os.tmpdir(), 'agentring-api-'))
  previousHome = process.env.HOME
  process.env.HOME = tempHome
  const { createServer } = await import('../src/server.mjs')
  server = createServer({ port: 0, log: () => {} }).server
  await new Promise((resolve) => server.listen(0, '0.0.0.0', resolve))
  const port = server.address().port
  base = `http://127.0.0.1:${port}`
  const ip = nonLoopbackIPv4()
  lanBase = ip ? `http://${ip}:${port}` : null
})

after(async () => {
  if (server) {
    server.closeAllConnections?.()
    await new Promise((resolve) => server.close(resolve))
  }
  if (previousHome === undefined) delete process.env.HOME
  else process.env.HOME = previousHome
  if (tempHome) fs.rmSync(tempHome, { recursive: true, force: true })
})

test('local reads expose state, config and the effect catalogue', async () => {
  const state = await get('/state')
  assert.equal(state.status, 200)
  assert.ok(Array.isArray((await state.json()).agents))

  const config = await get('/config')
  assert.equal(config.status, 200)
  const configBody = await config.json()
  assert.equal(configBody.version, 3)
  assert.equal(configBody.display.accent, 'state')

  const health = await get('/health')
  assert.equal(health.status, 200)
  assert.match((await health.json()).version, /^\d+\.\d+\.\d+/)

  const caps = await get('/capabilities')
  assert.equal(caps.status, 200)
  const body = await caps.json()
  assert.equal(body.version, 2)
  assert.equal(body.standby.default, 'dot')
  assert.equal(body.accents.default, 'state')
  assert.deepEqual(
    body.accents.options.map((option) => option.id),
    ['state', 'source', 'neon', 'sunset', 'mint', 'aurora', 'ember', 'rainbow'],
  )
  assert.deepEqual(
    body.standbyPalettes.options.map((option) => option.id),
    ['mono', 'neon', 'sunset', 'mint', 'aurora', 'ember', 'rainbow'],
  )
  assert.equal(body.effects.editing.default, 'patches')
  assert.deepEqual(
    body.effects.editing.options.map((option) => option.id),
    ['patches', 'pulse'],
  )
})

test('the source report is local-only and keeps the registry order', async () => {
  const sources = await get('/sources')
  assert.equal(sources.status, 200)
  const body = await sources.json()
  assert.ok(body.checkedAt > 0)
  assert.deepEqual(
    body.entries.map((entry) => entry.id),
    ['dsh', 'codex', 'claude'],
  )
  for (const entry of body.entries) {
    assert.equal(typeof entry.detected, 'boolean', entry.id)
    // A detected tool always explains itself; an absent one has no bridge.
    if (entry.detected) assert.ok(entry.bridge, `${entry.id} bridge`)
    else assert.equal(entry.bridge, null)
  }
})

test('the one-click installer wires Codex and Claude in the daemon home', async () => {
  fs.mkdirSync(path.join(tempHome, '.codex'), { recursive: true })
  fs.mkdirSync(path.join(tempHome, '.claude'), { recursive: true })

  const codex = await post('/sources/codex/install', '')
  assert.equal(codex.status, 200)
  const codexBody = await codex.json()
  assert.equal(codexBody.ok, true)
  assert.equal(
    codexBody.report.entries.find((entry) => entry.id === 'codex').bridge.state,
    'installed',
  )

  const claude = await post('/sources/claude/install', '')
  assert.equal(claude.status, 200)
  const claudeBody = await claude.json()
  assert.equal(claudeBody.ok, true)
  assert.equal(
    claudeBody.report.entries.find((entry) => entry.id === 'claude').bridge.state,
    'installed',
  )

  // Both hook installers share the stable shim.
  assert.equal(fs.existsSync(path.join(tempHome, '.agentring', 'hook.sh')), true)
  assert.equal(fs.existsSync(path.join(tempHome, '.codex', 'hooks.json')), true)
  const settings = JSON.parse(
    fs.readFileSync(path.join(tempHome, '.claude', 'settings.json'), 'utf8'),
  )
  assert.ok(Object.keys(settings.hooks).includes('PreToolUse'))
})

test('the installer route rejects unknown and copy-only sources', async () => {
  const unknown = await post('/sources/laser/install', '')
  assert.equal(unknown.status, 400)
  // DSH's install is a package-manager command, not one of our scripts.
  const copyOnly = await post('/sources/dsh/install', '')
  assert.equal(copyOnly.status, 400)
})

test('preview renders a synthetic frame and rejects unknown effects', async () => {
  const frame = await get('/preview?state=thinking&effect=comet')
  assert.equal(frame.status, 200)
  assert.equal(frame.headers.get('content-length'), '72')
  assert.equal((await frame.arrayBuffer()).byteLength, 72)

  const badState = await get('/preview?state=laser')
  assert.equal(badState.status, 400)
  const badEffect = await get('/preview?state=thinking&effect=disco')
  assert.equal(badEffect.status, 400)
  const removedEffect = await get('/preview?state=thinking&effect=pulse')
  assert.equal(removedEffect.status, 400)
})

test('preview can be mirrored to the ring, cleared and expired', async () => {
  const lit = (bytes) =>
    Array.from({ length: 24 }, (_, index) => bytes[index * 3]).filter((red) => red > 40).length

  const standby = new Uint8Array(await (await get('/frame')).arrayBuffer())
  assert.ok(lit(standby) <= 1, `standby should keep one LED lit, got ${lit(standby)}`)

  const on = await post('/preview', { state: 'error', effect: 'solid', ttlMs: 1500 })
  assert.equal(on.status, 200)
  assert.equal((await on.json()).state, 'error')
  const during = new Uint8Array(await (await get('/frame')).arrayBuffer())
  assert.equal(lit(during), 24, 'the preview should paint the whole ring')

  const cleared = await fetch(`${base}/preview`, { method: 'DELETE' })
  assert.equal(cleared.status, 204)
  const afterClear = new Uint8Array(await (await get('/frame')).arrayBuffer())
  assert.ok(lit(afterClear) <= 1, 'DELETE should restore the live frame')

  const short = await post('/preview', { state: 'error', effect: 'solid', ttlMs: 1000 })
  assert.equal(short.status, 200)
  await new Promise((resolve) => setTimeout(resolve, 1150))
  const expired = new Uint8Array(await (await get('/frame')).arrayBuffer())
  assert.ok(lit(expired) <= 1, 'a preview should expire without a client')
})

test('preview rejects unknown states and effects on POST', async () => {
  const badState = await post('/preview', { state: 'laser', effect: 'solid' })
  assert.equal(badState.status, 400)
  const badEffect = await post('/preview', { state: 'error', effect: 'disco' })
  assert.equal(badEffect.status, 400)
})

test('config reset restores the daemon defaults and the full source palette', async () => {
  const changed = await post('/config', { motion: { effects: { editing: 'pulse' } } })
  assert.equal(changed.status, 200)
  assert.equal((await changed.json()).motion.effects.editing, 'pulse')

  const reset = await post('/config/reset', '')
  assert.equal(reset.status, 200)
  const config = await reset.json()
  assert.equal(config.motion.effects.editing, 'patches')
  assert.equal(Object.keys(config.sources).length, 18)
  assert.equal(config.sources.codex.color, '#10a37f')
})

test('bad JSON is rejected without taking the daemon down', async () => {
  const bad = await post('/config', '{')
  assert.equal(bad.status, 400)
  const stillUp = await get('/health')
  assert.equal(stillUp.status, 200)
})

test('oversized bodies are rejected', async () => {
  const oversized = JSON.stringify({ source: 'dsh', event: 'thinking', padding: 'x'.repeat(70 * 1024) })
  const status = await post('/ingest', oversized)
    .then((response) => response.status)
    .catch(() => 500)
  assert.ok(status === 500 || status === 0, `unexpected status ${status}`)
})

test('frame and health stay available; other routes are local-only on the LAN', async (t) => {
  if (!lanBase) {
    t.skip('no non-loopback IPv4 interface')
    return
  }
  for (const pathname of [
    '/',
    '/state',
    '/config',
    '/capabilities',
    '/sources',
    '/preview?state=thinking&effect=breathe',
  ]) {
    const response = await fetch(`${lanBase}${pathname}`)
    assert.equal(response.status, 403, `${pathname} should be local-only`)
  }

  const frame = await fetch(`${lanBase}/frame`)
  assert.equal(frame.status, 200)
  assert.equal(frame.headers.get('content-length'), '72')
  assert.equal((await frame.arrayBuffer()).byteLength, 72)

  const health = await fetch(`${lanBase}/health`)
  assert.equal(health.status, 200)
  const healthBody = await health.json()
  assert.equal(healthBody.ok, true)
  assert.equal(healthBody.lanLastFrameFrom, new URL(lanBase).hostname)
})

test('unknown routes return 404 and no CORS header is added', async () => {
  const missing = await get('/nope')
  assert.equal(missing.status, 404)
  assert.equal(missing.headers.get('access-control-allow-origin'), null)
})
