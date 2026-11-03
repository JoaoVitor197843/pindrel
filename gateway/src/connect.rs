//! The page a person opens to connect a device securely: a QR code with the pairing code for the app, the certificate
//! of the server's own CA with the steps to install it in a browser, and a live check of whether this device already
//! trusts the server. Plain HTML and CSS, one small script, nothing loaded from outside. Feature `selfcert`.
use std::net::IpAddr;

use qrcodegen::{QrCode, QrCodeEcc};

/// `pindrel://pair?host=ip:port&ca=<sha256>&n=<name>`: what the QR code carries and what can be typed by hand.
pub fn pairing_uri(host_port: &str, fingerprint: &str, name: &str) -> String {
    format!("pindrel://pair?host={host_port}&ca={fingerprint}&n={}", percent_encode(name))
}

fn percent_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

pub fn escape(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '&' => "&amp;".into(),
            '<' => "&lt;".into(),
            '>' => "&gt;".into(),
            '"' => "&quot;".into(),
            '\'' => "&#39;".into(),
            c => c.to_string(),
        })
        .collect()
}

/// The modules of the QR code (true = dark), without the quiet zone.
pub fn qr_modules(text: &str) -> Option<Vec<Vec<bool>>> {
    let qr = QrCode::encode_text(text, QrCodeEcc::Medium).ok()?;
    let n = qr.size();
    Some((0..n).map(|y| (0..n).map(|x| qr.get_module(x, y)).collect()).collect())
}

/// An SVG of the QR code on white with the 4-module quiet zone scanners need.
pub fn qr_svg(text: &str) -> String {
    let Some(m) = qr_modules(text) else { return String::new() };
    let n = m.len();
    let mut path = String::new();
    for (y, row) in m.iter().enumerate() {
        let mut x = 0;
        while x < n {
            if row[x] {
                let start = x;
                while x < n && row[x] {
                    x += 1;
                }
                path.push_str(&format!("M{},{}h{}v1h-{}z", start + 4, y + 4, x - start, x - start));
            } else {
                x += 1;
            }
        }
    }
    let size = n + 8;
    format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {size} {size}\" role=\"img\" aria-label=\"QR code de pareamento\" shape-rendering=\"crispEdges\"><rect width=\"{size}\" height=\"{size}\" fill=\"#fff\"/><path d=\"{path}\" fill=\"#000\"/></svg>"
    )
}

/// The short code people compare by eye (and that the log and the app show too): the first 48 bits of the fingerprint,
/// `3DC3-39F4-232A`. Faking one would take about 2^48 certificate authorities to be generated, so it is enough for a person
/// checking two screens; the QR code and the pairing text carry the whole fingerprint and are what the app checks.
pub fn confirmation(fingerprint: &str) -> String {
    let up = fingerprint.to_ascii_uppercase();
    (0..3).map(|i| up.get(i * 4..i * 4 + 4).unwrap_or("")).collect::<Vec<_>>().join("-")
}

/// 64 hex digits as eight blocks of eight, easier to compare by eye.
pub fn grouped(fingerprint: &str) -> String {
    fingerprint
        .as_bytes()
        .chunks(8)
        .map(|c| String::from_utf8_lossy(c).to_string())
        .collect::<Vec<_>>()
        .join(" ")
}

pub struct Page<'a> {
    pub server_name: &'a str,
    /// The name of the machine the server runs on, so whoever installed it recognises it.
    pub machine: &'a str,
    pub fingerprint: &'a str,
    /// Host (no port) the person used to reach this page, already checked; used for the link to the HTTPS site.
    pub host: &'a str,
    pub tls_port: u16,
    /// The address other devices of the LAN use, for the QR code.
    pub lan_ip: Option<IpAddr>,
    pub nonce: &'a str,
}

impl Page<'_> {
    pub fn pairing_host(&self) -> String {
        let h = self.lan_ip.map(|ip| ip.to_string()).unwrap_or_else(|| self.host.to_string());
        if h.contains(':') && !h.starts_with('[') {
            format!("[{h}]:{}", self.tls_port)
        } else {
            format!("{h}:{}", self.tls_port)
        }
    }

    pub fn code(&self) -> String {
        pairing_uri(&self.pairing_host(), self.fingerprint, self.server_name)
    }

    pub fn https_origin(&self) -> String {
        let h = if self.host.contains(':') && !self.host.starts_with('[') {
            format!("[{}]", self.host)
        } else {
            self.host.to_string()
        };
        format!("https://{h}:{}", self.tls_port)
    }

    pub fn csp(&self) -> String {
        format!(
            "default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-{}'; img-src data:; connect-src 'self' {}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
            self.nonce,
            self.https_origin()
        )
    }

    pub fn render(&self) -> String {
        let origin = self.https_origin();
        let shown_ip = self.lan_ip.map(|i| i.to_string()).unwrap_or_else(|| self.host.to_string());
        TEMPLATE
            .replace("@@NAME@@", &escape(self.server_name))
            .replace("@@MACHINE@@", &escape(self.machine))
            .replace("@@IP@@", &escape(&shown_ip))
            .replace("@@SVG@@", &qr_svg(&self.code()))
            .replace("@@CODE@@", &escape(&self.code()))
            .replace("@@SHORT@@", &escape(&confirmation(self.fingerprint)))
            .replace("@@FP@@", &escape(&grouped(self.fingerprint)))
            .replace("@@ORIGIN_ATTR@@", &escape(&origin))
            .replace("@@ORIGIN_JS@@", &origin.replace(['\\', '\''], ""))
            .replace("@@NONCE@@", self.nonce)
    }
}

const TEMPLATE: &str = r##"<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>Primeira conexão · @@NAME@@</title>
<style>
:root { --bg:#141412; --surface:#1e1e1b; --line:#2e2e2a; --field:#75716a; --fg:#eae6df; --muted:#9a968e; --accent:#4a5d44; --accent-line:#6b8e61; --accent-text:#8fb085; --cream:#f5f2eb; --on-cream:#141412; --warn:#cd7065; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 system-ui,"Segoe UI",Roboto,sans-serif; -webkit-font-smoothing:antialiased; }
main { max-width:720px; margin:0 auto; padding:28px 20px 56px; }
h1,h2 { font-family:serif; font-weight:600; line-height:1.2; margin:0; }
h1 { font-size:30px; } h2 { font-size:21px; margin-bottom:6px; }
.badge { font:11px/1 monospace; letter-spacing:1.2px; text-transform:uppercase; color:var(--muted); border:1px solid var(--field); border-radius:10px; padding:6px 10px; display:inline-block; margin-bottom:14px; }
p { margin:8px 0; } .muted { color:var(--muted); }
section, details.choice { background:var(--surface); border:1px solid var(--line); border-radius:20px; padding:22px; margin-top:18px; }
.local { display:flex; gap:10px; align-items:flex-start; border:1px solid var(--accent-line); background:rgba(74,93,68,.35); border-radius:14px; padding:12px 14px; margin-top:16px; }
.local svg { flex:none; margin-top:3px; color:var(--accent-text); }
#status { border-radius:14px; padding:14px 16px; border:1px solid var(--field); margin-top:14px; }
#status.ok { border-color:var(--accent-line); background:rgba(74,93,68,.45); }
#status.todo { border-color:var(--warn); }
.facts { list-style:none; padding:0; margin:10px 0 0; }
.facts li { padding-left:26px; position:relative; margin:6px 0; }
.facts li::before { position:absolute; left:0; font-weight:700; }
.facts .no::before { content:"✕"; color:var(--accent-text); }
.facts .yes::before { content:"•"; color:var(--muted); }
details.choice > summary { list-style:none; cursor:pointer; font-family:serif; font-size:21px; font-weight:600; display:flex; justify-content:space-between; align-items:center; gap:12px; }
details.choice > summary::-webkit-details-marker { display:none; }
details.choice > summary::after { content:"+"; font:22px monospace; color:var(--muted); }
details.choice[open] > summary::after { content:"−"; }
.qr { background:#fff; border-radius:14px; padding:6px; width:min(260px,100%); margin:14px 0; }
.qr svg { display:block; width:100%; height:auto; }
code, .mono { font-family:monospace; }
.code { background:var(--bg); border:1px solid var(--field); border-radius:10px; padding:12px; font-size:13px; font-family:monospace; overflow-wrap:anywhere; word-break:break-all; }
.short { font:600 26px/1.2 monospace; letter-spacing:3px; margin:8px 0; }
.btn { display:inline-block; text-decoration:none; background:var(--cream); color:var(--on-cream); font-weight:600; border-radius:10px; padding:13px 18px; border:0; font-size:16px; cursor:pointer; }
.btn.ghost { background:transparent; color:var(--fg); border:1px solid var(--field); font:12px monospace; letter-spacing:.6px; text-transform:uppercase; }
.btn[aria-disabled="true"] { opacity:.55; pointer-events:none; }
.row { display:flex; gap:10px; flex-wrap:wrap; margin-top:12px; }
details.os { border-top:1px solid var(--line); padding:12px 0 0; margin-top:12px; }
details.os > summary { cursor:pointer; font-weight:600; padding:4px 0; }
ol { padding-left:20px; margin:8px 0; } li { margin:4px 0; }
a { color:var(--accent-text); }
:focus-visible { outline:2px solid var(--accent-line); outline-offset:2px; }
.sas { border:1px dashed var(--field); border-radius:14px; padding:14px 16px; margin:14px 0; }
.six { font:600 44px/1.1 monospace; letter-spacing:8px; text-align:center; margin:8px 0; }
.fp { font:14px monospace; word-spacing:6px; overflow-wrap:anywhere; }

/* Motion: everything below is switched off for people who asked their system for less movement. */
@keyframes rise { from { opacity:0; transform:translateY(14px); } to { opacity:1; transform:none; } }
@keyframes pop { from { opacity:0; transform:scale(.92); } to { opacity:1; transform:none; } }
@keyframes pulse { 0%,100% { box-shadow:0 0 0 0 rgba(143,176,133,.0); } 50% { box-shadow:0 0 0 6px rgba(143,176,133,.18); } }
@keyframes spin { to { transform:rotate(360deg); } }
@keyframes reveal { from { opacity:0; transform:translateY(-6px); } to { opacity:1; transform:none; } }
@media (prefers-reduced-motion: no-preference) {
  /* The badge and the title are never animated from transparent: a page whose first paint is invisible has no first contentful paint. */
  .local, #status, main > section, details.choice { animation:rise .55s cubic-bezier(.2,.7,.2,1) both; }
  .local { animation-delay:.08s; } #status { animation-delay:.16s; }
  main > section { animation-delay:.28s; } #web { animation-delay:.36s; } #app { animation-delay:.44s; } #why { animation-delay:.5s; }
  details.choice, .btn, #status { transition:border-color .25s, background-color .25s, transform .2s, opacity .2s; }
  details.choice:hover { border-color:var(--field); }
  details.choice > summary::after { transition:transform .3s; }
  details.choice[open] > summary::after { transform:rotate(180deg); }
  details.choice[open] > :not(summary) { animation:reveal .35s ease both; }
  .qr { animation:pop .45s .1s cubic-bezier(.2,.7,.2,1) both; }
  .btn:not([aria-disabled="true"]):hover { transform:translateY(-2px); }
  .btn:not([aria-disabled="true"]):active { transform:scale(.97); }
  #status.ok { animation:pulse 2.4s ease-in-out 2; }
  #status.wait::before { content:""; display:inline-block; width:12px; height:12px; margin-right:10px; vertical-align:-1px; border:2px solid var(--muted); border-top-color:transparent; border-radius:50%; animation:spin .8s linear infinite; }
  .local svg { animation:pop .5s .3s both; }
}
</style>
</head>
<body>
<main>
<span class="badge">Primeira conexão</span>
<h1>Conectar a @@NAME@@</h1>

<div class="local" role="note">
<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/></svg>
<div><strong>Este é um servidor da sua rede.</strong> Você está falando com o computador <code>@@MACHINE@@</code> (<code>@@IP@@</code>), dentro da sua rede local. Esta página só aparece para aparelhos da própria rede: de fora, ela nem existe.</div>
</div>

<div id="status" class="wait" role="status" aria-live="polite">Verificando se este aparelho já confia neste servidor…</div>

<section aria-labelledby="what">
<h2 id="what">O que esta página faz, e o que não faz</h2>
<p>Ela só mostra a chave de segurança deste servidor e ensina a confiar nela, para a conexão ficar criptografada.</p>
<ul class="facts">
<li class="no">Não pede senha, e-mail nem nenhum dado seu.</li>
<li class="no">Não envia nada para a internet, e não carrega nada de fora: tudo vem deste servidor.</li>
<li class="no">Não instala nada sozinha: você escolhe se e quando instalar.</li>
</ul>
</section>

<details class="choice" id="web" name="conexao">
<summary>Vou usar no navegador</summary>
<p style="margin-top:12px">Para abrir o Pindrel pelo navegador sem avisos, este aparelho precisa confiar uma vez na chave de segurança do servidor.</p>
<ol>
<li><strong>Baixe a chave.</strong>
<div class="row"><a class="btn" href="/server/ca.crt" download="pindrel-ca.crt">Baixar a chave de segurança</a></div></li>
<li><strong>Confira o código.</strong> Ele deve ser igual ao que o gateway mostra no registro (log) ao iniciar e ao que o app mostra:
<div class="short" id="short">@@SHORT@@</div>
<details class="os"><summary>Ver a impressão digital completa (SHA-256)</summary><p class="fp">@@FP@@</p></details></li>
<li><strong>Instale no seu sistema.</strong> Escolha o seu abaixo.</li>
<li><strong>Abra o Pindrel com HTTPS.</strong>
<div class="row"><a class="btn ghost" id="open" href="@@ORIGIN_ATTR@@/" aria-disabled="true">Abrir o Pindrel com HTTPS</a></div></li>
</ol>
<details class="os"><summary>Android</summary><ol><li>Baixe a chave.</li><li>Abra <em>Configurações</em> e procure por <em>Instalar certificado</em> (costuma ficar em Segurança e privacidade, Mais configurações de segurança, Criptografia e credenciais).</li><li>Escolha <em>Certificado de CA</em>, confirme o aviso e selecione o arquivo baixado.</li><li>No Chrome o aviso some. Outros apps ignoram essas chaves, por isso o app Pindrel usa o pareamento.</li></ol></details>
<details class="os"><summary>iPhone e iPad</summary><ol><li>Abra esta página no Safari e toque em <em>Baixar a chave</em>, depois em <em>Permitir</em>.</li><li>Em <em>Ajustes</em>, toque em <em>Perfil baixado</em> e em <em>Instalar</em>.</li><li>Em <em>Ajustes, Geral, Sobre, Ajustes de confiança de certificado</em>, ative a confiança total para a chave do Pindrel.</li></ol></details>
<details class="os"><summary>Windows</summary><ol><li>Baixe a chave e dê dois cliques no arquivo.</li><li>Escolha <em>Instalar Certificado</em>, <em>Usuário Atual</em>, depois <em>Colocar todos os certificados no repositório a seguir</em>.</li><li>Selecione <em>Autoridades de Certificação Raiz Confiáveis</em> e conclua. Reinicie o navegador.</li></ol></details>
<details class="os"><summary>macOS</summary><ol><li>Baixe a chave e dê dois cliques para abrir o <em>Acesso às Chaves</em>.</li><li>Abra o certificado, expanda <em>Confiança</em> e escolha <em>Sempre Confiar</em>.</li></ol></details>
<details class="os"><summary>Linux, Chrome e Firefox</summary><ol><li>Chrome: <em>Configurações, Privacidade e segurança, Segurança, Gerenciar certificados, Autoridades, Importar</em>.</li><li>Firefox: <em>Configurações, Privacidade e segurança, Certificados, Ver certificados, Autoridades, Importar</em>, marcando a confiança para sites.</li><li>No sistema: copie o arquivo para <code>/usr/local/share/ca-certificates/</code> e rode <code>sudo update-ca-certificates</code>.</li></ol></details>
<p class="muted" style="margin-top:14px">Os nomes dos menus mudam entre versões e fabricantes.</p>
</details>

<details class="choice" id="app" name="conexao">
<summary>Tenho o app Pindrel</summary>
<p style="margin-top:12px">Para parear o app, toque em <strong>Gerar código de pareamento</strong>. Aparece um <strong>código de 4 dígitos</strong>: digite-o no app (ao tocar neste servidor, ou em <em>Adicionar servidor</em>). Depois o app e esta página mostram <strong>6 números</strong>: se forem iguais, toque em <em>São iguais</em> no app. Nada precisa ser instalado no sistema.</p>
<div id="room" class="sas" aria-live="polite">
<div class="row" id="room-start"><button class="btn" id="room-open" type="button">Gerar código de pareamento</button></div>
<div id="room-on" hidden>
<p class="muted">Digite no app o <strong>código da sala</strong>:</p>
<div class="six" id="room-code"></div>
<p class="muted" id="room-state">Esperando o app…</p>
<div id="room-digits-box" hidden>
<p class="muted">Confira com o app (aparelho <span class="mono" id="room-phone"></span>):</p>
<div class="six" id="room-digits"></div>
<p class="muted">Se os números forem diferentes, <strong>não confirme</strong>: toque em <em>Cancelar</em> no app.</p>
</div>
<p class="muted">A sala fecha em <span id="room-left"></span> s. Os números são só desta sala: outras pessoas pareando ao mesmo tempo não os veem, nem você os delas.</p>
<div class="row"><button class="btn ghost" id="room-new" type="button">Gerar outro código</button><button class="btn ghost" id="room-close" type="button">Fechar</button></div>
</div>
<p class="muted" id="room-err" hidden></p>
</div>
<details class="os"><summary>Sem uma tela para olhar? Use o código mestre</summary>
<p>Quem tem acesso ao computador do servidor encontra, no registro (log) do gateway, uma linha <code>PAIR: código mestre XXXX-XXXX-XXXX-XXXX</code>. No app, escolha <em>Tenho o código mestre</em> e digite-o: o app e o servidor provam um ao outro que o conhecem, sem enviá-lo pela rede, e não é preciso comparar números. O código vale <strong>uma vez</strong> (e por até 24 h): depois de usado, um novo aparece no registro. Esta página nunca o mostra.</p>
</details>
<p class="muted">Por que números? O app confere, com você, que está falando com este servidor e não com outro aparelho da rede que se passa por ele. Os números mudam a cada tentativa e só valem por um minuto, então não dá para decorar nem preparar um falso.</p>
<details class="os"><summary>Prefiro ler um QR code</summary>
<p>O código abaixo contém só o endereço do servidor e a impressão digital da chave dele. Não contém senha.</p>
<div class="qr">@@SVG@@</div>
<div class="code" id="code">@@CODE@@</div>
<p class="muted">Código de conferência no app: <span class="mono">@@SHORT@@</span></p>
<div class="row"><button class="btn ghost" id="copy" type="button">Copiar código</button></div>
</details>
</details>

<section aria-labelledby="why">
<h2 id="why">Por que isso é seguro?</h2>
<p>A chave foi criada por este servidor e <strong>só vale para endereços e nomes da sua rede</strong> (como <code>localhost</code>, <code>.lan</code> e o nome desta máquina). Ela não consegue se passar por sites da internet. Instale somente se você reconhece este servidor.</p>
<p>Sem esta etapa, o Pindrel continua acessível por esta página, mas a senha e as notas não devem trafegar sem criptografia: por isso o endereço sem HTTPS só mostra esta tela.</p>
</section>
</main>
<script nonce="@@NONCE@@">
(function () {
  var s = document.getElementById('status'), open = document.getElementById('open');
  var stay = /[?&#]ficar\b/.test(location.search + location.hash);
  if (location.hash === '#app') document.getElementById('app').open = true;
  // Older browsers ignore the name attribute that makes the two choices exclusive: do it by hand.
  var choices = document.querySelectorAll('details.choice');
  [].forEach.call(choices, function (d) { d.addEventListener('toggle', function () {
    if (d.open) [].forEach.call(choices, function (o) { if (o !== d) o.open = false; });
  }); });
  // Without a limit a blocked port (a firewall that drops packets instead of refusing) leaves the browser waiting for minutes.
  var ac = typeof AbortController === 'function' ? new AbortController() : null;
  var timer = setTimeout(function () { if (ac) ac.abort(); }, 4000);
  fetch('@@ORIGIN_JS@@/server/info/', { mode: 'no-cors', cache: 'no-store', signal: ac ? ac.signal : undefined }).then(function () {
    clearTimeout(timer);
    open.removeAttribute('aria-disabled'); open.className = 'btn';
    s.className = 'ok';
    var trusted = 'Este aparelho já confia neste servidor. Você pode abrir o Pindrel com HTTPS.';
    if (stay) { s.textContent = trusted; return; }
    s.textContent = 'Este aparelho já confia neste servidor: abrindo o Pindrel com HTTPS…';
    var go = setTimeout(function () { location.href = open.href; }, 1800);
    var link = document.createElement('a'); link.href = '#'; link.textContent = ' Ficar nesta página';
    link.addEventListener('click', function (e) { e.preventDefault(); clearTimeout(go); s.textContent = trusted; });
    s.appendChild(link);
  }).catch(function () {
    clearTimeout(timer);
    s.className = 'todo'; s.textContent = 'Este aparelho ainda não confia neste servidor (ou não consegue chegar à porta segura). Siga os passos abaixo, ou use o app.';
  });

  // The room: a 4-digit code for the app, and the six digits of the app's session, shown only here (the token never leaves
  // this page's memory and travels in a header, not a URL).
  var app = document.getElementById('app'), token = null, poller = null, wait = false;
  function el(id) { return document.getElementById(id); }
  function view(on, err) { el('room-start').hidden = on; el('room-on').hidden = !on; el('room-err').hidden = !err; el('room-err').textContent = err || ''; }
  function stopPolling() { if (poller) { clearInterval(poller); poller = null; } }
  function leave() {
    if (token) { try { fetch('/server/pair/room/close', { method: 'POST', headers: { 'x-pindrel-room': token }, keepalive: true }).catch(function () {}); } catch (e) {} }
    token = null; stopPolling();
  }
  function lines(t) { var v = {}; String(t).split('\n').forEach(function (l) { var i = l.indexOf('='); if (i > 0) v[l.slice(0, i)] = l.slice(i + 1).trim(); }); return v; }
  function look() {
    if (!token || wait || document.hidden) return; wait = true;
    var ac = typeof AbortController === 'function' ? new AbortController() : null;
    var to = setTimeout(function () { if (ac) ac.abort(); }, 3000);
    fetch('/server/pair/room', { cache: 'no-store', headers: { 'x-pindrel-room': token }, signal: ac ? ac.signal : undefined }).then(function (r) {
      if (r.status === 404) { token = null; stopPolling(); view(false, 'Este código venceu, foi usado ou foi fechado. Gere outro.'); return; }
      return r.text().then(function (t) {
        var v = lines(t), m = /^(\d{6}),(\d{1,2})$/.exec(v.d || '');
        el('room-left').textContent = String(Math.min(180, parseInt(v.left, 10) || 0));
        if (m) {
          el('room-digits').textContent = m[1].slice(0, 3) + ' ' + m[1].slice(3);
          el('room-phone').textContent = (v.phone || '').replace(/[^0-9a-fA-F:.]/g, '').slice(0, 45);
          el('room-digits-box').hidden = false; el('room-state').textContent = 'O app entrou na sala.';
        } else {
          el('room-digits-box').hidden = true;
          el('room-state').textContent = v.phone ? 'O app entrou. Gerando os números…' : 'Esperando o app…';
        }
      });
    }).catch(function () {}).then(function () { clearTimeout(to); wait = false; });
  }
  function openRoom() {
    leave();
    fetch('/server/pair/room', { method: 'POST', cache: 'no-store' }).then(function (r) {
      if (r.status === 429) { view(false, 'Há pessoas demais pareando agora. Tente de novo em um minuto.'); return; }
      if (r.status !== 200) { view(false, 'Não foi possível abrir a sala agora.'); return; }
      return r.text().then(function (t) {
        var v = lines(t);
        if (!/^\d{4}$/.test(v.code || '') || !/^[0-9a-f]{32}$/.test(v.token || '')) { view(false, 'O servidor respondeu algo inesperado.'); return; }
        token = v.token; el('room-code').textContent = v.code; el('room-digits-box').hidden = true; el('room-state').textContent = 'Esperando o app…';
        el('room-left').textContent = String(Math.min(180, parseInt(v.ttl, 10) || 180));
        view(true); stopPolling(); poller = setInterval(look, 2000);
      });
    }).catch(function () { view(false, 'Não foi possível falar com o servidor.'); });
  }
  el('room-open').addEventListener('click', openRoom);
  el('room-new').addEventListener('click', openRoom);
  el('room-close').addEventListener('click', function () { leave(); view(false); });
  window.addEventListener('pagehide', leave);
  var b = document.getElementById('copy');
  b.addEventListener('click', function () {
    var t = document.getElementById('code').textContent;
    var done = function () { b.textContent = 'Copiado'; };
    if (navigator.clipboard) { navigator.clipboard.writeText(t).then(done); return; }
    var a = document.createElement('textarea'); a.value = t; document.body.appendChild(a); a.select();
    try { document.execCommand('copy'); done(); } catch (e) {} document.body.removeChild(a);
  });
})();
</script>
</body>
</html>
"##;
