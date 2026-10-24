import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { TapTrigger } from './trigger'

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

describe('TapTrigger', () => {
  it('cinco toques rápidos disparam; os quatro primeiros só apertam', () => {
    const t = new TapTrigger()
    expect([1, 2, 3, 4, 5].map(() => t.tap())).toEqual(['press', 'press', 'press', 'press', 'fire'])
  })

  it('quatro toques e uma pausa não disparam', () => {
    const t = new TapTrigger()
    for (let i = 0; i < 4; i++) t.tap()
    vi.advanceTimersByTime(1801)
    expect(t.taps).toBe(0)
    expect(t.tap()).toBe('press')
  })

  it('cada toque reinicia o prazo de 1,8 s', () => {
    const t = new TapTrigger()
    const out = []
    for (let i = 0; i < 5; i++) {
      out.push(t.tap())
      vi.advanceTimersByTime(1700)
    }
    expect(out.at(-1)).toBe('fire')
  })

  it('um intervalo maior que 1,8 s no meio zera a contagem', () => {
    const t = new TapTrigger()
    t.tap()
    t.tap()
    vi.advanceTimersByTime(2000)
    expect([t.tap(), t.tap(), t.tap(), t.tap()]).toEqual(['press', 'press', 'press', 'press'])
  })

  it('durante a cena os toques são ignorados, mesmo uma enxurrada', () => {
    const t = new TapTrigger()
    for (let i = 0; i < 5; i++) t.tap()
    t.hold(2500)
    const during = Array.from({ length: 50 }, () => t.tap())
    expect(new Set(during)).toEqual(new Set(['ignored']))
    vi.advanceTimersByTime(2500)
    expect(t.tap()).toBe('press')
  })

  it('depois de disparar, a contagem recomeça do zero', () => {
    const t = new TapTrigger()
    for (let i = 0; i < 5; i++) t.tap()
    expect(t.taps).toBe(0)
    expect([1, 2, 3, 4, 5].map(() => t.tap()).at(-1)).toBe('fire')
  })

  it('release libera o gatilho na hora', () => {
    const t = new TapTrigger()
    t.hold(10_000)
    t.release()
    expect(t.tap()).toBe('press')
  })
})
