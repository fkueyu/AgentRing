// Persistent raw-TCP frame stream for the ESP32.
//
// HTTP polling paid a request round-trip per frame. This server pushes one
// 72-byte frame per tick over a long-lived socket; clients just read 72 bytes
// at a time. The renderer is still the daemon's single `renderFrame` output.

import net from 'node:net'

function isLoopback(address) {
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1'
}

export function createFrameStream({ port, getFrame, intervalMs = 33, log = () => {} } = {}) {
  /** @type {Map<import('node:net').Socket, {remote: string, local: boolean}>} */
  const clients = new Map()
  const stats = {
    // Total traffic, useful for transport tests.
    frames: 0,
    lastAt: 0,
    lastFrom: '',
    clients: 0,
    // LAN-only counters exposed by /health. A local test client must never
    // make the app think the physical ring is online.
    lanFrames: 0,
    lanLastAt: 0,
    lanLastFrom: '',
    lanClients: 0,
  }
  let timer = null

  const server = net.createServer((socket) => {
    socket.setNoDelay(true)
    socket.setKeepAlive(true, 5000)
    const remote = socket.remoteAddress || ''
    const local = isLoopback(remote)
    clients.set(socket, { remote, local })
    stats.clients = clients.size
    if (!local) stats.lanClients++
    log(`stream client ${remote}${local ? ' (local)' : ''} (${clients.size})`)

    socket.on('error', () => {})
    socket.on('data', () => {}) // clients only listen
    socket.on('close', () => {
      const info = clients.get(socket)
      clients.delete(socket)
      stats.clients = clients.size
      if (info && !info.local) stats.lanClients = Math.max(0, stats.lanClients - 1)
      log(`stream client closed (${clients.size})`)
      if (clients.size === 0) stopTimer()
    })
    ensureTimer()
  })

  function tick() {
    if (clients.size === 0) return
    let frame
    try {
      frame = getFrame()
    } catch (err) {
      log(`stream frame error: ${err?.message || err}`)
      return
    }
    if (!Buffer.isBuffer(frame)) frame = Buffer.from(frame)
    const now = Date.now()
    let lanRemote = ''
    for (const [socket, info] of clients) {
      if (socket.destroyed) {
        clients.delete(socket)
        continue
      }
      // Never buffer a backlog of stale frames. A slow client simply misses
      // this tick and resumes on the next one.
      if (socket.writableLength > 4096) continue
      socket.write(frame)
      if (!info.local) lanRemote = info.remote
    }
    stats.frames++
    stats.lastAt = now
    stats.clients = clients.size
    if (lanRemote) {
      stats.lanFrames++
      stats.lanLastAt = now
      stats.lanLastFrom = lanRemote
    }
  }

  function ensureTimer() {
    if (!timer) timer = setInterval(tick, intervalMs)
  }

  function stopTimer() {
    if (timer) {
      clearInterval(timer)
      timer = null
    }
  }

  server.listen(port, '0.0.0.0')
  server.on('close', () => {
    stopTimer()
    for (const socket of clients.keys()) socket.destroy()
    clients.clear()
  })

  return {
    server,
    stats,
    close() {
      stopTimer()
      for (const socket of clients.keys()) socket.destroy()
      clients.clear()
      return new Promise((resolve) => server.close(resolve))
    },
  }
}
