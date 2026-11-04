//! WebSocket upgrades through the gateway (HTTP/1.1, plain and over TLS), against a replica that echoes the bytes.
mod common;

use std::time::Duration;

use common::*;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time,
};

const HANDSHAKE: &str = "GET /ws HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nX-Forwarded-For: 6.6.6.6\r\n\r\n";

/// Opens a tunnel and returns the socket after the 101 head, plus the head.
async fn open(addr: std::net::SocketAddr, request: &str) -> (TcpStream, String) {
    let mut s = TcpStream::connect(addr).await.unwrap();
    s.write_all(request.as_bytes()).await.unwrap();
    let mut head = Vec::new();
    let mut b = [0u8; 1];
    while !head.ends_with(b"\r\n\r\n") {
        if s.read(&mut b).await.unwrap() == 0 {
            break;
        }
        head.push(b[0]);
    }
    (s, String::from_utf8_lossy(&head).to_string())
}

#[tokio::test]
async fn the_upgrade_reaches_the_replica_and_bytes_flow_both_ways() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let (mut s, head) = open(gw.addr, HANDSHAKE).await;
    assert!(head.starts_with("HTTP/1.1 101"), "{head}");
    let lower = head.to_lowercase();
    assert!(
        lower.contains("upgrade: websocket") && lower.contains("sec-websocket-accept: test-accept"),
        "{head}"
    );
    assert!(lower.contains("x-backend: a"));
    // the client's own claim about its address does not reach the replica; the gateway's does
    assert!(lower.contains("x-seen-xff: 127.0.0.1"), "{head}");
    s.write_all(b"hello").await.unwrap();
    let mut got = [0u8; 5];
    s.read_exact(&mut got).await.unwrap();
    assert_eq!(&got, b"hello");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_large_stream_comes_back_intact() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let (s, _) = open(gw.addr, HANDSHAKE).await;
    let (mut r, mut w) = s.into_split();
    let data: Vec<u8> = (0..2_000_000u32).map(|i| (i.wrapping_mul(2654435761) >> 24) as u8).collect();
    let sent = data.clone();
    let writer = tokio::spawn(async move { w.write_all(&sent).await.unwrap() });
    let mut back = vec![0u8; data.len()];
    r.read_exact(&mut back).await.unwrap();
    writer.await.unwrap();
    assert!(back == data, "the bytes changed on the way");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_replica_that_refuses_the_upgrade_gives_the_client_its_own_answer() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let (_, head) = open(gw.addr, &HANDSHAKE.replace("/ws", "/missing")).await;
    assert!(head.starts_with("HTTP/1.1 404"), "{head}");
    gw.shutdown().await;
}

#[tokio::test]
async fn ordinary_requests_are_unchanged_and_an_upgrade_that_is_not_websocket_is_not_a_tunnel() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    assert_eq!(get(gw.addr, "/x").await.header("x-backend"), "a");
    // `Upgrade: h2c` must not open a tunnel to the replica
    let r = send(gw.addr, "GET", "/x", &[("connection", "upgrade"), ("upgrade", "h2c")], "").await;
    assert_eq!(r.header("x-seen-upgrade"), "", "the hop-by-hop header was passed on");
    gw.shutdown().await;
}

#[tokio::test]
async fn each_client_has_a_budget_of_tunnels_and_closing_one_gives_it_back() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.max_websockets_per_ip = 2).await;
    let (s1, h1) = open(gw.addr, HANDSHAKE).await;
    let (_s2, h2) = open(gw.addr, HANDSHAKE).await;
    let (_s3, h3) = open(gw.addr, HANDSHAKE).await;
    assert!(h1.starts_with("HTTP/1.1 101") && h2.starts_with("HTTP/1.1 101"), "{h1}{h2}");
    assert!(h3.starts_with("HTTP/1.1 429"), "{h3}");
    drop(s1);
    time::sleep(Duration::from_millis(300)).await;
    let (_s4, h4) = open(gw.addr, HANDSHAKE).await;
    assert!(h4.starts_with("HTTP/1.1 101"), "the slot was not given back: {h4}");
    gw.shutdown().await;
}

#[tokio::test]
async fn the_global_budget_is_enforced_with_a_clear_answer() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.max_websockets = 1).await;
    let (_s1, h1) = open(gw.addr, HANDSHAKE).await;
    let (_s2, h2) = open(gw.addr, HANDSHAKE).await;
    assert!(h1.starts_with("HTTP/1.1 101"));
    assert!(h2.starts_with("HTTP/1.1 503"), "{h2}");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_silent_tunnel_is_closed_after_the_idle_time_and_a_busy_one_is_not() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.ws_idle = Duration::from_millis(400)).await;
    let (mut quiet, _) = open(gw.addr, HANDSHAKE).await;
    let (mut busy, _) = open(gw.addr, HANDSHAKE).await;
    let mut buf = [0u8; 1];
    for _ in 0..6 {
        time::sleep(Duration::from_millis(200)).await;
        busy.write_all(b"p").await.unwrap();
        busy.read_exact(&mut buf).await.unwrap();
    }
    let closed = time::timeout(Duration::from_secs(2), quiet.read(&mut buf))
        .await
        .expect("closed in time");
    assert!(matches!(closed, Ok(0) | Err(_)));
    busy.write_all(b"z").await.unwrap();
    busy.read_exact(&mut buf).await.unwrap();
    gw.shutdown().await;
}

#[tokio::test]
async fn shutting_the_gateway_down_closes_the_open_tunnels() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let (mut s, _) = open(gw.addr, HANDSHAKE).await;
    let started = std::time::Instant::now();
    gw.shutdown().await;
    assert!(started.elapsed() < Duration::from_secs(4), "shutdown waited for the tunnel");
    let mut buf = [0u8; 1];
    let r = time::timeout(Duration::from_secs(2), s.read(&mut buf))
        .await
        .expect("the tunnel was closed");
    assert!(matches!(r, Ok(0) | Err(_)));
}

#[tokio::test]
async fn a_dead_replica_is_skipped_for_the_next_one() {
    let (a, b) = (Backend::start("a").await, Backend::start("b").await);
    let gw = gateway(&[&a, &b]).await;
    gw.app.pool.probe().await;
    a.kill();
    for _ in 0..4 {
        let (_s, head) = open(gw.addr, HANDSHAKE).await;
        assert!(
            head.starts_with("HTTP/1.1 101") && head.to_lowercase().contains("x-backend: b"),
            "{head}"
        );
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn a_flood_of_handshakes_and_garbage_does_not_hurt() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| {
        c.rate_limit = false;
        c.max_websockets_per_ip = 1000;
    })
    .await;
    let mut open_ones = Vec::new();
    for _ in 0..150 {
        open_ones.push(open(gw.addr, HANDSHAKE).await);
    }
    assert!(open_ones.iter().all(|(_, h)| h.starts_with("HTTP/1.1 101")));
    // malformed upgrade requests
    for junk in [
        "GET /ws HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\n\r\n",
        "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n\r\n",
        "POST /ws HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nContent-Length: 0\r\n\r\n",
    ] {
        let (_, head) = open(gw.addr, junk).await;
        assert!(!head.is_empty());
    }
    assert_eq!(get(gw.addr, "/x").await.header("x-backend"), "a");
    gw.shutdown().await;
}
