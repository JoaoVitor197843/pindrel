#![allow(dead_code)]
//! Test helpers: fake API replicas, a gateway started in-process and a tiny HTTP client.
use std::{convert::Infallible, net::SocketAddr, time::Duration};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::{body::Incoming, header::HeaderMap, service::service_fn, Request, Response, StatusCode};
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::{TokioExecutor, TokioIo},
};
use plany_gateway::{
    config::Config,
    server::{self, Running},
};
use prost::Message;
use tokio::{net::TcpListener, task::JoinHandle, time};

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
                        .await;
                });
            }
        });
        Backend { addr, task }
    }

    /// Simulates the replica dying: the listener and every open connection go away.
    pub fn kill(&self) {
        self.task.abort();
    }
}

async fn backend_handler(id: &'static str, req: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let h = |name: &str| req.headers().get(name).and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    let (xff, te, upgrade, conn, ctype) = (h("x-forwarded-for"), h("te"), h("upgrade"), h("connection"), h("content-type"));
    let claims = ["forwarded", "x-real-ip", "cf-connecting-ip", "true-client-ip"].map(h).concat();
    let (method, pq) = (
        req.method().to_string(),
        req.uri().path_and_query().map(|p| p.to_string()).unwrap_or_default(),
    );
    let path = req.uri().path().to_string();
    let body = req.into_body().collect().await.map(|b| b.to_bytes()).unwrap_or_default();
    if path == "/slow" {
        time::sleep(Duration::from_millis(800)).await;
    }
    let status = if path == "/missing" {
        StatusCode::NOT_FOUND
    } else {
        StatusCode::OK
    };
    Ok(Response::builder()
        .status(status)
        .header("x-backend", id)
        .header("x-seen-xff", xff)
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
    server::start(cfg).await.expect("gateway starts")
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
