// The page's side of the file feature: who is signed in, the pieces being sent, and short-lived addresses to read files.
// Nothing here keeps a file in memory: an upload reads and sends a piece at a time (api/files.ts), and an address is a
// few dozen characters.
import { FilesApi, uploadFile, sourceOf, FileApiError, type FileInfo } from '../api/files'

/** Where the access token comes from. Nobody is signed in yet in the prototype, so files stay off until a session sets it. */
export const session = {
  token: null as string | null,
}

export type UploadStatus = 'queued' | 'sending' | 'done' | 'failed' | 'cancelled'

export interface Upload {
  readonly key: string
  readonly name: string
  status: UploadStatus
  sent: number
  total: number
  error: string
}

/** What the editor needs from the file service, so a test (or a build without files) can stand in for it. */
export interface FilesPort {
  readonly available: boolean
  /** Starts sending; `onDone` runs with the finished file. */
  start(file: File, onDone: (info: FileInfo) => void, opts?: { name?: string; encrypted?: boolean }): Upload
  cancel(key: string): void
  /** A short-lived address to read a file; `fresh` forces a new one (the old one stopped working). */
  url(fileId: string, fresh?: boolean): Promise<string>
  /** Nothing uses the file any more (true) or something does again (false). */
  orphan(fileId: string, on: boolean): void
  /** Delete files for good (a page was deleted for good). */
  remove(fileIds: string[]): void
}

const MAX_AT_ONCE = 2
/** How long before an address stops working it is replaced. */
const RENEW_MARGIN_MS = 60_000

const SAYS: Record<string, string> = {
  quota_exceeded: 'Seu espaço de arquivos neste servidor acabou',
  file_too_large: 'O arquivo é maior do que este servidor aceita',
  storage_full: 'O servidor está sem espaço',
  too_many_uploads: 'Há envios demais abertos ao mesmo tempo',
  not_signed_in: 'Entre em um servidor para enviar arquivos',
  unauthorized: 'Sua sessão acabou: entre de novo',
  network: 'Sem conexão com o servidor',
  server_busy: 'O servidor está ocupado, tente de novo em instantes',
  invalid_input: 'Esse arquivo não pode ser enviado',
}

export const describeError = (e: unknown): string => (e instanceof FileApiError ? (SAYS[e.code] ?? `Não foi possível enviar (${e.status || 'sem resposta'})`) : 'Não foi possível enviar')

export class FilesService implements FilesPort {
  readonly api: FilesApi
  /** Every upload of this page since it opened: the editor shows the live ones. */
  uploads = $state<Upload[]>([])
  #queue: { upload: Upload; run: () => Promise<void> }[] = []
  #running = 0
  #aborts = new Map<string, AbortController>()
  #links = new Map<string, { url: string; expiresAt: number }>()
  #asking = new Map<string, Promise<string>>()
  #n = 0

  constructor(api?: FilesApi) {
    this.api = api ?? new FilesApi({ token: () => session.token })
  }

  get available() {
    return this.api.signedIn
  }

  start(file: File, onDone: (info: FileInfo) => void, opts: { name?: string; encrypted?: boolean } = {}): Upload {
    const upload = $state<Upload>({ key: `u${++this.#n}`, name: opts.name ?? file.name, status: 'queued', sent: 0, total: file.size, error: '' })
    this.uploads.push(upload)
    const abort = new AbortController()
    this.#aborts.set(upload.key, abort)
    const run = async () => {
      upload.status = 'sending'
      try {
        const info = await uploadFile(this.api, sourceOf(file), {
          name: opts.name ?? file.name,
          encrypted: opts.encrypted,
          signal: abort.signal,
          onProgress: (sent, total) => {
            upload.sent = sent
            upload.total = total
          },
        })
        upload.status = 'done'
        onDone(info)
      } catch (e) {
        if (abort.signal.aborted) upload.status = 'cancelled'
        else {
          upload.status = 'failed'
          upload.error = describeError(e)
        }
      } finally {
        this.#aborts.delete(upload.key)
      }
    }
    this.#queue.push({ upload, run })
    this.#pump()
    return upload
  }

  #pump() {
    while (this.#running < MAX_AT_ONCE) {
      const next = this.#queue.shift()
      if (!next) return
      if (next.upload.status === 'cancelled') continue
      this.#running++
      void next.run().finally(() => {
        this.#running--
        this.#pump()
      })
    }
  }

  cancel(key: string) {
    const upload = this.uploads.find((u) => u.key === key)
    if (!upload || upload.status === 'done' || upload.status === 'failed') return
    upload.status = 'cancelled'
    this.#aborts.get(key)?.abort()
  }

  /** Forgets the uploads that are over, so the list does not grow for as long as the page stays open. */
  tidy() {
    this.uploads = this.uploads.filter((u) => u.status === 'queued' || u.status === 'sending')
  }

  async url(fileId: string, fresh = false): Promise<string> {
    const known = this.#links.get(fileId)
    if (!fresh && known && known.expiresAt - Date.now() > RENEW_MARGIN_MS) return known.url
    // many blocks asking for the same file at once share one request
    let pending = this.#asking.get(fileId)
    if (!pending) {
      pending = this.api
        .link(fileId)
        .then((l) => {
          this.#links.set(fileId, l)
          return l.url
        })
        .finally(() => this.#asking.delete(fileId))
      this.#asking.set(fileId, pending)
    }
    return pending
  }

  orphan(fileId: string, on: boolean) {
    this.#links.delete(fileId)
    void this.api.orphan(fileId, on).catch(() => undefined)
  }

  remove(fileIds: string[]) {
    for (const id of fileIds) {
      this.#links.delete(id)
      void this.api.remove(id).catch(() => undefined)
    }
  }
}

/** The one the app uses. */
export const files = new FilesService()
