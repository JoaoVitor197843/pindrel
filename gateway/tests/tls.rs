//! TLS listener (HTTP/1.1 + HTTP/2) and, with `--features http3`, HTTP/3, against fake replicas.
#![cfg(feature = "tls")]
mod common;

use std::{path::PathBuf, sync::Arc, time::Duration};

use bytes::Bytes;
use common::*;
use http_body_util::{BodyExt, Full};
use hyper::{Request, StatusCode};
use hyper_util::rt::{TokioExecutor, TokioIo};
use pindrel_gateway::config::TlsConfig;
use rustls::{pki_types::ServerName, ClientConfig, RootCertStore};
use rustls_pki_types::{pem::PemObject, CertificateDer};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time,
};
use tokio_rustls::TlsConnector;

fn dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/tls")
}

/// A port free on both TCP and UDP (the gateway uses the same number for HTTP/3).
fn free_port() -> u16 {
    loop {
        let tcp = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = tcp.local_addr().unwrap().port();
        if std::net::UdpSocket::bind(("127.0.0.1", port)).is_ok() {
            return port;
        }
    }
}

fn tls_cfg(port: u16, http3: bool) -> TlsConfig {
    TlsConfig {
        port,
        cert: dir().join("cert.pem"),
        key: dir().join("key.pem"),
        auto_dir: None,
        extra_sans: Vec::new(),
        refresh: Duration::ZERO,
        http3,
    }
}

fn client_config(alpn: &[&[u8]]) -> Arc<ClientConfig> {
    let mut roots = RootCertStore::empty();
    for c in CertificateDer::pem_file_iter(dir().join("cert.pem")).unwrap() {
        roots.add(c.unwrap()).unwrap();
    }
    let mut cfg = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
    cfg.alpn_protocols = alpn.iter().map(|p| p.to_vec()).collect();
    Arc::new(cfg)
}

async fn tls_stream(port: u16, alpn: &[&[u8]]) -> tokio_rustls::client::TlsStream<TcpStream> {
    let tcp = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
    TlsConnector::from(client_config(alpn))
        .connect(ServerName::try_from("localhost").unwrap(), tcp)
        .await
        .expect("TLS handshake")
}

/// One request over HTTP/2; returns status, the `x-backend` header and the body.
async fn h2_request(port: u16, method: &str, path: &str, body: &str) -> (StatusCode, String, String, Option<String>) {
    let io = TokioIo::new(tls_stream(port, &[b"h2"]).await);
    let (mut send, conn) = hyper::client::conn::http2::handshake(TokioExecutor::new(), io).await.unwrap();
    tokio::spawn(conn);
    let req = Request::builder()
        .method(method)
        .uri(format!("https://localhost:{port}{path}"))
        .body(Full::new(Bytes::from(body.to_string())))
        .unwrap();
    let resp = send.send_request(req).await.unwrap();
    let (parts, incoming) = resp.into_parts();
    let text = String::from_utf8(incoming.collect().await.unwrap().to_bytes().to_vec()).unwrap();
    let h = |k: &str| parts.headers.get(k).and_then(|v| v.to_str().ok()).map(str::to_string);
    (parts.status, h("x-backend").unwrap_or_default(), text, h("alt-svc"))
}

#[tokio::test]
async fn http2_over_tls_reaches_the_replica_with_method_path_and_body() {
    let a = Backend::start("a").await;
    let port = free_port();
    let gw = gateway_with(&[&a], |c| c.tls = Some(tls_cfg(port, false))).await;
    let (status, backend, body, alt_svc) = h2_request(port, "PUT", "/notes/7?x=1", "payload").await;
    assert_eq!((status, backend.as_str(), body.as_str()), (StatusCode::OK, "a", "payload"));
    assert_eq!(alt_svc, None, "no HTTP/3 offered when it is off");
    gw.shutdown().await;
}

#[tokio::test]
async fn http1_over_tls_still_works_and_the_plain_port_is_unchanged() {
    let a = Backend::start("a").await;
    let port = free_port();
    let gw = gateway_with(&[&a], |c| c.tls = Some(tls_cfg(port, false))).await;
    let mut s = tls_stream(port, &[b"http/1.1"]).await;
    s.write_all(b"GET /x HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        .await
        .unwrap();
    let mut out = String::new();
    s.read_to_string(&mut out).await.unwrap();
    assert!(out.starts_with("HTTP/1.1 200"), "{out}");
    assert_eq!(get(gw.addr, "/x").await.header("x-backend"), "a");
    gw.shutdown().await;
}

#[tokio::test]
async fn websocket_works_over_tls_and_survives_a_large_exchange() {
    let a = Backend::start("a").await;
    let port = free_port();
    let gw = gateway_with(&[&a], |c| c.tls = Some(tls_cfg(port, false))).await;
    // browsers open WebSockets with an HTTP/1.1 upgrade even on a TLS connection that could speak HTTP/2
    let mut s = tls_stream(port, &[b"http/1.1"]).await;
    s.write_all(b"GET /ws HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").await.unwrap();
    let mut head = Vec::new();
    let mut b = [0u8; 1];
    while !head.ends_with(b"\r\n\r\n") {
        s.read_exact(&mut b).await.unwrap();
        head.push(b[0]);
    }
    assert!(String::from_utf8_lossy(&head).starts_with("HTTP/1.1 101"));
    let (mut r, mut w) = tokio::io::split(s);
    let data: Vec<u8> = (0..500_000u32).map(|i| (i % 251) as u8).collect();
    let sent = data.clone();
    let writer = tokio::spawn(async move {
        w.write_all(&sent).await.unwrap();
        w
    });
    let mut back = vec![0u8; data.len()];
    r.read_exact(&mut back).await.unwrap();
    assert!(back == data);
    let _ = writer.await;
    gw.shutdown().await;
}

#[tokio::test]
async fn many_concurrent_http2_streams_on_one_connection() {
    let a = Backend::start("a").await;
    let port = free_port();
    let gw = gateway_with(&[&a], |c| {
        c.tls = Some(tls_cfg(port, false));
        c.rate_limit = false;
    })
    .await;
    let io = TokioIo::new(tls_stream(port, &[b"h2"]).await);
    let (send, conn) = hyper::client::conn::http2::handshake(TokioExecutor::new(), io).await.unwrap();
    tokio::spawn(conn);
    // The server allows 64 streams at once on a connection (a client that opens more gets REFUSED_STREAM and retries,
    // as browsers do): 200 requests in waves of 50 all go through on the one connection.
    for wave in 0..4 {
        let mut tasks = Vec::new();
        for n in 0..50 {
            let i = wave * 50 + n;
            let mut send = send.clone();
            tasks.push(tokio::spawn(async move {
                let req = Request::builder()
                    .method("POST")
                    .uri(format!("https://localhost:{port}/echo/{i}"))
                    .body(Full::new(Bytes::from(format!("body-{i}"))))
                    .unwrap();
                let resp = send.send_request(req).await.unwrap();
                let body = resp.into_body().collect().await.unwrap().to_bytes();
                assert_eq!(body, format!("body-{i}").as_bytes());
            }));
        }
        for t in tasks {
            t.await.unwrap();
        }
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn garbage_and_silent_clients_on_the_tls_port_are_dropped_and_do_not_hold_slots() {
    let a = Backend::start("a").await;
    let port = free_port();
    let gw = gateway_with(&[&a], |c| {
        c.tls = Some(tls_cfg(port, false));
        c.header_timeout = Duration::from_millis(300);
        c.max_connections = 4;
        c.max_connections_per_ip = 100;
    })
    .await;
    // plain HTTP spoken to the TLS port, random bytes, and sockets that never say anything
    let mut junk = Vec::new();
    for payload in [
        &b"GET / HTTP/1.1\r\n\r\n"[..],
        &[0x16, 0x03, 0x01, 0xff, 0xff][..],
        &[][..],
        &[][..],
    ] {
        let mut s = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        s.write_all(payload).await.unwrap();
        junk.push(s);
    }
    time::sleep(Duration::from_millis(900)).await;
    // all four slots were taken by junk; after the handshake budget they are free again
    let (status, backend, _, _) = h2_request(port, "GET", "/x", "").await;
    assert_eq!((status, backend.as_str()), (StatusCode::OK, "a"));
    drop(junk);
    gw.shutdown().await;
}

#[tokio::test]
async fn an_unreadable_certificate_stops_the_start_with_a_clear_error() {
    let a = Backend::start("a").await;
    let mut cfg = tls_cfg(free_port(), false);
    cfg.cert = dir().join("missing.pem");
    let mut c = pindrel_gateway::config::Config::new(vec![a.addr]);
    c.port = 0;
    c.mdns = false;
    c.tls = Some(cfg);
    assert!(pindrel_gateway::server::start_with(c, None).await.is_err());
}

#[cfg(feature = "http3")]
mod http3 {
    use super::*;
    use bytes::Buf;
    use quinn::crypto::rustls::QuicClientConfig;
    use std::net::SocketAddr;

    async fn h3_request(port: u16, method: &str, path: &str, body: &str) -> (StatusCode, String, String) {
        let mut endpoint = quinn::Endpoint::client("0.0.0.0:0".parse::<SocketAddr>().unwrap()).unwrap();
        let quic = QuicClientConfig::try_from(client_config(&[b"h3"])).unwrap();
        endpoint.set_default_client_config(quinn::ClientConfig::new(Arc::new(quic)));
        let conn = endpoint
            .connect(([127, 0, 0, 1], port).into(), "localhost")
            .unwrap()
            .await
            .expect("QUIC handshake");
        let (mut driver, mut send) = h3::client::new(h3_quinn::Connection::new(conn)).await.unwrap();
        let drive = tokio::spawn(async move { std::future::poll_fn(|cx| driver.poll_close(cx)).await });
        let req = Request::builder()
            .method(method)
            .uri(format!("https://localhost:{port}{path}"))
            .body(())
            .unwrap();
        let mut stream = send.send_request(req).await.unwrap();
        if !body.is_empty() {
            stream.send_data(Bytes::from(body.to_string())).await.unwrap();
        }
        stream.finish().await.unwrap();
        let resp = stream.recv_response().await.unwrap();
        let mut text = Vec::new();
        while let Some(mut chunk) = stream.recv_data().await.unwrap() {
            text.extend_from_slice(&chunk.copy_to_bytes(chunk.remaining()));
        }
        let backend = resp
            .headers()
            .get("x-backend")
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_string();
        drive.abort();
        (resp.status(), backend, String::from_utf8(text).unwrap())
    }

    #[tokio::test]
    async fn http3_reaches_the_replica_and_http2_advertises_it() {
        let a = Backend::start("a").await;
        let port = free_port();
        let gw = gateway_with(&[&a], |c| c.tls = Some(tls_cfg(port, true))).await;
        let (status, backend, body) = h3_request(port, "PUT", "/notes/7?x=1", "payload").await;
        assert_eq!((status, backend.as_str(), body.as_str()), (StatusCode::OK, "a", "payload"));
        let (_, _, _, alt_svc) = h2_request(port, "GET", "/x", "").await;
        assert_eq!(alt_svc.as_deref(), Some(format!("h3=\":{port}\"; ma=86400").as_str()));
        gw.shutdown().await;
    }

    #[tokio::test]
    async fn http3_body_over_the_limit_is_refused_and_a_flood_of_requests_works() {
        let a = Backend::start("a").await;
        let port = free_port();
        let gw = gateway_with(&[&a], |c| {
            c.tls = Some(tls_cfg(port, true));
            c.max_body = 1024;
            c.rate_limit = false;
        })
        .await;
        let (status, _, _) = h3_request(port, "POST", "/big", &"x".repeat(4096)).await;
        assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
        let mut tasks = Vec::new();
        for i in 0..30 {
            tasks.push(tokio::spawn(
                async move { h3_request(port, "POST", "/echo", &format!("n{i}")).await },
            ));
        }
        for (i, t) in tasks.into_iter().enumerate() {
            let (status, _, body) = t.await.unwrap();
            assert_eq!((status, body), (StatusCode::OK, format!("n{i}")));
        }
        gw.shutdown().await;
    }

    #[tokio::test]
    async fn udp_junk_on_the_quic_port_is_ignored() {
        let a = Backend::start("a").await;
        let port = free_port();
        let gw = gateway_with(&[&a], |c| c.tls = Some(tls_cfg(port, true))).await;
        let sock = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        for n in [0usize, 1, 20, 1200, 1500] {
            let _ = sock.send_to(&vec![0xAB; n], ("127.0.0.1", port)).await;
        }
        let (status, backend, _) = h3_request(port, "GET", "/x", "").await;
        assert_eq!((status, backend.as_str()), (StatusCode::OK, "a"));
        gw.shutdown().await;
    }
}
