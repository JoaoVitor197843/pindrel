#!/usr/bin/env node
// Files against a REAL server, through the page in a real Chrome: the web is built in loadtest mode (the only build that
// accepts ?token=), the Go API is built and started on a temporary folder, and a small server puts the two behind one
// address. Needs Postgres (backend/.env, with the migrations applied), Go and Chrome; ffmpeg adds a video check.
//
//   yarn files:e2e                 builds both, runs every check, cleans up
//   BIG_MB=300 yarn files:e2e      size of the big upload (default 120)
//
// Exit code 1 when a check fails. It is not part of the CI: it needs a database and a browser.
import { execFileSync, execSync, spawn } from 'node:child_process'
import { createHash, randomBytes } from 'node:crypto'
import { createReadStream, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync, createWriteStream } from 'node:fs'
import { createServer, request as httpRequest } from 'node:http'
import { tmpdir } from 'node:os'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const BACKEND = join(ROOT, '..', 'backend')
const OUT = join(ROOT, 'dist-e2e-files')
const CHROME = process.env.CHROME ?? ['/opt/google/chrome/chrome', '/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync)
const BIG_MB = Number(process.env.BIG_MB ?? 120)
if (!CHROME) throw new Error('Chrome not found: set CHROME=/path/to/chrome')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const work = mkdtempSync(join(tmpdir(), 'pindrel-files-e2e-'))

// ---- the backend's settings come from backend/.env
const env = Object.fromEntries(readFileSync(join(BACKEND, '.env'), 'utf8').split('\n').filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))

console.log('construindo o site e o servidor…')
execSync('yarn build --mode loadtest --outDir dist-e2e-files --emptyOutDir', { cwd: ROOT, stdio: 'ignore' })
execFileSync('go', ['build', '-o', join(work, 'api'), './cmd/api'], { cwd: BACKEND, stdio: 'inherit' })

const freePort = () => new Promise((resolve) => { const s = createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)) }) })
const apiPort = await freePort()
const filesDir = join(work, 'files')
mkdirSync(filesDir)
const api = spawn(join(work, 'api'), [], {
  env: { ...process.env, ...env, PORT: String(apiPort), FILES_DIR: filesDir, FILES_MIN_FREE_BYTES: '1073741824', FILE_MAX_BYTES: '2147483648', FILE_QUOTA_BYTES: '21474836480', IN_APP_RATE_LIMIT: 'false', JWT_SECRET: 'e2e-secret', JWT_ACCESS_EXPIRY: '1h', JWT_REFRESH_EXPIRY: '2h', REGISTRATION_ENABLED: 'true', GOMEMLIMIT: '64MiB', DB_MAX_CONNS: '4' },
  stdio: ['ignore', 'ignore', 'pipe'],
})
let apiLog = ''
api.stderr.on('data', (d) => (apiLog += d))
for (let i = 0; i < 100; i++) { try { await fetch(`http://127.0.0.1:${apiPort}/server/info/`); break } catch { await sleep(100) } }

// ---- an account (protobuf by hand: strings are field number, wire type 2, length, bytes)
const field = (n, s) => { const b = Buffer.from(s); return Buffer.concat([Buffer.from([(n << 3) | 2, b.length]), b]) }
const email = `e2e-${Date.now()}@test.com`
await fetch(`http://127.0.0.1:${apiPort}/auth/register/`, { method: 'POST', body: Buffer.concat([field(1, email), field(2, 'e2e'), field(3, 'senha_valida_123')]) })
const login = Buffer.from(await (await fetch(`http://127.0.0.1:${apiPort}/auth/login/`, { method: 'POST', body: Buffer.concat([field(1, email), field(2, 'senha_valida_123')]) })).arrayBuffer())
// field 1 (the token) is a length-delimited string: a tag byte, a varint length, the bytes
const readVarint = (buf, at) => { let v = 0, shift = 0, i = at; for (;;) { const b = buf[i++]; v |= (b & 0x7f) << shift; if (!(b & 0x80)) return [v, i]; shift += 7 } }
const [tokenLength, tokenStart] = readVarint(login, 1)
const token = login.subarray(tokenStart, tokenStart + tokenLength).toString()
if (!/^[\w-]+\.[\w-]+\.[\w-]+$/.test(token)) throw new Error(`login failed: ${login.toString('hex').slice(0, 80)}`)

// ---- one address for the page and the API
const MIME = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.svg': 'image/svg+xml' }
const web = createServer((req, res) => {
  const url = new URL(req.url, 'http://x')
  if (/^\/(files|auth|server)\b/.test(url.pathname)) {
    const up = httpRequest({ host: '127.0.0.1', port: apiPort, method: req.method, path: req.url, headers: req.headers }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res) })
    up.on('error', () => { res.writeHead(502); res.end() })
    req.pipe(up)
    return
  }
  const path = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, '')
  let file = join(OUT, path)
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(OUT, 'index.html')
  res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' })
  createReadStream(file).pipe(res)
}).listen(0, '127.0.0.1')
await new Promise((r) => web.once('listening', r))
const BASE = `http://127.0.0.1:${web.address().port}`

// ---- Chrome
const downloads = join(work, 'downloads')
mkdirSync(downloads)
const profile = join(work, 'chrome')
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--no-first-run', '--disable-extensions', '--window-size=1300,1000', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] })
const port = await new Promise((resolve) => { let b = ''; chrome.stderr.on('data', (d) => { b += d; const m = b.match(/ws:\/\/127\.0\.0\.1:(\d+)\//); if (m) resolve(m[1]) }) })
const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json()
const ws = new WebSocket(target.webSocketDebuggerUrl)
await new Promise((r) => (ws.onopen = r))
let id = 0
const pending = new Map()
ws.onmessage = (m) => { const d = JSON.parse(m.data); pending.get(d.id)?.(d.result ?? d.error) }
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => (await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result?.value
const until = async (expression, ms = 60_000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await ev(expression)) return true; await sleep(100) } return false }

const processes = () => execSync('ps -eo pid=,ppid=,args=').toString().trim().split('\n').map((l) => { const m = l.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/); return { pid: +m[1], ppid: +m[2], args: m[3] } })
const descendants = (root) => { const all = processes(); const out = []; const walk = (p) => all.filter((r) => r.ppid === p).forEach((r) => (out.push(r), walk(r.pid))); walk(root); return out }
const pss = (pid) => { try { return +readFileSync(`/proc/${pid}/smaps_rollup`, 'utf8').match(/^Pss:\s+(\d+)/m)[1] / 1024 } catch { return 0 } }
const renderer = () => Math.max(0, ...descendants(chrome.pid).filter((p) => /--type=renderer/.test(p.args)).map((p) => pss(p.pid)))

let failures = 0
const check = (name, ok, detail = '') => { if (!ok) failures++; console.log(`  ${ok ? '✔' : '✘'} ${name}${ok ? '' : `  → ${detail}`}`) }
const sha = (path) => new Promise((resolve) => { const h = createHash('sha256'); createReadStream(path).on('data', (d) => h.update(d)).on('end', () => resolve(h.digest('hex'))) })
const psql = (sql) => execFileSync('psql', ['-h', env.DB_HOST, '-p', env.DB_PORT, '-U', env.DB_USER, '-d', env.DB_NAME, '-Atc', sql], { env: { ...process.env, PGPASSWORD: env.DB_PASSWORD } }).toString().trim()

async function makeFile(name, mb) {
  const path = join(work, name)
  await new Promise((resolve) => { const w = createWriteStream(path); let left = mb; const next = () => { while (left > 0) { left--; if (!w.write(randomBytes(1 << 20))) return void w.once('drain', next) } w.end(resolve) }; next() })
  return path
}
async function setFile(inputSelector, path) {
  const { root } = await send('DOM.getDocument', { depth: 0 })
  const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: inputSelector })
  if (!nodeId) throw new Error(`no ${inputSelector}`)
  await send('DOM.setFileInputFiles', { nodeId, files: [path] })
}
const clickByLabel = (label) => ev(`(()=>{const el=[...document.querySelectorAll('button,[role=menuitem]')].find((b)=>(b.getAttribute('aria-label')||b.textContent).trim().includes(${JSON.stringify(label)}));if(!el)return false;el.click();return true})()`)
async function openPage(path = '/notes/p5?tela=painel') {
  await send('Page.navigate', { url: `${BASE}${path}${path.includes('?') ? '&' : '?'}token=${token}` })
  await sleep(1800)
}
async function insertBlock(menuItem) {
  await ev(`document.querySelector('textarea[data-draft]').focus()`)
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: '/', text: '/' }); await send('Input.dispatchKeyEvent', { type: 'keyUp', key: '/' })
  await sleep(300)
  return clickByLabel(menuItem)
}

await send('Page.enable'); await send('DOM.enable')
await send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads, eventsEnabled: false })
await send('Emulation.setFocusEmulationEnabled', { enabled: true })

try {
  console.log('\narquivo pequeno de texto, pela tela')
  await openPage()
  check('o bloco Arquivo aparece e a conta está ligada', await insertBlock('Arquivo') && await until(`!!document.querySelector('input[aria-label^="Arraste um arquivo"]')`))
  const small = join(work, 'notas.txt')
  writeFileSync(small, 'olá, mundo\n'.repeat(5000))
  await setFile('input[aria-label^="Arraste um arquivo"]', small)
  check('o cartão com o nome do arquivo aparece', await until(`!!document.querySelector('button[aria-label="Baixar notas.txt"]')`))
  check('o servidor guardou o arquivo com o tamanho certo', psql(`SELECT size FROM files WHERE name='notas.txt' ORDER BY created_at DESC LIMIT 1`) === String(statSync(small).size))
  await clickByLabel('Baixar notas.txt')
  const got = join(downloads, 'notas.txt')
  check('baixar devolve os mesmos bytes', await (async () => { for (let i = 0; i < 50 && !existsSync(got); i++) await sleep(100); return existsSync(got) && (await sha(got)) === (await sha(small)) })())

  console.log('\nimagem')
  await openPage()
  await insertBlock('Imagem')
  await until(`!!document.querySelector('input[aria-label^="Arraste uma imagem"]')`)
  const png = join(work, 'foto.png')
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=320x200:rate=1', '-frames:v', '1', png])
  await setFile('input[aria-label^="Arraste uma imagem"]', png)
  check('a imagem do servidor carrega no navegador', await until(`(()=>{const i=document.querySelector('img[alt="foto.png"]');return !!i&&i.complete&&i.naturalWidth===320})()`))

  console.log('\nvídeo (precisa do ffmpeg)')
  let hasFfmpeg = true
  try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }) } catch { hasFfmpeg = false }
  if (hasFfmpeg) {
    await openPage()
    await insertBlock('Vídeo')
    await until(`!!document.querySelector('input[aria-label^="…ou envie"]')`)
    const mp4 = join(work, 'aula.mp4')
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=10', '-t', '4', '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-movflags', '+faststart', mp4])
    await setFile('input[aria-label^="…ou envie"]', mp4)
    check('o player aparece sem baixar nada antes do play', await until(`(()=>{const v=document.querySelector('video');return !!v&&v.preload==='none'&&v.src.includes('/files/')})()`))
    await ev(`document.querySelector('video').muted=true; document.querySelector('video').play().catch(()=>{})`)
    check('toca (o servidor entrega com Range)', await until(`(()=>{const v=document.querySelector('video');return v.currentTime>0.3})()`, 20000))
    await ev(`document.querySelector('video').currentTime = 3`)
    check('avançar para o meio funciona (pedido de Range)', await until(`document.querySelector('video').currentTime>=3&&!document.querySelector('video').seeking`, 10000))
  } else console.log('  (ffmpeg não encontrado: pulado)')

  console.log(`\narquivo grande de ${BIG_MB} MB, e a memória da página`)
  await openPage()
  await insertBlock('Arquivo')
  await until(`!!document.querySelector('input[aria-label^="Arraste um arquivo"]')`)
  const big = await makeFile('grande.bin', BIG_MB)
  const bigSha = await sha(big)
  const before = renderer()
  let peak = before
  const sampler = setInterval(() => (peak = Math.max(peak, renderer())), 100)
  const t0 = Date.now()
  await setFile('input[aria-label^="Arraste um arquivo"]', big)
  const sent = await until(`!!document.querySelector('button[aria-label="Baixar grande.bin"]')`, 600_000)
  clearInterval(sampler)
  const secs = (Date.now() - t0) / 1000
  check(`enviado em ${secs.toFixed(1)} s (${(BIG_MB / secs).toFixed(0)} MB/s)`, sent)
  const blob = join(filesDir, 'blobs', bigSha.slice(0, 2), bigSha.slice(2, 4), bigSha)
  check('no disco do servidor o arquivo tem o nome do seu SHA-256 e o tamanho certo', existsSync(blob) && statSync(blob).size === statSync(big).size)
  check(`a memória da página não cresceu com o arquivo (de ${before.toFixed(0)} MB a ${peak.toFixed(0)} MB no pico)`, peak - before < Math.max(60, BIG_MB / 3), `${(peak - before).toFixed(0)} MB a mais`)
  await clickByLabel('Baixar grande.bin')
  await sleep(300)
  check('arquivo de tipo desconhecido pede confirmação antes de baixar', await until(`!!document.querySelector('[role=alertdialog]')`, 5000))
  await clickByLabel('Baixar mesmo assim')
  const back = join(downloads, 'grande.bin')
  check('baixar de volta devolve os mesmos bytes', await (async () => { for (let i = 0; i < 600; i++) { if (existsSync(back) && !existsSync(`${back}.crdownload`)) break; await sleep(200) } return existsSync(back) && (await sha(back)) === bigSha })())

  console.log('\ncancelar no meio')
  await openPage()
  await insertBlock('Arquivo')
  await until(`!!document.querySelector('input[aria-label^="Arraste um arquivo"]')`)
  const cancelSource = await makeFile('cancelar.bin', 100)
  const filesBefore = Number(psql('SELECT count(*) FROM files'))
  await setFile('input[aria-label^="Arraste um arquivo"]', cancelSource)
  await until(`(()=>{const p=document.querySelector('[role=progressbar]');return !!p&&Number(p.getAttribute('aria-valuenow'))>=3})()`, 60_000)
  await clickByLabel('Cancelar')
  await sleep(1500)
  check('o servidor não guardou o arquivo cancelado e não deixou envio aberto', Number(psql('SELECT count(*) FROM files')) === filesBefore && Number(psql(`SELECT count(*) FROM uploads u JOIN users x ON x.id=u.user_id WHERE x.email='${email}'`)) === 0)
  check('o bloco voltou a pedir o arquivo', await ev(`!!document.querySelector('input[aria-label^="Arraste um arquivo"]')`))

  console.log('\nsoltar arquivos na página')
  await openPage()
  const blocksBefore = await ev(`document.querySelectorAll('[data-block-id]').length`)
  await ev(`(()=>{const dt=new DataTransfer();dt.items.add(new File([new Uint8Array(3000).fill(65)],'a.txt'));dt.items.add(new File([new Uint8Array(3000).fill(66)],'b.zip'));document.querySelector('article').dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:dt}))})()`)
  check('os dois arquivos viram dois blocos', await until(`document.querySelectorAll('[data-block-id]').length===${blocksBefore + 2}`, 5000))
  check('e chegam ao servidor', await until(`!!document.querySelector('button[aria-label="Baixar a.txt"]')&&!!document.querySelector('button[aria-label="Baixar b.zip"]')`, 20_000))

  console.log('\napagar o bloco solta o arquivo no servidor')
  const orphansBefore = Number(psql(`SELECT count(*) FROM files f JOIN users x ON x.id=f.user_id WHERE x.email='${email}' AND f.orphan_since IS NOT NULL`))
  await ev(`(()=>{const row=[...document.querySelectorAll('[data-block-id]')].find((r)=>r.textContent.includes('a.txt'));row.querySelector('button[aria-label^="Opções de"]').click()})()`)
  await sleep(200)
  await ev(`[...document.querySelectorAll('[role=menuitem]')].find((m)=>m.textContent.trim()==='Excluir').click()`)
  await sleep(1200)
  const orphansAfter = Number(psql(`SELECT count(*) FROM files f JOIN users x ON x.id=f.user_id WHERE x.email='${email}' AND f.orphan_since IS NOT NULL`))
  check('o arquivo do bloco apagado foi marcado como sem uso', orphansAfter === orphansBefore + 1, `${orphansBefore} → ${orphansAfter}`)

  const apiRss = (() => { try { return +readFileSync(`/proc/${api.pid}/status`, 'utf8').match(/VmRSS:\s+(\d+)/)[1] / 1024 } catch { return 0 } })()
  console.log(`\nRSS da API no fim: ${apiRss.toFixed(0)} MB`)
  check('a API continuou pequena depois de tudo isso', apiRss < 90, `${apiRss.toFixed(0)} MB`)
} finally {
  ws.close()
  chrome.kill('SIGKILL')
  api.kill('SIGTERM')
  web.close()
  await sleep(500)
  try { psql(`DELETE FROM users WHERE email='${email}'`) } catch { /* the account stays if the database is gone */ }
  rmSync(work, { recursive: true, force: true })
}
if (failures) console.log(apiLog.split('\n').slice(-8).join('\n'))
console.log(failures ? `\n${failures} verificação(ões) falharam` : '\ntudo certo')
process.exit(failures ? 1 : 0)
