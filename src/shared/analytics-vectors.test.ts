// SPDX-License-Identifier: GPL-3.0-only
// Runs shared/analytics-vectors.json through the analytics. MurmurCore runs
// the same file, so the iPhone's share card paints from the month desktop's
// would (ios/prd.json IOS-021).
import { describe, expect, it } from 'vitest'
import vectors from '../../shared/analytics-vectors.json'
import { dailyTotals } from './analytics'
import type { SessionEvent } from './history'

interface Take {
  day: string
  words: number
}

/** Local noon on a day, as desktop's clock would read it that day. */
const noonOf = (day: string): number => {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(y, m - 1, d, 12).getTime()
}

const event = (t: Take): SessionEvent => ({ at: noonOf(t.day), durationMs: 1000, rawText: '', finalText: '', words: t.words, wpm: 0, day: t.day, hour: 12 })

describe('shared/analytics-vectors.json', () => {
  for (const c of vectors.dailyTotals) {
    it(`daily totals: ${c.name}`, () => {
      expect(dailyTotals(c.takes.map(event), c.count, () => noonOf(c.today))).toEqual(c.expect)
    })
  }
})
