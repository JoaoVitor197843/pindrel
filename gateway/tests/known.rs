//! The memory of servers seen before: kept while they answer, tried again on our own, saved between runs,
//! and never used to make the gateway connect outside its own subnet.
mod common;

use std::{
    net::Ipv4Addr,
    path::PathBuf,
    sync::atomic::{AtomicU32, Ordering},
    time::Duration,
};

use common::*;
use plany_gateway::{
    discovery::{Lan, Server},
    proto,
    server::{self, Running},
};
use tokio::time;

static N: AtomicU32 = AtomicU32::new(0);

fn temp_file() -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "plany-known-test-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("known")
}

/// A local network that contains loopback, so that fake servers on 127.0.0.1 may be tried.
fn loopback_lan() -> Lan {
    Lan::new(Ipv4Addr::new(127, 0, 0, 2), Ipv4Addr::new(255, 0, 0, 0))
}

async fn gw(file: Option<PathBuf>, interval: Duration, lan: Lan) -> Running {
    let mut cfg = plany_gateway::config::Config::new(vec!["127.0.0.1:1".parse().unwrap()]);
    cfg.port = 0;
    cfg.mdns = false; // the registry is fed by hand: what the network announced
    cfg.known_file = file;
    cfg.known_interval = interval;
    server::start_with(cfg, Some(lan)).await.unwrap()
}

fn other(port: u16) -> Server {
    Server {
        name: "Other".into(),
        host: "other".into(),
        ips: vec!["127.0.0.1".into()],
        port,
    }
}

async fn eventually(what: &str, mut f: impl FnMut() -> bool) {
    for _ in 0..80 {
        if f() {
            return;
        }
        time::sleep(Duration::from_millis(50)).await;
    }
    panic!("{what}: did not happen within 4 s");
}

fn listed(g: &Running) -> Vec<String> {
    g.app.registry.list().into_iter().map(|s| s.name).collect()
}

#[tokio::test]
async fn a_server_that_stops_being_announced_stays_listed_while_it_answers_and_leaves_when_it_does_not() {
    let backend = Backend::start("other").await;
    let port = backend.addr.port();
    let file = temp_file();
    // a check every hour: only the "stopped being announced" wake-up can make this pass in time
    let g = gw(Some(file.clone()), Duration::from_secs(3600), loopback_lan()).await;

    g.app.registry.upsert("other-full".into(), other(port));
    assert_eq!(listed(&g), ["Other"]);
    g.app.registry.remove("other-full"); // e.g. the refresh of its announcement was lost on Wi-Fi
    eventually("listed again after being tried", || listed(&g) == ["Other"]).await;
    let served = get(g.addr, "/server/discover/").await;
    assert_eq!(
        <DiscoveredServers as prost::Message>::decode(served.body).unwrap().servers[0].name,
        "Other"
    );

    // it really goes away: no announcement and no answer, so it must disappear (here: the next goodbye-less check)
    backend.kill();
    time::sleep(Duration::from_millis(100)).await;
    g.app.registry.upsert("other-full".into(), other(port)); // announced once more...
    g.app.registry.remove("other-full"); // ...and lapsing again wakes the check
    eventually("forgotten once it stops answering", || listed(&g).is_empty()).await;

    // and when it comes back, we find it without any new announcement
    let _back = Backend::start_on(backend.addr, "other-again").await;
    g.app.registry.upsert("other-full".into(), other(port));
    g.app.registry.remove("other-full");
    eventually("found again by trying its address", || listed(&g) == ["Other"]).await;
    g.shutdown().await;
}

#[tokio::test]
async fn the_periodic_check_finds_a_server_that_comes_back_on_its_own() {
    let backend = Backend::start("other").await;
    let (addr, port) = (backend.addr, backend.addr.port());
    let g = gw(Some(temp_file()), Duration::from_millis(150), loopback_lan()).await;
    g.app.registry.upsert("f".into(), other(port));
    backend.kill();
    g.app.registry.remove("f");
    eventually("gone while down", || listed(&g).is_empty()).await;
    let _back = Backend::start_on(addr, "again").await; // nobody announces it again
    eventually("back in the list through the periodic check", || listed(&g) == ["Other"]).await;
    g.shutdown().await;
}

#[tokio::test]
async fn with_the_check_turned_off_a_lapsed_announcement_is_forgotten_as_before() {
    let backend = Backend::start("other").await;
    let g = gw(Some(temp_file()), Duration::ZERO, loopback_lan()).await;
    g.app.registry.upsert("f".into(), other(backend.addr.port()));
    g.app.registry.remove("f");
    time::sleep(Duration::from_millis(500)).await;
    assert!(listed(&g).is_empty());
    g.shutdown().await;
}

#[tokio::test]
async fn the_memory_is_saved_and_a_restarted_gateway_lists_the_others_at_once() {
    let backend = Backend::start("other").await;
    let file = temp_file();
    let first = gw(Some(file.clone()), Duration::from_millis(100), loopback_lan()).await;
    first.app.registry.upsert("f".into(), other(backend.addr.port()));
    eventually("saved", || {
        std::fs::read(&file)
            .ok()
            .and_then(|b| proto::parse_discovered_servers(&b))
            .is_some_and(|v| v.len() == 1)
    })
    .await;
    first.shutdown().await;
    let saved = proto::parse_discovered_servers(&std::fs::read(&file).unwrap()).unwrap();
    assert_eq!((saved[0].name.as_str(), saved[0].port), ("Other", backend.addr.port()));
    assert!(!file.with_extension("tmp").exists(), "no temporary file is left behind");

    // a new run: nothing is announced, yet the server is listed as soon as its address answered
    let second = gw(Some(file.clone()), Duration::from_millis(100), loopback_lan()).await;
    eventually("listed from the file", || listed(&second) == ["Other"]).await;

    // and if it is not there any more, it is not listed (the file only says where to look)
    backend.kill();
    eventually("not listed once it does not answer", || listed(&second).is_empty()).await;
    second.shutdown().await;
}

#[tokio::test]
async fn a_broken_or_hostile_file_is_ignored() {
    for garbage in [&b"not protobuf at all"[..], &[0xff; 64][..], &[0x0a, 0x7f][..], &[][..]] {
        let file = temp_file();
        std::fs::write(&file, garbage).unwrap();
        let g = gw(Some(file), Duration::from_millis(100), loopback_lan()).await;
        time::sleep(Duration::from_millis(300)).await;
        assert!(listed(&g).is_empty());
        assert_eq!(get(g.addr, "/server/discover/").await.status, 200);
        g.shutdown().await;
    }
}

#[tokio::test]
async fn addresses_outside_the_local_subnet_are_never_tried() {
    // a reachable server (loopback) and a "LAN" that does not contain it: the gateway must not even connect
    let backend = Backend::start("secret").await;
    let file = temp_file();
    let entries = vec![
        other(backend.addr.port()),
        Server {
            name: "Internet".into(),
            host: "x".into(),
            ips: vec!["8.8.8.8".into()],
            port: 8080,
        },
        Server {
            name: "OtherNet".into(),
            host: "x".into(),
            ips: vec!["10.9.9.9".into()],
            port: 8080,
        },
    ];
    std::fs::write(&file, proto::discovered_servers(&entries)).unwrap();
    let real_lan = Lan::new(Ipv4Addr::new(192, 168, 1, 5), Ipv4Addr::new(255, 255, 255, 0));
    let g = gw(Some(file), Duration::from_millis(100), real_lan).await;
    time::sleep(Duration::from_millis(600)).await;
    assert!(
        listed(&g).is_empty(),
        "an announcement must not turn the gateway into a port scanner: {:?}",
        listed(&g)
    );
    g.shutdown().await;
}

#[tokio::test]
async fn without_a_known_local_network_nothing_is_ever_tried() {
    let backend = Backend::start("other").await;
    let file = temp_file();
    std::fs::write(&file, proto::discovered_servers(&[other(backend.addr.port())])).unwrap();
    let mut cfg = plany_gateway::config::Config::new(vec!["127.0.0.1:1".parse().unwrap()]);
    cfg.port = 0;
    cfg.mdns = false;
    cfg.known_file = Some(file);
    cfg.known_interval = Duration::from_millis(100);
    let g = server::start_with(cfg, None).await.unwrap();
    time::sleep(Duration::from_millis(500)).await;
    assert!(listed(&g).is_empty());
    g.shutdown().await;
}
