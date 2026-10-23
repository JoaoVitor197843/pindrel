//! Configuration from environment variables. Every problem is reported at once, like backend/internal/config.
use std::{net::SocketAddr, time::Duration};

use crate::pool::parse_targets;

#[derive(Debug, Clone)]
pub struct Config {
    pub port: u16,
    pub upstreams: Vec<SocketAddr>,
    pub server_name: String,
    pub mdns: bool,
    /// Interface names to announce on; empty = the one that holds the default route.
    pub mdns_interfaces: Vec<String>,
    /// How often the LAN search is restarted while no other server is known (4x that once one is); zero turns it off.
    /// Wi-Fi drops many multicast frames and the library's own retries back off up to an hour.
    pub mdns_refresh: Duration,
    pub probe_interval: Duration,
    /// How often the remembered servers that are no longer announced are tried again; zero turns it off.
    pub known_interval: Duration,
    /// Where to keep the remembered servers between runs (unset: only in memory).
    pub known_file: Option<std::path::PathBuf>,
    pub max_connections: usize,
    pub rate_limit: bool,
    pub max_body: usize,
    pub header_timeout: Duration,
    pub body_timeout: Duration,
    pub upstream_timeout: Duration,
}

impl Config {
    /// Defaults for everything but the upstreams (handy for tests).
    pub fn new(upstreams: Vec<SocketAddr>) -> Self {
        Self {
            port: 8080,
            upstreams,
            server_name: "Plany".into(),
            mdns: true,
            mdns_interfaces: Vec::new(),
            mdns_refresh: Duration::from_secs(15),
            probe_interval: Duration::from_secs(3),
            known_interval: Duration::from_secs(15),
            known_file: None,
            max_connections: 1024,
            rate_limit: true,
            max_body: 1 << 20,
            header_timeout: Duration::from_secs(10),
            body_timeout: Duration::from_secs(10),
            upstream_timeout: Duration::from_secs(30),
        }
    }

    pub fn from_env() -> Result<Self, Vec<String>> {
        Self::from_lookup(|k| std::env::var(k).ok())
    }

    pub fn from_lookup(get: impl Fn(&str) -> Option<String>) -> Result<Self, Vec<String>> {
        let get = |k: &str| get(k).map(|v| v.trim().to_string()).filter(|v| !v.is_empty());
        let mut errs = Vec::new();
        let mut parse = |key: &str, default: &str, min: u64, max: u64| -> u64 {
            let raw = get(key).unwrap_or_else(|| default.to_string());
            match raw.parse::<u64>() {
                Ok(v) if (min..=max).contains(&v) => v,
                _ => {
                    errs.push(format!("{key}: invalid value {raw:?} (expected {min}-{max})"));
                    0
                }
            }
        };
        let port = parse("GATEWAY_PORT", "8080", 1, 65535) as u16;
        let probe = parse("PROBE_INTERVAL_SECS", "3", 1, 3600);
        let mdns_refresh = parse("MDNS_REFRESH_SECS", "15", 0, 3600);
        let known_interval = parse("KNOWN_PROBE_SECS", "15", 0, 3600);
        let max_connections = parse("MAX_CONNECTIONS", "1024", 1, 100_000) as usize;
        let max_body = parse("MAX_BODY_BYTES", "1048576", 1, 64 << 20) as usize;
        let mut flag = |key: &str, default: bool| -> bool {
            match get(key) {
                None => default,
                Some(v) => v.parse::<bool>().unwrap_or_else(|_| {
                    errs.push(format!("{key}: invalid value {v:?} (expected true or false)"));
                    default
                }),
            }
        };
        let mdns = flag("MDNS_ENABLED", true);
        let rate_limit = flag("RATE_LIMIT_ENABLED", true);
        let upstreams = match get("UPSTREAMS") {
            None => {
                errs.push("UPSTREAMS: required (e.g. 127.0.0.1:9000-9099)".into());
                Vec::new()
            }
            Some(spec) => parse_targets(&spec).unwrap_or_else(|e| {
                errs.push(format!("UPSTREAMS: {e}"));
                Vec::new()
            }),
        };
        if !errs.is_empty() {
            return Err(errs);
        }
        Ok(Self {
            port,
            upstreams,
            server_name: get("SERVER_NAME").unwrap_or_else(|| "Plany".into()),
            mdns,
            mdns_interfaces: get("MDNS_INTERFACES")
                .map(|v| v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
                .unwrap_or_default(),
            mdns_refresh: Duration::from_secs(mdns_refresh),
            probe_interval: Duration::from_secs(probe),
            known_interval: Duration::from_secs(known_interval),
            known_file: get("KNOWN_SERVERS_FILE").map(std::path::PathBuf::from),
            max_connections,
            rate_limit,
            max_body,
            ..Self::new(Vec::new())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn load(pairs: &[(&str, &str)]) -> Result<Config, Vec<String>> {
        let m: HashMap<String, String> = pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        Config::from_lookup(|k| m.get(k).cloned())
    }

    #[test]
    fn defaults() {
        let c = load(&[("UPSTREAMS", "127.0.0.1:9000-9002")]).unwrap();
        assert_eq!(
            (c.port, c.upstreams.len(), c.server_name.as_str(), c.mdns, c.rate_limit),
            (8080, 3, "Plany", true, true)
        );
        assert_eq!(
            (c.max_connections, c.max_body, c.probe_interval),
            (1024, 1 << 20, Duration::from_secs(3))
        );
    }

    #[test]
    fn overrides() {
        let c = load(&[
            ("UPSTREAMS", "10.0.0.5:80"),
            ("GATEWAY_PORT", "9000"),
            ("SERVER_NAME", "Casa"),
            ("MDNS_ENABLED", "false"),
            ("RATE_LIMIT_ENABLED", "false"),
            ("MDNS_INTERFACES", "eth0, wlan0"),
            ("MAX_CONNECTIONS", "8"),
        ])
        .unwrap();
        assert_eq!(
            (c.port, c.server_name.as_str(), c.mdns, c.rate_limit, c.max_connections),
            (9000, "Casa", false, false, 8)
        );
        assert_eq!(c.mdns_interfaces, ["eth0", "wlan0"]);
    }

    #[test]
    fn every_error_is_reported_at_once() {
        let errs = load(&[("GATEWAY_PORT", "0"), ("MDNS_ENABLED", "maybe"), ("MAX_CONNECTIONS", "x")]).unwrap_err();
        assert_eq!(errs.len(), 4, "{errs:?}"); // port, mdns flag, max connections, missing upstreams
        assert!(errs.iter().any(|e| e.starts_with("UPSTREAMS")));
    }

    #[test]
    fn blank_values_count_as_unset() {
        let c = load(&[("UPSTREAMS", "127.0.0.1:1"), ("SERVER_NAME", "   "), ("GATEWAY_PORT", "")]).unwrap();
        assert_eq!((c.server_name.as_str(), c.port), ("Plany", 8080));
    }
}
