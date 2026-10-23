import { fetchDiscoveredServers } from '../api/servers'
import type { DiscoveredServer } from '../../types/shared/protos/server'
import { toast } from './toast.svelte'

export interface ServerOption {
  id: string
  name: string
  /** Como aparece na tela (`192.168.0.20:8095`). */
  address: string
  /** Origem do servidor, para onde o navegador vai ao escolhê-lo. */
  url: string
}

// A página que está aberta é sempre a do servidor embutido, e ele é sempre o padrão.
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

/** Um anúncio é anônimo: só interessam IPv4 comuns (nada de loopback, link-local, multicast). */
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

/** Identificador estável derivado do nome (minúsculas, sem acentos, só letras, números e hífens). */
export function idFor(name: string): string {
  const slug = name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
  return slug || 'servidor'
}

/** O servidor achado na rede como opção, ou null se o anúncio não presta. */
export function toOption(server: DiscoveredServer): ServerOption | null {
  if (!server.name || server.name.length > MAX_NAME_LENGTH) return null
  if (!Number.isInteger(server.port) || server.port <= 0 || server.port > 65535) return null
  const ip = [...new Set(server.addresses.filter(isUsableIpv4))].sort().slice(0, MAX_ADDRESSES)[0]
  const host = ip ?? (server.host ? `${server.host}.local` : '')
  if (!host) return null
  const address = `${host}:${server.port}`
  return { id: idFor(server.name), name: server.name, address, url: `http://${address}` }
}

/**
 * Os outros servidores da rede, como o gateway os entrega. O navegador não tem mDNS: a lista vem de
 * `GET /server/discover/`, consultada de tempos em tempos. Um servidor que some de uma resposta não sai
 * na hora (no Wi-Fi um anúncio perdido é comum): fica `LOST_GRACE_MS` e só então é descartado.
 */
export class ServerDirectory {
  /** Os outros servidores (sem o embutido), ordenados por nome. */
  others = $state<ServerOption[]>([])
  /** Se a primeira consulta já terminou, com resposta ou erro. */
  loaded = $state(false)

  #lostSince = new Map<string, number>()
  #emptyStreak = 0

  /** O embutido primeiro, depois os outros. */
  get list(): ServerOption[] {
    return [embedded, ...this.others]
  }

  async refresh(signal?: AbortSignal): Promise<void> {
    try {
      this.#merge(await fetchDiscoveredServers(signal))
    } catch {
      // sem resposta não dá para dizer que alguém saiu: a lista fica como está
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
    const same = sorted.length === this.others.length && sorted.every((s, i) => s.id === this.others[i].id && s.address === this.others[i].address)
    if (!same) this.others = sorted
  }

  /**
   * Consulta de tempos em tempos até o cancelamento: logo e depressa enquanto não há outros servidores
   * (com espera cada vez maior se o gateway não existe), devagar quando há. Aba escondida não consulta.
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

/** Isolado para os testes trocarem: sair da página não dá para fazer no jsdom. */
export const navigation = {
  go: (url: string) => window.location.assign(url),
}

const PROBE_TIMEOUT_MS = 3000

/**
 * O servidor responde? Como é de outra origem, a resposta não pode ser lida (sem CORS): só se sabe se
 * houve resposta ou erro de rede, que é o que basta. Página https para servidor http: o navegador bloqueia
 * a consulta (conteúdo misto) mas não a navegação, então não há o que testar.
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
 * A página sempre é a do servidor embutido; escolher outro servidor não troca um estado local, leva o
 * navegador até a página dele (mesma origem, sem CORS nem cookies cruzados). `connecting` marca a transição.
 */
class ServerSelection {
  readonly selected = embedded
  connecting = $state<ServerOption | null>(null)

  constructor() {
    // voltar pelo histórico pode restaurar esta página como estava, no meio da transição
    window.addEventListener('pageshow', (e) => {
      if (e.persisted) this.connecting = null
    })
  }

  async open(server: ServerOption): Promise<void> {
    if (this.connecting || server.id === embedded.id) return
    this.connecting = server
    if (await probe(server.url)) {
      navigation.go(server.url)
    } else {
      this.connecting = null
      toast.show(`${server.name} não respondeu.`)
    }
  }
}

export const selection = new ServerSelection()
