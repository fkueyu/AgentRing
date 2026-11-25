// The daemon's live state is otherwise memory-only: a restart (upgrade, crash,
// launchd restart) would blank every session until each agent happens to emit
// its next event. Persist it and reload on boot instead.

import fs from 'node:fs'
import path from 'node:path'

import { CONFIG_DIR } from './config.mjs'

export const STATE_PATH = path.join(CONFIG_DIR, 'state.json')

export function loadState() {
  try {
    const parsed = JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'))
    return Array.isArray(parsed?.agents) ? parsed.agents : []
  } catch {
    return []
  }
}

export function saveState(agents) {
  try {
    fs.mkdirSync(CONFIG_DIR, { recursive: true })
    const tmp = `${STATE_PATH}.tmp`
    fs.writeFileSync(tmp, JSON.stringify({ version: 1, savedAt: Date.now(), agents }, null, 0))
    fs.renameSync(tmp, STATE_PATH)
  } catch {
    // Persistence is best-effort: never let it break event ingestion.
  }
}
