// A stand-in for the file routes of the server, speaking the real protocol, with places to break it on purpose.
import { ErrorHttp } from '../types/shared/protos/auth'
import {
  CreateUploadRequest,
  CreateUploadResponse,
  FileInfo,
  FileLinkResponse,
  FinishUploadResponse,
  ListFilesResponse,
  UploadStatus,
} from '../types/shared/protos/files'
import { createHash } from 'node:crypto'

const CHUNK = 512 * 1024

interface Upload {
  id: string
  size: number
  name: string
  encrypted: boolean
  count: number
  pieces: Map<number, Uint8Array | null>
}

export interface Seen {
  method: string
  path: string
  bytes: number
}

export class FakeFiles {
  uploads = new Map<string, Upload>()
  files = new Map<string, FileInfo & { bytes: Uint8Array | null }>()
  seen: Seen[] = []
  inFlight = 0
  peakInFlight = 0
  orphaned = new Set<string>()
  deleted = new Set<string>()
  token: string | null = 'token'
  /** Hold on to the bytes of what is sent (small files only). */
  keepBytes = true
  /** Called before every request is handled: return a Response to answer instead, 'drop' to lose the answer, or nothing. */
  hook: (r: Seen, n: number) => Response | 'drop' | 'throw' | void | Promise<Response | 'drop' | 'throw' | void> = () => {}
  /** What the server decides a file is (the real one looks at the bytes; the fake at the name). */
  classify = (name: string): { mime: string; level: number } => {
    const ext = name.toLowerCase().split('.').pop()
    const by: Record<string, [string, number]> = { png: ['image/png', 1], jpg: ['image/jpeg', 1], mp4: ['video/mp4', 1], mp3: ['audio/mpeg', 1], pdf: ['application/pdf', 1], txt: ['text/plain', 2], zip: ['application/zip', 2] }
    const [mime, level] = by[ext ?? ''] ?? ['application/octet-stream', 3]
    return { mime, level }
  }
  /** Milliseconds each request takes (to see them overlap). */
  delay = 0
  #n = 0
  #ids = 0
  quota = Infinity
  used = 0

  fetch = async (input: RequestInfo | URL, init: RequestInit = {}): Promise<Response> => {
    const path = String(input)
    const method = init.method ?? 'GET'
    // a piece may go as a slice of the file; the server sees the same bytes either way
    const raw = init.body as Uint8Array | Blob | undefined
    const body = raw instanceof Blob ? new Uint8Array(await raw.arrayBuffer()) : raw
    const seen: Seen = { method, path, bytes: body?.length ?? 0 }
    this.seen.push(seen)
    this.inFlight++
    this.peakInFlight = Math.max(this.peakInFlight, this.inFlight)
    try {
      if (init.signal?.aborted) throw new DOMException('aborted', 'AbortError')
      if (this.delay) await new Promise((r) => setTimeout(r, this.delay))
      if (init.signal?.aborted) throw new DOMException('aborted', 'AbortError')
      const decision = await this.hook(seen, this.#n++)
      if (decision === 'throw') throw new TypeError('Failed to fetch')
      if (decision instanceof Response) return decision
      const headers = new Headers(init.headers)
      if (!headers.get('Authorization')?.startsWith('Bearer ') || (this.token && headers.get('Authorization') !== `Bearer ${this.token}`)) return this.err(401, 'unauthorized')
      const res = this.route(method, path, body, headers)
      if (decision === 'drop') throw new TypeError('Failed to fetch')
      return res
    } finally {
      this.inFlight--
    }
  }

  err(status: number, code: string, headers: Record<string, string> = {}) {
    return new Response(ErrorHttp.encode({ code, message: code }).finish() as BodyInit, { status, headers })
  }

  ok(status: number, bytes?: Uint8Array) {
    return new Response((bytes ?? null) as BodyInit | null, { status })
  }

  info(f: FileInfo & { bytes: Uint8Array | null }): FileInfo {
    return { id: f.id, size: f.size, mime: f.mime, level: f.level, name: f.name, encrypted: f.encrypted, createdAt: f.createdAt }
  }

  route(method: string, path: string, body: Uint8Array | undefined, headers: Headers): Response {
    let m: RegExpMatchArray | null
    if (method === 'POST' && path === '/files/uploads/') {
      const req = CreateUploadRequest.decode(body ?? new Uint8Array())
      if (req.size <= 0) return this.err(400, 'invalid_input')
      if (this.used + req.size > this.quota) return this.err(413, 'quota_exceeded')
      this.used += req.size
      const id = `up${++this.#ids}`
      const count = Math.ceil(req.size / CHUNK)
      this.uploads.set(id, { id, size: req.size, name: req.name, encrypted: req.encrypted, count, pieces: new Map() })
      return this.ok(201, CreateUploadResponse.encode({ uploadId: id, chunkSize: CHUNK, chunkCount: count }).finish())
    }
    if ((m = path.match(/^\/files\/uploads\/([^/]+)$/))) {
      const up = this.uploads.get(m[1])
      if (!up) return this.err(404, 'upload_not_found')
      if (method === 'DELETE') {
        this.uploads.delete(up.id)
        this.used -= up.size
        return this.ok(204)
      }
      const received = new Uint8Array(Math.ceil(up.count / 8))
      for (const n of up.pieces.keys()) received[n >> 3] |= 1 << (n & 7)
      return this.ok(200, UploadStatus.encode({ uploadId: up.id, size: up.size, chunkSize: CHUNK, chunkCount: up.count, received }).finish())
    }
    if (method === 'PUT' && (m = path.match(/^\/files\/uploads\/([^/]+)\/(\d+)$/))) {
      const up = this.uploads.get(m[1])
      if (!up) return this.err(404, 'upload_not_found')
      const n = Number(m[2])
      if (n >= up.count) return this.err(400, 'chunk_out_of_range')
      const want = n === up.count - 1 ? up.size - CHUNK * (up.count - 1) : CHUNK
      const piece = body ?? new Uint8Array()
      if (piece.length > CHUNK) return this.err(413, 'payload_too_large')
      if (piece.length !== want) return this.err(400, 'bad_chunk_size')
      if (createHash('sha256').update(piece).digest('hex') !== headers.get('X-Chunk-Sha256')) return this.err(422, 'chunk_hash_mismatch')
      up.pieces.set(n, this.keepBytes ? piece.slice() : null)
      return this.ok(204)
    }
    if (method === 'POST' && (m = path.match(/^\/files\/uploads\/([^/]+)\/finish$/))) {
      const up = this.uploads.get(m[1])
      if (!up) return this.err(404, 'upload_not_found')
      if (up.pieces.size !== up.count) return this.err(409, 'upload_incomplete')
      let bytes: Uint8Array | null = null
      if (this.keepBytes) {
        bytes = new Uint8Array(up.size)
        for (let n = 0; n < up.count; n++) bytes.set(up.pieces.get(n)!, n * CHUNK)
      }
      const kind = up.encrypted ? { mime: 'application/octet-stream', level: 3 } : this.classify(up.name)
      const file = { id: `f${++this.#ids}`, size: up.size, mime: kind.mime, level: kind.level, name: up.name, encrypted: up.encrypted, createdAt: Date.now(), bytes }
      this.files.set(file.id, file)
      this.uploads.delete(up.id)
      return this.ok(201, FinishUploadResponse.encode({ file: this.info(file) }).finish())
    }
    if (method === 'GET' && path.startsWith('/files/') && !path.includes('uploads')) {
      const all = [...this.files.values()].sort((a, b) => b.createdAt - a.createdAt).map((f) => this.info(f))
      return this.ok(200, ListFilesResponse.encode({ files: all, nextCursor: '', usedBytes: this.used, quotaBytes: this.quota === Infinity ? 0 : this.quota }).finish())
    }
    if (method === 'POST' && (m = path.match(/^\/files\/([^/]+)\/link$/))) {
      if (!this.files.has(m[1])) return this.err(404, 'file_not_found')
      return this.ok(200, FileLinkResponse.encode({ url: `/files/${m[1]}?exp=1&sig=ab`, expiresAt: Date.now() + 600_000 }).finish())
    }
    if ((m = path.match(/^\/files\/([^/]+)\/orphan$/))) {
      if (!this.files.has(m[1])) return this.err(404, 'file_not_found')
      if (method === 'PUT') this.orphaned.add(m[1])
      else this.orphaned.delete(m[1])
      return this.ok(204)
    }
    if (method === 'DELETE' && (m = path.match(/^\/files\/([^/]+)$/))) {
      if (!this.files.delete(m[1])) return this.err(404, 'file_not_found')
      this.deleted.add(m[1])
      return this.ok(204)
    }
    return this.err(404, 'not_found')
  }
}

/** Bytes that depend on the position, so a piece in the wrong place is noticed. */
export function patterned(size: number): Uint8Array<ArrayBuffer> {
  const b = new Uint8Array(new ArrayBuffer(size))
  for (let i = 0; i < size; i++) b[i] = (i * 31 + (i >> 8) * 7 + (i >> 16)) & 0xff
  return b
}
