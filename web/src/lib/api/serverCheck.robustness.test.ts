import { afterEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { findServer, inspect, parseAddress } from './serverCheck'

afterEach(() => vi.useRealTimers())

const good = () =>
  new Response(ServerInfo.encode({ name: 'Casa', registrationEnabled: true }).finish() as BodyInit, {
    headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': 'abc' },
  })

/** A request that never answers, but notices when it is given up on. */
const hangs = (aborted: string[]) => (url: string, init: RequestInit) =>
  new Promise<Response>((_, reject) => {
    const stop = () => {
      aborted.push(url)
      reject(new Error('abort'))
    }
    // like the real fetch: a signal that is already aborted rejects at once
    if (init.signal?.aborted) stop()
    else init.signal?.addEventListener('abort', stop)
  })

describe('endereços escritos de outro jeito são o mesmo servidor', () => {
  it.each([
    ['Casa.COM', 'casa.com'],
    ['casa.com.', 'casa.com'],
    ['http://casa.com./', 'casa.com'],
    ['0x7f.1:8080', '127.0.0.1'],
    ['CASA.com:0080', 'casa.com'],
  ])('%s -> %s', (typed, host) => {
    const r = parseAddress(typed)
    expect(r.ok && r.address.hostname).toBe(host)
  })

  it('dois pontos finais ou ponto no começo continuam inválidos', () => {
    for (const t of ['casa.com..', '.casa.com', 'casa..com', '-casa.com']) expect(parseAddress(t).ok).toBe(false)
  })
})

describe('http e https em paralelo', () => {
  it('um servidor só com https responde em ~250 ms, não depois do tempo limite do http', async () => {
    const aborted: string[] = []
    vi.mocked(fetch).mockImplementation(((url: string, init: RequestInit) =>
      url.startsWith('https:') ? Promise.resolve(good()) : hangs(aborted)(url, init)) as typeof fetch)
    const t0 = Date.now()
    const r = await findServer('casa.com')
    expect(r).toMatchObject({ ok: true, origin: 'https://casa.com' })
    expect(Date.now() - t0).toBeLessThan(1500)
    expect(aborted).toEqual(['http://casa.com/server/info/']) // the loser does not outlive the call
  })

  it('se o http responde, o https nem chega a ser pedido', async () => {
    const asked: string[] = []
    vi.mocked(fetch).mockImplementation((async (url: string) => {
      asked.push(url)
      return good()
    }) as typeof fetch)
    await findServer('casa.com')
    expect(asked).toEqual(['http://casa.com/server/info/'])
  })

  it('o http recusado na hora passa a vez ao https sem esperar os 250 ms', async () => {
    vi.mocked(fetch).mockImplementation((async (url: string) => {
      if (url.startsWith('http:')) throw new TypeError('refused')
      return good()
    }) as typeof fetch)
    const t0 = Date.now()
    expect(await findServer('casa.com')).toMatchObject({ ok: true, origin: 'https://casa.com' })
    expect(Date.now() - t0).toBeLessThan(200)
  })

  it('cancelar de fora aborta os dois pedidos', async () => {
    const aborted: string[] = []
    vi.mocked(fetch).mockImplementation(hangs(aborted) as unknown as typeof fetch)
    const controller = new AbortController()
    const p = findServer('casa.com', controller.signal)
    await new Promise((r) => setTimeout(r, 300)) // past the stagger: both are in flight
    controller.abort()
    expect((await p).ok).toBe(false)
    expect(aborted.sort()).toEqual(['http://casa.com/server/info/', 'https://casa.com/server/info/'])
  })

  it('já cancelado antes de começar não pede nada de útil e termina', async () => {
    vi.mocked(fetch).mockImplementation(hangs([]) as unknown as typeof fetch)
    const controller = new AbortController()
    controller.abort()
    expect((await findServer('casa.com', controller.signal)).ok).toBe(false)
  })
})

describe('respostas hostis', () => {
  it('um corpo sem fim é cortado em 4 KiB e a conexão é cancelada', async () => {
    let cancelled = false
    let sent = 0
    const stream = new ReadableStream<Uint8Array>({
      pull(c) {
        sent += 1024
        c.enqueue(new Uint8Array(1024))
      },
      cancel() {
        cancelled = true
      },
    })
    vi.mocked(fetch).mockResolvedValue(
      new Response(stream, { headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': 'abc' } }),
    )
    expect(await inspect('http://evil.test')).toEqual({ ok: false, reason: 'invalid' })
    expect(cancelled).toBe(true)
    expect(sent).toBeLessThan(64 * 1024)
  })

  it('um corpo que goteja devagar para sempre acaba em "timeout"', async () => {
    vi.useFakeTimers()
    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(new Uint8Array([1]))
      },
      pull: () => new Promise(() => {}),
    })
    vi.mocked(fetch).mockResolvedValue(
      new Response(stream, { headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': 'abc' } }),
    )
    const p = inspect('http://slow.test')
    await vi.advanceTimersByTimeAsync(4100)
    expect(await p).toEqual({ ok: false, reason: 'timeout' })
  })

  it('sem corpo legível não carrega nada na memória: é recusado', async () => {
    const res = good()
    Object.defineProperty(res, 'body', { value: null })
    vi.mocked(fetch).mockResolvedValue(res)
    expect(await inspect('http://nobody.test')).toEqual({ ok: false, reason: 'invalid' })
  })

  it('cabeçalhos estranhos: id com lixo, tipo errado, status 500, redirecionamento para outro host', async () => {
    const bad = [
      new Response(ServerInfo.encode({ name: 'x', registrationEnabled: true }).finish() as BodyInit, { headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': 'a b<script>' } }),
      new Response('<html>', { headers: { 'content-type': 'text/html', 'x-pindrel-id': 'abc' } }),
      new Response('boom', { status: 500, headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': 'abc' } }),
    ]
    for (const res of bad) {
      vi.mocked(fetch).mockResolvedValueOnce(res)
      expect((await inspect('http://x.test')).ok).toBe(false)
    }
    const moved = good()
    Object.defineProperty(moved, 'url', { value: 'http://other.test/server/info/' })
    vi.mocked(fetch).mockResolvedValueOnce(moved)
    expect(await inspect('http://x.test')).toEqual({ ok: false, reason: 'invalid' })
  })

  it('bytes aleatórios no lugar do protobuf nunca lançam', async () => {
    for (let i = 0; i < 200; i++) {
      const bytes = new Uint8Array(1 + (i % 64)).map(() => Math.floor(Math.random() * 256))
      vi.mocked(fetch).mockResolvedValueOnce(
        new Response(bytes as BodyInit, { headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': 'abc' } }),
      )
      await expect(inspect('http://noise.test')).resolves.toBeDefined()
    }
  })
})
