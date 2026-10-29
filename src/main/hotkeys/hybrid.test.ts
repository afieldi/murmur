// SPDX-License-Identifier: GPL-3.0-only
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { HybridMachine } from './hybrid'

describe('HybridMachine', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  function setup() {
    const cb = { start: vi.fn<() => boolean | void>(), stop: vi.fn() }
    const machine = new HybridMachine(cb, () => Date.now())
    return { cb, machine }
  }

  it('starts immediately and stops a long hold on release', () => {
    const { machine: m, cb } = setup()
    m.keyDown()
    expect(cb.start).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(300)
    m.keyUp()
    expect(cb.stop).toHaveBeenCalledTimes(1)
    m.keyDown()
    expect(cb.start).toHaveBeenCalledTimes(2)
  })

  it('finishes a single short tap only after 300ms', () => {
    const { machine: m, cb } = setup()
    m.keyDown()
    m.keyUp()
    vi.advanceTimersByTime(299)
    expect(cb.stop).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    expect(cb.stop).toHaveBeenCalledTimes(1)
  })

  it('locks the same session, ignores repeats and release, stops once on next press', () => {
    const { machine: m, cb } = setup()
    m.keyDown()
    m.keyDown()
    m.keyUp()
    vi.advanceTimersByTime(100)
    m.keyDown()
    m.keyDown()
    m.keyUp()
    vi.advanceTimersByTime(1000)
    expect(cb.start).toHaveBeenCalledTimes(1)
    expect(cb.stop).not.toHaveBeenCalled()
    m.keyDown()
    m.keyDown()
    m.keyDown()
    m.keyUp()
    expect(cb.stop).toHaveBeenCalledTimes(1)
  })

  it('cancels pending timers and begins a fresh session', () => {
    const { machine: m, cb } = setup()
    m.keyDown()
    m.keyUp()
    m.reset()
    vi.advanceTimersByTime(500)
    expect(cb.stop).not.toHaveBeenCalled()
    m.keyDown()
    expect(cb.start).toHaveBeenCalledTimes(2)
  })

  it('latches a refused or throwing start until release', () => {
    const { machine: m, cb } = setup()
    cb.start.mockReturnValueOnce(false)
    m.keyDown()
    m.keyDown()
    expect(m.isActive()).toBe(false)
    m.keyUp()
    cb.start.mockImplementationOnce(() => {
      throw new Error('start')
    })
    expect(() => m.keyDown()).toThrow('start')
    m.keyDown()
    expect(cb.start).toHaveBeenCalledTimes(2)
    m.keyUp()
    m.keyDown()
    expect(m.isActive()).toBe(true)
  })

  it('clears state even if stopping throws', () => {
    const { machine: m, cb } = setup()
    cb.stop.mockImplementationOnce(() => {
      throw new Error('stop')
    })
    m.keyDown()
    vi.advanceTimersByTime(500)
    expect(() => m.keyUp()).toThrow('stop')
    expect(m.isActive()).toBe(false)
    m.keyDown()
    expect(cb.start).toHaveBeenCalledTimes(2)
  })

  it('uses the deadline even when timer delivery is late', () => {
    let now = 0
    const cb = { start: vi.fn(), stop: vi.fn() }
    const m = new HybridMachine(cb, () => now)
    m.keyDown()
    m.keyUp()
    now = 300
    m.keyDown()
    m.keyUp()
    vi.runAllTimers()
    expect(cb.stop).toHaveBeenCalledTimes(1)
  })
})
