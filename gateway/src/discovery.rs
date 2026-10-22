//! mDNS: announces this gateway as `_plany._tcp` and keeps the list of the other Plany servers
//! on the LAN, which the browser cannot do itself (GET /server/discover/).
use std::{
    collections::HashMap,
    net::{IpAddr, UdpSocket},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use mdns_sd::{IfKind, ServiceDaemon, ServiceEvent, ServiceInfo};
use tokio::time;

pub const SERVICE_TYPE: &str = "_plany._tcp.local.";

#[derive(Clone, Debug, PartialEq)]
pub struct Server {
    pub name: String,
    pub host: String,
    pub ips: Vec<String>,
    pub port: u16,
}

/// Live list of servers found. Hides the entry that is this very gateway.
pub struct Registry {
    found: Mutex<HashMap<String, Server>>,
    own_port: u16,
    own_ips: Vec<String>,
    searches: AtomicU64,
}

impl Registry {
    pub fn new(own_port: u16, own_ips: Vec<String>) -> Self {
        Self {
            found: Mutex::new(HashMap::new()),
            own_port,
            own_ips,
            searches: AtomicU64::new(0),
        }
    }

    pub fn upsert(&self, fullname: String, server: Server) {
        self.found.lock().unwrap().insert(fullname, server);
    }

    pub fn remove(&self, fullname: &str) {
        self.found.lock().unwrap().remove(fullname);
    }

    /// How many times the LAN search was (re)started.
    pub fn searches(&self) -> u64 {
        self.searches.load(Ordering::Relaxed)
    }

    /// The other servers, sorted by name.
    pub fn list(&self) -> Vec<Server> {
        let mut out: Vec<Server> = self
            .found
            .lock()
            .unwrap()
            .values()
            .filter(|s| !(s.port == self.own_port && s.ips.iter().any(|i| self.own_ips.contains(i))))
            .cloned()
            .collect();
        out.sort_by(|a, b| a.name.cmp(&b.name));
        out
    }
}

/// The address used to reach the outside, i.e. the LAN one. No packet is sent.
pub fn lan_ip() -> Option<IpAddr> {
    let s = UdpSocket::bind("0.0.0.0:0").ok()?;
    s.connect("192.0.2.1:9").ok()?;
    s.local_addr().ok().map(|a| a.ip())
}

/// Starts announcing `name` on `port` and browsing for the others. Keep the daemon alive; call
/// `shutdown` to say goodbye on the network.
pub fn start(
    name: &str,
    port: u16,
    lan: Option<IpAddr>,
    ifaces: &[String],
    refresh: Duration,
    registry: Arc<Registry>,
) -> Result<ServiceDaemon, String> {
    let e = |e: mdns_sd::Error| e.to_string();
    let d = ServiceDaemon::new().map_err(e)?;
    d.disable_interface(IfKind::IPv6).map_err(e)?;
    // only the LAN: docker bridges, veth and VPN interfaces would advertise addresses nobody can reach
    if !ifaces.is_empty() || lan.is_some() {
        d.disable_interface(IfKind::All).map_err(e)?;
        for n in ifaces {
            d.enable_interface(IfKind::Name(n.clone())).map_err(e)?;
        }
        if ifaces.is_empty() {
            d.enable_interface(IfKind::Addr(lan.unwrap())).map_err(e)?;
        }
    }
    let host = format!("{}.local.", gethostname::gethostname().to_string_lossy());
    let props = [("name", name)];
    let info = match lan {
        Some(ip) => ServiceInfo::new(SERVICE_TYPE, name, &host, ip, port, &props[..]),
        None => ServiceInfo::new(SERVICE_TYPE, name, &host, "", port, &props[..]).map(|i| i.enable_addr_auto()),
    }
    .map_err(e)?;
    d.register(info).map_err(e)?;
    let first = d.browse(SERVICE_TYPE).map_err(e)?;
    registry.searches.fetch_add(1, Ordering::Relaxed);
    tokio::spawn(browse_loop(d.clone(), first, refresh, registry));
    Ok(d)
}

/// How long to wait before restarting the search: often while nobody else is known (the first
/// answers may have been lost), rarely afterwards.
pub fn next_wait(refresh: Duration, others_known: bool) -> Duration {
    if others_known {
        refresh * 4
    } else {
        refresh
    }
}

fn apply(registry: &Registry, ev: ServiceEvent) {
    match ev {
        ServiceEvent::ServiceResolved(i) => {
            let full = i.get_fullname().to_string();
            let name = full.strip_suffix(&format!(".{SERVICE_TYPE}")).unwrap_or(&full).to_string();
            let mut ips: Vec<String> = i.get_addresses_v4().iter().map(|a| a.to_string()).collect();
            ips.sort();
            let host = i.get_hostname().trim_end_matches('.').trim_end_matches(".local").to_string();
            registry.upsert(
                full,
                Server {
                    name,
                    host,
                    ips,
                    port: i.get_port(),
                },
            );
        }
        ServiceEvent::ServiceRemoved(_, full) => registry.remove(&full),
        _ => {}
    }
}

/// Feeds the registry from the search and restarts it every `refresh` (see `next_wait`). The
/// library resends its query with a delay that doubles up to an hour, and Wi-Fi drops 20-50% of
/// multicast frames, so a lost answer could otherwise delay discovery for minutes. Calling
/// `browse` again replaces the receiver, restarts that backoff at one second and replays the cache.
async fn browse_loop(d: ServiceDaemon, first: mdns_sd::Receiver<ServiceEvent>, refresh: Duration, registry: Arc<Registry>) {
    let mut rx = first;
    loop {
        let restart = time::sleep(if refresh.is_zero() {
            Duration::MAX / 4
        } else {
            next_wait(refresh, !registry.list().is_empty())
        });
        tokio::pin!(restart);
        loop {
            tokio::select! {
                ev = rx.recv_async() => match ev {
                    Ok(ev) => apply(&registry, ev),
                    Err(_) => return, // the daemon was shut down
                },
                _ = &mut restart => break,
            }
        }
        match d.browse(SERVICE_TYPE) {
            Ok(next) => {
                registry.searches.fetch_add(1, Ordering::Relaxed);
                rx = next;
            }
            Err(_) => return,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn srv(name: &str, ip: &str, port: u16) -> Server {
        Server {
            name: name.into(),
            host: "h".into(),
            ips: vec![ip.into()],
            port,
        }
    }

    #[test]
    fn list_hides_this_gateway_and_is_sorted() {
        let r = Registry::new(8200, vec!["192.168.1.5".into()]);
        r.upsert("b".into(), srv("B", "192.168.1.9", 8200));
        r.upsert("me".into(), srv("Me", "192.168.1.5", 8200));
        r.upsert("a".into(), srv("A", "192.168.1.7", 9000));
        assert_eq!(r.list().iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["A", "B"]);
    }

    #[test]
    fn same_port_on_another_machine_is_not_me() {
        let r = Registry::new(8200, vec!["192.168.1.5".into()]);
        r.upsert("x".into(), srv("X", "192.168.1.6", 8200));
        assert_eq!(r.list().len(), 1);
    }

    #[test]
    fn search_restarts_often_while_alone_and_rarely_once_others_are_known() {
        let r = Duration::from_secs(15);
        assert_eq!(next_wait(r, false), Duration::from_secs(15));
        assert_eq!(next_wait(r, true), Duration::from_secs(60));
    }

    #[test]
    fn remove_forgets_a_server() {
        let r = Registry::new(1, vec![]);
        r.upsert("x".into(), srv("X", "10.0.0.1", 2));
        r.remove("x");
        r.remove("never-existed");
        assert!(r.list().is_empty());
    }
}
