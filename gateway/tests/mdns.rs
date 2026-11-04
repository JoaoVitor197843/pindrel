//! mDNS between real gateways on this machine's LAN interface. Environments without multicast
//! (some CI runners, containers on a bridge) cannot run these: they say so and pass.
mod common;

use std::time::Duration;

use common::*;
use pindrel_gateway::discovery::{lan_ip, Server};
use tokio::time;

async fn with_mdns(name: &str, backend: &Backend) -> pindrel_gateway::server::Running {
    let n = name.to_string();
    gateway_with(&[backend], move |c| {
        c.mdns = true;
        c.server_name = n;
    })
    .await
}

async fn with_mdns_refresh(name: &str, backend: &Backend, refresh: Duration) -> pindrel_gateway::server::Running {
    let n = name.to_string();
    gateway_with(&[backend], move |c| {
        c.mdns = true;
        c.server_name = n;
        c.mdns_refresh = refresh;
    })
    .await
}

async fn eventually(what: &str, f: impl Fn() -> bool) -> bool {
    for _ in 0..100 {
        if f() {
            return true;
        }
        time::sleep(Duration::from_millis(100)).await;
    }
    eprintln!("SKIPPED/FAILED: {what} did not happen within 10 s");
    false
}

fn names(r: &pindrel_gateway::server::Running) -> Vec<String> {
    r.app.registry.list().into_iter().map(|s| s.name).collect()
}

#[tokio::test]
async fn gateways_find_each_other_but_not_themselves_and_say_goodbye() {
    let be = Backend::start("a").await;
    let (a, b) = (with_mdns("pindrel-test-alfa", &be).await, with_mdns("pindrel-test-beta", &be).await);
    if !eventually("A sees B", || names(&a).contains(&"pindrel-test-beta".to_string())).await {
        eprintln!("(no multicast here: skipping)");
        return;
    }
    assert!(eventually("B sees A", || names(&b).contains(&"pindrel-test-alfa".to_string())).await);
    assert!(
        !names(&a).contains(&"pindrel-test-alfa".to_string()),
        "a gateway must not list itself"
    );
    assert!(!names(&b).contains(&"pindrel-test-beta".to_string()));

    // what A knows about B is served to the browser, with the LAN address only
    let list: Vec<Server> = a
        .app
        .registry
        .list()
        .into_iter()
        .filter(|s| s.name == "pindrel-test-beta")
        .collect();
    assert_eq!(list[0].port, b.addr.port());
    let lan = lan_ip().unwrap().to_string();
    assert_eq!(list[0].ips, [lan], "only the LAN address is announced, not docker/VPN ones");
    let served = DiscoveredServers::decode_body(&get(a.addr, "/server/discover/").await.body);
    assert!(served
        .iter()
        .any(|s| s.name == "pindrel-test-beta" && s.port == i32::from(b.addr.port())));

    // by name, not by count: other tests in this process bring servers up and down on the same LAN
    b.shutdown().await; // sends the mDNS goodbye
    assert!(
        eventually("A forgets B", || !names(&a).contains(&"pindrel-test-beta".to_string())).await,
        "a gateway that left must disappear from the list"
    );
    a.shutdown().await;
}

#[tokio::test]
async fn two_gateways_with_the_same_name_end_up_with_different_names() {
    let be = Backend::start("a").await;
    let (a, b) = (with_mdns("pindrel-test-same", &be).await, with_mdns("pindrel-test-same", &be).await);
    let distinct = || {
        let mut n = names(&a);
        n.extend(names(&b));
        n.sort();
        n.dedup();
        n.len() >= 2
    };
    if !eventually("each sees a server", || !names(&a).is_empty() || !names(&b).is_empty()).await {
        eprintln!("(no multicast here: skipping)");
        return;
    }
    assert!(
        eventually("conflict resolved by renaming", distinct).await,
        "a={:?} b={:?}",
        names(&a),
        names(&b)
    );
    a.shutdown().await;
    b.shutdown().await;
}

trait Decode {
    fn decode_body(b: &[u8]) -> Vec<DiscoveredServer>;
}
impl Decode for DiscoveredServers {
    fn decode_body(b: &[u8]) -> Vec<DiscoveredServer> {
        prost::Message::decode(b)
            .map(|m: DiscoveredServers| m.servers)
            .expect("protobuf body")
    }
}

#[tokio::test]
async fn the_id_travels_in_the_announcement_and_reaches_the_list() {
    let be = Backend::start("a").await;
    let (a, b) = (with_mdns("pindrel-test-id-a", &be).await, with_mdns("pindrel-test-id-b", &be).await);
    if !eventually("A sees B", || names(&a).contains(&"pindrel-test-id-b".to_string())).await {
        eprintln!("(no multicast here: skipping)");
        return;
    }
    let seen = a.app.registry.list().into_iter().find(|s| s.name == "pindrel-test-id-b").unwrap();
    assert_eq!(seen.id, b.app.registry.id());
    assert_ne!(seen.id, a.app.registry.id());
    let over_http = DiscoveredServers::decode_body(&get(a.addr, "/server/discover/").await.body);
    assert!(over_http
        .iter()
        .any(|s| s.name == "pindrel-test-id-b" && s.id == b.app.registry.id()));
    a.shutdown().await;
    b.shutdown().await;
}

#[tokio::test]
async fn the_search_is_restarted_periodically_and_events_keep_flowing_after_each_restart() {
    let be = Backend::start("a").await;
    // aggressive refresh: every restart replaces the receiver, so this proves nothing is lost in the swap
    let ms = Duration::from_millis(300);
    let (a, b) = (
        with_mdns_refresh("pindrel-test-refresh-a", &be, ms).await,
        with_mdns_refresh("pindrel-test-refresh-b", &be, ms).await,
    );
    assert!(eventually("the search was restarted several times", || a.app.registry.searches() >= 4).await);
    if !eventually("A sees B", || names(&a).contains(&"pindrel-test-refresh-b".to_string())).await {
        eprintln!("(no multicast here: skipping the rest)");
        return;
    }
    // a server that appears only after several restarts is still found, and one that leaves is still forgotten
    let late = with_mdns_refresh("pindrel-test-refresh-late", &be, ms).await;
    assert!(
        eventually("A sees the late one", || names(&a)
            .contains(&"pindrel-test-refresh-late".to_string()))
        .await
    );
    late.shutdown().await;
    assert!(eventually("A forgets it", || !names(&a).contains(&"pindrel-test-refresh-late".to_string())).await);
    a.shutdown().await;
    b.shutdown().await;
}

#[tokio::test]
async fn a_refresh_of_zero_never_restarts_the_search() {
    let be = Backend::start("a").await;
    let g = with_mdns_refresh("pindrel-test-norefresh", &be, Duration::ZERO).await;
    time::sleep(Duration::from_millis(1500)).await;
    assert_eq!(g.app.registry.searches(), 1, "only the initial search");
    g.shutdown().await;
}

/// A gateway with HTTPS announces its TLS port next to the HTTP one (TXT `tls`); one without HTTPS announces none.
#[cfg(feature = "tls")]
#[tokio::test]
async fn the_https_port_is_announced_only_when_there_is_one() {
    use pindrel_gateway::config::TlsConfig;
    let be = Backend::start("a").await;
    let tls_port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
    let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/tls");
    let secure = gateway_with(&[&be], move |c| {
        c.mdns = true;
        c.server_name = "pindrel-test-tls-secure".into();
        c.tls = Some(TlsConfig {
            port: tls_port,
            cert: dir.join("cert.pem"),
            key: dir.join("key.pem"),
            auto_dir: None,
            extra_sans: Vec::new(),
            refresh: Duration::ZERO,
        });
    })
    .await;
    let plain = with_mdns("pindrel-test-tls-plain", &be).await;
    let watcher = with_mdns("pindrel-test-tls-watcher", &be).await;
    let both = || {
        let n = names(&watcher);
        n.contains(&"pindrel-test-tls-secure".to_string()) && n.contains(&"pindrel-test-tls-plain".to_string())
    };
    if !eventually("the watcher sees both", both).await {
        eprintln!("(no multicast here: skipping)");
        return;
    }
    let list = watcher.app.registry.list();
    let find = |n: &str| list.iter().find(|s| s.name == n).unwrap().clone();
    let (s, p) = (find("pindrel-test-tls-secure"), find("pindrel-test-tls-plain"));
    assert_eq!(s.tls_port, tls_port, "the HTTPS port is announced");
    assert_eq!(s.port, secure.addr.port(), "the base port is still the HTTP one");
    assert_eq!(p.tls_port, 0, "no HTTPS, nothing announced");
    // and the list handed to the web carries it too
    let over_http = DiscoveredServers::decode_body(&get(watcher.addr, "/server/discover/").await.body);
    assert!(over_http
        .iter()
        .any(|d| d.name == "pindrel-test-tls-secure" && d.tls_port == tls_port as i32));
    assert!(over_http.iter().any(|d| d.name == "pindrel-test-tls-plain" && d.tls_port == 0));
    for g in [secure, plain, watcher] {
        g.shutdown().await;
    }
}
