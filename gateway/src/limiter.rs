//! Per-client rate limits. The gateway is the single entry point, so keeping the counters here
//! (and not in the API replicas) is what keeps the API stateless.
//!
//! The limiting itself (GCRA, a token bucket stored as one timestamp per client) and the clock come from
//! `governor`. What is ours is the table of clients: it has a hard cap, which governor's own stores do not.
use std::{
    collections::HashMap,
    net::{IpAddr, Ipv6Addr},
    num::NonZeroU32,
    sync::{Arc, Mutex},
    time::Duration,
};

use governor::{
    clock::{Clock, DefaultClock},
    middleware::NoOpMiddleware,
    nanos::Nanos,
    state::{keyed::ShrinkableKeyedStateStore, StateStore},
    Quota, RateLimiter,
};

/// Hard cap on tracked clients per limiter, so a flood of source addresses cannot grow the table forever
/// (about 60 bytes each: this is the number that bounds the gateway's memory, see `MAX_TRACKED_BYTES` in the tests).
const MAX_TRACKED: usize = 16_384;

/// Longest `Retry-After` we ever announce.
const MAX_RETRY_AFTER: Duration = Duration::from_secs(3600);

/// The table of clients: the theoretical arrival time (GCRA state) of each one, and a cap.
/// A new client that finds the table full is refused instead of growing it.
pub struct CappedStore {
    map: Mutex<HashMap<IpAddr, Nanos>>,
    cap: usize,
}

impl CappedStore {
    fn new(cap: usize) -> Self {
        Self {
            map: Mutex::new(HashMap::new()),
            cap,
        }
    }
}

impl StateStore for CappedStore {
    type Key = IpAddr;

    fn measure_and_replace<T, F, E>(&self, key: &IpAddr, f: F) -> Result<T, E>
    where
        F: Fn(Option<Nanos>) -> Result<(T, Nanos), E>,
    {
        let mut map = self.map.lock().unwrap();
        if let Some(state) = map.get_mut(key) {
            let (verdict, next) = f(Some(*state))?;
            *state = next;
            return Ok(verdict);
        }
        if map.len() >= self.cap {
            // Full: answer as a client whose bucket is spent for a very long time, and store nothing.
            // `f` returns its `Err` (rate limited) for that state without ever touching the table.
            return f(Some(Nanos::from(u64::MAX / 2))).map(|(v, _)| v);
        }
        let (verdict, next) = f(None)?;
        map.insert(*key, next);
        Ok(verdict)
    }
}

impl ShrinkableKeyedStateStore<IpAddr> for CappedStore {
    fn retain_recent(&self, drop_below: Nanos) {
        // a client whose bucket is back to full is the same as a client we never saw: it costs nothing to forget
        self.map.lock().unwrap().retain(|_, tat| tat.as_u64() > drop_below.as_u64());
    }
    fn shrink_to_fit(&self) {
        self.map.lock().unwrap().shrink_to_fit();
    }
    fn len(&self) -> usize {
        self.map.lock().unwrap().len()
    }
    fn is_empty(&self) -> bool {
        self.map.lock().unwrap().is_empty()
    }
}

pub struct Limiter<C: Clock = DefaultClock> {
    inner: RateLimiter<IpAddr, CappedStore, C, NoOpMiddleware<C::Instant>>,
    cap: usize,
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
    /// `per_minute` requests are replenished each minute, up to a `burst` in a row.
    pub fn new(per_minute: u32, burst: u32) -> Self {
        let quota =
            Quota::per_minute(NonZeroU32::new(per_minute).expect("per_minute > 0")).allow_burst(NonZeroU32::new(burst).expect("burst > 0"));
        Self::with(quota, MAX_TRACKED, DefaultClock::default())
    }
}

impl<C: Clock> Limiter<C> {
    fn with(quota: Quota, cap: usize, clock: C) -> Self {
        Self {
            inner: RateLimiter::new(quota, CappedStore::new(cap), clock),
            cap,
        }
    }

    /// `Ok` if the request may go on, `Err(how long to wait)` if the client is over its limit.
    pub fn check(&self, ip: IpAddr) -> Result<(), Duration> {
        let k = key(ip);
        if self.inner.len() >= self.cap {
            self.inner.retain_recent(); // make room by forgetting clients that are back to a full bucket
        }
        self.inner
            .check_key(&k)
            .map_err(|not_until| not_until.wait_time_from(self.inner.clock().now()).min(MAX_RETRY_AFTER))
    }

    pub fn allow(&self, ip: IpAddr) -> bool {
        self.check(ip).is_ok()
    }

    /// Forget the clients that are back to a full bucket.
    pub fn prune(&self) {
        self.inner.retain_recent();
        self.inner.shrink_to_fit();
    }

    pub fn tracked(&self) -> usize {
        self.inner.len()
    }
}

/// Open connections per client. The request limits count requests, not connections: without this one address
/// can hold every connection permit with sockets that stay open, and nobody else gets in.
pub struct ConnLimit {
    per_client: usize,
    open: Mutex<HashMap<IpAddr, usize>>,
}

/// One open connection of a client; the slot is given back when it is dropped.
pub struct ConnGuard {
    limit: Arc<ConnLimit>,
    client: IpAddr,
}

impl ConnLimit {
    pub fn new(per_client: usize) -> Arc<Self> {
        Arc::new(Self {
            per_client,
            open: Mutex::new(HashMap::new()),
        })
    }

    /// `None` if this client already has `per_client` connections open. The table only holds clients that have a
    /// connection open, so it is bounded by the total connection limit.
    pub fn acquire(self: &Arc<Self>, ip: IpAddr) -> Option<ConnGuard> {
        let client = key(ip);
        let mut open = self.open.lock().unwrap();
        let n = open.entry(client).or_insert(0);
        if *n >= self.per_client {
            return None;
        }
        *n += 1;
        Some(ConnGuard {
            limit: self.clone(),
            client,
        })
    }

    pub fn clients(&self) -> usize {
        self.open.lock().unwrap().len()
    }
}

impl Drop for ConnGuard {
    fn drop(&mut self) {
        let mut open = self.limit.open.lock().unwrap();
        if let Some(n) = open.get_mut(&self.client) {
            *n -= 1;
            if *n == 0 {
                open.remove(&self.client);
            }
        }
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
            login: Limiter::new(5, 5),
            register: Limiter::new(5, 5),
            global: Limiter::new(100, 20),
        }
    }
    pub fn prune(&self) {
        for l in [&self.login, &self.register, &self.global] {
            l.prune();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use governor::clock::FakeRelativeClock;
    use std::net::Ipv4Addr;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    /// A limiter on a clock we move by hand. `period` is the time to earn one request back.
    fn limiter(period: Duration, burst: u32, cap: usize) -> (Limiter<FakeRelativeClock>, FakeRelativeClock) {
        let clock = FakeRelativeClock::default();
        let quota = Quota::with_period(period).unwrap().allow_burst(NonZeroU32::new(burst).unwrap());
        (Limiter::with(quota, cap, clock.clone()), clock)
    }

    const NEVER: Duration = Duration::from_secs(10 * 365 * 24 * 3600);

    #[test]
    fn blocks_after_the_burst_and_is_per_client() {
        let (l, _) = limiter(NEVER, 2, 100);
        assert!(l.allow(ip("10.0.0.1")) && l.allow(ip("10.0.0.1")) && !l.allow(ip("10.0.0.1")));
        assert!(l.allow(ip("10.0.0.2")));
    }

    #[test]
    fn refills_over_time_but_never_above_the_burst() {
        let (l, clock) = limiter(Duration::from_secs(1), 2, 100); // 1 request per second back
        assert!(l.allow(ip("10.0.0.1")) && l.allow(ip("10.0.0.1")) && !l.allow(ip("10.0.0.1")));
        clock.advance(Duration::from_secs(1));
        assert!(l.allow(ip("10.0.0.1")) && !l.allow(ip("10.0.0.1")));
        clock.advance(Duration::from_secs(3600));
        assert!(l.allow(ip("10.0.0.1")) && l.allow(ip("10.0.0.1")) && !l.allow(ip("10.0.0.1")));
    }

    #[test]
    fn says_how_long_to_wait() {
        let (l, clock) = limiter(Duration::from_secs(10), 1, 100);
        assert_eq!(l.check(ip("10.0.0.1")), Ok(()));
        assert_eq!(l.check(ip("10.0.0.1")), Err(Duration::from_secs(10)));
        clock.advance(Duration::from_secs(4));
        assert_eq!(l.check(ip("10.0.0.1")), Err(Duration::from_secs(6)));
        clock.advance(Duration::from_secs(6));
        assert_eq!(l.check(ip("10.0.0.1")), Ok(()));
    }

    #[test]
    fn an_ipv6_prefix_shares_one_bucket() {
        let (l, _) = limiter(NEVER, 1, 100);
        assert!(l.allow(ip("2001:db8:1:2::1")));
        assert!(!l.allow(ip("2001:db8:1:2:ffff::9")), "same /64 must be the same client");
        assert!(l.allow(ip("2001:db8:1:3::1")), "another /64 is another client");
    }

    #[test]
    fn ipv4_mapped_ipv6_is_the_ipv4_client() {
        let (l, _) = limiter(NEVER, 1, 100);
        assert!(l.allow(ip("203.0.113.9")));
        assert!(!l.allow(ip("::ffff:203.0.113.9")));
    }

    #[test]
    fn prune_forgets_clients_back_to_a_full_bucket_and_keeps_the_others() {
        // governor keeps a client for one extra period after its bucket is full again (a conservative slack)
        let (l, clock) = limiter(Duration::from_secs(10), 2, 100);
        l.allow(ip("10.0.0.1")); // one request spent: its bucket is full again 10 s later
        l.allow(ip("10.0.0.2"));
        l.allow(ip("10.0.0.2")); // two spent: 20 s
        assert_eq!(l.tracked(), 2);
        clock.advance(Duration::from_secs(10));
        l.prune();
        assert_eq!(l.tracked(), 2, "full again, but inside the extra period");
        clock.advance(Duration::from_secs(10));
        l.prune();
        assert_eq!(l.tracked(), 1, "the client that spent one request is forgotten, the other is not");
        clock.advance(Duration::from_secs(10));
        l.prune();
        assert_eq!(l.tracked(), 0);
    }

    #[test]
    fn the_table_cannot_grow_without_bound() {
        let cap = 1000;
        let (l, _) = limiter(NEVER, 1, cap);
        for i in 0..cap as u32 {
            assert!(l.allow(IpAddr::V4(Ipv4Addr::from(i + 1))));
        }
        assert_eq!(l.tracked(), cap);
        // everyone is spent (not full), so a new client is refused instead of growing the table...
        let refused = l.check(ip("203.0.113.200"));
        assert!(refused.is_err());
        assert_eq!(l.tracked(), cap);
        // ...and told to wait a bounded time, not 150 years
        assert!(refused.unwrap_err() <= MAX_RETRY_AFTER);
        // while the clients already in the table keep being limited one by one (not locked out wholesale)
        assert!(!l.allow(IpAddr::V4(Ipv4Addr::from(1u32))));
    }

    #[test]
    fn a_full_table_makes_room_by_forgetting_recovered_clients() {
        let cap = 100;
        let (l, clock) = limiter(Duration::from_secs(1), 1, cap);
        for i in 0..cap as u32 {
            assert!(l.allow(IpAddr::V4(Ipv4Addr::from(i + 1))));
        }
        assert!(l.check(ip("203.0.113.200")).is_err());
        clock.advance(Duration::from_secs(2)); // every old client is back to a full bucket (plus governor's slack)
        assert!(l.allow(ip("203.0.113.200")), "the new client gets in");
        assert!(l.tracked() <= cap);
    }

    #[test]
    fn a_client_cannot_hold_more_connections_than_its_share_and_gives_them_back() {
        let l = ConnLimit::new(2);
        let (a, b) = (l.acquire(ip("10.0.0.1")).unwrap(), l.acquire(ip("10.0.0.1")).unwrap());
        assert!(l.acquire(ip("10.0.0.1")).is_none());
        assert!(l.acquire(ip("10.0.0.2")).is_some(), "another client is not affected");
        drop(a);
        let c = l.acquire(ip("10.0.0.1")).expect("a slot came back");
        assert!(l.acquire(ip("10.0.0.1")).is_none());
        drop((b, c));
        assert_eq!(l.clients(), 0, "a client with nothing open takes no memory");
    }

    #[test]
    fn connections_of_an_ipv6_prefix_share_the_slots() {
        let l = ConnLimit::new(1);
        let _g = l.acquire(ip("2001:db8:1:2::1")).unwrap();
        assert!(l.acquire(ip("2001:db8:1:2::ffff")).is_none());
        assert!(l.acquire(ip("2001:db8:1:3::1")).is_some());
    }

    #[test]
    fn memory_per_client_stays_small() {
        // the table is a HashMap<IpAddr, Nanos>: this bounds the worst case of three limiters at MAX_TRACKED each
        let entry = std::mem::size_of::<(IpAddr, Nanos)>();
        assert!(entry <= 32, "entry grew to {entry} bytes");
        assert!(3 * MAX_TRACKED * entry * 2 < 4 * 1024 * 1024, "worst case no longer fits a few MB");
    }
}
