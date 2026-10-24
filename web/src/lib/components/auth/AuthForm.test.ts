import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'
import AuthForm from './AuthForm.svelte'

const click = (el: HTMLElement) => fireEvent.click(el)
const email = () => screen.getByLabelText('E-mail') as HTMLInputElement
const password = () => screen.getByLabelText('Senha') as HTMLInputElement

describe('AuthForm — uso descuidado', () => {
  it('toques repetidos em MOSTRAR/OCULTAR terminam no estado certo', async () => {
    render(AuthForm)
    const toggle = () => screen.getByRole('button', { name: /MOSTRAR|OCULTAR/ })
    for (let i = 0; i < 7; i++) await click(toggle())
    expect(password().type).toBe('text') // 7 taps = odd

    await click(toggle())
    expect(password().type).toBe('password')
  })

  it('alternar login/registro várias vezes não perde o que foi digitado', async () => {
    render(AuthForm)
    await fireEvent.input(email(), { target: { value: 'ana@casa.local' } })
    await fireEvent.input(password(), { target: { value: 'segredo123' } })

    await click(screen.getByRole('button', { name: 'Criar conta' }))
    await click(screen.getByRole('button', { name: 'Entrar' }))
    await click(screen.getByRole('button', { name: 'Criar conta' }))

    expect(email().value).toBe('ana@casa.local')
    expect(password().value).toBe('segredo123')
  })

  it('o campo de senha muda o autocomplete conforme o modo (gerenciador de senhas)', async () => {
    render(AuthForm)
    expect(password().autocomplete).toBe('current-password')
    await click(screen.getByRole('button', { name: 'Criar conta' }))
    expect(password().autocomplete).toBe('new-password')
  })

  it('aceita texto vazio, enorme, com espaços e emoji sem quebrar', async () => {
    render(AuthForm)
    for (const value of ['', '   ', 'a'.repeat(100_000), 'çãõ 🚀 <script>alert(1)</script>']) {
      await fireEvent.input(password(), { target: { value } })
      expect(password().value).toBe(value)
    }
    expect(screen.getByRole('button', { name: 'Entrar' })).toBeTruthy()
  })

  it('enviar (Enter ou clique, várias vezes, até vazio) não recarrega a página', async () => {
    render(AuthForm)
    const form = document.querySelector('form')!
    for (let i = 0; i < 3; i++) {
      const notCancelled = await fireEvent.submit(form)
      expect(notCancelled).toBe(false) // preventDefault was called
    }
    await click(screen.getByRole('button', { name: 'Entrar' }))
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
  })

  it('o callback offline é chamado uma vez por toque (sem duplicar)', async () => {
    const cb = vi.fn()
    render(AuthForm, { oncontinueoffline: cb })
    const btn = screen.getByRole('button', { name: 'Continuar offline neste dispositivo' })
    await click(btn)
    await click(btn)
    expect(cb).toHaveBeenCalledTimes(2)
  })

  it('abrir o modal duas vezes não empilha dois diálogos', async () => {
    render(AuthForm)
    const open = screen.getByRole('button', { name: 'Chave de recuperação' })
    await click(open)
    // the button sits behind the modal, but a second direct click must not duplicate
    await click(open)
    expect(screen.getAllByRole('dialog')).toHaveLength(1)
  })

  it('o subtítulo só aparece quando pedido e acompanha o modo', async () => {
    const { unmount } = render(AuthForm)
    expect(screen.queryByText(/Entre para continuar/)).toBeNull()
    unmount()

    render(AuthForm, { showSubtitle: true })
    expect(screen.getByText(/Entre para continuar/)).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Criar conta' }))
    expect(screen.getByText(/Crie sua conta/)).toBeTruthy()
  })

  it('todos os campos têm label associado (acessibilidade)', async () => {
    render(AuthForm)
    await click(screen.getByRole('button', { name: 'Criar conta' }))
    for (const name of ['Username', 'E-mail', 'Senha']) {
      expect(screen.getByLabelText(name)).toBeTruthy()
    }
  })
})

describe('AuthForm — troca de modo animada', () => {
  it('toques em rajada em "Criar conta"/"Entrar" terminam no modo certo, sem duplicar nada', async () => {
    render(AuthForm, { showSubtitle: true })
    const link = () => screen.getAllByRole('button').find((b) => b.className.includes('font-bold')) as HTMLElement
    for (let i = 0; i < 7; i++) await click(link())
    await vi.waitFor(() => {
      expect(screen.getAllByRole('heading')).toHaveLength(1)
      expect(screen.getByRole('heading').textContent?.trim()).toBe('Criar nova conta')
      expect(screen.getAllByLabelText('Username')).toHaveLength(1)
    })
  })
})
