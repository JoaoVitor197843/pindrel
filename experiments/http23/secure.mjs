import puppeteer from 'puppeteer'
const probe = async (label, url, home) => {
  const browser = await puppeteer.launch({ headless: true, env: { ...process.env, ...(home ? { HOME: home } : {}) }, args: ['--no-sandbox', '--disable-quic'] })
  const page = await browser.newPage()
  try {
    await page.goto(url, { waitUntil: 'load', timeout: 15000 })
    const r = await page.evaluate(async () => ({
      secure: window.isSecureContext,
      serviceWorker: 'serviceWorker' in navigator,
      subtle: !!(globalThis.crypto && crypto.subtle),
      clipboard: !!navigator.clipboard,
      hash: globalThis.crypto?.subtle ? [...new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(4)))].length : '-',
    }))
    console.log(label.padEnd(44), JSON.stringify(r))
  } catch (e) { console.log(label.padEnd(44), 'NÃO ABRE:', e.message.split(' at ')[0]) }
  await browser.close()
}
await probe('http://IP-da-LAN (hoje)', 'http://192.168.1.163:8502/')
await probe('https://IP-da-LAN, CA NÃO instalada', 'https://192.168.1.163:8503/')
await probe('https://IP-da-LAN, CA instalada no navegador', 'https://192.168.1.163:8503/', process.argv[2])
