import { fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { beforeEach, describe, expect, it } from 'vitest'
import App from './App.svelte'
import { viewport } from './test/setup'

const settle = () => new Promise((r) => setTimeout(r, 30))

describe('App — painel e editor', () => {
  beforeEach(() => viewport.set(1400))

  it('sem ?tela=painel continua abrindo o login', () => {
    history.replaceState(null, '', '/')
    render(App)
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
  })

  it('abrir um cartão mostra o editor, e voltar traz o painel com a edição refletida', async () => {
    history.replaceState(null, '', '/?tela=painel')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: 'Pão de fermentação natural' }))
    expect(location.pathname).toBe('/notes/p5')
    const title = screen.getByLabelText('Título da página') as HTMLTextAreaElement
    expect(title.value).toBe('Pão de fermentação natural')

    await fireEvent.input(title, { target: { value: 'Pão de forma' } })
    await fireEvent.input(screen.getByLabelText('Parágrafo'), { target: { value: 'Receita nova do dia' } })
    await fireEvent.click(screen.getByRole('button', { name: /Dashboard/ }))
    await settle()

    expect(location.pathname).toBe('/')
    expect(screen.getByRole('button', { name: 'Pão de forma' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Pão de fermentação natural' })).toBeNull()
    expect(screen.getByText('Receita nova do dia')).toBeTruthy()
  })

  it('o botão voltar do navegador sai do editor', async () => {
    history.replaceState(null, '', '/?tela=painel')
    render(App)
    await fireEvent.click(screen.getByRole('button', { name: 'Notas da reunião de produto' }))
    expect(screen.getByLabelText('Título da página')).toBeTruthy()
    history.back()
    await waitFor(() => expect(screen.queryByLabelText('Título da página')).toBeNull())
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
  })

  it('abrir o endereço de uma página direto já mostra o editor', () => {
    history.replaceState(null, '', '/notes/p0?tela=painel')
    render(App)
    expect((screen.getByLabelText('Título da página') as HTMLTextAreaElement).value).toBe('Rotina de encerramento do trimestre')
  })

  it('um endereço de página que não existe mostra o aviso e deixa voltar', async () => {
    history.replaceState(null, '', '/notes/nada?tela=painel')
    render(App)
    expect(screen.getByRole('heading', { name: 'Página não encontrada' })).toBeTruthy()
    await fireEvent.click(screen.getByRole('button', { name: 'Voltar ao dashboard' }))
    await settle()
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
  })
})
