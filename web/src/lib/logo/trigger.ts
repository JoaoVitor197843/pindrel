export const TAPS_TO_FIRE = 5
export const TAP_WINDOW_MS = 1800

export type TapResult = 'press' | 'fire' | 'ignored'

/**
 * Counts taps on the logo: five in a row, each at most `windowMs` after the previous one. The first four
 * only press the logo; the fifth fires. While a scene plays (`hold`) every tap is ignored.
 */
export class TapTrigger {
  private count = 0
  private timer: ReturnType<typeof setTimeout> | undefined
  private busy = false

  constructor(private readonly windowMs = TAP_WINDOW_MS) {}

  get taps(): number {
    return this.count
  }

  tap(): TapResult {
    if (this.busy) return 'ignored'
    clearTimeout(this.timer)
    this.count++
    if (this.count >= TAPS_TO_FIRE) {
      this.count = 0
      return 'fire'
    }
    this.timer = setTimeout(() => (this.count = 0), this.windowMs)
    return 'press'
  }

  /** Ignores taps for `ms` (the length of the scene). */
  hold(ms: number) {
    this.busy = true
    this.count = 0
    clearTimeout(this.timer)
    this.timer = setTimeout(() => (this.busy = false), ms)
  }

  /** Cancels the hold and any pending count (scene cut short, component gone). */
  release() {
    this.busy = false
    this.count = 0
    clearTimeout(this.timer)
  }
}
