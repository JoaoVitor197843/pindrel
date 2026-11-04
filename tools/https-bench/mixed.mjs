// A busier page than the login screen, in a cold Chrome: 4 logins (Argon2 on the server), 30 small API calls and 2
// script files, all at once. Reports the time to finish everything and the 95th percentile of one request.
// usage: node mixed.mjs <downKbps> <runs>     env: PORT_PLAIN, PORT_TLS, PORT_QUIC, SPKI
import puppeteer from 'puppeteer'

const [kbps = '0', runs = '6'] = process.argv.slice(2)
const PLAIN = process.env.PORT_PLAIN ?? '9101'
const TLS = process.env.PORT_TLS ?? '9444'
const QUIC = process.env.PORT_QUIC ?? '9445'
const variants = {
  'h1  http  (hoje)': { url: `http://localhost:${PLAIN}/`, args: ['--disable-quic', '--disable-http2'] },
  'h1  https':        { url: `https://localhost:${TLS}/`, args: ['--disable-quic', '--disable-http2'] },
  'h2  https':        { url: `https://localhost:${TLS}/`, args: ['--disable-quic'] },
  'h3  https':        { url: `https://localhost:${QUIC}/`, args: ['--enable-quic', `--origin-to-force-quic-on=localhost:${QUIC}`, `--ignore-certificate-errors-spki-list=${process.env.SPKI}`] },
}
const pct = (a, p) => [...a].sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(a.length * p))]
const out = {}
for (const [name, v] of Object.entries(variants)) {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--ignore-certificate-errors', ...v.args] })
  const totals = [], p95s = [], failed = []
  let proto = ''
  for (let i = 0; i < Number(runs); i++) {
    const ctx = await browser.createBrowserContext()
    const page = await ctx.newPage()
    try { await page.goto(v.url, { waitUntil: 'load', timeout: 30000 }) } catch { failed.push(1); await ctx.close(); continue } // opens the connection and finds the script names
    const cdp = await page.createCDPSession()
    if (Number(kbps) > 0) {
      await cdp.send('Network.enable')
      await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: (Number(kbps) * 1000) / 8, uploadThroughput: (Number(kbps) * 1000) / 8 })
    }
    page.on('console', (m) => process.env.DEBUG && console.log('   page:', m.text()))
    const r = await page.evaluate(async (run) => {
      const field = (n, s) => [(n << 3) | 2, s.length, ...[...s].map((c) => c.charCodeAt(0))]
      const login = new Uint8Array([...field(1, `nobody${run}@casa.local`), ...field(2, 'Wrong-pass-123!')])
      const assets = [...document.querySelectorAll('script[src]')].map((s) => s.src)
      const jobs = [
        ...Array.from({ length: 4 }, () => ['POST', '/auth/login/', login]),
        ...Array.from({ length: 30 }, (_, i) => ['GET', `/server/info/?n=${run}-${i}`]),
        ...assets.map((a) => ['GET', `${new URL(a).pathname}?cb=${run}`]),
        ['GET', `/assets/${await fetch('/').then((r) => r.text()).then((t) => t.match(/play-[\w-]+\.js|index-[\w-]+\.js/)?.[0] ?? 'x').catch(() => 'x')}?cb=${run}b`],
      ]
      const t0 = performance.now()
      const times = await Promise.all(jobs.map(async ([m, u, b]) => {
        const s = performance.now()
        try { const res = await fetch(u, { method: m, body: b, headers: b ? { 'content-type': 'application/x-protobuf' } : {}, cache: 'no-store' }); await res.arrayBuffer(); if (res.status >= 500 || res.status === 429) console.log('STATUS', m, u.slice(0, 30), res.status); return [performance.now() - s, res.status >= 500 || res.status === 429] } catch (e) { console.log('EXC', m, u.slice(0, 30), String(e)); return [performance.now() - s, true] }
      }))
      return { total: performance.now() - t0, times: times.map((t) => t[0]), bad: times.filter((t) => t[1]).length,  proto: performance.getEntriesByType('navigation')[0].nextHopProtocol }
    }, i)
    if (process.env.DEBUG) console.log(v.url, r.detail)
    totals.push(r.total); p95s.push(pct(r.times, 0.95)); failed.push(r.bad); proto = r.proto
    await ctx.close()
  }
  await browser.close()
  out[name] = { proto, total: pct(totals, 0.5), p95: pct(p95s, 0.5), worst: Math.max(...totals), bad: failed.reduce((a, b) => a + b, 0) }
}
console.log(`banda ${Number(kbps) ? kbps + ' kbps' : 'sem limite'}; mediana de ${runs} cargas; "tudo" = 4 logins + 30 chamadas + scripts em paralelo`)
console.log('variante'.padEnd(18), 'proto'.padEnd(9), 'tudo'.padStart(8), 'p95 1 req'.padStart(10), 'pior'.padStart(8), 'falhas')
for (const [n, r] of Object.entries(out)) console.log(n.padEnd(18), r.proto.padEnd(9), `${r.total.toFixed(0)} ms`.padStart(8), `${r.p95.toFixed(0)} ms`.padStart(10), `${r.worst.toFixed(0)} ms`.padStart(8), r.bad)
