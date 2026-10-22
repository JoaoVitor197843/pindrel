//! Per-client token buckets. The gateway is the single entry point, so keeping the counters here
//! (and not in the API replicas) is what keeps the API stateless.
use std::{
    collections::HashMap,
    net::{IpAddr, Ipv6Addr},
    sync::Mutex,
    time::{Duration, Instant},
};

/// Hard cap on tracked clients, so a flood of source addresses cannot grow the table forever.
const MAX_TRACKED: usize = 65_536;

pub struct Limiter {
    per_sec: f64,
    burst: f64,
    map: Mutex<HashMap<IpAddr, (f64, Instant)>>,
}

/// IPv6 clients usually own a whole /64: limit that prefix, not each address inside it.
fn key(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => {
                let o = v6.octets();
                IpAddr::V6(Ipv6Addr::from([
                    o[0], o[1], o[2], o[3], o[4], o[5], o[6], o[7], 0, 0, 0, 0, 0, 0, 0, 0,
                ]))
            }
        },
        v4 => v4,
    }
}

impl Limiter {
    /// `per_minute` tokens refill each minute, up to `burst`.
    pub fn new(per_minute: f64, burst: f64) -> Self {
        Self {
            per_sec: per_minute / 60.0,
            burst,
            map: Mutex::new(HashMap::new()),
        }
    }

    pub fn allow(&self, ip: IpAddr) -> bool {
        self.allow_at(ip, Instant::now())
    }

    fn allow_at(&self, ip: IpAddr, now: Instant) -> bool {
        let mut m = self.map.lock().unwrap();
        if m.len() >= MAX_TRACKED && !m.contains_key(&key(ip)) {
            // drop the clients that are back to a full bucket (they lose nothing), then give up if still full
            let (per_sec, burst) = (self.per_sec, self.burst);
            m.retain(|_, (t, at)| *t + now.saturating_duration_since(*at).as_secs_f64() * per_sec < burst);
            if m.len() >= MAX_TRACKED {
                return false;
            }
        }
        let e = m.entry(key(ip)).or_insert((self.burst, now));
        e.0 = (e.0 + now.saturating_duration_since(e.1).as_secs_f64() * self.per_sec).min(self.burst);
        e.1 = now;
        if e.0 >= 1.0 {
            e.0 -= 1.0;
            true
        } else {
            false
        }
    }

    /// Forget clients not seen for `older_than`.
    pub fn prune(&self, older_than: Duration) {
        self.map.lock().unwrap().retain(|_, v| v.1.elapsed() < older_than);
    }

    pub fn tracked(&self) -> usize {
        self.map.lock().unwrap().len()
    }
}

/// The three limits applied at the entry point (same numbers the Go middleware used).
pub struct Limiters {
    pub login: Limiter,
    pub register: Limiter,
    pub global: Limiter,
}

impl Limiters {
    pub fn standard() -> Self {
        Self {
            login: Limiter::new(5.0, 5.0),
            register: Limiter::new(5.0, 5.0),
            global: Limiter::new(100.0, 20.0),
        }
    }
    pub fn prune(&self, older_than: Duration) {
        for l in [&self.login, &self.register, &self.global] {
            l.prune(older_than);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    #[test]
    fn blocks_after_the_burst_and_is_per_client() {
        let l = Limiter::new(0.0, 2.0);
        let t = Instant::now();
        assert!(l.allow_at(ip("10.0.0.1"), t) && l.allow_at(ip("10.0.0.1"), t) && !l.allow_at(ip("10.0.0.1"), t));
        assert!(l.allow_at(ip("10.0.0.2"), t));
    }

    #[test]
    fn refills_over_time_but_never_above_the_burst() {
        let l = Limiter::new(60.0, 2.0); // 1 token per second
        let t = Instant::now();
        assert!(l.allow_at(ip("10.0.0.1"), t) && l.allow_at(ip("10.0.0.1"), t) && !l.allow_at(ip("10.0.0.1"), t));
        let later = t + Duration::from_secs(1);
        assert!(l.allow_at(ip("10.0.0.1"), later) && !l.allow_at(ip("10.0.0.1"), later));
        let much_later = t + Duration::from_secs(3600);
        assert!(
            l.allow_at(ip("10.0.0.1"), much_later) && l.allow_at(ip("10.0.0.1"), much_later) && !l.allow_at(ip("10.0.0.1"), much_later)
        );
    }

    #[test]
    fn an_ipv6_prefix_shares_one_bucket() {
        let l = Limiter::new(0.0, 1.0);
        let t = Instant::now();
        assert!(l.allow_at(ip("2001:db8:1:2::1"), t));
        assert!(!l.allow_at(ip("2001:db8:1:2:ffff::9"), t), "same /64 must be the same client");
        assert!(l.allow_at(ip("2001:db8:1:3::1"), t), "another /64 is another client");
    }

    #[test]
    fn ipv4_mapped_ipv6_is_the_ipv4_client() {
        let l = Limiter::new(0.0, 1.0);
        let t = Instant::now();
        assert!(l.allow_at(ip("203.0.113.9"), t));
        assert!(!l.allow_at(ip("::ffff:203.0.113.9"), t));
    }

    #[test]
    fn prune_forgets_idle_clients() {
        let l = Limiter::new(60.0, 2.0);
        l.allow(ip("10.0.0.1"));
        assert_eq!(l.tracked(), 1);
        l.prune(Duration::ZERO);
        assert_eq!(l.tracked(), 0);
    }

    #[test]
    fn the_table_cannot_grow_without_bound() {
        let l = Limiter::new(0.0, 1.0);
        let t = Instant::now();
        for i in 0..MAX_TRACKED as u32 {
            assert!(l.allow_at(IpAddr::V4(std::net::Ipv4Addr::from(i + 1)), t));
        }
        assert_eq!(l.tracked(), MAX_TRACKED);
        // everyone is spent (not full), so a new client is refused instead of growing the table
        assert!(!l.allow_at(ip("203.0.113.200"), t));
        assert_eq!(l.tracked(), MAX_TRACKED);
    }
}
