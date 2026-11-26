import { untrack } from 'svelte'
import { inspect } from '../api/serverCheck'
import { mapLimit } from '../mapLimit'

/**
 * How the connection to a server is protected, as this browser sees it:
 * - `https`: it is (or will be) opened over HTTPS with a certificate this browser trusts;
 * - `available`: this page came over plain HTTP, but the same server has an HTTPS side this browser already trusts;
 * - `untrusted`: the server has an HTTPS side, but this browser does not trust its certificate (yet);
 * - `plain`: plain HTTP and nothing else;
 * - `checking`: it has an HTTPS side that was not asked yet.
 */
export type Security = 'https' | 'available' | 'untrusted' | 'plain' | 'checking'

/** The HTTPS side a server announces: the host it is reached by, its TLS port and, when known, its id. */
export interface SecureSide {
  hostname: string
  tlsPort: number
  serverId?: string
}

/** A result this young is not asked again (installing a certificate takes longer than that). */
const FRESH_MS = 30_000
/** At most this many checks at once: a weak device must not open dozens of TLS handshakes together. */
const CONCURRENCY = 4

const usablePort = (p: number) => Number.isInteger(p) && p >= 1 && p <= 65535

/** `https://host:port` of a secure side (IPv6 in brackets), or null when it cannot be one. */
export function secureOrigin(s: SecureSide): string | null {
  if (!usablePort(s.tlsPort) || !s.hostname) return null
  const host = s.hostname.includes(':') && !s.hostname.startsWith('[') ? `[${s.hostname}]` : s.hostname
  try {
    return new URL(`https://${host}:${s.tlsPort}`).origin
  } catch {
    return null
  }
}

/**
 * Whether this browser trusts the certificate of a server's HTTPS side. A page cannot read a certificate, but it does not
 * need to: a request over HTTPS gets an answer only when the browser accepted the certificate, and fails like a server that
 * is not there when it did not. The gateway lets any page read `/server/info/`, so the answer also says whose it is: an
 * HTTPS side that answers with another server's id is not this server's, and is not trusted for it.
 */
class SecureChecks {
  #results = $state<Record<string, { trusted: boolean; origin: string; at: number }>>({})
  #running = new Set<string>()

  #key(s: SecureSide, origin: string) {
    return `${origin}|${s.serverId ?? ''}`
  }

  /** What is known; undefined while it was never asked. */
  result(s: SecureSide): { trusted: boolean; origin: string } | undefined {
    const origin = secureOrigin(s)
    return origin ? this.#results[this.#key(s, origin)] : undefined
  }

  /** Asks the sides not asked in the last half minute. Nothing runs in the background: call it when the answer is shown. */
  async check(sides: readonly SecureSide[]): Promise<void> {
    const now = Date.now()
    const todo = untrack(() =>
      sides.flatMap((s) => {
        const origin = secureOrigin(s)
        if (!origin) return []
        const key = this.#key(s, origin)
        const known = this.#results[key]
        if (this.#running.has(key) || (known && now - known.at < FRESH_MS)) return []
        this.#running.add(key)
        return [{ s, origin, key }]
      }),
    )
    await mapLimit(todo, CONCURRENCY, async ({ s, origin, key }) => {
      try {
        const r = await inspect(origin)
        // `blocked`: something answered over TLS that the page may not read (an older gateway): the certificate was
        // accepted, but whose it is cannot be told, so it counts only for a server whose id is not known
        const trusted = r.ok ? !s.serverId || r.serverId === s.serverId : r.reason === 'blocked' && !s.serverId
        this.#results = { ...this.#results, [key]: { trusted, origin: r.ok ? r.origin : origin, at: Date.now() } }
      } finally {
        this.#running.delete(key)
      }
    })
  }

  /** Forgets every answer (tests). */
  reset() {
    this.#results = {}
    this.#running.clear()
  }
}

export const secureChecks = new SecureChecks()

/** A server whose plain address is `url`, with its HTTPS side when it has one. */
export function securityOf(url: string, side?: SecureSide): Security {
  if (url.startsWith('https:')) return 'https'
  if (!side || !secureOrigin(side)) return 'plain'
  const r = secureChecks.result(side)
  return !r ? 'checking' : r.trusted ? 'https' : 'untrusted'
}

/** The address to open a server at: its HTTPS side once this browser is known to trust it, its plain one otherwise. */
export function bestUrl(url: string, side?: SecureSide): string {
  const r = side && !url.startsWith('https:') ? secureChecks.result(side) : undefined
  return r?.trusted ? r.origin : url
}
