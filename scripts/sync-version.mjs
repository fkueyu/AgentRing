#!/usr/bin/env node
// Keep package versions in lockstep with the root VERSION file.
//
//   node scripts/sync-version.mjs          # write package.json versions
//   node scripts/sync-version.mjs --check  # fail if anything is stale (CI)

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(HERE, '..')
const VERSION = fs.readFileSync(path.join(ROOT, 'VERSION'), 'utf8').trim()
const PACKAGES = ['package.json', 'daemon/package.json', 'packages/dsh-plugin/package.json']
const check = process.argv.includes('--check')

if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(VERSION)) {
  console.error(`VERSION is not semver: ${JSON.stringify(VERSION)}`)
  process.exit(1)
}

let drift = false
for (const relative of PACKAGES) {
  const file = path.join(ROOT, relative)
  const data = JSON.parse(fs.readFileSync(file, 'utf8'))
  if (data.version === VERSION) continue
  drift = true
  if (check) {
    console.error(`${relative}: ${data.version} != VERSION ${VERSION}`)
    continue
  }
  data.version = VERSION
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n')
  console.log(`${relative}: ${VERSION}`)
}

if (check && drift) process.exit(1)
if (check) console.log(`all package versions match VERSION ${VERSION}`)
