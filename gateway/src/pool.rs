//! The replicas behind the gateway: which ones are up, and in which order to try them.
use std::{
    net::{IpAddr, SocketAddr},
    sync::{
        atomic::{AtomicUsize, Ordering},
        RwLock,
    },
    time::Duration,
};

use tokio::{net::TcpStream, task::JoinSet, time};

/// Expands "127.0.0.1:9000-9003,10.0.0.5:8080" into socket addresses.
pub fn parse_targets(spec: &str) -> Result<Vec<SocketAddr>, String> {
    let mut out = Vec::new();
    for part in spec.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        let (host, ports) = part
            .rsplit_once(':')
            .ok_or(format!("invalid upstream {part:?} (expected host:port)"))?;
        let (lo, hi) = ports.split_once('-').unwrap_or((ports, ports));
        let port = |s: &str| s.parse::<u16>().ok().filter(|p| *p > 0).ok_or(format!("invalid port in {part:?}"));
        let (lo, hi) = (port(lo)?, port(hi)?);
        if hi < lo {
            return Err(format!("invalid port range in {part:?}"));
        }
        let host: IpAddr = host
            .trim_matches(['[', ']'])
            .parse()
            .map_err(|_| format!("upstream host must be an IP address: {part:?}"))?;
        out.extend((lo..=hi).map(|p| SocketAddr::new(host, p)));
    }
    if out.is_empty() {
        Err("no upstreams given".into())
    } else {
        Ok(out)
    }
}

pub struct Pool {
    targets: Vec<SocketAddr>,
    alive: RwLock<Vec<SocketAddr>>,
    next: AtomicUsize,
}

impl Pool {
    pub fn new(targets: Vec<SocketAddr>) -> Self {
        Self {
            targets,
            alive: RwLock::new(Vec::new()),
            next: AtomicUsize::new(0),
        }
    }

    pub fn alive(&self) -> Vec<SocketAddr> {
        self.alive.read().unwrap().clone()
    }

    /// The live replicas in the order to try them: round-robin, each call starts one further.
    pub fn rotation(&self) -> Vec<SocketAddr> {
        let alive = self.alive();
        if alive.is_empty() {
            return alive;
        }
        let start = self.next.fetch_add(1, Ordering::Relaxed) % alive.len();
        alive.iter().cycle().skip(start).take(alive.len()).copied().collect()
    }

    /// A connection to it failed: stop sending traffic there until the next probe sees it again.
    pub fn mark_down(&self, target: SocketAddr) {
        self.alive.write().unwrap().retain(|a| *a != target);
    }

    /// Dials every possible replica and keeps the ones that accept connections.
    pub async fn probe(&self) {
        let mut set = JoinSet::new();
        for (i, t) in self.targets.iter().copied().enumerate() {
            set.spawn(async move {
                (
                    i,
                    matches!(time::timeout(Duration::from_millis(500), TcpStream::connect(t)).await, Ok(Ok(_))),
                )
            });
        }
        let mut up = vec![false; self.targets.len()];
        while let Some(Ok((i, ok))) = set.join_next().await {
            up[i] = ok;
        }
        *self.alive.write().unwrap() = self.targets.iter().zip(up).filter(|(_, u)| *u).map(|(t, _)| *t).collect();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_ranges_and_lists() {
        let t = parse_targets("127.0.0.1:9000-9002, 10.0.0.5:8080").unwrap();
        let want: Vec<SocketAddr> = ["127.0.0.1:9000", "127.0.0.1:9001", "127.0.0.1:9002", "10.0.0.5:8080"]
            .iter()
            .map(|s| s.parse().unwrap())
            .collect();
        assert_eq!(t, want);
        assert_eq!(parse_targets("[::1]:8080").unwrap(), ["[::1]:8080".parse::<SocketAddr>().unwrap()]);
    }

    #[test]
    fn rejects_garbage() {
        for bad in [
            "",
            " , ",
            "nohost",
            "h:abc",
            "127.0.0.1:0",
            "127.0.0.1:70000",
            "127.0.0.1:9005-9001",
            "name:80",
            "127.0.0.1:",
        ] {
            assert!(parse_targets(bad).is_err(), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn rotation_is_round_robin_and_covers_every_replica_once() {
        let p = Pool::new(parse_targets("127.0.0.1:1-3").unwrap());
        *p.alive.write().unwrap() = p.targets.clone();
        let firsts: Vec<u16> = (0..6).map(|_| p.rotation()[0].port()).collect();
        assert_eq!(firsts, [1, 2, 3, 1, 2, 3]);
        let mut all: Vec<u16> = p.rotation().iter().map(|a| a.port()).collect();
        all.sort();
        assert_eq!(all, [1, 2, 3]);
    }

    #[test]
    fn mark_down_removes_only_that_replica() {
        let p = Pool::new(parse_targets("127.0.0.1:1-2").unwrap());
        *p.alive.write().unwrap() = p.targets.clone();
        p.mark_down("127.0.0.1:1".parse().unwrap());
        assert_eq!(p.alive(), ["127.0.0.1:2".parse::<SocketAddr>().unwrap()]);
    }

    #[test]
    fn no_replica_means_empty_rotation() {
        assert!(Pool::new(parse_targets("127.0.0.1:1").unwrap()).rotation().is_empty());
    }
}
