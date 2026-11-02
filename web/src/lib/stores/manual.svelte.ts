import { findServer, errorText, MAX_NAME_LENGTH, reach } from '../api/serverCheck'

export { reach }
import { remember, trustOf } from './trust'

/**
 * Servers the user typed in (outside the LAN, or just not announced). Kept in the browser only. Each one is checked
 * on its own, from time to time: the network announces nothing about them.
 */
const KEY = 'plany:manual-servers'
export const MAX_MANUAL = 16
const POLL_MS = 15_000
/** Like the page's own server: one lost packet does not bring the dot down, two in a row do. */
const FAILURES = 2

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
   * Checks that [input] is a Plany gateway and only then saves it. [name] replaces the server's own name when it has
   * text. One call at a time: a second tap on "Adicionar" while the first one is checking does nothing.
   */
  async add(input: string, name: string, signal?: AbortSignal): Promise<AddResult> {
    if (this.#adding) return { ok: false, error: 'Já estou verificando um endereço.' }
    this.#adding = true
    try {
      if (this.list.length >= MAX_MANUAL) return { ok: false, error: `Limite de ${MAX_MANUAL} servidores adicionados.` }
      const found = await findServer(input, signal)
      if (!found.ok) return { ok: false, error: signal?.aborted ? 'Cancelado.' : errorText(found) }
      if (found.origin === window.location.origin) return { ok: false, error: 'Este é o servidor desta página.' }
      if (this.list.some((s) => s.id === found.origin)) return { ok: false, error: 'Este servidor já foi adicionado.' }
      if (this.list.some((s) => s.serverId === found.serverId)) {
        return { ok: false, error: 'Este servidor já foi adicionado com outro endereço.' }
      }
      if (this.list.length >= MAX_MANUAL) return { ok: false, error: `Limite de ${MAX_MANUAL} servidores adicionados.` }
      const server: ManualServer = {
        id: found.origin,
        name: cleanName(name) || found.name,
        trustName: found.name,
        serverId: found.serverId,
        url: found.origin,
        address: new URL(found.origin).host,
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

  async check(): Promise<void> {
    const servers = this.list
    const results = await Promise.all(servers.map(async (s) => [s.id, await reach(s.url)] as const))
    const next: Record<string, ManualHealth> = { ...this.health }
    for (const [id, up] of results) {
      if (!this.list.some((s) => s.id === id)) continue // removed while it was being checked
      const failures = up ? 0 : (this.#failures.get(id) ?? 0) + 1
      this.#failures.set(id, failures)
      next[id] = up ? 'connected' : failures >= FAILURES || this.health[id] === 'disconnected' ? 'disconnected' : (this.health[id] ?? 'connected')
    }
    this.health = next
  }

  /** Every [POLL_MS], and when the network or the tab comes back; a hidden tab does not poll. */
  start(): () => void {
    let timer: ReturnType<typeof setTimeout> | undefined
    let stopped = false
    let running = false
    const tick = async () => {
      if (running) return
      running = true
      clearTimeout(timer)
      try {
        if (!document.hidden && this.list.length) await this.check()
      } finally {
        running = false
      }
      if (!stopped) timer = setTimeout(tick, POLL_MS)
    }
    const wake = () => void tick()
    window.addEventListener('online', wake)
    document.addEventListener('visibilitychange', wake)
    void tick()
    return () => {
      stopped = true
      clearTimeout(timer)
      window.removeEventListener('online', wake)
      document.removeEventListener('visibilitychange', wake)
    }
  }
}

export const manual = new ManualServers()
