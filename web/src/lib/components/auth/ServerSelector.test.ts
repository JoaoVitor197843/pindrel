import { fireEvent, render, screen } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { found, mockDiscover } from '../../../test/discovery'
import { directory, navigation, selection } from '../../stores/servers.svelte'
import ServerSelector from './ServerSelector.svelte'

const button = () => screen.getByRole('button', { name: 'Selecionar servidor' })

beforeEach(async () => {
  selection.connecting = null
  directory.others = []
  mockDiscover([found('Escritório')])
  await directory.refresh()
})

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
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    const onadd = vi.fn()
    const { unmount } = render(ServerSelector, { onadd })
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
    expect(onadd).not.toHaveBeenCalled()
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))
    expect(onadd).toHaveBeenCalledOnce()
    unmount()

    go.mockRestore()
    render(ServerSelector) // sem onadd: não pode lançar
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('o nome do servidor selecionado é truncado, não estoura o botão', () => {
    selection.connecting = { id: 'x', name: 'N'.repeat(500), address: 'a', url: 'http://a' }
    render(ServerSelector)
    expect(button().querySelector('.truncate')?.textContent).toHaveLength(500 + 'Abrindo …'.length)
    expect(button().className).toContain('max-w-')
  })

  it('Escape com o menu fechado não faz nada de estranho', async () => {
    render(ServerSelector)
    await fireEvent.keyDown(window, { key: 'Escape' })
    expect(screen.queryByRole('menu')).toBeNull()
    expect(button().getAttribute('aria-expanded')).toBe('false')
  })

  it('lista o embutido (marcado) e os outros servidores da rede', async () => {
    render(ServerSelector)
    await fireEvent.click(button())
    const items = screen.getAllByRole('menuitemradio')
    expect(items).toHaveLength(2)
    expect(items[0].getAttribute('aria-checked')).toBe('true')
    expect(items[1].getAttribute('aria-checked')).toBe('false')
    expect(items[1].textContent).toContain('192.168.0.20:8095')
    expect(screen.getAllByTestId('selected-check')).toHaveLength(1)
  })

  it('escolher outro servidor fecha o menu, mostra "Abrindo" e navega para ele', async () => {
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    render(ServerSelector)
    await fireEvent.click(button())
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
    expect(screen.queryByRole('menu')).toBeNull()
    expect(button().textContent).toContain('Abrindo Escritório…')
    await vi.waitFor(() => expect(go).toHaveBeenCalledExactlyOnceWith('http://192.168.0.20:8095'))
    go.mockRestore()
  })

  it('durante a troca os itens do menu ficam desativados', async () => {
    selection.connecting = { id: 'x', name: 'X', address: 'a', url: 'http://a' }
    render(ServerSelector)
    await fireEvent.click(button())
    for (const item of screen.getAllByRole('menuitemradio')) expect((item as HTMLButtonElement).disabled).toBe(true)
  })

  it('escolher o embutido não sai da página', async () => {
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    render(ServerSelector)
    await fireEvent.click(button())
    await fireEvent.click(screen.getAllByRole('menuitemradio')[0])
    expect(selection.connecting).toBeNull()
    expect(go).not.toHaveBeenCalled()
    go.mockRestore()
  })

  it('sem outros servidores avisa; antes da primeira consulta mostra o esqueleto', async () => {
    directory.others = []
    render(ServerSelector)
    await fireEvent.click(button())
    expect(screen.getByText('Nenhum outro servidor na rede.')).toBeTruthy()
    expect(screen.queryByTestId('servers-skeleton')).toBeNull()
    directory.loaded = false
    expect(await screen.findByTestId('servers-skeleton')).toBeTruthy()
    directory.loaded = true
  })
})
