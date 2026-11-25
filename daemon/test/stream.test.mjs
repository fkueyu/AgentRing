import test from 'node:test'
import assert from 'node:assert/strict'
import net from 'node:net'

import { createFrameStream } from '../src/stream.mjs'

test('streams 72-byte frames over one persistent TCP connection', async () => {
  const stream = createFrameStream({
    port: 0,
    intervalMs: 5,
    getFrame: () => Buffer.alloc(72, 7),
  })
  await new Promise((resolve) => stream.server.once('listening', resolve))
  const port = stream.server.address().port
  const socket = net.connect(port, '127.0.0.1')
  await new Promise((resolve, reject) => {
    socket.once('connect', resolve)
    socket.once('error', reject)
  })

  const received = await new Promise((resolve, reject) => {
    let bytes = 0
    const timer = setTimeout(() => reject(new Error(`timed out after ${bytes} bytes`)), 1000)
    socket.on('data', (chunk) => {
      bytes += chunk.length
      if (bytes >= 144) {
        clearTimeout(timer)
        resolve(bytes)
      }
    })
  })

  assert.equal(received, 144)
  assert.ok(stream.stats.frames >= 2)
  assert.equal(stream.stats.clients, 1)
  // A local test client must not make the app think the physical ring is online.
  assert.equal(stream.stats.lanClients, 0)
  assert.equal(stream.stats.lanFrames, 0)
  socket.destroy()
  await stream.close()
})
