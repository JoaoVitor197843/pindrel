export interface ServerOption {
  id: string
  name: string
  address: string
}

// TODO: o backend embutido fará a descoberta mDNS (_plany._tcp) e entregará a lista.
// O servidor embutido (o que serve esta página) é sempre o padrão.
export const servers: ServerOption[] = [
  { id: 'embedded', name: 'Embutido', address: window.location.host },
  { id: 'escritorio', name: 'Escritório', address: '192.168.0.20' },
  { id: 'nuvem', name: 'Nuvem', address: 'notas.exemplo.com' },
]

class ServerSelection {
  selected = $state<ServerOption>(servers[0])

  select(server: ServerOption) {
    this.selected = server
  }
}

export const selection = new ServerSelection()
