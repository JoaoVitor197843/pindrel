import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { toast } from './toast.svelte'

beforeEach(() => vi.useFakeTimers())
afterEach(() => {
  vi.runAllTimers()
  vi.useRealTimers()
})

describe('toast', () => {
  it('mostra a mensagem e some depois de 3 s', () => {
    toast.show('oi')
    expect(toast.message).toBe('oi')

    vi.advanceTimersByTime(2999)
    expect(toast.message).toBe('oi')
    vi.advanceTimersByTime(1)
    expect(toast.message).toBe('')
  })

  // repeated taps: the old timer must not erase the new message
  it('uma nova mensagem reinicia o tempo e a antiga não a apaga', () => {
    toast.show('primeira')
    vi.advanceTimersByTime(2000)
    toast.show('segunda')

    vi.advanceTimersByTime(2000) // 4 s since the first
    expect(toast.message).toBe('segunda')
    vi.advanceTimersByTime(1000)
    expect(toast.message).toBe('')
  })

  it('aguenta rajada de toques e texto estranho', () => {
    for (let i = 0; i < 1000; i++) toast.show(`msg ${i}`)
    expect(toast.message).toBe('msg 999')

    const huge = 'x'.repeat(1_000_000)
    toast.show(huge)
    expect(toast.message).toHaveLength(huge.length)
    toast.show('')
    expect(toast.message).toBe('')
  })
})
