#!/usr/bin/env node
// Memory of the web app in a real Chrome, scenario by scenario, against a budget.
//
//   yarn memory                 builds with `--mode loadtest` (only that build can fabricate pages and blocks), serves it,
//                               opens each scenario in a fresh headless Chrome and prints the memory of its renderer
//   CHROME=/path/to/chrome yarn memory      pick the browser; BUDGET_MB=100 changes the limit
//
// "Memory" is the PSS of the page's renderer process (what the page costs, shared pages counted once), read from
// /proc, so it is Linux only. The API and IndexedDB are not part of it. Exit code 1 when a budgeted scenario is over.
import { execSync, spawn } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const OUT = join(ROOT, 'dist-loadtest')
const BUDGET = Number(process.env.BUDGET_MB ?? 100)
const CHROME = process.env.CHROME ?? ['/opt/google/chrome/chrome', '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'].find(existsSync)
if (!CHROME) throw new Error('Chrome not found: set CHROME=/path/to/chrome')

// [name, path, budgeted, JavaScript to run once loaded (optional)]
const SCENARIOS = [
  ['aba em branco', 'about:blank', false],
  ['login', '/', true],
  ['dashboard, 23 páginas', '/?tela=painel', true],
  ['dashboard, 1000 páginas', '/?tela=painel&pages=1000', true],
  ['dashboard, 5000 páginas', '/?tela=painel&pages=5000', true],
  ['editor, página de exemplo', '/notes/p0?tela=painel', true],
  ['editor, 3000 blocos', '/notes/p0?tela=painel&blocks=3000', true],
  ['editor, 6000 blocos', '/notes/p0?tela=painel&blocks=6000', true],
  ['editor, 10000 blocos (extremo)', '/notes/p0?tela=painel&blocks=10000', false],
]

// A focused block loads the rich-text editor (TipTap) and mounts it: the cost of editing, on top of the page itself
const FOCUS = "document.querySelector('[data-view]')?.focus()"
SCENARIOS.push(
  ['exemplo, bloco em edição', '/notes/p0?tela=painel', true, FOCUS],
  ['3000 blocos, bloco em edição', '/notes/p0?tela=painel&blocks=3000', true, FOCUS],
  ['6000 blocos, bloco em edição', '/notes/p0?tela=painel&blocks=6000', true, FOCUS],
)
if (process.env.ONLY) {
  const keep = process.env.ONLY.split('|')
  SCENARIOS.splice(0, SCENARIOS.length, ...SCENARIOS.filter((s) => keep.some((k) => s[0].includes(k))))
}

if (!process.env.SKIP_BUILD) execSync('yarn build --mode loadtest --outDir dist-loadtest --emptyOutDir', { cwd: ROOT, stdio: 'ignore' })

const MIME = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.svg': 'image/svg+xml', '.json': 'application/json' }
const server = createServer((req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '')
  let file = join(OUT, path)
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(OUT, 'index.html') // the app has no server routes: any path is the page
  res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' })
  res.end(readFileSync(file))
}).listen(0, '127.0.0.1')
await new Promise((r) => server.once('listening', r))
const BASE = `http://127.0.0.1:${server.address().port}`

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const processes = () =>
  execSync('ps -eo pid=,ppid=,args=').toString().trim().split('\n').map((l) => { const m = l.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/); return { pid: +m[1], ppid: +m[2], args: m[3] } })
const descendants = (root) => { const all = processes(); const out = []; const walk = (p) => all.filter((r) => r.ppid === p).forEach((r) => (out.push(r), walk(r.pid))); walk(root); return out }
const pss = (pid) => { try { return +readFileSync(`/proc/${pid}/smaps_rollup`, 'utf8').match(/^Pss:\s+(\d+)/m)[1] / 1024 } catch { return 0 } }

async function measure([name, path, , act]) {
  const dir = mkdtempSync('/tmp/pindrel-mem-')
  const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${dir}`, '--no-first-run', '--disable-extensions', '--window-size=1500,900', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] })
  const port = await new Promise((resolve) => {
    let buf = ''
    chrome.stderr.on('data', (d) => { buf += d; const m = buf.match(/ws:\/\/127\.0\.0\.1:(\d+)\//); if (m) resolve(m[1]) })
  })
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json()
  const ws = new WebSocket(target.webSocketDebuggerUrl)
  await new Promise((r) => (ws.onopen = r))
  let id = 0
  const pending = new Map()
  ws.onmessage = (m) => { const d = JSON.parse(m.data); pending.get(d.id)?.(d.result ?? d.error) }
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
  await send('Page.enable'); await send('Performance.enable'); await send('HeapProfiler.enable')
  // a headless page is never "focused": without this, element.focus() fires no focus event
  await send('Emulation.setFocusEmulationEnabled', { enabled: true })
  await send('Page.navigate', { url: path.startsWith('about:') ? path : BASE + path })
  await sleep(path.startsWith('about:') ? 2000 : 6000)
  let mounted = null
  if (act) {
    await send('Runtime.evaluate', { expression: act })
    await sleep(2500)
    mounted = (await send('Runtime.evaluate', { expression: "!!document.querySelector('[data-rich]')" })).result?.value
  }
  await send('HeapProfiler.collectGarbage'); await sleep(500)
  const heap = await send('Runtime.getHeapUsage')
  const metrics = Object.fromEntries((await send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]))
  const procs = descendants(chrome.pid)
  const kind = (a) => a.match(/--type=([\w-]+)/)?.[1]
  const renderer = Math.max(0, ...procs.filter((p) => kind(p.args) === 'renderer').map((p) => pss(p.pid)))
  const gpu = procs.filter((p) => kind(p.args) === 'gpu-process').reduce((s, p) => s + pss(p.pid), 0)
  ws.close(); chrome.kill('SIGKILL'); await sleep(300); rmSync(dir, { recursive: true, force: true })
  return { renderer, gpu, heap: heap.usedSize / 1048576, nodes: metrics.Nodes, mounted }
}

let failed = false
console.log(`orçamento: ${BUDGET} MB no renderer (sem API nem IndexedDB)\n`)
console.log('cenário'.padEnd(30), 'renderer'.padStart(9), 'GPU'.padStart(6), 'heap JS'.padStart(9), 'nós DOM'.padStart(9))
for (const s of SCENARIOS) {
  const r = await measure(s)
  const over = s[2] && r.renderer > BUDGET
  failed ||= over
  console.log(s[0].padEnd(30), `${r.renderer.toFixed(0)} MB`.padStart(9), `${r.gpu.toFixed(0)} MB`.padStart(6), `${r.heap.toFixed(1)} MB`.padStart(9), String(r.nodes).padStart(9), r.mounted === null ? '' : r.mounted ? '  editor montado' : '  EDITOR NÃO MONTOU', over ? '  ACIMA DO ORÇAMENTO' : '')
}
server.close()
process.exit(failed ? 1 : 0)
