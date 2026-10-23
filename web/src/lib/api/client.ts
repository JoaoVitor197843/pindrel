/** Resposta maior que isso não é de um servidor Plany: é descartada sem decodificar. */
const MAX_BODY_BYTES = 64 * 1024

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message)
  }
}

interface GetOptions {
  signal?: AbortSignal
  timeoutMs?: number
}

/** GET de um endpoint protobuf do servidor embutido (caminho relativo, na raiz). */
export async function getProto<T>(
  path: string,
  decode: (bytes: Uint8Array) => T,
  { signal, timeoutMs = 5000 }: GetOptions = {},
): Promise<T> {
  const timeout = new AbortController()
  const timer = setTimeout(() => timeout.abort(), timeoutMs)
  const onAbort = () => timeout.abort()
  signal?.addEventListener('abort', onAbort)
  try {
    const res = await fetch(path, {
      headers: { Accept: 'application/x-protobuf' },
      signal: timeout.signal,
    })
    if (!res.ok) throw new ApiError(res.status, `GET ${path}: ${res.status}`)
    const body = new Uint8Array(await res.arrayBuffer())
    if (body.length > MAX_BODY_BYTES) throw new ApiError(res.status, `GET ${path}: resposta grande demais`)
    return decode(body)
  } finally {
    clearTimeout(timer)
    signal?.removeEventListener('abort', onAbort)
  }
}
