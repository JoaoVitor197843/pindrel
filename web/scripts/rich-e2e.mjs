#!/usr/bin/env node
// The rich-text editor (TipTap) in a real Chrome, with real key presses, selection and clipboard events: what jsdom cannot do.
//
//   yarn rich:e2e                       builds the app, serves it, and runs every check
//   CHROME=/path/to/chrome yarn rich:e2e     picks the browser; E2E_URL=http://localhost:5173 uses a dev server
//
// Exit code 1 when a check fails.
import { execSync, spawn } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const OUT = join(ROOT, 'dist-e2e')
const CHROME = process.env.CHROME ?? ['/opt/google/chrome/chrome', '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'].find(existsSync)
if (!CHROME) throw new Error('Chrome not found: set CHROME=/path/to/chrome')
const ENGINES = ['tiptap']

if (!process.env.SKIP_BUILD && !process.env.E2E_URL) execSync('yarn build --outDir dist-e2e --emptyOutDir', { cwd: ROOT, stdio: 'ignore' })
const MIME = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.svg': 'image/svg+xml' }
const server = createServer((req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '')
  let file = join(OUT, path)
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(OUT, 'index.html')
  res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' })
  res.end(readFileSync(file))
}).listen(0, '127.0.0.1')
await new Promise((r) => server.once('listening', r))
// E2E_URL=http://localhost:5173 runs against a dev server instead (readable stack traces)
const BASE = process.env.E2E_URL ?? `http://127.0.0.1:${server.address().port}`

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const dir = mkdtempSync('/tmp/pindrel-e2e-')
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${dir}`, '--no-first-run', '--disable-extensions', '--window-size=1200,900', 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] })
const port = await new Promise((resolve) => { let b = ''; chrome.stderr.on('data', (d) => { b += d; const m = b.match(/ws:\/\/127\.0\.0\.1:(\d+)\//); if (m) resolve(m[1]) }) })
const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json()
const ws = new WebSocket(target.webSocketDebuggerUrl)
await new Promise((r) => (ws.onopen = r))
let id = 0
const pending = new Map()
ws.onmessage = (m) => { const d = JSON.parse(m.data); pending.get(d.id)?.(d.result ?? d.error) }
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
const ev = async (expression) => (await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result?.value
const key = async (k, mods = 0, code = k) => {
  for (const type of ['keyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: k, code, modifiers: mods, windowsVirtualKeyCode: k.length === 1 ? k.toUpperCase().charCodeAt(0) : 0 })
}
const typeText = async (s) => { for (const c of s) { await send('Input.dispatchKeyEvent', { type: 'keyDown', key: c, text: c }); await send('Input.dispatchKeyEvent', { type: 'keyUp', key: c }); await sleep(12) } }
const CTRL = 2, SHIFT = 8

// helpers that run in the page
const EDITABLE = "document.querySelector('[data-rich] [contenteditable]')"
const views = (n) => `document.querySelectorAll('[role=textbox][data-view]')[${n}]`
const clean = (h) => h.replace(/ (class|style|dir|data-[a-z-]+)="[^"]*"/g, '')
const focusBlock = async (n) => { await ev(`${views(n)}.focus()`); await sleep(900) }
const caret = (end) => ev(`(()=>{const e=${EDITABLE};e.focus();const r=document.createRange();r.selectNodeContents(e);r.collapse(${end ? 'false' : 'true'});const s=getSelection();s.removeAllRanges();s.addRange(r)})()`)
// Backspace in an empty block removes the block, so a block that is already empty is left alone
const clear = async () => {
  if (!(await ev(`${EDITABLE}.textContent.length`))) return
  await caret(true)
  await key('a', CTRL, 'KeyA')
  await key('Backspace', 0, 'Backspace')
  await sleep(100)
}
const leave = async () => { await ev(`${EDITABLE}.blur()`); await sleep(400) }
const text = () => ev(`${EDITABLE}.innerText.replace(/\\u200b/g,'')`)
const html = async () => clean((await ev(`${EDITABLE}?.innerHTML`)) ?? '')
// the marks that apply to a piece of text, read from what the browser draws (tags or classes: engines differ)
const marksAt = (frag) =>
  ev(`((frag)=>{const e=${EDITABLE};const w=document.createTreeWalker(e,NodeFilter.SHOW_TEXT);let n;while((n=w.nextNode())){if(n.textContent.includes(frag)){const m=new Set();for(let el=n.parentElement;el&&el!==e;el=el.parentElement){const c=getComputedStyle(el);if(parseInt(c.fontWeight)>=600)m.add('bold');if(c.fontStyle==='italic')m.add('italic');if(/underline/.test(c.textDecorationLine))m.add('underline');if(/line-through/.test(c.textDecorationLine))m.add('strike');if(el.tagName==='CODE'||/mono/.test(c.fontFamily))m.add('code');else if(c.backgroundColor!=='rgba(0, 0, 0, 0)')m.add('highlight');if(el.tagName==='A')m.add('link')}return [...m].sort().join(',')}}return null})(${JSON.stringify(frag)})`)
const links = async () => JSON.parse((await ev(`JSON.stringify([...(${EDITABLE}?.querySelectorAll('a') ?? [])].map((a) => (a.getAttribute('href') || '').replace(/\\/$/, '') + '|' + a.textContent))`)) ?? '[]')
const paste = (types) => ev(`(()=>{const dt=new DataTransfer();${Object.entries(types).map(([t, v]) => `dt.setData(${JSON.stringify(t)},${JSON.stringify(v)});`).join('')}const e=new ClipboardEvent('paste',{clipboardData:dt,bubbles:true,cancelable:true});${EDITABLE}.dispatchEvent(e)})()`)

let failures = 0
const notes = []
function check(engine, name, ok, detail = '') {
  if (!ok) failures++
  console.log(`  ${ok ? '✔' : '✘'} ${name}${ok ? '' : `  → ${detail}`}`)
}

await send('Emulation.setFocusEmulationEnabled', { enabled: true })
for (const engine of ENGINES) {
  console.log(`\n${engine}`)
  await send('Page.navigate', { url: `${BASE}/notes/p0?tela=painel` })
  await sleep(2500)

  await focusBlock(0)
  check(engine, 'o editor entra no lugar do texto ao focar', await ev(`!!${EDITABLE}`))

  // every mark on the whole block, then leaving shows them all, with the highlight color apart from the text
  await key('a', CTRL, 'KeyA')
  await key('b', CTRL); await key('i', CTRL); await key('u', CTRL); await key('S', CTRL | SHIFT, 'KeyS'); await key('H', CTRL | SHIFT, 'KeyH')
  await sleep(300)
  await leave()
  const view = clean(await ev(`${views(0)}.innerHTML`))
  check(engine, 'todas as marcas juntas aparecem ao sair (negrito, sublinhado, riscado, marca-texto, itálico)', /<strong><u><s><mark><em>[^<]+<\/em><\/mark><\/s><\/u><\/strong>/.test(view), view.slice(0, 160))
  const colors = await ev(`(()=>{const v=${views(0)};const u=getComputedStyle(v.querySelector('u'));return [u.textDecorationColor,getComputedStyle(v).color,getComputedStyle(v.querySelector('mark')).backgroundColor].join('|')})()`)
  const [deco, fg, bg] = colors.split('|')
  check(engine, 'sublinhado na cor do texto e marca-texto com fundo', deco === fg && bg !== 'rgba(0, 0, 0, 0)', colors)

  // toggling bold twice does not pile symbols up and keeps the other marks
  await focusBlock(0)
  await key('a', CTRL, 'KeyA'); await key('b', CTRL); await key('b', CTRL); await sleep(200)
  await leave()
  check(engine, 'negrito ligado e desligado não acumula símbolos', /<strong>/.test(clean(await ev(`${views(0)}.innerHTML`))) && !/\*\*/.test(await ev(`${views(0)}.textContent`)))

  // typing: closing the symbols formats at once, and what follows is plain
  await focusBlock(1)
  await caret(true)
  await typeText(' **oi** fim')
  await sleep(200)
  const [oi, fim] = [await marksAt('oi'), await marksAt('fim')]
  check(engine, 'fechar ** formata na hora e o texto seguinte sai sem negrito', oi === 'bold' && fim === '', `${oi} / ${fim}`)

  await clear()
  await typeText('hello**'); await caret(false); await typeText('**'); await sleep(200)
  check(engine, 'hello** e depois ** no começo vira negrito', (await marksAt('hello')) === 'bold' && !(await text()).includes('*'), await text())

  await clear()
  await typeText('uma ==nota== e ~~riscada~~ e `cod`'); await sleep(200)
  const got = [await marksAt('nota'), await marksAt('riscada'), await marksAt('cod')].join(' / ')
  check(engine, '==x==, ~~x~~ e `x` viram marca-texto, riscado e código', got === 'highlight / strike / code', got)

  // typography
  await clear()
  await typeText('a -> b <- c -- d ... e (c)'); await sleep(200)
  const typo = await text()
  check(engine, 'tipografia: -> <- -- ... (c) viram → ← — … ©', typo.trim() === 'a → b ← c — d … e ©', JSON.stringify(typo))
  await key('Backspace', 0, 'Backspace'); await sleep(100)
  const afterBs = await text()
  notes.push([engine, 'Backspace logo depois de uma regra de tipografia', afterBs.trim().endsWith('(c)') ? 'devolve os caracteres digitados' : `apaga só o caractere (${JSON.stringify(afterBs.slice(-6))})`])

  // autolink
  await clear()
  if (process.env.DEBUG) for (const part of ['veja https://exemplo.com', ' ', 'agora e readme.md', ' também ']) { await typeText(part); await sleep(150); console.log('   ·', JSON.stringify(part), 'editor:', await ev(`!!${EDITABLE}`), 'foco:', await ev(`document.activeElement?.tagName+'.'+(document.activeElement?.getAttribute('role')||'')`)) }
  else { await typeText('veja https://exemplo.com agora e readme.md também '); await sleep(200) }
  const linked = await links()
  check(engine, 'URL com https:// digitada vira link, e readme.md não', linked.length === 1 && linked[0] === 'https://exemplo.com|https://exemplo.com', JSON.stringify(linked))
  await leave()
  check(engine, 'o link volta a ser lido ao sair (texto com [..](..))', (await ev(`${views(1)}.querySelectorAll('a').length`)) === 1)

  // paste
  await focusBlock(1)
  await clear()
  await typeText('um texto aqui')
  await ev(`(()=>{const e=${EDITABLE};const t=[...e.querySelectorAll('*')].find(n=>n.firstChild&&n.firstChild.nodeType===3)||e;const r=document.createRange();r.setStart(t.firstChild,3);r.setEnd(t.firstChild,8);const s=getSelection();s.removeAllRanges();s.addRange(r)})()`)
  await paste({ 'text/plain': 'https://exemplo.com' })
  await sleep(200)
  const pasted = await links()
  check(engine, 'colar um endereço sobre palavras selecionadas faz o link', pasted.length === 1 && pasted[0] === 'https://exemplo.com|texto', JSON.stringify(pasted))

  await clear()
  await paste({ 'text/plain': 'linha um\nlinha dois', 'text/html': '<p><b>linha</b> um</p><p>linha dois</p><ul><li>item</li></ul><script>alert(1)</script>' })
  await sleep(300)
  const flat = await text()
  check(engine, 'colar vários parágrafos vira um bloco com quebras, só com marcas aceitas', /linha um/.test(flat) && /linha dois/.test(flat) && !/alert/.test(flat) && (await ev(`document.querySelectorAll('[data-block-id]').length`)) >= 2, JSON.stringify(flat))

  // limit
  await clear()
  if (process.env.DEBUG) await ev(`window.__errs=[];const o=console.error;console.error=(...a)=>{__errs.push(a.map(String).join(' ').slice(0,300));o(...a)};document.addEventListener('focusout',(e)=>__errs.push('focusout '+e.target.tagName+' '+String(new Error().stack).split('\\n').slice(2,9).join(' << ')),true);addEventListener('error',(e)=>__errs.push(String(e.error?.stack).split('\\n').slice(0,14).join(' << ')))`)
  await paste({ 'text/plain': 'x'.repeat(25000) })
  await sleep(500)
  if (process.env.DEBUG) console.log('   errs:', await ev(`JSON.stringify(window.__errs)`), 'editor:', await ev(`!!${EDITABLE}`))
  const len = await ev(`${EDITABLE}?.textContent.length`)
  check(engine, 'o limite de 20.000 caracteres vale ao colar texto enorme', typeof len === 'number' && len <= 20000 && (await ev(`!!${EDITABLE}`)), String(len))

  // undo
  await clear()
  await typeText('abc'); if (process.env.DEBUG) console.log('   abc typed:', await marksAt('abc'), JSON.stringify(await html()).slice(0, 200)); await key('a', CTRL, 'KeyA'); await key('b', CTRL); await key('z', CTRL); await sleep(200)
  check(engine, 'Ctrl+Z desfaz o negrito', (await marksAt('abc')) === '', await marksAt('abc'))

  // keyboard: Enter splits, Backspace in an empty block removes it
  await clear()
  await typeText('um dois'); await ev(`(()=>{const e=${EDITABLE};const t=e.querySelector('p')||e;const n=t.firstChild;const r=document.createRange();r.setStart(n,2);r.setEnd(n,2);const s=getSelection();s.removeAllRanges();s.addRange(r)})()`)
  const before = await ev(`document.querySelectorAll('[data-block-id]').length`)
  await key('Enter', 0, 'Enter'); await sleep(700)
  check(engine, 'Enter parte o bloco e leva o cursor ao novo', (await ev(`document.querySelectorAll('[data-block-id]').length`)) === before + 1 && !!(await ev(`!!${EDITABLE}`)))

  // block shortcuts and lists, on a page with a single paragraph
  await send('Page.navigate', { url: `${BASE}/notes/p5?tela=painel` })
  await sleep(2000)
  const labelOf = (n) => ev(`document.querySelectorAll('[data-block-id]')[${n}]?.getAttribute('aria-label') ?? ''`)
  await focusBlock(0)
  await clear()
  await typeText('## ')
  await sleep(500)
  check(engine, '"## " num parágrafo vazio vira título 2, com o cursor dentro', /^Título de seção/.test(await labelOf(0)) && (await ev(`!!${EDITABLE}`)), await labelOf(0))
  await key('Backspace', 0, 'Backspace'); await sleep(100)
  await ev(`${EDITABLE}.blur()`); await sleep(300)
  await send('Page.navigate', { url: `${BASE}/notes/p5?tela=painel` })
  await sleep(2000)
  await focusBlock(0)
  await clear()
  await typeText('- primeiro')
  await sleep(300)
  check(engine, '"- " vira item de lista e o texto fica nele', /^Item de lista/.test(await labelOf(0)) && (await text()).includes('primeiro'), `${await labelOf(0)} / ${await text()}`)
  await key('Enter', 0, 'Enter'); await sleep(600)
  await typeText('segundo')
  await key('Tab', 0, 'Tab'); await sleep(300)
  const pad = await ev(`document.querySelectorAll('[data-block-id]')[1].querySelector('[style*=padding-left]')?.style.paddingLeft ?? ''`)
  check(engine, 'Enter faz outro item e Tab o recua um nível', /^Item de lista/.test(await labelOf(1)) && pad === '1.75rem', `${await labelOf(1)} / ${pad}`)
  await key('Tab', 8, 'Tab'); await sleep(200)
  await key('Enter', 0, 'Enter'); await sleep(600)
  await key('Enter', 0, 'Enter'); await sleep(600)
  check(engine, 'Enter num item vazio termina a lista', /^Parágrafo/.test(await labelOf(2)), await labelOf(2))
  await send('Page.navigate', { url: `${BASE}/notes/p5?tela=painel` })
  await sleep(2000)
  await focusBlock(0)
  await clear()
  await typeText('1. um'); await key('Enter', 0, 'Enter'); await sleep(500); await typeText('dois'); await sleep(200)
  const nums = await ev(`[...document.querySelectorAll('[data-block-id] span.select-none')].map((s)=>s.textContent).join(',')`)
  check(engine, '"1. " cria lista numerada e conta 1., 2.', nums === '1.,2.', nums)

  // placeholder on an empty block
  await clear()
  const ph = await ev(`(()=>{const e=${EDITABLE};const p=e.querySelector('p.is-empty');return p?p.getAttribute('data-placeholder'):(document.querySelector('[data-rich] span[aria-hidden]')?.textContent??'')})()`)
  notes.push([engine, 'placeholder de bloco vazio', ph ? `aparece ("${ph}")` : 'não apareceu (bloco de parágrafo sem texto de ajuda)'])
}

console.log('\ndiferenças')
for (const n of notes) console.log(`  ${n[0].padEnd(12)} ${n[1]}: ${n[2]}`)
ws.close(); chrome.kill('SIGKILL'); server.close(); await sleep(200); rmSync(dir, { recursive: true, force: true })
console.log(failures ? `\n${failures} verificação(ões) falharam` : '\ntudo certo')
process.exit(failures ? 1 : 0)
