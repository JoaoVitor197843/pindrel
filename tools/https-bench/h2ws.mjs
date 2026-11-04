// Does the server accept WebSocket over HTTP/2 (RFC 8441, extended CONNECT)? How many on ONE TCP connection?
import http2 from 'node:http2'
const [port, count = '200'] = process.argv.slice(2)
const c = http2.connect(`https://localhost:${port}`, { rejectUnauthorized: false })
c.on('error', (e) => { console.log(`:${port} erro`, e.code); process.exit(0) })
await new Promise((r) => c.once('remoteSettings', r))
console.log(`:${port} SETTINGS_ENABLE_CONNECT_PROTOCOL =`, c.remoteSettings.enableConnectProtocol ?? false)
if (!c.remoteSettings.enableConnectProtocol) process.exit(0)
let ok = 0
const t0 = Date.now()
await Promise.all(Array.from({ length: Number(count) }, () => new Promise((res) => {
  const s = c.request({ ':method': 'CONNECT', ':protocol': 'websocket', ':scheme': 'https', ':path': '/ws', ':authority': `localhost:${port}`, 'sec-websocket-version': '13' })
  s.on('response', (h) => { if (h[':status'] === 200) ok++; res() })
  s.on('error', () => res())
  setTimeout(res, 4000)
})))
console.log(`:${port} ${ok}/${count} WebSockets abertos em UMA conexão TCP, ${Date.now() - t0} ms`)
process.exit(0)
