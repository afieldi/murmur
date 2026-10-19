// SPDX-License-Identifier: GPL-3.0-only
// Live probe for apply corrections (US-105): how often the real cleanup
// model fixes a spoken slip-up, and keeps cue words that are real
// content, through the exact prompt and validation the app ships.
// Skipped unless a key is set, so CI and plain test runs never call out.
//
//   MURMUR_PROBE_KEY=... npx vitest run src/main/formatter/corrections.probe.test.ts
//
// Optional: MURMUR_PROBE_BASE_URL (default Groq), MURMUR_PROBE_MODEL
// (default openai/gpt-oss-120b), MURMUR_PROBE_RUNS (default 5),
// MURMUR_PROBE_SMART_LISTS=1, and MURMUR_PROBE_ROUTE to pin an
// OpenRouter provider (Groq) so the numbers match the app's default.
import { describe, expect, it } from 'vitest'
import { polishTranscript } from './llm'

const KEY = process.env.MURMUR_PROBE_KEY ?? ''
const BASE_URL = process.env.MURMUR_PROBE_BASE_URL ?? 'https://api.groq.com/openai/v1'
const MODEL = process.env.MURMUR_PROBE_MODEL ?? 'openai/gpt-oss-120b'
const RUNS = Number(process.env.MURMUR_PROBE_RUNS ?? 5)
const SMART_LISTS = process.env.MURMUR_PROBE_SMART_LISTS === '1'
const ROUTE = process.env.MURMUR_PROBE_ROUTE ?? ''

interface ProbeCase {
  text: string
  /** Phrases the typed text must hold, compared without punctuation. */
  keep: string[]
  /** Phrases it must not hold; empty marks a trap sentence. */
  drop: string[]
}

const CASES: ProbeCase[] = [
  {
    text: 'Send the invoice to Mark on Tuesday. Oh wait, actually what I mean is Wednesday.',
    keep: ['wednesday'],
    drop: ['tuesday', 'wait', 'i mean']
  },
  {
    text: "Let's meet at the coffee shop on Main Street, no wait, the one on Elm Street, at three.",
    keep: ['elm street'],
    drop: ['main street', 'wait']
  },
  {
    text: 'The budget is fifteen thousand, sorry, fifty thousand dollars for the quarter.',
    keep: ['fifty thousand'],
    drop: ['fifteen', 'sorry']
  },
  {
    text: 'I need you to update the pricing page. Actually, I mean the checkout page, not the pricing page.',
    // "the checkout page, not the pricing page" is the speaker's own
    // contrast and a fine result; only the wrong instruction must go.
    keep: ['update the checkout page'],
    drop: ['update the pricing page', 'i mean']
  },
  { text: 'Tell Sarah the meeting moved to room four. I mean room five.', keep: ['room five'], drop: ['room four', 'i mean'] },
  {
    text: 'Can you rename the function to get user, I mean fetch user, and update the tests.',
    keep: ['fetch user', 'update the tests'],
    drop: ['get user', 'i mean']
  },
  {
    text: 'The color should be teal for the buttons. Oh wait, actually what I mean is orange instead of teal.',
    keep: ['orange', 'buttons'],
    drop: ['teal', 'wait']
  },
  {
    text: 'Book the flight for the twelfth, no, the fourteenth, and get a window seat.',
    keep: ['fourteenth', 'window seat'],
    drop: ['twelfth']
  },
  {
    text: 'I think we should, we should probably ship the update on Friday afternoon.',
    keep: ['we should probably ship'],
    drop: ['we should we should']
  },
  {
    text: 'We should use Postgres. Wait, no, let me rephrase that. We should use SQLite for the local cache.',
    keep: ['sqlite'],
    drop: ['postgres', 'rephrase']
  },
  // Added after the prompt was tuned, as a held-out check (2026-10-17).
  // The pizza case failed half the time and earned the prompt its make
  // that example, so it is tuned now; the table case below holds out.
  {
    text: 'Book a table for four, make that six, at seven thirty on Saturday.',
    keep: ['six', 'seven thirty on saturday'],
    drop: ['four', 'make that']
  },
  {
    text: 'Order two large pizzas, make that three, and a salad for the table.',
    keep: ['three', 'pizzas', 'salad for the table'],
    drop: ['two', 'make that']
  },
  {
    text: 'Set the deadline to the end of March. Sorry, the end of April, because legal needs more time.',
    keep: ['end of april', 'legal needs more time'],
    drop: ['march', 'sorry']
  },
  {
    text: 'Email Jordan, no, text Jordan the address before noon.',
    keep: ['text jordan the address before noon'],
    drop: ['email']
  },
  {
    text: 'Sorry I missed your call, I was in a meeting all afternoon.',
    keep: ['sorry i missed your call', 'meeting all afternoon'],
    drop: []
  },
  { text: 'No problem, I can cover the Thursday shift for you.', keep: ['no problem', 'thursday shift'], drop: [] },
  {
    text: "I'd rather we wait until the numbers come in next week.",
    keep: ['id rather we wait', 'next week'],
    drop: []
  },
  { text: 'I mean, it works, but I think we can make it faster.', keep: ['i mean', 'faster'], drop: [] },
  { text: 'Actually, the tests are passing now, so we can merge.', keep: ['actually', 'merge'], drop: [] },
  { text: 'Wait for the build to finish before you push the tag.', keep: ['wait for the build'], drop: [] },
  {
    text: 'Instead of Redis we chose Postgres because it was simpler to run.',
    keep: ['instead of redis', 'postgres'],
    drop: []
  },
  {
    text: "I talked to Sarah about the launch and she agreed with the plan. Actually, the pricing still needs work, so let's revisit it Monday.",
    keep: ['agreed with the plan', 'actually', 'pricing still needs work'],
    drop: []
  },
  {
    text: "No, I don't think that's right, the numbers look off to me.",
    keep: ['no i dont think', 'numbers look off'],
    drop: []
  }
]

function plain(value: string): string {
  return value
    .toLowerCase()
    .replace(/[‘’']/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

function passes(probe: ProbeCase, typed: string): boolean {
  const text = ` ${plain(typed)} `
  return (
    probe.keep.every((phrase) => text.includes(` ${phrase} `)) &&
    probe.drop.every((phrase) => !text.includes(` ${phrase} `))
  )
}

// Pins an OpenRouter provider so a probe through OpenRouter runs on
// the same host the app's default does.
const fetchImpl: typeof fetch = ROUTE
  ? (url, init) => {
      const body = JSON.parse(String(init?.body)) as Record<string, unknown>
      body.provider = { order: [ROUTE], allow_fallbacks: false }
      return fetch(url, { ...init, body: JSON.stringify(body) })
    }
  : fetch

async function measure(corrections: boolean): Promise<{ fixed: number; kept: number; misses: string[] }> {
  const jobs = CASES.flatMap((probe) => Array.from({ length: RUNS }, () => probe))
  const results: Array<{ probe: ProbeCase; typed: string }> = []
  let next = 0
  const worker = async (): Promise<void> => {
    while (next < jobs.length) {
      const probe = jobs[next++]
      const polished = await polishTranscript(
        probe.text,
        { baseUrl: BASE_URL, model: MODEL, apiKey: KEY },
        { fetchImpl, timeoutMs: 30_000, smartLists: SMART_LISTS, corrections }
      )
      // A fallback types the formatted text unchanged, so grade that.
      results.push({ probe, typed: polished ?? probe.text })
    }
  }
  await Promise.all(Array.from({ length: 6 }, worker))
  const misses = results.filter((r) => !passes(r.probe, r.typed)).map((r) => `${r.probe.text}\n    typed: ${r.typed}`)
  const fixed = results.filter((r) => r.probe.drop.length > 0 && passes(r.probe, r.typed)).length
  const kept = results.filter((r) => r.probe.drop.length === 0 && passes(r.probe, r.typed)).length
  return { fixed, kept, misses }
}

describe.skipIf(KEY === '')('apply corrections live probe', () => {
  it('fixes spoken corrections and keeps real cue words', { timeout: 600_000 }, async () => {
    const corrections = CASES.filter((c) => c.drop.length > 0).length * RUNS
    const traps = CASES.filter((c) => c.drop.length === 0).length * RUNS
    const off = await measure(false)
    const on = await measure(true)
    console.log(
      [
        `model ${MODEL} at ${BASE_URL}${ROUTE ? ` via ${ROUTE}` : ''}, smart lists ${SMART_LISTS ? 'on' : 'off'}, ${RUNS} runs`,
        `off: fixed ${off.fixed}/${corrections}, kept ${off.kept}/${traps}`,
        `on:  fixed ${on.fixed}/${corrections}, kept ${on.kept}/${traps}`,
        ...on.misses.map((miss) => `  on miss: ${miss}`)
      ].join('\n')
    )
    expect(on.fixed / corrections).toBeGreaterThanOrEqual(0.8)
    expect(on.kept).toBe(traps)
  })
})
