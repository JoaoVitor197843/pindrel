import type { FindResult } from './serverCheck'

/** What the person reads when an address could not be added. Kept apart from the network code that decides why. */
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
      return `Não foi possível conectar a ${r.host}: a conexão foi recusada ou o endereço não existe. Confira o endereço e a porta${r.https ? ' (e, em https, se este navegador confia no certificado: um servidor com certificado próprio tem uma página de conexão no endereço comum dele, terminada em /server/connect/)' : ''}.`
  }
}
