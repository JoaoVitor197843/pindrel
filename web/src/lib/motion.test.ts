import { afterEach, describe, expect, it, vi } from 'vitest'
import { ms } from './motion'

afterEach(() => {
  delete (Element.prototype as { animate?: unknown }).animate
  vi.restoreAllMocks()
})

describe('ms', () => {
  it('sem Web Animations (jsdom) a duração é zero', () => {
    expect(ms(300)).toBe(0)
  })

  it('com animações e sem "reduzir movimento" mantém a duração', () => {
    ;(Element.prototype as { animate?: unknown }).animate = () => ({})
    expect(ms(300)).toBe(300)
  })

  it('com "reduzir movimento" ligado vira zero', () => {
    ;(Element.prototype as { animate?: unknown }).animate = () => ({})
    vi.spyOn(window, 'matchMedia').mockReturnValue({ matches: true } as MediaQueryList)
    expect(ms(300)).toBe(0)
  })
})
