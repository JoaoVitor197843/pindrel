import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { stubLocalStorage } from '../../test/storage'
import { ManualServers, MAX_MANUAL, type ManualServer } from './manual.svelte'

beforeEach(() => {
  stubLocalStorage()
})

const make = (i: number, serverId = `id${i}`): ManualServer => ({
  id: `http://s${i}.test`,
  name: `S${i}`,
  trustName: `S${i}`,
  serverId,
  url: `http://s${i}.test`,
  address: `s${i}.test`,
})

const gateway = (id: string) =>
  new Response(ServerInfo.encode({ name: 'S', registrationEnabled: true }).finish() as BodyInit, {
    headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': id },
  })

function full() {
  const m = new ManualServers()
  m.list = Array.from({ length: MAX_MANUAL }, (_, i) => make(i))
  return m
}

describe('a verificação periódica', () => {
  it('com 16 servidores lentos nunca há mais de 4 pedidos ao mesmo tempo', async () => {
    let live = 0
    let peak = 0
    vi.mocked(fetch).mockImplementation((async () => {
      live++
      peak = Math.max(peak, live)
      await new Promise((r) => setTimeout(r, 15))
      live--
      return new Response(null)
    }) as typeof fetch)
    const m = full()
    await m.check()
    expect(peak).toBeLessThanOrEqual(4)
    expect(Object.values(m.health).filter((h) => h === 'connected')).toHaveLength(MAX_MANUAL)
  })

  it('a checagem forte vê outra máquina no mesmo endereço e mostra desconectado na hora (sem esperar 2 falhas)', async () => {
    vi.mocked(fetch).mockImplementation((async (url: string) => gateway(url.includes('s3.') ? 'impostor' : `id${/s(\d+)\./.exec(url)![1]}`)) as typeof fetch)
    const m = full()
    await m.check(true)
    expect(m.health['http://s3.test']).toBe('disconnected')
    expect(m.health['http://s4.test']).toBe('connected')
    expect(m.list[3].serverId).toBe('id3') // never rewritten silently: opening it asks
  })

  it('a checagem forte volta ao "alguém responde" quando o navegador não pode ler (gateway antigo)', async () => {
    vi.mocked(fetch).mockImplementation((async (_: string, init?: RequestInit) => {
      if (init?.mode === 'no-cors') return new Response(null)
      throw new TypeError('cors')
    }) as typeof fetch)
    const m = new ManualServers()
    m.list = [make(1)]
    await m.check(true)
    expect(m.health['http://s1.test']).toBe('connected')
  })

  it('a checagem forte de algo que virou um site comum também desconecta', async () => {
    vi.mocked(fetch).mockImplementation((async () => new Response('<html>', { headers: { 'content-type': 'text/html' } })) as typeof fetch)
    const m = new ManualServers()
    m.list = [make(1)]
    await m.check(true)
    expect(m.health['http://s1.test']).toBe('disconnected')
  })

  it('o servidor que volta com o mesmo id fica verde de novo', async () => {
    const m = new ManualServers()
    m.list = [make(1)]
    vi.mocked(fetch).mockImplementation((async () => gateway('impostor')) as typeof fetch)
    await m.check(true)
    expect(m.health['http://s1.test']).toBe('disconnected')
    vi.mocked(fetch).mockImplementation((async () => gateway('id1')) as typeof fetch)
    await m.check(true)
    expect(m.health['http://s1.test']).toBe('connected')
  })

  it('remover no meio da checagem não deixa rastro', async () => {
    vi.mocked(fetch).mockImplementation((async () => {
      await new Promise((r) => setTimeout(r, 20))
      return new Response(null)
    }) as typeof fetch)
    const m = full()
    const running = m.check()
    m.remove('http://s2.test')
    await running
    expect(m.health['http://s2.test']).toBeUndefined()
  })

  it('start() não repete a verificação quando a lista muda (efeito do Svelte) e para ao desligar', async () => {
    vi.useFakeTimers()
    let asked = 0
    vi.mocked(fetch).mockImplementation((async () => {
      asked++
      return new Response(null)
    }) as typeof fetch)
    const m = new ManualServers()
    m.list = [make(1)]
    const stop = m.start()
    await vi.advanceTimersByTimeAsync(0)
    const first = asked
    m.list = [...m.list, make(2)]
    await vi.advanceTimersByTimeAsync(100)
    expect(asked).toBe(first)
    stop()
    await vi.advanceTimersByTimeAsync(60_000)
    expect(asked).toBe(first)
    vi.useRealTimers()
  })
})
