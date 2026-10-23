import { DiscoveredServers, type DiscoveredServer } from '../../types/shared/protos/server'
import { ApiError, getProto } from './client'

/**
 * Servidores Plany que o gateway achou na rede (`GET /server/discover/`). Sem gateway
 * (deploy simples) o endpoint não existe: 404 vale por "nenhum outro servidor".
 */
export async function fetchDiscoveredServers(signal?: AbortSignal): Promise<DiscoveredServer[]> {
  try {
    return (await getProto('/server/discover/', (b) => DiscoveredServers.decode(b), { signal })).servers
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) return []
    throw error
  }
}
