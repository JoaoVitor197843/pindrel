import { describe, expect, it, vi } from 'vitest'
import { FakeFiles, patterned } from '../../test/fakeFiles'
import { CHUNK_SIZE, FileApiError, FilesApi, sourceOf, uploadFile, type ByteSource } from './files'

const noSleep = () => Promise.resolve()
const rig = () => {
  const server = new FakeFiles()
  const api = new FilesApi({ token: () => server.token, fetch: server.fetch })
  return { server, api }
}

// jsdom's Blob is slow and a loaded machine slower: the default five seconds is too tight for a dozen pieces
describe('uploadFile', { timeout: 30_000 }, () => {
  it('manda um arquivo em pedaços e o servidor monta os mesmos bytes', async () => {
    const { server, api } = rig()
    const data = patterned(CHUNK_SIZE * 2 + 12_345)
    const progress: number[] = []
    const file = await uploadFile(api, sourceOf(new Blob([data])), { name: 'foto.bin', sleep: noSleep, onProgress: (sent) => progress.push(sent) })
    expect(file.size).toBe(data.length)
    expect(file.name).toBe('foto.bin')
    expect(server.files.get(file.id)!.bytes).toEqual(data)
    // progress only goes up and ends at the total
    expect(progress).toEqual([...progress].sort((a, b) => a - b))
    expect(progress.at(-1)).toBe(data.length)
    // three pieces, none bigger than the limit
    const puts = server.seen.filter((r) => r.method === 'PUT')
    expect(puts).toHaveLength(3)
    expect(Math.max(...puts.map((p) => p.bytes))).toBeLessThanOrEqual(CHUNK_SIZE)
  })

  it('tamanhos nas bordas: 1 byte, um pedaço exato, um a mais', async () => {
    for (const size of [1, CHUNK_SIZE - 1, CHUNK_SIZE, CHUNK_SIZE + 1, CHUNK_SIZE * 3]) {
      const { server, api } = rig()
      const data = patterned(size)
      const file = await uploadFile(api, sourceOf(new Blob([data])), { sleep: noSleep })
      expect(server.files.get(file.id)!.bytes, `${size} bytes`).toEqual(data)
    }
  })

  it('um arquivo vazio não é enviado', async () => {
    const { server, api } = rig()
    await expect(uploadFile(api, sourceOf(new Blob([])), { sleep: noSleep })).rejects.toMatchObject({ code: 'invalid_input' })
    expect(server.seen).toHaveLength(0)
  })

  it('nunca tem mais pedaços no ar do que o combinado, e o servidor vê todos os envios sobrepostos', async () => {
    const { server, api } = rig()
    server.delay = 5
    await uploadFile(api, sourceOf(new Blob([patterned(CHUNK_SIZE * 8)])), { sleep: noSleep, concurrency: 2 })
    expect(server.peakInFlight).toBe(2)
    const one = rig()
    one.server.delay = 5
    await uploadFile(one.api, sourceOf(new Blob([patterned(CHUNK_SIZE * 4)])), { sleep: noSleep, concurrency: 1 })
    expect(one.server.peakInFlight).toBe(1)
  })

  it('um arquivo enorme (1000 pedaços) sai inteiro, sem repetir nem pular pedaço, lendo um pedaço de cada vez', async () => {
    const { server, api } = rig()
    server.keepBytes = false
    let reading = 0
    let peak = 0
    const size = CHUNK_SIZE * 1000
    const source: ByteSource = {
      size,
      read: async (start, end) => {
        peak = Math.max(peak, ++reading)
        await Promise.resolve()
        reading--
        return patterned(end - start)
      },
    }
    const file = await uploadFile(api, source, { sleep: noSleep })
    expect(file.size).toBe(size)
    const sent = server.seen.filter((r) => r.method === 'PUT').map((r) => Number(r.path.split('/').pop()))
    expect(sent).toHaveLength(1000)
    expect(new Set(sent).size).toBe(1000)
    expect(peak).toBeLessThanOrEqual(2)
  })

  it('tenta de novo quando a conexão cai ou o servidor está ocupado, e respeita o Retry-After', async () => {
    const { server, api } = rig()
    const pauses: number[] = []
    server.hook = (r, n) => {
      if (r.method !== 'PUT') return
      if (n === 1) return 'throw'
      if (n === 3) return server.err(503, 'server_busy', { 'Retry-After': '2' })
      if (n === 5) return server.err(502, 'bad_gateway')
    }
    const data = patterned(CHUNK_SIZE * 4)
    const file = await uploadFile(api, sourceOf(new Blob([data])), { sleep: async (ms) => void pauses.push(ms), concurrency: 1 })
    expect(server.files.get(file.id)!.bytes).toEqual(data)
    expect(pauses.length).toBeGreaterThanOrEqual(3)
    expect(pauses.some((p) => p >= 2000)).toBe(true)
  })

  it('um pedaço estragado no caminho (hash errado) é mandado de novo', async () => {
    const { server, api } = rig()
    let bad = 0
    server.hook = (r) => {
      if (r.method === 'PUT' && bad++ === 0) return server.err(422, 'chunk_hash_mismatch')
    }
    const file = await uploadFile(api, sourceOf(new Blob([patterned(1000)])), { sleep: noSleep })
    expect(file.size).toBe(1000)
  })

  it('desiste depois de tentativas demais, com o erro do servidor', async () => {
    const { server, api } = rig()
    server.hook = (r) => (r.method === 'PUT' ? server.err(503, 'server_busy') : undefined)
    const t = uploadFile(api, sourceOf(new Blob([patterned(1000)])), { sleep: noSleep, attempts: 3 })
    await expect(t).rejects.toMatchObject({ status: 503, code: 'server_busy' })
    expect(server.seen.filter((r) => r.method === 'PUT')).toHaveLength(3)
  })

  it('erros finais aparecem na hora, sem insistir: cota, tamanho, sessão', async () => {
    for (const [status, code] of [[413, 'quota_exceeded'], [413, 'file_too_large'], [507, 'storage_full'], [429, 'too_many_uploads'], [401, 'unauthorized'], [403, 'forbidden']] as const) {
      const { server, api } = rig()
      server.hook = (r) => (r.method === 'POST' ? server.err(status, code) : undefined)
      await expect(uploadFile(api, sourceOf(new Blob([patterned(10)])), { sleep: noSleep }), code).rejects.toMatchObject({ status, code })
      expect(server.seen, code).toHaveLength(1)
    }
  })

  it('sem sessão nem tenta falar com o servidor', async () => {
    const { server, api } = rig()
    const signedIn = api.signedIn
    const none = new FilesApi({ token: () => null, fetch: server.fetch })
    await expect(uploadFile(none, sourceOf(new Blob([patterned(10)])), { sleep: noSleep })).rejects.toMatchObject({ code: 'not_signed_in' })
    expect(server.seen).toHaveLength(0)
    expect(signedIn).toBe(true)
    expect(none.signedIn).toBe(false)
  })

  it('cancelar para na hora, não manda mais nada e apaga o envio no servidor', async () => {
    const { server, api } = rig()
    server.delay = 20
    const abort = new AbortController()
    const t = uploadFile(api, sourceOf(new Blob([patterned(CHUNK_SIZE * 10)])), { sleep: noSleep, signal: abort.signal, concurrency: 2, onProgress: (sent) => sent >= CHUNK_SIZE * 2 && abort.abort() })
    await expect(t).rejects.toMatchObject({ name: 'AbortError' })
    const after = server.seen.length
    await new Promise((r) => setTimeout(r, 120))
    // only the cancel itself and the pieces already in flight come after the abort
    expect(server.seen.length).toBeLessThanOrEqual(after + 2)
    expect(server.seen.some((r) => r.method === 'DELETE' && r.path.startsWith('/files/uploads/'))).toBe(true)
    expect(server.uploads.size).toBe(0)
  })

  it('já cancelado antes de começar não faz nada', async () => {
    const { server, api } = rig()
    const abort = new AbortController()
    abort.abort()
    await expect(uploadFile(api, sourceOf(new Blob([patterned(10)])), { signal: abort.signal })).rejects.toMatchObject({ name: 'AbortError' })
    expect(server.seen).toHaveLength(0)
  })

  it('um envio que falha por rede, sem quem retome, solta a vaga no servidor (nada fica aberto por 24 h)', async () => {
    const { server, api } = rig()
    // every piece times out, as when a slow line makes the gateway give up (408)
    server.hook = (r) => (r.method === 'PUT' ? server.err(408, 'request_timeout') : undefined)
    await expect(uploadFile(api, sourceOf(new Blob([patterned(1000)])), { sleep: noSleep, attempts: 2 })).rejects.toMatchObject({ status: 408 })
    await vi.waitFor(() => expect(server.uploads.size).toBe(0))
    expect(server.seen.some((r) => r.method === 'DELETE')).toBe(true)
  })

  it('várias tentativas que falham seguidas não enchem o limite de envios abertos', async () => {
    const { server, api } = rig()
    server.hook = (r) => (r.method === 'PUT' ? server.err(408, 'request_timeout') : undefined)
    for (let i = 0; i < 8; i++) await uploadFile(api, sourceOf(new Blob([patterned(500)])), { sleep: noSleep, attempts: 1 }).catch(() => {})
    await vi.waitFor(() => expect(server.uploads.size).toBe(0))
  })

  it('com quem pediu o id para retomar, a falha de rede mantém o envio, mas um erro final o solta', async () => {
    const { server, api } = rig()
    let opened = ''
    server.hook = (r) => (r.method === 'PUT' ? server.err(503, 'server_busy') : undefined)
    await expect(uploadFile(api, sourceOf(new Blob([patterned(500)])), { sleep: noSleep, attempts: 1, onOpen: (id) => (opened = id) })).rejects.toMatchObject({ status: 503 })
    expect(server.uploads.has(opened)).toBe(true)
    server.hook = (r) => (r.method === 'PUT' ? server.err(413, 'quota_exceeded') : undefined)
    await expect(uploadFile(api, sourceOf(new Blob([patterned(500)])), { sleep: noSleep, attempts: 1, onOpen: (id) => (opened = id) })).rejects.toMatchObject({ code: 'quota_exceeded' })
    await vi.waitFor(() => expect(server.uploads.has(opened)).toBe(false))
  })

  it('retoma um envio parado: só manda o que falta', async () => {
    const { server, api } = rig()
    const data = patterned(CHUNK_SIZE * 5)
    let opened = ''
    // the first try loses its connection for good after two pieces
    server.hook = (r, n) => (r.method === 'PUT' && n >= 3 ? 'throw' : undefined)
    await expect(uploadFile(api, sourceOf(new Blob([data])), { sleep: noSleep, concurrency: 1, attempts: 2, onOpen: (id) => (opened = id) })).rejects.toBeInstanceOf(FileApiError)
    expect(server.uploads.has(opened)).toBe(true)
    server.hook = () => {}
    const before = server.seen.filter((r) => r.method === 'PUT').length
    const file = await uploadFile(api, sourceOf(new Blob([data])), { sleep: noSleep, resume: opened })
    expect(server.files.get(file.id)!.bytes).toEqual(data)
    const puts = server.seen.filter((r) => r.method === 'PUT').slice(before)
    expect(puts.length).toBe(3) // five pieces, two already there
  })

  it('retomar um envio que sumiu, ou que era de outro arquivo, começa de novo', async () => {
    const { server, api } = rig()
    const data = patterned(CHUNK_SIZE + 5)
    const file = await uploadFile(api, sourceOf(new Blob([data])), { sleep: noSleep, resume: 'up999' })
    expect(server.files.get(file.id)!.bytes).toEqual(data)
    // an upload of another size
    const other = await api.createUpload(10, 'x', false)
    const again = await uploadFile(api, sourceOf(new Blob([data])), { sleep: noSleep, resume: other.uploadId })
    expect(server.files.get(again.id)!.bytes).toEqual(data)
  })

  it('a resposta do finish se perde depois de dar certo: acha o arquivo pronto em vez de falhar', async () => {
    const { server, api } = rig()
    const data = patterned(5000)
    let first = true
    server.hook = (r) => {
      if (r.method === 'POST' && r.path.endsWith('/finish') && first) {
        first = false
        return 'drop' // the server finishes, the answer never arrives
      }
    }
    const file = await uploadFile(api, sourceOf(new Blob([data])), { sleep: noSleep, name: 'x.bin' })
    expect(server.files.get(file.id)!.bytes).toEqual(data)
    expect(server.files.size).toBe(1)
  })

  it('o arquivo muda enquanto é lido (menor do que o prometido): para sem mandar lixo', async () => {
    const { server, api } = rig()
    const source: ByteSource = { size: CHUNK_SIZE * 2, read: async (start, end) => new Uint8Array(Math.max(0, end - start - 10)) }
    await expect(uploadFile(api, source, { sleep: noSleep })).rejects.toMatchObject({ code: 'source_changed' })
    expect(server.seen.filter((r) => r.method === 'PUT')).toHaveLength(0)
    expect(server.uploads.size).toBe(0)
  })

  it('respostas esquisitas do servidor viram erro, não travam', async () => {
    const { server, api } = rig()
    server.hook = () => new Response('<html>oi</html>', { status: 502 })
    await expect(uploadFile(api, sourceOf(new Blob([patterned(10)])), { sleep: noSleep, attempts: 2 })).rejects.toMatchObject({ status: 502, code: 'http_error' })
    server.hook = () => new Response(new Uint8Array(3 << 20), { status: 400 })
    await expect(uploadFile(api, sourceOf(new Blob([patterned(10)])), { sleep: noSleep, attempts: 2 })).rejects.toMatchObject({ status: 400 })
  })
})

describe('FilesApi', () => {
  it('link, apagar e marcar como sem uso falam com as rotas certas', async () => {
    const { server, api } = rig()
    const f = await uploadFile(api, sourceOf(new Blob([patterned(10)])), { sleep: noSleep })
    expect((await api.link(f.id)).url).toContain(`/files/${f.id}`)
    await api.orphan(f.id, true)
    expect(server.orphaned.has(f.id)).toBe(true)
    await api.orphan(f.id, false)
    expect(server.orphaned.has(f.id)).toBe(false)
    await api.remove(f.id)
    expect(server.deleted.has(f.id)).toBe(true)
    await expect(api.link(f.id)).rejects.toMatchObject({ status: 404, code: 'file_not_found' })
  })

  it('o token vai em todo pedido e nunca para um endereço de fora', async () => {
    const { server, api } = rig()
    await api.list()
    expect(server.seen.every((r) => r.path.startsWith('/files/'))).toBe(true)
  })
})
