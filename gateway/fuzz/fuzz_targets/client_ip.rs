//! Who a request belongs to. The invariant that protects every limit: whatever the headers say, a peer that is
//! not a declared proxy is itself.
#![no_main]
use std::net::{IpAddr, Ipv4Addr};

use hyper::header::{HeaderMap, HeaderName, HeaderValue};
use libfuzzer_sys::fuzz_target;
use plany_gateway::clientip::{parse_trusted, ClientIp};

const HEADERS: [&str; 3] = ["x-forwarded-for", "forwarded", "cf-connecting-ip"];

fuzz_target!(|data: &[u8]| {
    let Some((head, value)) = data.split_first_chunk::<5>() else { return };
    let peer = IpAddr::V4(Ipv4Addr::new(head[1], head[2], head[3], head[4]));
    let name = HEADERS[head[0] as usize % HEADERS.len()];
    let mut headers = HeaderMap::new();
    if let Ok(v) = HeaderValue::from_bytes(value) {
        headers.append(HeaderName::from_static(name), v);
    }

    let direct = ClientIp::direct();
    assert_eq!(direct.resolve(peer, &headers), peer);

    // 10.0.0.0/8 is the proxy; a peer outside it cannot choose its own address
    let proxied = ClientIp::new(parse_trusted("10.0.0.0/8").unwrap(), name).unwrap();
    let got = proxied.resolve(peer, &headers);
    if !proxied.is_proxy(peer) {
        assert_eq!(got, peer);
    }
});
