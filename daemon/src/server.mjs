import http from 'node:http'
import { readFileSync } from 'node:fs'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { DEFAULT_PORT, LED_COUNT } from './protocol.mjs'
import { createFrameStream } from './stream.mjs'
import { createStore, mapHookPayload } from './state.mjs'
import { renderFrame } from './frame.mjs'
import { loadConfig, sanitize, saveConfig } from './config.mjs'
import { EFFECTS, capabilities } from './effects.mjs'
import { inspectSources, installBridge } from './sources.mjs'
import { loadState, saveState } from './persist.mjs'
import { codexDesktopRunning } from './host.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = path.resolve(HERE, '..', '..')
const PREVIEW = path.join(HERE, '..', 'preview', 'index.html')

const DAEMON_VERSION = (() => {
  try {
    return JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version ?? null
  } catch {
    return null
  }
})()

const MAX_BODY = 64 * 1024
const LOCAL_ONLY_READS = new Set([
  '/',
  '/index.html',
  '/state',
  '/config',
  '/capabilities',
  '/sources',
  '/preview',
])

export function createServer({ port = DEFAULT_PORT, streamPort = null, log = () => {} } = {}) {
  const store = createStore()
  store.hydrate(loadState())
  let config = loadConfig()
  // A temporary synthetic preview that the physical ring, the stream and
  // /frame all see. The app refreshes it while auditioning an effect, and it
  // expires on its own if that client disappears.
  let preview = null

  function activePreview(now = Date.now()) {
    return preview && now < preview.expiresAt ? preview : null
  }

  /** One synthetic session rendered through the normal pipeline. */
  function renderPreviewFrame(state, effect, now) {
    // Never pick a disabled source: selectAgents filters it and the preview
    // would silently fall back to standby.
    const source =
      Object.entries(config.sources).find(([, entry]) => entry?.enabled !== false)?.[0] || 'preview'
    const previewConfig = {
      ...config,
      motion: { ...config.motion, effects: { ...config.motion.effects, [state]: effect } },
    }
    const snapshot = {
      ts: now,
      agents: [
        {
          key: `preview:${state}`,
          source,
          sessionId: `preview:${state}`,
          label: '预览',
          state,
          // A done preview should loop through the flash instead of freezing
          // on the first frame.
          sinceMs: state === 'done' ? now % 4000 : 0,
          updatedMs: 0,
        },
      ],
    }
    return Buffer.from(renderFrame(snapshot, { leds: LED_COUNT, config: previewConfig, now }))
  }

  /**
   * The frame the ring, the stream and /frame all see: the temporary preview
   * while one is active, otherwise the live snapshot.
   */
  function currentFrame(now = Date.now()) {
    const active = activePreview(now)
    if (active) return renderPreviewFrame(active.state, active.effect, now)
    return Buffer.from(renderFrame(store.snapshot(snapshotOptions(config)), { config, now }))
  }

  const stream = streamPort
    ? createFrameStream({ port: streamPort, log, getFrame: () => currentFrame() })
    : null

  let saveTimer = null
  let lastHeartbeatSave = 0
  let frameCount = 0
  let lastFrameAt = 0
  let lastFrameFrom = ''
  let lanFrameCount = 0
  let lanLastFrameAt = 0
  let lanLastFrameFrom = ''
  const scheduleSave = () => {
    if (saveTimer) return
    saveTimer = setTimeout(() => {
      saveTimer = null
      saveState(store.serialize())
    }, 400)
  }
  process.on('exit', () => saveState(store.serialize()))

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || '/', 'http://localhost')

      // Only /frame and /health are reachable from the LAN. Everything else,
      // including the browser preview and /state (which contains cwd paths),
      // stays on loopback. No CORS headers either: the preview is same-origin
      // and native clients ignore it.
      if (req.method !== 'GET' && req.method !== 'OPTIONS' && !isLoopback(req)) {
        res.writeHead(403).end('local only')
        return
      }

      if (req.method === 'OPTIONS') {
        res.writeHead(204).end()
        return
      }

      if (LOCAL_ONLY_READS.has(url.pathname) && !isLoopback(req)) {
        res.writeHead(403).end('local only')
        return
      }

      if (url.pathname === '/ingest' && req.method === 'POST') {
        const body = await readBody(req)
        let payload
        try {
          payload = JSON.parse(body || '{}')
        } catch {
          res.writeHead(400).end('bad json')
          return
        }
        const source = url.searchParams.get('source')
        // `?source=` marks a raw hook payload (Codex shape); without it the
        // adapter already speaks the unified vocabulary in snake_case.
        const ev = source
          ? { ...mapHookPayload(payload), source }
          : {
              source: payload.source,
              event: payload.event,
              sessionId: payload.session_id ?? payload.sessionId,
              cwd: payload.cwd,
              label: payload.label,
              tool: payload.tool,
              kind: payload.kind,
              message: payload.message,
            }
        const result = store.ingest(ev)
        if (result.ok) {
          if (ev.event === 'control') {
            // Heartbeats are liveness only. Persist them at most once a minute
            // (so a restart does not treat live sessions as stale) and keep them
            // out of the log, which they would otherwise dominate.
            if (Date.now() - lastHeartbeatSave > 60_000) {
              lastHeartbeatSave = Date.now()
              scheduleSave()
            }
          } else {
            scheduleSave()
            log(`ingest ${ev.source}/${ev.event} ${ev.sessionId || ev.cwd || ''}`.trim())
          }
        }
        res.writeHead(result.ok ? 204 : 400).end()
        return
      }

      if (url.pathname === '/capabilities') {
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(capabilities()))
        return
      }

      const installMatch = /^\/sources\/([a-z0-9-]+)\/install$/.exec(url.pathname)
      if (installMatch && req.method === 'POST') {
        // One-click bridge install. Only AgentRing's own scripts are runnable
        // (see BRIDGE_INSTALLERS); the display command in a probe is not.
        const id = installMatch[1]
        const result = await installBridge({ id, repoRoot: REPO_ROOT })
        if (!result.ok) {
          log(`bridge ${id} failed: ${result.error}`)
          res.writeHead(result.status || 500, { 'content-type': 'application/json' }).end(
            JSON.stringify({ ok: false, error: result.error }),
          )
          return
        }
        log(`bridge ${id} installed`)
        const report = await inspectSources({ repoRoot: REPO_ROOT })
        res.writeHead(200, { 'content-type': 'application/json' }).end(
          JSON.stringify({ ok: true, output: result.output, report }),
        )
        return
      }

      if (url.pathname === '/sources') {
        // Advisory install/bridge detection for the Sources page. It reads
        // manifests and app bundles only; it never installs or edits anything.
        // Loopback-only because the payload contains local paths.
        res.writeHead(200, { 'content-type': 'application/json' }).end(
          JSON.stringify(await inspectSources({ repoRoot: REPO_ROOT })),
        )
        return
      }

      if (url.pathname === '/state') {
        // Config is large and changes only through POST /config; callers that
        // need it ask for `?config=1` (the app fetches it on connect instead).
        const body = store.snapshot(snapshotOptions(config))
        if (url.searchParams.get('config') === '1') body.config = config
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(body))
        return
      }

      if (url.pathname === '/forget' && req.method === 'POST') {
        const body = await readBody(req)
        let payload = {}
        try {
          payload = JSON.parse(body || '{}')
        } catch {}
        if (payload.all) {
          const count = store.clear()
          scheduleSave()
          log(`cleared ${count} session(s)`)
          res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ cleared: count }))
          return
        }
        const removed = payload.sessionId ? store.forget(payload.sessionId) : 0
        scheduleSave()
        log(`forgot ${payload.sessionId || '(none)'}`)
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ removed }))
        return
      }

      if (url.pathname === '/config/reset' && req.method === 'POST') {
        // The daemon owns defaults and the full source palette; the app must
        // not reset with a hand-maintained subset of its own.
        config = saveConfig(sanitize({}))
        log('config reset')
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(config))
        return
      }

      if (url.pathname === '/config') {
        if (req.method === 'GET') {
          res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(config))
          return
        }
        if (req.method === 'POST' || req.method === 'PATCH') {
          const body = await readBody(req)
          let patch
          try {
            patch = JSON.parse(body || '{}')
          } catch {
            res.writeHead(400).end('bad json')
            return
          }
          config = saveConfig(sanitize(patch, config))
          log(
            `config ${config.display.accent} · ${Math.round(config.display.brightness * 100)}% brightness`,
          )
          res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(config))
          return
        }
      }

      if (url.pathname === '/preview') {
        if (req.method === 'GET') {
          // One-off synthetic frame: the same renderer the ring uses, without
          // changing what the ring shows.
          const state = url.searchParams.get('state') || 'thinking'
          const effect = url.searchParams.get('effect') || config.motion.effects[state]
          if (!EFFECTS[state]) {
            res.writeHead(400).end('unknown state')
            return
          }
          if (!EFFECTS[state].includes(effect)) {
            res.writeHead(400).end('unknown effect')
            return
          }
          const body = renderPreviewFrame(state, effect, Date.now())
          res.writeHead(200, {
            'content-type': 'application/octet-stream',
            'content-length': body.length,
            'cache-control': 'no-store',
          })
          res.end(body)
          return
        }

        if (req.method === 'POST') {
          // Mirror an auditioned state/effect to the physical ring (and every
          // /frame reader) until the TTL expires. The app refreshes the TTL
          // while the preview is open.
          const body = await readBody(req)
          let payload
          try {
            payload = JSON.parse(body || '{}')
          } catch {
            res.writeHead(400).end('bad json')
            return
          }
          const state = payload.state || 'thinking'
          const effect = payload.effect || config.motion.effects[state]
          if (!EFFECTS[state]) {
            res.writeHead(400).end('unknown state')
            return
          }
          if (!EFFECTS[state].includes(effect)) {
            res.writeHead(400).end('unknown effect')
            return
          }
          const ttlMs = Math.min(600_000, Math.max(1_000, Number(payload.ttlMs) || 45_000))
          preview = { state, effect, expiresAt: Date.now() + ttlMs }
          log(`preview ${state}/${effect} on the ring for ${Math.round(ttlMs / 1000)}s`)
          res.writeHead(200, { 'content-type': 'application/json' }).end(
            JSON.stringify({ ok: true, state, effect, expiresAt: preview.expiresAt }),
          )
          return
        }

        if (req.method === 'DELETE') {
          preview = null
          log('preview cleared')
          res.writeHead(204).end()
          return
        }

        res.writeHead(405).end('method not allowed')
        return
      }

      if (url.pathname === '/frame') {
        frameCount++
        lastFrameAt = Date.now()
        lastFrameFrom = req.socket.remoteAddress || ''
        if (!isLoopback(req)) {
          lanFrameCount++
          lanLastFrameAt = Date.now()
          lanLastFrameFrom = req.socket.remoteAddress || ''
        }
        const body = currentFrame()
        res.writeHead(200, {
          'content-type': 'application/octet-stream',
          'content-length': body.length,
          'cache-control': 'no-store',
        })
        res.end(body)
        return
      }

      if (url.pathname === '/health') {
        res.writeHead(200, { 'content-type': 'application/json' }).end(
          JSON.stringify({
            ok: true,
            version: DAEMON_VERSION,
            sessions: store.size,
            port,
            preview: activePreview()?.state ?? null,
            frames: frameCount,
            lanFrames: lanFrameCount,
            lanLastFrameAt,
            lanLastFrameFrom,
            lastFrameAt,
            lastFrameFrom,
            streamClients: stream?.stats.lanClients ?? 0,
            streamFrames: stream?.stats.lanFrames ?? 0,
            streamLastFrameAt: stream?.stats.lanLastAt ?? 0,
            streamLastFrameFrom: stream?.stats.lanLastFrom ?? '',
          }),
        )
        return
      }

      if (url.pathname === '/' || url.pathname === '/index.html') {
        const html = await fs.readFile(PREVIEW, 'utf8')
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }).end(html)
        return
      }

      res.writeHead(404).end('not found')
    } catch (err) {
      log(`error ${err?.message || err}`)
      if (!res.headersSent) res.writeHead(500).end('internal error')
    }
  })

  server.on('close', () => {
    if (stream) void stream.close()
  })

  return { server, store, stream }
}

function snapshotOptions(config) {
  return {
    doneHoldMs: config.motion.doneHoldSeconds * 1000,
    staleMs: config.motion.staleMinutes * 60 * 1000,
    // Only Codex needs the long grace: its desktop app closes a hook session
    // after every turn, so deleting the record makes the ring flicker. Other
    // sources (DeepSeek Harness) end sessions for real and should be dropped
    // after the short grace.
    endedGraceFor: (source) =>
      source === 'codex' && codexDesktopRunning() ? 45 * 60 * 1000 : 3 * 60 * 1000,
  }
}

function isLoopback(req) {
  const address = req.socket.remoteAddress || ''
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1'
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0
    const chunks = []
    req.on('data', (c) => {
      size += c.length
      if (size > MAX_BODY) {
        reject(new Error('body too large'))
        req.destroy()
        return
      }
      chunks.push(c)
    })
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    req.on('error', reject)
  })
}
