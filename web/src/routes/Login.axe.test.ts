import axe from 'axe-core'
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { beforeEach, describe, expect, it } from 'vitest'
import { directory, selection } from '../lib/stores/servers.svelte'
import { manual } from '../lib/stores/manual.svelte'
import { found, mockDiscover } from '../test/discovery'
import { viewport } from '../test/setup'
import { stubLocalStorage } from '../test/storage'
import Login from './Login.svelte'

/**
 * axe is the rule set behind Lighthouse's accessibility score and checks the ARIA that NVDA, JAWS and VoiceOver read
 * (valid roles, required children, names for every control, ids that exist). jsdom has no layout, so color contrast is
 * measured elsewhere (a real browser); here it is switched off.
 */
async function violations(): Promise<string[]> {
  const result = await axe.run(document.body, { rules: { 'color-contrast': { enabled: false }, region: { enabled: false } } })
  return result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.html.slice(0, 80)).join(' | ')}`)
}

beforeEach(async () => {
  stubLocalStorage()
  manual.list = []
  manual.health = {}
  selection.connecting = null
  selection.pendingChange = null
  selection.health = 'connected'
  directory.others = []
  mockDiscover([found('Escritório'), found('Sítio')])
  await directory.refresh()
  viewport.set(450)
})

const openMenu = () => fireEvent.click(screen.getByRole('button', { name: /^Selecionar servidor/ }))

describe('acessibilidade (axe) nos estados da tela de login', () => {
  it('celular: tela inicial', async () => {
    render(Login)
    expect(await violations()).toEqual([])
  })

  it('desktop: tela inicial', async () => {
    viewport.set(1200)
    render(Login)
    expect(await violations()).toEqual([])
  })

  it('menu de servidores aberto, com um servidor adicionado e outro desconectado', async () => {
    manual.list = [
      { id: 'http://a.test', name: 'A', trustName: 'A', serverId: 'a', url: 'http://a.test', address: 'a.test' },
      { id: 'http://b.test', name: 'B', trustName: 'B', serverId: 'b', url: 'http://b.test', address: 'b.test' },
    ]
    manual.health = { 'http://a.test': 'connected', 'http://b.test': 'disconnected' }
    render(Login)
    await openMenu()
    expect(await violations()).toEqual([])
  })

  it('menu com o servidor da página offline', async () => {
    selection.health = 'disconnected'
    render(Login)
    await openMenu()
    expect(await violations()).toEqual([])
  })

  it('janela de adicionar servidor, vazia e com erro', async () => {
    render(Login)
    await openMenu()
    await fireEvent.click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))
    expect(await violations()).toEqual([])
    await fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))
    await screen.findByRole('alert')
    expect(await violations()).toEqual([])
  })

  it('janela "Este servidor mudou"', async () => {
    render(Login)
    selection.pendingChange = { id: 'x', name: 'Casa', address: 'x:1', url: 'http://x:1' } as never
    await waitFor(() => expect(screen.getByRole('alertdialog')).toBeTruthy())
    expect(await violations()).toEqual([])
  })

  it('o próprio axe pega um erro de verdade (o teste não é cego)', async () => {
    render(Login)
    document.body.insertAdjacentHTML('beforeend', '<button></button><div role="menu"><p>x</p></div><img src="a.png">')
    const found = (await violations()).map((v) => v.split(':')[0])
    expect(found).toEqual(expect.arrayContaining(['button-name', 'image-alt']))
  })
})
