// SPDX-License-Identifier: GPL-3.0-only
// Hybrid hotkey gestures. Audio ownership stays with the dictation callbacks;
// the injected clock keeps timing tests deterministic.
import type { DictationCallbacks, TriggerMachine } from './machines'

export const DOUBLE_TAP_MS = 300

/** Gesture recognition only. Never owns microphone resources. */
export class HybridMachine implements TriggerMachine {
  private state: 'idle' | 'held' | 'waiting' | 'locked' = 'idle'
  private held = false
  private pressedAt = 0
  private deadline = 0
  private timer: NodeJS.Timeout | null = null
  private generation = 0

  constructor(
    private readonly cb: DictationCallbacks,
    private readonly now: () => number = () => performance.now()
  ) {}

  /** Forget the gesture and cancel its timer. The caller owns session cleanup. */
  reset(): void {
    this.generation++
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    this.state = 'idle'
    this.held = false
  }

  private finish(): void {
    const held = this.held
    this.reset()
    // Stopping changes the overlay phase and may reset us synchronously.
    // Keep the physical latch so OS repeat cannot start a second session.
    try {
      this.cb.stop()
    } finally {
      this.held = held
    }
  }

  keyDown(): void {
    if (this.held) return // OS key repeat
    this.held = true
    if (this.state === 'waiting') {
      if (this.now() >= this.deadline) {
        this.finish()
        return
      }
      if (this.timer) clearTimeout(this.timer)
      this.generation++
      this.state = 'locked'
    } else if (this.state === 'locked') {
      this.finish()
    } else {
      this.pressedAt = this.now()
      if (this.cb.start() !== false) this.state = 'held'
    }
  }

  keyUp(): void {
    if (!this.held) return
    this.held = false
    if (this.state !== 'held') return
    if (this.now() - this.pressedAt >= DOUBLE_TAP_MS) {
      this.finish()
      return
    }
    this.state = 'waiting'
    this.deadline = this.now() + DOUBLE_TAP_MS
    const generation = ++this.generation
    this.timer = setTimeout(() => {
      if (generation === this.generation && this.state === 'waiting') this.finish()
    }, DOUBLE_TAP_MS)
  }

  isActive(): boolean {
    return this.state !== 'idle'
  }
}
