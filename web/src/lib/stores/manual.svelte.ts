import { untrack } from 'svelte'
import { findServer, inspect, MAX_NAME_LENGTH, reach } from '../api/serverCheck'
import { errorText } from '../api/serverCheckText'

export { reach }
import { remember, trustOf } from './trust'

/**
 * Servers the user typed in (outside the LAN, or just not announced). Kept in the browser only. Each one is checked
 * on its own, from time to time: the network announces nothing about them.
 */
const KEY = 'pindrel:manual-servers'
export const MAX_MANUAL = 16
const POLL_MS = 15_000
/** Like the page's own server: one lost packet does not bring the dot down, two in a row do. */
const FAILURES = 2
/** At most this many checks in flight: 16 servers must not open 16 sockets at once on a weak device. */
const CONCURRENCY = 4
/** Every Nth round also reads who answers (the id), not only that someone does: ~1 per minute. */
const STRONG_EVERY = 4

async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length)
  let next = 0
  const worker = async () => {
    for (;;) {
      const i = next++
      if (i >= items.length) return
      out[i] = await fn(items[i])
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
  return out
}

/** `other`: something answers there, but it is not the server that was saved. */
type Probe = 'up' | 'down' | 'other'

export interface ManualServer {
  /** Stable and unique: the origin. */
  id: string
  /** What the list shows (the server's own name unless the user chose another). */
  name: string
  /** The name the server gave itself: what `trust` knows it by, whatever it is called here. */
  trustName: string
  serverId: string
  /** `http(s)://host[:port]` */
  url: string
  /** `host[:port]` */
  address: string
  /** Only when the server has a secure side this browser does not trust yet: the page that explains how to connect. */
  connectUrl?: string
}

export type ManualHealth = 'connected' | 'disconnected'

function valid(e: unknown): e is ManualServer {
  if (typeof e !== 'object' || e === null) return false
  const m = e as Record<string, unknown>
  if (![m.id, m.name, m.trustName, m.serverId, m.url, m.address].every((v) => typeof v === 'string')) return false
  try {
    const u = new URL(m.url as string)
    return (
      (u.protocol === 'http:' || u.protocol === 'https:') &&
      u.origin === m.url &&
      m.id === m.url &&
      (m.connectUrl === undefined || (typeof m.connectUrl === 'string' && sameHostPage(m.connectUrl, u))) &&
      m.address === u.host &&
      (m.name as string).length > 0 &&
      (m.name as string).length <= MAX_NAME_LENGTH &&
      (m.trustName as string).length > 0 &&
      (m.trustName as string).length <= MAX_NAME_LENGTH
    )
  } catch {
    return false
  }
}

function sameHostPage(connectUrl: string, server: URL): boolean {
  try {
    const c = new URL(connectUrl)
    return (c.protocol === 'http:' || c.protocol === 'https:') && c.hostname === server.hostname && c.pathname === '/server/connect/'
  } catch {
    return false
  }
}

function read(): ManualServer[] {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(KEY) ?? '[]')
    if (!Array.isArray(parsed)) return []
    const seen = new Set<string>()
    return parsed.filter(valid).filter((s) => !seen.has(s.id) && seen.add(s.id)).slice(0, MAX_MANUAL)
  } catch {
    return []
  }
}

function write(list: ManualServer[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(list))
  } catch {
    // no storage: the server works until the page is closed
  }
}

export function cleanName(name: string): string {
  return name.replace(/\s+/g, ' ').trim().slice(0, MAX_NAME_LENGTH)
}

export type AddResult = { ok: true; server: ManualServer } | { ok: false; error: string }

export class ManualServers {
  list = $state<ManualServer[]>(read())
  health = $state<Record<string, ManualHealth>>({})

  #failures = new Map<string, number>()
  #adding = false

  /**
   * Checks that [input] is a Pindrel gateway and only then saves it. [name] replaces the server's own name when it has
   * text. One call at a time: a second tap on "Adicionar" while the first one is checking does nothing.
   */
  async add(input: string, name: string, signal?: AbortSignal): Promise<AddResult> {
    if (this.#adding) return { ok: false, error: 'Já estou verificando um endereço.' }
    this.#adding = true
    try {
      if (this.list.length >= MAX_MANUAL) return { ok: false, error: `Limite de ${MAX_MANUAL} servidores adicionados.` }
      const found = await findServer(input, signal)
      if (!found.ok) return { ok: false, error: signal?.aborted ? 'Cancelado.' : errorText(found) }
      // The server has a secure side: use it when this browser already trusts it; otherwise keep the plain address and
      // remember the page that explains how to connect securely (the certificate is installed once per device).
      let origin = found.origin
      let connectUrl: string | undefined
      if (found.tlsPort && origin.startsWith('http:')) {
        const u = new URL(origin)
        const secure = await inspect(`https://${u.hostname.includes(':') ? `[${u.hostname.replace(/^\[|\]$/g, '')}]` : u.hostname}:${found.tlsPort}`, signal)
        if (secure.ok && secure.serverId === found.serverId) origin = secure.origin
        else connectUrl = `${origin}/server/connect/`
      }
      if (origin === window.location.origin || found.origin === window.location.origin) return { ok: false, error: 'Este é o servidor desta página.' }
      if (this.list.some((s) => s.id === origin || s.id === found.origin)) return { ok: false, error: 'Este servidor já foi adicionado.' }
      if (this.list.some((s) => s.serverId === found.serverId)) {
        return { ok: false, error: 'Este servidor já foi adicionado com outro endereço.' }
      }
      if (this.list.length >= MAX_MANUAL) return { ok: false, error: `Limite de ${MAX_MANUAL} servidores adicionados.` }
      const server: ManualServer = {
        id: origin,
        name: cleanName(name) || found.name,
        trustName: found.name,
        serverId: found.serverId,
        url: origin,
        address: new URL(origin).host,
        ...(connectUrl ? { connectUrl } : {}),
      }
      // an id that differs from the one this name had must not be learned silently: opening it will ask
      if (trustOf(server.trustName, server.serverId) !== 'changed') remember(server.trustName, server.serverId)
      this.list = [...this.list, server]
      this.health = { ...this.health, [server.id]: 'connected' }
      write(this.list)
      return { ok: true, server }
    } finally {
      this.#adding = false
    }
  }

  remove(id: string) {
    if (!this.list.some((s) => s.id === id)) return
    this.list = this.list.filter((s) => s.id !== id)
    const { [id]: _gone, ...rest } = this.health
    this.health = rest
    this.#failures.delete(id)
    write(this.list)
  }

  /** The id the server has now, when it is not the one saved (the list shows it once the user agrees). */
  update(id: string, serverId: string) {
    const at = this.list.findIndex((s) => s.id === id)
    if (at < 0 || this.list[at].serverId === serverId) return
    this.list = this.list.map((s, i) => (i === at ? { ...s, serverId } : s))
    write(this.list)
  }

  async #probe(s: ManualServer, strong: boolean): Promise<Probe> {
    if (strong) {
      const r = await inspect(s.url)
      if (r.ok) return r.serverId === s.serverId ? 'up' : 'other'
      if (r.reason === 'invalid') return 'other'
      if (r.reason !== 'blocked') return 'down'
      // an older gateway the browser may not read: fall back to "someone answers"
    }
    return (await reach(s.url)) ? 'up' : 'down'
  }

  /**
   * [strong] also compares the id the server gives now with the saved one, so another machine that took over the
   * address does not keep a green dot. It is shown as disconnected; opening it asks, like any other change.
   */
  async check(strong = false): Promise<void> {
    const servers = this.list
    const results = await mapLimit(servers, CONCURRENCY, async (s) => [s.id, await this.#probe(s, strong)] as const)
    const next: Record<string, ManualHealth> = { ...this.health }
    for (const [id, probe] of results) {
      if (!this.list.some((s) => s.id === id)) continue // removed while it was being checked
      const failures = probe === 'up' ? 0 : probe === 'other' ? FAILURES : (this.#failures.get(id) ?? 0) + 1
      this.#failures.set(id, failures)
      next[id] =
        probe === 'up'
          ? 'connected'
          : failures >= FAILURES || this.health[id] === 'disconnected'
            ? 'disconnected'
            : (this.health[id] ?? 'connected')
    }
    this.health = next
  }

  /** Every [POLL_MS], and when the network or the tab comes back; a hidden tab does not poll. */
  start(): () => void {
    let timer: ReturnType<typeof setTimeout> | undefined
    let stopped = false
    let running = false
    let round = 0
    const tick = async () => {
      if (running) return
      running = true
      clearTimeout(timer)
      try {
        if (!document.hidden && this.list.length) await this.check(round++ % STRONG_EVERY === 0)
      } finally {
        running = false
      }
      if (!stopped) timer = setTimeout(tick, POLL_MS)
    }
    const wake = () => void tick()
    window.addEventListener('online', wake)
    document.addEventListener('visibilitychange', wake)
    // called from an `$effect`: reading the list here must not make the effect rerun (and re-check) on every add/remove
    untrack(() => void tick())
    return () => {
      stopped = true
      clearTimeout(timer)
      window.removeEventListener('online', wake)
      document.removeEventListener('visibilitychange', wake)
    }
  }
}

export const manual = new ManualServers()
