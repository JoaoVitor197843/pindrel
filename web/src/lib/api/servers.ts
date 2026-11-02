import { DiscoveredServers, type DiscoveredServer } from '../../types/shared/protos/server'
import { ApiError, getProto } from './client'

/**
 * Pindrel servers the gateway found on the network (`GET /server/discover/`). Without a gateway
 * (simple deploy) the endpoint does not exist: 404 stands for "no other server".
 */
export async function fetchDiscoveredServers(signal?: AbortSignal): Promise<DiscoveredServer[]> {
  try {
    return (await getProto('/server/discover/', (b) => DiscoveredServers.decode(b), { signal })).servers
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) return []
    throw error
  }
}
