// Codex Desktop ends its hook session at the end of every turn (the CLI
// subprocess exits), so an open conversation looks "gone" between turns.
// Tie liveness to the desktop app process instead of the hook session: while
// the app runs, finished sessions linger rather than vanish.

import { execFileSync } from 'node:child_process'

const CACHE_MS = 15_000
let cached = { at: 0, running: false }

export function codexDesktopRunning() {
  const now = Date.now()
  if (now - cached.at < CACHE_MS) return cached.running
  cached = { at: now, running: probe() }
  return cached.running
}

function probe() {
  try {
    execFileSync('/usr/bin/pgrep', ['-x', 'ChatGPT'], { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}
