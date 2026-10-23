import { fireEvent, render, screen } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { selection, servers } from '../../stores/servers.svelte'
import ServerSelector from './ServerSelector.svelte'

const button = () => screen.getByRole('button', { name: 'Selecionar servidor' })

beforeEach(() => selection.select(servers[0]))

describe('ServerSelector', () => {
  it('o botão expõe aria-expanded e abre/fecha com toques repetidos', async () => {
    render(ServerSelector)
    expect(button().getAttribute('aria-expanded')).toBe('false')
    for (let i = 0; i < 5; i++) await fireEvent.click(button())
    expect(button().getAttribute('aria-expanded')).toBe('true')
    expect(screen.getByRole('menu')).toBeTruthy()
    await fireEvent.click(button())
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('clicar dentro do menu (fora de um item) não o fecha', async () => {
    render(ServerSelector)
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menu'))
    expect(screen.getByRole('menu')).toBeTruthy()
  })

  it('onadd é chamado só pelo item de adicionar, e é opcional', async () => {
    const onadd = vi.fn()
    const { unmount } = render(ServerSelector, { onadd })
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
    expect(onadd).not.toHaveBeenCalled()
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))
    expect(onadd).toHaveBeenCalledOnce()
    unmount()

    render(ServerSelector) // sem onadd: não pode lançar
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('o nome do servidor selecionado é truncado, não estoura o botão', () => {
    selection.select({ id: 'x', name: 'N'.repeat(500), address: 'a' })
    render(ServerSelector)
    expect(button().querySelector('.truncate')?.textContent).toHaveLength(500)
    expect(button().className).toContain('max-w-')
  })

  it('Escape com o menu fechado não faz nada de estranho', async () => {
    render(ServerSelector)
    await fireEvent.keyDown(window, { key: 'Escape' })
    expect(screen.queryByRole('menu')).toBeNull()
    expect(button().getAttribute('aria-expanded')).toBe('false')
  })
})
