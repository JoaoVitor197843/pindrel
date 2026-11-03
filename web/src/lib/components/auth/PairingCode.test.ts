import { cleanup, fireEvent, render, screen } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { selection } from '../../stores/servers.svelte'
import PairingCode from './PairingCode.svelte'

const TOKEN = 'a'.repeat(32)
const room = (code = '4821', token = TOKEN, ttl = 180) => new Response(`code=${code}\ntoken=${token}\nttl=${ttl}\n`, { status: 200 })
const state = (left = 170, phone = '', d = '') =>
  new Response(`left=${left}\n${phone ? `phone=${phone}\n` : ''}${d ? `d=${d}\n` : ''}`, { status: 200 })

// the shared setup resets the global fetch before every test; each test gives it the answers it needs
type Call = { url: string; method: string; token?: string }
function server(handlers: { open?: () => Response; look?: () => Response }) {
  const calls: Call[] = []
  vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
    const headers = (init?.headers ?? {}) as Record<string, string>
    calls.push({ url, method: init?.method ?? 'GET', token: headers['x-pindrel-room'] })
    if (url === '/server/pair/room' && init?.method === 'POST') return handlers.open?.() ?? room()
    if (url === '/server/pair/room') return handlers.look?.() ?? state()
    return new Response(null, { status: 204 })
  }) as never)
  return calls
}

beforeEach(() => {
  vi.useFakeTimers()
  selection.tlsOffered = true
})
afterEach(() => {
  cleanup()
  vi.useRealTimers()
  selection.tlsOffered = false
})

async function openBox() {
  const details = screen.getByTestId('pairing-code') as HTMLDetailsElement
  details.open = true
  await fireEvent(details, new Event('toggle'))
}
async function ask() {
  await openBox()
  await fireEvent.click(screen.getByTestId('room-open'))
  await vi.advanceTimersByTimeAsync(0)
}

describe('PairingCode (sala de pareamento na tela de login)', () => {
  it('não aparece quando o servidor não tem lado seguro', () => {
    selection.tlsOffered = false
    render(PairingCode)
    expect(screen.queryByTestId('pairing-code')).toBeNull()
  })

  it('fechada ou sem pedir, não fala com o servidor', async () => {
    const calls = server({})
    render(PairingCode)
    await vi.advanceTimersByTimeAsync(10_000)
    await openBox()
    await vi.advanceTimersByTimeAsync(10_000)
    expect(calls).toHaveLength(0)
  })

  it('pedir a sala mostra o código de 4 dígitos e espera o app', async () => {
    const calls = server({})
    render(PairingCode)
    await ask()
    expect(screen.getByTestId('room-code').textContent).toBe('4821')
    expect(screen.getByTestId('room-code').getAttribute('aria-label')).toBe('Código da sala: 4 8 2 1')
    expect(screen.getByTestId('room-waiting').textContent).toContain('Esperando o app')
    expect(calls[0]).toMatchObject({ url: '/server/pair/room', method: 'POST' })
    expect(calls[1]).toMatchObject({ method: 'GET', token: TOKEN }) // looked at once, the token in a header
    expect(calls.every((c) => !c.url.includes(TOKEN)), 'never in a URL').toBe(true)
  })

  it('quando o app entra e revela, mostra os 6 números e o aparelho; só os da sala', async () => {
    let look = () => state(160)
    server({ look: () => look() })
    render(PairingCode)
    await ask()
    look = () => state(150, '192.168.1.5')
    await vi.advanceTimersByTimeAsync(2000)
    expect(screen.getByTestId('room-waiting').textContent).toContain('O app entrou')
    look = () => state(140, '192.168.1.5', '123456,48')
    await vi.advanceTimersByTimeAsync(2000)
    const el = screen.getByTestId('pairing-digits')
    expect(el.textContent?.trim()).toBe('123 456')
    expect(el.getAttribute('aria-label')).toBe('Número de conferência: 1 2 3 4 5 6')
    expect(screen.getByText(/aparelho 192\.168\.1\.5/)).toBeTruthy()
    expect(screen.getByText(/fecha em 140 s/)).toBeTruthy()
  })

  it('se a sala some (usada, vencida, fechada), avisa e deixa gerar outra', async () => {
    let look = () => state()
    server({ look: () => look() })
    render(PairingCode)
    await ask()
    look = () => new Response('', { status: 404 })
    await vi.advanceTimersByTimeAsync(2000)
    expect(screen.queryByTestId('room-code')).toBeNull()
    expect(screen.getByTestId('room-error').textContent).toContain('venceu')
    look = () => state() // the next room is a fresh one
    await fireEvent.click(screen.getByTestId('room-open')) // and asking again works
    await vi.advanceTimersByTimeAsync(0)
    expect(screen.getByTestId('room-code').textContent).toBe('4821')
  })

  it('"Gerar outro código" fecha a sala antiga e abre uma nova', async () => {
    let n = 0
    const calls = server({ open: () => room(String(1000 + ++n), String(n).repeat(32).slice(0, 32).replace(/./g, (c) => ('0123456789abcdef'[+c] ?? 'a'))) })
    render(PairingCode)
    await ask()
    await fireEvent.click(screen.getByText('Gerar outro código'))
    await vi.advanceTimersByTimeAsync(0)
    expect(screen.getByTestId('room-code').textContent).toBe('1002')
    expect(calls.some((c) => c.url === '/server/pair/room/close' && c.token === '1'.repeat(32))).toBe(true)
  })

  it('"Fechar" e fechar a caixa fecham a sala no servidor e param de consultar', async () => {
    const calls = server({})
    render(PairingCode)
    await ask()
    await fireEvent.click(screen.getByText('Fechar'))
    await vi.advanceTimersByTimeAsync(0)
    expect(calls.some((c) => c.url === '/server/pair/room/close' && c.token === TOKEN)).toBe(true)
    const after = calls.length
    await vi.advanceTimersByTimeAsync(20_000)
    expect(calls.length).toBe(after)
    expect(screen.queryByTestId('room-code')).toBeNull()
  })

  it('sair da página fecha a sala', async () => {
    const calls = server({})
    render(PairingCode)
    await ask()
    window.dispatchEvent(new Event('pagehide'))
    await vi.advanceTimersByTimeAsync(0)
    expect(calls.some((c) => c.url === '/server/pair/room/close')).toBe(true)
  })

  it('servidor cheio, erro, resposta estranha ou fora do ar: mensagem simples, sem sala', async () => {
    for (const [open, text] of [
      [() => new Response('', { status: 429 }), 'demais'],
      [() => new Response('', { status: 500 }), 'Não foi possível abrir'],
      [() => new Response('code=12\ntoken=zz\n', { status: 200 }), 'inesperado'],
      [() => new Response('code=<b>1</b>\ntoken=' + TOKEN + '\n', { status: 200 }), 'inesperado'],
      [() => new Response('', { status: 200 }), 'inesperado'],
    ] as [() => Response, string][]) {
      cleanup()
      server({ open })
      render(PairingCode)
      await ask()
      expect(screen.getByTestId('room-error').textContent, text).toContain(text)
      expect(screen.queryByTestId('room-code')).toBeNull()
    }
    cleanup()
    vi.mocked(fetch).mockImplementation((async () => {
      throw new TypeError('offline')
    }) as never)
    render(PairingCode)
    await ask()
    expect(screen.getByTestId('room-error').textContent).toContain('falar com o servidor')
  })

  it('o que o servidor manda é mostrado como texto e só se for bem formado', async () => {
    for (const d of ['12345,10', '1234567,10', 'abcdef,10', '<img src=x onerror=alert(1)>', '123456', '123456,999', ',', '']) {
      cleanup()
      server({ look: () => state(100, '10.0.0.1', d) })
      render(PairingCode)
      await ask()
      await vi.advanceTimersByTimeAsync(2000)
      expect(screen.queryByTestId('pairing-digits'), d).toBeNull()
    }
    cleanup()
    server({ look: () => state(999, '<b>x</b>192.168.1.5', '123456,10') })
    render(PairingCode)
    await ask()
    await vi.advanceTimersByTimeAsync(2000)
    expect(document.querySelector('b')).toBeNull()
    expect(screen.getByText(/fecha em 180 s/)).toBeTruthy()
  })

  it('uma resposta lenta não empilha consultas', async () => {
    let looks = 0
    vi.mocked(fetch).mockImplementation(((url: string, init?: RequestInit) => {
      if (url === '/server/pair/room' && init?.method === 'POST') return Promise.resolve(room())
      if (url === '/server/pair/room') {
        looks++
        return new Promise<Response>(() => {})
      }
      return Promise.resolve(new Response(null, { status: 204 }))
    }) as never)
    render(PairingCode)
    await ask()
    await vi.advanceTimersByTimeAsync(2500)
    expect(looks).toBe(1)
    await vi.advanceTimersByTimeAsync(8000)
    expect(looks).toBeLessThanOrEqual(4)
  })

  it('com a aba escondida não consulta', async () => {
    const calls = server({})
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true })
    render(PairingCode)
    await ask()
    await vi.advanceTimersByTimeAsync(6000)
    expect(calls.filter((c) => c.method === 'GET')).toHaveLength(0)
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false })
  })

  it('toques repetidos em "Gerar" não deixam salas penduradas', async () => {
    let n = 0
    const calls = server({ open: () => room('1000', (++n % 10).toString().repeat(32)) })
    render(PairingCode)
    await openBox()
    for (let i = 0; i < 5; i++) await fireEvent.click(screen.queryByTestId('room-open') ?? screen.getByText('Gerar outro código'))
    await vi.advanceTimersByTimeAsync(0)
    const opened = calls.filter((c) => c.url === '/server/pair/room' && c.method === 'POST').length
    const closed = calls.filter((c) => c.url === '/server/pair/room/close').length
    expect(opened - closed).toBe(1) // every room but the last was closed: none is left hanging
  })
})
