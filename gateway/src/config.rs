//! Configuration from environment variables. Every problem is reported at once, like backend/internal/config.
use std::{net::SocketAddr, time::Duration};

use crate::{
    clientip::{self, ClientIp},
    pool::parse_targets,
};

/// TLS listener (HTTP/1.1 + HTTP/2 over TCP). HTTP/3 was measured and left out: no gain worth its code on a LAN.
#[derive(Debug, Clone)]
pub struct TlsConfig {
    pub port: u16,
    pub cert: std::path::PathBuf,
    pub key: std::path::PathBuf,
    /// `TLS_AUTO=true`: the gateway keeps its own CA and server certificate in this directory instead of reading
    /// `cert` and `key` (build feature `selfcert`).
    pub auto_dir: Option<std::path::PathBuf>,
    /// Extra names or addresses for the automatic certificate (`TLS_SANS`).
    pub extra_sans: Vec<String>,
    /// How often the certificate is looked at again (renewed files, a changed address); zero turns it off.
    pub refresh: Duration,
}

/// What the plain-HTTP port does when TLS is on. `Redirect`: only the public bootstrap routes answer (`/server/info/`,
/// `/server/ca.pem`, `/server/connect/`, and a landing page at `/`); other GETs are sent to HTTPS and anything that could
/// carry a password or a note (POST, WebSocket) is refused, so nothing private travels in clear. `Full` (the default): the
/// plain port answers everything as if TLS were off, so a client that has no HTTPS side keeps working; clients that know
/// the HTTPS side prefer it (the `tls` entry of the mDNS record and `x-pindrel-tls`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HttpMode {
    Full,
    Redirect,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub port: u16,
    /// Off unless `TLS_PORT` is set (needs the `tls` build feature).
    pub tls: Option<TlsConfig>,
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
    /// Open WebSocket tunnels in total, and per client (a tunnel outlives the HTTP connection that opened it, so the
    /// connection limits above do not count it).
    pub max_websockets: usize,
    pub max_websockets_per_ip: usize,
    /// Pairing rooms open at the same time (`PAIRING_MAX_ROOMS`): that many people can pair at once, each seeing only theirs.
    pub max_pairings: usize,
    /// A tunnel with no byte in either direction for this long is closed (clients ping, so a live one never idles).
    pub ws_idle: Duration,
    pub rate_limit: bool,
    /// Only used when `tls` is set.
    pub http_mode: HttpMode,
    /// Origins (besides the server's own) allowed to open a WebSocket from a browser (`WS_ALLOWED_ORIGINS`). Clients
    /// that are not browsers send no `Origin` and are not affected.
    pub ws_allowed_origins: Vec<String>,
    /// Who counts as the client behind a trusted proxy (`TRUSTED_PROXIES`, `CLIENT_IP_HEADER`); by default the peer.
    pub client_ip: ClientIp,
    pub max_body: usize,
    /// Bytes of request bodies the gateway may hold in memory at once (`BODY_BUDGET_BYTES`). A body is held whole before it
    /// is passed on (so it can be replayed on another replica), and a file is sent in many pieces of up to `max_body`: without
    /// a budget, enough uploads at once would grow the gateway past its memory limit.
    pub body_budget: usize,
    /// How long a request waits for room in the budget before it is told to try again (`503`).
    pub body_queue: Duration,
    /// A piece of a file may take longer to arrive than an ordinary body (a phone on a bad line): `FILE_BODY_TIMEOUT_SECS`.
    pub file_body_timeout: Duration,
    /// Joining the pieces of a large file takes the replica a while: `FILE_FINISH_TIMEOUT_SECS`.
    pub file_finish_timeout: Duration,
    pub header_timeout: Duration,
    pub body_timeout: Duration,
    pub upstream_timeout: Duration,
}

impl Config {
    /// Defaults for everything but the upstreams (handy for tests).
    pub fn new(upstreams: Vec<SocketAddr>) -> Self {
        Self {
            port: 8080,
            tls: None,
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
            max_websockets: 1024,
            max_websockets_per_ip: 32,
            max_pairings: 6,
            ws_idle: Duration::from_secs(600),
            rate_limit: true,
            http_mode: HttpMode::Full,
            ws_allowed_origins: Vec::new(),
            client_ip: ClientIp::direct(),
            max_body: 1 << 20,
            body_budget: 8 << 20,
            body_queue: Duration::from_secs(5),
            file_body_timeout: Duration::from_secs(60),
            file_finish_timeout: Duration::from_secs(600),
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
        let body_budget = parse("BODY_BUDGET_BYTES", "8388608", 0, 1 << 30) as usize;
        let file_body_timeout = parse("FILE_BODY_TIMEOUT_SECS", "60", 1, 3600);
        let file_finish_timeout = parse("FILE_FINISH_TIMEOUT_SECS", "600", 1, 86_400);
        let max_websockets = parse("MAX_WEBSOCKETS", "1024", 0, 100_000) as usize;
        let max_websockets_per_ip = parse("MAX_WEBSOCKETS_PER_IP", "32", 1, 100_000) as usize;
        let max_pairings = parse("PAIRING_MAX_ROOMS", "6", 1, 64) as usize;
        let ws_idle = parse("WS_IDLE_SECS", "600", 0, 86_400);
        let tls_refresh = parse("TLS_REFRESH_SECS", "3600", 0, 86_400 * 7);
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
        let tls_auto = flag("TLS_AUTO", false);
        let tls_port = get("TLS_PORT").map(|v| match v.parse::<u16>() {
            Ok(p) if p > 0 => p,
            _ => {
                errs.push(format!("TLS_PORT: invalid value {v:?} (expected 1-65535)"));
                0
            }
        });
        let tls_cert = get("TLS_CERT_FILE");
        let tls_key = get("TLS_KEY_FILE");
        let tls_dir = get("TLS_DIR");
        let tls = tls_port.map(|port| {
            if tls_auto {
                if tls_dir.is_none() {
                    errs.push("TLS_DIR: required when TLS_AUTO is true".into());
                }
                if tls_cert.is_some() || tls_key.is_some() {
                    errs.push("TLS_AUTO and TLS_CERT_FILE/TLS_KEY_FILE: choose one".into());
                }
            } else if tls_cert.is_none() || tls_key.is_none() {
                errs.push("TLS_CERT_FILE and TLS_KEY_FILE: required when TLS_PORT is set (or use TLS_AUTO=true)".into());
            }
            TlsConfig {
                port,
                cert: tls_cert.clone().unwrap_or_default().into(),
                key: tls_key.clone().unwrap_or_default().into(),
                auto_dir: tls_auto.then(|| tls_dir.clone().unwrap_or_default().into()),
                extra_sans: get("TLS_SANS")
                    .map(|v| v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
                    .unwrap_or_default(),
                refresh: Duration::from_secs(tls_refresh),
            }
        });
        let http_mode = match get("HTTP_MODE").as_deref() {
            None | Some("full") => HttpMode::Full,
            Some("redirect") => HttpMode::Redirect,
            Some(other) => {
                errs.push(format!("HTTP_MODE: invalid value {other:?} (expected full or redirect)"));
                HttpMode::Full
            }
        };
        let ws_allowed_origins: Vec<String> = get("WS_ALLOWED_ORIGINS")
            .map(|v| {
                v.split(',')
                    .map(|s| s.trim().trim_end_matches('/').to_lowercase())
                    .filter(|s| !s.is_empty())
                    .collect()
            })
            .unwrap_or_default();
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
            tls,
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
            max_websockets,
            max_websockets_per_ip,
            max_pairings,
            ws_idle: Duration::from_secs(ws_idle),
            rate_limit,
            http_mode,
            ws_allowed_origins,
            client_ip,
            max_body,
            // never less than one body, or no request could ever pass
            body_budget: body_budget.max(max_body),
            file_body_timeout: Duration::from_secs(file_body_timeout),
            file_finish_timeout: Duration::from_secs(file_finish_timeout),
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

    #[test]
    fn the_plain_port_answers_everything_by_default_and_redirect_is_opt_in() {
        let base = [("UPSTREAMS", "127.0.0.1:1")];
        assert_eq!(load(&base).unwrap().http_mode, HttpMode::Full);
        let with = |v: &'static str| load(&[base[0], ("HTTP_MODE", v)]);
        assert_eq!(with("full").unwrap().http_mode, HttpMode::Full);
        assert_eq!(with("redirect").unwrap().http_mode, HttpMode::Redirect);
        let errs = with("both").unwrap_err();
        assert!(
            errs.iter().any(|e| e.contains("HTTP_MODE") && e.contains("full or redirect")),
            "{errs:?}"
        );
    }

    #[test]
    fn tls_is_off_by_default_and_needs_both_files_when_on() {
        assert!(load(&[("UPSTREAMS", "127.0.0.1:1")]).unwrap().tls.is_none());
        let errs = load(&[("UPSTREAMS", "127.0.0.1:1"), ("TLS_PORT", "8443")]).unwrap_err();
        assert!(errs.iter().any(|e| e.starts_with("TLS_CERT_FILE and TLS_KEY_FILE")), "{errs:?}");
        let t = load(&[
            ("UPSTREAMS", "127.0.0.1:1"),
            ("TLS_PORT", "8443"),
            ("TLS_CERT_FILE", "/c.pem"),
            ("TLS_KEY_FILE", "/k.pem"),
        ])
        .unwrap()
        .tls
        .unwrap();
        assert_eq!(t.port, 8443);
    }

    #[test]
    fn the_pairing_limits_have_defaults_and_bounds() {
        let c = load(&[("UPSTREAMS", "127.0.0.1:1")]).unwrap();
        assert_eq!(c.max_pairings, 6, "six people at once unless told otherwise");
        let c = load(&[("UPSTREAMS", "127.0.0.1:1"), ("PAIRING_MAX_ROOMS", "12")]).unwrap();
        assert_eq!(c.max_pairings, 12);
        for (key, bad) in [
            ("PAIRING_MAX_ROOMS", "0"),
            ("PAIRING_MAX_ROOMS", "65"),
            ("PAIRING_MAX_ROOMS", "many"),
        ] {
            let errs = load(&[("UPSTREAMS", "127.0.0.1:1"), (key, bad)]).unwrap_err();
            assert!(errs.iter().any(|e| e.starts_with(key)), "{key}={bad}: {errs:?}");
        }
    }

    #[test]
    fn bad_tls_settings_are_reported_with_the_rest() {
        for port in ["0", "70000", "x"] {
            let errs = load(&[("UPSTREAMS", "127.0.0.1:1"), ("TLS_PORT", port)]).unwrap_err();
            assert!(errs.iter().any(|e| e.starts_with("TLS_PORT")), "{port}: {errs:?}");
        }
    }

    #[test]
    fn file_settings_have_defaults_and_can_be_changed() {
        let c = load(&[("UPSTREAMS", "127.0.0.1:9000")]).unwrap();
        assert_eq!(
            (c.body_budget, c.file_body_timeout.as_secs(), c.file_finish_timeout.as_secs()),
            (8 << 20, 60, 600)
        );
        let c = load(&[
            ("UPSTREAMS", "127.0.0.1:9000"),
            ("BODY_BUDGET_BYTES", "33554432"),
            ("FILE_BODY_TIMEOUT_SECS", "90"),
            ("FILE_FINISH_TIMEOUT_SECS", "1200"),
        ])
        .unwrap();
        assert_eq!(
            (c.body_budget, c.file_body_timeout.as_secs(), c.file_finish_timeout.as_secs()),
            (32 << 20, 90, 1200)
        );
    }

    #[test]
    fn the_body_budget_is_never_smaller_than_one_body() {
        // otherwise no request could ever be held
        let c = load(&[
            ("UPSTREAMS", "127.0.0.1:9000"),
            ("BODY_BUDGET_BYTES", "0"),
            ("MAX_BODY_BYTES", "2097152"),
        ])
        .unwrap();
        assert_eq!(c.body_budget, 2 << 20);
    }

    #[test]
    fn broken_file_settings_are_refused_together() {
        let errs = load(&[
            ("UPSTREAMS", "127.0.0.1:9000"),
            ("BODY_BUDGET_BYTES", "muito"),
            ("FILE_BODY_TIMEOUT_SECS", "0"),
            ("FILE_FINISH_TIMEOUT_SECS", "999999999"),
        ])
        .unwrap_err();
        assert!(
            errs.iter().any(|e| e.starts_with("BODY_BUDGET_BYTES"))
                && errs.iter().any(|e| e.starts_with("FILE_BODY_TIMEOUT_SECS"))
                && errs.iter().any(|e| e.starts_with("FILE_FINISH_TIMEOUT_SECS")),
            "{errs:?}"
        );
    }
}
