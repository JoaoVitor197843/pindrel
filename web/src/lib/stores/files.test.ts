import { describe, expect, it, vi } from 'vitest'
import { FakeFiles, patterned } from '../../test/fakeFiles'
import { FilesApi } from '../api/files'
import { FilesService, describeError } from './files.svelte'
import { FileApiError } from '../api/files'

const rig = () => {
  const server = new FakeFiles()
  const service = new FilesService(new FilesApi({ token: () => server.token, fetch: server.fetch }))
  return { server, service }
}
const file = (size: number, name = 'a.bin') => new File([patterned(size)], name)
const until = async (cond: () => boolean, ms = 3000) => {
  const t0 = Date.now()
  while (!cond()) {
    if (Date.now() - t0 > ms) throw new Error('timeout')
    await new Promise((r) => setTimeout(r, 5))
  }
}

describe('FilesService — envios', () => {
  it('um envio passa de na fila a enviando a pronto, e entrega o arquivo', async () => {
    const { server, service } = rig()
    let done = ''
    const up = service.start(file(1000, 'x.txt'), (info) => (done = info.id))
    expect(['queued', 'sending']).toContain(up.status)
    await until(() => up.status === 'done')
    expect(up.sent).toBe(1000)
    expect(up.total).toBe(1000)
    expect(server.files.get(done)).toMatchObject({ name: 'x.txt', level: 2 })
  })

  it('só dois envios andam ao mesmo tempo; o resto espera na fila e entra conforme os outros acabam', async () => {
    const { server, service } = rig()
    server.delay = 15
    const ups = Array.from({ length: 5 }, (_, i) => service.start(file(2000, `f${i}.bin`), () => undefined))
    await until(() => ups.some((u) => u.status === 'sending'))
    expect(ups.filter((u) => u.status === 'sending').length).toBe(2)
    expect(ups.filter((u) => u.status === 'queued').length).toBe(3)
    await until(() => ups.every((u) => u.status === 'done'))
    expect(server.files.size).toBe(5)
  })

  it('cancelar um envio na fila nunca o começa; cancelar um que anda para e apaga no servidor', async () => {
    const { server, service } = rig()
    server.delay = 30
    const ups = Array.from({ length: 3 }, (_, i) => service.start(file(5000, `f${i}.bin`), () => undefined))
    service.cancel(ups[2].key)
    await until(() => ups[0].status === 'sending')
    service.cancel(ups[0].key)
    await until(() => ups[1].status === 'done')
    await new Promise((r) => setTimeout(r, 150))
    expect(ups.map((u) => u.status)).toEqual(['cancelled', 'done', 'cancelled'])
    expect(server.files.size).toBe(1)
    expect(server.uploads.size).toBe(0)
  })

  it('cancelar o que já acabou, ou o que não existe, não faz nada', async () => {
    const { service } = rig()
    const up = service.start(file(10), () => undefined)
    await until(() => up.status === 'done')
    service.cancel(up.key)
    service.cancel('nunca-existiu')
    expect(up.status).toBe('done')
  })

  it('um erro vira uma frase para a pessoa, e o envio seguinte não é afetado', async () => {
    const { server, service } = rig()
    server.quota = 100
    const bad = service.start(file(1000), () => undefined)
    await until(() => bad.status === 'failed')
    expect(bad.error).toBe('Seu espaço de arquivos neste servidor acabou')
    server.quota = Infinity
    const good = service.start(file(10), () => undefined)
    await until(() => good.status === 'done')
  })

  it('sem sessão, o erro diz para entrar em um servidor', async () => {
    const server = new FakeFiles()
    const service = new FilesService(new FilesApi({ token: () => null, fetch: server.fetch }))
    expect(service.available).toBe(false)
    const up = service.start(file(10), () => undefined)
    await until(() => up.status === 'failed')
    expect(up.error).toBe('Entre em um servidor para enviar arquivos')
    expect(server.seen).toHaveLength(0)
  })

  it('tidy esquece o que acabou e guarda o que ainda anda', async () => {
    const { server, service } = rig()
    server.delay = 20
    const a = service.start(file(10), () => undefined)
    await until(() => a.status === 'done')
    const b = service.start(file(CHUNK * 3), () => undefined)
    service.tidy()
    expect(service.uploads.map((u) => u.key)).toEqual([b.key])
    await until(() => b.status === 'done')
  })

  it('mensagens para cada erro conhecido, e uma genérica para o resto', () => {
    expect(describeError(new FileApiError(413, 'file_too_large', ''))).toMatch(/maior/)
    expect(describeError(new FileApiError(507, 'storage_full', ''))).toMatch(/sem espaço/)
    expect(describeError(new FileApiError(0, 'network', ''))).toMatch(/Sem conexão/)
    expect(describeError(new FileApiError(500, 'weird', ''))).toMatch(/\(500\)/)
    expect(describeError(new Error('x'))).toBe('Não foi possível enviar')
  })
})

const CHUNK = 512 * 1024

describe('FilesService — endereços', () => {
  async function ready() {
    const r = rig()
    let id = ''
    const up = r.service.start(file(10, 'a.png'), (i) => (id = i.id))
    await until(() => up.status === 'done')
    r.server.seen.length = 0
    return { ...r, id }
  }
  const links = (s: FakeFiles) => s.seen.filter((r) => r.path.endsWith('/link')).length

  it('guarda o endereço e não pergunta de novo enquanto vale', async () => {
    const { server, service, id } = await ready()
    expect(await service.url(id)).toContain(id)
    expect(await service.url(id)).toContain(id)
    expect(links(server)).toBe(1)
  })

  it('vários blocos pedindo o mesmo arquivo ao mesmo tempo fazem um pedido só', async () => {
    const { server, service, id } = await ready()
    server.delay = 20
    await Promise.all(Array.from({ length: 10 }, () => service.url(id)))
    expect(links(server)).toBe(1)
  })

  it('o pedido "novo" ignora o guardado', async () => {
    const { server, service, id } = await ready()
    await service.url(id)
    await service.url(id, true)
    expect(links(server)).toBe(2)
  })

  it('um endereço perto de vencer é trocado antes de ser entregue', async () => {
    const { server, service, id } = await ready()
    // the fake hands out addresses that live ten minutes; the service renews one a minute before the end
    vi.useFakeTimers()
    try {
      const first = await service.url(id)
      vi.setSystemTime(Date.now() + 9.5 * 60_000)
      await service.url(id)
      expect(first).toContain(id)
      expect(links(server)).toBe(2)
    } finally {
      vi.useRealTimers()
    }
  })

  it('falha ao pedir o endereço dá erro (não fica pendente para sempre)', async () => {
    const { server, service, id } = await ready()
    server.hook = (r) => (r.path.endsWith('/link') ? server.err(404, 'file_not_found') : undefined)
    await expect(service.url(id)).rejects.toMatchObject({ code: 'file_not_found' })
    server.hook = () => {}
    expect(await service.url(id)).toContain(id)
  })

  it('orphan e remove falam com o servidor sem estourar, mesmo quando o servidor recusa', async () => {
    const { server, service, id } = await ready()
    service.orphan(id, true)
    await until(() => server.orphaned.has(id))
    service.orphan(id, false)
    await until(() => !server.orphaned.has(id))
    server.hook = () => server.err(500, 'internal_error')
    service.orphan(id, true)
    service.remove([id, 'outro'])
    await new Promise((r) => setTimeout(r, 30))
  })
})
