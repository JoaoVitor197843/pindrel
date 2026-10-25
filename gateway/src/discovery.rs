//! mDNS: announces this gateway as `_plany._tcp` and keeps the list of the other Plany servers
//! on the LAN, which the browser cannot do itself (GET /server/discover/).
use std::{
    collections::{HashMap, HashSet},
    net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use mdns_sd::{IfKind, ServiceDaemon, ServiceEvent, ServiceInfo};
use tokio::{sync::Notify, time};

pub const SERVICE_TYPE: &str = "_plany._tcp.local.";

/// Most servers kept from live announcements and from the memory of past ones. Anyone on the LAN
/// can announce anything, so the tables must not grow with what they are told.
const MAX_LIVE: usize = 256;
const MAX_KNOWN: usize = 64;
/// What `list` hands out, which is what the web reads: it throws away an answer over 64 KiB, so one device flooding
/// the LAN with announcements must not be able to make the whole list disappear. Same limits the web applies.
const MAX_LISTED: usize = 64;
const MAX_NAME_CHARS: usize = 64;
const MAX_LISTED_ADDRESSES: usize = 8;

/// An id is what a server chose for itself and then travels over the network: only plain, short text is accepted.
pub fn valid_id(id: &str) -> bool {
    (1..=64).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

#[derive(Clone, Debug, PartialEq)]
pub struct Server {
    pub name: String,
    pub host: String,
    /// Random id the server keeps between runs (`identity`); empty for an older server that announces none.
    pub id: String,
    pub ips: Vec<String>,
    pub port: u16,
}

/// The local network of this machine (its LAN address and netmask).
///
/// mDNS announcements are untrusted: whoever is on the LAN can announce a server at any address.
/// The gateway only ever *connects* to an announced address when it is in this very subnet, so
/// nobody can use it to probe loopback, other networks or the internet.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Lan {
    pub ip: Ipv4Addr,
    pub mask: Ipv4Addr,
}

impl Lan {
    pub fn new(ip: Ipv4Addr, mask: Ipv4Addr) -> Self {
        Self { ip, mask }
    }

    /// The LAN of this machine: an interface that is up, not a tunnel (Tailscale and other VPNs are
    /// point-to-point, and mDNS does not cross them), with a private IPv4 address. When several qualify
    /// (docker bridges, a second NIC) the one the default route uses wins, then a physical one.
    pub fn detect() -> Option<Lan> {
        let route = route_ip();
        let candidates: Vec<Candidate> = netdev::get_interfaces()
            .iter()
            .filter(|i| i.is_up() && i.is_running() && !i.is_loopback() && !i.is_tun() && !i.is_point_to_point())
            .flat_map(|i| {
                let physical = i.is_physical();
                i.ipv4.iter().map(move |n| Candidate {
                    lan: Lan::new(n.addr(), n.netmask()),
                    physical,
                })
            })
            .collect();
        pick(candidates, route)
    }

    /// Whether `ip` is another host of this subnet (never ourselves or a special address). Loopback is
    /// refused because no real LAN subnet contains it.
    pub fn allows(&self, ip: Ipv4Addr) -> bool {
        let mask = u32::from(self.mask);
        let host_bits = !mask;
        mask != 0
            && u32::from(ip) & host_bits != 0 // the network address
            && u32::from(ip) & host_bits != host_bits // the subnet broadcast address
            && ip != self.ip
            && !(ip.is_unspecified() || ip.is_multicast() || ip.is_broadcast())
            && u32::from(ip) & mask == u32::from(self.ip) & mask
    }
}

/// An address of an interface that is not a tunnel, as `Lan::detect` sees it.
struct Candidate {
    lan: Lan,
    physical: bool,
}

/// Private addresses only: a public one means the machine is directly on the internet (no LAN to
/// announce on), and 100.64/10 or 169.254/16 are VPNs and link-local, never a LAN.
fn pick(mut candidates: Vec<Candidate>, route: Option<Ipv4Addr>) -> Option<Lan> {
    candidates.retain(|c| c.lan.ip.is_private());
    // false sorts first, so "uses the default route" and "is physical" are negated
    candidates.sort_by_key(|c| (Some(c.lan.ip) != route, !c.physical, c.lan.ip));
    candidates.into_iter().next().map(|c| c.lan)
}

struct Remembered {
    server: Server,
    /// The addresses that accepted a connection the last time they were tried (or were just announced).
    verified: Vec<String>,
    seq: u64,
}

#[derive(Default)]
struct Memory {
    by_name: HashMap<String, Remembered>,
    seq: u64,
}

/// Live list of servers found, plus a memory of the ones seen before. Hides this very gateway.
///
/// A server that stops being announced (a lost refresh on a lossy Wi-Fi, or it really left) is not
/// dropped at once: it is remembered, and `known::run` tries its addresses again. It stays listed
/// as long as it answers.
pub struct Registry {
    found: Mutex<HashMap<String, Server>>,
    memory: Mutex<Memory>,
    own_port: u16,
    own_ips: Vec<String>,
    own_id: String,
    /// Announced addresses outside it (a VPN such as Tailscale, docker bridges) are dropped: mDNS does not
    /// cross them, so nobody on this LAN could use them.
    lan: Option<Lan>,
    searches: AtomicU64,
    /// Woken when a server stops being announced, so it is checked right away.
    pub lost: Notify,
}

impl Registry {
    pub fn new(own_port: u16, own_ips: Vec<String>) -> Self {
        Self {
            found: Mutex::new(HashMap::new()),
            memory: Mutex::new(Memory::default()),
            own_port,
            own_ips,
            own_id: String::new(),
            lan: None,
            searches: AtomicU64::new(0),
            lost: Notify::new(),
        }
    }

    /// This gateway's own id, so that it hides itself from the list even when its addresses differ.
    pub fn with_id(mut self, id: String) -> Self {
        self.own_id = id;
        self
    }

    pub fn id(&self) -> &str {
        &self.own_id
    }

    pub fn with_lan(mut self, lan: Option<Lan>) -> Self {
        self.lan = lan;
        self
    }

    fn is_self(&self, s: &Server) -> bool {
        (!s.id.is_empty() && s.id == self.own_id) || (s.port == self.own_port && s.ips.iter().any(|i| self.own_ips.contains(i)))
    }

    pub fn upsert(&self, fullname: String, mut server: Server) {
        if let Some(lan) = &self.lan {
            // our own address is not "another host" for `allows`, but it must reach `is_self`
            server
                .ips
                .retain(|i| i.parse().is_ok_and(|ip: Ipv4Addr| ip == lan.ip || lan.allows(ip)));
            if server.ips.is_empty() {
                return;
            }
        }
        {
            let mut f = self.found.lock().unwrap();
            if f.len() >= MAX_LIVE && !f.contains_key(&fullname) {
                return;
            }
            f.insert(fullname, server.clone());
        }
        self.remember(server.clone(), server.ips);
    }

    pub fn remove(&self, fullname: &str) {
        let gone = self.found.lock().unwrap().remove(fullname);
        let Some(gone) = gone else { return };
        if self.found.lock().unwrap().values().any(|s| s.name == gone.name) {
            return; // still announced on another interface
        }
        if let Some(r) = self.memory.lock().unwrap().by_name.get_mut(&gone.name) {
            r.verified.clear(); // no longer announced: it has to prove it is still there
        }
        self.lost.notify_one();
    }

    fn remember(&self, server: Server, verified: Vec<String>) {
        let mut m = self.memory.lock().unwrap();
        m.seq += 1;
        let seq = m.seq;
        if m.by_name.len() >= MAX_KNOWN && !m.by_name.contains_key(&server.name) {
            // make room by forgetting the least recently seen
            if let Some(oldest) = m.by_name.iter().min_by_key(|(_, r)| r.seq).map(|(n, _)| n.clone()) {
                m.by_name.remove(&oldest);
            }
        }
        m.by_name.insert(server.name.clone(), Remembered { server, verified, seq });
    }

    /// How many times the LAN search was (re)started.
    pub fn searches(&self) -> u64 {
        self.searches.load(Ordering::Relaxed)
    }

    /// The other servers, sorted by name: the ones announced now, plus the remembered ones that
    /// answered the last check.
    pub fn list(&self) -> Vec<Server> {
        let live: Vec<Server> = self.found.lock().unwrap().values().filter(|s| !self.is_self(s)).cloned().collect();
        let announced: HashSet<&str> = live.iter().map(|s| s.name.as_str()).collect();
        let mut out = live.clone();
        for r in self.memory.lock().unwrap().by_name.values() {
            if announced.contains(r.server.name.as_str()) || r.verified.is_empty() {
                continue;
            }
            let s = Server {
                ips: r.verified.clone(),
                ..r.server.clone()
            };
            if !self.is_self(&s) {
                out.push(s);
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        out.truncate(MAX_LISTED);
        for s in &mut out {
            s.name
                .truncate(s.name.char_indices().nth(MAX_NAME_CHARS).map_or(s.name.len(), |(i, _)| i));
            s.host
                .truncate(s.host.char_indices().nth(MAX_NAME_CHARS).map_or(s.host.len(), |(i, _)| i));
            s.ips.truncate(MAX_LISTED_ADDRESSES);
        }
        out
    }

    /// What to try again: the remembered servers that are not announced now, with the addresses
    /// that may be tried (see `Lan`; ports below 1024 are never tried).
    pub fn probe_targets(&self, lan: &Lan) -> Vec<(String, Vec<SocketAddr>)> {
        let announced: HashSet<String> = self.found.lock().unwrap().values().map(|s| s.name.clone()).collect();
        let m = self.memory.lock().unwrap();
        let mut out = Vec::new();
        for (name, r) in &m.by_name {
            if announced.contains(name) || r.server.port < 1024 {
                continue;
            }
            let addrs: Vec<SocketAddr> = r
                .server
                .ips
                .iter()
                .filter_map(|i| i.parse::<Ipv4Addr>().ok())
                .filter(|ip| lan.allows(*ip))
                .map(|ip| SocketAddr::new(IpAddr::V4(ip), r.server.port))
                .collect();
            if !addrs.is_empty() {
                out.push((name.clone(), addrs));
            }
        }
        out
    }

    /// Records which addresses of a remembered server answered.
    pub fn set_verified(&self, name: &str, ips: Vec<String>) {
        if let Some(r) = self.memory.lock().unwrap().by_name.get_mut(name) {
            r.verified = ips;
        }
    }

    /// Everything remembered, to be saved.
    pub fn snapshot(&self) -> Vec<Server> {
        let mut v: Vec<Server> = self.memory.lock().unwrap().by_name.values().map(|r| r.server.clone()).collect();
        v.sort_by(|a, b| a.name.cmp(&b.name));
        v
    }

    /// Adds servers remembered from an earlier run; they are listed once checked.
    pub fn load(&self, servers: Vec<Server>) {
        for s in servers {
            if !self.is_self(&s) {
                self.remember(s, Vec::new());
            }
        }
    }
}

/// The source address of the default route. Only a hint to choose among the LAN interfaces: with a
/// VPN exit node this is the tunnel's address, which `Lan::detect` never accepts. No packet is sent.
fn route_ip() -> Option<Ipv4Addr> {
    let s = UdpSocket::bind("0.0.0.0:0").ok()?;
    s.connect("192.0.2.1:9").ok()?;
    match s.local_addr().ok()?.ip() {
        IpAddr::V4(ip) => Some(ip),
        IpAddr::V6(_) => None,
    }
}

/// The address of the LAN this machine is on, see `Lan::detect`.
pub fn lan_ip() -> Option<IpAddr> {
    Lan::detect().map(|l| IpAddr::V4(l.ip))
}

/// Starts announcing `name` on `port` and browsing for the others. Keep the daemon alive; call
/// `shutdown` to say goodbye on the network.
pub fn start(
    name: &str,
    id: &str,
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
    let props = [("name", name), ("id", id)];
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
            let id = i.get_property_val_str("id").filter(|v| valid_id(v)).unwrap_or_default().to_string();
            let host = i.get_hostname().trim_end_matches('.').trim_end_matches(".local").to_string();
            registry.upsert(
                full,
                Server {
                    name,
                    host,
                    id,
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
            id: String::new(),
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
    fn addresses_outside_the_lan_are_not_listed() {
        let r = Registry::new(1, vec![]).with_lan(Some(lan()));
        let mut s = srv("X", "100.101.1.2", 8200);
        s.ips.push("192.168.1.9".into());
        r.upsert("x".into(), s);
        assert_eq!(r.list()[0].ips, ["192.168.1.9"]);
        r.upsert("y".into(), srv("Y", "100.101.1.3", 8200));
        assert_eq!(r.list().len(), 1, "a server reachable only outside the LAN is not listed");
    }

    fn cand(ip: &str, physical: bool) -> Candidate {
        Candidate {
            lan: Lan::new(ip.parse().unwrap(), "255.255.255.0".parse().unwrap()),
            physical,
        }
    }

    #[test]
    fn the_lan_is_never_a_vpn_or_link_local_address() {
        let none = pick(
            vec![cand("100.96.228.54", true), cand("169.254.3.4", true), cand("8.8.8.8", true)],
            None,
        );
        assert_eq!(none, None);
    }

    #[test]
    fn the_default_route_wins_then_a_physical_interface_then_the_lowest_address() {
        let ip = |l: Option<Lan>| l.unwrap().ip.to_string();
        let all = || vec![cand("172.18.0.1", false), cand("192.168.1.163", true), cand("10.0.0.2", true)];
        assert_eq!(ip(pick(all(), Some("172.18.0.1".parse().unwrap()))), "172.18.0.1");
        // the route goes through a VPN exit node: its address is not a candidate, so it is only ignored
        assert_eq!(ip(pick(all(), Some("100.96.228.54".parse().unwrap()))), "10.0.0.2");
        assert_eq!(
            ip(pick(vec![cand("172.18.0.1", false), cand("192.168.1.9", true)], None)),
            "192.168.1.9"
        );
    }

    #[test]
    fn this_gateway_is_hidden_by_its_id_even_when_it_is_announced_from_other_addresses() {
        let r = Registry::new(8200, vec!["192.168.1.5".into()]).with_id("abc".into());
        let mut me = srv("Me", "10.9.9.9", 1234);
        me.id = "abc".into();
        r.upsert("me".into(), me);
        let mut other = srv("Other", "192.168.1.6", 8200);
        other.id = "def".into();
        r.upsert("o".into(), other);
        assert_eq!(r.list().iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["Other"]);
    }

    #[test]
    fn only_short_plain_text_is_an_id() {
        for ok in ["a", "0123456789abcdef0123456789abcdef", "Casa-2025", &"x".repeat(64)] {
            assert!(valid_id(ok), "{ok:?}");
        }
        for bad in ["", " ", "a b", "a/b", "a\nb", "ü", &"x".repeat(65), "a;b", "<b>"] {
            assert!(!valid_id(bad), "{bad:?}");
        }
    }

    #[test]
    fn same_port_on_another_machine_is_not_me() {
        let r = Registry::new(8200, vec!["192.168.1.5".into()]);
        r.upsert("x".into(), srv("X", "192.168.1.6", 8200));
        assert_eq!(r.list().len(), 1);
    }

    fn lan() -> Lan {
        Lan::new("192.168.1.5".parse().unwrap(), "255.255.255.0".parse().unwrap())
    }

    #[test]
    fn only_other_hosts_of_the_same_subnet_may_be_tried() {
        let l = lan();
        for ok in ["192.168.1.9", "192.168.1.1", "192.168.1.254"] {
            assert!(l.allows(ok.parse().unwrap()), "{ok}");
        }
        for no in [
            "192.168.1.5",     // ourselves
            "192.168.1.0",     // network address
            "192.168.1.255",   // subnet broadcast
            "192.168.2.9",     // another subnet
            "10.0.0.1",        // another private network
            "8.8.8.8",         // the internet
            "127.0.0.1",       // loopback: services of this very machine
            "169.254.169.254", // link-local / cloud metadata
            "0.0.0.0",
            "224.0.0.251",
            "255.255.255.255",
        ] {
            assert!(!l.allows(no.parse().unwrap()), "{no} must never be tried");
        }
        assert!(
            !Lan::new("10.0.0.5".parse().unwrap(), "0.0.0.0".parse().unwrap()).allows("1.2.3.4".parse().unwrap()),
            "a zero mask would allow everything"
        );
    }

    #[test]
    fn a_server_that_stops_being_announced_is_listed_again_only_after_it_answers() {
        let r = Registry::new(1, vec![]);
        r.upsert("a".into(), srv("A", "192.168.1.9", 8080));
        r.remove("a");
        assert!(r.list().is_empty(), "not announced and not verified yet");
        r.set_verified("A", vec!["192.168.1.9".into()]);
        assert_eq!(r.list(), [srv("A", "192.168.1.9", 8080)]);
        r.set_verified("A", vec![]);
        assert!(r.list().is_empty(), "it stopped answering");
    }

    #[test]
    fn only_the_addresses_that_answered_are_listed() {
        let r = Registry::new(1, vec![]);
        let mut s = srv("A", "192.168.1.9", 8080);
        s.ips.push("192.168.1.10".into());
        r.upsert("a".into(), s);
        r.remove("a");
        r.set_verified("A", vec!["192.168.1.10".into()]);
        assert_eq!(r.list()[0].ips, ["192.168.1.10"]);
    }

    #[test]
    fn an_announced_server_shadows_its_memory_and_is_never_listed_twice() {
        let r = Registry::new(1, vec![]);
        r.upsert("a".into(), srv("A", "192.168.1.9", 8080));
        r.remove("a");
        r.set_verified("A", vec!["192.168.1.9".into()]);
        r.upsert("a2".into(), srv("A", "192.168.1.9", 8080));
        assert_eq!(r.list().len(), 1);
        assert!(r.probe_targets(&lan()).is_empty(), "no need to try what is announced");
    }

    #[test]
    fn losing_one_interface_does_not_forget_a_server_still_announced_on_another() {
        let r = Registry::new(1, vec![]);
        r.upsert("a-eth".into(), srv("A", "192.168.1.9", 8080));
        r.upsert("a-wifi".into(), srv("A", "192.168.1.9", 8080));
        r.remove("a-eth");
        assert_eq!(r.list().len(), 1);
        assert!(r.probe_targets(&lan()).is_empty());
    }

    #[test]
    fn probe_targets_are_limited_to_the_local_subnet_and_to_ports_from_1024() {
        let r = Registry::new(1, vec![]);
        r.load(vec![
            srv("fine", "192.168.1.9", 8080),
            srv("other-subnet", "10.1.1.1", 8080),
            srv("loopback", "127.0.0.1", 8080),
            srv("internet", "8.8.8.8", 8080),
            srv("low-port", "192.168.1.20", 22),
            srv("not-an-ip", "evil.example", 8080),
            Server {
                ips: vec!["10.1.1.1".into(), "192.168.1.30".into()],
                ..srv("mixed", "x", 9000)
            },
        ]);
        let mut t = r.probe_targets(&lan());
        t.sort();
        let t: Vec<(String, Vec<String>)> = t.into_iter().map(|(n, a)| (n, a.iter().map(|x| x.to_string()).collect())).collect();
        assert_eq!(
            t,
            [
                ("fine".to_string(), vec!["192.168.1.9:8080".to_string()]),
                ("mixed".to_string(), vec!["192.168.1.30:9000".to_string()])
            ]
        );
    }

    #[test]
    fn what_is_loaded_from_a_file_is_not_listed_until_it_answers_and_never_includes_this_gateway() {
        let r = Registry::new(8080, vec!["192.168.1.5".into()]);
        r.load(vec![srv("A", "192.168.1.9", 8080), srv("Me", "192.168.1.5", 8080)]);
        assert!(r.list().is_empty());
        assert_eq!(r.snapshot().iter().map(|s| s.name.as_str()).collect::<Vec<_>>(), ["A"]);
    }

    #[test]
    fn the_answer_stays_far_below_what_the_web_accepts_whatever_is_announced() {
        let r = Registry::new(1, vec![]);
        for i in 0..400 {
            let long = "é".repeat(200);
            let mut s = srv(&format!("{long}{i:04}"), "192.168.1.9", 8000);
            s.host = long.clone();
            s.ips = (0..40).map(|n| format!("192.168.1.{n}")).collect();
            r.upsert(format!("f{i}"), s);
        }
        let list = r.list();
        assert_eq!(list.len(), MAX_LISTED);
        assert!(list
            .iter()
            .all(|s| s.name.chars().count() <= 64 && s.host.chars().count() <= 64 && s.ips.len() <= 8));
        assert!(
            crate::proto::discovered_servers(&list).len() < 32 * 1024,
            "web discards over 64 KiB"
        );
    }

    #[test]
    fn the_tables_cannot_be_grown_without_limit_by_what_the_network_announces() {
        // literal numbers on purpose: changing a limit should be a decision, not a side effect
        let r = Registry::new(1, vec![]);
        for i in 0..306 {
            r.upsert(format!("f{i}"), srv(&format!("S{i}"), "192.168.1.9", 8080));
        }
        assert_eq!(r.found.lock().unwrap().len(), 256, "at most 256 announced servers are kept");
        assert_eq!(r.list().len(), 64, "and at most 64 are handed out");
        // the memory keeps the 64 most recently seen of the accepted ones
        let names: Vec<String> = r.snapshot().into_iter().map(|s| s.name).collect();
        assert_eq!(names.len(), 64);
        assert!(names.contains(&"S255".to_string()), "the newest accepted one is remembered");
        assert!(!names.contains(&"S0".to_string()), "the oldest was forgotten to make room");
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
