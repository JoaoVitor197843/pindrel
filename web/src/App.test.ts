import { fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { instances } from './lib/components/editor/rich/engine'
import App from './App.svelte'
import { viewport } from './test/setup'

const settle = () => new Promise((r) => setTimeout(r, 30))

describe('App — painel e editor', () => {
  beforeEach(() => viewport.set(1400))
  afterEach(() => vi.unstubAllEnvs())
  // the sample panel exists only in the build made for the memory measurements
  const demo = (path: string) => {
    vi.stubEnv('MODE', 'loadtest')
    history.replaceState(null, '', path)
  }

  it('sem ?tela=painel continua abrindo o login', () => {
    history.replaceState(null, '', '/')
    render(App)
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
  })

  it('?tela=painel sem modo não abre o painel de exemplo: mostra o login', () => {
    history.replaceState(null, '', '/?tela=painel')
    render(App)
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(screen.queryByText('Pão de fermentação natural')).toBeNull()
  })

  it('"Continuar sem login" leva ao painel de notas', async () => {
    history.replaceState(null, '', '/')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: /Continuar sem login/ }))
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
    expect(location.search).toBe('?tela=painel&modo=local')
  })

  it('offline: o menu da conta mostra Você, o endereço do servidor e "Logar",', async () => {
    history.replaceState(null, '', '/')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: /Continuar sem login/ }))
    await fireEvent.click(screen.getByRole('button', { name: /Menu da conta de Você/ }))
    expect(screen.getByRole('menu', { name: 'Conta' }).textContent).toContain('Você')
    expect(screen.getByRole('menuitem', { name: 'Logar' })).toBeTruthy()
    expect(screen.queryByRole('menuitem', { name: 'Sair' })).toBeNull()
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Logar' }))
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(location.search).toBe('')
  })

  it('offline: começa vazio, sem páginas de exemplo nem tags, com o cofre e sem "Compartilhadas comigo"', async () => {
    history.replaceState(null, '', '/')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: /Continuar sem login/ }))
    expect(screen.getByRole('heading', { name: 'Nenhuma página ainda' })).toBeTruthy()
    expect(screen.getByRole('button', { name: /Cofre/ })).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Compartilhadas comigo/ })).toBeNull()
    expect(screen.getByRole('button', { name: /Lixeira/ })).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Filtrar pela tag/ })).toBeNull()
    expect(screen.getByText('TAGS').textContent).toContain('0')
    expect(screen.queryByRole('button', { name: /Pão de fermentação/ })).toBeNull()
  })

  it('offline: o cofre abre vazio, sem entradas de exemplo', async () => {
    history.replaceState(null, '', '/?tela=painel&modo=local')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: /Cofre/ }))
    expect(screen.getByRole('heading', { name: 'Cofre' })).toBeTruthy()
    expect(screen.queryByText(/Senhas do/i)).toBeNull()
    expect(screen.getByTestId('vault-empty')).toBeTruthy()
  })

  it('offline: uma página nova não tem o campo Pessoas', async () => {
    history.replaceState(null, '', '/?tela=painel&modo=local')
    render(App)
    await fireEvent.click(await screen.findByRole('button', { name: 'Criar primeira página' }))
    await fireEvent.click(screen.getAllByTestId('page-card')[0].querySelector('button')!)
    expect(screen.queryByText('Pessoas')).toBeNull()
  })

  it('online (sem o modo offline) o menu e o campo de pessoas continuam', async () => {
    demo('/?tela=painel')
    render(App)
    expect(screen.getByRole('button', { name: /Compartilhadas comigo/ })).toBeTruthy()
    await fireEvent.click(screen.getByRole('button', { name: 'Pão de fermentação natural' }))
    expect(screen.getAllByText('Pessoas').length).toBeGreaterThan(0)
  })

  it('abrir um cartão mostra o editor, e voltar traz o painel com a edição refletida', async () => {
    demo('/?tela=painel')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: 'Pão de fermentação natural' }))
    expect(location.pathname).toBe('/notes/p5')
    const title = screen.getByLabelText('Título da página') as HTMLTextAreaElement
    expect(title.value).toBe('Pão de fermentação natural')

    await fireEvent.input(title, { target: { value: 'Pão de forma' } })
    // the paragraph is drawn text until focused: open its editor and write through it
    screen.getByRole('textbox', { name: 'Parágrafo' }).focus()
    await waitFor(() => expect(document.querySelector('[data-rich] [aria-label="Parágrafo"]')).not.toBeNull())
    const inst = instances.get(document.querySelector<HTMLElement>('[data-rich]')!)!
    inst.replace(0, inst.runs().reduce((n, r) => n + r.text.length, 0), [{ text: 'Receita nova do dia', marks: {} }])
    await fireEvent.click(screen.getByRole('button', { name: /Dashboard/ }))
    await settle()

    expect(location.pathname).toBe('/')
    expect(screen.getByRole('button', { name: 'Pão de forma' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Pão de fermentação natural' })).toBeNull()
    expect(screen.getByText('Receita nova do dia')).toBeTruthy()
  })

  it('o botão voltar do navegador sai do editor', async () => {
    demo('/?tela=painel')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: 'Notas da reunião de produto' }))
    expect(screen.getByLabelText('Título da página')).toBeTruthy()
    history.back()
    await waitFor(() => expect(screen.queryByLabelText('Título da página')).toBeNull())
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
  })

  it('abrir o endereço de uma página direto já mostra o editor', () => {
    demo('/notes/p0?tela=painel')
    render(App)
    expect((screen.getByLabelText('Título da página') as HTMLTextAreaElement).value).toBe('Rotina de encerramento do trimestre')
  })

  it('um endereço de página que não existe mostra o aviso e deixa voltar', async () => {
    demo('/notes/nada?tela=painel')
    render(App)
    expect(screen.getByRole('heading', { name: 'Página não encontrada' })).toBeTruthy()
    await fireEvent.click(screen.getByRole('button', { name: 'Voltar ao dashboard' }))
    await settle()
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
  })
})
