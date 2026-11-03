//! The plain-HTTP port while TLS is on, the connection page and its QR code, the scheme the replicas are told and the
//! WebSocket origin check.
#![cfg(feature = "selfcert")]
mod common;

use std::{path::PathBuf, time::Duration};

use common::*;
use pindrel_gateway::{
    config::{HttpMode, TlsConfig},
    connect,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time,
};

fn auto(port: u16, dir: &std::path::Path) -> TlsConfig {
    TlsConfig {
        port,
        cert: PathBuf::new(),
        key: PathBuf::new(),
        auto_dir: Some(dir.to_path_buf()),
        extra_sans: Vec::new(),
        refresh: Duration::ZERO,
    }
}

struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!("pindrel-connect-{}-{}", std::process::id(), free_port()));
        std::fs::create_dir_all(&p).unwrap();
        Dir(p)
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// A request written by hand (so the Host header is whatever the test says); returns the head and the body.
async fn raw(addr: std::net::SocketAddr, request: &str) -> (String, String) {
    let mut s = TcpStream::connect(addr).await.unwrap();
    s.write_all(request.as_bytes()).await.unwrap();
    let mut out = Vec::new();
    let _ = time::timeout(Duration::from_secs(3), s.read_to_end(&mut out)).await;
    let text = String::from_utf8_lossy(&out).to_string();
    match text.split_once("\r\n\r\n") {
        Some((h, b)) => (h.to_string(), b.to_string()),
        None => (text, String::new()),
    }
}

fn req(method: &str, path: &str, host: &str, extra: &str) -> String {
    format!("{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n{extra}\r\n")
}

async fn started(tweak: impl FnOnce(&mut pindrel_gateway::config::Config)) -> (Backend, pindrel_gateway::server::Running, Dir, u16) {
    let (a, dir, port) = (Backend::start("a").await, Dir::new(), free_port());
    let d = dir.0.clone();
    let gw = gateway_with(&[&a], move |c| {
        c.tls = Some(auto(port, &d));
        tweak(c);
    })
    .await;
    (a, gw, dir, port)
}

#[tokio::test]
async fn the_plain_port_only_answers_the_bootstrap_routes_and_sends_the_rest_to_https() {
    let (_a, gw, _d, tls) = started(|_| {}).await;
    // public and read-only: allowed
    for path in ["/server/info/", "/server/ca.pem", "/server/ca.crt", "/server/connect/"] {
        let (head, _) = raw(gw.addr, &req("GET", path, "casa.lan:8080", "")).await;
        assert!(head.starts_with("HTTP/1.1 200"), "{path}: {head}");
    }
    // anything else is sent to the secure port, keeping the path and the query
    let (head, _) = raw(gw.addr, &req("GET", "/assets/app.js?v=3", "casa.lan:8080", "")).await;
    assert!(head.starts_with("HTTP/1.1 308"), "{head}");
    assert!(
        head.to_lowercase()
            .contains(&format!("location: https://casa.lan:{tls}/assets/app.js?v=3")),
        "{head}"
    );
    // what could carry a password or a note is refused, not redirected
    for method in ["POST", "PUT", "DELETE", "PATCH"] {
        let (head, body) = raw(gw.addr, &req(method, "/auth/login/", "casa.lan", "Content-Length: 0\r\n")).await;
        assert!(head.starts_with("HTTP/1.1 426"), "{method}: {head}");
        assert!(body.contains("https_required"), "{body}");
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn opening_the_address_in_a_browser_shows_how_to_connect_instead_of_a_certificate_error() {
    let (_a, gw, _d, tls) = started(|_| {}).await;
    let (head, body) = raw(
        gw.addr,
        &req("GET", "/", "192.168.1.5:8080", "Accept: text/html,application/xhtml+xml\r\n"),
    )
    .await;
    assert!(head.starts_with("HTTP/1.1 200"), "{head}");
    assert!(
        body.contains("Conectar a Pindrel") && body.contains("<svg") && body.contains("pindrel://pair?host="),
        "{body:.300}"
    );
    assert!(body.contains(&format!("https://192.168.1.5:{tls}")));
    // not a browser (no Accept: text/html): the ordinary redirect
    let (head, _) = raw(gw.addr, &req("GET", "/", "casa.lan", "")).await;
    assert!(head.starts_with("HTTP/1.1 308"), "{head}");
    gw.shutdown().await;
}

#[tokio::test]
async fn the_page_is_strict_about_what_it_loads_and_never_trusts_the_host_header() {
    let (_a, gw, _d, _tls) = started(|_| {}).await;
    let (head, body) = raw(gw.addr, &req("GET", "/server/connect/", "casa.lan", "")).await;
    let lower = head.to_lowercase();
    let csp = lower.lines().find(|l| l.starts_with("content-security-policy:")).expect("CSP");
    assert!(
        csp.contains("default-src 'none'") && csp.contains("frame-ancestors 'none'") && csp.contains("script-src 'nonce-"),
        "{csp}"
    );
    assert!(!csp.contains("unsafe-eval") && !csp.contains("script-src 'unsafe-inline'"));
    assert!(
        lower.contains("cache-control: no-store")
            && lower.contains("x-frame-options: deny")
            && lower.contains("referrer-policy: no-referrer")
    );
    // the nonce in the header is the one on the script
    let nonce = csp.split("'nonce-").nth(1).unwrap().split('\'').next().unwrap();
    assert!(body.contains(&format!("<script nonce=\"{nonce}\">")));
    assert!(
        !body.contains("http://") || body.matches("http://").count() == body.matches("http://www.w3.org/2000/svg").count(),
        "an outside address is loaded"
    );
    // each answer has its own nonce
    let (head2, _) = raw(gw.addr, &req("GET", "/server/connect/", "casa.lan", "")).await;
    assert_ne!(
        head.to_lowercase().split("'nonce-").nth(1),
        head2.to_lowercase().split("'nonce-").nth(1)
    );
    // hostile Host headers: refused, or at least never reflected as markup
    for host in [
        "<script>alert(1)</script>",
        "a.b/../../x",
        "evil.com\"onload=\"x",
        "",
        "a b",
        "[::1",
    ] {
        let (head, body) = raw(gw.addr, &req("GET", "/other", host, "")).await;
        assert!(!head.to_lowercase().contains("<script"), "{host}: {head}");
        assert!(!body.contains("<script>alert"), "{host}");
        assert!(
            head.starts_with("HTTP/1.1 400") || head.starts_with("HTTP/1.1 308"),
            "{host}: {head}"
        );
    }
    let (_, body) = raw(gw.addr, &req("GET", "/server/connect/", "<img src=x onerror=alert(1)>", "")).await;
    assert!(!body.contains("<img src=x"), "the host was written into the page as markup");
    gw.shutdown().await;
}

#[tokio::test]
async fn the_qr_code_decodes_to_exactly_the_pairing_code_of_the_page() {
    let (_a, gw, _d, tls) = started(|c| c.server_name = "Casa & <Sítio>".into()).await;
    let (_, body) = raw(gw.addr, &req("GET", "/server/connect/", "192.168.1.5", "")).await;
    // the fingerprint on the page is the one of the CA that is served
    let (_, pem) = raw(gw.addr, &req("GET", "/server/ca.pem", "x", "")).await;
    let fp = pindrel_gateway::selfcert::fingerprint_of_pem(&pem).unwrap();
    assert!(body.contains(&connect::grouped(&fp)));
    // read the QR back: it is the code shown as text
    let uri = connect::pairing_uri(
        &format!(
            "{}:{tls}",
            pindrel_gateway::discovery::lan_ip()
                .map(|i| i.to_string())
                .unwrap_or("192.168.1.5".into())
        ),
        &fp,
        "Casa & <Sítio>",
    );
    let m = connect::qr_modules(&uri).unwrap();
    let n = m.len();
    let scale = 4;
    let side = (n + 8) * scale;
    let mut img = rqrr::PreparedImage::prepare_from_greyscale(side, side, |x, y| {
        let (mx, my) = (x / scale, y / scale);
        if mx >= 4 && my >= 4 && mx < n + 4 && my < n + 4 && m[my - 4][mx - 4] {
            0
        } else {
            255
        }
    });
    let grids = img.detect_grids();
    assert_eq!(grids.len(), 1);
    let (_, content) = grids[0].decode().unwrap();
    assert_eq!(content, uri);
    assert!(
        content.starts_with("pindrel://pair?host=") && content.contains(&format!("ca={fp}")) && content.contains("n=Casa%20%26%20%3CS"),
        "{content}"
    );
    // and the name with markup is shown escaped
    assert!(body.contains("Casa &amp; &lt;Sítio&gt;") && !body.contains("<Sítio>"));
    gw.shutdown().await;
}

#[tokio::test]
async fn full_mode_and_a_declared_proxy_keep_the_plain_port_as_it_was() {
    let (_a, gw, _d, _tls) = started(|c| c.http_mode = HttpMode::Full).await;
    let (head, _) = raw(gw.addr, &req("GET", "/x", "casa.lan", "")).await;
    assert!(head.starts_with("HTTP/1.1 200"), "{head}");
    gw.shutdown().await;
    // behind a tunnel that ended the TLS (TRUSTED_PROXIES), the plain connection is the secure one
    let (_a, gw, _d, _tls) = started(|c| {
        c.client_ip =
            pindrel_gateway::clientip::ClientIp::new(pindrel_gateway::clientip::parse_trusted("127.0.0.1").unwrap(), "x-forwarded-for")
                .unwrap();
    })
    .await;
    let (head, _) = raw(
        gw.addr,
        &req(
            "POST",
            "/auth/login/",
            "casa.lan",
            "Content-Length: 0\r\nX-Forwarded-For: 9.9.9.9\r\n",
        ),
    )
    .await;
    assert!(head.starts_with("HTTP/1.1 200"), "{head}");
    gw.shutdown().await;
}

#[tokio::test]
async fn replicas_are_told_the_scheme_and_a_client_cannot_choose_it() {
    // without TLS configured at all: plain, and a forged header is replaced
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let r = send(gw.addr, "GET", "/x", &[("x-forwarded-proto", "https")], "").await;
    assert_eq!(r.header("x-seen-proto"), "http", "a client made itself look secure");
    gw.shutdown().await;
    // a declared proxy that ended the TLS is believed
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| {
        c.client_ip =
            pindrel_gateway::clientip::ClientIp::new(pindrel_gateway::clientip::parse_trusted("127.0.0.1").unwrap(), "x-forwarded-for")
                .unwrap();
    })
    .await;
    assert_eq!(
        send(gw.addr, "GET", "/x", &[("x-forwarded-proto", "https")], "")
            .await
            .header("x-seen-proto"),
        "https"
    );
    assert_eq!(
        send(gw.addr, "GET", "/x", &[("x-forwarded-proto", "javascript")], "")
            .await
            .header("x-seen-proto"),
        "http"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn info_tells_where_the_secure_side_is_and_exposes_it_to_pages() {
    let (_a, gw, _d, tls) = started(|_| {}).await;
    let r = get(gw.addr, "/server/info/").await;
    assert_eq!(r.header("x-pindrel-tls"), tls.to_string());
    assert!(r.header("access-control-expose-headers").contains("x-pindrel-tls"));
    assert_eq!(r.header("x-pindrel-ca").len(), 64);
    gw.shutdown().await;
}

fn ws(origin: Option<&str>, host: &str) -> String {
    let o = origin.map(|o| format!("Origin: {o}\r\n")).unwrap_or_default();
    format!("GET /ws HTTP/1.1\r\nHost: {host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n{o}\r\n")
}

#[tokio::test]
async fn a_page_from_another_site_cannot_open_a_websocket_but_the_own_page_and_native_clients_can() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.ws_allowed_origins = vec!["https://painel.casa.lan".into()]).await;
    let status = |h: &str| h.lines().next().unwrap_or("").to_string();
    let try_ws = |o: Option<&'static str>, host: &'static str| {
        let addr = gw.addr;
        async move {
            let mut s = TcpStream::connect(addr).await.unwrap();
            s.write_all(ws(o, host).as_bytes()).await.unwrap();
            let mut buf = vec![0u8; 512];
            let n = time::timeout(Duration::from_secs(2), s.read(&mut buf)).await.unwrap().unwrap();
            String::from_utf8_lossy(&buf[..n]).to_string()
        }
    };
    assert!(
        status(&try_ws(None, "casa.lan").await).contains("101"),
        "a native client has no Origin"
    );
    assert!(
        status(&try_ws(Some("https://casa.lan"), "casa.lan:8443").await).contains("101"),
        "its own page"
    );
    assert!(status(&try_ws(Some("http://casa.lan:8080"), "casa.lan:8080").await).contains("101"));
    assert!(
        status(&try_ws(Some("https://painel.casa.lan"), "casa.lan").await).contains("101"),
        "listed"
    );
    for bad in [
        "https://evil.example",
        "null",
        "http://casa.lan.evil.example",
        "file://",
        "",
        "https://",
    ] {
        let r = try_ws(Some(bad), "casa.lan").await;
        assert!(status(&r).contains("403"), "{bad:?}: {r}");
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn a_flood_of_hostile_plain_requests_is_answered_and_the_gateway_stays_up() {
    let (_a, gw, _d, _tls) = started(|c| {
        c.rate_limit = false;
        c.max_connections_per_ip = 1000;
    })
    .await;
    let mut tasks = Vec::new();
    for i in 0..200 {
        let addr = gw.addr;
        tasks.push(tokio::spawn(async move {
            let r = match i % 5 {
                0 => req("GET", "/server/connect/", "casa.lan", ""),
                1 => req("POST", "/auth/login/", "casa.lan", "Content-Length: 0\r\n"),
                2 => req("GET", &format!("/{}", "a".repeat(4000)), "casa.lan", ""),
                3 => req("GET", "/", &"h".repeat(300), "Accept: text/html\r\n"),
                _ => ws(Some("https://evil.example"), "casa.lan"),
            };
            raw(addr, &r).await.0.starts_with("HTTP/1.1")
        }));
    }
    for t in tasks {
        assert!(t.await.unwrap());
    }
    assert!(raw(gw.addr, &req("GET", "/server/info/", "casa.lan", ""))
        .await
        .0
        .starts_with("HTTP/1.1 200"));
    gw.shutdown().await;
}

#[tokio::test]
async fn the_page_and_the_ca_exist_only_for_the_local_network_never_through_a_tunnel() {
    // a declared proxy in front (a tunnel): the peer is the proxy, and the person behind it is on the internet
    let (_a, gw, _d, _tls) = started(|c| {
        c.client_ip =
            pindrel_gateway::clientip::ClientIp::new(pindrel_gateway::clientip::parse_trusted("127.0.0.1").unwrap(), "x-forwarded-for")
                .unwrap();
    })
    .await;
    for path in ["/server/connect/", "/server/ca.crt", "/server/ca.pem"] {
        let (head, _) = raw(gw.addr, &req("GET", path, "casa.example.com", "X-Forwarded-For: 203.0.113.9\r\n")).await;
        assert!(head.starts_with("HTTP/1.1 404"), "{path}: {head}");
    }
    // and the plain landing page is not offered to them either
    let (head, body) = raw(
        gw.addr,
        &req(
            "GET",
            "/",
            "casa.example.com",
            "Accept: text/html\r\nX-Forwarded-For: 203.0.113.9\r\n",
        ),
    )
    .await;
    assert!(!body.contains("Conectar a"), "{head}");
    // what is public stays public
    assert!(raw(
        gw.addr,
        &req("GET", "/server/info/", "casa.example.com", "X-Forwarded-For: 203.0.113.9\r\n")
    )
    .await
    .0
    .starts_with("HTTP/1.1 200"));
    gw.shutdown().await;
}

#[tokio::test]
async fn the_page_tells_whose_machine_it_is_and_what_it_does_not_do() {
    let (_a, gw, _d, _tls) = started(|_| {}).await;
    let (_, body) = raw(gw.addr, &req("GET", "/server/connect/", "192.168.1.5", "")).await;
    let machine = gethostname::gethostname().to_string_lossy().to_string();
    assert!(
        body.contains(&format!("<code>{}</code>", connect::escape(&machine))),
        "the machine name is not on the page"
    );
    assert!(body.contains("Este é um servidor da sua rede") && body.contains("só aparece para aparelhos da própria rede"));
    for promise in [
        "Não pede senha",
        "Não envia nada para a internet",
        "Não instala nada sozinha",
        "Não contém senha",
    ] {
        assert!(body.contains(promise), "missing: {promise}");
    }
    // the QR is behind a choice, not the first thing seen: the browser path is open, the app path is closed
    // both closed at first and exclusive: opening one closes the other (the name attribute, plus a script for old browsers)
    assert!(body.contains("<details class=\"choice\" id=\"web\" name=\"conexao\">\n<summary>Vou usar no navegador"));
    assert!(body.contains("<details class=\"choice\" id=\"app\" name=\"conexao\">\n<summary>Tenho o app Pindrel"));
    assert!(!body.contains("class=\"choice\" open"));
    // the trust check has a time limit: a port that drops packets must not leave "Verificando..." on screen for minutes
    assert!(
        body.contains("AbortController") && body.contains("abort()"),
        "the trust check needs a timeout"
    );
    assert!(
        body.contains("prefers-reduced-motion: no-preference"),
        "motion must respect the system setting"
    );
    // the title is painted at once: animating it from transparent leaves the page without a first contentful paint
    let motion = body.split("prefers-reduced-motion: no-preference").nth(1).unwrap();
    assert!(
        !motion.contains("h1, ") && !motion.contains(".badge,"),
        "the title and badge must not start transparent"
    );
    assert!(
        body.find("Vou usar no navegador").unwrap() < body.find("<svg xmlns").unwrap(),
        "the QR comes before the explanation"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn the_short_code_is_the_start_of_the_fingerprint_and_is_on_the_page_and_in_the_log_format() {
    let (_a, gw, _d, _tls) = started(|_| {}).await;
    let (_, pem) = raw(gw.addr, &req("GET", "/server/ca.pem", "x", "")).await;
    let fp = pindrel_gateway::selfcert::fingerprint_of_pem(&pem).unwrap();
    let short = connect::confirmation(&fp);
    assert_eq!(short.len(), 14);
    assert!(short.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '-'));
    assert_eq!(short.replace('-', "").to_lowercase(), fp[..12]);
    let (_, body) = raw(gw.addr, &req("GET", "/server/connect/", "casa.lan", "")).await;
    assert_eq!(
        body.matches(&short).count(),
        2,
        "on the page once for the browser path and once for the app path"
    );
    gw.shutdown().await;
}

#[test]
fn confirmation_survives_odd_input() {
    assert_eq!(connect::confirmation(&"ab".repeat(32)), "ABAB-ABAB-ABAB");
    assert_eq!(connect::confirmation(""), "--");
    assert_eq!(connect::confirmation("abc"), "--");
    assert_eq!(connect::confirmation("日本語日本語日本語"), "--");
}

#[tokio::test]
async fn a_device_that_already_trusts_the_server_is_sent_on_unless_it_asks_to_stay() {
    let (_a, gw, _d, _tls) = started(|_| {}).await;
    let (_, body) = raw(gw.addr, &req("GET", "/server/connect/", "casa.lan", "")).await;
    // the script jumps to HTTPS when the secure side answers, gives a way to stay, and honours ?ficar
    assert!(
        body.contains("location.href = open.href") && body.contains("Ficar nesta página") && body.contains("ficar"),
        "no automatic hand-over"
    );
    assert!(
        body.contains("setTimeout(function () { location.href"),
        "it must wait a moment, not jump at once"
    );
    // the address it jumps to is the one checked, never taken from the page's own query
    assert!(!body.contains("location.search +") || !body.contains("location.href = location.search"));
    gw.shutdown().await;
}

#[tokio::test]
async fn the_app_choice_leads_with_the_six_digits_and_keeps_the_qr_as_a_second_way() {
    let (_a, gw, _d, _tls) = started(|_| {}).await;
    let (head, body) = raw(gw.addr, &req("GET", "/server/connect/", "192.168.1.5:8080", "")).await;
    assert!(
        head.to_lowercase().contains("connect-src 'self' https://"),
        "the page asks the server for the digits: {head}"
    );
    // the digits come first, the QR sits inside a closed "prefer a QR" box after them
    let (digits, qr) = (body.find("6 números").unwrap(), body.find("Prefiro ler um QR code").unwrap());
    assert!(digits < qr && qr < body.find("<svg xmlns").unwrap());
    // live: asks for them only while the choice is open, never stores them, and fills the text (not HTML)
    assert!(body.contains("/server/pair/sas") && body.contains("textContent") && body.contains("clearInterval"));
    assert!(!body.contains("innerHTML"), "what the server sends is shown as text");
    assert!(body.contains("Nenhum aparelho está pareando agora"));
    // several devices may pair at once: one row each, with the address of the device, built as text (never as markup)
    assert!(body.contains("sas-list") && body.contains("Confira a <strong>sua</strong>") && body.contains("createElement('li')"));
    assert!(!body.contains("em desenvolvimento"), "the app screen exists now");
    // a device that already trusts the server is sent to HTTPS, but not while somebody is pairing: the numbers are here
    assert!(
        body.contains("Há um aparelho pareando agora") && body.contains("pairing"),
        "the redirect must wait for a pairing"
    );
    gw.shutdown().await;
}
