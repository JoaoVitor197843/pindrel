//! Pairing a new device with this server (no camera, no Bluetooth: everything goes over the network the app already uses).
//!
//! The problem: a device that meets a server for the first time has nothing to check its certificate authority against,
//! and mDNS proves nothing (anyone on the network can announce a server). Somebody has to vouch for the server. Two ways:
//!
//! # By six digits, in a room
//!
//! A person at a page of the server (the connection page, or the web login) asks for a **room**: a 4-digit code and a secret
//! token that stays in that page. The code goes into the app, which starts a session in that room:
//!
//! 1. the app commits to a random number `a` (sends `sha256(a)`), the server answers with its own random number `s`;
//! 2. the app reveals `a`, the server checks it against the commitment;
//! 3. both compute `digits = sha256("pindrel-sas-v1" || fingerprint of the CA || a || s)` reduced to six decimal digits,
//!    the app from the CA it downloaded, the server from its own. The room's page (the one that holds the token, nobody
//!    else) shows the server's; the app shows its own; the person compares.
//!
//! Somebody who sits between the two and presents another CA gets different digits (1 chance in a million that they match)
//! and cannot grind for a match, because `a` was committed before `s` was known and the fingerprint is fixed before `a` is
//! revealed. The room code only says *which* page shows the digits: guessing it gets nothing but a session whose digits the
//! rightful page shows and the person then refuses. Rooms are independent, so several people pair at once, and each sees
//! only their own digits.
//!
//! # With the master code
//!
//! For whoever has the host at hand and no page to open: the gateway prints a **master code** (80 random bits) in its log.
//! The app and the server prove to each other that they know it without ever sending it, with an HMAC over the code, the
//! fingerprint of the CA each side sees and both fresh numbers. Somebody in between with another CA cannot produce the
//! server's proof, and 80 bits cannot be searched from a proof that was watched. The code works once, for 24 hours at most,
//! and is replaced (and printed again) after it is used, when it expires, or after a few wrong tries.

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::Mutex,
    time::{Duration, Instant},
};

use ring::{
    digest::{digest, SHA256},
    hmac,
};

/// Equal, in time that does not depend on where they differ (secrets are compared with it).
fn same(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// How long the digits of one session live from its start.
pub const TTL: Duration = Duration::from_secs(60);
/// How long a room lives: time to type the code and to compare, with a renewal of the digits or two in between.
pub const ROOM_TTL: Duration = Duration::from_secs(180);
/// Rooms open at the same time unless configured otherwise.
pub const DEFAULT_ROOMS: usize = 6;
/// Failed attempts (an unknown room code, a commitment that does not match, a wrong proof) before an address must wait.
const MAX_FAILS: u8 = 3;
const LOCKOUT: Duration = Duration::from_secs(300);
/// Remembered misbehaving addresses; beyond it the table is emptied rather than grown.
const MAX_TRACKED: usize = 256;
/// A master code is replaced after this long unused, and after this many wrong proofs from anyone.
const MASTER_TTL: Duration = Duration::from_secs(24 * 3600);
const MASTER_MAX_FAILS: u32 = 5;
/// Sessions with the master code waiting for their proof (one per address, at most this many).
const MAX_MASTER_SESSIONS: usize = 16;

#[derive(Debug, PartialEq, Eq)]
pub enum PairError {
    /// Every room is taken (a page asking for one), or the room already has another device in it (a phone).
    Busy,
    /// Too many failures from this address.
    Locked,
    /// The request is not what the protocol says (wrong lengths, unknown or expired session, commitment mismatch).
    Invalid,
    /// That room does not exist (any more).
    UnknownRoom,
    /// The proof with the master code does not match.
    Denied,
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

struct Room {
    /// Typed into the app. Says which page the digits go to, and nothing more.
    code: u16,
    /// Secret of the page that asked for the room: who holds it sees the digits.
    token: [u8; 16],
    owner: IpAddr,
    opened: Instant,
    session: Option<Session>,
}

struct Master {
    code: [u8; 10],
    born: Instant,
    fails: u32,
}

struct State {
    rooms: Vec<Room>,
    /// Sessions that will be proven with the master code instead of compared.
    master_sessions: Vec<Session>,
    master: Master,
    /// A new master code the log has not shown yet.
    notice: Option<String>,
    fails: HashMap<IpAddr, (u8, Instant)>,
}

pub struct Pairing {
    state: Mutex<State>,
    max_rooms: usize,
}

impl Default for Pairing {
    fn default() -> Self {
        Self::new(DEFAULT_ROOMS)
    }
}

/// What the page that holds a room's token is shown.
#[derive(Debug, PartialEq, Eq)]
pub struct RoomView {
    /// Seconds before the room closes.
    pub room_left: u64,
    /// Once the app has revealed: the six digits and how long they are good for.
    pub digits: Option<(String, u64)>,
    /// The address of the device that joined, if one did.
    pub phone: Option<IpAddr>,
}

const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/// 10 bytes as 16 characters of Crockford base32 in groups of four: `K7Q2-9XMD-4R8T-0HZ3`.
pub fn master_text(code: &[u8; 10]) -> String {
    let mut out = String::with_capacity(19);
    let (mut acc, mut bits, mut n) = (0u32, 0u32, 0);
    for &b in code {
        acc = (acc << 8) | b as u32;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            if n > 0 && n % 4 == 0 {
                out.push('-');
            }
            out.push(ALPHABET[((acc >> bits) & 31) as usize] as char);
            n += 1;
        }
        acc &= (1 << bits) - 1; // what is left of the byte; the rest was written out
    }
    out
}

/// The inverse, forgiving as people are: any case, dashes and spaces ignored, `O` read as `0`, `I` and `L` as `1`.
pub fn master_from_text(text: &str) -> Option<[u8; 10]> {
    let mut symbols = Vec::with_capacity(16);
    for c in text.chars() {
        if c == '-' || c.is_whitespace() {
            continue;
        }
        let c = match c.to_ascii_uppercase() {
            'O' => '0',
            'I' | 'L' => '1',
            other => other,
        };
        symbols.push(ALPHABET.iter().position(|&a| a as char == c)? as u32);
    }
    if symbols.len() != 16 {
        return None;
    }
    let (mut acc, mut bits) = (0u32, 0u32);
    let mut out = [0u8; 10];
    let mut i = 0;
    for s in symbols {
        acc = (acc << 5) | s;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out[i] = ((acc >> bits) & 0xff) as u8;
            i += 1;
            acc &= (1 << bits) - 1;
        }
    }
    Some(out)
}

/// The proof one side gives the other: `tag` says who it is for (`b"pindrel-master-a"` from the app, `-s` from the server).
pub fn master_proof(master: &[u8; 10], tag: &[u8], fp: &[u8; 32], a: &[u8; 16], s: &[u8; 16]) -> [u8; 32] {
    let key = hmac::Key::new(hmac::HMAC_SHA256, master);
    let mut input = Vec::with_capacity(tag.len() + 64);
    input.extend_from_slice(tag);
    input.extend_from_slice(fp);
    input.extend_from_slice(a);
    input.extend_from_slice(s);
    let mut out = [0u8; 32];
    out.copy_from_slice(hmac::sign(&key, &input).as_ref());
    out
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

fn new_master(now: Instant) -> Master {
    Master {
        code: random::<10>(),
        born: now,
        fails: 0,
    }
}

impl State {
    fn locked(&mut self, ip: IpAddr, now: Instant) -> bool {
        match self.fails.get(&ip) {
            Some(&(n, since)) if now.duration_since(since) < LOCKOUT => n >= MAX_FAILS,
            Some(_) => {
                self.fails.remove(&ip);
                false
            }
            None => false,
        }
    }

    fn fail(&mut self, ip: IpAddr, now: Instant) {
        if self.fails.len() >= MAX_TRACKED && !self.fails.contains_key(&ip) {
            self.fails.clear();
        }
        let entry = self.fails.entry(ip).or_insert((0, now));
        if now.duration_since(entry.1) >= LOCKOUT {
            *entry = (0, now);
        }
        entry.0 = entry.0.saturating_add(1);
    }

    fn expire(&mut self, now: Instant) {
        self.rooms.retain(|r| now.duration_since(r.opened) < ROOM_TTL);
        for r in &mut self.rooms {
            if r.session.as_ref().is_some_and(|s| now.duration_since(s.started) >= TTL) {
                r.session = None; // the digits are gone; the same room can ask for new ones
            }
        }
        self.master_sessions.retain(|s| now.duration_since(s.started) < TTL);
    }

    fn rotate_master(&mut self, now: Instant) {
        self.master = new_master(now);
        self.master_sessions.clear();
        self.notice = Some(master_text(&self.master.code));
    }
}

impl Pairing {
    pub fn new(max_rooms: usize) -> Self {
        let now = Instant::now();
        let master = new_master(now);
        Self {
            max_rooms: max_rooms.max(1),
            state: Mutex::new(State {
                rooms: Vec::new(),
                master_sessions: Vec::new(),
                notice: Some(master_text(&master.code)),
                master,
                fails: HashMap::new(),
            }),
        }
    }

    // ---- the page side -------------------------------------------------------------------------------------------

    /// A page asks for a room. The same address asking again replaces its own room.
    pub fn open_room(&self, ip: IpAddr, now: Instant) -> Result<(u16, [u8; 16]), PairError> {
        let mut st = self.state.lock().unwrap();
        st.expire(now);
        st.rooms.retain(|r| r.owner != ip);
        if st.rooms.len() >= self.max_rooms {
            return Err(PairError::Busy);
        }
        let code = loop {
            let c = (u32::from_be_bytes(random::<4>()) % 10_000) as u16;
            if !st.rooms.iter().any(|r| r.code == c) {
                break c;
            }
        };
        let token = random::<16>();
        st.rooms.push(Room {
            code,
            token,
            owner: ip,
            opened: now,
            session: None,
        });
        Ok((code, token))
    }

    /// What the holder of `token` is shown. `None` when there is no such room (any more).
    pub fn room_view(&self, token: &[u8; 16], now: Instant) -> Option<RoomView> {
        let mut st = self.state.lock().unwrap();
        st.expire(now);
        let room = st.rooms.iter().find(|r| same(&r.token, token))?;
        let (digits, phone) = match &room.session {
            Some(s) => (
                s.digits
                    .clone()
                    .map(|d| (d, TTL.saturating_sub(now.duration_since(s.started)).as_secs())),
                Some(s.peer),
            ),
            None => (None, None),
        };
        Some(RoomView {
            room_left: ROOM_TTL.saturating_sub(now.duration_since(room.opened)).as_secs(),
            digits,
            phone,
        })
    }

    pub fn close_room(&self, token: &[u8; 16]) -> bool {
        let mut st = self.state.lock().unwrap();
        let before = st.rooms.len();
        st.rooms.retain(|r| !same(&r.token, token));
        st.rooms.len() != before
    }

    // ---- the app side, by digits ---------------------------------------------------------------------------------

    /// Step 1. Returns the session id and the server's number. A phone joins a room by its code; a room holds one phone at a
    /// time (the same address starting again replaces its own session, which is how the digits are renewed).
    pub fn start(&self, ip: IpAddr, room: u16, commit: [u8; 32], now: Instant) -> Result<([u8; 16], [u8; 16]), PairError> {
        let mut st = self.state.lock().unwrap();
        if st.locked(ip, now) {
            return Err(PairError::Locked);
        }
        st.expire(now);
        let Some(at) = st.rooms.iter().position(|r| r.code == room) else {
            st.fail(ip, now); // guessing room codes is what gets an address locked
            return Err(PairError::UnknownRoom);
        };
        let r = &mut st.rooms[at];
        if r.session.as_ref().is_some_and(|s| s.peer != ip) {
            return Err(PairError::Busy);
        }
        let (id, nonce) = (random::<16>(), random::<16>());
        r.session = Some(Session {
            id,
            peer: ip,
            commit,
            nonce,
            started: now,
            digits: None,
        });
        Ok((id, nonce))
    }

    /// Step 2. `ca` is this server's own CA fingerprint. Returns the six digits and the room they belong to.
    pub fn reveal(&self, ip: IpAddr, id: [u8; 16], nonce_a: [u8; 16], ca: &[u8; 32], now: Instant) -> Result<(String, u16), PairError> {
        let mut st = self.state.lock().unwrap();
        if st.locked(ip, now) {
            return Err(PairError::Locked);
        }
        st.expire(now);
        let at = st.rooms.iter().position(|r| {
            r.session
                .as_ref()
                .is_some_and(|s| s.peer == ip && s.id == id && s.digits.is_none() && digest(&SHA256, &nonce_a).as_ref() == s.commit)
        });
        match at {
            Some(i) => {
                let r = &mut st.rooms[i];
                let code = r.code;
                let s = r.session.as_mut().unwrap();
                let d = digits(ca, &nonce_a, &s.nonce);
                s.digits = Some(d.clone());
                Ok((d, code))
            }
            None => {
                st.fail(ip, now);
                Err(PairError::Invalid)
            }
        }
    }

    /// The app is done (the person confirmed or cancelled): the room closes. Returns whether that session was still the live
    /// one: a session that was replaced, or that expired, no longer matches what the page showed, so the person's
    /// confirmation of it is worth nothing and the app must not pair on it. Only the owner of a session can end it.
    pub fn finish(&self, ip: IpAddr, id: [u8; 16], now: Instant) -> bool {
        let mut st = self.state.lock().unwrap();
        st.expire(now);
        let at = st
            .rooms
            .iter()
            .position(|r| r.session.as_ref().is_some_and(|s| s.peer == ip && s.id == id));
        match at {
            Some(i) => st.rooms.remove(i).session.is_some_and(|s| s.digits.is_some()),
            None => false,
        }
    }

    // ---- the app side, with the master code ----------------------------------------------------------------------

    /// Step 1 of the master way: like `start`, with no room.
    pub fn master_start(&self, ip: IpAddr, commit: [u8; 32], now: Instant) -> Result<([u8; 16], [u8; 16]), PairError> {
        let mut st = self.state.lock().unwrap();
        if st.locked(ip, now) {
            return Err(PairError::Locked);
        }
        st.expire(now);
        if now.duration_since(st.master.born) >= MASTER_TTL {
            st.rotate_master(now);
        }
        st.master_sessions.retain(|s| s.peer != ip);
        if st.master_sessions.len() >= MAX_MASTER_SESSIONS {
            return Err(PairError::Busy);
        }
        let (id, nonce) = (random::<16>(), random::<16>());
        st.master_sessions.push(Session {
            id,
            peer: ip,
            commit,
            nonce,
            started: now,
            digits: None,
        });
        Ok((id, nonce))
    }

    /// Step 2 of the master way: the app reveals its number and gives its proof; the server checks it and answers with its own.
    /// The code is replaced on success (it works once) and after [`MASTER_MAX_FAILS`] wrong proofs from anyone.
    pub fn master_finish(
        &self,
        ip: IpAddr,
        id: [u8; 16],
        nonce_a: [u8; 16],
        proof: &[u8],
        ca: &[u8; 32],
        now: Instant,
    ) -> Result<[u8; 32], PairError> {
        let mut st = self.state.lock().unwrap();
        if st.locked(ip, now) {
            return Err(PairError::Locked);
        }
        st.expire(now);
        let at = st
            .master_sessions
            .iter()
            .position(|s| s.peer == ip && s.id == id && digest(&SHA256, &nonce_a).as_ref() == s.commit);
        let Some(at) = at else {
            st.fail(ip, now);
            return Err(PairError::Invalid);
        };
        let session = st.master_sessions.remove(at); // one try per session
        let code = st.master.code;
        let expected = master_proof(&code, b"pindrel-master-a", ca, &nonce_a, &session.nonce);
        if !same(&expected, proof) {
            st.fail(ip, now);
            st.master.fails += 1;
            if st.master.fails >= MASTER_MAX_FAILS {
                st.rotate_master(now);
            }
            return Err(PairError::Denied);
        }
        let answer = master_proof(&code, b"pindrel-master-s", ca, &nonce_a, &session.nonce);
        st.rotate_master(now);
        Ok(answer)
    }

    // ---- the log -------------------------------------------------------------------------------------------------

    /// Replaces an expired master code. Returns a code the log has not shown yet (the first one, a replacement), once.
    pub fn tick(&self, now: Instant) -> Option<String> {
        let mut st = self.state.lock().unwrap();
        st.expire(now);
        if now.duration_since(st.master.born) >= MASTER_TTL {
            st.rotate_master(now);
        }
        st.notice.take()
    }

    /// A master code that was created since the log last showed one.
    pub fn take_notice(&self) -> Option<String> {
        self.state.lock().unwrap().notice.take()
    }

    /// Rooms open right now (for the tests and the log).
    pub fn rooms_open(&self, now: Instant) -> usize {
        let mut st = self.state.lock().unwrap();
        st.expire(now);
        st.rooms.len()
    }

    /// The current master code, for the tests of the protocol: what an administrator reads in the log.
    #[doc(hidden)]
    pub fn master_for_tests(&self) -> [u8; 10] {
        self.state.lock().unwrap().master.code
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

    /// A page opens a room, a phone joins it and reveals: returns (room code, token, session id, nonce a, nonce s, digits).
    fn full(p: &Pairing, page: u8, phone: u8, t: Instant) -> (u16, [u8; 16], [u8; 16], [u8; 16], [u8; 16], String) {
        let (code, token) = p.open_room(ip(page), t).unwrap();
        let a = [phone; 16];
        let (id, s) = p.start(ip(phone), code, commit(&a), t).unwrap();
        let (d, c) = p.reveal(ip(phone), id, a, &CA, t).unwrap();
        assert_eq!(c, code);
        (code, token, id, a, s, d)
    }

    // ---- rooms ---------------------------------------------------------------------------------------------------

    #[test]
    fn the_page_that_holds_the_token_sees_the_digits_the_app_computes() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (_, token, _, a, s, d) = full(&p, 50, 5, t0);
        assert_eq!(d, digits(&CA, &a, &s), "the app computes it from what it downloaded");
        let v = p.room_view(&token, t0).unwrap();
        assert_eq!(v.digits.as_ref().map(|x| x.0.clone()), Some(d));
        assert_eq!(v.phone, Some(ip(5)));
    }

    #[test]
    fn nothing_is_shown_before_the_phone_joins_or_reveals() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (code, token) = p.open_room(ip(50), t0).unwrap();
        assert_eq!(p.room_view(&token, t0).unwrap().digits, None);
        assert_eq!(p.room_view(&token, t0).unwrap().phone, None);
        p.start(ip(5), code, commit(&[1; 16]), t0).unwrap();
        let v = p.room_view(&token, t0).unwrap();
        assert_eq!(
            (v.digits, v.phone),
            (None, Some(ip(5))),
            "joined, but the commitment has not been checked yet"
        );
    }

    #[test]
    fn rooms_are_private_a_token_sees_only_its_own_digits() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (_, t1, _, _, _, d1) = full(&p, 50, 5, t0);
        let (_, t2, _, _, _, d2) = full(&p, 51, 6, t0);
        assert_ne!(d1, d2);
        assert_eq!(p.room_view(&t1, t0).unwrap().digits.unwrap().0, d1);
        assert_eq!(p.room_view(&t2, t0).unwrap().digits.unwrap().0, d2);
        assert!(p.room_view(&[9; 16], t0).is_none(), "a token that is not any room's sees nothing");
        let mut near = t1;
        near[15] ^= 1;
        assert!(p.room_view(&near, t0).is_none(), "nor one that is almost right");
    }

    #[test]
    fn six_rooms_pair_at_once_and_a_seventh_page_waits() {
        let (p, t0) = (Pairing::new(6), Instant::now());
        let mut rooms = Vec::new();
        for n in 1..=6u8 {
            rooms.push((n, full(&p, 100 + n, n, t0)));
        }
        assert_eq!(p.open_room(ip(120), t0), Err(PairError::Busy), "the seventh waits");
        let codes: std::collections::HashSet<u16> = rooms.iter().map(|(_, r)| r.0).collect();
        assert_eq!(codes.len(), 6, "every room has its own code");
        for (n, (_, token, _, a, s, d)) in &rooms {
            assert_eq!(&digits(&CA, a, s), d, "phone {n}");
            assert_eq!(&p.room_view(token, t0).unwrap().digits.unwrap().0, d, "page of phone {n}");
        }
        // one finishes: its room closes, the waiting page gets in, the others are untouched
        let (n, (_, _, id, _, _, _)) = &rooms[2];
        assert!(p.finish(ip(*n), *id, t0));
        assert_eq!(p.rooms_open(t0), 5);
        assert!(p.open_room(ip(120), t0).is_ok());
        for (i, (_, (_, token, _, _, _, d))) in rooms.iter().enumerate() {
            if i != 2 {
                assert_eq!(&p.room_view(token, t0).unwrap().digits.unwrap().0, d);
            }
        }
    }

    #[test]
    fn a_phone_cannot_join_a_room_that_does_not_exist_and_guessing_locks_it() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (code, _) = p.open_room(ip(50), t0).unwrap();
        let wrong = (code + 1) % 10_000;
        for _ in 0..MAX_FAILS {
            assert_eq!(p.start(ip(5), wrong, commit(&[1; 16]), t0), Err(PairError::UnknownRoom));
        }
        assert_eq!(
            p.start(ip(5), code, commit(&[1; 16]), t0),
            Err(PairError::Locked),
            "even the right code now waits"
        );
        assert!(p.start(ip(6), code, commit(&[1; 16]), t0).is_ok(), "another device is not punished");
        // the room is long gone by the time the lock ends (a lock outlives a room), so the address is free to ask again
        assert_eq!(p.start(ip(5), code, commit(&[1; 16]), t0 + LOCKOUT), Err(PairError::UnknownRoom));
    }

    #[test]
    fn one_room_holds_one_phone_and_the_same_phone_may_renew() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (code, token) = p.open_room(ip(50), t0).unwrap();
        let (first, _) = p.start(ip(5), code, commit(&[1; 16]), t0).unwrap();
        assert_eq!(
            p.start(ip(6), code, commit(&[2; 16]), t0),
            Err(PairError::Busy),
            "a second phone cannot take the room"
        );
        let (second, _) = p.start(ip(5), code, commit(&[3; 16]), t0).unwrap(); // the app renews its digits
        assert_ne!(first, second);
        assert!(!p.finish(ip(5), first, t0), "the replaced session is not the live one");
        assert!(p.room_view(&token, t0).is_some(), "the room itself is still there");
    }

    #[test]
    fn when_the_digits_expire_the_room_takes_a_new_session_from_anyone() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (code, token) = p.open_room(ip(50), t0).unwrap();
        p.start(ip(5), code, commit(&[1; 16]), t0).unwrap();
        let later = t0 + TTL;
        assert!(p.room_view(&token, later).unwrap().digits.is_none());
        assert!(
            p.start(ip(6), code, commit(&[2; 16]), later).is_ok(),
            "the first phone never answered"
        );
    }

    #[test]
    fn a_room_expires_and_its_code_is_free_again() {
        let (p, t0) = (Pairing::new(2), Instant::now());
        let (code, token) = p.open_room(ip(50), t0).unwrap();
        p.open_room(ip(51), t0 + Duration::from_secs(100)).unwrap();
        assert_eq!(p.open_room(ip(52), t0 + Duration::from_secs(101)), Err(PairError::Busy));
        let late = t0 + ROOM_TTL;
        assert!(p.room_view(&token, late).is_none());
        assert_eq!(p.start(ip(5), code, commit(&[1; 16]), late), Err(PairError::UnknownRoom));
        assert!(p.open_room(ip(52), late).is_ok(), "its place is free");
    }

    #[test]
    fn the_same_page_asking_again_replaces_its_own_room() {
        let (p, t0) = (Pairing::new(3), Instant::now());
        let (_, old) = p.open_room(ip(50), t0).unwrap();
        for _ in 0..20 {
            p.open_room(ip(50), t0).unwrap();
        }
        assert_eq!(p.rooms_open(t0), 1, "one room per address");
        assert!(p.room_view(&old, t0).is_none());
    }

    #[test]
    fn closing_a_room_needs_its_token_and_frees_the_place() {
        let (p, t0) = (Pairing::new(1), Instant::now());
        let (_, token) = p.open_room(ip(50), t0).unwrap();
        assert!(!p.close_room(&[1; 16]));
        assert_eq!(p.open_room(ip(51), t0), Err(PairError::Busy));
        assert!(p.close_room(&token));
        assert!(!p.close_room(&token), "twice says nothing was there");
        assert!(p.open_room(ip(51), t0).is_ok());
    }

    #[test]
    fn a_phone_cannot_reveal_or_finish_someone_elses_session() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (code, _) = p.open_room(ip(50), t0).unwrap();
        let a = [1u8; 16];
        let (id, _) = p.start(ip(5), code, commit(&a), t0).unwrap();
        assert_eq!(p.reveal(ip(6), id, a, &CA, t0), Err(PairError::Invalid));
        assert!(!p.finish(ip(6), id, t0));
        assert!(p.reveal(ip(5), id, a, &CA, t0).is_ok());
        assert_eq!(p.reveal(ip(5), id, a, &CA, t0), Err(PairError::Invalid), "a replay is refused");
    }

    #[test]
    fn a_wrong_commitment_is_refused_and_counted() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (code, token) = p.open_room(ip(50), t0).unwrap();
        let (id, _) = p.start(ip(5), code, commit(&[1; 16]), t0).unwrap();
        assert_eq!(p.reveal(ip(5), id, [2; 16], &CA, t0), Err(PairError::Invalid));
        assert!(
            p.room_view(&token, t0).unwrap().digits.is_none(),
            "nothing is shown for a failed reveal"
        );
    }

    #[test]
    fn finishing_says_whether_the_session_was_live_and_closes_the_room() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (_, token, id, _, _, _) = full(&p, 50, 5, t0);
        assert!(p.finish(ip(5), id, t0));
        assert!(p.room_view(&token, t0).is_none(), "the page learns that it is over");
        assert!(!p.finish(ip(5), id, t0), "twice says it is no longer live");
        // expired
        let (_, _, id2, _, _, _) = full(&p, 51, 6, t0);
        assert!(!p.finish(ip(6), id2, t0 + TTL), "its minute is over");
    }

    #[test]
    fn a_flood_of_pages_and_phones_never_holds_more_than_the_limits() {
        let (p, t0) = (Pairing::new(6), Instant::now());
        let mut opened = 0;
        for i in 0..5000u32 {
            let who = IpAddr::from([10, (i >> 16) as u8, (i >> 8) as u8, i as u8]);
            if p.open_room(who, t0).is_ok() {
                opened += 1;
            }
            let _ = p.start(who, (i % 10_000) as u16, commit(&[1; 16]), t0);
        }
        assert_eq!(opened, 6);
        assert_eq!(p.rooms_open(t0), 6);
        assert!(p.state.lock().unwrap().fails.len() <= MAX_TRACKED);
    }

    #[test]
    fn a_man_in_the_middle_with_another_ca_gets_other_digits() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let (_, token, _, a, s, _) = full(&p, 50, 5, t0);
        let shown = p.room_view(&token, t0).unwrap().digits.unwrap().0;
        assert_ne!(shown, digits(&[8; 32], &a, &s));
    }

    #[test]
    fn the_digits_depend_on_every_input_and_match_the_vector_the_app_checks() {
        // the same vector is in mobile/test/core/network/pairing_sas_test.dart: both sides must compute alike
        assert_eq!(digits(&[7; 32], &[1; 16], &[2; 16]), "180115");
        let base = digits(&CA, &[1; 16], &[2; 16]);
        assert_ne!(base, digits(&[8; 32], &[1; 16], &[2; 16]));
        assert_ne!(base, digits(&CA, &[3; 16], &[2; 16]));
        assert_ne!(base, digits(&CA, &[1; 16], &[3; 16]));
        for i in 0..2000u16 {
            assert_eq!(digits(&CA, &[i as u8; 16], &[(i >> 8) as u8; 16]).len(), 6);
        }
    }

    #[test]
    fn hex_parsing_is_strict() {
        assert_eq!(unhex::<2>("0aFF"), Some([0x0a, 0xff]));
        for bad in ["", "0a", "0aFFF", "zz11", "０ａ１１", "0a ff", "+1+2", "-1-2"] {
            assert_eq!(unhex::<2>(bad), None, "{bad:?}");
        }
    }

    // ---- the master code -----------------------------------------------------------------------------------------

    fn master_session(p: &Pairing, phone: u8, t: Instant) -> ([u8; 16], [u8; 16], [u8; 16]) {
        let a = [phone; 16];
        let (id, s) = p.master_start(ip(phone), commit(&a), t).unwrap();
        (id, a, s)
    }

    #[test]
    fn the_master_code_text_round_trips_and_is_forgiving() {
        for _ in 0..200 {
            let code = random::<10>();
            let text = master_text(&code);
            assert_eq!(text.len(), 19, "{text}");
            assert_eq!(master_from_text(&text), Some(code));
            assert_eq!(master_from_text(&text.to_lowercase()), Some(code), "any case");
            assert_eq!(master_from_text(&text.replace('-', " ")), Some(code), "spaces for dashes");
            assert_eq!(master_from_text(&format!("  {text}\n")), Some(code), "stray space and line break");
        }
        // the confusable letters: O is read as 0, I and L as 1
        assert_eq!(master_from_text("OOOO-OOOO-OOOO-OOOO"), master_from_text("0000-0000-0000-0000"));
        assert_eq!(master_from_text("IIII-LLLL-iiii-llll"), master_from_text("1111-1111-1111-1111"));
        for bad in [
            "",
            "0000",
            "0000-0000-0000-000",
            "0000-0000-0000-00000",
            "UUUU-0000-0000-0000",
            "0000-0000-0000-000!",
        ] {
            assert_eq!(master_from_text(bad), None, "{bad:?}");
        }
        assert_eq!(master_text(&[0u8; 10]), "0000-0000-0000-0000");
        assert_eq!(master_text(&[0xff; 10]), "ZZZZ-ZZZZ-ZZZZ-ZZZZ");
    }

    #[test]
    fn the_master_vectors_match_the_ones_the_app_checks() {
        // the same vectors are in mobile/test/core/network/pairing_master_test.dart: both sides must compute alike
        let master: [u8; 10] = core::array::from_fn(|i| i as u8 + 1);
        assert_eq!(master_text(&master), "0410-6105-0R3G-G28A");
        assert_eq!(master_from_text("0410-6105-0R3G-G28A"), Some(master));
        assert_eq!(
            hex(&master_proof(&master, b"pindrel-master-a", &[7; 32], &[1; 16], &[2; 16])),
            "a32fc5e550573f5abec0ecb980ca343f29e0693d6eaed7d788c1a7d7c62aab3b"
        );
        assert_eq!(
            hex(&master_proof(&master, b"pindrel-master-s", &[7; 32], &[1; 16], &[2; 16])),
            "508f576d687b3fe4dd7dc9a9d4e0f7535e73619c281dcdc3046b95ef6201ee59"
        );
    }

    #[test]
    fn the_master_proof_checks_out_both_ways_and_depends_on_everything() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let master = p.master_for_tests();
        let (id, a, s) = master_session(&p, 5, t0);
        let proof = master_proof(&master, b"pindrel-master-a", &CA, &a, &s);
        let answer = p.master_finish(ip(5), id, a, &proof, &CA, t0).unwrap();
        assert_eq!(
            answer,
            master_proof(&master, b"pindrel-master-s", &CA, &a, &s),
            "the app can check the server's proof"
        );
        assert_ne!(proof, answer, "the two directions are not interchangeable");
        let other = [3u8; 10];
        assert_ne!(proof, master_proof(&other, b"pindrel-master-a", &CA, &a, &s));
        assert_ne!(proof, master_proof(&master, b"pindrel-master-a", &[8; 32], &a, &s));
        assert_ne!(proof, master_proof(&master, b"pindrel-master-a", &CA, &[9; 16], &s));
        assert_ne!(proof, master_proof(&master, b"pindrel-master-a", &CA, &a, &[9; 16]));
    }

    #[test]
    fn the_master_code_works_once_and_a_new_one_takes_its_place() {
        let (p, t0) = (Pairing::default(), Instant::now());
        assert!(p.take_notice().is_some(), "the first code is for the log");
        assert!(p.take_notice().is_none(), "shown once");
        let old = p.master_for_tests();
        let (id, a, s) = master_session(&p, 5, t0);
        let proof = master_proof(&old, b"pindrel-master-a", &CA, &a, &s);
        p.master_finish(ip(5), id, a, &proof, &CA, t0).unwrap();
        let new = p.master_for_tests();
        assert_ne!(old, new);
        assert_eq!(p.take_notice(), Some(master_text(&new)), "the replacement is for the log");
        // the old code is worthless now
        let (id, a, s) = master_session(&p, 6, t0);
        let proof = master_proof(&old, b"pindrel-master-a", &CA, &a, &s);
        assert_eq!(p.master_finish(ip(6), id, a, &proof, &CA, t0), Err(PairError::Denied));
    }

    #[test]
    fn somebody_in_the_middle_with_another_ca_cannot_pass_even_knowing_nothing_else() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let master = p.master_for_tests();
        let (id, a, s) = master_session(&p, 5, t0);
        // the app was handed another CA: its proof is over that fingerprint, the server checks over its own
        let proof = master_proof(&master, b"pindrel-master-a", &[0xAB; 32], &a, &s);
        assert_eq!(p.master_finish(ip(5), id, a, &proof, &CA, t0), Err(PairError::Denied));
    }

    #[test]
    fn five_wrong_master_proofs_from_anyone_replace_the_code() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let _ = p.take_notice();
        let original = p.master_for_tests();
        for i in 0..MASTER_MAX_FAILS as u8 {
            let phone = 10 + i; // different devices, so the per-address lock does not stop the count
            let (id, a, _) = master_session(&p, phone, t0);
            assert_eq!(p.master_finish(ip(phone), id, a, &[0u8; 32], &CA, t0), Err(PairError::Denied));
        }
        assert_ne!(p.master_for_tests(), original);
        assert!(p.take_notice().is_some(), "and the new one is for the log");
    }

    #[test]
    fn one_try_per_session_and_the_address_is_locked_after_three_failures() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let master = p.master_for_tests();
        let (id, a, s) = master_session(&p, 5, t0);
        assert_eq!(p.master_finish(ip(5), id, a, &[0u8; 32], &CA, t0), Err(PairError::Denied));
        let good = master_proof(&master, b"pindrel-master-a", &CA, &a, &s);
        assert_eq!(
            p.master_finish(ip(5), id, a, &good, &CA, t0),
            Err(PairError::Invalid),
            "the session is spent"
        );
        let (id, a, _) = master_session(&p, 5, t0);
        assert_eq!(p.master_finish(ip(5), id, a, &[0u8; 32], &CA, t0), Err(PairError::Denied));
        assert_eq!(p.master_start(ip(5), commit(&[1; 16]), t0), Err(PairError::Locked));
    }

    #[test]
    fn the_master_code_expires_and_is_replaced_by_the_clock() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let _ = p.take_notice();
        let old = p.master_for_tests();
        assert!(p.tick(t0 + MASTER_TTL - Duration::from_secs(1)).is_none());
        let shown = p.tick(t0 + MASTER_TTL).expect("a new code is announced");
        let new = p.master_for_tests();
        assert_ne!(old, new);
        assert_eq!(shown, master_text(&new));
        assert!(p.tick(t0 + MASTER_TTL).is_none(), "announced once");
    }

    #[test]
    fn a_master_session_that_waits_too_long_or_does_not_match_is_refused() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let master = p.master_for_tests();
        let (id, a, s) = master_session(&p, 5, t0);
        let proof = master_proof(&master, b"pindrel-master-a", &CA, &a, &s);
        assert_eq!(
            p.master_finish(ip(5), id, a, &proof, &CA, t0 + TTL),
            Err(PairError::Invalid),
            "a minute is all it gets"
        );
        let (id, a, s) = master_session(&p, 6, t0);
        let proof = master_proof(&master, b"pindrel-master-a", &CA, &a, &s);
        assert_eq!(
            p.master_finish(ip(6), id, [0; 16], &proof, &CA, t0),
            Err(PairError::Invalid),
            "the number does not match its commitment"
        );
        assert_eq!(
            p.master_finish(ip(7), id, a, &proof, &CA, t0),
            Err(PairError::Invalid),
            "not another address's session"
        );
    }

    #[test]
    fn a_flood_of_master_sessions_is_bounded() {
        let (p, t0) = (Pairing::default(), Instant::now());
        let mut ok = 0;
        for i in 0..2000u32 {
            let who = IpAddr::from([10, (i >> 16) as u8, (i >> 8) as u8, i as u8]);
            if p.master_start(who, commit(&[1; 16]), t0).is_ok() {
                ok += 1;
            }
        }
        assert_eq!(ok, MAX_MASTER_SESSIONS);
    }

    #[test]
    fn a_proof_of_the_wrong_length_is_just_wrong() {
        let (p, t0) = (Pairing::default(), Instant::now());
        for (i, proof) in [&b""[..], &[0u8; 1][..], &[0u8; 31][..], &[0u8; 33][..], &[0xffu8; 1000][..]]
            .into_iter()
            .enumerate()
        {
            let phone = 30 + i as u8; // one address each, so none is locked before the others are tried
            let (id, a, _) = master_session(&p, phone, t0);
            assert_eq!(
                p.master_finish(ip(phone), id, a, proof, &CA, t0 + Duration::from_secs(i as u64)),
                Err(PairError::Denied)
            );
        }
    }
}
