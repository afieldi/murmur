// SPDX-License-Identifier: GPL-3.0-only
// Each iPhone target's privacy manifest declares every required reason API
// its code uses (ios/prd.json IOS-001 conventions; IOS-009 review): this
// fails before App Store Connect would.
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { categoriesUsed, declared } from './privacy-manifest'

const ios = join(__dirname, '..', '..', 'ios')

function swiftFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) return swiftFiles(path)
    return entry.name.endsWith('.swift') ? [path] : []
  })
}

/** The categories used anywhere in these folders, MurmurCore included. */
function used(...folders) {
  const files = [...folders, 'MurmurCore/Sources'].flatMap((folder) => swiftFiles(join(ios, folder)))
  return [...new Set(files.flatMap((file) => categoriesUsed(readFileSync(file, 'utf8'))))].sort()
}

describe('the privacy manifests declare what the code uses', () => {
  it('finds required reason APIs in code, not in comments', () => {
    expect(categoriesUsed('let defaults = UserDefaults.standard')).toEqual(['NSPrivacyAccessedAPICategoryUserDefaults'])
    expect(categoriesUsed('let up = ProcessInfo.processInfo.systemUptime')).toEqual(['NSPrivacyAccessedAPICategorySystemBootTime'])
    expect(categoriesUsed('let keys: [URLResourceKey] = [.contentModificationDateKey]')).toEqual(['NSPrivacyAccessedAPICategoryFileTimestamp'])
    expect(categoriesUsed('// UserDefaults is for settings\nlet x = 1')).toEqual([])
  })

  it('reads the declared categories and reasons', () => {
    const manifest = '<key>NSPrivacyAccessedAPITypes</key><array><dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array></dict></array>'
    expect(declared(manifest)).toEqual({ NSPrivacyAccessedAPICategoryUserDefaults: ['CA92.1'] })
    expect(declared('<key>NSPrivacyAccessedAPITypes</key><array/>')).toEqual({})
  })

  for (const [target, folders] of [
    ['App', ['App', 'Shared']],
    ['Keyboard', ['Keyboard', 'Shared']]
  ]) {
    it(`declares every category the ${target} target uses, for its own defaults only`, () => {
      const manifest = declared(readFileSync(join(ios, target, 'PrivacyInfo.xcprivacy'), 'utf8'))
      expect(Object.keys(manifest).sort()).toEqual(used(...folders))
      // Each target reads and writes only its own defaults (CA92.1); the
      // app group holds files, never shared defaults.
      expect(manifest.NSPrivacyAccessedAPICategoryUserDefaults).toEqual(['CA92.1'])
    })
  }
})
