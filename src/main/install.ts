// SPDX-License-Identifier: GPL-3.0-only
// The install date (US-107), recorded once: a fresh install takes its
// first launch, and an install from before this field existed takes its
// earliest dictation on record (or this launch when there is none). The
// Home offer counts calendar days from it.
import { resolveInstallDate } from '../shared/proMark'
import { readHistory } from './history'
import { getSettings, updateSettings } from './settings'
import { registerSmokeCheck } from './smoke'

export function recordInstallDate(now = Date.now()): number {
  const current = getSettings().installedAt
  if (current > 0) return current
  let earliest: number | null = null
  for (const event of readHistory()) {
    if (typeof event.at === 'number' && (earliest === null || event.at < earliest)) earliest = event.at
  }
  const at = resolveInstallDate(current, earliest, now)
  updateSettings({ installedAt: at })
  return at
}

export function initInstallDate(): void {
  try {
    recordInstallDate()
  } catch (error) {
    // The date only times a quiet offer; it must never block launch.
    console.error('[murmur] could not record the install date:', error)
  }
  registerSmokeCheck('installDate', () => getSettings().installedAt > 0)
}
