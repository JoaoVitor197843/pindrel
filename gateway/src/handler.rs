//! Request handling: rate limits, GET /server/discover/, and the reverse proxy to the replicas.
use std::{convert::Infallible, net::IpAddr, net::SocketAddr, sync::Arc, sync::RwLock, time::Duration};

use bytes::Bytes;
use http_body_util::{combinators::BoxBody, BodyExt, Full, LengthLimitError, Limited};
use hyper::{body::Body as HttpBody, header, Method, Request, Response, StatusCode};
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::TokioExecutor,
};
use tokio::time;

use crate::{config::Config, discovery::Registry, limiter::Limiters, pool::Pool, proto};

pub type Body = BoxBody<Bytes, hyper::Error>;

pub struct App {
    pub cfg: Config,
    pub pool: Pool,
    pub limiters: Limiters,
    pub registry: Arc<Registry>,
    /// This machine's address on the LAN (`192.168.1.163:8086`), once known; see `ADDRESS_HEADER`.
    pub address: RwLock<Option<String>>,
    pub(crate) client: Client<HttpConnector, Full<Bytes>>,
    /// WebSocket tunnels: a global budget, one per client, and a signal that closes them on shutdown.
    pub(crate) ws_slots: Arc<tokio::sync::Semaphore>,
    pub(crate) ws_per_ip: Arc<crate::limiter::ConnLimit>,
    pub ws_stop: tokio::sync::watch::Sender<bool>,
    /// Public CA certificate (PEM) and its SHA-256 fingerprint, when the gateway keeps its own CA (`TLS_AUTO`).
    pub ca: RwLock<Option<(String, String)>>,
}

impl App {
    pub fn new(cfg: Config, registry: Arc<Registry>, address: Option<String>) -> Self {
        let (cfg_ws, cfg_ws_ip) = (cfg.max_websockets, cfg.max_websockets_per_ip);
        let pool = Pool::new(cfg.upstreams.clone());
        let client = Client::builder(TokioExecutor::new())
            .pool_max_idle_per_host(4)
            .pool_idle_timeout(std::time::Duration::from_secs(30))
            .build_http();
        Self {
            cfg,
            pool,
            limiters: Limiters::standard(),
            registry,
            address: RwLock::new(address),
            client,
            ws_slots: Arc::new(tokio::sync::Semaphore::new(cfg_ws)),
            ws_per_ip: crate::limiter::ConnLimit::new(cfg_ws_ip),
            ws_stop: tokio::sync::watch::channel(false).0,
            ca: RwLock::new(None),
        }
    }
}

/// Headers that claim to say who the client is. The gateway is the edge: it sets `x-forwarded-for` itself, and the
/// others do not reach the API (nothing there should trust them).
pub(crate) const CLIENT_ADDRESS: [&str; 5] = ["x-forwarded-for", "forwarded", "x-real-ip", "cf-connecting-ip", "true-client-ip"];

/// The page of a server may be opened by `localhost` or a VPN address; this header on `GET /server/info/` tells
/// the web the address the other devices of the LAN use. It is not sent when the request came through a declared
/// proxy (a tunnel): those clients are not on the LAN and have no use for its private address.
pub const ADDRESS_HEADER: &str = "x-pindrel-address";

/// Also on `GET /server/info/`: the id of this server (see `identity`), which a client that remembers servers by id can
/// read from the page it is on. Unlike the address it is harmless for anyone to see, so a tunnel gets it too.
pub const ID_HEADER: &str = "x-pindrel-id";

/// SHA-256 of the CA certificate of this server, on `GET /server/info/` (see `selfcert`). Seeing it over plain HTTP proves
/// nothing: a client trusts it only when it matches the fingerprint it was given out of band (a pairing code).
pub const CA_HEADER: &str = "x-pindrel-ca";

pub(crate) const HOP_BY_HOP: [&str; 8] = [
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
];

pub(crate) fn reply(status: StatusCode, content_type: &'static str, body: Vec<u8>) -> Response<Body> {
    let mut r = Response::new(Full::new(Bytes::from(body)).map_err(|e| match e {}).boxed());
    *r.status_mut() = status;
    r.headers_mut()
        .insert(header::CONTENT_TYPE, header::HeaderValue::from_static(content_type));
    r.headers_mut()
        .insert(header::X_CONTENT_TYPE_OPTIONS, header::HeaderValue::from_static("nosniff"));
    r
}

/// Errors use the same protobuf `ErrorHttp` body as the API.
pub(crate) fn error(status: StatusCode, code: &str, message: &str) -> Response<Body> {
    reply(status, "application/x-protobuf", proto::error_http(code, message))
}

fn rate_limited(retry_after: Duration) -> Response<Body> {
    let mut r = error(StatusCode::TOO_MANY_REQUESTS, "rate_limited", "too many requests, try again later");
    // whole seconds, rounded up, at least 1: what the client has to wait before the bucket has a request again
    let secs = retry_after.as_secs() + u64::from(retry_after.subsec_nanos() > 0);
    r.headers_mut().insert(header::RETRY_AFTER, header::HeaderValue::from(secs.max(1)));
    r
}

/// Works for any request body: hyper's own `Incoming` (HTTP/1.1, HTTP/2) and the ones the HTTP/3 side builds.
pub async fn handle<B>(app: Arc<App>, peer: SocketAddr, mut req: Request<B>) -> Result<Response<Body>, Infallible>
where
    B: HttpBody<Data = Bytes> + Send + 'static,
    B::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
{
    // the connection's peer, or the client a trusted proxy in front of us vouches for (never a header from anyone else)
    let ip = app.cfg.client_ip.resolve(peer.ip(), req.headers());
    if app.cfg.rate_limit {
        if let Err(wait) = app.limiters.global.check(ip) {
            return Ok(rate_limited(wait));
        }
    }
    if crate::websocket::is_upgrade(&req) {
        return Ok(crate::websocket::tunnel(&app, ip, &mut req).await);
    }
    let path = req.uri().path();
    let via_proxy = app.cfg.client_ip.is_proxy(peer.ip());
    if req.method() == Method::GET && path == "/server/ca.pem" {
        // public by nature (it is a certificate); the fingerprint a client was given out of band is what makes it trusted
        return Ok(match app.ca.read().ok().and_then(|c| c.clone()) {
            Some((pem, _)) => {
                let mut r = reply(StatusCode::OK, "application/x-x509-ca-cert", pem.into_bytes());
                r.headers_mut()
                    .insert(header::CACHE_CONTROL, header::HeaderValue::from_static("no-cache"));
                r
            }
            None => error(StatusCode::NOT_FOUND, "not_found", "this server has no CA of its own"),
        });
    }
    if req.method() == Method::GET && path == "/server/discover/" {
        // the list is the map of the LAN (names, private addresses): only for clients that are on it, never for
        // whoever reaches a tunnel
        if via_proxy {
            return Ok(error(StatusCode::NOT_FOUND, "not_found", "not found"));
        }
        let mut r = reply(
            StatusCode::OK,
            "application/x-protobuf",
            proto::discovered_servers(&app.registry.list()),
        );
        r.headers_mut()
            .insert(header::CACHE_CONTROL, header::HeaderValue::from_static("no-store"));
        return Ok(r);
    }
    if app.cfg.rate_limit && req.method() == Method::POST {
        let limiter = match path {
            "/auth/login/" => Some(&app.limiters.login),
            "/auth/register/" => Some(&app.limiters.register),
            _ => None,
        };
        if let Some(Err(wait)) = limiter.map(|l| l.check(ip)) {
            return Ok(rate_limited(wait));
        }
    }
    Ok(proxy(&app, ip, via_proxy, req).await)
}

async fn proxy<B>(app: &App, client_ip: IpAddr, via_proxy: bool, req: Request<B>) -> Response<Body>
where
    B: HttpBody<Data = Bytes> + Send + 'static,
    B::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
{
    let (parts, body) = req.into_parts();
    // The body is buffered once so that a request can be replayed on another replica when the
    // first one refuses the connection (safe even for POST: nothing was sent yet).
    let body = match time::timeout(app.cfg.body_timeout, Limited::new(body, app.cfg.max_body).collect()).await {
        Err(_) => return error(StatusCode::REQUEST_TIMEOUT, "request_timeout", "request body took too long"),
        Ok(Err(e)) if e.downcast_ref::<LengthLimitError>().is_some() => {
            return error(StatusCode::PAYLOAD_TOO_LARGE, "payload_too_large", "request body too large")
        }
        Ok(Err(_)) => return error(StatusCode::BAD_REQUEST, "bad_request", "could not read the request body"),
        Ok(Ok(b)) => b.to_bytes(),
    };
    let path_and_query = parts.uri.path_and_query().map(|p| p.as_str()).unwrap_or("/");
    // A replica that is being stopped (rolling update) can close a connection right after a request was written to it.
    // The request may have been processed, so only the ones that change nothing are replayed, and only once: a request
    // that kills replicas must not be able to walk through all of them.
    let mut replays_left = usize::from(matches!(parts.method, Method::GET | Method::HEAD | Method::OPTIONS));
    for target in app.pool.rotation() {
        let mut b = Request::builder()
            .method(parts.method.clone())
            .uri(format!("http://{target}{path_and_query}"));
        for (k, v) in &parts.headers {
            // the client address replaces whatever X-Forwarded-For the client sent: the gateway is the edge
            if k != header::CONTENT_LENGTH && !CLIENT_ADDRESS.contains(&k.as_str()) && !HOP_BY_HOP.contains(&k.as_str()) {
                b = b.header(k, v);
            }
        }
        let out = match b.header("x-forwarded-for", client_ip.to_string()).body(Full::new(body.clone())) {
            Ok(r) => r,
            Err(_) => return error(StatusCode::BAD_REQUEST, "bad_request", "invalid request"),
        };
        match time::timeout(app.cfg.upstream_timeout, app.client.request(out)).await {
            Err(_) => {
                return error(
                    StatusCode::GATEWAY_TIMEOUT,
                    "gateway_timeout",
                    "the replica took too long to answer",
                )
            }
            Ok(Ok(resp)) => {
                let (mut p, inc) = resp.into_parts();
                for h in HOP_BY_HOP {
                    p.headers.remove(h);
                }
                p.headers.remove(ADDRESS_HEADER);
                p.headers.remove(ID_HEADER);
                p.headers.remove(CA_HEADER);
                p.headers.remove(header::ACCESS_CONTROL_ALLOW_ORIGIN);
                p.headers.remove(header::ACCESS_CONTROL_EXPOSE_HEADERS);
                if parts.method == Method::GET && parts.uri.path() == "/server/info/" {
                    if let Ok(v) = header::HeaderValue::from_str(app.registry.id()) {
                        p.headers.insert(ID_HEADER, v);
                    }
                    if let Some(v) = app
                        .ca
                        .read()
                        .ok()
                        .and_then(|c| c.as_ref().and_then(|(_, fp)| header::HeaderValue::from_str(fp).ok()))
                    {
                        p.headers.insert(CA_HEADER, v);
                    }
                    // Public and read-only, no credentials: a web page opened from another server may read it to check
                    // that an address typed by the user is a Pindrel gateway. Only the id is exposed, never the address.
                    p.headers
                        .insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, header::HeaderValue::from_static("*"));
                    p.headers
                        .insert(header::ACCESS_CONTROL_EXPOSE_HEADERS, header::HeaderValue::from_static(ID_HEADER));
                }
                if !via_proxy && parts.method == Method::GET && parts.uri.path() == "/server/info/" {
                    let address = app.address.read().ok().and_then(|a| a.clone());
                    if let Some(v) = address.and_then(|a| header::HeaderValue::from_str(&a).ok()) {
                        p.headers.insert(ADDRESS_HEADER, v);
                    }
                }
                return Response::from_parts(p, inc.boxed());
            }
            Ok(Err(e)) if e.is_connect() => app.pool.mark_down(target),
            Ok(Err(_)) if replays_left > 0 => replays_left -= 1,
            Ok(Err(_)) => break,
        }
    }
    error(StatusCode::BAD_GATEWAY, "bad_gateway", "no replica available")
}
