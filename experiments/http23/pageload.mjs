// Cold page loads of the login screen over each protocol, with the network throttled through the DevTools protocol.
// usage: node pageload.mjs <downKbps> [runs]   (round-trip latency comes from latproxy.mjs on ports 9087 and 9443)
import puppeteer from 'puppeteer'

const [kbps = '0', runs = '10'] = process.argv.slice(2)
const PLAIN = process.env.PORT_PLAIN ?? '9087'
const TLS = process.env.PORT_TLS ?? '9443' // TCP: HTTP/1.1 and HTTP/2
const QUIC = process.env.PORT_QUIC ?? TLS // UDP: HTTP/3 (same port number in the gateway)
const variants = {
  'h1  http  (hoje)': { url: `http://localhost:${PLAIN}/`, args: ['--disable-quic', '--disable-http2'] },
  'h1  https':        { url: `https://localhost:${TLS}/`, args: ['--disable-quic', '--disable-http2'] },
  'h2  https':        { url: `https://localhost:${TLS}/`, args: ['--disable-quic'] },
  'h3  https':        { url: `https://localhost:${QUIC}/`, args: ['--enable-quic', `--origin-to-force-quic-on=localhost:${QUIC}`, `--ignore-certificate-errors-spki-list=${process.env.SPKI}`] },
}
const median = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)]
const out = {}
for (const [name, v] of Object.entries(variants)) {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--ignore-certificate-errors', ...v.args] })
  const rows = []
  let proto = ''
  for (let i = 0; i < Number(runs); i++) {
    const ctx = await browser.createBrowserContext() // new context: no cache, no connection reuse
    const page = await ctx.newPage()
    await page.setViewport({ width: 390, height: 844 })
    const cdp = await page.createCDPSession()
    if (Number(kbps) > 0) {
      await cdp.send('Network.enable')
      await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: (Number(kbps) * 1000) / 8, uploadThroughput: (Number(kbps) * 1000) / 8 })
    }
    await page.evaluateOnNewDocument(() => {
      window.__lcp = 0
      new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__lcp = e.startTime }).observe({ type: 'largest-contentful-paint', buffered: true })
    })
    await page.goto(v.url, { waitUntil: 'load' })
    await new Promise((r) => setTimeout(r, 400))
    const m = await page.evaluate(() => {
      const n = performance.getEntriesByType('navigation')[0]
      const fcp = performance.getEntriesByName('first-contentful-paint')[0]
      return { ttfb: n.responseStart, fcp: fcp?.startTime ?? 0, lcp: window.__lcp, load: n.loadEventEnd, proto: n.nextHopProtocol }
    })
    proto = m.proto
    rows.push(m)
    await ctx.close()
  }
  await browser.close()
  out[name] = { proto, ttfb: median(rows.map((r) => r.ttfb)), fcp: median(rows.map((r) => r.fcp)), lcp: median(rows.map((r) => r.lcp)), load: median(rows.map((r) => r.load)) }
}
console.log(`
largura de banda: ${Number(kbps) ? `${kbps} kbps` : 'sem limite'} (a latência vem do latproxy); mediana de ${runs} cargas a frio`)
console.log('variante'.padEnd(18), 'proto'.padEnd(6), 'TTFB'.padStart(7), 'FCP'.padStart(7), 'LCP'.padStart(7), 'load'.padStart(7))
for (const [n, r] of Object.entries(out)) console.log(n.padEnd(18), r.proto.padEnd(6), ...['ttfb', 'fcp', 'lcp', 'load'].map((k) => `${r[k].toFixed(0)} ms`.padStart(7)))
