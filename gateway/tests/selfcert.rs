//! The gateway's own certificate authority (`TLS_AUTO`): creation, persistence, renewal without a restart, and what a client
//! that trusts only that CA can and cannot do.
#![cfg(feature = "selfcert")]
mod common;

use std::{fs, path::PathBuf, sync::Arc, time::Duration};

use common::*;
use pindrel_gateway::config::TlsConfig;
use rustls::{pki_types::ServerName, ClientConfig, RootCertStore};
use rustls_pki_types::{pem::PemObject, CertificateDer};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time,
};
use tokio_rustls::TlsConnector;

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}

fn auto(port: u16, dir: &std::path::Path, refresh: Duration) -> TlsConfig {
    TlsConfig {
        port,
        cert: PathBuf::new(),
        key: PathBuf::new(),
        auto_dir: Some(dir.to_path_buf()),
        extra_sans: Vec::new(),
        refresh,
        http3: false,
    }
}

fn client_trusting(ca_pem: &str) -> TlsConnector {
    let mut roots = RootCertStore::empty();
    for c in CertificateDer::pem_slice_iter(ca_pem.as_bytes()) {
        roots.add(c.unwrap()).unwrap();
    }
    let cfg = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
    TlsConnector::from(Arc::new(cfg))
}

/// Handshake with `name` as the host; returns the server certificate it presented.
async fn handshake(port: u16, ca_pem: &str, name: &str) -> std::io::Result<Vec<u8>> {
    let tcp = TcpStream::connect(("127.0.0.1", port)).await?;
    let tls = client_trusting(ca_pem)
        .connect(ServerName::try_from(name.to_string()).unwrap(), tcp)
        .await?;
    Ok(tls.get_ref().1.peer_certificates().unwrap()[0].to_vec())
}

async fn fetch_ca(addr: std::net::SocketAddr) -> (String, Reply) {
    let r = get(addr, "/server/ca.pem").await;
    (String::from_utf8(r.body.clone().into()).unwrap(), r)
}

fn tmp() -> tempdir::Dir {
    tempdir::Dir::new()
}

/// A tiny temp directory (the tests have no other need for a crate).
mod tempdir {
    use std::path::{Path, PathBuf};
    pub struct Dir(PathBuf);
    impl Dir {
        pub fn new() -> Self {
            let p = std::env::temp_dir().join(format!("pindrel-selfcert-{}-{}", std::process::id(), super::free_port()));
            std::fs::create_dir_all(&p).unwrap();
            Dir(p)
        }
        pub fn path(&self) -> &Path {
            &self.0
        }
    }
    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

#[tokio::test]
async fn first_start_creates_the_ca_and_a_client_that_trusts_only_that_ca_connects() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let (ca_pem, r) = fetch_ca(gw.addr).await;
    assert_eq!(r.header("content-type"), "application/x-x509-ca-cert");
    assert!(ca_pem.starts_with("-----BEGIN CERTIFICATE-----"));
    for host in ["localhost", "127.0.0.1"] {
        handshake(port, &ca_pem, host).await.unwrap_or_else(|e| panic!("{host}: {e}"));
    }
    // a name the certificate does not cover is refused even though the CA is trusted
    assert!(handshake(port, &ca_pem, "evil.example").await.is_err());
    gw.shutdown().await;
}

#[tokio::test]
async fn a_name_the_ca_cannot_vouch_for_is_left_out_instead_of_breaking_the_certificate() {
    // the CA was made for this network; later someone adds a public name: it is not put in the certificate (every client
    // would refuse the whole certificate), and the others keep working
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    gw.shutdown().await;
    let gw = gateway_with(&[&a], |c| {
        let mut t = auto(port, dir.path(), Duration::ZERO);
        t.extra_sans = vec!["bank.example.com".into(), "8.8.8.8".into(), "nas.lan".into()];
        c.tls = Some(t);
    })
    .await;
    let (ca, _) = fetch_ca(gw.addr).await;
    handshake(port, &ca, "localhost").await.expect("the certificate still works");
    handshake(port, &ca, "nas.lan").await.expect("a private name is fine");
    assert!(handshake(port, &ca, "bank.example.com").await.is_err());
    gw.shutdown().await;
}

#[tokio::test]
async fn names_given_when_the_ca_is_created_are_covered_by_it() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| {
        let mut t = auto(port, dir.path(), Duration::ZERO);
        t.extra_sans = vec!["casa.example.org".into()];
        c.tls = Some(t);
    })
    .await;
    let (ca, _) = fetch_ca(gw.addr).await;
    handshake(port, &ca, "casa.example.org")
        .await
        .expect("a name chosen by the administrator");
    assert!(handshake(port, &ca, "evil.example.org").await.is_err());
    gw.shutdown().await;
}

#[tokio::test]
async fn a_client_given_another_ca_refuses_the_server() {
    let (a, dir, other, port) = (Backend::start("a").await, tmp(), tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    // somebody else's gateway, with its own CA: the pairing code of this one does not match it
    let b = Backend::start("b").await;
    let other_port = free_port();
    let gw2 = gateway_with(&[&b], |c| c.tls = Some(auto(other_port, other.path(), Duration::ZERO))).await;
    let (other_ca, _) = fetch_ca(gw2.addr).await;
    assert!(
        handshake(port, &other_ca, "localhost").await.is_err(),
        "a CA that is not the server's must not be enough"
    );
    gw.shutdown().await;
    gw2.shutdown().await;
}

#[tokio::test]
async fn the_fingerprint_is_public_matches_the_ca_and_a_replica_cannot_spoof_it() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let (ca_pem, _) = fetch_ca(gw.addr).await;
    let expected = pindrel_gateway::selfcert::fingerprint_of_pem(&ca_pem).unwrap();
    let info = get(gw.addr, "/server/info/").await;
    assert_eq!(info.header("x-pindrel-ca"), expected);
    assert_eq!(expected.len(), 64);
    // an ordinary path never carries it
    assert_eq!(get(gw.addr, "/x").await.header("x-pindrel-ca"), "");
    gw.shutdown().await;
}

#[tokio::test]
async fn without_tls_auto_there_is_no_ca_to_download() {
    let a = Backend::start("a").await;
    let gw = gateway(&[&a]).await;
    assert_eq!(get(gw.addr, "/server/ca.pem").await.status, hyper::StatusCode::NOT_FOUND);
    assert_eq!(get(gw.addr, "/server/info/").await.header("x-pindrel-ca"), "");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_restart_keeps_the_ca_and_the_server_certificate() {
    let (a, dir) = (Backend::start("a").await, tmp());
    let port = free_port();
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let (ca1, _) = fetch_ca(gw.addr).await;
    let leaf1 = handshake(port, &ca1, "localhost").await.unwrap();
    gw.shutdown().await;
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let (ca2, _) = fetch_ca(gw.addr).await;
    assert_eq!(ca1, ca2, "the CA changed: every paired device would have to pair again");
    assert_eq!(leaf1, handshake(port, &ca2, "localhost").await.unwrap());
    gw.shutdown().await;
}

#[tokio::test]
async fn a_lost_server_certificate_is_signed_again_by_the_same_ca() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let (ca, _) = fetch_ca(gw.addr).await;
    let before = handshake(port, &ca, "localhost").await.unwrap();
    gw.shutdown().await;
    for f in ["server.pem", "server.key", "server.meta"] {
        fs::remove_file(dir.path().join(f)).unwrap();
    }
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let after = handshake(port, &ca, "localhost")
        .await
        .expect("the old CA still trusts the new certificate");
    assert_ne!(before, after);
    gw.shutdown().await;
}

#[tokio::test]
async fn a_changed_address_or_an_old_certificate_is_renewed_without_a_restart() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::from_millis(150)))).await;
    let (ca, _) = fetch_ca(gw.addr).await;
    let first = handshake(port, &ca, "localhost").await.unwrap();
    // the machine "changes address": the saved list of names no longer matches
    fs::write(dir.path().join("server.meta"), "localhost,10.9.9.9\n99999999999\n").unwrap();
    time::sleep(Duration::from_millis(600)).await;
    let second = handshake(port, &ca, "localhost").await.unwrap();
    assert_ne!(first, second, "the new certificate was not picked up");
    // and a certificate close to its end
    fs::write(
        dir.path().join("server.meta"),
        format!(
            "{}\n1\n",
            fs::read_to_string(dir.path().join("server.meta")).unwrap().lines().next().unwrap()
        ),
    )
    .unwrap();
    time::sleep(Duration::from_millis(600)).await;
    let third = handshake(port, &ca, "localhost").await.unwrap();
    assert_ne!(second, third);
    gw.shutdown().await;
}

#[tokio::test]
async fn the_private_keys_are_readable_only_by_their_owner() {
    use std::os::unix::fs::PermissionsExt;
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    for f in ["ca.key", "server.key"] {
        let mode = fs::metadata(dir.path().join(f)).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "{f} is {mode:o}");
    }
    gw.shutdown().await;
}

#[tokio::test]
async fn damaged_files_are_replaced_instead_of_stopping_the_gateway() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    gw.shutdown().await;
    fs::write(dir.path().join("server.pem"), "not a certificate").unwrap();
    fs::write(dir.path().join("ca.key"), "").unwrap(); // a CA key that cannot be read: a new CA, loudly different
    let gw = gateway_with(&[&a], |c| c.tls = Some(auto(port, dir.path(), Duration::ZERO))).await;
    let (ca, _) = fetch_ca(gw.addr).await;
    handshake(port, &ca, "localhost").await.expect("serving again");
    gw.shutdown().await;
}

#[tokio::test]
async fn files_given_by_hand_are_picked_up_when_they_change_and_a_broken_renewal_changes_nothing() {
    use pindrel_gateway::certs::{Reloadable, Source};
    let dir = tmp();
    let (cert, key) = (dir.path().join("c.pem"), dir.path().join("k.pem"));
    let test = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/tls");
    fs::copy(test.join("cert.pem"), &cert).unwrap();
    fs::copy(test.join("key.pem"), &key).unwrap();
    let r = Reloadable::new(Source::Files {
        cert: cert.clone(),
        key: key.clone(),
    })
    .unwrap();
    assert!(!r.refresh().unwrap(), "nothing changed");
    // a half-written renewal
    time::sleep(Duration::from_millis(1100)).await; // mtime granularity
    fs::write(&cert, "-----BEGIN CERTIFICATE-----\ngarbage").unwrap();
    assert!(r.refresh().is_err());
    assert!(r.serial_hint() > 0, "the certificate in use was lost");
    // the real renewal arrives
    time::sleep(Duration::from_millis(1100)).await;
    let (b, d2) = (Backend::start("b").await, tmp());
    let gw = gateway_with(&[&b], |c| c.tls = Some(auto(free_port(), d2.path(), Duration::ZERO))).await;
    let new_leaf = fs::read_to_string(d2.path().join("server.pem")).unwrap();
    let new_key = fs::read_to_string(d2.path().join("server.key")).unwrap();
    fs::write(&cert, new_leaf).unwrap();
    fs::write(&key, new_key).unwrap();
    assert!(r.refresh().unwrap(), "the new files were not noticed");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_flood_of_handshakes_and_junk_on_the_auto_tls_port_changes_nothing() {
    let (a, dir, port) = (Backend::start("a").await, tmp(), free_port());
    let gw = gateway_with(&[&a], |c| {
        c.tls = Some(auto(port, dir.path(), Duration::ZERO));
        c.rate_limit = false;
        c.max_connections_per_ip = 1000;
    })
    .await;
    let (ca, _) = fetch_ca(gw.addr).await;
    let mut tasks = Vec::new();
    for _ in 0..100 {
        let ca = ca.clone();
        tasks.push(tokio::spawn(async move { handshake(port, &ca, "localhost").await.is_ok() }));
    }
    for _ in 0..30 {
        tokio::spawn(async move {
            if let Ok(mut s) = TcpStream::connect(("127.0.0.1", port)).await {
                let _ = s.write_all(b"\x16\x03\x01\x00\x05junk!").await;
                let mut b = [0u8; 8];
                let _ = s.read(&mut b).await;
            }
        });
    }
    for t in tasks {
        assert!(t.await.unwrap());
    }
    gw.shutdown().await;
}
