import { afterEach, describe, expect, it, vi } from 'vitest'
import swSource from '../../sw.template.js?raw'
import { registerServiceWorker } from './sw'

// ---- the worker's own logic, run against fake globals (a service worker cannot run in jsdom)
type Handler = (event: unknown) => void
function boot(opts: { fetch: (r: Request) => Promise<Response>; origin?: string; assets?: string[]; keys?: string[] }) {
  const handlers: Record<string, Handler> = {}
  const stores = new Map<string, Map<string, Response>>()
  for (const k of opts.keys ?? []) stores.set(k, new Map())
  const keyOf = (r: Request | string) => new URL(typeof r === 'string' ? r : r.url, 'https://pindrel.test').pathname
  const open = async (name: string) => {
    if (!stores.has(name)) stores.set(name, new Map())
    const m = stores.get(name)!
    return {
      add: async (r: Request | string) => {
        const res = await opts.fetch(typeof r === 'string' ? new Request(new URL(r, 'https://pindrel.test')) : r)
        if (!res.ok) throw new Error('bad')
        m.set(keyOf(r), res)
      },
      put: async (r: Request | string, res: Response) => void m.set(keyOf(r), res),
      match: async (r: Request | string) => m.get(keyOf(r))?.clone(),
    }
  }
  const caches = { open, keys: async () => [...stores.keys()], delete: async (k: string) => stores.delete(k) }
  const self = { location: { origin: opts.origin ?? 'https://pindrel.test' }, clients: { claim: vi.fn(async () => {}) }, addEventListener: (t: string, h: Handler) => (handlers[t] = h) }
  // a worker resolves '/' against its own origin; Node's Request wants an absolute address
  class Req extends Request {
    constructor(input: RequestInfo | URL, init?: RequestInit) {
      super(typeof input === 'string' ? new URL(input, 'https://pindrel.test').href : input, init)
    }
  }
  const src = swSource.replace('__VERSION__', 'v1').replace('__ASSETS__', JSON.stringify(opts.assets ?? ['/assets/a.js', '/assets/b.js']))
  new Function('self', 'caches', 'fetch', 'Request', 'URL', 'setTimeout', src)(self, caches, opts.fetch, Req, URL, setTimeout)
  const run = async (type: 'install' | 'activate') => {
    let p: Promise<unknown> = Promise.resolve()
    handlers[type]({ waitUntil: (x: Promise<unknown>) => (p = x) })
    await p
  }
  const request = (path: string, init: { method?: string; mode?: string; origin?: string } = {}) => {
    const req = new Request(new URL(path, init.origin ?? 'https://pindrel.test'), { method: init.method ?? 'GET' })
    Object.defineProperty(req, 'mode', { value: init.mode ?? 'cors' })
    let answered: Promise<Response> | null = null
    handlers.fetch({ request: req, respondWith: (p: Promise<Response>) => (answered = p) })
    return answered as Promise<Response> | null
  }
  return { run, request, stores, self }
}
const html = (body = 'shell') => new Response(body, { headers: { 'content-type': 'text/html' } })
const up = async (r: Request) => (new URL(r.url).pathname.startsWith('/assets/') ? new Response('js', { status: 200 }) : html())
const down = async (_r?: Request): Promise<Response> => {
  throw new TypeError('Failed to fetch')
}

describe('service worker', () => {
  it('guarda a página e todos os arquivos ao instalar, um a um, e tolera um que falha', async () => {
    const seen: string[] = []
    const w = boot({
      fetch: async (r) => {
        seen.push(new URL(r.url).pathname)
        return new URL(r.url).pathname === '/assets/b.js' ? new Response('x', { status: 500 }) : up(r)
      },
    })
    await expect(w.run('install')).resolves.toBeUndefined()
    expect(seen[0]).toBe('/')
    expect([...w.stores.get('pindrel-v1')!.keys()].sort()).toEqual(['/', '/assets/a.js'])
  })

  it('ao ativar apaga os guardados de versões antigas e não mexe em outros', async () => {
    const w = boot({ fetch: up, keys: ['pindrel-old', 'pindrel-v1', 'outro-app'] })
    await w.run('activate')
    expect([...w.stores.keys()].sort()).toEqual(['outro-app', 'pindrel-v1'])
    expect(w.self.clients.claim).toHaveBeenCalled()
  })

  it('a página abre pela rede quando o servidor responde, e a cópia guardada é renovada', async () => {
    const w = boot({ fetch: async () => html('nova') })
    const res = await w.request('/?tela=painel&modo=conta', { mode: 'navigate' })!
    expect(await res.text()).toBe('nova')
    expect(await (await w.stores.get('pindrel-v1')!.get('/')!.clone()).text()).toBe('nova')
  })

  it('sem servidor (rede cai, 502, 503) a página vem da cópia guardada', async () => {
    for (const failing of [down, async () => new Response('bad gateway', { status: 502 }), async () => new Response('x', { status: 503 })] as ((r: Request) => Promise<Response>)[]) {
      let online = true
      const w = boot({ fetch: async (r) => (online ? html('guardada') : failing(r)) })
      await w.request('/', { mode: 'navigate' })
      online = false
      const res = await w.request('/notes/abc', { mode: 'navigate' })!
      expect(await res.text()).toBe('guardada')
    }
  })

  it('um servidor lento (não fora do ar) é esperado por pouco tempo e depois vale a cópia', async () => {
    vi.useFakeTimers()
    let online = true
    const w = boot({ fetch: (r) => (online ? Promise.resolve(html('guardada')) : new Promise(() => {})) })
    await w.request('/', { mode: 'navigate' })
    online = false
    const pending = w.request('/login', { mode: 'navigate' })!
    await vi.advanceTimersByTimeAsync(4100)
    expect(await (await pending).text()).toBe('guardada')
    vi.useRealTimers()
  })

  it('sem cópia guardada e sem servidor o erro passa adiante (o navegador mostra o dele)', async () => {
    const w = boot({ fetch: down })
    await expect(w.request('/', { mode: 'navigate' })!).rejects.toThrow()
  })

  it('/assets/ vem da cópia guardada sem perguntar à rede, e o que falta é buscado e guardado', async () => {
    const calls: string[] = []
    const w = boot({ fetch: async (r) => (calls.push(new URL(r.url).pathname), up(r)) })
    await w.run('install')
    calls.length = 0
    expect(await (await w.request('/assets/a.js')!).text()).toBe('js')
    expect(calls).toEqual([])
    await w.request('/assets/novo.js')
    expect(w.stores.get('pindrel-v1')!.has('/assets/novo.js')).toBe(true)
  })

  it('um arquivo que deu erro não é guardado como se fosse o arquivo', async () => {
    const w = boot({ fetch: async () => new Response('nope', { status: 404 }) })
    const res = await w.request('/assets/x.js')!
    expect(res.status).toBe(404)
    expect(w.stores.get('pindrel-v1')?.has('/assets/x.js') ?? false).toBe(false)
  })

  it('a API, outras origens, outros métodos e páginas que não são do app não são tocados', () => {
    const w = boot({ fetch: up })
    for (const path of ['/auth/login/', '/auth/refresh/', '/server/info/', '/files/abc', '/sync/bulk/', '/ws/sync', '/swagger/index.html', '/server/connect/']) {
      expect(w.request(path, { mode: 'navigate' })).toBeNull()
      expect(w.request(path)).toBeNull()
    }
    expect(w.request('/assets/a.js', { method: 'POST' })).toBeNull()
    expect(w.request('/', { mode: 'navigate', origin: 'https://outro.test' })).toBeNull()
    expect(w.request('/notes/a/b', { mode: 'navigate' })).toBeNull()
    expect(w.request('/notes/', { mode: 'navigate' })).toBeNull()
  })
})

// ---- the registration
describe('registro do service worker', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
    Object.defineProperty(window, 'isSecureContext', { value: undefined, configurable: true })
  })
  const fakeNavigator = () => {
    const register = vi.fn(async () => ({}))
    Object.defineProperty(navigator, 'serviceWorker', { value: { register }, configurable: true })
    return register
  }

  it('numa build de produção em página segura registra /sw.js', async () => {
    vi.stubEnv('PROD', true)
    const register = fakeNavigator()
    registerServiceWorker()
    await vi.waitFor(() => expect(register).toHaveBeenCalledWith('/sw.js'))
  })

  it('não registra em desenvolvimento, na build de medição, nem em HTTP puro', async () => {
    const register = fakeNavigator()
    vi.stubEnv('PROD', false)
    registerServiceWorker()
    vi.stubEnv('PROD', true)
    vi.stubEnv('MODE', 'loadtest')
    registerServiceWorker()
    vi.stubEnv('MODE', 'production')
    Object.defineProperty(window, 'isSecureContext', { value: false, configurable: true })
    registerServiceWorker()
    await new Promise((r) => setTimeout(r, 30))
    expect(register).not.toHaveBeenCalled()
  })

  it('um registro que falha não quebra a página', async () => {
    vi.stubEnv('PROD', true)
    const register = vi.fn(async () => {
      throw new Error('nope')
    })
    Object.defineProperty(navigator, 'serviceWorker', { value: { register }, configurable: true })
    expect(() => registerServiceWorker()).not.toThrow()
    await vi.waitFor(() => expect(register).toHaveBeenCalled())
  })
})
