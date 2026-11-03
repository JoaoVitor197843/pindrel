import { ServerInfo } from '../../types/shared/protos/server'

/**
 * Checks an address typed by the user: is there a Pindrel gateway behind it? The gateway lets any page read
 * `GET /server/info/` (CORS `*`, only the id exposed), which is how a page opened from another server can tell a real
 * Pindrel from any web server that happens to answer.
 */

export const MAX_INPUT_LENGTH = 300
export const MAX_NAME_LENGTH = 64
const MAX_BODY = 4096
const TIMEOUT_MS = 4000
const REACH_TIMEOUT_MS = 3000
const HOST_NAME = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/
const SERVER_ID = /^[A-Za-z0-9-]{1,64}$/

export interface Address {
  /** Only when the user typed it. */
  scheme?: 'http' | 'https'
  /** Lowercase, with brackets for IPv6. */
  hostname: string
  /** Empty when not typed. */
  port: string
}

export type ParseResult = { ok: true; address: Address } | { ok: false; error: 'empty' | 'invalid' }

/** `[http(s)://]host[:port][/]` and nothing else: no user info, path, query or spaces. */
export function parseAddress(input: string): ParseResult {
  const text = input.trim()
  if (!text) return { ok: false, error: 'empty' }
  if (text.length > MAX_INPUT_LENGTH || /[\s\\?#@]/.test(text)) return { ok: false, error: 'invalid' }
  let scheme: Address['scheme']
  let rest = text
  const m = /^([a-z][a-z0-9+.-]*):\/\/(.*)$/i.exec(text)
  if (m) {
    const s = m[1].toLowerCase()
    if (s !== 'http' && s !== 'https') return { ok: false, error: 'invalid' }
    scheme = s
    rest = m[2]
  }
  if (rest.endsWith('/')) rest = rest.slice(0, -1)
  if (!rest || rest.includes('/')) return { ok: false, error: 'invalid' }
  let url: URL
  try {
    url = new URL(`http://${rest}`)
  } catch {
    return { ok: false, error: 'invalid' }
  }
  // `host.` and `host` are the same server: one spelling, so the origin (the list's key) is too
  const hostname = url.hostname.replace(/\.$/, '')
  const ipv6 = hostname.startsWith('[') && hostname.endsWith(']')
  if (!ipv6 && !HOST_NAME.test(hostname)) return { ok: false, error: 'invalid' }
  // the port is read from the text: the URL parser drops the default one of `http` (80), which is not the default of https
  const typedPort = /:(\d*)$/.exec(rest)
  if (typedPort && (typedPort[1] === '' || Number(typedPort[1]) === 0)) return { ok: false, error: 'invalid' }
  return { ok: true, address: { scheme, hostname, port: typedPort ? String(Number(typedPort[1])) : '' } }
}

export type Inspection =
  | { ok: true; name: string; serverId: string; origin: string }
  | { ok: false; reason: Failure }

/**
 * Why it failed, as far as a browser lets us know. `blocked`: something answers but the page may not read it (CORS,
 * which is what an older gateway does); `timeout`: no answer in time; `unreachable`: refused, unknown name, or an
 * https certificate the browser does not trust; `invalid`: it answered and is not a Pindrel gateway.
 */
export type Failure = 'invalid' | 'blocked' | 'timeout' | 'unreachable'

const sleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve) => {
    if (signal.aborted) return resolve()
    const done = () => {
      clearTimeout(timer)
      signal.removeEventListener('abort', done)
      resolve()
    }
    const timer = setTimeout(done, ms)
    signal.addEventListener('abort', done)
  })

/**
 * Runs `fn` with a signal that aborts after `ms` or as soon as `outer` does, and always releases the timer and the
 * listener. `timedOut()` tells the two apart. One place for what `reach` and `inspect` both need.
 */
async function withTimeout<T>(
  ms: number,
  outer: AbortSignal | undefined,
  fn: (signal: AbortSignal, timedOut: () => boolean) => Promise<T>,
): Promise<T> {
  const controller = new AbortController()
  let expired = false
  const timer = setTimeout(() => {
    expired = true
    controller.abort()
  }, ms)
  const onAbort = () => controller.abort()
  if (outer?.aborted) controller.abort()
  else outer?.addEventListener('abort', onAbort)
  try {
    return await fn(controller.signal, () => expired)
  } finally {
    clearTimeout(timer)
    outer?.removeEventListener('abort', onAbort)
  }
}

/** Whether something answers at `url`, readable or not (`no-cors`: only "there was an answer" is learned). */
export function reach(url: string, signal?: AbortSignal): Promise<boolean> {
  return withTimeout(REACH_TIMEOUT_MS, signal, async (s) => {
    try {
      await fetch(`${url}/server/info/`, { mode: 'no-cors', cache: 'no-store', credentials: 'omit', signal: s })
      return true
    } catch {
      return false
    }
  })
}

/** Rejects when `signal` aborts, whatever the body stream does: a server that drips a byte at a time must not hold us. */
const whenAborted = (signal: AbortSignal) =>
  new Promise<never>((_, reject) => {
    if (signal.aborted) return reject(new Error('aborted'))
    signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true })
  })

async function readCapped(res: Response, max: number, signal: AbortSignal): Promise<Uint8Array | null> {
  const declared = Number(res.headers.get('content-length'))
  if (declared > max) return null
  // without a stream the only way to read it is all at once, which is exactly what the cap is there to prevent
  if (!res.body) return null
  const reader = res.body.getReader()
  const parts: Uint8Array[] = []
  let total = 0
  const aborted = whenAborted(signal)
  aborted.catch(() => {}) // the race below is what observes it
  for (;;) {
    let chunk: ReadableStreamReadResult<Uint8Array>
    try {
      chunk = await Promise.race([reader.read(), aborted])
    } catch (e) {
      void reader.cancel().catch(() => {})
      throw e
    }
    const { done, value } = chunk
    if (done) break
    total += value.length
    if (total > max) {
      void reader.cancel()
      return null
    }
    parts.push(value)
  }
  const out = new Uint8Array(total)
  let at = 0
  for (const p of parts) {
    out.set(p, at)
    at += p.length
  }
  return out
}

/**
 * Asks `origin` who it is. `invalid`: it answered but is not a Pindrel gateway (wrong status or type, body that is not
 * a `ServerInfo`, no id, a redirect to another host); `unreachable`: no answer at all.
 */
export function inspect(origin: string, signal?: AbortSignal): Promise<Inspection> {
  return withTimeout(TIMEOUT_MS, signal, async (s, timedOut): Promise<Inspection> => {
    let res: Response
    try {
      res = await fetch(`${origin}/server/info/`, {
        cache: 'no-store',
        credentials: 'omit',
        headers: { Accept: 'application/x-protobuf' },
        signal: s,
      })
    } catch {
      if (s.aborted) return { ok: false, reason: timedOut() ? 'timeout' : 'unreachable' }
      // same failure for "nobody there" and "blocked by CORS": asking again without reading tells them apart
      return { ok: false, reason: (await reach(origin, signal)) ? 'blocked' : 'unreachable' }
    }
    // a redirect (http to https and back) is followed, but only inside the same host
    let final = new URL(origin)
    if (res.url) {
      const got = new URL(res.url)
      if ((got.protocol !== 'http:' && got.protocol !== 'https:') || got.hostname !== final.hostname) {
        void res.body?.cancel()
        return { ok: false, reason: 'invalid' }
      }
      final = got
    }
    const id = res.headers.get('x-pindrel-id') ?? ''
    if (res.status !== 200 || !res.headers.get('content-type')?.startsWith('application/x-protobuf') || !SERVER_ID.test(id)) {
      void res.body?.cancel()
      return { ok: false, reason: 'invalid' }
    }
    let body: Uint8Array | null
    try {
      body = await readCapped(res, MAX_BODY, s)
    } catch {
      return { ok: false, reason: timedOut() ? 'timeout' : 'unreachable' }
    }
    if (!body) return { ok: false, reason: 'invalid' }
    try {
      const name = ServerInfo.decode(body).name.trim()
      if (!name || name.length > MAX_NAME_LENGTH) return { ok: false, reason: 'invalid' }
      return { ok: true, name, serverId: id, origin: final.origin }
    } catch {
      return { ok: false, reason: 'invalid' }
    }
  })
}

export type FindResult =
  | { ok: true; name: string; serverId: string; origin: string }
  | { ok: false; error: 'empty' | 'invalid' | 'mixed' | 'invalid-server' | Exclude<Failure, 'invalid'>; host?: string; https?: boolean }

/** http gets a head start; https joins if http has not answered by then (or has already failed). */
const STAGGER_MS = 250

/**
 * Tries the schemes with a short stagger instead of one after the other (the worst case was the sum of the timeouts)
 * and keeps the first valid answer. The loser is aborted, so no request outlives the call.
 */
async function firstValid(
  host: string,
  schemes: ('http' | 'https')[],
  signal?: AbortSignal,
): Promise<{ winner?: Extract<Inspection, { ok: true }>; reasons: Failure[] }> {
  const group = new AbortController()
  const relay = () => group.abort()
  if (signal?.aborted) group.abort()
  else signal?.addEventListener('abort', relay)
  let winner: Extract<Inspection, { ok: true }> | undefined
  const reasons: Failure[] = []
  const run = async (scheme: string) => {
    const r = await inspect(`${scheme}://${host}`, group.signal)
    if (r.ok) {
      winner ??= r
      group.abort()
    } else if (!winner) {
      reasons.push(r.reason)
    }
  }
  try {
    const [head, ...tail] = schemes
    const first = run(head)
    const rest = tail.map(async (scheme) => {
      await Promise.race([sleep(STAGGER_MS, group.signal), first])
      if (!group.signal.aborted) await run(scheme)
    })
    await Promise.all([first, ...rest])
  } finally {
    signal?.removeEventListener('abort', relay)
  }
  return { winner, reasons }
}

/**
 * http when the user typed no scheme, then https; exactly what was typed otherwise. A page served over https cannot
 * talk to an http server (mixed content), so there only https is tried.
 */
export async function findServer(input: string, signal?: AbortSignal): Promise<FindResult> {
  const parsed = parseAddress(input)
  if (!parsed.ok) return { ok: false, error: parsed.error }
  const { scheme, hostname, port } = parsed.address
  const host = port ? `${hostname}:${port}` : hostname
  const pageIsHttps = window.location.protocol === 'https:'
  const schemes: ('http' | 'https')[] = scheme ? [scheme] : pageIsHttps ? ['https'] : ['http', 'https']
  const { winner, reasons } = await firstValid(host, schemes, signal)
  if (winner) return winner
  const rank: Record<Failure, number> = { invalid: 3, blocked: 2, timeout: 1, unreachable: 0 }
  const worst = reasons.reduce<Failure>((a, b) => (rank[b] > rank[a] ? b : a), 'unreachable')
  if (worst === 'invalid') return { ok: false, error: 'invalid-server', host }
  if (worst === 'unreachable' && pageIsHttps && scheme === 'http') return { ok: false, error: 'mixed', host }
  return { ok: false, error: worst, host, https: schemes.includes('https') }
}
