import { fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../../types/shared/protos/server'
import { stubLocalStorage } from '../../../test/storage'
import { manual } from '../../stores/manual.svelte'
import { directory, selection } from '../../stores/servers.svelte'
import { toast } from '../../stores/toast.svelte'
import Login from '../../../routes/Login.svelte'

const gateway = (name: string, id: string) =>
  new Response(ServerInfo.encode({ name, registrationEnabled: true }).finish(), {
    headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': id },
  })

/** `up`: hosts that answer as a gateway. Everything else refuses the connection. */
let up: Record<string, Response | 'ok'>
beforeEach(() => {
  stubLocalStorage()
  manual.list = []
  manual.health = {}
  selection.connecting = null
  selection.pendingChange = null
  selection.health = 'connected'
  directory.others = []
  toast.message = ''
  up = {}
  vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
    const entry = up[new URL(url, window.location.href).host]
    if (!entry) {
      if (new URL(url, window.location.href).host === window.location.host) return new Response(null, { status: 404 }) // this page's own server
      if (new URL(url).pathname === '/server/discover/') return new Response(null, { status: 404 })
      throw new TypeError('network')
    }
    if (init?.mode === 'no-cors') return new Response(null)
    return (entry as Response).clone()
  }) as typeof fetch)
})

const openDialog = async () => {
  await fireEvent.click(screen.getByRole('button', { name: /^Selecionar servidor/ }))
  await fireEvent.click(screen.getByRole('menuitem', { name: '+ Adicionar servidor...' }))
}
const type = (label: string, value: string) => fireEvent.input(screen.getByLabelText(label), { target: { value } })
const submit = () => fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))

describe('janela de adicionar servidor', () => {
  it('endereço vazio ou inválido mostra o erro e não consulta a rede', async () => {
    render(Login)
    await openDialog()
    vi.mocked(fetch).mockClear()
    await submit()
    expect((await screen.findByRole('alert')).textContent).toContain('Digite o endereço')
    await type('Endereço', 'um dois')
    await submit()
    expect((await screen.findByRole('alert')).textContent).toContain('Endereço inválido')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('adiciona um gateway válido, fecha, avisa e passa a listá-lo', async () => {
    up = { 'casa.com': gateway('Casa', 'aaa') }
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    await submit()
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    expect(toast.message).toBe('Casa adicionado.')
    await fireEvent.click(screen.getByRole('button', { name: /^Selecionar servidor/ }))
    expect(screen.getByRole('menuitemradio', { name: /Casa/ })).toBeTruthy()
  })

  it('o nome digitado vale mais que o do servidor', async () => {
    up = { 'casa.com': gateway('Casa', 'aaa') }
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    await type('Nome (opcional)', 'Sítio')
    await submit()
    await waitFor(() => expect(manual.list[0]?.name).toBe('Sítio'))
  })

  it('um servidor que não é Pindrel mostra o motivo e a janela continua aberta', async () => {
    up = { 'web.com': new Response('<html>', { headers: { 'content-type': 'text/html' } }) }
    render(Login)
    await openDialog()
    await type('Endereço', 'web.com')
    await submit()
    expect((await screen.findByRole('alert')).textContent).toContain('não é um servidor Pindrel')
    expect(screen.getByRole('dialog')).toBeTruthy()
    expect(manual.list).toEqual([])
  })

  it('durante a verificação os campos travam e o botão não aceita novo toque', async () => {
    let release!: () => void
    vi.mocked(fetch).mockImplementation((() => new Promise<Response>((r) => (release = () => r(gateway('Casa', 'aaa'))))) as typeof fetch)
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    await submit()
    // not `disabled`: that would drop the keyboard focus out of the window
    const button = screen.getByRole('button', { name: 'Verificando…' }) as HTMLButtonElement
    expect(button.getAttribute('aria-disabled')).toBe('true')
    expect((screen.getByLabelText('Endereço') as HTMLInputElement).readOnly).toBe(true)
    expect(screen.getByRole('status').textContent).toContain('Verificando o endereço')
    release()
    await waitFor(() => expect(manual.list).toHaveLength(1))
  })

  const hangingFetch = () => {
    let release!: () => void
    vi.mocked(fetch).mockImplementation(((_: string, init: RequestInit) =>
      new Promise<Response>((resolve, reject) => {
        release = () => resolve(gateway('Casa', 'aaa'))
        init.signal?.addEventListener('abort', () => reject(new Error('abort')))
      })) as typeof fetch)
    return () => release?.()
  }

  it('Escape no meio da verificação só a interrompe: a janela e o texto ficam, o segundo Escape fecha', async () => {
    const release = hangingFetch()
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    await submit()
    await fireEvent.keyDown(window, { key: 'Escape' })
    await waitFor(() => expect(screen.getByRole('button', { name: 'Adicionar' })).toBeTruthy())
    expect(screen.getByRole('dialog')).toBeTruthy()
    expect((screen.getByLabelText('Endereço') as HTMLInputElement).value).toBe('casa.com')
    expect(document.activeElement).toBe(screen.getByLabelText('Endereço'))
    release()
    await new Promise((r) => setTimeout(r, 20))
    expect(manual.list).toEqual([])
    expect(toast.message).toBe('')
    await fireEvent.keyDown(window, { key: 'Escape' })
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  })

  it('Cancelar no meio da verificação fecha e não adiciona nada depois', async () => {
    const release = hangingFetch()
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    await submit()
    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    release()
    await new Promise((r) => setTimeout(r, 20))
    expect(manual.list).toEqual([])
    expect(toast.message).toBe('')
  })

  it('o clique ao lado só fecha se não há nada digitado (não se perde o texto por um toque errado)', async () => {
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.co')
    await fireEvent.click(screen.getByTestId('backdrop'))
    expect(screen.getByRole('dialog')).toBeTruthy()
    await type('Endereço', '   ')
    await fireEvent.click(screen.getByTestId('backdrop'))
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  })

  it('o erro some quando a pessoa volta a digitar, e o foco já está no campo para corrigir', async () => {
    render(Login)
    await openDialog()
    await type('Endereço', 'um dois')
    await submit()
    const field = screen.getByLabelText('Endereço')
    await screen.findByRole('alert')
    expect(field.getAttribute('aria-invalid')).toBe('true')
    expect(field.getAttribute('aria-describedby')).toBe('add-server-error')
    expect(document.activeElement).toBe(field)
    await type('Endereço', 'um')
    expect(screen.queryByRole('alert')).toBeNull()
    expect(field.getAttribute('aria-invalid')).toBeNull()
  })

  it('Enter em qualquer campo envia, e o foco abre no endereço', async () => {
    up = { 'casa.com': gateway('Casa', 'aaa') }
    render(Login)
    await openDialog()
    expect(document.activeElement).toBe(screen.getByLabelText('Endereço'))
    await type('Endereço', 'casa.com')
    await fireEvent.submit(screen.getByLabelText('Nome (opcional)').closest('form')!)
    await waitFor(() => expect(manual.list).toHaveLength(1))
  })

  it('Tab e Shift+Tab giram dentro da janela; a página atrás fica fora de alcance (inert)', async () => {
    render(Login)
    await openDialog()
    expect((document.querySelector('main') as HTMLElement).inert).toBe(true)
    const dialog = screen.getByRole('dialog')
    const cancel = screen.getByRole('button', { name: 'Cancelar' })
    const address = screen.getByLabelText('Endereço')
    cancel.focus()
    await fireEvent.keyDown(document, { key: 'Tab' })
    expect(document.activeElement).toBe(address)
    await fireEvent.keyDown(document, { key: 'Tab', shiftKey: true })
    expect(document.activeElement).toBe(cancel)
    expect(dialog.contains(document.activeElement)).toBe(true)
  })

  it('ao fechar, o foco volta para o botão do seletor, não para o nada', async () => {
    render(Login)
    await openDialog()
    await fireEvent.keyDown(window, { key: 'Escape' })
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    expect(document.activeElement).toBe(screen.getByRole('button', { name: /^Selecionar servidor/ }))
    expect((document.querySelector('main') as HTMLElement).inert).toBe(false)
  })

  it('uso descuidado: colar com espaços, https duplicado ou caminho dá erro claro e não consulta a rede', async () => {
    render(Login)
    await openDialog()
    vi.mocked(fetch).mockClear()
    for (const text of ['https://https://casa.com', 'casa.com/login', 'http://', ' ', '://casa.com', 'casa com']) {
      await type('Endereço', text)
      await submit()
      expect((await screen.findByRole('alert')).textContent).toMatch(/Digite|inválido/)
    }
    expect(fetch).not.toHaveBeenCalled()
  })

  it('muitos toques seguidos em Adicionar fazem uma única verificação', async () => {
    const real = vi.mocked(fetch).getMockImplementation()!
    up = { 'casa.com': gateway('Casa', 'aaa') }
    // the answer takes a while, so every tap lands while the first check is still running
    vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
      await new Promise((r) => setTimeout(r, 40))
      return real(url, init)
    }) as typeof fetch)
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    vi.mocked(fetch).mockClear()
    const form = screen.getByLabelText('Endereço').closest('form')!
    await Promise.all(Array.from({ length: 10 }, () => fireEvent.submit(form)))
    await waitFor(() => expect(manual.list).toHaveLength(1))
    const checks = vi.mocked(fetch).mock.calls.filter(([url, init]) => String(url).includes('casa.com') && init?.mode !== 'no-cors')
    expect(checks.length).toBe(1)
  })

  it('texto enorme não passa do limite do campo', async () => {
    render(Login)
    await openDialog()
    expect((screen.getByLabelText('Endereço') as HTMLInputElement).maxLength).toBe(300)
    expect((screen.getByLabelText('Nome (opcional)') as HTMLInputElement).maxLength).toBe(64)
  })
})

describe('servidores adicionados no seletor', () => {
  const add = async () => {
    up = { 'casa.com': gateway('Casa', 'aaa') }
    await manual.add('casa.com', '')
  }

  it('um servidor que não responde vai para "Desconectados" com o ponto vermelho', async () => {
    await add()
    manual.health = { 'http://casa.com': 'disconnected' }
    render(Login)
    await fireEvent.click(screen.getByRole('button', { name: /^Selecionar servidor/ }))
    const row = screen.getByTestId('added-server')
    expect(row.dataset.tone).toBe('offline')
    expect(screen.getByText('Desconectados')).toBeTruthy()
  })

  it('um que responde fica entre os disponíveis, com o ponto verde, sem o título "Desconectados"', async () => {
    await add()
    render(Login)
    await fireEvent.click(screen.getByRole('button', { name: /^Selecionar servidor/ }))
    expect(screen.getByTestId('added-server').dataset.tone).toBe('online')
    expect(screen.queryByText('Desconectados')).toBeNull()
  })

  it('remover tira da lista e avisa; remover não escolhe o servidor', async () => {
    await add()
    render(Login)
    await fireEvent.click(screen.getByRole('button', { name: /^Selecionar servidor/ }))
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Remover Casa' }))
    expect(manual.list).toEqual([])
    expect(screen.queryByTestId('added-server')).toBeNull()
    expect(toast.message).toBe('Casa removido.')
    expect(selection.connecting).toBeNull()
  })
})
