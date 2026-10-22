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
