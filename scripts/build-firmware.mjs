#!/usr/bin/env node
/**
 * Build the ESP32-C3 ring firmware and publish a versioned USB image.
 *
 * Usage:
 *   node scripts/build-firmware.mjs --public-dir ../web/public/agentring/firmware
 *
 * The app/direct downloader reads the generated manifest.json. `app` is written
 * at 0x10000 for normal USB updates (NVS/Wi-Fi settings survive); `merged` is
 * written at 0x0 for a blank board or recovery.
 */
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const publicDirArg = args.find((arg, index) => arg === '--public-dir' && args[index + 1])
const publicDir = resolve(
  root,
  publicDirArg ? args[args.indexOf('--public-dir') + 1] : '../web/public/agentring/firmware'
)
const cli = process.env.ARDUINO_CLI
  || '/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli'
const fqbn = 'esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app'
const version = readFileSync(join(root, 'VERSION'), 'utf8').trim()
const sketch = join(root, 'firmware/esp32/agentring_ring')
const work = mkdtempSync(join(tmpdir(), 'agentring-fw-'))
const buildDir = join(work, 'build')
const outDir = join(work, 'out')
mkdirSync(outDir, { recursive: true })

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

if (!existsSync(cli)) {
  console.error(`arduino-cli not found at ${cli}; set ARDUINO_CLI`)
  process.exit(1)
}

try {
  console.log(`==> compiling ${version} (${fqbn})`)
  execFileSync(cli, [
    'compile',
    '--fqbn', fqbn,
    '--build-path', buildDir,
    '--output-dir', outDir,
    sketch,
  ], { cwd: root, stdio: 'inherit' })

  const appSource = join(outDir, 'agentring_ring.ino.bin')
  const mergedSource = join(outDir, 'agentring_ring.ino.merged.bin')
  if (!existsSync(appSource) || !existsSync(mergedSource)) {
    throw new Error('compiled images not found')
  }

  const appName = `agentring-${version}-app.bin`
  const mergedName = `agentring-${version}-merged.bin`
  mkdirSync(publicDir, { recursive: true })
  copyFileSync(appSource, join(publicDir, appName))
  copyFileSync(mergedSource, join(publicDir, mergedName))

  const manifest = {
    schema: 1,
    version,
    builtAt: new Date().toISOString(),
    fqbn,
    partitionScheme: 'huge_app',
    app: {
      file: appName,
      offset: 0x10000,
      size: readFileSync(appSource).length,
      sha256: sha256(appSource),
    },
    merged: {
      file: mergedName,
      offset: 0,
      size: readFileSync(mergedSource).length,
      sha256: sha256(mergedSource),
    },
    notes: 'Write app at 0x10000 for a normal USB update; write merged at 0x0 for a blank board or recovery. The app and merged hashes are checked before flashing.',
  }
  writeFileSync(join(publicDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)

  console.log(`==> published ${version}`)
  console.log(`    ${join(publicDir, 'manifest.json')}`)
  console.log(`    ${appName} (${manifest.app.size} bytes, 0x10000)`)
  console.log(`    ${mergedName} (${manifest.merged.size} bytes, 0x0)`)
} finally {
  rmSync(work, { recursive: true, force: true })
}
