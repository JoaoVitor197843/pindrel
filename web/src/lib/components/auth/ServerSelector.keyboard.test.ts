import { fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { beforeEach, describe, expect, it } from 'vitest'
import { found, mockDiscover } from '../../../test/discovery'
import { directory, selection } from '../../stores/servers.svelte'
import { manual } from '../../stores/manual.svelte'
import ServerSelector from './ServerSelector.svelte'

const trigger = () => screen.getByRole('button', { name: /^Selecionar servidor/ })
const items = () => [...document.querySelectorAll<HTMLElement>('button[role^="menuitem"]')]

beforeEach(async () => {
  selection.connecting = null
  selection.health = 'connected'
  directory.others = []
  mockDiscover([found('Escritório'), found('Sítio')])
  await directory.refresh()
})

describe('seletor de servidor só com o teclado', () => {
  it('ArrowDown abre o menu e põe o foco no item marcado; ArrowUp abre no último', async () => {
    render(ServerSelector)
    trigger().focus()
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    await waitFor(() => expect(document.activeElement).toBe(items().find((i) => i.getAttribute('aria-checked') === 'true')))
    await fireEvent.keyDown(trigger(), { key: 'Escape' })
    await fireEvent.keyDown(trigger(), { key: 'ArrowUp' })
    await waitFor(() => expect(document.activeElement).toBe(items().at(-1)))
  })

  it('as setas percorrem os itens em círculo, Home e End vão às pontas', async () => {
    render(ServerSelector)
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    const menu = await screen.findByRole('menu')
    await waitFor(() => expect(menu.contains(document.activeElement)).toBe(true))
    const list = items()
    await fireEvent.keyDown(menu, { key: 'End' })
    expect(document.activeElement).toBe(list.at(-1))
    await fireEvent.keyDown(menu, { key: 'ArrowDown' })
    expect(document.activeElement).toBe(list[0])
    await fireEvent.keyDown(menu, { key: 'ArrowUp' })
    expect(document.activeElement).toBe(list.at(-1))
    await fireEvent.keyDown(menu, { key: 'Home' })
    expect(document.activeElement).toBe(list[0])
  })

  it('Escape fecha e devolve o foco ao botão; Tab fecha sem prender o foco', async () => {
    render(ServerSelector)
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    const menu = await screen.findByRole('menu')
    await fireEvent.keyDown(menu, { key: 'Escape' })
    await waitFor(() => expect(screen.queryByRole('menu')).toBeNull())
    expect(document.activeElement).toBe(trigger())
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    await fireEvent.keyDown(await screen.findByRole('menu'), { key: 'Tab' })
    await waitFor(() => expect(screen.queryByRole('menu')).toBeNull())
  })

  it('Enter num item escolhe o servidor (botão nativo) e o menu tem nome para o leitor de tela', async () => {
    render(ServerSelector)
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    expect(await screen.findByRole('menu', { name: 'Servidores' })).toBeTruthy()
    expect(items().every((i) => i.tagName === 'BUTTON')).toBe(true)
  })

  it('setas numa lista sem itens focáveis não quebram', async () => {
    selection.connecting = { id: 'x', name: 'X', address: 'x:1', url: 'http://x:1' } as never
    render(ServerSelector)
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    const menu = await screen.findByRole('menu')
    for (const key of ['ArrowDown', 'ArrowUp', 'Home', 'End', 'Tab', 'Enter']) await fireEvent.keyDown(menu, { key })
  })

  it('se a lista é refeita sob o foco (o servidor fica offline), o foco continua dentro do menu', async () => {
    render(ServerSelector)
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    const menu = await screen.findByRole('menu')
    await waitFor(() => expect(menu.contains(document.activeElement)).toBe(true))
    expect((document.activeElement as HTMLElement).getAttribute('aria-checked')).toBe('true')
    selection.health = 'disconnected' // the focused entry is destroyed and rebuilt in another section
    await waitFor(() => expect(menu.contains(document.activeElement)).toBe(true))
    expect(document.activeElement).not.toBe(document.body)
  })

  it('o link "Conectar com segurança" também é alcançado pelas setas e abre a página certa em outra aba', async () => {
    manual.list = [{ id: 'http://b.test', name: 'B', trustName: 'B', serverId: 'b', url: 'http://b.test', address: 'b.test', connectUrl: 'http://b.test/server/connect/' }]
    manual.health = { 'http://b.test': 'connected' }
    render(ServerSelector)
    await fireEvent.keyDown(trigger(), { key: 'ArrowDown' })
    const menu = await screen.findByRole('menu')
    const link = screen.getByRole('menuitem', { name: /Conectar com segurança/ }) as HTMLAnchorElement
    expect(link.getAttribute('href')).toBe('http://b.test/server/connect/')
    expect(link.target).toBe('_blank')
    expect(link.rel).toContain('noopener')
    for (let i = 0; i < 6 && document.activeElement !== link; i++) await fireEvent.keyDown(menu, { key: 'ArrowDown' })
    expect(document.activeElement).toBe(link)
    manual.list = []
  })

  it('um servidor com https mostra o cadeado', async () => {
    manual.list = [{ id: 'https://a.test:8443', name: 'A', trustName: 'A', serverId: 'a', url: 'https://a.test:8443', address: 'a.test:8443' }]
    manual.health = { 'https://a.test:8443': 'connected' }
    render(ServerSelector)
    await fireEvent.click(trigger())
    expect(screen.getByRole('img', { name: 'Conexão segura' })).toBeTruthy()
    manual.list = []
  })
})
