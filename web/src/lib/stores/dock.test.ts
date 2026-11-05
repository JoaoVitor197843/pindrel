import { describe, expect, it, vi } from 'vitest'
import { DOCK_PANEL_WIDTH, Dock, RAIL_WIDTH, dockScale } from './dock.svelte'
import { stubLocalStorage } from '../../test/storage'

describe('dockScale', () => {
  it('é 1 no limite de tela larga e abaixo dele', () => {
    for (const w of [0, 320, 390, 1024, 1339, 1340]) expect(dockScale(w), String(w)).toBe(1)
  })

  it('cresce com a tela e para em 1,7', () => {
    expect(dockScale(1500)).toBeGreaterThan(1)
    expect(dockScale(1864)).toBeGreaterThan(1.4)
    expect(dockScale(1864)).toBeLessThan(1.7)
    expect(dockScale(2560)).toBe(1.7)
    expect(dockScale(7680)).toBe(1.7)
    let last = 1
    for (let w = 1340; w <= 2800; w += 60) {
      const s = dockScale(w)
      expect(s).toBeGreaterThanOrEqual(last)
      last = s
    }
  })

  it('o painel nunca encosta na coluna da página, em nenhuma largura', () => {
    for (let w = 1340; w <= 5000; w += 20) {
      const dock = (RAIL_WIDTH + DOCK_PANEL_WIDTH) * dockScale(w)
      const room = (w - 768) / 2
      // at the breakpoint the panel may touch the margin of the page column (its text starts 80px further in)
      expect(dock, String(w)).toBeLessThanOrEqual(Math.max(room * 0.8, RAIL_WIDTH + DOCK_PANEL_WIDTH) + 0.5)
    }
  })

  it('entradas estranhas não quebram', () => {
    for (const w of [NaN, -5, Infinity, undefined as unknown as number]) expect(Number.isFinite(dockScale(w)), String(w)).toBe(true)
  })
})

describe('Dock', () => {
  it('largo: aberto de início, e a escolha fica lembrada', () => {
    const data = stubLocalStorage()
    const d = new Dock('k')
    expect(d.isOpen(true)).toBe(true)
    d.toggle(true)
    expect(d.isOpen(true)).toBe(false)
    expect(data.get('k')).toBe('0')
    expect(new Dock('k').isOpen(true)).toBe(false)
    d.toggle(true)
    expect(data.get('k')).toBe('1')
  })

  it('estreito: gaveta que começa fechada, mesmo que a escolha larga seja "aberto"', () => {
    stubLocalStorage().set('k', '1')
    const d = new Dock('k')
    expect(d.isOpen(false)).toBe(false)
    d.toggle(false)
    expect(d.isOpen(false)).toBe(true)
    d.closeDrawer()
    expect(d.isOpen(false)).toBe(false)
    expect(d.isOpen(true)).toBe(true)
  })

  it('sem armazenamento, ou com lixo guardado, ainda funciona', () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new Error('bloqueado')
      },
      setItem: () => {
        throw new Error('bloqueado')
      },
    })
    const d = new Dock('k')
    expect(d.isOpen(true)).toBe(true)
    d.toggle(true)
    expect(d.isOpen(true)).toBe(false)
    vi.unstubAllGlobals()
    stubLocalStorage().set('k', 'lixo')
    expect(new Dock('k').choice).toBeNull()
  })
})
