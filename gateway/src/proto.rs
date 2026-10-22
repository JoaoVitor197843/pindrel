//! The few protobuf messages the gateway writes, encoded by hand (no protoc/prost at runtime).
//! They mirror shared/protos: `ErrorHttp` (auth.proto) and `DiscoveredServers` (server.proto).
//! tests/golden/*.bin pin the bytes, and backend/internal/api/golden_test.go decodes the same
//! files with the generated Go code, so a drift from the .proto files fails a test.
use crate::discovery::Server;

fn varint(mut n: usize, out: &mut Vec<u8>) {
    while n >= 128 {
        out.push((n % 128) as u8 | 128);
        n /= 128;
    }
    out.push(n as u8);
}

fn field(tag: u8, data: &[u8], out: &mut Vec<u8>) {
    out.push(tag);
    varint(data.len(), out);
    out.extend_from_slice(data);
}

/// ErrorHttp { code = 1; message = 2 }
pub fn error_http(code: &str, message: &str) -> Vec<u8> {
    let mut b = Vec::with_capacity(code.len() + message.len() + 4);
    field(0x0a, code.as_bytes(), &mut b);
    field(0x12, message.as_bytes(), &mut b);
    b
}

/// DiscoveredServers { repeated DiscoveredServer servers = 1 }
/// DiscoveredServer { name = 1; host = 2; repeated addresses = 3; int32 port = 4 }
pub fn discovered_servers(list: &[Server]) -> Vec<u8> {
    let mut out = Vec::new();
    for s in list {
        let mut e = Vec::new();
        field(0x0a, s.name.as_bytes(), &mut e);
        field(0x12, s.host.as_bytes(), &mut e);
        for ip in &s.ips {
            field(0x1a, ip.as_bytes(), &mut e);
        }
        e.push(0x20);
        varint(s.port as usize, &mut e);
        field(0x0a, &e, &mut out);
    }
    out
}

const MAX_SERVERS: usize = 256;
const MAX_ADDRESSES: usize = 16;
const MAX_TEXT: usize = 255;

struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn varint(&mut self) -> Option<u64> {
        let mut v = 0u64;
        for shift in (0..64).step_by(7) {
            let (&b, rest) = self.0.split_first()?;
            self.0 = rest;
            v |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Some(v);
            }
        }
        None
    }

    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        if n > self.0.len() {
            return None;
        }
        let (head, tail) = self.0.split_at(n);
        self.0 = tail;
        Some(head)
    }

    fn bytes(&mut self) -> Option<&'a [u8]> {
        let n = usize::try_from(self.varint()?).ok()?;
        self.take(n)
    }

    /// Skips a field of an unknown number, by wire type.
    fn skip(&mut self, wire: u64) -> Option<()> {
        match wire {
            0 => self.varint().map(|_| ()),
            1 => self.take(8).map(|_| ()),
            2 => self.bytes().map(|_| ()),
            5 => self.take(4).map(|_| ()),
            _ => None,
        }
    }
}

fn text(b: &[u8]) -> Option<String> {
    if b.len() > MAX_TEXT {
        return None;
    }
    String::from_utf8(b.to_vec()).ok()
}

fn server(b: &[u8]) -> Option<Server> {
    let mut r = Reader(b);
    let (mut name, mut host, mut ips, mut port) = (String::new(), String::new(), Vec::new(), 0u16);
    while !r.0.is_empty() {
        let tag = r.varint()?;
        match (tag >> 3, tag & 7) {
            (1, 2) => name = text(r.bytes()?)?,
            (2, 2) => host = text(r.bytes()?)?,
            (3, 2) => {
                if ips.len() >= MAX_ADDRESSES {
                    return None;
                }
                ips.push(text(r.bytes()?)?);
            }
            (4, 0) => port = u16::try_from(r.varint()?).ok()?,
            (_, wire) => r.skip(wire)?,
        }
    }
    (!name.is_empty() && port != 0).then_some(Server { name, host, ips, port })
}

/// Reads a `DiscoveredServers` message (what `discovered_servers` writes, also the format of the
/// file with the servers remembered between runs). `None` when it is malformed or over the limits;
/// it never panics, whatever the input.
pub fn parse_discovered_servers(b: &[u8]) -> Option<Vec<Server>> {
    let mut r = Reader(b);
    let mut out = Vec::new();
    while !r.0.is_empty() {
        let tag = r.varint()?;
        match (tag >> 3, tag & 7) {
            (1, 2) => {
                if out.len() >= MAX_SERVERS {
                    return None;
                }
                out.push(server(r.bytes()?)?);
            }
            (_, wire) => r.skip(wire)?,
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message;

    #[derive(Clone, PartialEq, Message)]
    struct ErrorHttp {
        #[prost(string, tag = "1")]
        code: String,
        #[prost(string, tag = "2")]
        message: String,
    }
    #[derive(Clone, PartialEq, Message)]
    struct DiscoveredServer {
        #[prost(string, tag = "1")]
        name: String,
        #[prost(string, tag = "2")]
        host: String,
        #[prost(string, repeated, tag = "3")]
        addresses: Vec<String>,
        #[prost(int32, tag = "4")]
        port: i32,
    }
    #[derive(Clone, PartialEq, Message)]
    struct DiscoveredServers {
        #[prost(message, repeated, tag = "1")]
        servers: Vec<DiscoveredServer>,
    }

    fn server(name: &str, port: u16) -> Server {
        Server {
            name: name.into(),
            host: "casa".into(),
            ips: vec!["192.168.1.10".into(), "10.0.0.5".into()],
            port,
        }
    }

    #[test]
    fn error_http_roundtrips_with_a_real_protobuf_decoder() {
        let got = ErrorHttp::decode(error_http("rate_limited", "too many requests, try again later").as_slice()).unwrap();
        assert_eq!(
            (got.code.as_str(), got.message.as_str()),
            ("rate_limited", "too many requests, try again later")
        );
    }

    #[test]
    fn discovered_servers_roundtrips_including_multibyte_values() {
        let long = "n".repeat(63); // forces a 2-byte length for the whole entry
        let list = [server("Casa do João & Maria", 8200), server(&long, 65535), server("a", 1)];
        let got = DiscoveredServers::decode(discovered_servers(&list).as_slice()).unwrap();
        assert_eq!(got.servers.len(), 3);
        assert_eq!((got.servers[0].name.as_str(), got.servers[0].port), ("Casa do João & Maria", 8200));
        assert_eq!(got.servers[0].addresses, ["192.168.1.10", "10.0.0.5"]);
        assert_eq!((got.servers[1].name.len(), got.servers[1].port), (63, 65535));
        assert_eq!(got.servers[2].port, 1);
    }

    #[test]
    fn empty_list_is_an_empty_message() {
        assert!(discovered_servers(&[]).is_empty());
        assert!(DiscoveredServers::decode(&[][..]).unwrap().servers.is_empty());
    }

    #[test]
    fn golden_files_match_the_encoder() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/");
        let want_err = std::fs::read(format!("{dir}rate_limited.bin")).expect("tests/golden/rate_limited.bin");
        assert_eq!(error_http("rate_limited", "too many requests, try again later"), want_err);
        let want = std::fs::read(format!("{dir}discovered.bin")).expect("tests/golden/discovered.bin");
        let list = [
            Server {
                name: "Casa do João".into(),
                host: "casa".into(),
                ips: vec!["192.168.1.10".into(), "10.0.0.5".into()],
                port: 8080,
            },
            Server {
                name: "Servidor".into(),
                host: "srv".into(),
                ips: vec!["192.168.1.20".into()],
                port: 39215,
            },
        ];
        assert_eq!(discovered_servers(&list), want);
    }

    #[test]
    fn parser_reads_back_what_the_encoder_wrote() {
        let list = vec![server("Casa do João & Maria", 8200), server("a", 1), server(&"n".repeat(63), 65535)];
        assert_eq!(parse_discovered_servers(&discovered_servers(&list)), Some(list));
        assert_eq!(parse_discovered_servers(&[]), Some(vec![]));
    }

    #[test]
    fn parser_reads_the_golden_file_written_by_protoc() {
        let raw = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden/discovered.bin")).unwrap();
        let got = parse_discovered_servers(&raw).unwrap();
        assert_eq!(got.len(), 2);
        assert_eq!((got[0].name.as_str(), got[0].port, got[0].ips.len()), ("Casa do João", 8080, 2));
        assert_eq!(
            (got[1].name.as_str(), got[1].host.as_str(), got[1].port),
            ("Servidor", "srv", 39215)
        );
    }

    #[test]
    fn parser_skips_unknown_fields() {
        // field 9 (varint) before the server and field 7 (bytes) inside it
        let mut b = vec![0x48, 0x05];
        let mut entry = Vec::new();
        field(0x0a, b"N", &mut entry);
        field(0x3a, b"future", &mut entry);
        entry.extend_from_slice(&[0x20, 0x50]);
        field(0x0a, &entry, &mut b);
        let got = parse_discovered_servers(&b).unwrap();
        assert_eq!((got[0].name.as_str(), got[0].port), ("N", 80));
    }

    #[test]
    fn parser_rejects_malformed_input_without_panicking() {
        let good = discovered_servers(&[server("N", 8080)]);
        // every truncation of a valid message
        for n in 0..good.len() {
            assert!(parse_discovered_servers(&good[..n]).is_none() || n == 0, "prefix of {n} bytes");
        }
        let cases: Vec<Vec<u8>> = vec![
            vec![0x0a, 0x05, 1, 2],                                                 // length beyond the data
            vec![0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f], // absurd length
            vec![0x80; 12],                                                         // unterminated varint
            vec![0x0b],                                                             // wire type 3 (group)
            vec![0x0a, 0x02, 0x0a, 0x00],                                           // server without a name or a port
            vec![0x0a, 0x04, 0x0a, 0x01, 0xff, 0x20],                               // invalid utf-8 / truncated
        ];
        for c in cases {
            assert!(parse_discovered_servers(&c).is_none(), "{c:?}");
        }
        // port out of range, name too long, too many servers, too many addresses
        let mut e = Vec::new();
        field(0x0a, b"N", &mut e);
        e.push(0x20);
        varint(70_000, &mut e);
        let mut b = Vec::new();
        field(0x0a, &e, &mut b);
        assert!(parse_discovered_servers(&b).is_none());
        assert!(parse_discovered_servers(&discovered_servers(&[server(&"x".repeat(300), 80)])).is_none());
        let many: Vec<Server> = (0..257).map(|i| server(&format!("s{i}"), 80)).collect();
        assert!(parse_discovered_servers(&discovered_servers(&many)).is_none());
        let mut crowded = server("N", 80);
        crowded.ips = (0..17).map(|i| format!("10.0.0.{i}")).collect();
        assert!(parse_discovered_servers(&discovered_servers(&[crowded])).is_none());
    }

    #[test]
    fn parser_survives_random_bytes() {
        // deterministic pseudo-random garbage, many lengths: must return, not panic or hang
        let mut x = 0x2545_f491_4f6c_dd1du64;
        for len in 0..400 {
            let b: Vec<u8> = (0..len)
                .map(|_| {
                    x ^= x << 13;
                    x ^= x >> 7;
                    x ^= x << 17;
                    (x >> 24) as u8
                })
                .collect();
            let _ = parse_discovered_servers(&b);
        }
    }

    /// The field numbers used above must be the ones declared in the shared .proto files.
    #[test]
    fn field_numbers_match_the_proto_files() {
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../shared/protos/");
        let server = std::fs::read_to_string(format!("{root}server.proto")).unwrap();
        let auth = std::fs::read_to_string(format!("{root}auth.proto")).unwrap();
        for line in [
            "string name = 1;",
            "string host = 2;",
            "repeated string addresses = 3;",
            "int32 port = 4;",
            "repeated DiscoveredServer servers = 1;",
        ] {
            assert!(server.contains(line), "server.proto lost `{line}`");
        }
        let err = auth.split("message ErrorHttp").nth(1).and_then(|s| s.split('}').next()).unwrap();
        assert!(
            err.contains("string code = 1;") && err.contains("string message = 2;"),
            "auth.proto ErrorHttp changed"
        );
    }
}
