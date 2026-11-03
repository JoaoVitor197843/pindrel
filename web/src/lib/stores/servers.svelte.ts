import { fetchDiscoveredServers } from '../api/servers'
import type { DiscoveredServer } from '../../types/shared/protos/server'
import { inspect } from '../api/serverCheck'
import { manual } from './manual.svelte'
import { parsePort } from '../api/serverCheck'
import { toast } from './toast.svelte'
import { remember, trustOf } from './trust'

export interface ServerOption {
  id: string
  name: string
  /** How it appears on screen (`192.168.0.20:8095`). */
  address: string
  /** The server's origin, where the browser goes when it is chosen. */
  url: string
  /** What the server announced as its own id (empty or absent: it announces none). */
  serverId?: string
  /** Typed in by the user (kept in `manual`), not found on the network. */
  manual?: boolean
  /** The name `trust` knows it by, when the list shows another one the user chose. */
  trustName?: string
}

// The open page is always the embedded server's, and it is always the default.
export const embedded: ServerOption = {
  id: 'embedded',
  name: 'Embutido',
  address: window.location.host,
  url: window.location.origin,
}

export const MAX_SERVERS = 64
const MAX_NAME_LENGTH = 64
const MAX_ADDRESSES = 8
const LOST_GRACE_MS = 15_000
const POLL_FOUND_MS = 15_000
const POLL_EMPTY_MS = 5_000
const POLL_MAX_MS = 60_000

/** An announcement is anonymous: only ordinary IPv4 matters (no loopback, link-local, multicast). */
export function isUsableIpv4(ip: string): boolean {
  const parts = ip.split('.')
  if (parts.length !== 4) return false
  const octets: number[] = []
  for (const p of parts) {
    const n = Number(p)
    if (!/^\d{1,3}$/.test(p) || n > 255 || p !== String(n)) return false
    octets.push(n)
  }
  const [first, second] = octets
  if (first === 0 || first === 127 || first >= 224) return false
  return !(first === 169 && second === 254)
}

/** Stable identifier derived from the name (lowercase, no accents, only letters, numbers and hyphens). */
export function idFor(name: string): string {
  const slug = name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
  return slug || 'servidor'
}

/** The server found on the network as an option, or null if the announcement is no good. */
export function toOption(server: DiscoveredServer): ServerOption | null {
  if (!server.name || server.name.length > MAX_NAME_LENGTH) return null
  if (!Number.isInteger(server.port) || server.port <= 0 || server.port > 65535) return null
  const ip = [...new Set(server.addresses.filter(isUsableIpv4))].sort().slice(0, MAX_ADDRESSES)[0]
  const host = ip ?? (server.host ? `${server.host}.local` : '')
  if (!host) return null
  const address = `${host}:${server.port}`
  const serverId = /^[A-Za-z0-9-]{1,64}$/.test(server.id ?? '') ? server.id : ''
  return { id: idFor(server.name), name: server.name, address, url: `http://${address}`, serverId }
}

/**
 * The other servers on the network, as the gateway delivers them. The browser has no mDNS: the list comes from
 * `GET /server/discover/`, polled from time to time. A server that disappears from an answer does not leave
 * right away (on Wi-Fi a lost announcement is common): it stays `LOST_GRACE_MS` and only then is dropped.
 */
export class ServerDirectory {
  /** The other servers (without the embedded one), sorted by name. */
  others = $state<ServerOption[]>([])
  /** Whether the first query has finished, with an answer or an error. */
  loaded = $state(false)

  #lostSince = new Map<string, number>()
  #emptyStreak = 0

  /** The embedded one first, then the others. */
  get list(): ServerOption[] {
    return [embedded, ...this.others]
  }

  async refresh(signal?: AbortSignal): Promise<void> {
    try {
      this.#merge(await fetchDiscoveredServers(signal))
    } catch {
      // with no answer we cannot say anyone left: the list stays as it is
    } finally {
      this.loaded = true
    }
  }

  #merge(found: DiscoveredServer[], now = Date.now()) {
    const seen = new Map<string, ServerOption>()
    for (const server of found) {
      const option = toOption(server)
      if (!option || option.id === embedded.id || option.address === embedded.address) continue
      if (!seen.has(option.id) && seen.size < MAX_SERVERS) seen.set(option.id, option)
    }
    const next = new Map(seen)
    for (const old of this.others) {
      if (seen.has(old.id)) {
        this.#lostSince.delete(old.id)
        continue
      }
      const since = this.#lostSince.get(old.id) ?? now
      if (now - since < LOST_GRACE_MS && next.size < MAX_SERVERS) {
        this.#lostSince.set(old.id, since)
        next.set(old.id, old)
      } else {
        this.#lostSince.delete(old.id)
      }
    }
    const sorted = [...next.values()].sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
    const same = sorted.length === this.others.length && sorted.every((s, i) => s.id === this.others[i].id && s.address === this.others[i].address && s.serverId === this.others[i].serverId)
    if (!same) this.others = sorted
  }

  /**
   * Polls from time to time until cancelled: soon and fast while there are no other servers
   * (backing off more and more if the gateway does not exist), slowly when there are. A hidden tab does not poll.
   */
  start(): () => void {
    const controller = new AbortController()
    let timer: ReturnType<typeof setTimeout> | undefined
    const tick = async () => {
      if (!document.hidden) await this.refresh(controller.signal)
      if (controller.signal.aborted) return
      this.#emptyStreak = this.others.length ? 0 : this.#emptyStreak + 1
      const delay = this.others.length ? POLL_FOUND_MS : Math.min(POLL_EMPTY_MS * 2 ** (this.#emptyStreak - 1), POLL_MAX_MS)
      timer = setTimeout(tick, delay)
    }
    void tick()
    return () => {
      controller.abort()
      clearTimeout(timer)
    }
  }
}

export const directory = new ServerDirectory()

/** Isolated so tests can swap it: leaving the page cannot be done in jsdom. */
export const navigation = {
  go: (url: string) => window.location.assign(url),
}

const PROBE_TIMEOUT_MS = 3000
const HEALTH_TIMEOUT_MS = 3000
const HEALTH_POLL_MS = 10_000
const HEALTH_RETRY_MS = 3000
/** A single failure does not bring the status down (one lost packet); two in a row do. */
const HEALTH_FAILURES = 2

export type Health = 'connected' | 'disconnected'

const ADDRESS_HEADER = 'x-pindrel-address'
const TLS_HEADER = 'x-pindrel-tls'

/** `ip:port` of the header if it looks like a usable LAN address (the value comes from the network: never trusted blindly). */
export function lanAddress(value: string | null): string | null {
  const m = /^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$/.exec(value?.trim() ?? '')
  if (!m || !isUsableIpv4(m[1])) return null
  const port = Number(m[2])
  return port >= 1 && port <= 65535 ? `${m[1]}:${port}` : null
}

/**
 * Does the server respond? Since it is another origin, the response cannot be read (no CORS): all we know is whether
 * there was a response or a network error, which is all that is needed. https page to http server: the browser blocks
 * the query (mixed content) but not the navigation, so there is nothing to test.
 */
export async function probe(url: string, timeoutMs = PROBE_TIMEOUT_MS): Promise<boolean> {
  if (window.location.protocol === 'https:' && url.startsWith('http:')) return true
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    await fetch(`${url}/server/info/`, { mode: 'no-cors', cache: 'no-store', signal: controller.signal })
    return true
  } catch {
    return false
  } finally {
    clearTimeout(timer)
  }
}

/**
 * The page is always the embedded server's; choosing another server does not change a local state, it takes the
 * browser to that server's page (same origin, no CORS or crossed cookies). `connecting` marks the transition.
 */
class ServerSelection {
  readonly selected = embedded
  connecting = $state<ServerOption | null>(null)
  /** A server whose name is known but whose id is not the one opened before: waits for the user to say go on. */
  pendingChange = $state<ServerOption | null>(null)
  /** Whether this page's server responds: `disconnected` after consecutive failures, back to connected on the first success. */
  health = $state<Health>('connected')
  /**
   * The address of this server, once known: what the gateway says the LAN uses (`x-pindrel-address` on `/server/info/`),
   * or the page's own host when it says nothing or does not answer. `null` until the first check ends: the page's host
   * may be `localhost` or a VPN address, which is exactly what must not flash on screen before the right one arrives.
   */
  address = $state<string | null>(null)
  /** Whether this page's server has a secure (HTTPS) side (`x-pindrel-tls` on `/server/info/`). */
  tlsOffered = $state(false)

  /** What to print for the address: a placeholder while it is not known yet. */
  get shownAddress(): string {
    return this.address ?? '…'
  }

  #failures = 0

  constructor() {
    // going back through history can restore this page as it was, in the middle of the transition
    window.addEventListener('pageshow', (e) => {
      if (e.persisted) this.connecting = null
    })
  }

  /** Asks the page's own server (same origin, so the response can be read). */
  async check(signal?: AbortSignal): Promise<void> {
    const timeout = new AbortController()
    const timer = setTimeout(() => timeout.abort(), HEALTH_TIMEOUT_MS)
    const onAbort = () => timeout.abort()
    signal?.addEventListener('abort', onAbort)
    let up = false
    try {
      // any response that is not a server error proves someone is there: 404 and 429 count
      const res = await fetch('/server/info/', { cache: 'no-store', signal: timeout.signal })
      up = res.status < 500
      if (up) {
        this.address = lanAddress(res.headers.get(ADDRESS_HEADER)) ?? embedded.address
        this.tlsOffered = parsePort(res.headers.get(TLS_HEADER)) !== undefined
      }
    } catch {
      up = false
    } finally {
      clearTimeout(timer)
      signal?.removeEventListener('abort', onAbort)
    }
    if (signal?.aborted) return
    this.address ??= embedded.address // no answer on the first try: the page's own host is all there is
    this.#failures = up ? 0 : this.#failures + 1
    if (up) this.health = 'connected'
    else if (this.#failures >= HEALTH_FAILURES) this.health = 'disconnected'
  }

  /**
   * Checks the page's server from time to time (faster after a failure), when the network comes back and
   * when the tab is reopened. A hidden tab does not poll. Returns the function that stops it.
   */
  watchHealth(): () => void {
    const controller = new AbortController()
    let timer: ReturnType<typeof setTimeout> | undefined
    let running = false
    const tick = async () => {
      if (running) return
      running = true
      clearTimeout(timer)
      try {
        if (!document.hidden) await this.check(controller.signal)
      } finally {
        running = false
      }
      if (controller.signal.aborted) return
      timer = setTimeout(tick, this.#failures ? HEALTH_RETRY_MS : HEALTH_POLL_MS)
    }
    const wake = () => void tick()
    window.addEventListener('online', wake)
    document.addEventListener('visibilitychange', wake)
    void tick()
    return () => {
      controller.abort()
      clearTimeout(timer)
      window.removeEventListener('online', wake)
      document.removeEventListener('visibilitychange', wake)
    }
  }

  async open(server: ServerOption, confirmed = false): Promise<void> {
    if (this.connecting || server.id === embedded.id) return
    if (server.manual) return this.#openManual(server, confirmed)
    if (!confirmed) {
      if (this.pendingChange) return // the question is still open
      if (trustOf(server.name, server.serverId ?? '') === 'changed') {
        this.pendingChange = server
        return
      }
    }
    this.pendingChange = null
    this.connecting = server
    if (await probe(server.url)) {
      remember(server.name, server.serverId ?? '') // only what really answered becomes the one we know
      navigation.go(server.url)
    } else {
      this.connecting = null
      toast.show(`${server.name} não respondeu.`)
    }
  }

  /**
   * A server typed in by the user is asked who it is again: it may have moved or been replaced since it was added.
   * Another id under the name it had is the same "this server changed" question as on the network.
   */
  async #openManual(server: ServerOption, confirmed: boolean): Promise<void> {
    if (!confirmed && this.pendingChange) return
    this.pendingChange = null
    this.connecting = server
    const now = await inspect(server.url)
    if (!now.ok) {
      this.connecting = null
      toast.show(`${server.name} não respondeu.`)
      return
    }
    const trustName = server.trustName ?? server.name
    if (!confirmed && trustOf(trustName, now.serverId) === 'changed') {
      this.connecting = null
      this.pendingChange = { ...server, serverId: now.serverId }
      return
    }
    remember(trustName, now.serverId)
    manual.update(server.id, now.serverId)
    // a redirect may have moved it between http and https
    navigation.go(now.origin)
  }

  /** The user accepted the change: go on to the server. */
  confirmChange(): void {
    const server = this.pendingChange
    if (server) void this.open(server, true)
  }

  cancelChange(): void {
    this.pendingChange = null
  }
}

export const selection = new ServerSelection()
