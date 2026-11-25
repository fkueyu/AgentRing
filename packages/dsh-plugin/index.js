// AgentRing — report DeepSeek Harness agent activity to the local ring daemon.
//
// Besides the lifecycle events, this plugin reconciles every 30 s: a session
// that existed before the plugin (or the daemon) started would otherwise stay
// invisible until its next state change. Reconciling also heartbeats live
// agents so a long, quiet turn is not mistaken for a stale one.

import http from 'node:http'

const HOST = '127.0.0.1'
const PORT = Number(process.env.AGENTRING_PORT || 7801)
const RECONCILE_MS = Number(process.env.AGENTRING_RECONCILE_MS || 30_000)

// One keep-alive socket preserves event order (important for error -> idle and
// tool-start -> tool-end) and avoids a TCP handshake per transition.
const httpAgent = new http.Agent({ keepAlive: true, maxSockets: 1 })

function send(event, extra = {}) {
  let body
  try {
    body = Buffer.from(JSON.stringify({ source: 'dsh', event, ...extra }))
  } catch {
    return
  }
  let req
  try {
    req = http.request(
      {
        host: HOST,
        port: PORT,
        path: '/ingest',
        method: 'POST',
        agent: httpAgent,
        headers: { 'content-type': 'application/json', 'content-length': body.length },
        timeout: 400,
      },
      (res) => res.resume(),
    )
  } catch {
    // A bad AGENTRING_PORT must not break the Harness tool pipeline.
    return
  }
  req.on('error', () => {})
  req.on('timeout', () => req.destroy())
  req.end(body)
}

/** Session ids the daemon already knows, or null when it is not reachable. */
function daemonSessions() {
  return new Promise((resolve) => {
    let req
    try {
      req = http.get({ host: HOST, port: PORT, path: '/state', agent: httpAgent, timeout: 500 }, (res) => {
        let body = ''
        res.setEncoding('utf8')
        res.on('data', (chunk) => (body += chunk))
        res.on('end', () => {
          try {
            const parsed = JSON.parse(body)
            resolve(new Set((parsed.agents || []).map((session) => session.sessionId)))
          } catch {
            resolve(null)
          }
        })
      })
    } catch {
      resolve(null)
      return
    }
    req.on('error', () => resolve(null))
    req.on('timeout', () => {
      req.destroy()
      resolve(null)
    })
  })
}

function sessionInfo(agent) {
  // Session.header is the detached creation metadata; cwd lives there.
  const cwd = agent?.session?.header?.cwd
  return { session_id: agent?.id, cwd }
}

export const inject = ['agents']

export function apply(ctx) {
  const announced = new Set()

  const announce = (agent) => {
    const info = sessionInfo(agent)
    if (announced.has(agent.id)) {
      // Heartbeat: keeps `updated` fresh without touching the state.
      send('control', info)
      return
    }
    announced.add(agent.id)
    send(agent.status === 'running' ? 'thinking' : 'session-start', info)
  }

  async function reconcile() {
    try {
      const known = await daemonSessions()
      for (const agent of ctx.agents.list()) {
        // The daemon restarted and lost this session: announce it again.
        if (known && !known.has(agent.id)) announced.delete(agent.id)
        announce(agent)
      }
    } catch {
      // Reconciliation is best-effort; the next tick retries.
    }
  }

  ctx.on('agent/created', ({ agent }) => {
    announced.add(agent.id)
    send('session-start', sessionInfo(agent))
  })

  ctx.on('agent/status', ({ agent, status }) => {
    announced.add(agent.id)
    send(status === 'running' ? 'thinking' : 'turn-end', sessionInfo(agent))
  })

  ctx.on('agent/error', ({ agent, error }) => {
    send('error', {
      ...sessionInfo(agent),
      message: error && typeof error === 'object' && 'message' in error ? String(error.message) : String(error),
    })
  })

  ctx.on('agent/disposed', ({ agent }) => {
    announced.delete(agent.id)
    send('session-end', sessionInfo(agent))
  })

  // Tool-level detail: the ring shows which tool is running, same granularity
  // the Codex hooks provided.
  ctx.on('tools/pre-execute', async (exec, next) => {
    try {
      const id = exec?.agent?.id
      if (id && exec?.name) send('tool-start', { session_id: id, tool: String(exec.name) })
    } catch {}
    return await next()
  })

  ctx.on('tools/post-execute', async (exec, result, next) => {
    try {
      const id = exec?.agent?.id
      if (id) send('thinking', { session_id: id })
    } catch {}
    return await next()
  })

  // Both interaction events are waterfall chains: the first listener that
  // returns an outcome claims the request and short-circuits every listener
  // behind it. The desktop client's approval/question bridge registers its
  // forwarding listener during the base bundle, before this profile plugin, so
  // a normal listener here would never run — the ring stayed on "tool" while
  // the user was staring at the prompt. `prepend` puts the observer first; it
  // then calls next(), so the client still owns the actual answer.
  //
  // Structured questions (`ask_user_question`) also block on a human, but they
  // do not go through approval/request. Without this the ring shows "tool"
  // while the agent is actually waiting for an answer.
  ctx.on('user-questions/request', async (req, next) => {
    const id = req?.agent?.id
    if (id) send('waiting', { session_id: id, tool: 'question' })
    try {
      return await next()
    } finally {
      if (id) send('thinking', { session_id: id })
    }
  }, true)

  // A pending approval is the state a physical indicator is most useful for.
  ctx.on('approval/request', async (req, next) => {
    send('waiting', { session_id: req?.agent?.id, tool: req?.toolName })
    try {
      return await next()
    } finally {
      send('thinking', sessionInfo(req?.agent))
    }
  }, true)

  ctx.effect(() => {
    const timer = setInterval(() => {
      void reconcile()
    }, RECONCILE_MS)
    void reconcile()
    return () => clearInterval(timer)
  })
}
