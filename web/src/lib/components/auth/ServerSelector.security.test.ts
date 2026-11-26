import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { found } from '../../../test/discovery'
import { DiscoveredServers, ServerInfo, type DiscoveredServer } from '../../../types/shared/protos/server'
import { manual } from '../../stores/manual.svelte'
import { secureChecks } from '../../stores/security.svelte'
import { directory, navigation, selection } from '../../stores/servers.svelte'
import ServerSelector from './ServerSelector.svelte'

const trigger = () => screen.getByRole('button', { name: /^Selecionar servidor/ })
const row = (name: RegExp) => screen.getByRole('menuitemradio', { name }).parentElement as HTMLElement
const securityOf = (name: RegExp) => within(row(name)).getByTestId('security')

/**
 * The network as the page sees it: the gateway's list, and HTTPS sides that answer (an id: this browser accepts the
 * certificate) or are refused (no entry: what a browser does with a certificate it does not trust).
 */
function network(servers: DiscoveredServer[], secure: Record<string, string>) {
  const asked: string[] = []
  vi.mocked(fetch).mockImplementation((async (input: string) => {
    const url = String(input)
    if (url === '/server/discover/') return new Response(DiscoveredServers.encode({ servers }).finish() as BodyInit)
    if (url.startsWith('https:')) {
      asked.push(url)
      const id = secure[new URL(url).origin]
      if (!id) throw new TypeError('net::ERR_CERT_AUTHORITY_INVALID')
      return new Response(ServerInfo.encode({ name: 'X', registrationEnabled: true }).finish() as BodyInit, {
        headers: { 'content-type': 'application/x-protobuf', 'x-pindrel-id': id },
      })
    }
    return new Response(null, { status: 200 })
  }) as typeof fetch)
  return asked
}

const esc = { ...found('Escritório', '192.168.0.20', 8095, 'esc-1'), tlsPort: 8443 }
const sitio = { ...found('Sítio', '192.168.0.30', 8095, 'sit-1'), tlsPort: 8443 }
const velho = found('Velho', '192.168.0.40', 8095, 'vel-1')

beforeEach(async () => {
  secureChecks.reset()
  selection.connecting = null
  selection.health = 'connected'
  selection.tlsPort = undefined
  selection.serverId = ''
  manual.list = []
  manual.health = {}
  directory.others = []
})
afterEach(() => {
  manual.list = []
  vi.restoreAllMocks()
})

describe('ServerSelector — HTTP, HTTPS e confiança', () => {
  it('cada servidor diz se é HTTP ou HTTPS e se este navegador confia nele', async () => {
    network([esc, sitio, velho], { 'https://192.168.0.20:8443': 'esc-1' })
    await directory.refresh()
    render(ServerSelector)
    await fireEvent.click(trigger())
    await waitFor(() => expect(securityOf(/Escritório/).dataset.security).toBe('https'))
    expect(securityOf(/Escritório/).textContent).toContain('HTTPS · confiável')
    // the address shown is the one it will be opened at
    expect(row(/Escritório/).textContent).toContain('192.168.0.20:8443')
    await waitFor(() => expect(securityOf(/Sítio/).dataset.security).toBe('untrusted'))
    expect(securityOf(/Sítio/).textContent).toContain('HTTP · HTTPS não confiável')
    expect(securityOf(/Velho/).textContent).toContain('HTTP · sem criptografia')
    expect(securityOf(/Embutido/).textContent).toContain('HTTP · sem criptografia')
  })

  it('o não confiável oferece a página que ensina a conectar com segurança; os outros não', async () => {
    network([sitio, velho], {})
    await directory.refresh()
    render(ServerSelector)
    await fireEvent.click(trigger())
    await waitFor(() => expect(within(row(/Sítio/)).getByRole('menuitem', { name: 'Conectar com segurança' })).toBeTruthy())
    expect(within(row(/Sítio/)).getByRole('menuitem', { name: 'Conectar com segurança' }).getAttribute('href')).toBe('http://192.168.0.30:8095/server/connect/')
    expect(within(row(/Velho/)).queryByRole('menuitem')).toBeNull()
  })

  it('o confiável abre pelo HTTPS; o não confiável continua pelo HTTP', async () => {
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    network([esc, sitio], { 'https://192.168.0.20:8443': 'esc-1' })
    await directory.refresh()
    render(ServerSelector)
    await fireEvent.click(trigger())
    await waitFor(() => expect(securityOf(/Escritório/).dataset.security).toBe('https'))
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Escritório/ }))
    await waitFor(() => expect(go).toHaveBeenCalledWith('https://192.168.0.20:8443'))
    selection.connecting = null
    await fireEvent.click(trigger())
    await waitFor(() => expect(securityOf(/Sítio/).dataset.security).toBe('untrusted'))
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Sítio/ }))
    await waitFor(() => expect(go).toHaveBeenLastCalledWith('http://192.168.0.30:8095'))
  })

  it('com o menu fechado nada é perguntado; abrir e fechar várias vezes pergunta uma vez', async () => {
    const asked = network([esc], { 'https://192.168.0.20:8443': 'esc-1' })
    await directory.refresh()
    render(ServerSelector)
    expect(asked).toEqual([])
    for (let i = 0; i < 4; i++) await fireEvent.click(trigger())
    await waitFor(() => expect(asked).toHaveLength(1))
    await new Promise((r) => setTimeout(r, 20))
    expect(asked).toHaveLength(1)
  })

  it('o servidor desta página, aberto por HTTP: oferece "Usar HTTPS" quando o navegador já confia', async () => {
    network([], { [`https://${location.hostname}:8443`]: 'casa' })
    await directory.refresh()
    selection.tlsPort = 8443
    selection.serverId = 'casa'
    render(ServerSelector)
    await fireEvent.click(trigger())
    await waitFor(() => expect(securityOf(/Embutido/).dataset.security).toBe('available'))
    expect(securityOf(/Embutido/).textContent).toContain('HTTP · HTTPS confiável disponível')
    const link = within(row(/Embutido/)).getByRole('menuitem', { name: 'Usar HTTPS' })
    expect(link.getAttribute('href')).toBe(`https://${location.hostname}:8443${location.pathname}${location.search}`)
  })

  it('o servidor desta página sem certificado confiável aponta para a página de conexão dele', async () => {
    network([], {})
    await directory.refresh()
    selection.tlsPort = 8443
    render(ServerSelector)
    await fireEvent.click(trigger())
    await waitFor(() => expect(securityOf(/Embutido/).dataset.security).toBe('untrusted'))
    expect(within(row(/Embutido/)).getByRole('menuitem', { name: 'Conectar com segurança' }).getAttribute('href')).toBe('/server/connect/')
  })

  it('um servidor adicionado à mão passa a HTTPS quando o navegador começa a confiar nele', async () => {
    const go = vi.spyOn(navigation, 'go').mockImplementation(() => {})
    network([], {})
    await directory.refresh()
    manual.list = [
      { id: 'http://10.0.0.9:8095', name: 'Mão', trustName: 'Mão', serverId: 'mao-1', url: 'http://10.0.0.9:8095', address: '10.0.0.9:8095', connectUrl: 'http://10.0.0.9:8095/server/connect/', tlsPort: 8443 },
    ]
    manual.health = { 'http://10.0.0.9:8095': 'connected' }
    const { unmount } = render(ServerSelector)
    await fireEvent.click(trigger())
    const added = () => screen.getByTestId('added-server')
    await waitFor(() => expect(within(added()).getByTestId('security').dataset.security).toBe('untrusted'))
    expect(within(added()).getByRole('menuitem', { name: 'Conectar com segurança' })).toBeTruthy()
    unmount()

    // the person installed the certificate; the next time the list is looked at, it is trusted
    secureChecks.reset()
    network([], { 'https://10.0.0.9:8443': 'mao-1' })
    render(ServerSelector)
    await fireEvent.click(trigger())
    await waitFor(() => expect(within(added()).getByTestId('security').dataset.security).toBe('https'))
    expect(within(added()).queryByRole('menuitem', { name: 'Conectar com segurança' })).toBeNull()
    expect(added().textContent).toContain('10.0.0.9:8443')
    await fireEvent.click(within(added()).getByRole('menuitemradio'))
    await waitFor(() => expect(go).toHaveBeenCalledWith('https://10.0.0.9:8443'))
  })
})
