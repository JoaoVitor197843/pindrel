// How does a browser reach HTTP/3 without being told? It learns it from the `Alt-Svc` header of an HTTP/2 answer and uses
// it on the next connection. usage: SPKI=<pin> node altsvc.mjs https://localhost:8203/
import puppeteer from 'puppeteer'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const url = process.argv[2]
const browser = await puppeteer.launch({
  headless: true,
  userDataDir: mkdtempSync(join(tmpdir(), 'altsvc-')),
  args: ['--no-sandbox', `--ignore-certificate-errors-spki-list=${process.env.SPKI}`, '--enable-quic'],
})
const seen = []
for (let i = 1; i <= 4; i++) {
  const page = await browser.newPage()
  await page.goto(`${url}?visit=${i}`, { waitUntil: 'load' })
  seen.push(await page.evaluate(() => performance.getEntriesByType('navigation')[0].nextHopProtocol))
  await page.close()
  await new Promise((r) => setTimeout(r, 1500))
}
await browser.close()
console.log('protocolo em cada visita seguida:', seen.join(' -> '))
