import { afterEach, describe, expect, it, vi } from 'vitest'
import { canCopy, canServiceWorker, canVault } from './capabilities'

const realNavigator = globalThis.navigator
const restoreNavigator = () => vi.stubGlobal('navigator', realNavigator)
const setSecure = (v: boolean | undefined) => Object.defineProperty(window, 'isSecureContext', { value: v, configurable: true })
afterEach(() => {
  restoreNavigator()
  setSecure(undefined)
})

describe('o que a página pode usar depende de como foi aberta', () => {
  it('sem dizer que é insegura (testes, localhost), tudo vale', () => {
    setSecure(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText: () => {} }, serviceWorker: {} })
    expect(canVault()).toBe(true)
    expect(canCopy()).toBe(true)
    expect(canServiceWorker()).toBe(true)
  })

  it('em HTTP puro (isSecureContext falso) nada disso existe', () => {
    setSecure(false)
    vi.stubGlobal('navigator', { clipboard: { writeText: () => {} }, serviceWorker: {} })
    expect(canVault()).toBe(false)
    expect(canCopy()).toBe(false)
    expect(canServiceWorker()).toBe(false)
  })

  it('numa página segura, sem a API o recurso também fica de fora', () => {
    setSecure(true)
    vi.stubGlobal('navigator', {})
    expect(canCopy()).toBe(false)
    expect(canServiceWorker()).toBe(false)
  })
})
