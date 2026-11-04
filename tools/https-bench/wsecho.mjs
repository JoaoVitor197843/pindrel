// WebSocket echo server for the experiment (the Go API has no WebSocket endpoint yet).
import { WebSocketServer } from 'ws'
const wss = new WebSocketServer({ port: Number(process.env.PORT ?? 9500), host: '127.0.0.1', path: '/ws' })
wss.on('connection', (ws) => ws.on('message', (d, bin) => ws.send(d, { binary: bin })))
console.log('ws echo on', process.env.PORT ?? 9500)
