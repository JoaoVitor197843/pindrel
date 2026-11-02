import { cleanup, fireEvent, render } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { LOGO_THEMES } from '../../logo/season'
import LogoMark from './LogoMark.svelte'

// jsdom has no Web Animations: a stub that records the calls and never finishes by itself.
let animate: ReturnType<typeof vi.fn>

beforeEach(() => {
  vi.useFakeTimers()
  animate = vi.fn(() => ({ onfinish: null, cancel() {} }))
  Element.prototype.animate = animate as unknown as typeof Element.prototype.animate
  Element.prototype.getAnimations = () => []
})

afterEach(() => {
  cleanup()
  vi.useRealTimers()
  vi.restoreAllMocks()
  history.replaceState(null, '', '/')
  // @ts-expect-error restoring jsdom's lack of the API
  delete Element.prototype.animate
  // @ts-expect-error same
  delete Element.prototype.getAnimations
})

const stages = () => [...document.body.children].filter((e) => (e as HTMLElement).style.zIndex === '60')

async function taps(button: HTMLElement, n: number) {
  for (let i = 0; i < n; i++) await fireEvent.click(button)
}

describe('LogoMark', () => {
  it('é um botão com o P', () => {
    const { getByRole } = render(LogoMark)
    expect(getByRole('button', { name: 'Logo do Pindrel' }).textContent?.trim()).toBe('P')
  })

  it('cinco toques rápidos mostram a cena e depois tudo some', async () => {
    const { getByRole } = render(LogoMark)
    const logo = getByRole('button')
    await taps(logo, 4)
    expect(stages()).toHaveLength(0)
    await taps(logo, 1)
    expect(stages()).toHaveLength(1)
    expect(logo.style.visibility).toBe('hidden')
    await vi.advanceTimersByTimeAsync(5000)
    expect(stages()).toHaveLength(0)
    expect(logo.style.visibility).toBe('')
    expect(logo.textContent?.trim()).toBe('P')
  })

  it('quatro toques e uma pausa não disparam', async () => {
    const { getByRole } = render(LogoMark)
    const logo = getByRole('button')
    await taps(logo, 4)
    await vi.advanceTimersByTimeAsync(1900)
    await taps(logo, 1)
    expect(stages()).toHaveLength(0)
  })

  it('toques durante a cena são ignorados (uma enxurrada não empilha cenas)', async () => {
    const { getByRole } = render(LogoMark)
    const logo = getByRole('button')
    await taps(logo, 60)
    expect(stages()).toHaveLength(1)
    await vi.advanceTimersByTimeAsync(5000)
    expect(stages()).toHaveLength(0)
    await taps(logo, 5)
    expect(stages()).toHaveLength(1)
  })

  it('todos os temas rodam sem erro e limpam o palco', async () => {
    for (const theme of LOGO_THEMES) {
      const { getByRole, unmount } = render(LogoMark, { theme })
      await taps(getByRole('button'), 5)
      expect(stages(), theme).toHaveLength(1)
      await vi.advanceTimersByTimeAsync(6000)
      expect(stages(), theme).toHaveLength(0)
      unmount()
    }
  })

  it('com redução de movimento só pisca o logo, sem palco', async () => {
    vi.spyOn(window, 'matchMedia').mockImplementation((q) => ({ matches: /reduce/.test(q) }) as MediaQueryList)
    const { getByRole } = render(LogoMark)
    const logo = getByRole('button')
    animate.mockClear()
    await taps(logo, 5)
    expect(stages()).toHaveLength(0)
    expect(animate).toHaveBeenCalledTimes(1)
    expect(animate.mock.calls[0]![1]).toEqual({ duration: 400 })
  })

  it('sair da tela no meio da cena remove o palco', async () => {
    const { getByRole, unmount } = render(LogoMark)
    await taps(getByRole('button'), 5)
    expect(stages()).toHaveLength(1)
    unmount()
    expect(stages()).toHaveLength(0)
    await vi.advanceTimersByTimeAsync(6000)
  })

  it('ir para segundo plano cancela a cena', async () => {
    const { getByRole } = render(LogoMark)
    await taps(getByRole('button'), 5)
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
    document.dispatchEvent(new Event('visibilitychange'))
    expect(stages()).toHaveLength(0)
  })

  it('sem Web Animations não quebra nem cria palco', async () => {
    // @ts-expect-error simulating a browser without the API
    delete Element.prototype.animate
    const { getByRole } = render(LogoMark)
    await taps(getByRole('button'), 5)
    expect(stages()).toHaveLength(0)
  })
})
