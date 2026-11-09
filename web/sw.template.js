// Pindrel service worker. It is built into dist/sw.js by vite.assets.ts, which fills in the version and the list of files.
// It exists for one thing: the page (and the editor's lazy chunks) must open when the server does not answer. It never
// touches the API: only the page's own routes and /assets/ are handled, everything else goes to the network untouched.
const VERSION = '__VERSION__'
const ASSETS = __ASSETS__
const CACHE = `pindrel-${VERSION}`
const SHELL = '/'
// a server that is slow (not down) is waited for this long before the saved page is used
const WAIT_MS = 4000

// the routes the Go server answers with index.html (isWebRoute in router.go): keep both in step
const isPage = (p) => p === '/' || p === '/login' || (p.startsWith('/notes/') && p.length > 7 && !p.slice(7).includes('/'))

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE)
      // the page first: without it nothing opens
      await cache.add(new Request(SHELL, { cache: 'reload' }))
      // then the files, one at a time so the worker never holds many bodies at once; one that fails is fetched on first use
      for (const url of ASSETS) {
        try {
          if (!(await cache.match(url))) await cache.add(url)
        } catch {
          // left for the first request
        }
      }
    })(),
  )
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) if (name.startsWith('pindrel-') && name !== CACHE) await caches.delete(name)
      await self.clients.claim()
    })(),
  )
})

const timeout = (ms) => new Promise((_, reject) => setTimeout(() => reject(new Error('slow')), ms))

async function page(request) {
  const cache = await caches.open(CACHE)
  try {
    const res = await Promise.race([fetch(request), timeout(WAIT_MS)])
    // a server that answers with an error (the gateway is up and the API behind it is not) counts as down
    if (res.status >= 500) throw new Error('down')
    if (res.ok && (res.headers.get('content-type') || '').includes('text/html')) await cache.put(SHELL, res.clone())
    return res
  } catch (e) {
    const saved = await cache.match(SHELL, { ignoreVary: true })
    if (saved) return saved
    throw e
  }
}

async function asset(request) {
  const cache = await caches.open(CACHE)
  const saved = await cache.match(request, { ignoreVary: true })
  if (saved) return saved
  const res = await fetch(request)
  // a partial answer or an error must never be kept as if it were the file
  if (res.status === 200 && !request.headers.has('range')) await cache.put(request, res.clone())
  return res
}

self.addEventListener('fetch', (event) => {
  const request = event.request
  if (request.method !== 'GET') return
  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return
  if (request.mode === 'navigate') {
    if (isPage(url.pathname)) event.respondWith(page(request))
  } else if (url.pathname.startsWith('/assets/')) {
    event.respondWith(asset(request))
  }
})
