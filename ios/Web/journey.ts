// SPDX-License-Identifier: GPL-3.0-only
// The iPhone Journey's painter page (ios/prd.json IOS-018): desktop's own
// brush engine and Journey painter (src/renderer/brush.ts and
// settings/journeyPaint.ts), bundled into the app at build time and run in
// a web view that loads nothing else. murmur asks it for pictures (the
// belt, the road, the gates, the stamps) and for the promotion ceremony;
// every word stays a native view beside or over the painting.
import cosmetics from '../../shared/cosmetics.json'
import ranks from '../../shared/ranks.json'
import { animateScene, paintScene, type Surface } from '../../src/renderer/brush'
import {
  ROAD,
  beltOnInk,
  ceremonyScene,
  journeyColors,
  paintBelt,
  paintRoad,
  paintStamp,
  paintTallies,
  paintWordsGate,
  roadGroups,
  roadPlace,
  sinceRank
} from '../../src/renderer/settings/journeyPaint'
import type { ProgressReport, RankSpec } from '../../src/shared/ranks'

const LADDER = (ranks as { ranks: RankSpec[] }).ranks
const BELT_HEX = (cosmetics as { beltColors: Record<string, string> }).beltColors

/** Where practice stands, as murmur's own math found it. */
export interface Standing {
  rank: string
  next: string | null
  words: number
  days: number
}

export type PictureRequest =
  | { kind: 'belt'; width: number; height: number; scale: number; belt: string; stripes: number; drop?: number }
  | { kind: 'road'; scale: number; standing: Standing }
  | { kind: 'words'; width: number; height: number; scale: number; standing: Standing }
  | { kind: 'tallies'; width: number; height: number; scale: number; standing: Standing }
  | { kind: 'stamp'; size: number; scale: number; id: string; got: boolean; seed: number }

export interface Picture {
  png: string
  /** The road's group names and your place, for native text over it. */
  groups?: { name: string; x: number }[]
  you?: number
}

/** A token's value, as desktop's Journey reads its fonts. */
function token(name: string, fallback: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback
}

function rank(id: string | null): RankSpec | null {
  return id === null ? null : (LADDER.find((r) => r.id === id) ?? null)
}

/** Just enough of a progress report for the road: practice is the rank,
 *  as on the iPhone, where there is no founder yet. */
export function progressFor(standing: Standing): ProgressReport {
  const at = rank(standing.rank) ?? LADDER[0]
  const next = rank(standing.next)
  const practice = { rank: at, index: LADDER.indexOf(at), next, words: null, activeDays: null }
  return {
    ...practice,
    totals: { words: standing.words, activeDays: standing.days },
    promotions: [],
    founder: false,
    practice,
    level: 1
  }
}

function canvas(width: number, height: number, scale: number): { el: HTMLCanvasElement; ctx: CanvasRenderingContext2D } {
  const el = document.createElement('canvas')
  el.width = Math.round(width * scale)
  el.height = Math.round(height * scale)
  const ctx = el.getContext('2d')
  if (!ctx) throw new Error('no 2d context')
  ctx.setTransform(scale, 0, 0, scale, 0, 0)
  return { el, ctx }
}

/** One picture, as a PNG data URL. */
export function picture(req: PictureRequest): Picture {
  const colors = journeyColors(BELT_HEX)
  switch (req.kind) {
    case 'belt': {
      const { el, ctx } = canvas(req.width, req.height, req.scale)
      const newest = Math.min(req.stripes, req.belt === 'black' ? 6 : 4) - 1
      paintBelt(ctx, req.width, req.height, req.belt, req.stripes, colors, 1, req.drop === undefined ? undefined : { i: newest, k: req.drop })
      return { png: el.toDataURL('image/png') }
    }
    case 'road': {
      const { el, ctx } = canvas(ROAD.W, ROAD.H, req.scale)
      const place = roadPlace(progressFor(req.standing), LADDER)
      paintRoad(ctx, place.road, place.roadIndex, place.you, place.you, '', colors, token('--font-mono', 'monospace'), false)
      return { png: el.toDataURL('image/png'), groups: roadGroups(place.road), you: place.you }
    }
    case 'words': {
      const { el, ctx } = canvas(req.width, req.height, req.scale)
      const at = rank(req.standing.rank)
      const next = rank(req.standing.next)
      const pct = next ? sinceRank(req.standing.words, at?.words ?? 0, next.words ?? 0) : 1
      paintWordsGate(ctx, req.width, req.height, pct, beltOnInk(at?.belt ?? 'none', colors), colors)
      return { png: el.toDataURL('image/png') }
    }
    case 'tallies': {
      const { el, ctx } = canvas(req.width, req.height, req.scale)
      const at = rank(req.standing.rank)
      const next = rank(req.standing.next)
      const start = at?.activeDays ?? 0
      const need = (next?.activeDays ?? start) - start
      const have = req.standing.days - start
      paintTallies(ctx, req.width, req.height, need, have, beltOnInk(at?.belt ?? 'none', colors), colors, 1, have)
      return { png: el.toDataURL('image/png') }
    }
    case 'stamp': {
      const { el, ctx } = canvas(req.size, req.size, req.scale)
      paintStamp(ctx, req.size, req.id, req.got, req.seed, colors, token('--font-body', 'sans-serif'))
      return { png: el.toDataURL('image/png') }
    }
  }
}

function surface(id: string, width: number, height: number): Surface | null {
  const el = document.getElementById(id)
  if (!(el instanceof HTMLCanvasElement)) return null
  const dpr = Math.min(3, window.devicePixelRatio || 1)
  el.width = Math.round(width * dpr)
  el.height = Math.round(height * dpr)
  el.style.width = `${width}px`
  el.style.height = `${height}px`
  const ctx = el.getContext('2d')
  if (!ctx) return null
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  return { canvas: el, ctx, dpr }
}

/** The ceremony on the page's own canvases: animated, or the finished
 *  painting with Reduce Motion. */
export function ceremony(req: { rank: string; width: number; height: number; reduced: boolean }): boolean {
  const at = rank(req.rank)
  const { width, height } = req
  const base = surface('base', width, height)
  const fx = surface('fx', width, height)
  if (!at || !base || !fx) return false
  const items = ceremonyScene(at, width, height, journeyColors(BELT_HEX))
  if (req.reduced) paintScene(base.ctx, items)
  else animateScene(base, fx, items)
  return true
}

declare global {
  interface Window {
    murmurJourney?: { picture: typeof picture; ceremony: typeof ceremony }
    webkit?: { messageHandlers?: { journey?: { postMessage: (message: unknown) => void } } }
  }
}

if (typeof window !== 'undefined') {
  window.murmurJourney = { picture, ceremony }
  window.webkit?.messageHandlers?.journey?.postMessage({ type: 'ready' })
}
