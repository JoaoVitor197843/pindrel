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

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::Mutex,
    time::{Duration, Instant},
};

use ring::digest::{digest, SHA256};

/// How long a session lives from its start: enough to walk to the other screen, short enough that a forgotten one is gone.
pub const TTL: Duration = Duration::from_secs(60);
/// Failed attempts (a commitment that does not match, a reveal for an unknown session) before an address is made to wait.
const MAX_FAILS: u8 = 3;
const LOCKOUT: Duration = Duration::from_secs(300);
/// Remembered misbehaving addresses; beyond it the table is emptied rather than grown.
const MAX_TRACKED: usize = 256;

#[derive(Debug, PartialEq, Eq)]
pub enum PairError {
    /// Another device is pairing right now.
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
    session: Option<Session>,
    fails: HashMap<IpAddr, (u8, Instant)>,
}

#[derive(Default)]
pub struct Pairing {
    state: Mutex<State>,
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
        if state.session.as_ref().is_some_and(|s| now.duration_since(s.started) >= TTL) {
            state.session = None;
        }
    }

    /// Step 1. Returns the session id and the server's number. A device that already has a session replaces it (the person
    /// tried again); a different device waits until it is over.
    pub fn start(&self, ip: IpAddr, commit: [u8; 32], now: Instant) -> Result<([u8; 16], [u8; 16]), PairError> {
        let mut st = self.state.lock().unwrap();
        if Self::locked(&mut st, ip, now) {
            return Err(PairError::Locked);
        }
        Self::expire(&mut st, now);
        if st.session.as_ref().is_some_and(|s| s.peer != ip) {
            return Err(PairError::Busy);
        }
        let (id, nonce) = (random::<16>(), random::<16>());
        st.session = Some(Session {
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
        let ok = st
            .session
            .as_ref()
            .is_some_and(|s| s.peer == ip && s.id == id && s.digits.is_none() && digest(&SHA256, &nonce_a).as_ref() == s.commit);
        if !ok {
            return Err(Self::fail(&mut st, ip, now));
        }
        let s = st.session.as_mut().unwrap();
        let d = digits(ca, &nonce_a, &s.nonce);
        s.digits = Some(d.clone());
        Ok(d)
    }

    /// The app is done (the person confirmed or cancelled): the digits leave the page and the slot is free again.
    /// Returns whether that session was still the live one: a session that was replaced (another device, or the same address
    /// starting again) or that expired no longer matches what the page showed, so the person's confirmation of it is worth
    /// nothing and the app must not pair on it. Only the owner of a session can end it.
    pub fn finish(&self, ip: IpAddr, id: [u8; 16], now: Instant) -> bool {
        let mut st = self.state.lock().unwrap();
        Self::expire(&mut st, now);
        let live = st
            .session
            .as_ref()
            .is_some_and(|s| s.peer == ip && s.id == id && s.digits.is_some());
        if st.session.as_ref().is_some_and(|s| s.peer == ip && s.id == id) {
            st.session = None;
        }
        live
    }

    /// What the page and the log show: only after a valid reveal, and only while the session lives.
    pub fn showing(&self, now: Instant) -> Option<Showing> {
        let mut st = self.state.lock().unwrap();
        Self::expire(&mut st, now);
        let s = st.session.as_ref()?;
        Some(Showing {
            digits: s.digits.clone()?,
            seconds_left: TTL.saturating_sub(now.duration_since(s.started)).as_secs(),
            from: s.peer,
        })
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
        let shown = p.showing(t0).unwrap();
        assert_eq!((shown.digits, shown.from), (server, ip(5)));
    }

    #[test]
    fn nothing_is_shown_before_the_reveal() {
        let (p, t0) = (Pairing::default(), Instant::now());
        p.start(ip(5), commit(&[1; 16]), t0).unwrap();
        assert_eq!(p.showing(t0), None, "the digits appear only after the commitment is checked");
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
        assert!(p.showing(t0).is_some());
        assert!(!p.finish(ip(5), [0; 16], t0), "nor can a wrong id");
        assert!(p.showing(t0).is_some());
        assert!(p.finish(ip(5), id, t0), "the owner ends it, and it was live");
        assert_eq!(p.showing(t0), None);
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
        assert_eq!(p.showing(t0), None);
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
        assert!(p.showing(t0 + TTL - Duration::from_secs(1)).is_some());
        assert_eq!(p.showing(t0 + TTL), None, "the digits disappear from the page with the session");
    }

    #[test]
    fn another_device_waits_while_one_is_pairing_and_the_same_one_may_retry() {
        let (p, t0) = (Pairing::default(), Instant::now());
        p.start(ip(5), commit(&[1; 16]), t0).unwrap();
        assert_eq!(p.start(ip(6), commit(&[2; 16]), t0), Err(PairError::Busy));
        p.start(ip(5), commit(&[3; 16]), t0).unwrap(); // the person tried again from the same phone
        assert!(p.start(ip(6), commit(&[2; 16]), t0 + TTL).is_ok(), "and the slot frees itself");
    }

    #[test]
    fn repeated_failures_lock_the_address_for_a_while_but_not_the_others() {
        let (p, t0) = (Pairing::default(), Instant::now());
        for _ in 0..MAX_FAILS {
            let (id, _) = p.start(ip(5), commit(&[1; 16]), t0).unwrap();
            assert_eq!(p.reveal(ip(5), id, [9; 16], &CA, t0), Err(PairError::Invalid));
        }
        assert_eq!(p.start(ip(5), commit(&[1; 16]), t0), Err(PairError::Locked));
        // the open session of the locked device is gone with its time; the other device is not punished for it
        assert!(p.start(ip(6), commit(&[1; 16]), t0 + TTL).is_ok(), "another device is not punished");
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
