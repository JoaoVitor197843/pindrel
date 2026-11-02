import { afterEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { errorText, findServer, inspect, MAX_INPUT_LENGTH, parseAddress } from './serverCheck'

const realLocation = window.location
afterEach(() => {
  vi.stubGlobal('location', realLocation)
  vi.useRealTimers()
})

const body = (name = 'Casa') => ServerInfo.encode({ name, registrationEnabled: true }).finish()

function reply(over: { status?: number; type?: string | null; id?: string | null; bytes?: Uint8Array; url?: string } = {}) {
  const headers = new Headers()
  if (over.type !== null) headers.set('content-type', over.type ?? 'application/x-protobuf')
  if (over.id !== null) headers.set('x-plany-id', over.id ?? 'abc123')
  const res = new Response((over.bytes ?? body()) as BodyInit, { status: over.status ?? 200, headers })
  if (over.url) Object.defineProperty(res, 'url', { value: over.url })
  return res
}

/** Answers per origin; an origin that is not listed refuses the connection. */
function servers(map: Record<string, () => Response>) {
  const calls: string[] = []
  vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
    if (init?.mode !== 'no-cors') calls.push(url) // the follow-up "is anyone there" question is not a check
    const make = map[new URL(url).origin]
    if (!make) throw new TypeError('network')
    return make()
  }) as typeof fetch)
  return calls
}

function hang() {
  vi.mocked(fetch).mockImplementation(((_: string, init: RequestInit) =>
    new Promise((_, reject) => init.signal?.addEventListener('abort', () => reject(new Error('abort'))))) as typeof fetch)
}

describe('parseAddress', () => {
  it.each([
    ['192.168.0.20:8095', undefined, '192.168.0.20', '8095'],
    ['  meu.servidor.com  ', undefined, 'meu.servidor.com', ''],
    ['MEU.Servidor.COM/', undefined, 'meu.servidor.com', ''],
    ['http://casa.local:8080', 'http', 'casa.local', '8080'],
    ['HTTPS://casa.local', 'https', 'casa.local', ''],
    ['https://casa.local:80', 'https', 'casa.local', '80'],
    ['[fe80::1]:9000', undefined, '[fe80::1]', '9000'],
    ['servidor', undefined, 'servidor', ''],
  ])('aceita %s', (input, scheme, hostname, port) => {
    expect(parseAddress(input)).toEqual({ ok: true, address: { scheme, hostname, port } })
  })

  it.each([
    '',
    '   ',
    'a b',
    'a\tb',
    'ftp://x.com',
    'javascript:alert(1)',
    'http://',
    'host:',
    'host:0',
    'host:65536',
    'host:abc',
    'user@host',
    'http://user:pw@host',
    'host/path',
    'host/auth/login/',
    'host?x=1',
    'host#x',
    '-host.com',
    'host..com',
    'ho_st.com',
    '::1',
    '[::1',
    '../../etc',
    'c:\\windows',
    'x'.repeat(MAX_INPUT_LENGTH + 1),
    '<script>',
  ])('recusa %j', (input) => {
    expect(parseAddress(input).ok).toBe(false)
  })

  it('texto vazio é "empty", o resto é "invalid"', () => {
    expect(parseAddress('  ')).toEqual({ ok: false, error: 'empty' })
    expect(parseAddress('a b')).toEqual({ ok: false, error: 'invalid' })
  })

  it('um texto enorme ou estranho nunca lança', () => {
    for (const t of ['\u0000', '😀', 'é.com', 'x'.repeat(100_000), '%'.repeat(50), 'http://' + 'a.'.repeat(200)]) {
      expect(() => parseAddress(t)).not.toThrow()
    }
  })
})

describe('inspect', () => {
  it('um gateway válido devolve nome e id', async () => {
    servers({ 'https://a.com': () => reply({ id: 'xyz-1' }) })
    expect(await inspect('https://a.com')).toEqual({ ok: true, name: 'Casa', serverId: 'xyz-1', origin: 'https://a.com' })
  })

  it('sem resposta é inalcançável', async () => {
    servers({})
    expect(await inspect('https://a.com')).toEqual({ ok: false, reason: 'unreachable' })
  })

  it.each([
    ['status de erro', { status: 500 }],
    ['404 (uma API sem gateway não é um gateway)', { status: 404 }],
    ['sem id (não é um gateway)', { id: null }],
    ['id com lixo', { id: 'a b<' }],
    ['id gigante', { id: 'a'.repeat(65) }],
    ['tipo errado', { type: 'text/html' }],
    ['sem tipo', { type: null }],
    ['corpo que não é protobuf', { bytes: new TextEncoder().encode('<html>oi</html>') }],
    ['nome vazio', { bytes: body('') }],
    ['nome grande demais', { bytes: body('n'.repeat(65)) }],
    ['corpo grande demais', { bytes: new Uint8Array(5000).fill(0) }],
  ])('%s é inválido', async (_, over) => {
    servers({ 'https://a.com': () => reply(over) })
    expect(await inspect('https://a.com')).toEqual({ ok: false, reason: 'invalid' })
  })

  it('segue o redirecionamento entre http e https do mesmo host e guarda a origem final', async () => {
    servers({ 'http://a.com': () => reply({ url: 'https://a.com/server/info/' }) })
    expect(await inspect('http://a.com')).toMatchObject({ ok: true, origin: 'https://a.com' })
  })

  it('redirecionar para outro host é inválido', async () => {
    servers({ 'http://a.com': () => reply({ url: 'http://outro.com/server/info/' }) })
    expect(await inspect('http://a.com')).toEqual({ ok: false, reason: 'invalid' })
  })

  it('não responder dentro do tempo é inalcançável', async () => {
    vi.useFakeTimers()
    hang()
    const p = inspect('http://a.com')
    await vi.advanceTimersByTimeAsync(5000)
    expect(await p).toEqual({ ok: false, reason: 'timeout' })
  })

  it('responde mas o navegador não deixa ler (CORS) é "blocked", diferente de ninguém responder', async () => {
    vi.mocked(fetch).mockImplementation((async (_: string, init?: RequestInit) => {
      if (init?.mode === 'no-cors') return new Response(null)
      throw new TypeError('Failed to fetch')
    }) as typeof fetch)
    expect(await inspect('http://a.com')).toEqual({ ok: false, reason: 'blocked' })
    servers({})
    expect(await inspect('http://a.com')).toEqual({ ok: false, reason: 'unreachable' })
  })

  it('cancelar pelo sinal interrompe a pergunta', async () => {
    hang()
    const c = new AbortController()
    const p = inspect('http://a.com', c.signal)
    c.abort()
    expect(await p).toEqual({ ok: false, reason: 'unreachable' })
  })

  it('pergunta sem credenciais e sem cache', async () => {
    servers({ 'http://a.com': () => reply() })
    await inspect('http://a.com')
    const init = vi.mocked(fetch).mock.calls[0][1] as RequestInit
    expect(init.credentials).toBe('omit')
    expect(init.cache).toBe('no-store')
  })
})

describe('findServer', () => {
  it('sem esquema tenta http primeiro', async () => {
    const calls = servers({ 'http://a.com': () => reply(), 'https://a.com': () => reply() })
    expect(await findServer('a.com')).toMatchObject({ ok: true, origin: 'http://a.com' })
    expect(calls).toEqual(['http://a.com/server/info/'])
  })

  it('sem esquema cai para https se o http não responde', async () => {
    const calls = servers({ 'https://a.com:8443': () => reply() })
    expect(await findServer('a.com:8443')).toMatchObject({ ok: true, origin: 'https://a.com:8443' })
    expect(calls).toEqual(['http://a.com:8443/server/info/', 'https://a.com:8443/server/info/'])
  })

  it('com esquema explícito tenta só ele', async () => {
    const calls = servers({ 'https://a.com': () => reply() })
    expect(await findServer('http://a.com')).toMatchObject({ ok: false, error: 'unreachable', host: 'a.com' })
    expect(calls).toEqual(['http://a.com/server/info/'])
    expect(await findServer('https://a.com')).toMatchObject({ ok: true })
  })

  it('http que redireciona para https termina em https', async () => {
    servers({ 'http://a.com': () => reply({ url: 'https://a.com/server/info/' }) })
    expect(await findServer('http://a.com')).toMatchObject({ ok: true, origin: 'https://a.com' })
  })

  it('um servidor web qualquer é "invalid-server", não "unreachable"', async () => {
    servers({ 'http://a.com': () => reply({ type: 'text/html', id: null }) })
    expect(await findServer('a.com')).toEqual({ ok: false, error: 'invalid-server', host: 'a.com' })
  })

  it('numa página https só tenta https; http explícito explica o bloqueio', async () => {
    vi.stubGlobal('location', { ...window.location, protocol: 'https:', origin: 'https://app.com' })
    const calls = servers({})
    expect(await findServer('a.com')).toMatchObject({ ok: false, error: 'unreachable' })
    expect(calls).toEqual(['https://a.com/server/info/'])
    expect(await findServer('http://a.com')).toMatchObject({ ok: false, error: 'mixed' })
  })

  it('cada falha tem a sua mensagem, e a mais informativa vence entre http e https', async () => {
    vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
      if (init?.mode === 'no-cors') return new Response(null)
      throw new TypeError(url)
    }) as typeof fetch)
    const blocked = await findServer('a.com')
    expect(blocked).toMatchObject({ ok: false, error: 'blocked' })
    expect(errorText(blocked as never)).toContain('CORS')
    servers({})
    const refused = await findServer('a.com')
    expect(errorText(refused as never)).toContain('recusada')
    expect(errorText(refused as never)).toContain('certificado')
    expect(errorText((await findServer('http://a.com')) as never)).not.toContain('certificado')
    hang()
    vi.useFakeTimers()
    const p = findServer('https://a.com')
    await vi.advanceTimersByTimeAsync(5000)
    expect(errorText((await p) as never)).toContain('a tempo')
  })

  it('endereço inválido nem chega à rede', async () => {
    const calls = servers({})
    expect(await findServer('a b')).toEqual({ ok: false, error: 'invalid' })
    expect(await findServer('')).toEqual({ ok: false, error: 'empty' })
    expect(calls).toEqual([])
  })

  it('uma porta 80 com https é mesmo a porta 80', async () => {
    const calls = servers({})
    await findServer('https://a.com:80')
    expect(calls).toEqual(['https://a.com:80/server/info/'])
  })
})
