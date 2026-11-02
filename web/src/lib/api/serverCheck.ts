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
  const hostname = url.hostname
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

/** Whether something answers at `url`, readable or not (`no-cors`: only "there was an answer" is learned). */
export async function reach(url: string, signal?: AbortSignal): Promise<boolean> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), REACH_TIMEOUT_MS)
  const onAbort = () => controller.abort()
  signal?.addEventListener('abort', onAbort)
  try {
    await fetch(`${url}/server/info/`, { mode: 'no-cors', cache: 'no-store', credentials: 'omit', signal: controller.signal })
    return true
  } catch {
    return false
  } finally {
    clearTimeout(timer)
    signal?.removeEventListener('abort', onAbort)
  }
}

async function readCapped(res: Response, max: number): Promise<Uint8Array | null> {
  const declared = Number(res.headers.get('content-length'))
  if (declared > max) return null
  if (!res.body) {
    const all = new Uint8Array(await res.arrayBuffer())
    return all.length <= max ? all : null
  }
  const reader = res.body.getReader()
  const parts: Uint8Array[] = []
  let total = 0
  for (;;) {
    const { done, value } = await reader.read()
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
export async function inspect(origin: string, signal?: AbortSignal): Promise<Inspection> {
  const timeout = new AbortController()
  const timer = setTimeout(() => timeout.abort(), TIMEOUT_MS)
  const onAbort = () => timeout.abort()
  signal?.addEventListener('abort', onAbort)
  try {
    let res: Response
    try {
      res = await fetch(`${origin}/server/info/`, {
        cache: 'no-store',
        credentials: 'omit',
        headers: { Accept: 'application/x-protobuf' },
        signal: timeout.signal,
      })
    } catch {
      if (timeout.signal.aborted) return { ok: false, reason: signal?.aborted ? 'unreachable' : 'timeout' }
      // same failure for "nobody there" and "blocked by CORS": asking again without reading tells them apart
      return { ok: false, reason: (await reach(origin, signal)) ? 'blocked' : 'unreachable' }
    }
    // a redirect (http to https and back) is followed, but only inside the same host
    let final = new URL(origin)
    if (res.url) {
      const got = new URL(res.url)
      if ((got.protocol !== 'http:' && got.protocol !== 'https:') || got.hostname !== final.hostname) {
        return { ok: false, reason: 'invalid' }
      }
      final = got
    }
    const id = res.headers.get('x-pindrel-id') ?? ''
    if (res.status !== 200 || !res.headers.get('content-type')?.startsWith('application/x-protobuf') || !SERVER_ID.test(id)) {
      return { ok: false, reason: 'invalid' }
    }
    let body: Uint8Array | null
    try {
      body = await readCapped(res, MAX_BODY)
    } catch {
      return { ok: false, reason: 'unreachable' }
    }
    if (!body) return { ok: false, reason: 'invalid' }
    try {
      const name = ServerInfo.decode(body).name.trim()
      if (!name || name.length > MAX_NAME_LENGTH) return { ok: false, reason: 'invalid' }
      return { ok: true, name, serverId: id, origin: final.origin }
    } catch {
      return { ok: false, reason: 'invalid' }
    }
  } finally {
    clearTimeout(timer)
    signal?.removeEventListener('abort', onAbort)
  }
}

export type FindResult =
  | { ok: true; name: string; serverId: string; origin: string }
  | { ok: false; error: 'empty' | 'invalid' | 'mixed' | 'invalid-server' | Exclude<Failure, 'invalid'>; host?: string; https?: boolean }

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
  const rank: Record<Failure, number> = { invalid: 3, blocked: 2, timeout: 1, unreachable: 0 }
  let worst: Failure = 'unreachable'
  for (const s of schemes) {
    const r = await inspect(`${s}://${host}`, signal)
    if (r.ok) return r
    if (signal?.aborted) break
    if (rank[r.reason] > rank[worst]) worst = r.reason
  }
  if (worst === 'invalid') return { ok: false, error: 'invalid-server', host }
  if (worst === 'unreachable' && pageIsHttps && scheme === 'http') return { ok: false, error: 'mixed', host }
  return { ok: false, error: worst, host, https: schemes.includes('https') }
}

export function errorText(r: Extract<FindResult, { ok: false }>): string {
  switch (r.error) {
    case 'empty':
      return 'Digite o endereço do servidor.'
    case 'invalid':
      return 'Endereço inválido. Use algo como 192.168.0.20:8095 ou meu.servidor.com.'
    case 'mixed':
      return 'Esta página usa https e o navegador bloqueia servidores http. Use o endereço https do servidor.'
    case 'invalid-server':
      return `${r.host} respondeu, mas não é um servidor Pindrel (gateway) válido.`
    case 'blocked':
      return `${r.host} respondeu, mas o navegador não deixou a página ler a resposta (CORS). Provavelmente o gateway desse servidor é de uma versão antiga: atualize-o.`
    case 'timeout':
      return `${r.host} não respondeu a tempo. Confira se o aparelho está ligado e se você está na mesma rede ou VPN.`
    case 'unreachable':
      return `Não foi possível conectar a ${r.host}: a conexão foi recusada ou o endereço não existe. Confira o endereço e a porta${r.https ? ' (e, em https, se o certificado é confiável)' : ''}.`
  }
}
