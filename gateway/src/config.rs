//! Configuration from environment variables. Every problem is reported at once, like backend/internal/config.
use std::{net::SocketAddr, time::Duration};

use crate::{
    clientip::{self, ClientIp},
    pool::parse_targets,
};

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
    /// Where the id of this server is kept between runs (unset: a new id on every start).
    pub server_id_file: Option<std::path::PathBuf>,
    pub max_connections: usize,
    /// Open connections one client may hold (not counted for the declared proxies, which carry many clients).
    pub max_connections_per_ip: usize,
    pub rate_limit: bool,
    /// Who counts as the client behind a trusted proxy (`TRUSTED_PROXIES`, `CLIENT_IP_HEADER`); by default the peer.
    pub client_ip: ClientIp,
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
            server_name: "Pindrel".into(),
            mdns: true,
            mdns_interfaces: Vec::new(),
            mdns_refresh: Duration::from_secs(15),
            probe_interval: Duration::from_secs(3),
            known_interval: Duration::from_secs(15),
            known_file: None,
            server_id_file: None,
            max_connections: 1024,
            max_connections_per_ip: 64,
            rate_limit: true,
            client_ip: ClientIp::direct(),
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
        let max_connections_per_ip = parse("MAX_CONNECTIONS_PER_IP", "64", 1, 100_000) as usize;
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
        let trusted = get("TRUSTED_PROXIES").map_or(Vec::new(), |spec| {
            clientip::parse_trusted(&spec).unwrap_or_else(|e| {
                errs.push(format!("TRUSTED_PROXIES: {e}"));
                Vec::new()
            })
        });
        let client_ip = ClientIp::new(trusted, &get("CLIENT_IP_HEADER").unwrap_or_else(|| "x-forwarded-for".into())).unwrap_or_else(|e| {
            errs.push(format!("CLIENT_IP_HEADER: {e}"));
            ClientIp::direct()
        });
        if !errs.is_empty() {
            return Err(errs);
        }
        Ok(Self {
            port,
            upstreams,
            server_name: get("SERVER_NAME").unwrap_or_else(|| "Pindrel".into()),
            mdns,
            mdns_interfaces: get("MDNS_INTERFACES")
                .map(|v| v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
                .unwrap_or_default(),
            mdns_refresh: Duration::from_secs(mdns_refresh),
            probe_interval: Duration::from_secs(probe),
            known_interval: Duration::from_secs(known_interval),
            known_file: get("KNOWN_SERVERS_FILE").map(std::path::PathBuf::from),
            server_id_file: get("SERVER_ID_FILE").map(std::path::PathBuf::from),
            max_connections,
            max_connections_per_ip,
            rate_limit,
            client_ip,
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
            (8080, 3, "Pindrel", true, true)
        );
        assert_eq!(
            (c.max_connections, c.max_connections_per_ip, c.max_body, c.probe_interval),
            (1024, 64, 1 << 20, Duration::from_secs(3))
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
            ("MAX_CONNECTIONS_PER_IP", "3"),
            ("SERVER_ID_FILE", "/data/server-id"),
        ])
        .unwrap();
        assert_eq!(
            (c.port, c.server_name.as_str(), c.mdns, c.rate_limit, c.max_connections),
            (9000, "Casa", false, false, 8)
        );
        assert_eq!(c.mdns_interfaces, ["eth0", "wlan0"]);
        assert_eq!(c.max_connections_per_ip, 3);
        assert_eq!(c.server_id_file.as_deref(), Some(std::path::Path::new("/data/server-id")));
    }

    #[test]
    fn every_error_is_reported_at_once() {
        let errs = load(&[("GATEWAY_PORT", "0"), ("MDNS_ENABLED", "maybe"), ("MAX_CONNECTIONS", "x")]).unwrap_err();
        assert_eq!(errs.len(), 4, "{errs:?}"); // port, mdns flag, max connections, missing upstreams
        assert!(errs.iter().any(|e| e.starts_with("UPSTREAMS")));
    }

    #[test]
    fn no_trusted_proxy_by_default_and_the_header_is_x_forwarded_for_when_there_is_one() {
        let c = load(&[("UPSTREAMS", "127.0.0.1:1")]).unwrap();
        assert!(c.client_ip.is_direct());
        let c = load(&[("UPSTREAMS", "127.0.0.1:1"), ("TRUSTED_PROXIES", "127.0.0.1, 10.0.0.0/8")]).unwrap();
        assert!(!c.client_ip.is_direct());
        let c = load(&[
            ("UPSTREAMS", "127.0.0.1:1"),
            ("TRUSTED_PROXIES", "::1"),
            ("CLIENT_IP_HEADER", "CF-Connecting-IP"),
        ])
        .unwrap();
        assert!(!c.client_ip.is_direct());
    }

    #[test]
    fn bad_proxy_settings_are_reported_with_the_rest() {
        let errs = load(&[
            ("TRUSTED_PROXIES", "127.0.0.1, banana"),
            ("CLIENT_IP_HEADER", "not a header"),
            ("GATEWAY_PORT", "0"),
        ])
        .unwrap_err();
        assert_eq!(errs.len(), 4, "{errs:?}"); // port, proxies, header, missing upstreams
        assert!(errs.iter().any(|e| e.starts_with("TRUSTED_PROXIES")));
        assert!(errs.iter().any(|e| e.starts_with("CLIENT_IP_HEADER")));
    }

    #[test]
    fn blank_values_count_as_unset() {
        let c = load(&[("UPSTREAMS", "127.0.0.1:1"), ("SERVER_NAME", "   "), ("GATEWAY_PORT", "")]).unwrap();
        assert_eq!((c.server_name.as_str(), c.port), ("Pindrel", 8080));
    }
}
