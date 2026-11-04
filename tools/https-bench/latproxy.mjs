// A loopback proxy that adds round-trip latency, for TCP and UDP (QUIC), because the DevTools throttling shifts bytes
// per second but not the round trips, which is exactly what TLS and QUIC change.
// usage: LOSS=0.02 node latproxy.mjs <rttMs> <listenPort>:<targetPort>[:udp] ...
// LOSS is the share of packets lost. UDP: the datagram is dropped (QUIC retransmits it). TCP: the kernel would retransmit
// after a timeout and everything behind the lost segment waits (head-of-line blocking), which is modelled here by
// delaying the chunk by the timeout and keeping the order.
import net from 'node:net'
import dgram from 'node:dgram'

const [rttArg, ...maps] = process.argv.slice(2)
const rtt = Number(rttArg)
const oneWay = rtt / 2
const loss = Number(process.env.LOSS ?? 0)
const RTO = Math.max(200, 2 * rtt)
const later = (ms, fn) => (ms <= 0 ? fn() : setTimeout(fn, ms))

for (const m of maps) {
  const [listen, target, kind] = m.split(':')
  if (kind === 'udp') {
    const server = dgram.createSocket('udp4')
    const flows = new Map()
    server.on('message', (msg, rinfo) => {
      if (Math.random() < loss) return
      const key = `${rinfo.address}:${rinfo.port}`
      let up = flows.get(key)
      if (!up) {
        up = dgram.createSocket('udp4')
        up.on('message', (reply) => Math.random() >= loss && later(oneWay, () => server.send(reply, rinfo.port, rinfo.address)))
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
          // one queue per direction, released in order: bytes of a TCP stream never overtake each other
          const queue = []
          let timer
          let last = 0
          const pump = () => {
            timer = undefined
            while (queue.length && queue[0].at <= Date.now()) {
              const item = queue.shift()
              if (item.end) to.end()
              else if (!to.destroyed) to.write(item.data)
            }
            if (queue.length) timer = setTimeout(pump, Math.max(0, queue[0].at - Date.now()))
          }
          const push = (item) => {
            last = item.at = Math.max(item.at, last)
            queue.push(item)
            if (!timer) timer = setTimeout(pump, Math.max(0, item.at - Date.now()))
          }
          from.on('data', (d) => {
            const packets = Math.ceil(d.length / 1400)
            const lost = loss > 0 && Math.random() < 1 - (1 - loss) ** packets
            push({ data: d, at: Math.max(Date.now(), ready) + oneWay + (lost ? RTO : 0) })
          })
          from.on('end', () => push({ end: true, at: Date.now() + oneWay }))
          from.on('error', () => to.destroy())
        }
        pipe(client, up)
        pipe(up, client)
      })
      .listen(Number(listen), '127.0.0.1')
  }
}
console.log(`latproxy: rtt=${rtt}ms`, maps.join(' '))
