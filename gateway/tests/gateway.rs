//! The whole gateway in-process against fake replicas.
mod common;

use std::{collections::HashMap, time::Duration};

use common::*;
use hyper::StatusCode;
use pindrel_gateway::discovery::Server;
use prost::Message;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time,
};

#[tokio::test]
async fn round_robin_spreads_requests_evenly() {
    let (a, b, c) = (Backend::start("a").await, Backend::start("b").await, Backend::start("c").await);
    let gw = gateway(&[&a, &b, &c]).await;
    let mut seen: HashMap<String, u32> = HashMap::new();
    for _ in 0..12 {
        *seen.entry(get(gw.addr, "/x").await.header("x-backend").to_string()).or_default() += 1;
    }
    assert_eq!((seen["a"], seen["b"], seen["c"]), (4, 4, 4), "{seen:?}");
    gw.shutdown().await;
}

#[tokio::test]
async fn method_path_query_headers_and_body_reach_the_replica() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let r = send(
        gw.addr,
        "PUT",
        "/notes/7?x=1&y=a%20b",
        &[("content-type", "application/x-protobuf")],
        "payload",
    )
    .await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.body, "payload");
    assert_eq!(r.header("x-seen-method"), "PUT");
    assert_eq!(r.header("x-seen-path"), "/notes/7?x=1&y=a%20b");
    assert_eq!(r.header("x-seen-content-type"), "application/x-protobuf");
    gw.shutdown().await;
}

#[tokio::test]
async fn replica_status_and_headers_pass_through_untouched() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let r = get(gw.addr, "/missing").await;
    assert_eq!(r.status, StatusCode::NOT_FOUND);
    assert_eq!(r.header("x-custom"), "kept");
    gw.shutdown().await;
}

#[tokio::test]
async fn forwarded_for_is_the_real_client_and_a_spoofed_one_is_replaced() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    assert_eq!(get(gw.addr, "/x").await.header("x-seen-xff"), "127.0.0.1");
    let r = send(gw.addr, "GET", "/x", &[("x-forwarded-for", "1.2.3.4, 5.6.7.8")], "").await;
    assert_eq!(
        r.header("x-seen-xff"),
        "127.0.0.1",
        "the gateway is the edge: client-sent values must not survive"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn hop_by_hop_headers_are_not_forwarded() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let r = send(
        gw.addr,
        "GET",
        "/x",
        &[
            ("te", "trailers"),
            ("upgrade", "websocket"),
            ("connection", "keep-alive, x-secret"),
            ("x-secret", "1"),
        ],
        "",
    )
    .await;
    assert_eq!((r.header("x-seen-te"), r.header("x-seen-upgrade")), ("", ""));
    assert!(!r.header("x-seen-connection").contains("x-secret"));
    gw.shutdown().await;
}

#[tokio::test]
async fn a_dead_replica_is_skipped_and_even_a_post_is_replayed_on_the_next_one() {
    let (a, b) = (Backend::start("a").await, Backend::start("b").await);
    let gw = gateway(&[&a, &b]).await;
    a.kill(); // dies after the last probe: the gateway still believes it is up
    time::sleep(Duration::from_millis(100)).await;
    for _ in 0..4 {
        let r = send(gw.addr, "POST", "/auth/refresh/", &[], "important-body").await;
        assert_eq!(
            (r.status, r.body.as_ref(), r.header("x-backend")),
            (StatusCode::OK, &b"important-body"[..], "b")
        );
    }
    assert_eq!(
        gw.app.pool.alive(),
        [b.addr],
        "the dead replica is marked down without waiting for the next probe"
    );
    gw.shutdown().await;
}

// A replica that is stopped by a rolling update can close a connection a request was just sent on. The request
// may have been processed, so only the ones that change nothing (GET, HEAD, OPTIONS) go to another replica.
#[tokio::test]
async fn a_safe_request_dropped_by_a_replica_is_replayed_on_another_one() {
    let (a, b) = (Backend::start_dropping().await, Backend::start("b").await);
    let gw = gateway(&[&a, &b]).await;
    for method in ["GET", "HEAD", "OPTIONS"] {
        for _ in 0..4 {
            let r = send(gw.addr, method, "/server/info/", &[], "").await;
            assert_eq!((r.status, r.header("x-backend")), (StatusCode::OK, "b"), "{method}");
        }
    }
    assert!(a.hits() > 0, "the dropping replica really was tried");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_post_dropped_by_a_replica_is_not_replayed() {
    let (a, b) = (Backend::start_dropping().await, Backend::start_dropping().await);
    let gw = gateway(&[&a, &b]).await;
    let r = send(gw.addr, "POST", "/auth/register/", &[], "once").await;
    assert_eq!(r.status, StatusCode::BAD_GATEWAY);
    assert_eq!(error_of(&r).code, "bad_gateway");
    assert_eq!(
        a.hits() + b.hits(),
        1,
        "the request may have been processed: only one replica ever saw it"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn a_dropped_safe_request_is_replayed_once_not_on_every_replica() {
    // a request that kills replicas must not be able to walk through all of them
    let replicas = [
        Backend::start_dropping().await,
        Backend::start_dropping().await,
        Backend::start_dropping().await,
    ];
    let gw = gateway(&[&replicas[0], &replicas[1], &replicas[2]]).await;
    let r = get(gw.addr, "/poison").await;
    assert_eq!(r.status, StatusCode::BAD_GATEWAY);
    assert_eq!(replicas.iter().map(Backend::hits).sum::<usize>(), 2, "the first try and one replay");
    gw.shutdown().await;
}

// The web is opened by `localhost` or a VPN address but must show the address the LAN uses for this server.
fn set_address(gw: &pindrel_gateway::server::Running, address: Option<&str>) {
    *gw.app.address.write().unwrap() = address.map(str::to_string);
}

#[tokio::test]
async fn server_info_carries_the_lan_address_and_only_there() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    set_address(&gw, Some("192.168.1.9:8086"));
    let r = get(gw.addr, "/server/info/").await;
    assert_eq!(
        r.header("x-pindrel-address"),
        "192.168.1.9:8086",
        "the gateway's value, not the replica's 6.6.6.6:1"
    );
    for (method, path) in [
        ("HEAD", "/server/info/"),
        ("POST", "/server/info/"),
        ("GET", "/server/info"),
        ("GET", "/auth/me/"),
        ("GET", "/"),
    ] {
        let r = send(gw.addr, method, path, &[], "").await;
        assert_eq!(r.header("x-pindrel-address"), "", "{method} {path}");
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn without_a_known_lan_address_the_header_is_absent_and_a_replicas_one_is_dropped() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    set_address(&gw, None);
    let r = get(gw.addr, "/server/info/").await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.header("x-pindrel-address"), "");
    gw.shutdown().await;
}

#[tokio::test]
async fn requests_through_a_declared_proxy_never_get_the_private_address() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "x-forwarded-for").await;
    set_address(&gw, Some("192.168.1.9:8086"));
    let r = send(gw.addr, "GET", "/server/info/", &[("x-forwarded-for", "203.0.113.7")], "").await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.header("x-pindrel-address"), "", "the client may be anywhere on the internet");
    gw.shutdown().await;
}

#[tokio::test]
async fn server_info_carries_the_id_of_this_server_also_through_a_tunnel_and_only_there() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let id = gw.app.registry.id().to_string();
    assert_eq!(id.len(), 32);
    assert_eq!(get(gw.addr, "/server/info/").await.header("x-pindrel-id"), id);
    for (method, path) in [("POST", "/server/info/"), ("GET", "/server/info"), ("GET", "/auth/me/")] {
        assert_eq!(
            send(gw.addr, method, path, &[], "").await.header("x-pindrel-id"),
            "",
            "{method} {path}"
        );
    }
    // a client cannot make the gateway repeat an id of its own choosing
    let r = send(gw.addr, "GET", "/server/info/", &[("x-pindrel-id", "evil")], "").await;
    assert_eq!(r.header("x-pindrel-id"), id);
    let tunnel = behind_proxy(&a, "x-forwarded-for").await;
    let r = send(tunnel.addr, "GET", "/server/info/", &[("x-forwarded-for", "203.0.113.7")], "").await;
    assert_eq!(r.header("x-pindrel-id"), tunnel.app.registry.id(), "the id is not private");
    assert_ne!(tunnel.app.registry.id(), id, "each gateway without a file has its own");
    gw.shutdown().await;
    tunnel.shutdown().await;
}

#[tokio::test]
async fn server_info_may_be_read_from_another_origin_and_nothing_else_may() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let r = send(gw.addr, "GET", "/server/info/", &[("origin", "http://10.0.0.7:8095")], "").await;
    assert_eq!(r.header("access-control-allow-origin"), "*");
    assert_eq!(r.header("access-control-expose-headers"), "x-pindrel-id");
    for (method, path) in [
        ("POST", "/server/info/"),
        ("GET", "/server/info"),
        ("GET", "/auth/me/"),
        ("GET", "/server/discover/"),
    ] {
        let r = send(gw.addr, method, path, &[("origin", "http://evil.example")], "").await;
        assert_eq!(r.header("access-control-allow-origin"), "", "{method} {path}");
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn the_id_is_the_same_after_a_restart_when_there_is_a_file() {
    let a = Backend::start("a").await;
    let file = std::env::temp_dir().join(format!("pindrel-gw-id-{}", std::process::id()));
    let _ = std::fs::remove_file(&file);
    let mut ids = Vec::new();
    for _ in 0..2 {
        let f = file.clone();
        let gw = gateway_with(&[&a], move |c| c.server_id_file = Some(f)).await;
        ids.push(get(gw.addr, "/server/info/").await.header("x-pindrel-id").to_string());
        gw.shutdown().await;
    }
    assert_eq!(ids[0], ids[1]);
    assert_eq!(ids[0].len(), 32);
    let _ = std::fs::remove_file(&file);
}

#[tokio::test]
async fn without_any_replica_the_answer_is_a_protobuf_502() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    a.kill();
    time::sleep(Duration::from_millis(100)).await;
    let r = get(gw.addr, "/x").await;
    assert_eq!(r.status, StatusCode::BAD_GATEWAY);
    assert_eq!(r.header("content-type"), "application/x-protobuf");
    assert_eq!(error_of(&r).code, "bad_gateway");
    gw.shutdown().await;
}

#[tokio::test]
async fn replicas_leaving_and_coming_back_are_followed_by_the_probe() {
    let port = free_port();
    let addr = format!("127.0.0.1:{port}").parse().unwrap();
    let ghost = Backend::start_on(addr, "first").await;
    let gw = gateway(&[&ghost]).await;
    assert_eq!(gw.app.pool.alive().len(), 1);
    ghost.kill();
    time::sleep(Duration::from_millis(100)).await;
    gw.app.pool.probe().await;
    assert!(gw.app.pool.alive().is_empty());
    let _back = Backend::start_on(addr, "second").await;
    gw.app.pool.probe().await;
    assert_eq!(get(gw.addr, "/x").await.header("x-backend"), "second");
    gw.shutdown().await;
}

#[tokio::test]
async fn login_and_register_have_their_own_limit_and_answer_protobuf_429() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    for path in ["/auth/login/", "/auth/register/"] {
        for i in 1..=5 {
            assert_eq!(
                send(gw.addr, "POST", path, &[], "x").await.status,
                StatusCode::OK,
                "{path} request {i} is inside the burst"
            );
        }
        let r = send(gw.addr, "POST", path, &[], "x").await;
        assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS, "{path}");
        assert_eq!(r.header("content-type"), "application/x-protobuf");
        let e = error_of(&r);
        assert_eq!(
            (e.code.as_str(), e.message.as_str()),
            ("rate_limited", "too many requests, try again later")
        );
        // login/register earn one request back every 12 s (5 per minute): the client is told how long to wait
        let wait: u64 = r.header("retry-after").parse().expect("Retry-After in whole seconds");
        assert!((1..=12).contains(&wait), "{path}: Retry-After {wait}");
    }
    // the limit is only for POST on those two paths
    assert_eq!(get(gw.addr, "/auth/login/").await.status, StatusCode::OK);
    assert_eq!(send(gw.addr, "POST", "/auth/refresh/", &[], "x").await.status, StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn the_global_limit_applies_to_everything() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let mut ok = 0;
    for _ in 0..30 {
        if get(gw.addr, "/x").await.status == StatusCode::OK {
            ok += 1;
        }
    }
    assert!((20..=22).contains(&ok), "burst of 20 (+ a refill or two while running), got {ok}");
    assert_eq!(
        get(gw.addr, "/server/discover/").await.status,
        StatusCode::TOO_MANY_REQUESTS,
        "discover is limited too"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn rate_limiting_can_be_turned_off() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.rate_limit = false).await;
    for _ in 0..40 {
        assert_eq!(send(gw.addr, "POST", "/auth/login/", &[], "x").await.status, StatusCode::OK);
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn discover_lists_the_other_servers_as_protobuf() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let empty = get(gw.addr, "/server/discover/").await;
    assert_eq!(
        (empty.status, empty.header("content-type"), empty.header("cache-control")),
        (StatusCode::OK, "application/x-protobuf", "no-store")
    );
    assert!(DiscoveredServers::decode(empty.body.clone()).unwrap().servers.is_empty());

    gw.app.registry.upsert(
        "z".into(),
        Server {
            name: "Zeta".into(),
            host: "zeta".into(),
            id: String::new(),
            ips: vec!["192.168.1.9".into()],
            port: 8080,
            tls_port: 0,
        },
    );
    gw.app.registry.upsert(
        "a".into(),
        Server {
            name: "Alfa".into(),
            host: "alfa".into(),
            id: String::new(),
            ips: vec!["192.168.1.8".into(), "10.0.0.8".into()],
            port: 39215,
            tls_port: 0,
        },
    );
    let list = DiscoveredServers::decode(get(gw.addr, "/server/discover/").await.body)
        .unwrap()
        .servers;
    assert_eq!(list.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["Alfa", "Zeta"]);
    assert_eq!(
        (list[0].port, list[0].addresses.clone(), list[0].host.as_str()),
        (39215, vec!["192.168.1.8".to_string(), "10.0.0.8".to_string()], "alfa")
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn discover_is_answered_by_the_gateway_not_the_replicas() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    assert_eq!(get(gw.addr, "/server/discover/").await.header("x-backend"), "");
    // other methods on that path are the API's business
    assert_eq!(send(gw.addr, "POST", "/server/discover/", &[], "").await.header("x-backend"), "a");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_body_over_the_limit_is_a_protobuf_413_and_never_reaches_a_replica() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.max_body = 16).await;
    assert_eq!(send(gw.addr, "POST", "/x", &[], "0123456789abcdef").await.status, StatusCode::OK);
    let r = send(gw.addr, "POST", "/x", &[], "0123456789abcdefX").await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(error_of(&r).code, "payload_too_large");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_slow_replica_becomes_a_protobuf_504() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.upstream_timeout = Duration::from_millis(200)).await;
    let r = get(gw.addr, "/slow").await;
    assert_eq!(r.status, StatusCode::GATEWAY_TIMEOUT);
    assert_eq!(error_of(&r).code, "gateway_timeout");
    assert_eq!(
        gw.app.pool.alive().len(),
        1,
        "slow is not dead: no failover that could run a POST twice"
    );
    gw.shutdown().await;
}

/// Reads until the peer closes or `limit` passes; returns what arrived.
async fn read_until_closed(s: &mut TcpStream, limit: Duration) -> Option<Vec<u8>> {
    let mut all = Vec::new();
    let mut buf = [0u8; 1024];
    let end = time::Instant::now() + limit;
    loop {
        match time::timeout_at(end, s.read(&mut buf)).await {
            Err(_) => return None, // still open
            Ok(Ok(0)) | Ok(Err(_)) => return Some(all),
            Ok(Ok(n)) => all.extend_from_slice(&buf[..n]),
        }
    }
}

#[tokio::test]
async fn a_client_that_never_finishes_its_headers_is_dropped() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.header_timeout = Duration::from_millis(300)).await;
    let mut s = TcpStream::connect(gw.addr).await.unwrap();
    s.write_all(b"GET /x HTTP/1.1\r\nHost: x\r\nX-Slow: ").await.unwrap(); // never ends the header block
    assert!(
        read_until_closed(&mut s, Duration::from_secs(3)).await.is_some(),
        "the gateway must close the connection"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn the_connection_limit_holds_new_clients_until_one_leaves() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| c.max_connections = 2).await;
    let (c1, _c2) = (
        TcpStream::connect(gw.addr).await.unwrap(),
        TcpStream::connect(gw.addr).await.unwrap(),
    );
    let mut c3 = TcpStream::connect(gw.addr).await.unwrap(); // the kernel accepts it, the gateway does not serve it yet
    c3.write_all(b"GET /x HTTP/1.1\r\nHost: x\r\n\r\n").await.unwrap();
    assert!(
        read_until_closed(&mut c3, Duration::from_millis(500)).await.is_none(),
        "no answer while 2 connections are open"
    );
    drop(c1);
    let mut buf = [0u8; 12];
    time::timeout(Duration::from_secs(3), c3.read_exact(&mut buf))
        .await
        .expect("served once a slot is free")
        .unwrap();
    assert!(buf.starts_with(b"HTTP/1.1 200"), "{}", String::from_utf8_lossy(&buf));
    gw.shutdown().await;
}

#[tokio::test]
async fn one_client_cannot_hold_all_the_connections_and_gets_its_slots_back() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| {
        c.max_connections = 100;
        c.max_connections_per_ip = 3;
    })
    .await;
    // a flood of connections that stay silent: only the first 3 are kept, the others are closed at once
    let mut held = Vec::new();
    let mut refused = 0;
    for _ in 0..20 {
        let mut s = TcpStream::connect(gw.addr).await.unwrap();
        match read_until_closed(&mut s, Duration::from_millis(100)).await {
            None => held.push(s),
            Some(_) => refused += 1,
        }
    }
    assert_eq!((held.len(), refused), (3, 17));
    // while they are held, this address gets no more; once one leaves, a request is served again
    drop(held.pop());
    let mut ok = false;
    for _ in 0..20 {
        let mut s = TcpStream::connect(gw.addr).await.unwrap();
        s.write_all(b"GET /x HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
            .await
            .unwrap();
        if read_until_closed(&mut s, Duration::from_secs(1))
            .await
            .is_some_and(|r| r.starts_with(b"HTTP/1.1 200"))
        {
            ok = true;
            break;
        }
        time::sleep(Duration::from_millis(50)).await;
    }
    assert!(ok, "the freed slot is usable");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_declared_proxy_is_not_held_to_the_per_client_connection_limit() {
    let a = Backend::start("a").await;
    let gw = gateway_with(&[&a], |c| {
        c.max_connections_per_ip = 1;
        c.client_ip = ClientIp::new(parse_trusted("127.0.0.1").unwrap(), "x-forwarded-for").unwrap();
    })
    .await;
    let mut held = Vec::new();
    for _ in 0..5 {
        let mut s = TcpStream::connect(gw.addr).await.unwrap();
        s.write_all(b"GET /x HTTP/1.1\r\nHost: x\r\n\r\n").await.unwrap();
        let mut buf = [0u8; 12];
        time::timeout(Duration::from_secs(2), s.read_exact(&mut buf))
            .await
            .unwrap()
            .unwrap();
        assert!(buf.starts_with(b"HTTP/1.1 200"));
        held.push(s);
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn the_map_of_the_lan_is_not_served_through_a_tunnel() {
    let a = Backend::start("a").await;
    let server = Server {
        name: "Casa".into(),
        host: "casa".into(),
        id: String::new(),
        ips: vec!["192.168.1.9".into()],
        port: 8080,
        tls_port: 0,
    };
    let direct = gateway(&[&a]).await;
    direct.app.registry.upsert("c".into(), server.clone());
    assert_eq!(get(direct.addr, "/server/discover/").await.status, StatusCode::OK);

    let tunnel = behind_proxy(&a, "x-forwarded-for").await;
    tunnel.app.registry.upsert("c".into(), server);
    let r = send(tunnel.addr, "GET", "/server/discover/", &[("x-forwarded-for", "203.0.113.7")], "").await;
    assert_eq!(r.status, StatusCode::NOT_FOUND);
    assert!(!String::from_utf8_lossy(&r.body).contains("192.168"));
    direct.shutdown().await;
    tunnel.shutdown().await;
}

#[tokio::test]
async fn shutdown_lets_in_flight_requests_finish_and_stops_accepting() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    let addr = gw.addr;
    let in_flight = tokio::spawn(async move { get(addr, "/slow").await });
    time::sleep(Duration::from_millis(200)).await;
    let t = time::Instant::now();
    gw.shutdown().await;
    assert!(
        t.elapsed() >= Duration::from_millis(400),
        "shutdown must wait for the request in flight (took {:?})",
        t.elapsed()
    );
    assert_eq!(
        in_flight.await.unwrap().status,
        StatusCode::OK,
        "the request that was running must complete"
    );
    assert!(t.elapsed() < Duration::from_secs(4));
    assert!(TcpStream::connect(addr).await.is_err(), "nothing listens after shutdown");
}

#[tokio::test]
async fn rate_limit_state_is_tracked_per_client() {
    // the gateway sees 127.0.0.1 here; per-prefix (IPv6) sharing is covered by the limiter unit tests
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    assert_eq!(gw.app.limiters.login.tracked(), 0);
    send(gw.addr, "POST", "/auth/login/", &[], "x").await;
    assert_eq!(gw.app.limiters.login.tracked(), 1);
    gw.shutdown().await;
}

// ---- the client behind a trusted proxy ----

use pindrel_gateway::clientip::{parse_trusted, ClientIp};

/// A gateway that trusts the test client's own address (127.0.0.1) as a proxy, reading `header`.
async fn behind_proxy(a: &Backend, header: &str) -> pindrel_gateway::server::Running {
    let header = header.to_string();
    gateway_with(&[a], move |c| {
        c.client_ip = ClientIp::new(parse_trusted("127.0.0.1").unwrap(), &header).unwrap();
    })
    .await
}

async fn login_as(gw: &pindrel_gateway::server::Running, headers: &[(&str, &str)]) -> StatusCode {
    send(gw.addr, "POST", "/auth/login/", headers, "x").await.status
}

#[tokio::test]
async fn without_a_trusted_proxy_a_client_cannot_pick_its_address() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    // six different "addresses" from one real client: they all land in the same bucket
    for i in 1..=5 {
        let xff = format!("203.0.113.{i}");
        assert_eq!(login_as(&gw, &[("x-forwarded-for", &xff)]).await, StatusCode::OK);
    }
    assert_eq!(
        login_as(&gw, &[("x-forwarded-for", "203.0.113.99"), ("cf-connecting-ip", "203.0.113.98")]).await,
        StatusCode::TOO_MANY_REQUESTS
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn behind_a_trusted_proxy_each_client_has_its_own_limit() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "x-forwarded-for").await;
    for client in ["198.51.100.1", "198.51.100.2"] {
        for _ in 0..5 {
            assert_eq!(login_as(&gw, &[("x-forwarded-for", client)]).await, StatusCode::OK, "{client}");
        }
        assert_eq!(
            login_as(&gw, &[("x-forwarded-for", client)]).await,
            StatusCode::TOO_MANY_REQUESTS,
            "{client}"
        );
    }
    // the proxy's own address (no header) is one more client, not everybody
    assert_eq!(login_as(&gw, &[]).await, StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn a_forged_left_side_does_not_buy_a_new_bucket() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "x-forwarded-for").await;
    // the real client is the right-most address (what the proxy appended); the lies on the left change nothing
    for i in 1..=5 {
        let xff = format!("10.9.9.{i}, 198.51.100.7");
        assert_eq!(login_as(&gw, &[("x-forwarded-for", &xff)]).await, StatusCode::OK);
    }
    assert_eq!(
        login_as(&gw, &[("x-forwarded-for", "10.9.9.99, 198.51.100.7")]).await,
        StatusCode::TOO_MANY_REQUESTS
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn only_the_configured_header_is_trusted() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "cf-connecting-ip").await;
    for i in 1..=5 {
        let lie = format!("203.0.113.{i}");
        // X-Forwarded-For / Forwarded / X-Real-IP are not the configured header: ignored, the peer is the client
        let h = [
            ("x-forwarded-for", lie.as_str()),
            ("forwarded", "for=203.0.113.9"),
            ("x-real-ip", "203.0.113.8"),
        ];
        assert_eq!(login_as(&gw, &h).await, StatusCode::OK);
    }
    assert_eq!(
        login_as(&gw, &[("x-forwarded-for", "203.0.113.50")]).await,
        StatusCode::TOO_MANY_REQUESTS
    );
    // while the configured one is believed
    assert_eq!(login_as(&gw, &[("cf-connecting-ip", "198.51.100.5")]).await, StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn the_replica_sees_the_real_client_and_none_of_the_other_claims() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "x-forwarded-for").await;
    let r = send(
        gw.addr,
        "GET",
        "/x",
        &[
            ("x-forwarded-for", "9.9.9.9, 198.51.100.7"),
            ("forwarded", "for=9.9.9.9"),
            ("x-real-ip", "9.9.9.9"),
            ("cf-connecting-ip", "9.9.9.9"),
            ("true-client-ip", "9.9.9.9"),
        ],
        "",
    )
    .await;
    assert_eq!(r.header("x-seen-xff"), "198.51.100.7");
    assert_eq!(r.header("x-seen-claims"), "", "the API must not see headers that claim an address");
    gw.shutdown().await;
}

#[tokio::test]
async fn garbage_in_the_header_falls_back_to_the_proxy_and_never_breaks_a_request() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "x-forwarded-for").await;
    for bad in ["", "unknown", "1.2.3.4, _hidden", &"9".repeat(5000), "[::1"] {
        let r = send(gw.addr, "GET", "/x", &[("x-forwarded-for", bad)], "").await;
        assert_eq!(r.status, StatusCode::OK, "{bad:.20}");
        assert_eq!(
            r.header("x-seen-xff"),
            "127.0.0.1",
            "the proxy is the client when the header is useless"
        );
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn many_clients_through_one_proxy_do_not_share_the_global_limit() {
    let a = Backend::start("a").await;
    let gw = behind_proxy(&a, "x-forwarded-for").await;
    // 30 different clients, 5 requests each: 150 requests in a second would be far over 20 for one address
    let mut ok = 0;
    for c in 0..30 {
        let client = format!("198.51.100.{}", c + 1);
        for _ in 0..5 {
            if send(gw.addr, "GET", "/x", &[("x-forwarded-for", &client)], "").await.status == StatusCode::OK {
                ok += 1;
            }
        }
    }
    assert_eq!(ok, 150);
    gw.shutdown().await;
}
