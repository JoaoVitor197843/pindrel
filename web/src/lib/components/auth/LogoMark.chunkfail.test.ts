import { cleanup, fireEvent, render } from '@testing-library/svelte'
import { afterEach, describe, expect, it, vi } from 'vitest'
import LogoMark from './LogoMark.svelte'

vi.mock('../../logo/play', () => {
  throw new Error('chunk unreachable')
})
afterEach(cleanup)

describe('LogoMark sem conseguir baixar a cena', () => {
  it('é só enfeite: nenhum erro escapa, nenhum palco aparece e os toques voltam a contar', async () => {
    const unhandled = vi.fn()
    process.on('unhandledRejection', unhandled)
    const { getByTestId } = render(LogoMark)
    const logo = getByTestId('logo-mark')
    for (let i = 0; i < 12; i++) await fireEvent.click(logo)
    await vi.dynamicImportSettled()
    await new Promise((r) => setTimeout(r, 10))
    expect([...document.body.children].filter((e) => (e as HTMLElement).style.zIndex === '60')).toHaveLength(0)
    expect(logo.style.visibility).toBe('')
    expect(unhandled).not.toHaveBeenCalled()
    process.off('unhandledRejection', unhandled)
  })
})
