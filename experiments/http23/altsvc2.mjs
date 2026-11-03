// Same as altsvc.mjs but the certificate is trusted for real (a throw-away NSS database in a temp HOME holds the test CA),
// so Chrome treats the origin as legitimate and may switch to HTTP/3 by itself.
import puppeteer from 'puppeteer'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
const [url, host] = process.argv.slice(2)
const browser = await puppeteer.launch({
  headless: true,
  userDataDir: mkdtempSync(join(tmpdir(), 'altsvc-')),
  env: { ...process.env, HOME: process.env.FAKE_HOME },
  args: ['--no-sandbox', '--enable-quic', ...(host ? [`--host-resolver-rules=MAP ${host} 127.0.0.1`] : [])],
})
const seen = []
for (let i = 1; i <= 5; i++) {
  const page = await browser.newPage()
  await page.goto(`${url}?visit=${i}`, { waitUntil: 'load' })
  seen.push(await page.evaluate(() => performance.getEntriesByType('navigation')[0].nextHopProtocol))
  await page.close()
  await new Promise((r) => setTimeout(r, 1500))
}
await browser.close()
console.log('protocolo em cada visita seguida:', seen.join(' -> '))
