// SPDX-License-Identifier: GPL-3.0-only
// Helpers for scripts/ios.js (ios/prd.json IOS-001): murmur's own
// simulator, the tools on PATH, the shared rules copy, and the app's
// SMOKE_RESULT line. Pure where it can be, so desktop CI tests it on
// every platform without Xcode.
const { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync } = require('node:fs')
const { delimiter, join } = require('node:path')

const SMOKE_SIMULATOR = 'murmur smoke'
const MIN_IOS = 26

/** Simulator builds sign ad hoc, so CI needs no certificates; the
 *  entitlements (the app group) still ride along in the signature. */
const SIM_SIGNING = ['CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=', 'PROVISIONING_PROFILE_SPECIFIER=']

function compareVersions(a, b) {
  const pa = String(a).split('.').map(Number)
  const pb = String(b).split('.').map(Number)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0)
    if (d !== 0) return d
  }
  return 0
}

/**
 * murmur's own simulator from `xcrun simctl list --json devicetypes
 * runtimes devices`: the device named murmur smoke on an available iOS
 * 26 or later runtime, or a recipe to create one on the newest such
 * runtime. Never another project's simulator, booted or not.
 */
function pickSmokeSimulator(list) {
  const runtimes = list.runtimes.filter(
    (r) => r.isAvailable && r.platform === 'iOS' && Number(String(r.version).split('.')[0]) >= MIN_IOS
  )
  if (runtimes.length === 0) {
    throw new Error(`no iOS ${MIN_IOS} or later simulator runtime is installed (Xcode, Settings, Components)`)
  }
  for (const runtime of runtimes) {
    const found = (list.devices[runtime.identifier] || []).find((d) => d.name === SMOKE_SIMULATOR && d.isAvailable)
    if (found) return { udid: found.udid }
  }
  const newest = [...runtimes].sort((a, b) => compareVersions(b.version, a.version))[0]
  const iphones = (newest.supportedDeviceTypes || list.devicetypes).filter((t) => t.productFamily === 'iPhone')
  // simctl lists the newest iPhone first.
  const type = iphones.find((t) => t.name === 'iPhone 17') || iphones[0]
  if (!type) throw new Error(`iOS ${newest.version} offers no iPhone simulator`)
  return { create: { name: SMOKE_SIMULATOR, deviceType: type.identifier, runtime: newest.identifier } }
}

/** The tool's full path, or null when no PATH directory holds it. */
function findOnPath(name, pathEnv = process.env.PATH, exists = existsSync) {
  for (const dir of (pathEnv || '').split(delimiter)) {
    if (dir && exists(join(dir, name))) return join(dir, name)
  }
  return null
}

/** Mirrors shared/*.json into dest, which starts empty each time. */
function copySharedJson(src, dest) {
  rmSync(dest, { recursive: true, force: true })
  mkdirSync(dest, { recursive: true })
  const names = readdirSync(src).filter((f) => f.endsWith('.json'))
  for (const name of names) copyFileSync(join(src, name), join(dest, name))
  return names.length
}

/** The app's {"ok", "checks"} result, or null when it never printed one. */
function parseSmokeLine(output) {
  const line = output
    .split(/\r?\n/)
    .map((l) => l.trim())
    .find((l) => l.startsWith('SMOKE_RESULT '))
  return line ? JSON.parse(line.slice('SMOKE_RESULT '.length)) : null
}

/** The folder the app saved its pill shots in (IOS-010), or null when it
 *  never said. */
function parsePillShotsLine(output) {
  const line = output
    .split(/\r?\n/)
    .map((l) => l.trim())
    .find((l) => l.startsWith('PILL_SHOTS '))
  return line ? line.slice('PILL_SHOTS '.length) : null
}

/** A setting's value in project.yml, such as MARKETING_VERSION. */
function projectSetting(projectYml, name) {
  const match = projectYml.match(new RegExp(`^\\s*${name}:\\s*"?([^"\\s]+)"?\\s*$`, 'm'))
  if (!match) throw new Error(`project.yml has no ${name}`)
  return match[1]
}

/** The build number for App Store Connect (IOS-015): the count of commits
 *  behind the build, which only grows, so every upload has a new one. */
function buildNumber(countText) {
  const count = Number.parseInt(String(countText).trim(), 10)
  if (!Number.isInteger(count) || count < 1 || String(count) !== String(countText).trim()) {
    throw new Error(`not a commit count: ${String(countText).trim()}`)
  }
  return String(count)
}

/** Export options for an App Store Connect build signed by the team. */
function exportOptionsPlist(teamId) {
  if (!/^[A-Z0-9]{10}$/.test(teamId)) throw new Error(`not a team id: ${teamId}`)
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '  <key>method</key>',
    '  <string>app-store-connect</string>',
    '  <key>destination</key>',
    '  <string>export</string>',
    '  <key>teamID</key>',
    `  <string>${teamId}</string>`,
    '  <key>signingStyle</key>',
    '  <string>automatic</string>',
    '  <key>uploadSymbols</key>',
    '  <true/>',
    '  <key>manageAppVersionAndBuildNumber</key>',
    '  <false/>',
    '</dict>',
    '</plist>',
    ''
  ].join('\n')
}

const SYSTEM_PATHS = ['/usr/bin', '/bin', '/usr/sbin', '/sbin']

/** PATH with the system's own tools first: Homebrew's rsync breaks the
 *  copy step of xcodebuild -exportArchive. */
function systemFirstPath(pathEnv = '') {
  const rest = pathEnv.split(delimiter).filter((entry) => entry && !SYSTEM_PATHS.includes(entry))
  return [...SYSTEM_PATHS, ...rest].join(delimiter)
}

/** xcrun's arguments to upload an ipa with an App Store Connect API key:
 *  the key's id and issuer only, as altool reads the key file itself. */
function uploadArgs(ipa, keyId, issuer) {
  if (!keyId || !issuer) throw new Error('uploading needs APPLE_API_KEY_ID and APPLE_API_ISSUER')
  return ['altool', '--upload-app', '-f', ipa, '-t', 'ios', '--apiKey', keyId, '--apiIssuer', issuer]
}

module.exports = {
  SMOKE_SIMULATOR,
  SIM_SIGNING,
  compareVersions,
  pickSmokeSimulator,
  findOnPath,
  copySharedJson,
  parseSmokeLine,
  parsePillShotsLine,
  projectSetting,
  buildNumber,
  exportOptionsPlist,
  systemFirstPath,
  uploadArgs
}
