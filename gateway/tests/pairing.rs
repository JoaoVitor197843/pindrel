//! Pairing by six digits over the real gateway: the app's side of the protocol is played here, over TLS, with the CA it
//! downloaded, and the digits must agree with the ones the connection page shows.
#![cfg(feature = "selfcert")]
mod common;

use std::{path::PathBuf, sync::Arc, time::Duration};

use common::*;
use pindrel_gateway::{
    config::{HttpMode, TlsConfig},
    pairing::{digits, hex, unhex},
};
use ring::digest::{digest, SHA256};
use rustls::{pki_types::ServerName, ClientConfig, RootCertStore};
use rustls_pki_types::{pem::PemObject, CertificateDer};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time,
};
use tokio_rustls::TlsConnector;

struct Dir(PathBuf);
impl Dir {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!("pindrel-pair-{}-{}", std::process::id(), free_port()));
        std::fs::create_dir_all(&p).unwrap();
        Dir(p)
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct Rig {
    _a: Backend,
    gw: pindrel_gateway::server::Running,
    _dir: Dir,
    tls: u16,
    ca_pem: String,
    ca_fp: [u8; 32],
}

async fn rig(tweak: impl FnOnce(&mut pindrel_gateway::config::Config)) -> Rig {
    let (a, dir, tls) = (Backend::start("a").await, Dir::new(), free_port());
    let d = dir.0.clone();
    let gw = gateway_with(&[&a], move |c| {
        c.tls = Some(TlsConfig {
            port: tls,
            cert: PathBuf::new(),
            key: PathBuf::new(),
            auto_dir: Some(d),
            extra_sans: Vec::new(),
            refresh: Duration::ZERO,
        });
        tweak(c);
    })
    .await;
    // behind a declared proxy there is no CA to fetch (that is one of the things tested)
    let r = get(gw.addr, "/server/ca.pem").await;
    let ca_pem = if r.status == 200 {
        String::from_utf8(r.body.to_vec()).unwrap()
    } else {
        String::new()
    };
    let ca_fp: [u8; 32] = match CertificateDer::from_pem_slice(ca_pem.as_bytes()) {
        Ok(der) => digest(&SHA256, &der).as_ref().try_into().unwrap(),
        Err(_) => [0; 32],
    };
    Rig {
        _a: a,
        gw,
        _dir: dir,
        tls,
        ca_pem,
        ca_fp,
    }
}

/// One HTTPS request written by hand, trusting only the CA the server gave; returns the status and the body.
async fn https(rig: &Rig, method: &str, path: &str, body: &[u8]) -> (u16, String) {
    let mut roots = RootCertStore::empty();
    for c in CertificateDer::pem_slice_iter(rig.ca_pem.as_bytes()) {
        roots.add(c.unwrap()).unwrap();
    }
    let cfg = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
    let tcp = TcpStream::connect(("127.0.0.1", rig.tls)).await.unwrap();
    let mut tls = TlsConnector::from(Arc::new(cfg))
        .connect(ServerName::try_from("localhost").unwrap(), tcp)
        .await
        .unwrap();
    let head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Length: {}\r\n\r\n",
        body.len()
    );
    tls.write_all(head.as_bytes()).await.unwrap();
    tls.write_all(body).await.unwrap();
    let mut out = Vec::new();
    let _ = time::timeout(Duration::from_secs(3), tls.read_to_end(&mut out)).await;
    let text = String::from_utf8_lossy(&out).to_string();
    let status = text.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    (status, text.split_once("\r\n\r\n").map(|(_, b)| b.to_string()).unwrap_or_default())
}

fn value(body: &str, key: &str) -> String {
    body.lines()
        .find_map(|l| l.strip_prefix(&format!("{key}=")))
        .unwrap_or_default()
        .to_string()
}

/// What the app does up to the point where it shows its digits. Returns them.
async fn app_side(rig: &Rig, nonce: [u8; 16]) -> String {
    let commit = hex(digest(&SHA256, &nonce).as_ref());
    let (status, body) = https(rig, "POST", "/server/pair/start", format!("c={commit}\n").as_bytes()).await;
    assert_eq!(status, 200, "{body}");
    let (id, s) = (value(&body, "id"), unhex::<16>(&value(&body, "n")).unwrap());
    assert_eq!(value(&body, "name"), "Pindrel");
    let (status, body) = https(
        rig,
        "POST",
        "/server/pair/reveal",
        format!("id={id}\na={}\n", hex(&nonce)).as_bytes(),
    )
    .await;
    assert_eq!(status, 204, "{body}");
    digits(&rig.ca_fp, &nonce, &s)
}

#[tokio::test]
async fn the_digits_the_app_computes_are_the_ones_the_page_shows() {
    let r = rig(|_| {}).await;
    // nobody is pairing: the page has nothing to show
    assert_eq!(get(r.gw.addr, "/server/pair/sas").await.status, 204);
    let app = app_side(&r, [5; 16]).await;
    let shown = get(r.gw.addr, "/server/pair/sas").await; // the plain port, like the connection page
    assert_eq!(shown.status, 200);
    let text = String::from_utf8(shown.body.to_vec()).unwrap();
    assert_eq!(value(&text, "sas"), app, "{text}");
    assert_eq!(value(&text, "from"), "127.0.0.1");
    assert!(value(&text, "left").parse::<u64>().unwrap() <= 60);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn somebody_in_between_with_another_ca_sees_other_digits() {
    let r = rig(|_| {}).await;
    let nonce = [6u8; 16];
    let commit = hex(digest(&SHA256, &nonce).as_ref());
    let (_, body) = https(&r, "POST", "/server/pair/start", format!("c={commit}").as_bytes()).await;
    let (id, s) = (value(&body, "id"), unhex::<16>(&value(&body, "n")).unwrap());
    https(&r, "POST", "/server/pair/reveal", format!("id={id}\na={}", hex(&nonce)).as_bytes()).await;
    let shown = String::from_utf8(get(r.gw.addr, "/server/pair/sas").await.body.to_vec()).unwrap();
    let forged = digits(&[0xAB; 32], &nonce, &s); // the app was handed another CA
    assert_ne!(value(&shown, "sas"), forged);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn a_wrong_commitment_is_refused_and_repeated_failures_lock_the_address() {
    let r = rig(|_| {}).await;
    for _ in 0..3 {
        let commit = hex(digest(&SHA256, &[1u8; 16]).as_ref());
        let (_, body) = https(&r, "POST", "/server/pair/start", format!("c={commit}").as_bytes()).await;
        let id = value(&body, "id");
        let (status, _) = https(
            &r,
            "POST",
            "/server/pair/reveal",
            format!("id={id}\na={}", hex(&[2u8; 16])).as_bytes(),
        )
        .await;
        assert_eq!(status, 400);
    }
    let (status, body) = https(&r, "POST", "/server/pair/start", format!("c={}", hex(&[0u8; 32])).as_bytes()).await;
    assert_eq!(status, 429, "{body}");
    assert!(body.contains("pairing_locked"));
    assert_eq!(
        get(r.gw.addr, "/server/pair/sas").await.status,
        204,
        "a failed attempt shows nothing"
    );
    r.gw.shutdown().await;
}

#[tokio::test]
async fn it_happens_only_over_https_and_never_through_a_tunnel() {
    // plain port, redirect mode: the POST is refused before reaching the route
    let r = rig(|_| {}).await;
    let (head, _) = raw_plain(r.gw.addr, "POST", "/server/pair/start", "c=00").await;
    assert!(head.starts_with("HTTP/1.1 426"), "{head}");
    r.gw.shutdown().await;
    // plain port, full mode: the route itself still insists on TLS
    let r = rig(|c| c.http_mode = HttpMode::Full).await;
    let (head, body) = raw_plain(r.gw.addr, "POST", "/server/pair/start", &format!("c={}", hex(&[0u8; 32]))).await;
    assert!(head.starts_with("HTTP/1.1 426") && body.contains("https_required"), "{head} {body}");
    r.gw.shutdown().await;
    // a declared proxy (a tunnel): the whole family does not exist
    let r = rig(|c| {
        c.client_ip =
            pindrel_gateway::clientip::ClientIp::new(pindrel_gateway::clientip::parse_trusted("127.0.0.1").unwrap(), "x-forwarded-for")
                .unwrap()
    })
    .await;
    assert_eq!(get(r.gw.addr, "/server/pair/sas").await.status, 404);
    let (head, _) = raw_plain(r.gw.addr, "POST", "/server/pair/start", "c=00").await;
    assert!(head.starts_with("HTTP/1.1 404"), "{head}");
    r.gw.shutdown().await;
}

async fn raw_plain(addr: std::net::SocketAddr, method: &str, path: &str, body: &str) -> (String, String) {
    let mut s = TcpStream::connect(addr).await.unwrap();
    let req = format!(
        "{method} {path} HTTP/1.1\r\nHost: casa.lan\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{body}",
        body.len()
    );
    s.write_all(req.as_bytes()).await.unwrap();
    let mut out = Vec::new();
    let _ = time::timeout(Duration::from_secs(3), s.read_to_end(&mut out)).await;
    let text = String::from_utf8_lossy(&out).to_string();
    match text.split_once("\r\n\r\n") {
        Some((h, b)) => (h.to_string(), b.to_string()),
        None => (text, String::new()),
    }
}

#[tokio::test]
async fn malformed_requests_get_an_error_and_the_gateway_keeps_working() {
    let r = rig(|_| {}).await;
    let good = hex(&[0u8; 32]);
    let cases: Vec<(&str, Vec<u8>)> = vec![
        ("/server/pair/start", vec![]),
        ("/server/pair/start", b"c=".to_vec()),
        ("/server/pair/start", b"c=zz".to_vec()),
        ("/server/pair/start", format!("c={good}\nc={good}").into_bytes()), // given twice
        ("/server/pair/start", format!("c=+{}", &good[1..]).into_bytes()),
        ("/server/pair/start", vec![0xff, 0xfe, 0x00, 0x80]),
        ("/server/pair/start", vec![b'x'; 100_000]), // far over the 512 bytes it reads
        ("/server/pair/reveal", b"id=00&a=11".to_vec()),
        (
            "/server/pair/reveal",
            format!("id={}\na={}", hex(&[0u8; 16]), hex(&[0u8; 16])).into_bytes(),
        ), // unknown session
    ];
    for (path, body) in cases {
        let (status, _) = https(&r, "POST", path, &body).await;
        assert!(
            (400..500).contains(&status),
            "{path} {:?}: {status}",
            String::from_utf8_lossy(&body[..body.len().min(30)])
        );
    }
    for (method, path) in [
        ("GET", "/server/pair/start"),
        ("PUT", "/server/pair/sas"),
        ("POST", "/server/pair/other"),
        ("GET", "/server/pair/"),
    ] {
        let (status, _) = https(&r, method, path, b"").await;
        assert_eq!(status, 404, "{method} {path}");
    }
    assert_eq!(get(r.gw.addr, "/server/info/").await.status, 200, "still alive");
    r.gw.shutdown().await;
}

#[tokio::test]
async fn a_second_try_after_a_failure_still_works_for_a_careless_person() {
    // wrong tap, start again, finish: one failure does not lock anything
    let r = rig(|_| {}).await;
    let commit = hex(digest(&SHA256, &[1u8; 16]).as_ref());
    let (_, body) = https(&r, "POST", "/server/pair/start", format!("c={commit}").as_bytes()).await;
    let id = value(&body, "id");
    https(
        &r,
        "POST",
        "/server/pair/reveal",
        format!("id={id}\na={}", hex(&[9u8; 16])).as_bytes(),
    )
    .await;
    let app = app_side(&r, [3; 16]).await;
    let text = String::from_utf8(get(r.gw.addr, "/server/pair/sas").await.body.to_vec()).unwrap();
    assert_eq!(value(&text, "sas"), app);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn telling_the_server_the_person_answered_clears_the_page() {
    let r = rig(|_| {}).await;
    let nonce = [4u8; 16];
    let commit = hex(digest(&SHA256, &nonce).as_ref());
    let (_, body) = https(&r, "POST", "/server/pair/start", format!("c={commit}").as_bytes()).await;
    let id = value(&body, "id");
    https(&r, "POST", "/server/pair/reveal", format!("id={id}\na={}", hex(&nonce)).as_bytes()).await;
    assert_eq!(get(r.gw.addr, "/server/pair/sas").await.status, 200);
    // garbage is refused; a well-formed id that is not the live session ends nothing and is told so
    for junk in ["id=00", "", "id=zz"] {
        let (status, _) = https(&r, "POST", "/server/pair/done", junk.as_bytes()).await;
        assert_eq!(status, 400, "{junk:?}");
    }
    let (status, body) = https(&r, "POST", "/server/pair/done", format!("id={}", hex(&[1u8; 16])).as_bytes()).await;
    assert_eq!(status, 409, "{body}");
    assert_eq!(get(r.gw.addr, "/server/pair/sas").await.status, 200, "still showing");
    let (status, _) = https(&r, "POST", "/server/pair/done", format!("id={id}").as_bytes()).await;
    assert_eq!(status, 204);
    assert_eq!(
        get(r.gw.addr, "/server/pair/sas").await.status,
        204,
        "the digits are gone once the app is done"
    );
    r.gw.shutdown().await;
}

#[tokio::test]
async fn a_second_start_from_the_same_address_makes_the_first_confirmation_worthless() {
    // two people behind one address: the second replaces the first, and the first may not pair on numbers the page no longer shows
    let r = rig(|_| {}).await;
    let n1 = [7u8; 16];
    let c1 = hex(digest(&SHA256, &n1).as_ref());
    let (_, b1) = https(&r, "POST", "/server/pair/start", format!("c={c1}").as_bytes()).await;
    let id1 = value(&b1, "id");
    https(&r, "POST", "/server/pair/reveal", format!("id={id1}\na={}", hex(&n1)).as_bytes()).await;
    let _second = app_side(&r, [8; 16]).await; // takes the slot and shows its own digits
    let shown = String::from_utf8(get(r.gw.addr, "/server/pair/sas").await.body.to_vec()).unwrap();
    assert_ne!(value(&shown, "sas"), "");
    let (status, body) = https(&r, "POST", "/server/pair/done", format!("id={id1}").as_bytes()).await;
    assert_eq!(status, 409, "{body}");
    assert!(body.contains("pairing_expired"));
    r.gw.shutdown().await;
}
