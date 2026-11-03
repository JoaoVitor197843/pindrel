import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { parsePort } from '../api/serverCheck'
import { stubLocalStorage } from '../../test/storage'
import { ManualServers } from './manual.svelte'
import { selection } from './servers.svelte'

let data: Map<string, string>
beforeEach(() => {
  data = stubLocalStorage()
  selection.connecting = null
  selection.pendingChange = null
})

/** A gateway on `http://casa.lan:8080` with a secure side on 8443. `trusted`: whether this browser trusts that side. */
function network(opts: { trusted: boolean; httpsId?: string; tlsHeader?: string | null }) {
  const reply = (id: string, tls: string | null) =>
    new Response(ServerInfo.encode({ name: 'Casa', registrationEnabled: true }).finish() as BodyInit, {
      headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': id, ...(tls ? { 'x-pindrel-tls': tls } : {}) },
    })
  vi.mocked(fetch).mockImplementation((async (url: string, init?: RequestInit) => {
    const u = new URL(url)
    if (u.host === 'casa.lan:8080') return init?.mode === 'no-cors' ? new Response(null) : reply('aaa', opts.tlsHeader === undefined ? '8443' : opts.tlsHeader)
    if (u.host === 'casa.lan:8443') {
      if (!opts.trusted) throw new TypeError('net::ERR_CERT_AUTHORITY_INVALID')
      return init?.mode === 'no-cors' ? new Response(null) : reply(opts.httpsId ?? 'aaa', '8443')
    }
    throw new TypeError('network')
  }) as typeof fetch)
}

describe('parsePort', () => {
  it.each([
    ['8443', 8443],
    [' 443 ', 443],
    ['1', 1],
    ['65535', 65535],
  ])('%s', (value, port) => expect(parsePort(value)).toBe(port))
  it.each([null, '', '0', '65536', '-1', '80.5', '8e3', '0x50', 'abc', '8443; evil', '１２３', '99999999'])('recusa %s', (v) => {
    expect(parsePort(v)).toBeUndefined()
  })
})

describe('adicionar um servidor que tem lado seguro', () => {
  it('se este navegador já confia, o servidor é salvo com https', async () => {
    network({ trusted: true })
    const m = new ManualServers()
    const r = await m.add('casa.lan:8080', '')
    expect(r).toMatchObject({ ok: true, server: { url: 'https://casa.lan:8443', address: 'casa.lan:8443' } })
    expect(m.list[0].connectUrl).toBeUndefined()
  })

  it('se não confia ainda, fica com http e guarda a página que explica como conectar com segurança', async () => {
    network({ trusted: false })
    const m = new ManualServers()
    const r = await m.add('casa.lan:8080', '')
    expect(r).toMatchObject({ ok: true, server: { url: 'http://casa.lan:8080', connectUrl: 'http://casa.lan:8080/server/connect/' } })
    expect(new ManualServers().list[0].connectUrl).toBe('http://casa.lan:8080/server/connect/') // survives a reload
  })

  it('se o lado seguro responde como OUTRO servidor, não é trocado', async () => {
    network({ trusted: true, httpsId: 'bbb' })
    const m = new ManualServers()
    const r = await m.add('casa.lan:8080', '')
    expect(r).toMatchObject({ ok: true, server: { url: 'http://casa.lan:8080' } })
    expect(m.list[0].connectUrl).toBeDefined()
  })

  it.each(['0', '99999', 'x', '8443 8444', null])('um cabeçalho de porta inválido (%s) é ignorado: nada de https', async (tls) => {
    network({ trusted: true, tlsHeader: tls })
    const m = new ManualServers()
    const r = await m.add('casa.lan:8080', '')
    expect(r).toMatchObject({ ok: true, server: { url: 'http://casa.lan:8080' } })
    expect(m.list[0].connectUrl).toBeUndefined()
  })

  it('não adiciona duas vezes o mesmo servidor, nem pelo lado seguro', async () => {
    network({ trusted: true })
    const m = new ManualServers()
    await m.add('casa.lan:8080', '')
    expect(await m.add('casa.lan:8080', '')).toMatchObject({ ok: false })
    expect(await m.add('https://casa.lan:8443', '')).toMatchObject({ ok: false })
    expect(m.list).toHaveLength(1)
  })
})

describe('connectUrl guardado no navegador não é confiado às cegas', () => {
  const base = { id: 'http://casa.lan:8080', name: 'Casa', trustName: 'Casa', serverId: 'a', url: 'http://casa.lan:8080', address: 'casa.lan:8080' }
  it.each([
    ['de outro host', 'http://evil.example/server/connect/'],
    ['javascript:', 'javascript:alert(1)'],
    ['de outro caminho', 'http://casa.lan:8080/auth/login/'],
    ['não é URL', 'isto não é url'],
    ['número', 5 as unknown as string],
  ])('%s é descartado junto com o servidor', (_, connectUrl) => {
    data.set('pindrel:manual-servers', JSON.stringify([{ ...base, connectUrl }]))
    expect(new ManualServers().list).toEqual([])
  })
  it('o certo é mantido', () => {
    data.set('pindrel:manual-servers', JSON.stringify([{ ...base, connectUrl: 'http://casa.lan:8080/server/connect/' }]))
    expect(new ManualServers().list).toHaveLength(1)
  })
})

describe('o servidor desta página', () => {
  it('guarda se tem lado seguro a partir do cabeçalho de /server/info/', async () => {
    const answer = (tls: string | null) =>
      vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 200, headers: tls ? { 'x-pindrel-tls': tls } : {} }))
    answer('8443')
    await selection.check()
    expect(selection.tlsOffered).toBe(true)
    answer(null)
    await selection.check()
    expect(selection.tlsOffered).toBe(false)
    answer('lixo')
    await selection.check()
    expect(selection.tlsOffered).toBe(false)
  })
})
