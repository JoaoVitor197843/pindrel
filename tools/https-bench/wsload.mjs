// Holds N idle WebSocket connections (ws library, HTTP/1.1 upgrade) so the RAM of each terminator can be read.
// usage: node wsload.mjs <wss://host:port/ws> <count> <holdSeconds>
import WebSocket from 'ws'
const [url, count = '500', hold = '8'] = process.argv.slice(2)
const socks = []
let open = 0
await Promise.all(Array.from({ length: Number(count) }, (_, i) => new Promise((resolve) => {
  const ws = new WebSocket(url, { rejectUnauthorized: false, localAddress: `127.0.0.${2 + (i % 40)}` })
  ws.on('open', () => { open++; socks.push(ws); resolve() })
  ws.on('error', () => resolve())
})))
console.log(`abertas: ${open}/${count}`)
await new Promise((r) => setTimeout(r, Number(hold) * 1000))
socks.forEach((s) => s.close())
