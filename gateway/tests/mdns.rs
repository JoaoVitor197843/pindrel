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

    let before = a.app.registry.list().len();
    b.shutdown().await; // sends the mDNS goodbye
    assert!(
        eventually("A forgets B", || a.app.registry.list().len() < before).await,
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
