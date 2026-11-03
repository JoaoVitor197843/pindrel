import { cleanup, fireEvent, render, screen } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { selection } from '../../stores/servers.svelte'
import PairingCode from './PairingCode.svelte'

const sas = (digits = '123456', left = 48, from = '192.168.1.5') => new Response(`d=${digits},${left},${from}\n`, { status: 200 })
const many = (...r: [string, number, string][]) => new Response(r.map(([d, l, f]) => `d=${d},${l},${f}\n`).join(''), { status: 200 })

// the shared setup resets the global fetch before every test; each test gives it the answers it needs
const fetchWith = (impl: (...a: never[]) => unknown) => vi.mocked(fetch).mockImplementation(impl as never)

beforeEach(() => {
  vi.useFakeTimers()
  selection.tlsOffered = true
})
afterEach(() => {
  cleanup()
  vi.useRealTimers()
  selection.tlsOffered = false
})

async function open() {
  const details = screen.getByTestId('pairing-code') as HTMLDetailsElement
  details.open = true
  await fireEvent(details, new Event('toggle'))
  await vi.advanceTimersByTimeAsync(0)
}

describe('PairingCode (os 6 números na tela de login)', () => {
  it('não aparece quando o servidor não tem lado seguro', () => {
    selection.tlsOffered = false
    render(PairingCode)
    expect(screen.queryByTestId('pairing-code')).toBeNull()
  })

  it('fechado, não consulta o servidor', async () => {
    const f = fetchWith(async () => sas())
    render(PairingCode)
    await vi.advanceTimersByTimeAsync(10_000)
    expect(f).not.toHaveBeenCalled()
  })

  it('aberto, sem pareamento: diz que ninguém está pareando', async () => {
    fetchWith(async () => new Response(null, { status: 204 }))
    render(PairingCode)
    await open()
    expect(screen.getByText(/Nenhum aparelho está pareando agora/)).toBeTruthy()
  })

  it('mostra os 6 números agrupados, o aparelho e o tempo, e some quando o pareamento termina', async () => {
    let answer: () => Response = () => sas()
    fetchWith(async () => answer())
    render(PairingCode)
    await open()
    const el = screen.getByTestId('pairing-digits')
    expect(el.textContent?.trim()).toBe('123 456')
    expect(el.getAttribute('aria-label')).toBe('Número de conferência: 1 2 3 4 5 6')
    expect(screen.getByText(/aparelho 192\.168\.1\.5/)).toBeTruthy()
    expect(screen.getByText('48 s')).toBeTruthy()
    answer = () => new Response(null, { status: 204 })
    await vi.advanceTimersByTimeAsync(2000)
    expect(screen.queryByTestId('pairing-digits')).toBeNull()
  })

  it('consulta de 2 em 2 segundos e para ao fechar', async () => {
    const f = fetchWith(async () => new Response(null, { status: 204 }))
    render(PairingCode)
    await open()
    expect(f).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(6000)
    expect(f).toHaveBeenCalledTimes(4)
    const details = screen.getByTestId('pairing-code') as HTMLDetailsElement
    details.open = false
    await fireEvent(details, new Event('toggle'))
    await vi.advanceTimersByTimeAsync(20_000)
    expect(f).toHaveBeenCalledTimes(4)
  })

  it('uma resposta lenta não empilha consultas', async () => {
    let calls = 0
    fetchWith(() => {
      calls++
      return new Promise<Response>(() => {})
    })
    render(PairingCode)
    await open()
    await vi.advanceTimersByTimeAsync(2500)
    expect(calls).toBe(1)
    await vi.advanceTimersByTimeAsync(1000) // the 3 s limit gives up, the next tick asks again
    await vi.advanceTimersByTimeAsync(4000)
    expect(calls).toBeLessThanOrEqual(3)
  })

  it('vários aparelhos pareando: uma linha para cada, com o endereço, e some só a que terminou', async () => {
    let answer: () => Response = () => many(['111111', 50, '192.168.1.5'], ['222222', 40, '192.168.1.9'], ['333333', 10, '10.0.0.4'])
    fetchWith(async () => answer())
    render(PairingCode)
    await open()
    const rows = screen.getAllByTestId('pairing-digits').map((e) => e.textContent?.trim())
    expect(rows).toEqual(['111 111', '222 222', '333 333'])
    expect(screen.getByText('aparelho 192.168.1.9')).toBeTruthy()
    expect(screen.getByText('aparelho 10.0.0.4')).toBeTruthy()
    answer = () => many(['111111', 48, '192.168.1.5'], ['333333', 8, '10.0.0.4'])
    await vi.advanceTimersByTimeAsync(2000)
    expect(screen.getAllByTestId('pairing-digits').map((e) => e.textContent?.trim())).toEqual(['111 111', '333 333'])
  })

  it('o que o servidor manda é mostrado como texto, só linhas bem formadas, e no máximo 64', async () => {
    for (const body of ['d=12345,10,1.2.3.4\n', 'd=1234567,10,1.2.3.4\n', 'd=abcdef,10,1.2.3.4\n', 'd=123456,10,<img src=x onerror=alert(1)>\n', '', 'lixo', 'sas=123456\n', 'd=123456,10\n', 'd=123456,abc,1.2.3.4\n']) {
      cleanup()
      fetchWith(async () => new Response(body, { status: 200 }))
      render(PairingCode)
      await open()
      expect(screen.queryByTestId('pairing-digits'), body).toBeNull()
    }
    cleanup()
    fetchWith(async () => many(['123456', 99, '192.168.1.5']))
    render(PairingCode)
    await open()
    expect(screen.getByText('60 s')).toBeTruthy()
    cleanup()
    const lots = Array.from({ length: 200 }, (_, i) => ['123456', 10, `10.0.${i >> 8}.${i & 255}`] as [string, number, string])
    fetchWith(async () => many(...lots))
    render(PairingCode)
    await open()
    expect(screen.getAllByTestId('pairing-digits').length).toBe(64)
    expect(document.querySelector('img')).toBeNull()
  })

  it('erro de rede ou 404 (fora da rede local): avisa, sem quebrar', async () => {
    fetchWith(async () => { throw new TypeError('offline') })
    render(PairingCode)
    await open()
    expect(screen.getByText(/Não foi possível consultar/)).toBeTruthy()
    cleanup()
    fetchWith(async () => new Response('not found', { status: 404 }))
    render(PairingCode)
    await open()
    expect(screen.getByText(/Não foi possível consultar/)).toBeTruthy()
  })

  it('com a aba escondida não consulta', async () => {
    const f = fetchWith(async () => new Response(null, { status: 204 }))
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true })
    render(PairingCode)
    await open()
    await vi.advanceTimersByTimeAsync(6000)
    expect(f).not.toHaveBeenCalled()
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false })
  })
})
