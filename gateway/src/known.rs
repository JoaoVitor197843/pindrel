//! Memory of the servers seen before. A server that stops being announced is not necessarily gone:
//! on a lossy Wi-Fi the refresh of its announcement can simply be lost. So the gateway tries the
//! addresses of the remembered servers itself (a plain TCP connection to the same subnet) and keeps
//! listing the ones that answer. The memory can also be kept in a file, so that a restarted gateway
//! lists the others at once instead of waiting for them to be announced again.
use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use tokio::{net::TcpStream, sync::watch, task::JoinSet, time};

use crate::{
    discovery::{Lan, Registry},
    proto,
};

const MAX_FILE: u64 = 1 << 20;

/// Tries every address that may be tried and records which ones answered.
pub async fn verify(registry: &Registry, lan: &Lan) {
    let mut set = JoinSet::new();
    for (name, addrs) in registry.probe_targets(lan) {
        set.spawn(async move {
            let mut ok = Vec::new();
            for a in addrs {
                if matches!(time::timeout(Duration::from_millis(500), TcpStream::connect(a)).await, Ok(Ok(_))) {
                    ok.push(a.ip().to_string());
                }
            }
            (name, ok)
        });
    }
    while let Some(Ok((name, ok))) = set.join_next().await {
        registry.set_verified(&name, ok);
    }
}

fn load(path: &Path) -> Vec<crate::discovery::Server> {
    match std::fs::metadata(path) {
        Ok(m) if m.len() > MAX_FILE => eprintln!("known servers: {} is too big, ignored", path.display()),
        Ok(_) => match std::fs::read(path).ok().as_deref().and_then(proto::parse_discovered_servers) {
            Some(v) => return v,
            None => eprintln!("known servers: {} is not valid, ignored", path.display()),
        },
        Err(_) => {} // first run
    }
    Vec::new()
}

/// Writes the file in one piece (a crash in the middle never leaves a broken file).
fn save(path: &Path, bytes: &[u8]) {
    let tmp: PathBuf = path.with_extension("tmp");
    if let Err(e) = std::fs::write(&tmp, bytes).and_then(|_| std::fs::rename(&tmp, path)) {
        eprintln!("known servers: could not save {}: {e}", path.display());
    }
}

/// Checks the remembered servers every `interval`, and right away when one stops being announced.
/// With `file`, the memory is loaded at the start and saved when it changes.
pub async fn run(registry: Arc<Registry>, lan: Option<Lan>, file: Option<PathBuf>, interval: Duration, mut stop: watch::Receiver<bool>) {
    if let Some(f) = &file {
        registry.load(load(f));
    }
    let mut saved = file.as_deref().map(|f| std::fs::read(f).unwrap_or_default());
    loop {
        if let Some(lan) = &lan {
            verify(&registry, lan).await;
        }
        if let (Some(f), Some(prev)) = (&file, saved.as_mut()) {
            let now = proto::discovered_servers(&registry.snapshot());
            if now != *prev {
                save(f, &now);
                *prev = now;
            }
        }
        tokio::select! {
            _ = time::sleep(interval) => {}
            _ = registry.lost.notified() => {}
            _ = stop.changed() => return,
        }
    }
}
