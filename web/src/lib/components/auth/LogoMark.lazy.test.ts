import { cleanup, fireEvent, render } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import LogoMark from './LogoMark.svelte'

// The scene chunk arrives only when the test lets it (a slow connection), and in the failure case it never does.
const chunk = vi.hoisted(() => ({ release: () => {}, gate: Promise.resolve(), fail: false }))
vi.mock('../../logo/play', async (original) => {
  await chunk.gate
  if (chunk.fail) throw new Error('chunk unreachable')
  return original()
})

beforeEach(() => {
  vi.resetModules() // each test meets the chunk as if for the first time
  chunk.fail = false
  chunk.gate = new Promise<void>((r) => (chunk.release = r))
  Element.prototype.animate = vi.fn(() => ({ onfinish: null, cancel() {} })) as unknown as typeof Element.prototype.animate
  Element.prototype.getAnimations = () => []
})
afterEach(() => {
  cleanup()
  // @ts-expect-error restoring jsdom's lack of the API
  delete Element.prototype.animate
  // @ts-expect-error same
  delete Element.prototype.getAnimations
})

const stages = () => [...document.body.children].filter((e) => (e as HTMLElement).style.zIndex === '60')
const tap = async (el: HTMLElement, n: number) => {
  for (let i = 0; i < n; i++) await fireEvent.click(el)
}

describe('LogoMark com a cena carregada sob demanda', () => {
  it('numa conexão lenta, dezenas de toques enquanto o pedaço chega não empilham cenas', async () => {
    const { getByTestId } = render(LogoMark)
    await tap(getByTestId('logo-mark'), 60)
    expect(stages()).toHaveLength(0)
    chunk.release()
    await vi.waitFor(() => expect(stages()).toHaveLength(1))
  })

  it('sair da tela antes de o pedaço chegar não cria palco depois', async () => {
    const { getByTestId, unmount } = render(LogoMark)
    await tap(getByTestId('logo-mark'), 5)
    unmount()
    chunk.release()
    await vi.dynamicImportSettled()
    await Promise.resolve()
    expect(stages()).toHaveLength(0)
  })
})
