import { act, fireEvent, render, screen, within } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { selection, servers } from '../lib/stores/servers.svelte'
import { viewport } from '../test/setup'
import Login from './Login.svelte'

const click = (el: HTMLElement) => fireEvent.click(el)

const openMenu = () => click(screen.getByRole('button', { name: 'Selecionar servidor' }))

beforeEach(() => selection.select(servers[0]))

describe('Login — layout mobile', () => {
  it('mostra cabeçalho e formulário de login, sem o painel desktop', () => {
    render(Login)

    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(screen.getByText('SELF-HOSTED')).toBeTruthy()
    expect(screen.getByPlaceholderText('voce@casa.local')).toBeTruthy()
    expect(screen.getByText('Chave de recuperação')).toBeTruthy()
    expect(screen.queryByText('Esqueceu a senha?')).toBeNull()
    expect(screen.getByRole('button', { name: 'Entrar' })).toBeTruthy()
    expect(screen.getByText('OU')).toBeTruthy()

    expect(screen.queryByText('Roda no seu hardware')).toBeNull()
    expect(screen.queryByText(/Rodando em/)).toBeNull()
    expect(screen.queryByText(/Entre para continuar/)).toBeNull()
  })

  it('alterna a visibilidade da senha com MOSTRAR / OCULTAR', async () => {
    render(Login)
    const password = screen.getByLabelText('Senha') as HTMLInputElement
    expect(password.type).toBe('password')

    await click(screen.getByRole('button', { name: 'MOSTRAR' }))
    expect(password.type).toBe('text')

    await click(screen.getByRole('button', { name: 'OCULTAR' }))
    expect(password.type).toBe('password')
  })

  it('"Manter conectado" começa marcado e alterna', async () => {
    render(Login)
    const checkbox = screen.getByLabelText('Manter conectado') as HTMLInputElement
    expect(checkbox.checked).toBe(true)

    await click(checkbox)
    expect(checkbox.checked).toBe(false)
  })

  it('alterna para o modo de registro com Username e volta ao login', async () => {
    render(Login)
    expect(screen.queryByLabelText('Username')).toBeNull()

    await click(screen.getByRole('button', { name: 'Criar conta' }))

    expect(screen.getByRole('heading', { name: 'Criar nova conta' })).toBeTruthy()
    expect(screen.getByLabelText('Username')).toBeTruthy()
    expect(screen.getByText('Já tem conta?')).toBeTruthy()
    // o botão primário também vira "Criar conta"; o link do rodapé vira "Entrar"
    expect(screen.getAllByRole('button', { name: 'Criar conta' })).toHaveLength(1)

    await click(screen.getByRole('button', { name: 'Entrar' }))
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(screen.queryByLabelText('Username')).toBeNull()
  })

  it('botão offline chama o callback', async () => {
    const oncontinueoffline = vi.fn()
    render(Login, { oncontinueoffline })

    await click(screen.getByRole('button', { name: 'Continuar offline neste dispositivo' }))

    expect(oncontinueoffline).toHaveBeenCalledOnce()
  })

  it('botão offline sem callback mostra aviso', async () => {
    render(Login)

    await click(screen.getByRole('button', { name: 'Continuar offline neste dispositivo' }))

    expect(screen.getByRole('status').textContent).toContain('Notas locais chegam em breve.')
  })

  it('"Chave de recuperação" abre e fecha o modal', async () => {
    render(Login)

    await click(screen.getByRole('button', { name: 'Chave de recuperação' }))
    const dialog = screen.getByRole('dialog')
    expect(within(dialog).getByPlaceholderText('XXXX-XXXX-XXXX')).toBeTruthy()

    await click(within(dialog).getByRole('button', { name: 'Recuperar acesso' }))
    expect(screen.queryByRole('dialog')).toBeNull()
  })

  it('Escape fecha o modal de recuperação', async () => {
    render(Login)
    await click(screen.getByRole('button', { name: 'Chave de recuperação' }))

    await fireEvent.keyDown(window, { key: 'Escape' })

    expect(screen.queryByRole('dialog')).toBeNull()
  })
})

describe('Login — seletor de servidor', () => {
  it('destaca o servidor selecionado e troca a seleção', async () => {
    render(Login)
    await openMenu()

    const items = screen.getAllByRole('menuitemradio')
    expect(items).toHaveLength(servers.length)
    expect(items[0].getAttribute('aria-checked')).toBe('true')
    expect(items[0].className).toContain('border-accent-line')
    expect(within(items[0]).getByTestId('selected-check')).toBeTruthy()
    expect(screen.getAllByTestId('selected-check')).toHaveLength(1)
    expect(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' })).toBeTruthy()

    await click(screen.getByRole('menuitemradio', { name: /Escritório/ }))

    // o menu fecha e o botão passa a mostrar o novo servidor
    expect(screen.queryByRole('menu')).toBeNull()
    expect(screen.getByRole('button', { name: 'Selecionar servidor' }).textContent).toContain('Escritório')

    await openMenu()
    const after = screen.getAllByRole('menuitemradio')
    expect(after[0].getAttribute('aria-checked')).toBe('false')
    expect(after[0].className).not.toContain('bg-accent/45')
    expect(after[1].getAttribute('aria-checked')).toBe('true')
    expect(after[1].className).toContain('bg-accent/45')
    expect(screen.getAllByTestId('selected-check')).toHaveLength(1)
  })

  it('o servidor embutido é o padrão', () => {
    expect(selection.selected.id).toBe('embedded')
    expect(selection.selected.address).toBe(window.location.host)
  })

  it('"+ Adicionar servidor..." fecha o menu e avisa o usuário', async () => {
    render(Login)
    await openMenu()

    await click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))

    expect(screen.queryByRole('menu')).toBeNull()
    expect(screen.getByRole('status').textContent).toContain('Adicionar servidor chega em breve.')
  })

  it('clicar fora ou apertar Escape fecha o menu', async () => {
    render(Login)
    await openMenu()
    await click(document.body)
    expect(screen.queryByRole('menu')).toBeNull()

    await openMenu()
    await fireEvent.keyDown(window, { key: 'Escape' })
    expect(screen.queryByRole('menu')).toBeNull()
  })
})

describe('Login — layout desktop', () => {
  beforeEach(() => viewport.set(1300))

  it('mostra painel institucional, subtítulo e rodapé do servidor', () => {
    render(Login)

    expect(screen.getByText('Roda no seu hardware')).toBeTruthy()
    expect(screen.getByText('Blocos aninhados')).toBeTruthy()
    expect(screen.getByText('Cofre com criptografia')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(screen.getByText('Entre para continuar de onde você parou.')).toBeTruthy()
    expect(screen.getByText(`→ Rodando em: ${window.location.host}`)).toBeTruthy()
  })

  it('trocar de servidor atualiza o rodapé', async () => {
    render(Login)
    await openMenu()

    await click(screen.getByRole('menuitemradio', { name: /Escritório/ }))

    expect(screen.getByText('→ Rodando em: 192.168.0.20')).toBeTruthy()
  })

  it('senha, registro e offline continuam funcionando', async () => {
    const oncontinueoffline = vi.fn()
    render(Login, { oncontinueoffline })

    await click(screen.getByRole('button', { name: 'MOSTRAR' }))
    expect((screen.getByLabelText('Senha') as HTMLInputElement).type).toBe('text')

    await click(screen.getByRole('button', { name: 'Criar conta' }))
    expect(screen.getByText('Crie sua conta para começar a escrever.')).toBeTruthy()
    expect(screen.getByLabelText('Username')).toBeTruthy()

    await click(screen.getByRole('button', { name: 'Continuar offline neste dispositivo' }))
    expect(oncontinueoffline).toHaveBeenCalledOnce()
  })

  it('redimensionar alterna entre os layouts', async () => {
    viewport.set(450)
    render(Login)
    expect(screen.queryByText('Roda no seu hardware')).toBeNull()

    await act(() => viewport.set(1300))
    expect(screen.getByText('Roda no seu hardware')).toBeTruthy()

    await act(() => viewport.set(450))
    expect(screen.queryByText('Roda no seu hardware')).toBeNull()
  })
})
