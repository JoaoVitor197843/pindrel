// Sending files to the server and asking for them back (backend/internal/files). A file is sent in pieces of 512 KiB, a
// couple at a time, each with its SHA-256, so nothing larger than a piece is ever held in memory, a broken line costs one
// piece, and the gateway (which holds a whole request in memory) is never asked for more than it can take.
import { ErrorHttp } from '../../types/shared/protos/auth'
import {
  CreateUploadRequest,
  CreateUploadResponse,
  FileInfo,
  FileLinkResponse,
  FinishUploadResponse,
  ListFilesResponse,
  UploadStatus,
} from '../../types/shared/protos/files'
import { sha256, toHex } from '../sha256'

export type { FileInfo } from '../../types/shared/protos/files'

/** The size of every piece but the last. It has to match the server's `files.ChunkSize` and stay under the gateway's body limit. */
export const CHUNK_SIZE = 512 * 1024

/** What the server answered, or why there was no answer. `code` is the server's own (`quota_exceeded`, ...) or one of ours. */
export class FileApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    /** How long the server asked to wait before trying again (Retry-After), in milliseconds. */
    readonly retryAfterMs = 0,
  ) {
    super(message)
  }
}

/** Where the bytes come from. A file is one; so is anything that makes bytes piece by piece (an encrypted file, a test). */
export interface ByteSource {
  readonly size: number
  /**
   * The bytes from `start` to `end`. `scratch` is a buffer the caller is done with: a source that can read into it does,
   * so a long upload keeps using the same few hundred KiB instead of allocating a new buffer for every piece (and leaving
   * the browser to collect the old ones whenever it gets round to it: measured, 76 MB of page memory on a 300 MB file
   * against 3 MB). The result may be a view of `scratch`'s buffer once it was taken over; its `.buffer` is the one to pass next time.
   */
  read(start: number, end: number, scratch?: ArrayBuffer): Promise<Uint8Array>
  /**
   * The same bytes as something the browser can send without copying them into the page's memory (a slice of a file). When
   * there is one, `read` is only for the hash and its buffer is dropped at once.
   */
  slice?(start: number, end: number): Blob
}

/** Reads a slice of a file into `scratch` with a byte-stream reader; null when the browser cannot (then a new buffer is made). */
async function readInto(part: Blob, want: number, scratch: ArrayBuffer): Promise<Uint8Array | null> {
  let reader: ReadableStreamBYOBReader
  try {
    reader = (part as { stream?: () => ReadableStream }).stream!().getReader({ mode: 'byob' })
  } catch {
    return null
  }
  let buffer = scratch
  let got = 0
  try {
    while (got < want) {
      const { done, value } = await reader.read(new Uint8Array(buffer, got, want - got))
      if (value) {
        buffer = value.buffer as ArrayBuffer
        got += value.byteLength
      }
      if (done) break
    }
  } finally {
    reader.releaseLock()
  }
  return new Uint8Array(buffer, 0, got)
}

export function sourceOf(blob: Blob): ByteSource {
  return {
    size: blob.size,
    async read(start, end, scratch) {
      const part = blob.slice(start, end)
      if (scratch && scratch.byteLength >= end - start) {
        const filled = await readInto(part, end - start, scratch).catch(() => null)
        if (filled) return filled
      }
      return new Uint8Array(await part.arrayBuffer())
    },
    slice: (start, end) => blob.slice(start, end),
  }
}

const MAX_REPLY = 1 << 20

export interface ApiOptions {
  /** The session's access token, or null when nobody is signed in. */
  token: () => string | null
  fetch?: typeof fetch
}

export class FilesApi {
  readonly #token: () => string | null
  readonly #fetch: typeof fetch

  constructor({ token, fetch: f }: ApiOptions) {
    this.#token = token
    this.#fetch = f ?? ((...args) => globalThis.fetch(...args))
  }

  get signedIn() {
    return !!this.#token()
  }

  async #call(method: string, path: string, init: { body?: BodyInit; headers?: Record<string, string>; signal?: AbortSignal; auth?: boolean } = {}): Promise<Response> {
    const headers: Record<string, string> = { Accept: 'application/x-protobuf', ...init.headers }
    if (init.auth !== false) {
      const token = this.#token()
      if (!token) throw new FileApiError(401, 'not_signed_in', 'sem sessão')
      headers.Authorization = `Bearer ${token}`
    }
    let res: Response
    try {
      res = await this.#fetch(path, { method, headers, body: init.body, signal: init.signal })
    } catch (e) {
      if (init.signal?.aborted) throw init.signal.reason instanceof Error ? init.signal.reason : new DOMException('Cancelado', 'AbortError')
      throw new FileApiError(0, 'network', e instanceof Error ? e.message : 'sem conexão')
    }
    if (res.ok) return res
    let code = 'http_error'
    try {
      const text = new Uint8Array(await res.arrayBuffer())
      if (text.length <= MAX_REPLY) code = ErrorHttp.decode(text).code || code
    } catch {
      // not a protobuf answer: the status is all there is
    }
    const retry = Number(res.headers.get('retry-after'))
    throw new FileApiError(res.status, code, `${method} ${path}: ${res.status} ${code}`, Number.isFinite(retry) && retry > 0 ? Math.min(retry, 60) * 1000 : 0)
  }

  async #bytes(res: Response): Promise<Uint8Array> {
    const b = new Uint8Array(await res.arrayBuffer())
    if (b.length > MAX_REPLY) throw new FileApiError(res.status, 'bad_reply', 'resposta grande demais')
    return b
  }

  async createUpload(size: number, name: string, encrypted: boolean, signal?: AbortSignal): Promise<CreateUploadResponse> {
    const body = CreateUploadRequest.encode({ size, name, encrypted }).finish()
    const res = await this.#call('POST', '/files/uploads/', { body: body as BodyInit, headers: { 'Content-Type': 'application/x-protobuf' }, signal })
    return CreateUploadResponse.decode(await this.#bytes(res))
  }

  async status(uploadId: string, signal?: AbortSignal): Promise<UploadStatus> {
    return UploadStatus.decode(await this.#bytes(await this.#call('GET', `/files/uploads/${uploadId}`, { signal })))
  }

  async putChunk(uploadId: string, n: number, bytes: Uint8Array | Blob, sum: string, signal?: AbortSignal): Promise<void> {
    await this.#call('PUT', `/files/uploads/${uploadId}/${n}`, { body: bytes as BodyInit, headers: { 'Content-Type': 'application/octet-stream', 'X-Chunk-Sha256': sum }, signal })
  }

  async finish(uploadId: string, signal?: AbortSignal): Promise<FileInfo> {
    const res = await this.#call('POST', `/files/uploads/${uploadId}/finish`, { signal })
    const file = FinishUploadResponse.decode(await this.#bytes(res)).file
    if (!file) throw new FileApiError(res.status, 'bad_reply', 'resposta sem arquivo')
    return file
  }

  async cancel(uploadId: string): Promise<void> {
    await this.#call('DELETE', `/files/uploads/${uploadId}`).catch(() => undefined)
  }

  /** A short-lived address that works in an <img>, a <video> or a link. */
  async link(fileId: string, signal?: AbortSignal): Promise<{ url: string; expiresAt: number }> {
    const r = FileLinkResponse.decode(await this.#bytes(await this.#call('POST', `/files/${fileId}/link`, { signal })))
    return { url: r.url, expiresAt: r.expiresAt }
  }

  async remove(fileId: string): Promise<void> {
    await this.#call('DELETE', `/files/${fileId}`)
  }

  /** Tells the server nothing uses the file any more (true) or that something does again (false). */
  async orphan(fileId: string, on: boolean): Promise<void> {
    await this.#call(on ? 'PUT' : 'DELETE', `/files/${fileId}/orphan`)
  }

  async list(after = ''): Promise<ListFilesResponse> {
    return ListFilesResponse.decode(await this.#bytes(await this.#call('GET', `/files/${after}`)))
  }
}

export interface UploadOptions {
  name?: string
  encrypted?: boolean
  signal?: AbortSignal
  /** Called as pieces are stored: bytes sent so far and the total. */
  onProgress?: (sent: number, total: number) => void
  /** Pieces in flight at once. */
  concurrency?: number
  /** Tries per request before giving up. */
  attempts?: number
  /** An upload that was already opened and may have pieces on the server: it continues where it stopped. */
  resume?: string
  /** Called with the id of the upload as soon as it exists, so a caller can resume it later. */
  onOpen?: (uploadId: string) => void
  /** For tests: waits `ms` milliseconds. */
  sleep?: (ms: number) => Promise<void>
}

/** Errors that mean "this will not work however often it is tried". */
const FINAL = new Set(['quota_exceeded', 'file_too_large', 'storage_full', 'too_many_uploads', 'upload_not_found', 'unauthorized', 'not_signed_in', 'invalid_input', 'chunk_out_of_range', 'bad_chunk_size'])

const abortError = () => new DOMException('Envio cancelado', 'AbortError')

function retryable(e: unknown): e is FileApiError {
  if (!(e instanceof FileApiError)) return false
  if (FINAL.has(e.code) || e.status === 401 || e.status === 403) return false
  // a connection that broke, a gateway or replica that is busy or restarting, a piece damaged on the way
  return e.status === 0 || e.status === 408 || e.status === 409 || e.status === 422 || e.status === 429 || e.status >= 500
}

const hasBit = (bitmap: Uint8Array, n: number) => ((bitmap[n >> 3] ?? 0) >> (n & 7)) & 1

/** Sends a file. Resolves with the finished file; rejects with a FileApiError, or an AbortError when cancelled. */
export async function uploadFile(api: FilesApi, source: ByteSource, opts: UploadOptions = {}): Promise<FileInfo> {
  const { signal, onProgress, concurrency = 2, attempts = 5, sleep = (ms) => new Promise((r) => setTimeout(r, ms)) } = opts
  if (source.size <= 0) throw new FileApiError(400, 'invalid_input', 'arquivo vazio')
  if (signal?.aborted) throw abortError()

  /** Tries a request again after a pause that grows, unless the error is final or the person cancelled. */
  async function persist<T>(run: () => Promise<T>): Promise<T> {
    for (let attempt = 1; ; attempt++) {
      if (signal?.aborted) throw abortError()
      try {
        return await run()
      } catch (e) {
        if (signal?.aborted) throw abortError()
        if (!retryable(e) || attempt >= attempts) throw e
        const pause = Math.max(e.retryAfterMs, Math.min(8000, 500 * 2 ** (attempt - 1)) * (0.75 + Math.random() * 0.5))
        await sleep(pause)
      }
    }
  }

  let uploadId = opts.resume ?? ''
  let count = Math.ceil(source.size / CHUNK_SIZE)
  let have: Uint8Array = new Uint8Array(0)
  if (uploadId) {
    try {
      const st = await persist(() => api.status(uploadId, signal))
      if (st.size !== source.size || st.chunkSize !== CHUNK_SIZE) throw new FileApiError(409, 'upload_mismatch', 'o envio guardado é de outro arquivo')
      have = st.received
      count = st.chunkCount
    } catch (e) {
      if (!(e instanceof FileApiError) || (e.code !== 'upload_not_found' && e.code !== 'upload_mismatch')) throw e
      uploadId = '' // gone or not this file: start over
    }
  }
  if (!uploadId) {
    const made = await persist(() => api.createUpload(source.size, opts.name ?? '', !!opts.encrypted, signal))
    uploadId = made.uploadId
    count = made.chunkCount
    have = new Uint8Array(0)
  }
  opts.onOpen?.(uploadId)

  let sent = 0
  const sizeOf = (n: number) => (n === count - 1 ? source.size - CHUNK_SIZE * (count - 1) : CHUNK_SIZE)
  const todo: number[] = []
  for (let n = 0; n < count; n++) {
    if (hasBit(have, n)) sent += sizeOf(n)
    else todo.push(n)
  }
  onProgress?.(sent, source.size)

  // the pieces left, shared by the workers in order: each takes the next one when it is free
  let next = 0
  let failure: unknown
  const worker = async () => {
    // one buffer per worker, filled again for every piece
    let scratch: ArrayBuffer | undefined = new ArrayBuffer(CHUNK_SIZE)
    while (!failure && !signal?.aborted) {
      const n = todo[next++]
      if (n === undefined) return
      try {
        const bytes = await source.read(n * CHUNK_SIZE, n * CHUNK_SIZE + sizeOf(n), scratch)
        scratch = bytes.buffer.byteLength >= CHUNK_SIZE ? (bytes.buffer as ArrayBuffer) : scratch
        if (bytes.length !== sizeOf(n)) throw new FileApiError(0, 'source_changed', 'o arquivo mudou durante o envio')
        const sum = toHex(await sha256(bytes))
        // what is sent is a slice of the file when the browser can send one: the page then holds a piece only while hashing it
        const body = source.slice ? source.slice(n * CHUNK_SIZE, n * CHUNK_SIZE + sizeOf(n)) : bytes
        await persist(() => api.putChunk(uploadId, n, body, sum, signal))
        sent += bytes.length
        onProgress?.(sent, source.size)
      } catch (e) {
        failure ??= e
        return
      }
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, Math.min(concurrency, todo.length || 1)) }, worker))
  if (signal?.aborted) {
    void api.cancel(uploadId)
    throw abortError()
  }
  if (failure) {
    // A half upload holds one of the person's few open slots for a day. Only a caller that asked for the id (`onOpen`) can
    // resume it later, so for anyone else every failure drops it; with `onOpen`, a tired connection keeps it and a final
    // error (which will not get better) still drops it.
    if (!opts.onOpen || !(failure instanceof FileApiError) || FINAL.has(failure.code) || failure.code === 'source_changed') void api.cancel(uploadId)
    throw failure
  }

  // Joining a large file takes the replica a while, and a slow answer is not a failed join: ask again. If the first answer
  // was lost after the join had worked, the upload is gone ("not found"): the file is then looked up among the newest.
  let asked = 0
  let file: FileInfo
  try {
    file = await persist(() => (asked++, api.finish(uploadId, signal)))
  } catch (e) {
    const found = asked > 1 && e instanceof FileApiError && e.code === 'upload_not_found' ? await justFinished(api, source.size, !!opts.encrypted) : null
    if (!found) throw e
    file = found
  }
  onProgress?.(source.size, source.size)
  return file
}

/** A file of this size made in the last quarter of an hour: what a finish whose answer was lost left behind. */
async function justFinished(api: FilesApi, size: number, encrypted: boolean): Promise<FileInfo | null> {
  try {
    const recent = (await api.list()).files
    return recent.find((f) => f.size === size && f.encrypted === encrypted && Date.now() - f.createdAt < 15 * 60_000) ?? null
  } catch {
    return null
  }
}
