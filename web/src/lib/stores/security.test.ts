import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ServerInfo } from '../../types/shared/protos/server'
import { bestUrl, secureChecks, secureOrigin, securityOf } from './security.svelte'

const info = (id: string) => {
  const res = new Response(ServerInfo.encode({ name: 'Casa', registrationEnabled: true }).finish() as BodyInit, {
    headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': id },
  })
  return res
}

/** Answers per origin: an id (a gateway whose certificate this browser accepts), or nothing (refused, as a browser does with a certificate it does not trust). */
function https(map: Record<string, string>) {
  const calls: string[] = []
  vi.mocked(fetch).mockImplementation((async (url: string) => {
    calls.push(String(url))
    const id = map[new URL(url).origin]
    if (!id) throw new TypeError('net::ERR_CERT_AUTHORITY_INVALID')
    return info(id)
  }) as typeof fetch)
  return calls
}

beforeEach(() => secureChecks.reset())
afterEach(() => vi.useRealTimers())

describe('secureOrigin', () => {
  it('monta o endereço seguro; IPv6 vai entre colchetes; porta ou host inúteis não viram endereço', () => {
    expect(secureOrigin({ hostname: '192.168.0.20', tlsPort: 8443 })).toBe('https://192.168.0.20:8443')
    expect(secureOrigin({ hostname: 'fd00::1', tlsPort: 8443 })).toBe('https://[fd00::1]:8443')
    expect(secureOrigin({ hostname: '[fd00::1]', tlsPort: 8443 })).toBe('https://[fd00::1]:8443')
    for (const tlsPort of [0, -1, 70000, 1.5, NaN]) expect(secureOrigin({ hostname: 'a', tlsPort })).toBeNull()
    expect(secureOrigin({ hostname: '', tlsPort: 8443 })).toBeNull()
    expect(secureOrigin({ hostname: 'a b', tlsPort: 8443 })).toBeNull()
  })
})

describe('se este navegador confia no HTTPS de um servidor', () => {
  const side = { hostname: '192.168.0.20', tlsPort: 8443, serverId: 'casa-1' }

  it('sem lado seguro é HTTP sem criptografia; endereço https já é https', () => {
    expect(securityOf('http://192.168.0.20:8095')).toBe('plain')
    expect(securityOf('https://a.test')).toBe('https')
    expect(securityOf('http://192.168.0.20:8095', { hostname: 'x', tlsPort: 0 })).toBe('plain')
  })

  it('antes de perguntar, "verificando"; com o certificado aceito, HTTPS e o endereço seguro para abrir', async () => {
    https({ 'https://192.168.0.20:8443': 'casa-1' })
    expect(securityOf('http://192.168.0.20:8095', side)).toBe('checking')
    expect(bestUrl('http://192.168.0.20:8095', side)).toBe('http://192.168.0.20:8095')
    await secureChecks.check([side])
    expect(securityOf('http://192.168.0.20:8095', side)).toBe('https')
    expect(bestUrl('http://192.168.0.20:8095', side)).toBe('https://192.168.0.20:8443')
  })

  it('certificado recusado pelo navegador: não confiável, e continua abrindo pelo HTTP', async () => {
    https({})
    await secureChecks.check([side])
    expect(securityOf('http://192.168.0.20:8095', side)).toBe('untrusted')
    expect(bestUrl('http://192.168.0.20:8095', side)).toBe('http://192.168.0.20:8095')
  })

  it('outro servidor respondendo na porta segura não é este: não confiável', async () => {
    https({ 'https://192.168.0.20:8443': 'impostor' })
    await secureChecks.check([side])
    expect(securityOf('http://192.168.0.20:8095', side)).toBe('untrusted')
  })

  it('resposta que a página não pode ler: sem saber de quem é, só vale para um servidor de id desconhecido', async () => {
    // CORS read refused, plain no-cors answer: an HTTPS service whose certificate the browser accepts, owner unknown
    vi.mocked(fetch).mockImplementation((async (_url: string, init?: RequestInit) => {
      if (init?.mode === 'no-cors') return new Response(null)
      throw new TypeError('Failed to fetch')
    }) as typeof fetch)
    const anonymous = { hostname: '192.168.0.21', tlsPort: 8443 }
    await secureChecks.check([side, anonymous])
    expect(securityOf('http://192.168.0.20:8095', side)).toBe('untrusted')
    expect(bestUrl('http://192.168.0.20:8095', side)).toBe('http://192.168.0.20:8095')
    expect(securityOf('http://192.168.0.21:8095', anonymous)).toBe('https')
  })

  it('pergunta uma vez por meio minuto, mesmo com o menu aberto e fechado várias vezes', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    const calls = https({ 'https://192.168.0.20:8443': 'casa-1' })
    await Promise.all([secureChecks.check([side]), secureChecks.check([side]), secureChecks.check([side, side])])
    await secureChecks.check([side])
    expect(calls).toHaveLength(1)
    vi.setSystemTime(Date.now() + 31_000)
    await secureChecks.check([side])
    expect(calls).toHaveLength(2)
  })

  it('muitos servidores: no máximo 4 perguntas ao mesmo tempo', async () => {
    let now = 0
    let peak = 0
    vi.mocked(fetch).mockImplementation((async () => {
      peak = Math.max(peak, ++now)
      await new Promise((r) => setTimeout(r, 5))
      now--
      throw new TypeError('cert')
    }) as typeof fetch)
    const many = Array.from({ length: 20 }, (_, i) => ({ hostname: `10.0.0.${i + 1}`, tlsPort: 8443 }))
    await secureChecks.check(many)
    expect(peak).toBeLessThanOrEqual(4)
    expect(many.every((s) => securityOf('http://x', s) === 'untrusted')).toBe(true)
  })
})
