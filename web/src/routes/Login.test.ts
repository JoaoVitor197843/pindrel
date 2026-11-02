import { act, fireEvent, render, screen, within } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { directory, navigation, selection } from '../lib/stores/servers.svelte'
import { found, mockDiscover } from '../test/discovery'
import { viewport } from '../test/setup'
import { stubLocalStorage } from '../test/storage'
import { remember } from '../lib/stores/trust'
import Login from './Login.svelte'

const click = (el: HTMLElement) => fireEvent.click(el)

const openMenu = () => click(screen.getByRole('button', { name: 'Selecionar servidor' }))

beforeEach(async () => {
  stubLocalStorage()
  selection.connecting = null
  selection.pendingChange = null
  selection.health = 'connected'
  selection.address = null
  directory.others = []
  mockDiscover([found('Escritório')])
  await directory.refresh()
})

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
    // the primary button also becomes "Criar conta"; the footer link becomes "Entrar"
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
    expect(items).toHaveLength(directory.list.length)
    expect(items[0].getAttribute('aria-checked')).toBe('true')
    expect(items[0].className).toContain('border-accent-line')
    expect(within(items[0]).getByTestId('selected-check')).toBeTruthy()
    expect(screen.getAllByTestId('selected-check')).toHaveLength(1)
    expect(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' })).toBeTruthy()

    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await click(screen.getByRole('menuitemradio', { name: /Escritório/ }))

    // the menu closes, the button shows the switch and the form fades without accepting taps
    expect(screen.queryByRole('menu')).toBeNull()
    expect(screen.getByRole('button', { name: 'Selecionar servidor' }).textContent).toContain('Abrindo Escritório…')
    const form = screen.getByRole('heading', { name: 'Bem-vindo de volta' }).closest('.transition-opacity')
    expect(form?.className).toContain('opacity-30')
    await vi.waitFor(() => expect(go).toHaveBeenCalledWith('http://192.168.0.20:8095'))
    go.mockRestore()
  })

  it('servidor que não responde: a tela volta ao normal e avisa', async () => {
    vi.mocked(fetch).mockRejectedValue(new TypeError('sem rota'))
    render(Login)
    await openMenu()
    await click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
    await vi.waitFor(() => expect(screen.getByRole('status').textContent).toContain('Escritório não respondeu.'))
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' }).closest('.transition-opacity')?.className).not.toContain('opacity-30')
    expect(screen.getByRole('button', { name: 'Selecionar servidor' }).textContent).toContain('Embutido')
  })

  it('o servidor embutido é o padrão', () => {
    expect(selection.selected.id).toBe('embedded')
    expect(selection.selected.address).toBe(window.location.host)
  })

  it('"+ Adicionar servidor..." fecha o menu e abre a janela de adicionar', async () => {
    render(Login)
    await openMenu()

    await click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))

    expect(screen.queryByRole('menu')).toBeNull()
    expect(screen.getByRole('dialog', { name: 'Adicionar servidor' })).toBeTruthy()
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

describe('Login — servidor com outra identidade', () => {
  async function chooseOffice(announcedId: string) {
    mockDiscover([found('Escritório', '192.168.0.20', 8095, announcedId)])
    await directory.refresh()
    render(Login)
    await openMenu()
    await click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
  }

  it('o mesmo nome com outro id pergunta, e Cancelar deixa tudo como estava', async () => {
    remember('Escritório', 'aaa')
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await chooseOffice('bbb')
    expect(screen.getByRole('heading', { name: 'Este servidor mudou' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Selecionar servidor' }).textContent).toContain('Embutido')
    await click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(go).not.toHaveBeenCalled()
    go.mockRestore()
  })

  it('Continuar mesmo assim segue para o servidor', async () => {
    remember('Escritório', 'aaa')
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await chooseOffice('bbb')
    await click(screen.getByRole('button', { name: 'Continuar mesmo assim' }))
    await vi.waitFor(() => expect(go).toHaveBeenCalledWith('http://192.168.0.20:8095'))
    go.mockRestore()
  })

  it('o mesmo id, ou um servidor novo, não pergunta nada', async () => {
    remember('Escritório', 'aaa')
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await chooseOffice('aaa')
    expect(screen.queryByRole('dialog')).toBeNull()
    await vi.waitFor(() => expect(go).toHaveBeenCalledOnce())
    go.mockRestore()
  })
})

describe('Login — layout desktop', () => {
  beforeEach(() => viewport.set(1300))

  it('mostra painel institucional, subtítulo e rodapé do servidor', async () => {
    render(Login)

    expect(screen.getByText('Roda no seu hardware')).toBeTruthy()
    expect(screen.getByText('Blocos aninhados')).toBeTruthy()
    expect(screen.getByText('Cofre com criptografia')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(screen.getByText('Entre para continuar de onde você parou.')).toBeTruthy()
    // sem gateway (404) o endereço é o do próprio host, assim que a primeira consulta termina
    expect(await screen.findByText(`→ Rodando em: ${window.location.host}`)).toBeTruthy()
  })

  it('o rodapé continua no servidor embutido durante a troca de servidor', async () => {
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    render(Login)
    await openMenu()
    await click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
    expect(screen.getByText(`→ Rodando em: ${window.location.host}`)).toBeTruthy()
    await vi.waitFor(() => expect(go).toHaveBeenCalled())
    go.mockRestore()
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

describe('Login — rodapé do desktop e saúde do servidor', () => {
  it('rodapé com bolinha verde enquanto o servidor responde', async () => {
    viewport.set(1200)
    render(Login)
    expect(screen.getByText(/Rodando em:/)).toBeTruthy()
    expect(screen.getByTestId('footer-dot').dataset.tone).toBe('online')
  })

  it('rodapé vermelho e "Desconectado de" quando o servidor cai, e volta ao voltar', async () => {
    viewport.set(1200)
    render(Login)
    // the initial query answers 'connected': wait for it to finish before simulating the drop
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledWith('/server/info/', expect.anything()))
    await new Promise((r) => setTimeout(r, 0))
    selection.health = 'disconnected'
    expect(await screen.findByText(/Desconectado de:/)).toBeTruthy()
    expect(screen.getByTestId('footer-dot').dataset.tone).toBe('offline')
    selection.health = 'connected'
    expect(await screen.findByText(/Rodando em:/)).toBeTruthy()
  })

  it('o login consulta a saúde do servidor ao abrir', async () => {
    render(Login)
    await vi.waitFor(() => {
      expect(vi.mocked(fetch).mock.calls.some(([url]) => String(url) === '/server/info/')).toBe(true)
    })
  })
})

describe('Login — address of the server', () => {
  it('the footer and the menu show the LAN address when the gateway tells it', async () => {
    viewport.set(1200)
    vi.mocked(fetch).mockImplementation(
      async () => new Response(null, { status: 200, headers: { 'x-pindrel-address': '192.168.1.163:8086' } }),
    )
    render(Login)
    expect(await screen.findByText(/192\.168\.1\.163:8086/)).toBeTruthy()
    expect(screen.queryByText(new RegExp(selection.selected.address.replace('.', '\\.') + '$'))).toBeNull()
    await openMenu()
    expect(screen.getAllByText('192.168.1.163:8086').length).toBeGreaterThan(0)
  })
})

describe('Login — the address does not flash the wrong one', () => {
  it('shows a placeholder until the server answers, then the LAN address', async () => {
    viewport.set(1200)
    let answer!: (r: Response) => void
    vi.mocked(fetch).mockImplementation(() => new Promise<Response>((resolve) => (answer = resolve)))
    render(Login)
    await vi.waitFor(() => expect(answer).toBeTypeOf('function'))
    expect(screen.getByText(/Rodando em:/).textContent).toContain('…')
    expect(screen.queryByText(new RegExp(selection.selected.address.replace('.', '\\.')))).toBeNull()
    answer(new Response(null, { status: 200, headers: { 'x-pindrel-address': '192.168.1.163:8086' } }))
    expect(await screen.findByText(/192\.168\.1\.163:8086/)).toBeTruthy()
  })
})
