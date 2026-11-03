import { cleanup, fireEvent, render, screen } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { selection } from '../../stores/servers.svelte'
import PairingCode from './PairingCode.svelte'

const sas = (digits = '123456', left = 48, from = '192.168.1.5') => new Response(`sas=${digits}\nleft=${left}\nfrom=${from}\n`, { status: 200 })

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
    expect(screen.getByText(/mais 48 s/)).toBeTruthy()
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

  it('o que o servidor manda é mostrado como texto e só se for 6 dígitos', async () => {
    for (const body of ['sas=12345\n', 'sas=1234567\n', 'sas=abcdef\n', 'sas=<img src=x onerror=alert(1)>\n', '', 'lixo', 'sas=123456 \nsas=999999']) {
      cleanup()
      fetchWith(async () => new Response(body, { status: 200 }))
      render(PairingCode)
      await open()
      if (body.startsWith('sas=123456')) continue
      expect(screen.queryByTestId('pairing-digits'), body).toBeNull()
    }
    cleanup()
    fetchWith(async () => sas('123456', 999, '<b>x</b>192.168.1.5'))
    render(PairingCode)
    await open()
    expect(document.querySelector('b')).toBeNull()
    expect(screen.getByText(/mais 60 s/)).toBeTruthy()
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
