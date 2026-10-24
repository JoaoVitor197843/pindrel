//! Which address is the client: the one that opened the connection, or, behind a proxy WE trust (a Cloudflare
//! tunnel, `tailscale serve`, another load balancer), the one that proxy says it saw.
//!
//! Anything a client can write is a lie, so the rules are strict:
//! * nothing is read unless the peer that connected is inside `TRUSTED_PROXIES` (empty by default: no proxy);
//! * only the ONE header named by `CLIENT_IP_HEADER` is read. `real_ip::real_ip` looks at `Forwarded`, then
//!   `X-Forwarded-For`, then `X-Real-IP`, and a client that sends all three through a proxy that only sets one of
//!   them would choose its own address through the first, which is why that function is not used as is;
//! * several lines of the same header are one list, in order (RFC 9110), and the list is read from the RIGHT:
//!   the first address that is not a trusted proxy is the client; what the client wrote on the left is never used;
//! * a header that does not parse, has bytes that are not text, or is absurdly long is ignored as a whole, and the
//!   client is the peer (the proxy itself), which only makes the limit stricter, never looser.
use std::{borrow::Cow, net::IpAddr};

use hyper::header::{HeaderMap, HeaderName};
use real_ip::{
    headers::{extract_forwarded_header, extract_real_ip_header, extract_x_forwarded_for_header},
    IpNet,
};

/// Longer than any honest chain of proxies.
const MAX_HEADER_LEN: usize = 2048;

/// How the value of `CLIENT_IP_HEADER` is read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    /// `X-Forwarded-For: client, proxy1, proxy2`
    ForwardedFor,
    /// RFC 7239 `Forwarded: for=client, for=proxy1;proto=https`
    Forwarded,
    /// One address (`CF-Connecting-IP`, `X-Real-IP`, `True-Client-IP`...).
    Single,
}

#[derive(Debug, Clone)]
pub struct ClientIp {
    trusted: Vec<IpNet>,
    header: HeaderName,
    format: Format,
}

impl ClientIp {
    /// No proxy in front: the client is whoever connected.
    pub fn direct() -> Self {
        Self {
            trusted: Vec::new(),
            header: HeaderName::from_static("x-forwarded-for"),
            format: Format::ForwardedFor,
        }
    }

    pub fn new(trusted: Vec<IpNet>, header: &str) -> Result<Self, String> {
        let header = HeaderName::from_bytes(header.trim().to_ascii_lowercase().as_bytes())
            .map_err(|_| format!("{header:?} is not a valid header name"))?;
        let format = match header.as_str() {
            "x-forwarded-for" => Format::ForwardedFor,
            "forwarded" => Format::Forwarded,
            _ => Format::Single,
        };
        Ok(Self { trusted, header, format })
    }

    pub fn is_direct(&self) -> bool {
        self.trusted.is_empty()
    }

    fn is_trusted(&self, ip: IpAddr) -> bool {
        self.trusted.iter().any(|net| net.contains(&ip))
    }

    /// Whether `peer` is one of the declared proxies, i.e. the request may come from anywhere (a tunnel).
    pub fn is_proxy(&self, peer: IpAddr) -> bool {
        self.is_trusted(peer.to_canonical())
    }

    /// The client address of a request that arrived from `peer`.
    pub fn resolve(&self, peer: IpAddr, headers: &HeaderMap) -> IpAddr {
        let peer = peer.to_canonical(); // ::ffff:127.0.0.1 is 127.0.0.1
        if self.is_direct() || !self.is_trusted(peer) {
            return peer;
        }
        let Some(value) = self.header_value(headers) else {
            return peer;
        };
        match self.format {
            Format::Single => extract_real_ip_header(&value).next().map_or(peer, |ip| ip.to_canonical()),
            Format::ForwardedFor => self.rightmost_untrusted(extract_x_forwarded_for_header(&value).rev(), peer),
            Format::Forwarded => self.rightmost_untrusted(extract_forwarded_header(&value).rev(), peer),
        }
    }

    /// Walks the chain from the proxy nearest to us: trusted hops are skipped, the first other one is the client.
    /// If every hop is trusted the client is the farthest one (the leftmost).
    fn rightmost_untrusted(&self, hops: impl Iterator<Item = IpAddr>, peer: IpAddr) -> IpAddr {
        let mut farthest = peer;
        for hop in hops {
            let hop = hop.to_canonical();
            if !self.is_trusted(hop) {
                return hop;
            }
            farthest = hop;
        }
        farthest
    }

    /// All the lines of the configured header as one comma-separated list, or None if it is absent, not text, or too long.
    fn header_value<'a>(&self, headers: &'a HeaderMap) -> Option<Cow<'a, str>> {
        let mut lines = headers.get_all(&self.header).iter();
        let first = lines.next()?.to_str().ok()?;
        let Some(second) = lines.next() else {
            return (first.len() <= MAX_HEADER_LEN).then_some(Cow::Borrowed(first));
        };
        let mut joined = String::from(first);
        for line in std::iter::once(second).chain(lines) {
            joined.push(',');
            joined.push_str(line.to_str().ok()?);
            if joined.len() > MAX_HEADER_LEN {
                return None;
            }
        }
        (joined.len() <= MAX_HEADER_LEN).then_some(Cow::Owned(joined))
    }
}

/// `TRUSTED_PROXIES`: comma-separated addresses or CIDR ranges (`127.0.0.1`, `10.0.0.0/8`, `fd7a:115c:a1e0::/48`).
pub fn parse_trusted(spec: &str) -> Result<Vec<IpNet>, String> {
    let mut out = Vec::new();
    for item in spec.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        let net = match item.parse::<IpNet>() {
            Ok(n) => n,
            Err(_) => item
                .parse::<IpAddr>()
                .map(IpNet::from)
                .map_err(|_| format!("{item:?} is not an address or a CIDR range"))?,
        };
        out.push(net);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hyper::header::HeaderValue;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn headers(pairs: &[(&str, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.append(HeaderName::from_bytes(k.as_bytes()).unwrap(), HeaderValue::from_str(v).unwrap());
        }
        h
    }

    fn proxy(trusted: &str, header: &str) -> ClientIp {
        ClientIp::new(parse_trusted(trusted).unwrap(), header).unwrap()
    }

    #[test]
    fn without_trusted_proxies_the_headers_are_never_read() {
        let c = ClientIp::direct();
        let h = headers(&[("x-forwarded-for", "9.9.9.9"), ("cf-connecting-ip", "8.8.8.8")]);
        assert_eq!(c.resolve(ip("203.0.113.5"), &h), ip("203.0.113.5"));
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("127.0.0.1"));
    }

    #[test]
    fn an_untrusted_peer_cannot_set_its_own_address() {
        let c = proxy("127.0.0.1,10.0.0.0/8", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "9.9.9.9")]);
        assert_eq!(c.resolve(ip("203.0.113.5"), &h), ip("203.0.113.5"));
    }

    #[test]
    fn a_trusted_proxy_vouches_for_the_client() {
        let c = proxy("127.0.0.1", "x-forwarded-for");
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &headers(&[("x-forwarded-for", "198.51.100.7")])),
            ip("198.51.100.7")
        );
    }

    #[test]
    fn what_the_client_wrote_on_the_left_is_never_used() {
        // the client sent "9.9.9.9"; the proxy appended the address it really saw
        let c = proxy("127.0.0.1", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "9.9.9.9, 198.51.100.7")]);
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("198.51.100.7"));
    }

    #[test]
    fn trusted_proxies_in_the_chain_are_skipped() {
        let c = proxy("127.0.0.1, 10.0.0.0/8", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "9.9.9.9, 198.51.100.7, 10.1.2.3")]);
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("198.51.100.7"));
    }

    #[test]
    fn an_untrusted_hop_in_the_middle_stops_the_walk() {
        // 203.0.113.9 is not ours: whatever is to its left was written by someone we do not trust
        let c = proxy("127.0.0.1, 10.0.0.0/8", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "1.1.1.1, 203.0.113.9, 10.1.2.3")]);
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("203.0.113.9"));
    }

    #[test]
    fn several_header_lines_are_one_list_in_order() {
        // a client cannot hide behind a first line: the proxy's line is the last one
        let c = proxy("127.0.0.1", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "9.9.9.9"), ("x-forwarded-for", "198.51.100.7")]);
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("198.51.100.7"));
    }

    #[test]
    fn only_the_configured_header_counts() {
        let c = proxy("127.0.0.1", "x-forwarded-for");
        let h = headers(&[
            ("forwarded", "for=9.9.9.9"),
            ("x-real-ip", "9.9.9.9"),
            ("cf-connecting-ip", "9.9.9.9"),
        ]);
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &h),
            ip("127.0.0.1"),
            "no X-Forwarded-For: the proxy is the client"
        );
        let both = headers(&[("forwarded", "for=9.9.9.9"), ("x-forwarded-for", "198.51.100.7")]);
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &both),
            ip("198.51.100.7"),
            "a client-sent Forwarded must not win"
        );
    }

    #[test]
    fn a_single_address_header_like_cloudflares() {
        let c = proxy("127.0.0.1", "CF-Connecting-IP");
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &headers(&[("cf-connecting-ip", "198.51.100.7")])),
            ip("198.51.100.7")
        );
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &headers(&[("x-forwarded-for", "9.9.9.9")])),
            ip("127.0.0.1")
        );
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &headers(&[("cf-connecting-ip", "not an ip")])),
            ip("127.0.0.1")
        );
        assert_eq!(
            c.resolve(ip("127.0.0.1"), &headers(&[("cf-connecting-ip", "2001:db8::7")])),
            ip("2001:db8::7")
        );
    }

    #[test]
    fn rfc_7239_forwarded() {
        let c = proxy("127.0.0.1", "forwarded");
        let h = headers(&[("forwarded", "for=9.9.9.9, for=198.51.100.7;proto=https")]);
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("198.51.100.7"));
        let v6 = headers(&[("forwarded", "for=\"[2001:db8::7]:4711\"")]);
        assert_eq!(c.resolve(ip("127.0.0.1"), &v6), ip("2001:db8::7"));
    }

    #[test]
    fn garbage_is_ignored_as_a_whole() {
        let c = proxy("127.0.0.1", "x-forwarded-for");
        for bad in [
            "",
            "   ",
            ",",
            "unknown",
            "9.9.9.9, _hidden",
            "9.9.9.9, 198.51.100.7, nonsense",
            "999.1.1.1",
            "9.9.9.9;x",
        ] {
            let h = headers(&[("x-forwarded-for", bad)]);
            assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("127.0.0.1"), "{bad:?}");
        }
        // bytes that are not text
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", HeaderValue::from_bytes(b"198.51.100.7\xff").unwrap());
        assert_eq!(c.resolve(ip("127.0.0.1"), &h), ip("127.0.0.1"));
    }

    #[test]
    fn an_absurdly_long_header_is_ignored() {
        let c = proxy("127.0.0.1", "x-forwarded-for");
        let long = vec!["198.51.100.7"; 300].join(", "); // ~3.9 KB
        assert_eq!(c.resolve(ip("127.0.0.1"), &headers(&[("x-forwarded-for", &long)])), ip("127.0.0.1"));
        let line = "198.51.100.7, ".repeat(100);
        let lines: Vec<_> = (0..10).map(|_| ("x-forwarded-for", line.as_str())).collect();
        assert_eq!(c.resolve(ip("127.0.0.1"), &headers(&lines)), ip("127.0.0.1"), "many lines add up");
    }

    #[test]
    fn mapped_ipv4_peers_and_hops_are_ipv4() {
        let c = proxy("127.0.0.1", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "::ffff:198.51.100.7")]);
        assert_eq!(c.resolve(ip("::ffff:127.0.0.1"), &h), ip("198.51.100.7"));
    }

    #[test]
    fn ipv6_proxy_ranges() {
        let c = proxy("fd7a:115c:a1e0::/48", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "2001:db8::7")]);
        assert_eq!(c.resolve(ip("fd7a:115c:a1e0::1"), &h), ip("2001:db8::7"));
        assert_eq!(c.resolve(ip("fd7a:115c:a1f0::1"), &h), ip("fd7a:115c:a1f0::1"), "outside the range");
    }

    #[test]
    fn every_hop_trusted_means_the_farthest_one() {
        let c = proxy("10.0.0.0/8", "x-forwarded-for");
        let h = headers(&[("x-forwarded-for", "10.9.9.9, 10.1.1.1")]);
        assert_eq!(c.resolve(ip("10.0.0.1"), &h), ip("10.9.9.9"));
    }

    #[test]
    fn config_parsing() {
        assert!(parse_trusted("").unwrap().is_empty());
        assert_eq!(parse_trusted(" 127.0.0.1 , ::1 ,10.0.0.0/8,").unwrap().len(), 3);
        assert!(parse_trusted("127.0.0.1, banana").is_err());
        assert!(parse_trusted("10.0.0.0/33").is_err());
        assert!(ClientIp::new(vec![], "bad header name").is_err());
        assert!(ClientIp::new(vec![], "").is_err());
    }

    #[test]
    fn nothing_in_the_input_can_make_it_panic() {
        // a cheap fuzz: odd bytes and shapes through every format
        let weird = [
            "[",
            "]",
            "[::1",
            "::1]",
            "for=",
            "for=;",
            "for=\"",
            ";;;",
            ",,,,",
            "a=b=c",
            "for=[",
            "for=\"[::1]:99999\"",
            "1.1.1.1/24",
            "-1.1.1.1",
            "1.1.1.1.1",
            "١.١.١.١",
            "\u{0}",
        ];
        for fmt in ["x-forwarded-for", "forwarded", "cf-connecting-ip"] {
            let c = proxy("127.0.0.1", fmt);
            for w in weird {
                if let Ok(v) = HeaderValue::from_str(w) {
                    let mut h = HeaderMap::new();
                    h.insert(HeaderName::from_bytes(fmt.as_bytes()).unwrap(), v);
                    let _ = c.resolve(ip("127.0.0.1"), &h);
                }
            }
        }
    }
}
