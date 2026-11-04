import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { found, mockDiscover } from '../../test/discovery'
import { stubLocalStorage } from '../../test/storage'
import {
  directory,
  embedded,
  idFor,
  isUsableIpv4,
  MAX_SERVERS,
  navigation,
  probe,
  selection,
  ServerDirectory,
  toOption,
} from './servers.svelte'
import { toast } from './toast.svelte'
import { remember, trustOf } from './trust'

afterEach(() => vi.useRealTimers())

describe('servidor embutido', () => {
  it('é o escolhido e aponta para quem serve a página', () => {
    expect(selection.selected).toBe(embedded)
    expect(embedded.address).toBe(window.location.host)
    expect(embedded.url).toBe(window.location.origin)
  })

  it('a lista começa com ele e um anúncio com o mesmo id não o repete', async () => {
    mockDiscover([found('Embedded')])
    const d = new ServerDirectory()
    await d.refresh()
    expect(d.list[0]).toBe(embedded)
    expect(d.list.filter((s) => s.id === 'embedded')).toHaveLength(1)
    expect(d.others).toEqual([])
  })
})

describe('anúncios', () => {
  it.each([
    ['10.0.0.1', true],
    ['192.168.1.116', true],
    ['127.0.0.1', false],
    ['169.254.1.1', false],
    ['0.0.0.0', false],
    ['224.0.0.251', false],
    ['256.1.1.1', false],
    ['01.2.3.4', false],
    ['fe80::1', false],
    ['1.2.3', false],
    ['a.b.c.d', false],
    ['', false],
  ])('IPv4 %s utilizável: %s', (ip, ok) => expect(isUsableIpv4(ip)).toBe(ok))

  it('o id que o servidor anuncia é atualizado na lista mesmo com o mesmo nome e endereço', async () => {
    const d = new ServerDirectory()
    mockDiscover([found('Casa', '10.0.0.5', 8095, 'aaa')])
    await d.refresh()
    expect(d.others[0].serverId).toBe('aaa')
    mockDiscover([found('Casa', '10.0.0.5', 8095, 'bbb')])
    await d.refresh()
    expect(d.others[0].serverId).toBe('bbb')
  })

  it('toOption leva o id do servidor; um id inútil vira vazio', () => {
    expect(toOption(found('Casa', '10.0.0.5', 8095, 'a1B2-c3'))?.serverId).toBe('a1B2-c3')
    for (const bad of ['', 'com espaço', 'a;b', 'ü', 'x'.repeat(65), '<b>']) {
      expect(toOption(found('Casa', '10.0.0.5', 8095, bad))?.serverId, bad).toBe('')
    }
  })

  it('id sem acentos, minúsculo e só com letras, números e hífens', () => {
    expect(idFor('Escritório  do João!')).toBe('escritorio-do-joao')
    expect(idFor('!!!')).toBe('servidor')
  })

  it('toOption monta endereço e url; IP inútil cai para o nome mDNS', () => {
    expect(toOption(found('Casa', '10.0.0.5', 8095))).toEqual({
      id: 'casa',
      name: 'Casa',
      address: '10.0.0.5:8095',
      url: 'http://10.0.0.5:8095',
      serverId: '',
    })
    expect(toOption({ name: 'X', host: 'pi', id: '', addresses: ['127.0.0.1'], port: 80, tlsPort: 0 })?.address).toBe('pi.local:80')
  })

  it.each([
    ['sem nome', { name: '', host: 'h', id: '', addresses: ['10.0.0.1'], port: 80, tlsPort: 0 }],
    ['nome enorme', { name: 'N'.repeat(65), host: 'h', id: '', addresses: ['10.0.0.1'], port: 80, tlsPort: 0 }],
    ['porta zero', { name: 'A', host: 'h', id: '', addresses: ['10.0.0.1'], port: 0, tlsPort: 0 }],
    ['porta enorme', { name: 'A', host: 'h', id: '', addresses: ['10.0.0.1'], port: 70000, tlsPort: 0 }],
    ['sem endereço nem host', { name: 'A', host: '', id: '', addresses: ['127.0.0.1'], port: 80, tlsPort: 0 }],
  ])('anúncio inútil (%s) é ignorado', (_, server) => expect(toOption(server)).toBeNull())
})

describe('ServerDirectory', () => {
  it('lista os servidores achados, ordenados sem diferenciar maiúsculas', async () => {
    mockDiscover([found('zeta', '10.0.0.2'), found('Alfa', '10.0.0.1')])
    const d = new ServerDirectory()
    expect(d.loaded).toBe(false)
    await d.refresh()
    expect(d.loaded).toBe(true)
    expect(d.others.map((s) => s.name)).toEqual(['Alfa', 'zeta'])
  })

  it('sem gateway (404) ou com erro de rede: nada quebra e loaded fica true', async () => {
    for (const reply of ['missing', 'error'] as const) {
      mockDiscover(reply)
      const d = new ServerDirectory()
      await d.refresh()
      expect(d.loaded).toBe(true)
      expect(d.others).toEqual([])
    }
  })

  it('erro de rede não apaga o que já se sabia', async () => {
    mockDiscover([found('A')])
    const d = new ServerDirectory()
    await d.refresh()
    mockDiscover('error')
    await d.refresh()
    expect(d.others.map((s) => s.name)).toEqual(['A'])
  })

  it('resposta lixo (não é protobuf) é tratada como erro', async () => {
    vi.mocked(fetch).mockResolvedValue(new Response(new Uint8Array([0xff, 0xff, 0xff, 0xff, 0xff])))
    const d = new ServerDirectory()
    await expect(d.refresh()).resolves.toBeUndefined()
    expect(d.others).toEqual([])
  })

  it('resposta enorme é descartada', async () => {
    vi.mocked(fetch).mockResolvedValue(new Response(new Uint8Array(200_000)))
    const d = new ServerDirectory()
    await d.refresh()
    expect(d.others).toEqual([])
  })

  it('um servidor que some fica pelo prazo; se volta, nada muda; vencido, sai', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(0)
    mockDiscover([found('A')])
    const d = new ServerDirectory()
    await d.refresh()
    mockDiscover([])
    vi.setSystemTime(10_000)
    await d.refresh()
    expect(d.others.map((s) => s.name)).toEqual(['A'])
    mockDiscover([found('A')])
    vi.setSystemTime(12_000)
    await d.refresh()
    mockDiscover([])
    vi.setSystemTime(20_000) // the deadline restarted at 12 s... and only 8 s have passed here
    await d.refresh()
    expect(d.others.map((s) => s.name)).toEqual(['A'])
    vi.setSystemTime(40_000)
    await d.refresh()
    expect(d.others).toEqual([])
  })

  it('tem teto de servidores e ignora os repetidos', async () => {
    mockDiscover([
      ...Array.from({ length: 500 }, (_, i) => found(`S${i}`, `10.0.${i >> 8}.${(i & 255) + 1}`)),
      found('S1', '10.9.9.9'),
    ])
    const d = new ServerDirectory()
    await d.refresh()
    expect(d.others).toHaveLength(MAX_SERVERS)
    expect(new Set(d.others.map((s) => s.id)).size).toBe(MAX_SERVERS)
  })

  it('start consulta já, depressa enquanto vazio e devagar com servidores; parar cancela', async () => {
    vi.useFakeTimers()
    mockDiscover([])
    const d = new ServerDirectory()
    const stop = d.start()
    await vi.advanceTimersByTimeAsync(0)
    expect(fetch).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(5_000)
    expect(fetch).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(10_000) // the wait doubled (10 s)
    expect(fetch).toHaveBeenCalledTimes(3)
    stop()
    await vi.advanceTimersByTimeAsync(120_000)
    expect(fetch).toHaveBeenCalledTimes(3)
  })

  it('aba escondida não consulta', async () => {
    vi.useFakeTimers()
    mockDiscover([])
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
    const stop = new ServerDirectory().start()
    await vi.advanceTimersByTimeAsync(30_000)
    expect(fetch).not.toHaveBeenCalled()
    stop()
    vi.restoreAllMocks()
  })
})

describe('probe', () => {
  it('true se o servidor responde; false em erro de rede ou sem resposta no prazo', async () => {
    vi.mocked(fetch).mockResolvedValue(new Response(null))
    expect(await probe('http://10.0.0.1:8095')).toBe(true)
    vi.mocked(fetch).mockRejectedValue(new TypeError('recusou'))
    expect(await probe('http://10.0.0.1:8095')).toBe(false)
    vi.mocked(fetch).mockImplementation(
      (_, init) => new Promise((_, reject) => init?.signal?.addEventListener('abort', () => reject(new DOMException('', 'AbortError')))),
    )
    expect(await probe('http://10.0.0.1:8095', 20)).toBe(false)
  })
})

describe('selection.open', () => {
  let go: ReturnType<typeof vi.spyOn>
  const server = { id: 'escritorio', name: 'Escritório', address: '10.0.0.9:8095', url: 'http://10.0.0.9:8095' }

  beforeEach(() => {
    stubLocalStorage()
    go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    vi.mocked(fetch).mockResolvedValue(new Response(null))
    selection.connecting = null
    selection.pendingChange = null
    toast.message = ''
  })
  afterEach(() => go.mockRestore())

  it('sonda e navega; durante a troca fica "connecting"', async () => {
    const pending = selection.open(server)
    expect(selection.connecting).toEqual(server)
    await pending
    expect(go).toHaveBeenCalledExactlyOnceWith('http://10.0.0.9:8095')
    expect(selection.connecting).toEqual(server)
  })

  it('servidor mudo: não sai da página, volta ao normal e avisa', async () => {
    vi.mocked(fetch).mockRejectedValue(new TypeError('sem rota'))
    await selection.open(server)
    expect(go).not.toHaveBeenCalled()
    expect(selection.connecting).toBeNull()
    expect(toast.message).toBe('Escritório não respondeu.')
  })

  it('toques repetidos ou em outro servidor durante a troca são ignorados', async () => {
    const first = selection.open(server)
    for (let i = 0; i < 10; i++) void selection.open({ ...server, id: `o${i}`, url: `http://10.0.0.${i}:1` })
    await first
    expect(go).toHaveBeenCalledOnce()
    expect(go).toHaveBeenCalledWith(server.url)
  })

  describe('identidade do servidor', () => {
    const casa = { ...server, id: 'casa', name: 'Casa', serverId: 'aaa' }

    it('o primeiro contato entra direto e fica lembrado; voltar com o mesmo id também', async () => {
      await selection.open(casa)
      expect(selection.pendingChange).toBeNull()
      expect(go).toHaveBeenCalledOnce()
      expect(trustOf('Casa', 'aaa')).toBe('same')
      selection.connecting = null
      await selection.open(casa)
      expect(go).toHaveBeenCalledTimes(2)
    })

    it('outro id sob o mesmo nome pergunta antes e não sai da página', async () => {
      remember('Casa', 'aaa')
      await selection.open({ ...casa, serverId: 'bbb' })
      expect(selection.pendingChange?.serverId).toBe('bbb')
      expect(selection.connecting).toBeNull()
      expect(go).not.toHaveBeenCalled()
      expect(vi.mocked(fetch)).not.toHaveBeenCalled()
    })

    it('sem id onde havia um também pergunta', async () => {
      remember('Casa', 'aaa')
      await selection.open({ ...casa, serverId: '' })
      expect(selection.pendingChange).not.toBeNull()
    })

    it('cancelar fecha a pergunta, não navega e não muda o que se lembra', async () => {
      remember('Casa', 'aaa')
      await selection.open({ ...casa, serverId: 'bbb' })
      selection.cancelChange()
      expect(selection.pendingChange).toBeNull()
      expect(go).not.toHaveBeenCalled()
      expect(trustOf('Casa', 'aaa')).toBe('same')
    })

    it('confirmar sonda, navega e passa a lembrar do novo id', async () => {
      remember('Casa', 'aaa')
      await selection.open({ ...casa, serverId: 'bbb' })
      selection.confirmChange()
      await vi.waitFor(() => expect(go).toHaveBeenCalledOnce())
      expect(selection.pendingChange).toBeNull()
      expect(trustOf('Casa', 'bbb')).toBe('same')
    })

    it('com a pergunta aberta, outros toques não abrem outro servidor nem empilham perguntas', async () => {
      remember('Casa', 'aaa')
      const changed = { ...casa, serverId: 'bbb' }
      await selection.open(changed)
      for (let i = 0; i < 5; i++) await selection.open({ ...server, id: `o${i}`, name: `O${i}`, url: `http://10.0.0.${i}:1` })
      await selection.open(changed)
      expect(go).not.toHaveBeenCalled()
      expect(selection.pendingChange).toEqual(changed)
    })

    it('confirmar sem pergunta aberta (toque duplo) não faz nada', async () => {
      selection.confirmChange()
      await Promise.resolve()
      expect(go).not.toHaveBeenCalled()
    })

    it('servidor que não respondeu não passa a ser lembrado', async () => {
      vi.mocked(fetch).mockRejectedValue(new TypeError('sem rota'))
      await selection.open(casa)
      expect(trustOf('Casa', 'aaa')).toBe('new')
    })

    it('sem armazenamento a navegação continua funcionando', async () => {
      vi.stubGlobal('localStorage', {
        getItem: () => {
          throw new Error('bloqueado')
        },
        setItem: () => {
          throw new Error('bloqueado')
        },
      })
      await selection.open(casa)
      expect(go).toHaveBeenCalledOnce()
    })
  })

  it('escolher o embutido não faz nada', async () => {
    await selection.open(embedded)
    expect(go).not.toHaveBeenCalled()
    expect(selection.connecting).toBeNull()
  })

  it('voltar pelo histórico (bfcache) limpa a transição', async () => {
    await selection.open(server)
    window.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: true }))
    expect(selection.connecting).toBeNull()
  })
})

it('a store global começa vazia e não carregada', () => {
  expect(directory.others).toEqual([])
})
