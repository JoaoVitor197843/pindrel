import { vi } from 'vitest'
import { DiscoveredServers, type DiscoveredServer } from '../types/shared/protos/server'

export const found = (name: string, ip = '192.168.0.20', port = 8095, id = ''): DiscoveredServer => ({
  id,
  name,
  host: `${name.toLowerCase()}-host`,
  addresses: [ip],
  port,
})

/** Makes `GET /server/discover/` answer [servers] in protobuf; the rest (probe) answers 200. */
export function mockDiscover(servers: DiscoveredServer[] | 'error' | 'missing') {
  vi.mocked(fetch).mockImplementation(async (input) => {
    if (String(input) !== '/server/discover/') return new Response(null, { status: 200 })
    if (servers === 'missing') return new Response(null, { status: 404 })
    if (servers === 'error') throw new TypeError('rede caiu')
    return new Response(DiscoveredServers.encode({ servers }).finish() as BodyInit)
  })
}
