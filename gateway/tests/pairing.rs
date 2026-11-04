//! Pairing over the real gateway: a page asks for a room and watches it, the app (played here over TLS, with the CA it
//! downloaded) joins it, and the master code of the log is proven without being sent. Devices are told apart by their
//! address, so the tests give each one its own (`127.0.0.N` all reach the same listener).
#![cfg(feature = "selfcert")]
mod common;

use std::{net::Ipv4Addr, path::PathBuf, sync::Arc, time::Duration};

use common::*;
use pindrel_gateway::{
    config::{HttpMode, TlsConfig},
    pairing::{digits, hex, master_proof, unhex},
};
use ring::digest::{digest, SHA256};
use rustls::{pki_types::ServerName, ClientConfig, RootCertStore};
use rustls_pki_types::{pem::PemObject, CertificateDer};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpSocket, TcpStream},
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

fn device(n: u8) -> Ipv4Addr {
    Ipv4Addr::new(127, 0, 0, n)
}

async fn connect(port: u16, src: Option<Ipv4Addr>) -> TcpStream {
    match src {
        None => TcpStream::connect(("127.0.0.1", port)).await.unwrap(),
        Some(ip) => {
            let socket = TcpSocket::new_v4().unwrap();
            socket.bind((ip, 0).into()).unwrap();
            socket.connect(([127, 0, 0, 1], port).into()).await.unwrap()
        }
    }
}

fn request(method: &str, path: &str, headers: &[(&str, &str)], body: &[u8]) -> Vec<u8> {
    let mut head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Length: {}\r\n",
        body.len()
    );
    for (k, v) in headers {
        head.push_str(&format!("{k}: {v}\r\n"));
    }
    head.push_str("\r\n");
    let mut out = head.into_bytes();
    out.extend_from_slice(body);
    out
}

fn parse(out: &[u8]) -> (u16, String) {
    let text = String::from_utf8_lossy(out).to_string();
    let status = text.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    (status, text.split_once("\r\n\r\n").map(|(_, b)| b.to_string()).unwrap_or_default())
}

/// One HTTPS request, trusting only the CA the server gave, from the address `src`.
async fn https(rig: &Rig, src: Option<Ipv4Addr>, method: &str, path: &str, headers: &[(&str, &str)], body: &[u8]) -> (u16, String) {
    let mut roots = RootCertStore::empty();
    for c in CertificateDer::pem_slice_iter(rig.ca_pem.as_bytes()) {
        roots.add(c.unwrap()).unwrap();
    }
    let cfg = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
    let tcp = connect(rig.tls, src).await;
    let mut tls = TlsConnector::from(Arc::new(cfg))
        .connect(ServerName::try_from("localhost").unwrap(), tcp)
        .await
        .unwrap();
    tls.write_all(&request(method, path, headers, body)).await.unwrap();
    let mut out = Vec::new();
    let _ = time::timeout(Duration::from_secs(3), tls.read_to_end(&mut out)).await;
    parse(&out)
}

/// One request on the plain port (where a page of the connection page lives), from the address `src`.
async fn plain(rig: &Rig, src: Option<Ipv4Addr>, method: &str, path: &str, headers: &[(&str, &str)], body: &[u8]) -> (u16, String) {
    let mut s = match src {
        None => TcpStream::connect(rig.gw.addr).await.unwrap(),
        Some(ip) => {
            let socket = TcpSocket::new_v4().unwrap();
            socket.bind((ip, 0).into()).unwrap();
            socket.connect(rig.gw.addr).await.unwrap()
        }
    };
    s.write_all(&request(method, path, headers, body)).await.unwrap();
    let mut out = Vec::new();
    let _ = time::timeout(Duration::from_secs(3), s.read_to_end(&mut out)).await;
    parse(&out)
}

fn value(body: &str, key: &str) -> String {
    body.lines()
        .find_map(|l| l.strip_prefix(&format!("{key}=")))
        .unwrap_or_default()
        .to_string()
}

/// A page asks for a room (on the plain port, like the connection page): returns its code and token.
async fn open_room(rig: &Rig, page: Option<Ipv4Addr>) -> (String, String) {
    let (status, body) = plain(rig, page, "POST", "/server/pair/room", &[], b"").await;
    assert_eq!(status, 200, "{body}");
    let (code, token) = (value(&body, "code"), value(&body, "token"));
    assert_eq!(code.len(), 4, "{body}");
    assert_eq!(token.len(), 32, "{body}");
    (code, token)
}

async fn view(rig: &Rig, token: &str) -> (u16, String) {
    plain(rig, None, "GET", "/server/pair/room", &[("x-pindrel-room", token)], b"").await
}

/// What the app does up to the point where it shows its digits: returns the session id, the server's number and the digits.
async fn join(rig: &Rig, phone: Option<Ipv4Addr>, room: &str, nonce: [u8; 16]) -> (String, [u8; 16], String) {
    let commit = hex(digest(&SHA256, &nonce).as_ref());
    let (status, body) = https(
        rig,
        phone,
        "POST",
        "/server/pair/start",
        &[],
        format!("c={commit}\nroom={room}\n").as_bytes(),
    )
    .await;
    assert_eq!(status, 200, "{body}");
    let (id, s) = (value(&body, "id"), unhex::<16>(&value(&body, "n")).unwrap());
    assert_eq!(value(&body, "name"), "Pindrel");
    let (status, body) = https(
        rig,
        phone,
        "POST",
        "/server/pair/reveal",
        &[],
        format!("id={id}\na={}\n", hex(&nonce)).as_bytes(),
    )
    .await;
    assert_eq!(status, 204, "{body}");
    let d = digits(&rig.ca_fp, &nonce, &s);
    (id, s, d)
}

fn shown_digits(body: &str) -> Option<String> {
    body.lines()
        .find_map(|l| l.strip_prefix("d="))
        .map(|l| l.split(',').next().unwrap().to_string())
}

// ---- rooms ---------------------------------------------------------------------------------------------------------

#[tokio::test]
async fn the_page_that_asked_for_the_room_sees_the_digits_the_app_computes() {
    let r = rig(|_| {}).await;
    let (code, token) = open_room(&r, None).await;
    let (status, body) = view(&r, &token).await;
    assert_eq!(status, 200);
    assert_eq!(shown_digits(&body), None, "nobody joined yet");
    let (_, _, app) = join(&r, None, &code, [5; 16]).await;
    let (_, body) = view(&r, &token).await;
    assert_eq!(shown_digits(&body).as_deref(), Some(app.as_str()), "{body}");
    assert_eq!(value(&body, "phone"), "127.0.0.1");
    assert!(value(&body, "left").parse::<u64>().unwrap() <= 180);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn somebody_in_between_with_another_ca_sees_other_digits() {
    let r = rig(|_| {}).await;
    let (code, token) = open_room(&r, None).await;
    let (_, s, _) = join(&r, None, &code, [6; 16]).await;
    let (_, body) = view(&r, &token).await;
    assert_ne!(
        shown_digits(&body).unwrap(),
        digits(&[0xAB; 32], &[6; 16], &s),
        "the app was handed another CA"
    );
    r.gw.shutdown().await;
}

#[tokio::test]
async fn six_people_pair_at_once_and_each_page_sees_only_its_own_digits() {
    let r = rig(|_| {}).await;
    // six pages ask for a room at the same time, each from its own address
    let (a, b, c, d, e, f) = tokio::join!(
        open_room(&r, Some(device(20))),
        open_room(&r, Some(device(21))),
        open_room(&r, Some(device(22))),
        open_room(&r, Some(device(23))),
        open_room(&r, Some(device(24))),
        open_room(&r, Some(device(25)))
    );
    let rooms = [a, b, c, d, e, f];
    let codes: std::collections::HashSet<_> = rooms.iter().map(|(c, _)| c.clone()).collect();
    assert_eq!(codes.len(), 6, "every room has its own code");
    // a seventh page waits
    let (status, body) = plain(&r, Some(device(26)), "POST", "/server/pair/room", &[], b"").await;
    assert_eq!(status, 429, "{body}");
    assert!(body.contains("pairing_busy"));
    // six phones join their own rooms at the same time
    let phone = |n: usize| {
        let (r, code) = (&r, rooms[n].0.clone());
        async move { join(r, Some(device(2 + n as u8)), &code, [10 + n as u8; 16]).await }
    };
    let (p0, p1, p2, p3, p4, p5) = tokio::join!(phone(0), phone(1), phone(2), phone(3), phone(4), phone(5));
    let phones = [p0, p1, p2, p3, p4, p5];
    for n in 0..6 {
        let (_, body) = view(&r, &rooms[n].1).await;
        assert_eq!(
            shown_digits(&body).as_deref(),
            Some(phones[n].2.as_str()),
            "page {n} sees the digits of phone {n}"
        );
        assert_eq!(value(&body, "phone"), device(2 + n as u8).to_string(), "and only its phone");
        for m in 0..6 {
            if m != n {
                assert_ne!(phones[n].2, phones[m].2, "digits differ between rooms");
            }
        }
    }
    // one person confirms: that room closes, and the others are untouched
    let (id, _, _) = &phones[2];
    let (status, _) = https(&r, Some(device(4)), "POST", "/server/pair/done", &[], format!("id={id}").as_bytes()).await;
    assert_eq!(status, 204);
    assert_eq!(view(&r, &rooms[2].1).await.0, 404, "the page learns it is over");
    for n in [0usize, 1, 3, 4, 5] {
        assert_eq!(view(&r, &rooms[n].1).await.0, 200, "room {n} carries on");
    }
    let (status, _) = plain(&r, Some(device(26)), "POST", "/server/pair/room", &[], b"").await;
    assert_eq!(status, 200, "the waiting page gets the freed place");
    r.gw.shutdown().await;
}

#[tokio::test]
async fn a_page_cannot_see_another_pages_digits_with_a_wrong_or_missing_token() {
    let r = rig(|_| {}).await;
    let (code, token) = open_room(&r, Some(device(20))).await;
    join(&r, Some(device(2)), &code, [1; 16]).await;
    let mut near = token.clone();
    near.replace_range(31..32, if token.ends_with('0') { "1" } else { "0" });
    for bad in [
        near.as_str(),
        "",
        "zz",
        &"0".repeat(32),
        &"0".repeat(31),
        &"f".repeat(33),
        "' OR 1=1 --",
    ] {
        let (status, body) = plain(&r, None, "GET", "/server/pair/room", &[("x-pindrel-room", bad)], b"").await;
        assert_eq!(status, 404, "{bad:?}");
        assert!(shown_digits(&body).is_none());
    }
    // no header at all, or the token in the URL (which is never read)
    assert_eq!(plain(&r, None, "GET", "/server/pair/room", &[], b"").await.0, 404);
    assert_eq!(
        plain(&r, None, "GET", &format!("/server/pair/room?token={token}"), &[], b"")
            .await
            .0,
        404
    );
    assert_eq!(view(&r, &token).await.0, 200);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn a_room_holds_one_phone_and_the_same_phone_renews_its_digits() {
    let r = rig(|_| {}).await;
    let (code, token) = open_room(&r, None).await;
    let (first, _, d1) = join(&r, Some(device(2)), &code, [1; 16]).await;
    // another phone cannot take the room
    let (status, body) = https(
        &r,
        Some(device(3)),
        "POST",
        "/server/pair/start",
        &[],
        format!("c={}\nroom={code}\n", hex(&[0u8; 32])).as_bytes(),
    )
    .await;
    assert_eq!(status, 429, "{body}");
    // the first one renews (the app does it every minute): new digits on the page, and the old session is worthless
    let (second, _, d2) = join(&r, Some(device(2)), &code, [2; 16]).await;
    assert_ne!(first, second);
    assert_eq!(shown_digits(&view(&r, &token).await.1).as_deref(), Some(d2.as_str()));
    assert_ne!(d1, d2);
    let (status, body) = https(
        &r,
        Some(device(2)),
        "POST",
        "/server/pair/done",
        &[],
        format!("id={first}").as_bytes(),
    )
    .await;
    assert_eq!(status, 409, "{body}");
    let (status, _) = https(
        &r,
        Some(device(2)),
        "POST",
        "/server/pair/done",
        &[],
        format!("id={second}").as_bytes(),
    )
    .await;
    assert_eq!(status, 204);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn guessing_room_codes_locks_the_address_but_not_the_others() {
    let r = rig(|_| {}).await;
    let (code, _) = open_room(&r, None).await;
    let wrong = format!("{:04}", (code.parse::<u16>().unwrap() + 1) % 10_000);
    let start = |room: String| {
        let r = &r;
        async move {
            https(
                r,
                Some(device(9)),
                "POST",
                "/server/pair/start",
                &[],
                format!("c={}\nroom={room}\n", hex(&[0u8; 32])).as_bytes(),
            )
            .await
        }
    };
    for _ in 0..3 {
        let (status, body) = start(wrong.clone()).await;
        assert_eq!(status, 404, "{body}");
        assert!(body.contains("pairing_room"));
    }
    let (status, body) = start(code.clone()).await;
    assert_eq!(status, 429, "even the right code waits now: {body}");
    assert!(body.contains("pairing_locked"));
    let (status, _) = https(
        &r,
        Some(device(10)),
        "POST",
        "/server/pair/start",
        &[],
        format!("c={}\nroom={code}\n", hex(&[0u8; 32])).as_bytes(),
    )
    .await;
    assert_eq!(status, 200, "another device is not punished");
    r.gw.shutdown().await;
}

#[tokio::test]
async fn closing_a_room_needs_its_token_and_a_page_can_leave() {
    let r = rig(|_| {}).await;
    let (code, token) = open_room(&r, None).await;
    let (status, _) = plain(
        &r,
        None,
        "POST",
        "/server/pair/room/close",
        &[("x-pindrel-room", &"0".repeat(32))],
        b"",
    )
    .await;
    assert_eq!(status, 204, "says nothing about whether it existed");
    assert_eq!(view(&r, &token).await.0, 200, "a wrong token closed nothing");
    let (status, _) = plain(&r, None, "POST", "/server/pair/room/close", &[("x-pindrel-room", &token)], b"").await;
    assert_eq!(status, 204);
    assert_eq!(view(&r, &token).await.0, 404);
    let (status, _) = https(
        &r,
        Some(device(2)),
        "POST",
        "/server/pair/start",
        &[],
        format!("c={}\nroom={code}\n", hex(&[0u8; 32])).as_bytes(),
    )
    .await;
    assert_eq!(status, 404, "its code is dead too");
    r.gw.shutdown().await;
}

#[tokio::test]
async fn the_number_of_rooms_is_configurable() {
    let r = rig(|c| c.max_pairings = 2).await;
    for (n, want) in [(20u8, 200u16), (21, 200), (22, 429)] {
        let (status, body) = plain(&r, Some(device(n)), "POST", "/server/pair/room", &[], b"").await;
        assert_eq!(status, want, "page {n}: {body}");
    }
    r.gw.shutdown().await;
}

#[tokio::test]
async fn the_app_side_happens_only_over_https_and_nothing_at_all_through_a_tunnel() {
    // plain port, redirect mode: the phone's calls are refused before reaching the route; the page's are allowed
    let r = rig(|c| c.http_mode = HttpMode::Redirect).await;
    for path in [
        "/server/pair/start",
        "/server/pair/reveal",
        "/server/pair/done",
        "/server/pair/master/start",
        "/server/pair/master/finish",
    ] {
        let (status, _) = plain(&r, None, "POST", path, &[], b"c=00").await;
        assert_eq!(status, 426, "{path}");
    }
    assert_eq!(plain(&r, None, "POST", "/server/pair/room", &[], b"").await.0, 200);
    r.gw.shutdown().await;
    // plain port, full mode: the routes themselves insist on TLS
    let r = rig(|c| c.http_mode = HttpMode::Full).await;
    for path in ["/server/pair/start", "/server/pair/master/start"] {
        let (status, body) = plain(
            &r,
            None,
            "POST",
            path,
            &[],
            format!("c={}\nroom=1234\n", hex(&[0u8; 32])).as_bytes(),
        )
        .await;
        assert_eq!(status, 426, "{path}: {body}");
        assert!(body.contains("https_required"));
    }
    r.gw.shutdown().await;
    // a declared proxy (a tunnel): the whole family does not exist, rooms included
    let r = rig(|c| {
        c.client_ip =
            pindrel_gateway::clientip::ClientIp::new(pindrel_gateway::clientip::parse_trusted("127.0.0.1").unwrap(), "x-forwarded-for")
                .unwrap()
    })
    .await;
    assert_eq!(plain(&r, None, "POST", "/server/pair/room", &[], b"").await.0, 404);
    assert_eq!(
        plain(&r, None, "GET", "/server/pair/room", &[("x-pindrel-room", &"0".repeat(32))], b"")
            .await
            .0,
        404
    );
    assert_eq!(plain(&r, None, "POST", "/server/pair/start", &[], b"c=00").await.0, 404);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn malformed_requests_get_an_error_and_the_gateway_keeps_working() {
    let r = rig(|_| {}).await;
    let (code, _) = open_room(&r, None).await;
    let good = hex(&[0u8; 32]);
    let cases: Vec<(&str, Vec<u8>)> = vec![
        ("/server/pair/start", vec![]),
        ("/server/pair/start", format!("c={good}").into_bytes()), // no room
        ("/server/pair/start", format!("c={good}\nroom=").into_bytes()),
        ("/server/pair/start", format!("c={good}\nroom=12345").into_bytes()),
        ("/server/pair/start", format!("c={good}\nroom=123").into_bytes()),
        ("/server/pair/start", format!("c={good}\nroom=12a4").into_bytes()),
        ("/server/pair/start", format!("c={good}\nroom=+123").into_bytes()),
        ("/server/pair/start", format!("c={good}\nroom={code}\nroom={code}").into_bytes()), // given twice
        ("/server/pair/start", format!("c=zz\nroom={code}").into_bytes()),
        ("/server/pair/start", vec![0xff, 0xfe, 0x00, 0x80]),
        ("/server/pair/start", vec![b'x'; 100_000]), // far over the 512 bytes it reads
        ("/server/pair/reveal", b"id=00&a=11".to_vec()),
        (
            "/server/pair/reveal",
            format!("id={}\na={}", hex(&[0u8; 16]), hex(&[0u8; 16])).into_bytes(),
        ), // unknown session
        ("/server/pair/done", b"id=zz".to_vec()),
        ("/server/pair/master/start", b"c=".to_vec()),
        ("/server/pair/master/finish", b"id=00".to_vec()),
        (
            "/server/pair/master/finish",
            format!("id={}\na={}\np={}", hex(&[0u8; 16]), hex(&[0u8; 16]), "ab").into_bytes(),
        ), // proof too short
    ];
    for (i, (path, body)) in cases.into_iter().enumerate() {
        // each from its own address, so the lock after three failures does not hide the answer of the next
        let (status, _) = https(&r, Some(device(100 + i as u8)), "POST", path, &[], &body).await;
        assert!(
            (400..500).contains(&status),
            "{path} {:?}: {status}",
            String::from_utf8_lossy(&body[..body.len().min(30)])
        );
    }
    for (method, path) in [
        ("GET", "/server/pair/start"),
        ("PUT", "/server/pair/room"),
        ("POST", "/server/pair/other"),
        ("GET", "/server/pair/"),
        ("GET", "/server/pair/sas"),
    ] {
        let (status, _) = https(&r, None, method, path, &[], b"").await;
        assert_eq!(status, 404, "{method} {path}");
    }
    assert_eq!(get(r.gw.addr, "/server/info/").await.status, 200, "still alive");
    r.gw.shutdown().await;
}

#[tokio::test]
async fn a_flood_of_pages_and_phones_leaves_the_gateway_standing_and_the_rooms_bounded() {
    let r = rig(|_| {}).await;
    let mut opened = 0;
    for i in 0..60u8 {
        let (status, _) = plain(&r, Some(device(30 + (i % 200))), "POST", "/server/pair/room", &[], b"").await;
        if status == 200 {
            opened += 1;
        }
        let (status, _) = https(
            &r,
            Some(device(30 + (i % 200))),
            "POST",
            "/server/pair/start",
            &[],
            format!("c={}\nroom={:04}\n", hex(&[0u8; 32]), i as u16 * 37).as_bytes(),
        )
        .await;
        assert!([200, 404, 429].contains(&status), "{status}");
    }
    assert_eq!(opened, 6, "never more rooms than allowed");
    assert_eq!(get(r.gw.addr, "/server/info/").await.status, 200);
    r.gw.shutdown().await;
}

// ---- the master code -----------------------------------------------------------------------------------------------

/// The app's side of the master way: returns the status and, on success, the server's proof.
async fn master(rig: &Rig, phone: Option<Ipv4Addr>, code: &[u8; 10], fp: &[u8; 32], nonce: [u8; 16]) -> (u16, String, [u8; 16], [u8; 16]) {
    let commit = hex(digest(&SHA256, &nonce).as_ref());
    let (status, body) = https(
        rig,
        phone,
        "POST",
        "/server/pair/master/start",
        &[],
        format!("c={commit}\n").as_bytes(),
    )
    .await;
    assert_eq!(status, 200, "{body}");
    let (id, s) = (value(&body, "id"), unhex::<16>(&value(&body, "n")).unwrap());
    let proof = master_proof(code, b"pindrel-master-a", fp, &nonce, &s);
    let (status, body) = https(
        rig,
        phone,
        "POST",
        "/server/pair/master/finish",
        &[],
        format!("id={id}\na={}\np={}\n", hex(&nonce), hex(&proof)).as_bytes(),
    )
    .await;
    (status, body, nonce, s)
}

#[tokio::test]
async fn the_master_code_pairs_without_digits_and_both_sides_prove_themselves() {
    let r = rig(|_| {}).await;
    let code = r.gw.app.pairing.master_for_tests();
    let (status, body, a, s) = master(&r, Some(device(2)), &code, &r.ca_fp, [3; 16]).await;
    assert_eq!(status, 200, "{body}");
    // the app can check the server's proof: it could only be made with the master code and this server's CA
    let answer = unhex::<32>(&value(&body, "p")).unwrap();
    assert_eq!(answer, master_proof(&code, b"pindrel-master-s", &r.ca_fp, &a, &s));
    r.gw.shutdown().await;
}

#[tokio::test]
async fn the_master_code_works_once_and_the_next_one_is_new() {
    let r = rig(|_| {}).await;
    let _ = r.gw.app.pairing.take_notice();
    let code = r.gw.app.pairing.master_for_tests();
    assert_eq!(master(&r, Some(device(2)), &code, &r.ca_fp, [3; 16]).await.0, 200);
    let next = r.gw.app.pairing.master_for_tests();
    assert_ne!(code, next);
    assert!(
        r.gw.app.pairing.take_notice().is_none(),
        "the gateway already printed the new code in its log"
    );
    // the old one is worth nothing
    assert_eq!(master(&r, Some(device(3)), &code, &r.ca_fp, [4; 16]).await.0, 403);
    // and the new one works
    assert_eq!(master(&r, Some(device(4)), &next, &r.ca_fp, [5; 16]).await.0, 200);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn somebody_in_between_with_another_ca_cannot_use_the_master_code_even_if_they_had_it() {
    let r = rig(|_| {}).await;
    let code = r.gw.app.pairing.master_for_tests();
    // the app was handed another CA: its proof is over that fingerprint, the server checks over its own
    let (status, body, _, _) = master(&r, Some(device(2)), &code, &[0xAB; 32], [3; 16]).await;
    assert_eq!(status, 403, "{body}");
    assert!(body.contains("pairing_denied"));
    r.gw.shutdown().await;
}

#[tokio::test]
async fn wrong_master_codes_lock_the_address_and_five_from_anyone_replace_the_code() {
    let r = rig(|_| {}).await;
    let _ = r.gw.app.pairing.take_notice();
    let real = r.gw.app.pairing.master_for_tests();
    let wrong = [9u8; 10];
    for _ in 0..3 {
        assert_eq!(master(&r, Some(device(2)), &wrong, &r.ca_fp, [3; 16]).await.0, 403);
    }
    let commit = hex(digest(&SHA256, &[1u8; 16]).as_ref());
    let (status, body) = https(
        &r,
        Some(device(2)),
        "POST",
        "/server/pair/master/start",
        &[],
        format!("c={commit}").as_bytes(),
    )
    .await;
    assert_eq!(status, 429, "{body}");
    assert!(body.contains("pairing_locked"));
    // two more from other devices: five in all, so the code is replaced even though nobody guessed it
    assert_eq!(master(&r, Some(device(3)), &wrong, &r.ca_fp, [3; 16]).await.0, 403);
    assert_eq!(master(&r, Some(device(4)), &wrong, &r.ca_fp, [3; 16]).await.0, 403);
    assert!(
        r.gw.app.pairing.master_for_tests() != real,
        "the code of the log is not the one that was being guessed at"
    );
    assert!(
        r.gw.app.pairing.take_notice().is_none(),
        "the replacement was already printed in the log"
    );
    // so a right (old) code no longer works from a clean address
    assert_eq!(master(&r, Some(device(5)), &real, &r.ca_fp, [3; 16]).await.0, 403);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn master_sessions_in_parallel_are_bounded() {
    let r = rig(|_| {}).await;
    let commit = hex(digest(&SHA256, &[1u8; 16]).as_ref());
    let mut ok = 0;
    for n in 0..24u8 {
        let (status, _) = https(
            &r,
            Some(device(60 + n)),
            "POST",
            "/server/pair/master/start",
            &[],
            format!("c={commit}").as_bytes(),
        )
        .await;
        if status == 200 {
            ok += 1;
        } else {
            assert_eq!(status, 429);
        }
    }
    assert_eq!(ok, 16, "only so many wait for a proof at once");
    assert_eq!(get(r.gw.addr, "/server/info/").await.status, 200);
    r.gw.shutdown().await;
}

#[tokio::test]
async fn rooms_and_the_master_way_work_at_the_same_time() {
    let r = rig(|_| {}).await;
    let code = r.gw.app.pairing.master_for_tests();
    let (room, token) = open_room(&r, Some(device(20))).await;
    let (by_digits, by_master) = tokio::join!(
        join(&r, Some(device(2)), &room, [1; 16]),
        master(&r, Some(device(3)), &code, &r.ca_fp, [2; 16])
    );
    assert_eq!(by_master.0, 200);
    assert_eq!(
        shown_digits(&view(&r, &token).await.1).as_deref(),
        Some(by_digits.2.as_str()),
        "the room was not disturbed"
    );
    r.gw.shutdown().await;
}
