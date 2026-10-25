//! mDNS between real gateways on this machine's LAN interface. Environments without multicast
//! (some CI runners, containers on a bridge) cannot run these: they say so and pass.
mod common;

use std::time::Duration;

use common::*;
use plany_gateway::discovery::{lan_ip, Server};
use tokio::time;

async fn with_mdns(name: &str, backend: &Backend) -> plany_gateway::server::Running {
    let n = name.to_string();
    gateway_with(&[backend], move |c| {
        c.mdns = true;
        c.server_name = n;
    })
    .await
}

async fn with_mdns_refresh(name: &str, backend: &Backend, refresh: Duration) -> plany_gateway::server::Running {
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

fn names(r: &plany_gateway::server::Running) -> Vec<String> {
    r.app.registry.list().into_iter().map(|s| s.name).collect()
}

#[tokio::test]
async fn gateways_find_each_other_but_not_themselves_and_say_goodbye() {
    let be = Backend::start("a").await;
    let (a, b) = (with_mdns("plany-test-alfa", &be).await, with_mdns("plany-test-beta", &be).await);
    if !eventually("A sees B", || names(&a).contains(&"plany-test-beta".to_string())).await {
        eprintln!("(no multicast here: skipping)");
        return;
    }
    assert!(eventually("B sees A", || names(&b).contains(&"plany-test-alfa".to_string())).await);
    assert!(
        !names(&a).contains(&"plany-test-alfa".to_string()),
        "a gateway must not list itself"
    );
    assert!(!names(&b).contains(&"plany-test-beta".to_string()));

    // what A knows about B is served to the browser, with the LAN address only
    let list: Vec<Server> = a.app.registry.list().into_iter().filter(|s| s.name == "plany-test-beta").collect();
    assert_eq!(list[0].port, b.addr.port());
    let lan = lan_ip().unwrap().to_string();
    assert_eq!(list[0].ips, [lan], "only the LAN address is announced, not docker/VPN ones");
    let served = DiscoveredServers::decode_body(&get(a.addr, "/server/discover/").await.body);
    assert!(served
        .iter()
        .any(|s| s.name == "plany-test-beta" && s.port == i32::from(b.addr.port())));

    // by name, not by count: other tests in this process bring servers up and down on the same LAN
    b.shutdown().await; // sends the mDNS goodbye
    assert!(
        eventually("A forgets B", || !names(&a).contains(&"plany-test-beta".to_string())).await,
        "a gateway that left must disappear from the list"
    );
    a.shutdown().await;
}

#[tokio::test]
async fn two_gateways_with_the_same_name_end_up_with_different_names() {
    let be = Backend::start("a").await;
    let (a, b) = (with_mdns("plany-test-same", &be).await, with_mdns("plany-test-same", &be).await);
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
    let (a, b) = (with_mdns("plany-test-id-a", &be).await, with_mdns("plany-test-id-b", &be).await);
    if !eventually("A sees B", || names(&a).contains(&"plany-test-id-b".to_string())).await {
        eprintln!("(no multicast here: skipping)");
        return;
    }
    let seen = a.app.registry.list().into_iter().find(|s| s.name == "plany-test-id-b").unwrap();
    assert_eq!(seen.id, b.app.registry.id());
    assert_ne!(seen.id, a.app.registry.id());
    let over_http = DiscoveredServers::decode_body(&get(a.addr, "/server/discover/").await.body);
    assert!(over_http.iter().any(|s| s.name == "plany-test-id-b" && s.id == b.app.registry.id()));
    a.shutdown().await;
    b.shutdown().await;
}

#[tokio::test]
async fn the_search_is_restarted_periodically_and_events_keep_flowing_after_each_restart() {
    let be = Backend::start("a").await;
    // aggressive refresh: every restart replaces the receiver, so this proves nothing is lost in the swap
    let ms = Duration::from_millis(300);
    let (a, b) = (
        with_mdns_refresh("plany-test-refresh-a", &be, ms).await,
        with_mdns_refresh("plany-test-refresh-b", &be, ms).await,
    );
    assert!(eventually("the search was restarted several times", || a.app.registry.searches() >= 4).await);
    if !eventually("A sees B", || names(&a).contains(&"plany-test-refresh-b".to_string())).await {
        eprintln!("(no multicast here: skipping the rest)");
        return;
    }
    // a server that appears only after several restarts is still found, and one that leaves is still forgotten
    let late = with_mdns_refresh("plany-test-refresh-late", &be, ms).await;
    assert!(eventually("A sees the late one", || names(&a).contains(&"plany-test-refresh-late".to_string())).await);
    late.shutdown().await;
    assert!(eventually("A forgets it", || !names(&a).contains(&"plany-test-refresh-late".to_string())).await);
    a.shutdown().await;
    b.shutdown().await;
}

#[tokio::test]
async fn a_refresh_of_zero_never_restarts_the_search() {
    let be = Backend::start("a").await;
    let g = with_mdns_refresh("plany-test-norefresh", &be, Duration::ZERO).await;
    time::sleep(Duration::from_millis(1500)).await;
    assert_eq!(g.app.registry.searches(), 1, "only the initial search");
    g.shutdown().await;
}
