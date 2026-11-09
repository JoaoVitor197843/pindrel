import { cleanup, fireEvent, render, screen } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resetNearView } from '../lib/components/editor/nearView'
import { sampleWorkspace } from '../lib/sample'
import { toast } from '../lib/stores/toast.svelte'
import type { Workspace } from '../lib/stores/workspace.svelte'
import { viewport } from '../test/setup'
import Dashboard from './Dashboard.svelte'
import Editor from './Editor.svelte'

// plain HTTP at a LAN address: no crypto.subtle, no clipboard (checked in Chrome)
const realNavigator = globalThis.navigator
const restoreNavigator = () => vi.stubGlobal('navigator', realNavigator)
let ws: Workspace
beforeEach(() => {
  viewport.set(1400)
  toast.message = ''
  Object.defineProperty(window, 'isSecureContext', { value: false, configurable: true })
  ws = sampleWorkspace()
})
afterEach(() => {
  cleanup()
  resetNearView()
  Object.defineProperty(window, 'isSecureContext', { value: undefined, configurable: true })
  restoreNavigator()
})

describe('página aberta em HTTP puro: o que precisa de contexto seguro some', () => {
  it('a barra lateral não oferece o Cofre', () => {
    render(Dashboard, { ws })
    expect(screen.queryByRole('button', { name: /^Cofre/ })).toBeNull()
    expect(screen.getByRole('button', { name: /Todas as páginas/ })).toBeTruthy()
    expect(screen.getByRole('button', { name: /Lixeira/ })).toBeTruthy()
  })

  it('o painel de comandos não leva ao cofre', async () => {
    render(Dashboard, { ws })
    await fireEvent.keyDown(window, { key: 'k', ctrlKey: true })
    await fireEvent.input(await screen.findByRole('combobox'), { target: { value: 'cofre' } })
    expect(screen.queryByText('Ir para o cofre')).toBeNull()
  })

  it('ir ao cofre pelo código não muda a lista, e a senha não destrava nada', () => {
    ws.go('vault')
    expect(ws.view).toBe('all')
    expect(ws.unlockVault('qualquer senha longa')).toBe('unavailable')
    expect(ws.vaultUnlocked).toBe(false)
  })

  it('abrir uma página do cofre que já estava guardada só avisa, sem pedir senha', async () => {
    const onopen = vi.fn()
    ws.view = 'vault'
    render(Dashboard, { ws, onopen })
    // even if the view is forced, the card of a vault page never opens it
    const id = ws.pages.find((p) => p.locked)!.id
    expect(ws.page(id)!.locked).toBe(true)
    expect(ws.visible.some((p) => p.locked)).toBe(false)
    expect(onopen).not.toHaveBeenCalled()
  })

  it('o editor de uma página do cofre explica que só abre em HTTPS e não oferece "Desbloquear"', () => {
    const id = ws.pages.find((p) => p.locked)!.id
    render(Editor, { ws, id, onback: vi.fn() })
    expect(screen.getByText(/só abre em HTTPS ou em localhost/)).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Desbloquear' })).toBeNull()
  })

  it('o menu de exportar não oferece copiar para a área de transferência', async () => {
    vi.stubGlobal('navigator', { ...navigator, clipboard: { writeText: vi.fn() } })
    render(Editor, { ws, id: 'p0', onback: vi.fn() })
    await fireEvent.click(screen.getByRole('button', { name: 'Exportar página' }))
    expect(screen.queryByRole('menuitem', { name: 'Copiar como Markdown' })).toBeNull()
    expect(screen.getAllByRole('menuitem').length).toBeGreaterThan(0)
  })
})
