#!/usr/bin/env node
// Sign-up, sign-in, session and the two panels against a REAL server, through the page in a real Chrome: the normal web
// build, the Go API on a temporary folder, and a small server that puts both behind one address. Needs Postgres
// (backend/.env, with the migrations applied), Go and Chrome.
//
//   yarn auth:e2e
//
// Exit code 1 when a check fails. It is not part of the CI: it needs a database and a browser.
import { execFileSync, execSync, spawn } from 'node:child_process'
import { createReadStream, existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { createServer, request as httpRequest } from 'node:http'
import { tmpdir } from 'node:os'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const BACKEND = join(ROOT, '..', 'backend')
const OUT = join(ROOT, 'dist-e2e-auth')
const CHROME = process.env.CHROME ?? ['/opt/google/chrome/chrome', '/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync)
if (!CHROME) throw new Error('Chrome not found: set CHROME=/path/to/chrome')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const work = mkdtempSync(join(tmpdir(), 'pindrel-auth-e2e-'))
const env = Object.fromEntries(readFileSync(join(BACKEND, '.env'), 'utf8').split('\n').filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]))

console.log('construindo o site e o servidor…')
execSync('yarn build --outDir dist-e2e-auth --emptyOutDir', { cwd: ROOT, stdio: 'ignore' })
execFileSync('go', ['build', '-o', join(work, 'api'), './cmd/api'], { cwd: BACKEND, stdio: 'inherit' })

const freePort = () => new Promise((resolve) => { const s = createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)) }) })
const apiPort = await freePort()
const api = spawn(join(work, 'api'), [], {
  env: { ...process.env, ...env, PORT: String(apiPort), IN_APP_RATE_LIMIT: 'false', JWT_SECRET: 'e2e-secret', JWT_ACCESS_EXPIRY: '1h', JWT_REFRESH_EXPIRY: '2h', REGISTRATION_ENABLED: 'true', GOMEMLIMIT: '64MiB', DB_MAX_CONNS: '4' },
  stdio: ['ignore', 'ignore', 'pipe'],
})
let apiLog = ''
api.stderr.on('data', (d) => (apiLog += d))
for (let i = 0; i < 100; i++) { try { await fetch(`http://127.0.0.1:${apiPort}/server/info/`); break } catch { await sleep(100) } }

// every request that reaches the API is counted, so "local mode never calls the server" can be checked
const seen = []
const MIME = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.svg': 'image/svg+xml' }
const web = createServer((req, res) => {
  const url = new URL(req.url, 'http://x')
  if (/^\/(auth|server)\b/.test(url.pathname)) {
    seen.push(`${req.method} ${url.pathname}`)
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

const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${join(work, 'chrome')}`, '--no-first-run', '--disable-extensions', '--window-size=1300,1000', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] })
const port = await new Promise((resolve) => { let b = ''; chrome.stderr.on('data', (d) => { b += d; const m = b.match(/ws:\/\/127\.0\.0\.1:(\d+)\//); if (m) resolve(m[1]) }) })
const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json()
const ws = new WebSocket(target.webSocketDebuggerUrl)
await new Promise((r) => (ws.onopen = r))
let id = 0
const pending = new Map()
ws.onmessage = (m) => { const d = JSON.parse(m.data); pending.get(d.id)?.(d.result ?? d.error) }
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => (await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result?.value
const until = async (expression, ms = 10_000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await ev(expression)) return true; await sleep(100) } return false }
const text = () => ev('document.body.innerText')
const go = async (path) => { await send('Page.navigate', { url: `${BASE}${path}` }); await sleep(600) }
const click = (label) => ev(`(()=>{const el=[...document.querySelectorAll('button,a,[role=menuitem]')].find((b)=>(b.getAttribute('aria-label')||b.textContent).trim().includes(${JSON.stringify(label)}));if(!el)return false;el.click();return true})()`)
const typeInto = async (selector, value) => { await ev(`document.querySelector(${JSON.stringify(selector)}).focus()`); await send('Input.insertText', { text: value }) }
const cookies = async () => (await send('Network.getCookies', { urls: [BASE] })).cookies ?? []

let failures = 0
const check = (name, ok, detail = '') => { if (!ok) failures++; console.log(`  ${ok ? '✔' : '✘'} ${name}${ok ? '' : `  → ${detail}`}`) }
const email = `e2e-${Date.now()}@test.com`
const password = 'senha_valida_123'

await send('Page.enable'); await send('Network.enable')
try {
  console.log('\nmodo "Continuar sem login": nunca fala com o servidor')
  seen.length = 0
  await go('/')
  seen.length = 0 // the login screen itself asks /server/info/
  await click('Continuar sem login')
  check('abre o painel local', await until(`location.search === '?tela=painel&modo=local'`))
  await sleep(1500)
  await go('/?tela=painel&modo=local')
  await sleep(1500)
  check('nenhuma chamada à API no painel local (nem após recarregar)', !seen.some((s) => !s.startsWith('GET /server/info')) && seen.length === 0, seen.join(', '))
  check('o painel local começa vazio', !/Pão de fermentação|Reforma do apartamento/.test(await text()))

  console.log('\nacesso sem sessão')
  for (const path of ['/?tela=painel&modo=conta', '/notes/p1?tela=painel&modo=conta', '/?tela=painel', '/notes/p0?tela=painel']) {
    await go(path)
    await sleep(800)
    const t = await text()
    check(`${path} sem sessão mostra o login`, /Bem-vindo de volta/.test(t) && !/Minhas páginas/.test(t), t.slice(0, 80))
  }
  await ev(`localStorage.setItem('pindrel:account','1')`)
  await go('/?tela=painel&modo=conta')
  await sleep(800)
  check('uma marca velha sem cookie também cai no login (e a marca some)', /Bem-vindo de volta/.test(await text()) && (await ev(`localStorage.getItem('pindrel:account')`)) === null)

  console.log('\ncriar conta pela tela')
  await go('/')
  await click('Criar conta')
  await until(`!!document.querySelector('#username')`)
  await typeInto('#username', 'e2euser')
  await typeInto('#email', email)
  await typeInto('#password', password)
  await click('Criar conta') // the submit button
  check('entra sozinho no painel da conta depois de criar', await until(`location.search === '?tela=painel&modo=conta'`, 15_000), await text())
  await go('/?tela=painel&modo=conta')
  await until(`/Minhas páginas/.test(document.body.innerText)`)
  await click('Criar primeira página')
  await sleep(500)
  await ev(`document.querySelector('[data-testid=page-card] button')?.click()`)
  await until(`!!document.querySelector('textarea[aria-label="Título da página"]')`)
  await sleep(500)
  await ev(`window.dispatchEvent(new Event('resize'))`)
  if (!(await ev(`!!document.querySelector('[data-testid=meta]')`))) await click('Abrir propriedades')
  await sleep(500)
  check('"Dono" mostra o username da conta', await until(`/dono\\s*e2euser/i.test(document.querySelector('[data-testid=meta]')?.innerText ?? '')`, 4000), await ev(`document.querySelector('[data-testid=meta]')?.innerText ?? 'sem painel: ' + [...document.querySelectorAll('button')].map((b)=>b.getAttribute('aria-label')).filter(Boolean).join(' | ')`))
  await go('/?tela=painel&modo=conta')
  check('o painel da conta começa vazio', !/Pão de fermentação|Reforma do apartamento/.test(await text()))
  const c = (await cookies()).find((k) => k.name === 'refresh_token')
  check('o cookie de renovação é HttpOnly', !!c?.httpOnly, JSON.stringify(c))
  check('"Manter conectado" (padrão) dá um cookie com validade', !!c && c.expires > 0 && !c.session, JSON.stringify(c))
  check('o token de acesso não foi parar no armazenamento', !(await ev(`JSON.stringify([localStorage, sessionStorage])`)).match(/eyJ/))

  console.log('\nsessão sobrevive a recarregar')
  await go('/?tela=painel&modo=conta')
  check('recarregar mantém o painel da conta (renova pelo cookie)', await until(`location.search === '?tela=painel&modo=conta' && /Minhas páginas/.test(document.body.innerText)`, 10_000), await text())
  await go('/')
  check('abrir a raiz de um aparelho já conectado leva ao painel', await until(`location.search === '?tela=painel&modo=conta'`, 10_000), await ev('location.href'))

  console.log('\nsair')
  await ev(`[...document.querySelectorAll('button')].find((b)=>/Menu da conta/.test(b.getAttribute('aria-label')||''))?.click()`)
  await sleep(300)
  await click('Sair')
  check('sair volta ao login', await until(`location.pathname === '/' && !location.search && /Bem-vindo de volta/.test(document.body.innerText)`, 10_000), await text())
  await go('/')
  await sleep(800)
  check('depois de sair, recarregar mostra o login (cookie revogado)', /Bem-vindo de volta/.test(await text()))

  console.log('\nentrar pela tela')
  await typeInto('#email', email)
  await typeInto('#password', 'senha_errada_000')
  await ev(`document.querySelector('form').requestSubmit()`)
  check('senha errada mostra o erro em português', await until(`!!document.querySelector('[data-testid=form-error]')`), await text())
  await ev(`(()=>{const e=document.querySelector('#password');e.focus();e.select()})()`)
  await send('Input.insertText', { text: password })
  await ev(`document.querySelector('form').requestSubmit()`)
  check('senha certa entra no painel da conta', await until(`location.search === '?tela=painel&modo=conta'`, 15_000), await text())

  console.log('\nsem "Manter conectado": cookie de sessão')
  await ev(`[...document.querySelectorAll('button')].find((b)=>/Menu da conta/.test(b.getAttribute('aria-label')||''))?.click()`)
  await sleep(300)
  await click('Sair')
  await until(`/Bem-vindo de volta/.test(document.body.innerText)`)
  await typeInto('#email', email)
  await typeInto('#password', password)
  await ev(`document.querySelector('input[type=checkbox]').click()`)
  await ev(`document.querySelector('form').requestSubmit()`)
  await until(`location.search === '?tela=painel&modo=conta'`, 15_000)
  const s = (await cookies()).find((k) => k.name === 'refresh_token')
  check('o cookie sai sem validade (some ao fechar o navegador)', !!s && s.session === true, JSON.stringify(s))
} finally {
  chrome.kill()
  api.kill()
  web.close()
  rmSync(work, { recursive: true, force: true })
  rmSync(OUT, { recursive: true, force: true })
  try { execFileSync('psql', ['-h', env.DB_HOST, '-p', env.DB_PORT, '-U', env.DB_USER, '-d', env.DB_NAME, '-Atc', `DELETE FROM users WHERE email='${email}'`], { env: { ...process.env, PGPASSWORD: env.DB_PASSWORD }, stdio: 'ignore' }) } catch {}
}
if (failures) console.log(`\n${failures} falha(s)\n${apiLog.slice(-600)}`)
console.log(failures ? '' : '\ntudo certo')
process.exit(failures ? 1 : 0)
