#![allow(dead_code)]
//! Test helpers: fake API replicas, a gateway started in-process and a tiny HTTP client.
use std::{
    convert::Infallible,
    net::SocketAddr,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
    time::Duration,
};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::{body::Incoming, header::HeaderMap, service::service_fn, Request, Response, StatusCode};
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::{TokioExecutor, TokioIo},
};
use pindrel_gateway::{
    config::Config,
    server::{self, Running},
};
use prost::Message;
use tokio::{io::AsyncReadExt, net::TcpListener, task::JoinHandle, time};

#[derive(Clone, PartialEq, Message)]
pub struct ErrorHttp {
    #[prost(string, tag = "1")]
    pub code: String,
    #[prost(string, tag = "2")]
    pub message: String,
}
#[derive(Clone, PartialEq, Message)]
pub struct DiscoveredServer {
    #[prost(string, tag = "1")]
    pub name: String,
    #[prost(string, tag = "2")]
    pub host: String,
    #[prost(string, repeated, tag = "3")]
    pub addresses: Vec<String>,
    #[prost(int32, tag = "4")]
    pub port: i32,
    #[prost(string, tag = "5")]
    pub id: String,
    #[prost(int32, tag = "6")]
    pub tls_port: i32,
}
#[derive(Clone, PartialEq, Message)]
pub struct DiscoveredServers {
    #[prost(message, repeated, tag = "1")]
    pub servers: Vec<DiscoveredServer>,
}

/// A fake API replica. It echoes what it received in `x-seen-*` headers and the body.
pub struct Backend {
    pub addr: SocketAddr,
    task: JoinHandle<()>,
    /// Requests whose head arrived (only counted by `start_dropping`).
    pub hits: Arc<AtomicUsize>,
}

impl Backend {
    pub async fn start(id: &'static str) -> Backend {
        Self::start_on("127.0.0.1:0".parse().unwrap(), id).await
    }

    pub async fn start_on(addr: SocketAddr, id: &'static str) -> Backend {
        // a killed backend frees its port a moment later, so retry for a while
        let mut tries = 0;
        let listener = loop {
            match TcpListener::bind(addr).await {
                Ok(l) => break l,
                Err(e) if tries < 40 => {
                    tries += 1;
                    let _ = e;
                    time::sleep(Duration::from_millis(50)).await;
                }
                Err(e) => panic!("could not bind {addr}: {e}"),
            }
        };
        let addr = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let mut conns = tokio::task::JoinSet::new(); // dropped with the task: killing the backend closes its connections
            loop {
                let Ok((s, _)) = listener.accept().await else { return };
                conns.spawn(async move {
                    let svc = service_fn(move |req| backend_handler(id, req));
                    let _ = hyper::server::conn::http1::Builder::new()
                        .serve_connection(TokioIo::new(s), svc)
                        .with_upgrades()
                        .await;
                });
            }
        });
        Backend {
            addr,
            task,
            hits: Arc::default(),
        }
    }

    /// A replica that accepts the connection, reads the request head and closes without answering: what a
    /// replica that is being stopped looks like to a request that reached it at the wrong moment.
    pub async fn start_dropping() -> Backend {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let hits = Arc::new(AtomicUsize::new(0));
        let counter = hits.clone();
        let task = tokio::spawn(async move {
            loop {
                let Ok((mut s, _)) = listener.accept().await else { return };
                let counter = counter.clone();
                tokio::spawn(async move {
                    let mut seen = Vec::new();
                    let mut buf = [0u8; 1024];
                    while !seen.windows(4).any(|w| w == b"\r\n\r\n") {
                        match s.read(&mut buf).await {
                            Ok(0) | Err(_) => return,
                            Ok(n) => seen.extend_from_slice(&buf[..n]),
                        }
                    }
                    counter.fetch_add(1, Ordering::SeqCst);
                    // dropped here: the connection closes with no response
                });
            }
        });
        Backend { addr, task, hits }
    }

    pub fn hits(&self) -> usize {
        self.hits.load(Ordering::SeqCst)
    }

    /// Simulates the replica dying: the listener and every open connection go away.
    pub fn kill(&self) {
        self.task.abort();
    }
}

async fn backend_handler(id: &'static str, mut req: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let h = |name: &str| req.headers().get(name).and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    let (xff, te, upgrade, conn, ctype) = (h("x-forwarded-for"), h("te"), h("upgrade"), h("connection"), h("content-type"));
    let proto = h("x-forwarded-proto");
    let claims = ["forwarded", "x-real-ip", "cf-connecting-ip", "true-client-ip"].map(h).concat();
    let (method, pq) = (
        req.method().to_string(),
        req.uri().path_and_query().map(|p| p.to_string()).unwrap_or_default(),
    );
    let path = req.uri().path().to_string();
    // /ws accepts a WebSocket upgrade and echoes the bytes it receives (the frames themselves are not parsed)
    if path == "/ws" && req.headers().contains_key("upgrade") {
        let on = hyper::upgrade::on(&mut req);
        tokio::spawn(async move {
            if let Ok(up) = on.await {
                let (mut r, mut w) = tokio::io::split(TokioIo::new(up));
                let _ = tokio::io::copy(&mut r, &mut w).await;
            }
        });
        return Ok(Response::builder()
            .status(StatusCode::SWITCHING_PROTOCOLS)
            .header("connection", "Upgrade")
            .header("upgrade", "websocket")
            .header("sec-websocket-accept", "test-accept")
            .header("x-backend", id)
            .header("x-seen-xff", xff)
            .body(Full::new(Bytes::new()))
            .unwrap());
    }
    let body = req.into_body().collect().await.map(|b| b.to_bytes()).unwrap_or_default();
    if path == "/slow" {
        time::sleep(Duration::from_millis(800)).await;
    }
    let status = if path == "/missing" {
        StatusCode::NOT_FOUND
    } else {
        StatusCode::OK
    };
    let mut res = Response::builder().status(status);
    if path == "/server/info/" {
        // a replica must not be able to speak for the gateway
        res = res.header("x-pindrel-address", "6.6.6.6:1");
    }
    Ok(res
        .header("x-backend", id)
        .header("x-seen-xff", xff)
        .header("x-seen-proto", proto)
        .header("x-seen-claims", claims)
        .header("x-seen-method", method)
        .header("x-seen-path", pq)
        .header("x-seen-te", te)
        .header("x-seen-upgrade", upgrade)
        .header("x-seen-connection", conn)
        .header("x-seen-content-type", ctype)
        .header("x-custom", "kept")
        .body(Full::new(body))
        .unwrap())
}

/// A gateway on a free port, no mDNS, probes done by hand (`app.pool.probe()`), limits on.
pub async fn gateway(backends: &[&Backend]) -> Running {
    gateway_with(backends, |_| {}).await
}

pub async fn gateway_with(backends: &[&Backend], tweak: impl FnOnce(&mut Config)) -> Running {
    let mut cfg = Config::new(backends.iter().map(|b| b.addr).collect());
    cfg.port = 0;
    cfg.mdns = false;
    cfg.probe_interval = Duration::from_secs(3600);
    tweak(&mut cfg);
    // no local network: the tests announce made-up addresses that the real LAN filter would drop
    server::start_with(cfg, None).await.expect("gateway starts")
}

pub type Http = Client<HttpConnector, Full<Bytes>>;

pub fn client() -> Http {
    Client::builder(TokioExecutor::new()).pool_max_idle_per_host(0).build_http()
}

pub struct Reply {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: Bytes,
}

impl Reply {
    pub fn header(&self, name: &str) -> &str {
        self.headers.get(name).and_then(|v| v.to_str().ok()).unwrap_or("")
    }
}

pub async fn send(gw: SocketAddr, method: &str, path: &str, headers: &[(&str, &str)], body: &str) -> Reply {
    let mut b = Request::builder()
        .method(method)
        .uri(format!("http://127.0.0.1:{}{path}", gw.port()));
    for (k, v) in headers {
        b = b.header(*k, *v);
    }
    let resp = client()
        .request(b.body(Full::new(Bytes::from(body.to_string()))).unwrap())
        .await
        .expect("request");
    let (p, inc) = resp.into_parts();
    Reply {
        status: p.status,
        headers: p.headers,
        body: inc.collect().await.unwrap().to_bytes(),
    }
}

pub async fn get(gw: SocketAddr, path: &str) -> Reply {
    send(gw, "GET", path, &[], "").await
}

pub fn error_of(r: &Reply) -> ErrorHttp {
    ErrorHttp::decode(r.body.clone()).expect("body is a protobuf ErrorHttp")
}

pub fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}
