import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { embedded, lanAddress, selection } from './servers.svelte'

const answer = (status: number) => vi.mocked(fetch).mockImplementation(async () => new Response(null, { status }))
const down = () => vi.mocked(fetch).mockImplementation(async () => Promise.reject(new TypeError('rede caiu')))

beforeEach(() => {
  selection.health = 'connected'
  selection.address = null
  // resets the failure count left by earlier tests
  answer(200)
})

describe('selection.check', () => {
  it('uma falha solta não derruba o status; duas seguidas sim', async () => {
    await selection.check()
    down()
    await selection.check()
    expect(selection.health).toBe('connected')
    await selection.check()
    expect(selection.health).toBe('disconnected')
  })

  it('o primeiro sucesso volta a conectado e zera a contagem', async () => {
    down()
    await selection.check()
    await selection.check()
    answer(200)
    await selection.check()
    expect(selection.health).toBe('connected')
    down()
    await selection.check()
    expect(selection.health).toBe('connected') // started over from zero
  })

  it.each([200, 404, 429])('resposta %i prova que o servidor está lá', async (status) => {
    answer(status)
    await selection.check()
    await selection.check()
    expect(selection.health).toBe('connected')
  })

  it.each([500, 502, 503])('erro %i do servidor conta como falha', async (status) => {
    answer(status)
    await selection.check()
    await selection.check()
    expect(selection.health).toBe('disconnected')
  })

  it('sem resposta no prazo é falha', async () => {
    vi.useFakeTimers()
    try {
      vi.mocked(fetch).mockImplementation(
        (_url, init) =>
          new Promise((_, reject) => init?.signal?.addEventListener('abort', () => reject(new DOMException('x', 'AbortError')))),
      )
      for (let i = 0; i < 2; i++) {
        const done = selection.check()
        await vi.advanceTimersByTimeAsync(3000)
        await done
      }
      expect(selection.health).toBe('disconnected')
    } finally {
      vi.useRealTimers()
    }
  })

  it('cancelado no meio não muda o status', async () => {
    const controller = new AbortController()
    vi.mocked(fetch).mockImplementation(async () => {
      controller.abort()
      throw new DOMException('x', 'AbortError')
    })
    await selection.check(controller.signal)
    await selection.check(controller.signal)
    expect(selection.health).toBe('connected')
  })
})

describe('selection.watchHealth', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('consulta logo, a cada 10 s, e mais depressa depois de uma falha', async () => {
    const stop = selection.watchHealth()
    await vi.advanceTimersByTimeAsync(0)
    expect(fetch).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(9_999)
    expect(fetch).toHaveBeenCalledTimes(1)
    down()
    await vi.advanceTimersByTimeAsync(1)
    expect(fetch).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(3_000) // after failing: 3 s
    expect(fetch).toHaveBeenCalledTimes(3)
    expect(selection.health).toBe('disconnected')
    answer(200)
    await vi.advanceTimersByTimeAsync(3_000)
    expect(selection.health).toBe('connected')
    stop()
  })

  it('parar cancela tudo, e parar duas vezes não quebra', async () => {
    const stop = selection.watchHealth()
    await vi.advanceTimersByTimeAsync(0)
    stop()
    stop()
    await vi.advanceTimersByTimeAsync(60_000)
    expect(fetch).toHaveBeenCalledTimes(1)
  })

  it('aba escondida não consulta; ao reaparecer, consulta na hora', async () => {
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
    const stop = selection.watchHealth()
    await vi.advanceTimersByTimeAsync(30_000)
    expect(fetch).not.toHaveBeenCalled()
    hidden.mockReturnValue(false)
    document.dispatchEvent(new Event('visibilitychange'))
    await vi.advanceTimersByTimeAsync(0)
    expect(fetch).toHaveBeenCalledTimes(1)
    stop()
    hidden.mockRestore()
  })

  it('voltar a rede consulta na hora; eventos em rajada não empilham consultas', async () => {
    const stop = selection.watchHealth()
    await vi.advanceTimersByTimeAsync(0)
    vi.mocked(fetch).mockClear()
    for (let i = 0; i < 20; i++) window.dispatchEvent(new Event('online'))
    await vi.advanceTimersByTimeAsync(0)
    expect(fetch).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(10_000)
    expect(fetch).toHaveBeenCalledTimes(2) // a single cycle goes on, not twenty
    stop()
  })
})

describe('LAN address of the server', () => {
  const withHeader = (value: string | null) =>
    vi.mocked(fetch).mockImplementation(async () => new Response(null, { status: 200, headers: value === null ? {} : { 'x-pindrel-address': value } }))

  it('the page shows the address the gateway says the LAN uses', async () => {
    withHeader('192.168.1.163:8086')
    await selection.check()
    expect(selection.address).toBe('192.168.1.163:8086')
  })

  it('without the header (no gateway) or after it goes away, the page address is shown', async () => {
    withHeader('192.168.1.163:8086')
    await selection.check()
    withHeader(null)
    await selection.check()
    expect(selection.address).toBe(embedded.address)
  })

  it('a failed check keeps the last known address', async () => {
    withHeader('192.168.1.163:8086')
    await selection.check()
    down()
    await selection.check()
    expect(selection.address).toBe('192.168.1.163:8086')
  })

  it.each([
    '',
    'x',
    '192.168.1.163',
    '192.168.1.163:0',
    '192.168.1.163:99999',
    '192.168.1.163:80:80',
    '999.1.1.1:80',
    '127.0.0.1:8080',
    '169.254.169.254:80',
    '224.0.0.251:5353',
    'evil.example.com:80',
    '<img src=x onerror=alert(1)>:80',
    '192.168.1.163:8086\nSet-Cookie: a=b',
    '192.168.001.163:8086',
    '1'.repeat(10_000),
  ])('a bad value (%j) is ignored', (value) => {
    expect(lanAddress(value)).toBeNull()
  })

  it('good values pass, with stray spaces trimmed', () => {
    expect(lanAddress(' 10.0.0.5:8080 ')).toBe('10.0.0.5:8080')
    expect(lanAddress(null)).toBeNull()
  })
})

describe('address before the first answer', () => {
  it('a placeholder is shown, never the page host that may be localhost or a VPN address', () => {
    expect(selection.address).toBeNull()
    expect(selection.shownAddress).toBe('…')
  })

  it('the first check failing falls back to the page host, and a later header wins', async () => {
    down()
    await selection.check()
    expect(selection.shownAddress).toBe(embedded.address)
    vi.mocked(fetch).mockImplementation(
      async () => new Response(null, { status: 200, headers: { 'x-pindrel-address': '192.168.1.163:8086' } }),
    )
    await selection.check()
    expect(selection.shownAddress).toBe('192.168.1.163:8086')
  })

  it('an answer without the header (no gateway) also falls back to the page host', async () => {
    await selection.check()
    expect(selection.shownAddress).toBe(embedded.address)
  })

  it('a check cancelled before it ends leaves the placeholder', async () => {
    const controller = new AbortController()
    vi.mocked(fetch).mockImplementation(async () => {
      controller.abort()
      throw new DOMException('x', 'AbortError')
    })
    await selection.check(controller.signal)
    expect(selection.shownAddress).toBe('…')
  })
})
