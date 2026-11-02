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
    headers: { 'content-type': 'application/x-protobuf', 'x-plany-id': id },
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
  await fireEvent.click(screen.getByRole('button', { name: 'Selecionar servidor' }))
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
    await fireEvent.click(screen.getByRole('button', { name: 'Selecionar servidor' }))
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

  it('um servidor que não é Plany mostra o motivo e a janela continua aberta', async () => {
    up = { 'web.com': new Response('<html>', { headers: { 'content-type': 'text/html' } }) }
    render(Login)
    await openDialog()
    await type('Endereço', 'web.com')
    await submit()
    expect((await screen.findByRole('alert')).textContent).toContain('não é um servidor Plany')
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
    const button = screen.getByRole('button', { name: 'Verificando…' }) as HTMLButtonElement
    expect(button.disabled).toBe(true)
    expect((screen.getByLabelText('Endereço') as HTMLInputElement).disabled).toBe(true)
    release()
    await waitFor(() => expect(manual.list).toHaveLength(1))
  })

  it('Escape ou Cancelar no meio da verificação não adiciona nada depois', async () => {
    let release!: () => void
    vi.mocked(fetch).mockImplementation(((_: string, init: RequestInit) =>
      new Promise<Response>((resolve, reject) => {
        release = () => resolve(gateway('Casa', 'aaa'))
        init.signal?.addEventListener('abort', () => reject(new Error('abort')))
      })) as typeof fetch)
    render(Login)
    await openDialog()
    await type('Endereço', 'casa.com')
    await submit()
    await fireEvent.keyDown(window, { key: 'Escape' })
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    release?.()
    await new Promise((r) => setTimeout(r, 20))
    expect(manual.list).toEqual([])
    expect(toast.message).toBe('')
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
    await fireEvent.click(screen.getByRole('button', { name: 'Selecionar servidor' }))
    const row = screen.getByTestId('added-server')
    expect(row.dataset.tone).toBe('offline')
    expect(screen.getByText('Desconectados')).toBeTruthy()
  })

  it('um que responde fica entre os disponíveis, com o ponto verde, sem o título "Desconectados"', async () => {
    await add()
    render(Login)
    await fireEvent.click(screen.getByRole('button', { name: 'Selecionar servidor' }))
    expect(screen.getByTestId('added-server').dataset.tone).toBe('online')
    expect(screen.queryByText('Desconectados')).toBeNull()
  })

  it('remover tira da lista e avisa; remover não escolhe o servidor', async () => {
    await add()
    render(Login)
    await fireEvent.click(screen.getByRole('button', { name: 'Selecionar servidor' }))
    await fireEvent.click(screen.getByRole('button', { name: 'Remover Casa' }))
    expect(manual.list).toEqual([])
    expect(screen.queryByTestId('added-server')).toBeNull()
    expect(toast.message).toBe('Casa removido.')
    expect(selection.connecting).toBeNull()
  })
})
