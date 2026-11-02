import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { stubLocalStorage } from '../../test/storage'
import { cleanName, ManualServers, MAX_MANUAL, reach } from './manual.svelte'
import { navigation, selection } from './servers.svelte'
import { toast } from './toast.svelte'
import { remember, trustOf } from './trust'

let data: Map<string, string>
beforeEach(() => {
  data = stubLocalStorage()
  selection.connecting = null
  selection.pendingChange = null
})

/** Plany gateways by host, with their id and name; anything else refuses the connection. */
function network(table: Record<string, { id: string; name?: string } | 'web'>) {
  vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
    const u = new URL(url)
    const entry = table[u.host]
    if (!entry) throw new TypeError('network')
    if (init?.mode === 'no-cors') return new Response(null)
    if (entry === 'web') return new Response('<html></html>', { headers: { 'content-type': 'text/html' } })
    return new Response(ServerInfo.encode({ name: entry.name ?? 'Casa', registrationEnabled: true }).finish(), {
      headers: { 'content-type': 'application/x-protobuf', 'x-plany-id': entry.id },
    })
  }) as typeof fetch)
}

describe('adicionar', () => {
  it('só salva depois de confirmar que é um gateway, usa o nome do servidor e guarda no navegador', async () => {
    network({ 'casa.com': { id: 'aaa' } })
    const m = new ManualServers()
    const r = await m.add('casa.com', '')
    expect(r).toMatchObject({ ok: true, server: { name: 'Casa', url: 'http://casa.com', address: 'casa.com', serverId: 'aaa' } })
    expect(m.list).toHaveLength(1)
    expect(JSON.parse(data.get('plany:manual-servers')!)).toHaveLength(1)
    expect(trustOf('Casa', 'aaa')).toBe('same')
    expect(new ManualServers().list).toEqual(m.list) // survives a reload
  })

  it('o nome digitado substitui o do servidor, mas a confiança segue o nome do servidor', async () => {
    network({ 'casa.com': { id: 'aaa' } })
    const m = new ManualServers()
    const r = await m.add('casa.com', '  Meu   sítio  ')
    expect(r).toMatchObject({ ok: true, server: { name: 'Meu sítio', trustName: 'Casa' } })
    expect(trustOf('Casa', 'aaa')).toBe('same')
    expect(trustOf('Meu sítio', 'aaa')).toBe('new')
  })

  it('um servidor web comum, ou um que não responde, não é adicionado', async () => {
    network({ 'web.com': 'web' })
    const m = new ManualServers()
    expect(await m.add('web.com', '')).toMatchObject({ ok: false, error: expect.stringContaining('não é um servidor Plany') })
    expect(await m.add('fora.com', '')).toMatchObject({ ok: false, error: expect.stringContaining('Não foi possível conectar') })
    expect(await m.add('a b', '')).toMatchObject({ ok: false })
    expect(m.list).toEqual([])
    expect(data.get('plany:manual-servers')).toBeUndefined()
  })

  it('recusa repetido, o mesmo servidor por outro endereço e a própria página', async () => {
    network({ 'a.com': { id: 'aaa' }, 'b.com': { id: 'aaa', name: 'Outro' }, [window.location.host]: { id: 'zzz' } })
    const m = new ManualServers()
    await m.add('a.com', '')
    expect(await m.add('a.com', '')).toMatchObject({ ok: false, error: 'Este servidor já foi adicionado.' })
    expect(await m.add('http://a.com/', '')).toMatchObject({ ok: false })
    expect(await m.add('b.com', '')).toMatchObject({ ok: false, error: expect.stringContaining('outro endereço') })
    expect(await m.add(window.location.host, '')).toMatchObject({ ok: false, error: 'Este é o servidor desta página.' })
    expect(m.list).toHaveLength(1)
  })

  it('respeita o limite', async () => {
    const table: Record<string, { id: string }> = {}
    for (let i = 0; i <= MAX_MANUAL; i++) table[`h${i}.com`] = { id: `id${i}` }
    network(table)
    const m = new ManualServers()
    for (let i = 0; i < MAX_MANUAL; i++) expect((await m.add(`h${i}.com`, '')).ok).toBe(true)
    expect(await m.add(`h${MAX_MANUAL}.com`, '')).toMatchObject({ ok: false, error: expect.stringContaining('Limite') })
    expect(m.list).toHaveLength(MAX_MANUAL)
  })

  it('toques repetidos em "Adicionar" verificam uma vez só', async () => {
    network({ 'a.com': { id: 'aaa' } })
    const m = new ManualServers()
    const results = await Promise.all([m.add('a.com', ''), m.add('a.com', ''), m.add('a.com', '')])
    expect(results.filter((r) => r.ok)).toHaveLength(1)
    expect(m.list).toHaveLength(1)
  })

  it('cancelar no meio não adiciona nada e o próximo pedido funciona', async () => {
    vi.mocked(fetch).mockImplementation(((_: string, init: RequestInit) =>
      new Promise((_, reject) => init.signal?.addEventListener('abort', () => reject(new Error('abort'))))) as typeof fetch)
    const m = new ManualServers()
    const c = new AbortController()
    const p = m.add('a.com', '', c.signal)
    c.abort()
    expect(await p).toEqual({ ok: false, error: 'Cancelado.' })
    expect(m.list).toEqual([])
    network({ 'a.com': { id: 'aaa' } })
    expect((await m.add('a.com', '')).ok).toBe(true)
  })

  it('um nome já aberto com outro id não é sobrescrito em silêncio: ao abrir, pergunta', async () => {
    remember('Casa', 'antigo')
    network({ 'a.com': { id: 'novo' } })
    const m = new ManualServers()
    expect((await m.add('a.com', '')).ok).toBe(true)
    expect(trustOf('Casa', 'antigo')).toBe('same')
    expect(trustOf('Casa', 'novo')).toBe('changed')
  })

  it('nomes absurdos são limpos', () => {
    expect(cleanName('  a \n\t b  ')).toBe('a b')
    expect(cleanName('x'.repeat(500))).toHaveLength(64)
    expect(cleanName('   ')).toBe('')
  })
})

describe('remover e carregar', () => {
  it('remover tira da lista e do armazenamento', async () => {
    network({ 'a.com': { id: 'aaa' } })
    const m = new ManualServers()
    await m.add('a.com', '')
    m.remove('http://a.com')
    m.remove('http://a.com') // twice: nothing happens
    expect(m.list).toEqual([])
    expect(JSON.parse(data.get('plany:manual-servers')!)).toEqual([])
    expect(m.health).toEqual({})
  })

  it.each([
    ['lixo', 'isto não é json'],
    ['objeto', '{"a":1}'],
    ['itens quebrados', '[1,null,"x",{"id":"http://a.com"}]'],
    ['url de outro esquema', JSON.stringify([{ id: 'javascript:alert(1)', name: 'x', trustName: 'x', serverId: 'a', url: 'javascript:alert(1)', address: '' }])],
    ['url com caminho', JSON.stringify([{ id: 'http://a.com/x', name: 'x', trustName: 'x', serverId: 'a', url: 'http://a.com/x', address: 'a.com' }])],
    ['nome vazio', JSON.stringify([{ id: 'http://a.com', name: '', trustName: 'x', serverId: 'a', url: 'http://a.com', address: 'a.com' }])],
  ])('armazenamento estragado (%s) vira lista vazia', (_, raw) => {
    data.set('plany:manual-servers', raw)
    expect(new ManualServers().list).toEqual([])
  })

  it('sem localStorage funciona na sessão', async () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new Error('blocked')
      },
      setItem: () => {
        throw new Error('blocked')
      },
    })
    network({ 'a.com': { id: 'aaa' } })
    const m = new ManualServers()
    expect((await m.add('a.com', '')).ok).toBe(true)
    expect(m.list).toHaveLength(1)
  })
})

describe('saúde de cada servidor', () => {
  it('cai para desconectado só na segunda falha seguida e volta na primeira resposta', async () => {
    network({ 'a.com': { id: 'aaa' } })
    const m = new ManualServers()
    await m.add('a.com', '')
    expect(m.health['http://a.com']).toBe('connected')
    network({})
    await m.check()
    expect(m.health['http://a.com']).toBe('connected')
    await m.check()
    expect(m.health['http://a.com']).toBe('disconnected')
    await m.check()
    expect(m.health['http://a.com']).toBe('disconnected')
    network({ 'a.com': { id: 'aaa' } })
    await m.check()
    expect(m.health['http://a.com']).toBe('connected')
  })

  it('cada servidor tem a sua saúde', async () => {
    network({ 'a.com': { id: 'aaa' }, 'b.com': { id: 'bbb', name: 'B' } })
    const m = new ManualServers()
    await m.add('a.com', '')
    await m.add('b.com', '')
    network({ 'a.com': { id: 'aaa' } })
    await m.check()
    await m.check()
    expect(m.health).toEqual({ 'http://a.com': 'connected', 'http://b.com': 'disconnected' })
  })

  it('um servidor removido durante a checagem não volta', async () => {
    network({ 'a.com': { id: 'aaa' } })
    const m = new ManualServers()
    await m.add('a.com', '')
    const p = m.check()
    m.remove('http://a.com')
    await p
    expect(m.health).toEqual({})
  })

  it('reach: qualquer resposta conta, sem resposta não', async () => {
    network({ 'a.com': 'web' })
    expect(await reach('http://a.com')).toBe(true)
    expect(await reach('http://b.com')).toBe(false)
  })

  it('sem servidores adicionados não consulta nada', async () => {
    const m = new ManualServers()
    const stop = m.start()
    await Promise.resolve()
    expect(fetch).not.toHaveBeenCalled()
    stop()
  })
})

describe('abrir um servidor adicionado', () => {
  async function added(id = 'aaa') {
    network({ 'a.com': { id } })
    const { manual } = await import('./manual.svelte')
    manual.list = []
    const r = await manual.add('a.com', 'Meu')
    if (!r.ok) throw new Error(r.error)
    return { manual, option: { id: r.server.id, name: r.server.name, address: r.server.address, url: r.server.url, serverId: r.server.serverId, manual: true, trustName: r.server.trustName } }
  }

  it('confere quem responde e vai até lá', async () => {
    const { option } = await added()
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await selection.open(option)
    expect(go).toHaveBeenCalledWith('http://a.com')
    go.mockRestore()
  })

  it('outro id sob o mesmo nome pergunta antes, e confirmar vai', async () => {
    const { option } = await added('aaa')
    network({ 'a.com': { id: 'trocado' } })
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await selection.open(option)
    expect(go).not.toHaveBeenCalled()
    expect(selection.pendingChange?.serverId).toBe('trocado')
    expect(selection.connecting).toBeNull()
    selection.confirmChange()
    await vi.waitFor(() => expect(go).toHaveBeenCalledWith('http://a.com'))
    expect(trustOf('Casa', 'trocado')).toBe('same')
    go.mockRestore()
  })

  it('cancelar a pergunta fica onde está', async () => {
    const { option } = await added('aaa')
    network({ 'a.com': { id: 'trocado' } })
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await selection.open(option)
    selection.cancelChange()
    expect(selection.pendingChange).toBeNull()
    expect(go).not.toHaveBeenCalled()
    go.mockRestore()
  })

  it('se não responde ou deixou de ser um gateway, avisa e não sai da página', async () => {
    const { option } = await added()
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    for (const net of [{} as Record<string, 'web'>, { 'a.com': 'web' } as Record<string, 'web'>]) {
      network(net)
      await selection.open(option)
      expect(toast.message).toBe('Meu não respondeu.')
      expect(selection.connecting).toBeNull()
    }
    expect(go).not.toHaveBeenCalled()
    go.mockRestore()
  })

  it('segue o http que virou https', async () => {
    const { option } = await added()
    vi.mocked(fetch).mockImplementation((async () => {
      const res = new Response(ServerInfo.encode({ name: 'Casa', registrationEnabled: true }).finish(), {
        headers: { 'content-type': 'application/x-protobuf', 'x-plany-id': 'aaa' },
      })
      Object.defineProperty(res, 'url', { value: 'https://a.com/server/info/' })
      return res
    }) as typeof fetch)
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await selection.open(option)
    expect(go).toHaveBeenCalledWith('https://a.com')
    go.mockRestore()
  })

  it('dois toques seguidos abrem uma vez só', async () => {
    const { option } = await added()
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    await Promise.all([selection.open(option), selection.open(option), selection.open(option)])
    expect(go).toHaveBeenCalledTimes(1)
    go.mockRestore()
  })
})
