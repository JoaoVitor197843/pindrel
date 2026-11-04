// WebSocket in a cold Chrome: time to open, round trip of a 64-byte message (median of 40, one at a time) and the time
// for 300 messages sent at once to come back. usage: node wstest.mjs <label> <wsUrl> <pageUrl> [chrome flags...]
import puppeteer from 'puppeteer'

const [label, wsUrl, pageUrl, ...flags] = process.argv.slice(2)
const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--ignore-certificate-errors', ...flags] })
const rows = []
for (let run = 0; run < 5; run++) {
  const ctx = await browser.createBrowserContext()
  const page = await ctx.newPage()
  await page.goto(pageUrl, { waitUntil: 'load' }).catch(() => {})
  rows.push(
    await page.evaluate(async (url) => {
      const t0 = performance.now()
      const ws = new WebSocket(url)
      ws.binaryType = 'arraybuffer'
      const opened = await new Promise((res) => {
        ws.onopen = () => res(performance.now() - t0)
        ws.onerror = () => res(-1)
        setTimeout(() => res(-1), 8000)
      })
      if (opened < 0) return { opened }
      const next = () => new Promise((res) => (ws.onmessage = () => res(performance.now())))
      const payload = new Uint8Array(64)
      const rtts = []
      for (let i = 0; i < 40; i++) { const s = performance.now(); const p = next(); ws.send(payload); rtts.push((await p) - s) }
      let got = 0
      const burstStart = performance.now()
      const done = new Promise((res) => (ws.onmessage = () => ++got === 300 && res(performance.now() - burstStart)))
      for (let i = 0; i < 300; i++) ws.send(payload)
      const burst = await Promise.race([done, new Promise((r) => setTimeout(() => r(-1), 8000))])
      ws.close()
      rtts.sort((a, b) => a - b)
      return { opened, rtt: rtts[20], burst }
    }, wsUrl),
  )
  await ctx.close()
}
await browser.close()
const ok = rows.filter((r) => r.opened >= 0)
const med = (k) => (ok.length ? ok.map((r) => r[k]).sort((a, b) => a - b)[Math.floor(ok.length / 2)].toFixed(0) + ' ms' : '-')
console.log(label.padEnd(30), ok.length ? `abre=${med('opened').padStart(7)}  ida-e-volta=${med('rtt').padStart(7)}  300 msgs=${med('burst').padStart(7)}` : 'NÃO CONECTOU (5 tentativas)')
