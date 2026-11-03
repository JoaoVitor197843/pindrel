// A loopback proxy that adds round-trip latency, for TCP and UDP (QUIC), because the DevTools throttling shifts bytes
// per second but not the round trips, which is exactly what TLS and QUIC change.
// usage: node latproxy.mjs <rttMs> <listenPort>:<targetPort>[:udp] ...
import net from 'node:net'
import dgram from 'node:dgram'

const [rttArg, ...maps] = process.argv.slice(2)
const rtt = Number(rttArg)
const oneWay = rtt / 2
const later = (ms, fn) => (ms <= 0 ? fn() : setTimeout(fn, ms))

for (const m of maps) {
  const [listen, target, kind] = m.split(':')
  if (kind === 'udp') {
    const server = dgram.createSocket('udp4')
    const flows = new Map()
    server.on('message', (msg, rinfo) => {
      const key = `${rinfo.address}:${rinfo.port}`
      let up = flows.get(key)
      if (!up) {
        up = dgram.createSocket('udp4')
        up.on('message', (reply) => later(oneWay, () => server.send(reply, rinfo.port, rinfo.address)))
        flows.set(key, up)
      }
      later(oneWay, () => up.send(msg, Number(target), '127.0.0.1'))
    })
    server.bind(Number(listen), '127.0.0.1')
  } else {
    net
      .createServer((client) => {
        // the kernel already finished the TCP handshake with this proxy; the real one costs a round trip
        const ready = Date.now() + rtt
        const up = net.connect(Number(target), '127.0.0.1')
        const pipe = (from, to) => {
          from.on('data', (d) => later(Math.max(oneWay, ready - Date.now() + oneWay), () => !to.destroyed && to.write(d)))
          from.on('end', () => later(oneWay, () => to.end()))
          from.on('error', () => to.destroy())
        }
        pipe(client, up)
        pipe(up, client)
      })
      .listen(Number(listen), '127.0.0.1')
  }
}
console.log(`latproxy: rtt=${rtt}ms`, maps.join(' '))
