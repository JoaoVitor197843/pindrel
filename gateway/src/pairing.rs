//! Pairing by comparing six digits (no camera, no Bluetooth: everything goes over the network the app already uses).
//!
//! The problem: a device that meets a server for the first time has nothing to check its certificate authority against,
//! and mDNS proves nothing (anyone on the network can announce a server). A person has to confirm it; the digits make
//! that easy, and the exchange below makes them impossible to prepare in advance:
//!
//! 1. the app commits to a random number `a` (sends `sha256(a)`), the server answers with its own random number `s`;
//! 2. the app reveals `a`, the server checks it against the commitment;
//! 3. both compute `digits = sha256("pindrel-sas-v1" || fingerprint of the CA || a || s)` reduced to six decimal digits,
//!    the app from the CA it downloaded, the server from its own. The server shows its digits on the connection page and in
//!    its log; the app shows its own; the person compares.
//!
//! Somebody who sits between the two and presents another CA gets different digits (1 chance in a million that they match)
//! and cannot grind for a match, because `a` was committed before `s` was known and the fingerprint is fixed before `a` is
//! revealed. A failed comparison costs the attacker the session, and the failures are counted per address.
//!
//! Several devices may pair at once (up to `max` sessions, one per address). The page lists the digits of each with the address
//! of its device, and the app is told its own address, so a person compares the row that is theirs: another device cannot
//! show up under the address of this one.

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::Mutex,
    time::{Duration, Instant},
};

use ring::digest::{digest, SHA256};

/// How long a session lives from its start: enough to walk to the other screen, short enough that a forgotten one is gone.
pub const TTL: Duration = Duration::from_secs(60);
/// Devices pairing at the same time unless configured otherwise.
pub const DEFAULT_SESSIONS: usize = 6;
/// Failed attempts (a commitment that does not match, a reveal for an unknown session) before an address is made to wait.
const MAX_FAILS: u8 = 3;
const LOCKOUT: Duration = Duration::from_secs(300);
/// Remembered misbehaving addresses; beyond it the table is emptied rather than grown.
const MAX_TRACKED: usize = 256;

#[derive(Debug, PartialEq, Eq)]
pub enum PairError {
    /// As many devices are pairing right now as the server allows.
    Busy,
    /// Too many failures from this address.
    Locked,
    /// The request is not what the protocol says (wrong lengths, unknown or expired session, commitment mismatch).
    Invalid,
}

struct Session {
    id: [u8; 16],
    peer: IpAddr,
    commit: [u8; 32],
    nonce: [u8; 16],
    started: Instant,
    /// Set by a valid reveal: the six digits the person compares.
    digits: Option<String>,
}

#[derive(Default)]
struct State {
    /// At most one per address, at most `max` in all.
    sessions: Vec<Session>,
    fails: HashMap<IpAddr, (u8, Instant)>,
}

pub struct Pairing {
    state: Mutex<State>,
    max: usize,
}

impl Default for Pairing {
    fn default() -> Self {
        Self::new(DEFAULT_SESSIONS)
    }
}

/// What the connection page shows while somebody pairs.
#[derive(Debug, PartialEq, Eq)]
pub struct Showing {
    pub digits: String,
    pub seconds_left: u64,
    pub from: IpAddr,
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn unhex<const N: usize>(text: &str) -> Option<[u8; N]> {
    // from_str_radix would also take a leading `+`, so the digits are checked first
    if text.len() != N * 2 || !text.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let mut out = [0u8; N];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}

/// The six digits both sides compute.
pub fn digits(ca_fingerprint: &[u8; 32], nonce_a: &[u8; 16], nonce_s: &[u8; 16]) -> String {
    let mut input = Vec::with_capacity(14 + 32 + 32);
    input.extend_from_slice(b"pindrel-sas-v1");
    input.extend_from_slice(ca_fingerprint);
    input.extend_from_slice(nonce_a);
    input.extend_from_slice(nonce_s);
    let d = digest(&SHA256, &input);
    let n = u32::from_be_bytes([d.as_ref()[0], d.as_ref()[1], d.as_ref()[2], d.as_ref()[3]]);
    format!("{:06}", n % 1_000_000)
}

fn random<const N: usize>() -> [u8; N] {
    let mut out = [0u8; N];
    getrandom::fill(&mut out).expect("the system has a source of randomness");
    out
}

impl Pairing {
    pub fn new(max: usize) -> Self {
        Self {
            state: Mutex::new(State::default()),
            max: max.max(1),
        }
    }

    fn locked(state: &mut State, ip: IpAddr, now: Instant) -> bool {
        match state.fails.get(&ip) {
            Some(&(n, since)) if now.duration_since(since) < LOCKOUT => n >= MAX_FAILS,
            Some(_) => {
                state.fails.remove(&ip);
                false
            }
            None => false,
        }
    }

    fn fail(state: &mut State, ip: IpAddr, now: Instant) -> PairError {
        if state.fails.len() >= MAX_TRACKED && !state.fails.contains_key(&ip) {
            state.fails.clear();
        }
        let entry = state.fails.entry(ip).or_insert((0, now));
        if now.duration_since(entry.1) >= LOCKOUT {
            *entry = (0, now);
        }
        entry.0 = entry.0.saturating_add(1);
        PairError::Invalid
    }

    fn expire(state: &mut State, now: Instant) {
        state.sessions.retain(|s| now.duration_since(s.started) < TTL);
    }

    /// Step 1. Returns the session id and the server's number. A device that already has a session replaces it (the person
    /// tried again); a new device is taken in while there is room for it, otherwise it waits.
    pub fn start(&self, ip: IpAddr, commit: [u8; 32], now: Instant) -> Result<([u8; 16], [u8; 16]), PairError> {
        let mut st = self.state.lock().unwrap();
        if Self::locked(&mut st, ip, now) {
            return Err(PairError::Locked);
        }
        Self::expire(&mut st, now);
        st.sessions.retain(|s| s.peer != ip);
        if st.sessions.len() >= self.max {
            return Err(PairError::Busy);
        }
        let (id, nonce) = (random::<16>(), random::<16>());
        st.sessions.push(Session {
            id,
            peer: ip,
            commit,
            nonce,
            started: now,
            digits: None,
        });
        Ok((id, nonce))
    }

    /// Step 2. `ca` is this server's own CA fingerprint. Returns the six digits (also what the page will show).
    pub fn reveal(&self, ip: IpAddr, id: [u8; 16], nonce_a: [u8; 16], ca: &[u8; 32], now: Instant) -> Result<String, PairError> {
        let mut st = self.state.lock().unwrap();
        if Self::locked(&mut st, ip, now) {
            return Err(PairError::Locked);
        }
        Self::expire(&mut st, now);
        let found = st
            .sessions
            .iter_mut()
            .find(|s| s.peer == ip && s.id == id && s.digits.is_none() && digest(&SHA256, &nonce_a).as_ref() == s.commit);
        match found {
            Some(s) => {
                let d = digits(ca, &nonce_a, &s.nonce);
                s.digits = Some(d.clone());
                Ok(d)
            }
            None => Err(Self::fail(&mut st, ip, now)),
        }
    }

    /// The app is done (the person confirmed or cancelled): its digits leave the page and its place is free again.
    /// Returns whether that session was still the live one: a session that was replaced (the same address starting again) or
    /// that expired no longer matches what the page showed, so the person's confirmation of it is worth nothing and the app
    /// must not pair on it. Only the owner of a session can end it.
    pub fn finish(&self, ip: IpAddr, id: [u8; 16], now: Instant) -> bool {
        let mut st = self.state.lock().unwrap();
        Self::expire(&mut st, now);
        let at = st.sessions.iter().position(|s| s.peer == ip && s.id == id);
        match at {
            Some(i) => st.sessions.remove(i).digits.is_some(),
            None => false,
        }
    }

    /// What the page and the log show: the digits of every device that has revealed, oldest first, while its session lives.
    pub fn showing(&self, now: Instant) -> Vec<Showing> {
        let mut st = self.state.lock().unwrap();
        Self::expire(&mut st, now);
        st.sessions
            .iter()
            .filter_map(|s| {
                Some(Showing {
                    digits: s.digits.clone()?,
                    seconds_left: TTL.saturating_sub(now.duration_since(s.started)).as_secs(),
                    from: s.peer,
                })
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CA: [u8; 32] = [7; 32];
    fn ip(n: u8) -> IpAddr {
        IpAddr::from([192, 168, 1, n])
    }
    fn commit(a: &[u8; 16]) -> [u8; 32] {
        digest(&SHA256, a).as_ref().try_into().unwrap()
    }

    #[test]
    fn both_sides_get_the_same_six_digits() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let a = [1u8; 16];
        let (id, s) = p.start(ip(5), commit(&a), t0).unwrap();
        let server = p.reveal(ip(5), id, a, &CA, t0).unwrap();
        assert_eq!(server, digits(&CA, &a, &s), "the app computes it from what it downloaded");
        assert_eq!(server.len(), 6);
        assert!(server.chars().all(|c| c.is_ascii_digit()));
        let shown = p.showing(t0);
        assert_eq!(shown.len(), 1);
        assert_eq!((shown[0].digits.clone(), shown[0].from), (server, ip(5)));
    }

    #[test]
    fn nothing_is_shown_before_the_reveal() {
        let (p, t0) = (Pairing::default(), Instant::now());
        p.start(ip(5), commit(&[1; 16]), t0).unwrap();
        assert!(p.showing(t0).is_empty(), "the digits appear only after the commitment is checked");
    }

    #[test]
    fn a_man_in_the_middle_with_another_ca_gets_other_digits() {
        // the server holds CA; the app was handed another CA by somebody in between
        let (p, t0) = (Pairing::default(), Instant::now());
        let a = [9u8; 16];
        let (id, s) = p.start(ip(5), commit(&a), t0).unwrap();
        let server = p.reveal(ip(5), id, a, &CA, t0).unwrap();
        let app = digits(&[8; 32], &a, &s);
        assert_ne!(server, app);
    }

    #[test]
    fn finishing_clears_the_page_and_frees_the_slot_but_only_for_its_owner() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let a = [1u8; 16];
        let (id, _) = p.start(ip(5), commit(&a), t0).unwrap();
        p.reveal(ip(5), id, a, &CA, t0).unwrap();
        assert!(!p.finish(ip(6), id, t0), "somebody else cannot end it");
        assert!(!p.showing(t0).is_empty());
        assert!(!p.finish(ip(5), [0; 16], t0), "nor can a wrong id");
        assert!(!p.showing(t0).is_empty());
        assert!(p.finish(ip(5), id, t0), "the owner ends it, and it was live");
        assert!(p.showing(t0).is_empty());
        assert!(!p.finish(ip(5), id, t0), "ending twice says it is no longer live");
        assert!(
            p.start(ip(6), commit(&a), t0).is_ok(),
            "the next device does not wait for the old session to expire"
        );
    }

    #[test]
    fn a_replaced_or_expired_session_is_not_live_when_the_app_says_it_is_done() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let a = [1u8; 16];
        // the same address starts again: the first session is gone, and its confirmation must not count
        let (first, _) = p.start(ip(5), commit(&a), t0).unwrap();
        p.reveal(ip(5), first, a, &CA, t0).unwrap();
        let (second, _) = p.start(ip(5), commit(&[2; 16]), t0).unwrap();
        assert!(!p.finish(ip(5), first, t0), "the first was replaced");
        assert!(
            !p.finish(ip(5), second, t0),
            "the second was never revealed, so nothing was shown to compare"
        );
        // expired
        let (third, _) = p.start(ip(5), commit(&a), t0).unwrap();
        p.reveal(ip(5), third, a, &CA, t0).unwrap();
        assert!(!p.finish(ip(5), third, t0 + TTL), "its minute is over");
    }

    #[test]
    fn several_devices_pair_at_the_same_time_each_with_its_own_digits() {
        let (p, t0) = (Pairing::new(6), Instant::now());
        let mut sessions = Vec::new();
        for n in 1..=6u8 {
            let a = [n; 16];
            let (id, s) = p.start(ip(n), commit(&a), t0).unwrap();
            sessions.push((n, a, id, s));
        }
        assert_eq!(p.start(ip(7), commit(&[9; 16]), t0), Err(PairError::Busy), "the seventh waits");
        let mut mine = Vec::new();
        for (n, a, id, s) in &sessions {
            let d = p.reveal(ip(*n), *id, *a, &CA, t0).unwrap();
            assert_eq!(d, digits(&CA, a, s), "device {n} computes the same as the server");
            mine.push((*n, d));
        }
        let shown = p.showing(t0);
        assert_eq!(shown.len(), 6);
        for (n, d) in &mine {
            let row = shown.iter().find(|r| r.from == ip(*n)).expect("a row per device");
            assert_eq!(&row.digits, d, "the row under an address carries that device's digits");
        }
        // one finishes: its row goes and a waiting device gets in, while the others carry on untouched
        let (n, _, id, _) = sessions[2];
        assert!(p.finish(ip(n), id, t0));
        assert_eq!(p.showing(t0).len(), 5);
        assert!(p.start(ip(7), commit(&[9; 16]), t0).is_ok());
        assert_eq!(
            p.reveal(ip(1), sessions[0].2, sessions[0].1, &CA, t0).map_err(|_| ()),
            Err(()),
            "a session is revealed once"
        );
        assert!(p.finish(ip(1), sessions[0].2, t0), "the others were not disturbed");
    }

    #[test]
    fn one_device_cannot_take_two_places_and_cannot_finish_another_ones_session() {
        let (p, t0) = (Pairing::new(3), Instant::now());
        for _ in 0..10 {
            p.start(ip(5), commit(&[1; 16]), t0).unwrap(); // the same address again and again
        }
        assert_eq!(p.state.lock().unwrap().sessions.len(), 1, "one place per address");
        let (id6, _) = p.start(ip(6), commit(&[2; 16]), t0).unwrap();
        assert!(!p.finish(ip(5), id6, t0), "an address cannot end somebody else's session");
        assert!(p.start(ip(7), commit(&[3; 16]), t0).is_ok());
        assert_eq!(p.start(ip(8), commit(&[4; 16]), t0), Err(PairError::Busy));
    }

    #[test]
    fn sessions_expire_one_by_one_and_free_their_places() {
        let (p, t0) = (Pairing::new(2), Instant::now());
        p.start(ip(1), commit(&[1; 16]), t0).unwrap();
        p.start(ip(2), commit(&[2; 16]), t0 + Duration::from_secs(30)).unwrap();
        assert_eq!(p.start(ip(3), commit(&[3; 16]), t0 + Duration::from_secs(31)), Err(PairError::Busy));
        assert!(p.start(ip(3), commit(&[3; 16]), t0 + TTL).is_ok(), "the first one's minute is over");
        assert_eq!(p.state.lock().unwrap().sessions.len(), 2);
    }

    #[test]
    fn a_flood_of_addresses_never_holds_more_than_the_limit() {
        let (p, t0) = (Pairing::new(6), Instant::now());
        let mut taken = 0;
        for i in 0..5000u32 {
            let who = IpAddr::from([10, (i >> 16) as u8, (i >> 8) as u8, i as u8]);
            if p.start(who, commit(&[1; 16]), t0).is_ok() {
                taken += 1;
            }
        }
        assert_eq!(taken, 6);
        assert_eq!(p.state.lock().unwrap().sessions.len(), 6);
    }

    #[test]
    fn the_limit_is_at_least_one() {
        let (p, t0) = (Pairing::new(0), Instant::now());
        assert!(p.start(ip(1), commit(&[1; 16]), t0).is_ok());
    }

    #[test]
    fn the_digits_match_the_vector_the_app_checks() {
        // the same vector is in mobile/test/core/network/pairing_sas_test.dart: both sides must compute alike
        assert_eq!(digits(&[7; 32], &[1; 16], &[2; 16]), "180115");
    }

    #[test]
    fn the_digits_depend_on_every_input() {
        let base = digits(&CA, &[1; 16], &[2; 16]);
        assert_ne!(base, digits(&[8; 32], &[1; 16], &[2; 16]));
        assert_ne!(base, digits(&CA, &[3; 16], &[2; 16]));
        assert_ne!(base, digits(&CA, &[1; 16], &[3; 16]));
        // never shorter than six, whatever the hash is
        for i in 0..2000u16 {
            let d = digits(&CA, &[i as u8; 16], &[(i >> 8) as u8; 16]);
            assert_eq!(d.len(), 6, "{d}");
        }
    }

    #[test]
    fn a_reveal_that_does_not_match_the_commitment_is_refused_and_counted() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (id, _) = p.start(ip(5), commit(&[1; 16]), t0).unwrap();
        assert_eq!(p.reveal(ip(5), id, [2; 16], &CA, t0), Err(PairError::Invalid));
        assert!(p.showing(t0).is_empty());
    }

    #[test]
    fn a_session_is_revealed_once_and_only_by_the_device_that_started_it() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let a = [1u8; 16];
        let (id, _) = p.start(ip(5), commit(&a), t0).unwrap();
        assert_eq!(
            p.reveal(ip(6), id, a, &CA, t0),
            Err(PairError::Invalid),
            "another address cannot finish it"
        );
        p.reveal(ip(5), id, a, &CA, t0).unwrap();
        assert_eq!(p.reveal(ip(5), id, a, &CA, t0), Err(PairError::Invalid), "a replay is refused");
    }

    #[test]
    fn a_session_expires() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let a = [1u8; 16];
        let (id, _) = p.start(ip(5), commit(&a), t0).unwrap();
        let late = t0 + TTL;
        assert_eq!(p.reveal(ip(5), id, a, &CA, late), Err(PairError::Invalid));
        let (id, _) = p.start(ip(5), commit(&a), t0).unwrap();
        p.reveal(ip(5), id, a, &CA, t0).unwrap();
        assert!(!p.showing(t0 + TTL - Duration::from_secs(1)).is_empty());
        assert!(
            p.showing(t0 + TTL).is_empty(),
            "the digits disappear from the page with the session"
        );
    }

    #[test]
    fn another_device_waits_while_the_server_is_full_and_the_same_one_may_retry() {
        let (p, t0) = (Pairing::new(1), Instant::now());
        p.start(ip(5), commit(&[1; 16]), t0).unwrap();
        assert_eq!(p.start(ip(6), commit(&[2; 16]), t0), Err(PairError::Busy));
        p.start(ip(5), commit(&[3; 16]), t0).unwrap(); // the person tried again from the same phone
        assert!(p.start(ip(6), commit(&[2; 16]), t0 + TTL).is_ok(), "and the place frees itself");
    }

    #[test]
    fn repeated_failures_lock_the_address_for_a_while_but_not_the_others() {
        let (p, t0) = (Pairing::default(), Instant::now());
        for _ in 0..MAX_FAILS {
            let (id, _) = p.start(ip(5), commit(&[1; 16]), t0).unwrap();
            assert_eq!(p.reveal(ip(5), id, [9; 16], &CA, t0), Err(PairError::Invalid));
        }
        assert_eq!(p.start(ip(5), commit(&[1; 16]), t0), Err(PairError::Locked));
        assert!(p.start(ip(6), commit(&[1; 16]), t0).is_ok(), "another device is not punished");
        assert_eq!(p.start(ip(5), commit(&[1; 16]), t0 + TTL), Err(PairError::Locked));
        assert!(p.start(ip(5), commit(&[1; 16]), t0 + LOCKOUT).is_ok(), "and the lock ends");
    }

    #[test]
    fn a_flood_of_failing_addresses_does_not_grow_the_table() {
        let (p, t0) = (Pairing::default(), Instant::now());
        for i in 0..5000u32 {
            let who = IpAddr::from([10, (i >> 16) as u8, (i >> 8) as u8, i as u8]);
            let _ = p.reveal(who, [0; 16], [0; 16], &CA, t0);
        }
        assert!(p.state.lock().unwrap().fails.len() <= MAX_TRACKED);
    }

    #[test]
    fn hex_parsing_is_strict() {
        assert_eq!(unhex::<2>("0aFF"), Some([0x0a, 0xff]));
        for bad in ["", "0a", "0aFFF", "zz11", "０ａ１１", "0a ff", "+1+2", "-1-2"] {
            assert_eq!(unhex::<2>(bad), None, "{bad:?}");
        }
    }
}
