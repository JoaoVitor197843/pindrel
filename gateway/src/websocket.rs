//! WebSocket through the gateway: an HTTP/1.1 `Upgrade` is passed to a replica and, once both sides agree (101), the
//! two connections are joined byte for byte. The gateway does not look inside the frames.
//!
//! Browsers open WebSockets with HTTP/1.1 upgrades even over TLS, so this is what `/ws/sync` needs. (WebSocket over
//! HTTP/2 and HTTP/3, RFC 8441 and 9220, is not offered by any browser or server tested; a request that did not arrive
//! as an HTTP/1.1 upgrade is refused with 426.)
use std::{net::IpAddr, sync::Arc, time::Duration};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::{body::Body as HttpBody, header, upgrade::OnUpgrade, Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    sync::watch,
    time,
};

use crate::handler::{error, App, Body, CLIENT_ADDRESS};

/// Per direction. A tunnel holds two of these for its whole life, so they are small: WebSocket messages are short.
const BUFFER: usize = 4096;

/// A browser always sends `Origin` on a WebSocket, and any page can ask it to open one to any server: without this check a
/// page on another site could use the cookies of a logged-in user (Cross-Site WebSocket Hijacking). The origin must be this
/// server's own (same host as `Host`) or listed in `WS_ALLOWED_ORIGINS`. Clients that are not browsers send no `Origin`.
fn origin_allowed(app: &App, headers: &hyper::HeaderMap) -> bool {
    let Some(origin) = headers.get(header::ORIGIN) else { return true };
    let Ok(origin) = origin.to_str() else { return false };
    let origin = origin.trim().trim_end_matches('/').to_lowercase();
    if app.cfg.ws_allowed_origins.contains(&origin) {
        return true;
    }
    let host = headers
        .get(header::HOST)
        .and_then(|v| v.to_str().ok())
        .map(|h| h.trim().to_lowercase());
    let origin_host = origin.strip_prefix("https://").or_else(|| origin.strip_prefix("http://"));
    match (origin_host, host) {
        (Some(o), Some(h)) => {
            // the same name, whatever the port: the page and the socket are on the same machine
            let strip = |s: &str| {
                s.rsplit_once(':')
                    .filter(|(_, p)| p.chars().all(|c| c.is_ascii_digit()))
                    .map_or(s.to_string(), |(a, _)| a.to_string())
            };
            !o.is_empty() && strip(o) == strip(&h)
        }
        _ => false,
    }
}

pub fn is_upgrade<B>(req: &Request<B>) -> bool {
    let has = |name, token: &str| {
        req.headers()
            .get_all(name)
            .iter()
            .filter_map(|v| v.to_str().ok())
            .any(|v| v.split(',').any(|t| t.trim().eq_ignore_ascii_case(token)))
    };
    req.method() == Method::GET && has(header::CONNECTION, "upgrade") && has(header::UPGRADE, "websocket")
}

pub async fn tunnel<B>(app: &Arc<App>, client_ip: IpAddr, secure: bool, req: &mut Request<B>) -> Response<Body>
where
    B: HttpBody<Data = Bytes> + Send + 'static,
{
    let Some(on_client) = req.extensions_mut().remove::<OnUpgrade>() else {
        return error(
            StatusCode::UPGRADE_REQUIRED,
            "upgrade_unavailable",
            "WebSocket needs an HTTP/1.1 connection",
        );
    };
    if !origin_allowed(app, req.headers()) {
        return error(StatusCode::FORBIDDEN, "forbidden_origin", "this page may not open a WebSocket here");
    }
    let Ok(permit) = app.ws_slots.clone().try_acquire_owned() else {
        return error(StatusCode::SERVICE_UNAVAILABLE, "too_many_websockets", "too many open WebSockets");
    };
    let Some(guard) = app.ws_per_ip.acquire(client_ip) else {
        return error(
            StatusCode::TOO_MANY_REQUESTS,
            "too_many_websockets",
            "too many open WebSockets for this client",
        );
    };
    let path_and_query = req.uri().path_and_query().map(|p| p.as_str()).unwrap_or("/").to_string();
    for target in app.pool.rotation() {
        let mut b = Request::builder()
            .method(Method::GET)
            .uri(format!("http://{target}{path_and_query}"));
        for (k, v) in req.headers() {
            // the upgrade headers are the point here; who the client is, the gateway says itself
            if k != header::CONTENT_LENGTH && !CLIENT_ADDRESS.contains(&k.as_str()) {
                b = b.header(k, v);
            }
        }
        let proto = if secure { "https" } else { "http" };
        let Ok(out) = b
            .header("x-forwarded-for", client_ip.to_string())
            .header("x-forwarded-proto", proto)
            .body(Full::new(Bytes::new()))
        else {
            return error(StatusCode::BAD_REQUEST, "bad_request", "invalid request");
        };
        match time::timeout(app.cfg.upstream_timeout, app.client.request(out)).await {
            Err(_) => {
                return error(
                    StatusCode::GATEWAY_TIMEOUT,
                    "gateway_timeout",
                    "the replica took too long to answer",
                )
            }
            Ok(Err(e)) if e.is_connect() => app.pool.mark_down(target),
            Ok(Err(_)) => break,
            Ok(Ok(mut resp)) if resp.status() == StatusCode::SWITCHING_PROTOCOLS => {
                let on_replica = hyper::upgrade::on(&mut resp);
                let (parts, _) = resp.into_parts();
                let (idle, stop) = (app.cfg.ws_idle, app.ws_stop.subscribe());
                tokio::spawn(async move {
                    // the slots are given back when the tunnel ends, however it ends
                    let _held = (permit, guard);
                    if let (Ok(c), Ok(r)) = (on_client.await, on_replica.await) {
                        join(TokioIo::new(c), TokioIo::new(r), idle, stop).await;
                    }
                });
                let mut reply = Response::new(Full::new(Bytes::new()).map_err(|e| match e {}).boxed());
                *reply.status_mut() = StatusCode::SWITCHING_PROTOCOLS;
                *reply.headers_mut() = parts.headers;
                return reply;
            }
            // the replica said no (wrong path, bad origin, 401...): the client gets that answer, not a tunnel
            Ok(Ok(resp)) => {
                let (mut p, inc) = resp.into_parts();
                for h in crate::handler::HOP_BY_HOP {
                    p.headers.remove(h);
                }
                return Response::from_parts(p, inc.boxed());
            }
        }
    }
    error(StatusCode::BAD_GATEWAY, "bad_gateway", "no replica available")
}

/// Copies both ways until one side closes, goes quiet for `idle`, or the gateway stops.
async fn join<A, B>(a: A, b: B, idle: Duration, mut stop: watch::Receiver<bool>)
where
    A: AsyncRead + AsyncWrite + Unpin,
    B: AsyncRead + AsyncWrite + Unpin,
{
    let (mut ar, mut aw) = tokio::io::split(a);
    let (mut br, mut bw) = tokio::io::split(b);
    let mut up = Box::pin(copy_idle(&mut ar, &mut bw, idle));
    let mut down = Box::pin(copy_idle(&mut br, &mut aw, idle));
    // the close handshake is a frame each way: when one direction ends the other gets a moment to deliver its last bytes
    tokio::select! {
        _ = &mut up => { let _ = time::timeout(Duration::from_secs(5), &mut down).await; }
        _ = &mut down => { let _ = time::timeout(Duration::from_secs(5), &mut up).await; }
        _ = stop.changed() => {}
    }
}

async fn copy_idle<R, W>(from: &mut R, to: &mut W, idle: Duration)
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut buf = vec![0u8; BUFFER];
    loop {
        let read = from.read(&mut buf);
        let n = if idle.is_zero() {
            read.await
        } else {
            match time::timeout(idle, read).await {
                Ok(r) => r,
                Err(_) => break,
            }
        };
        match n {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                if to.write_all(&buf[..n]).await.is_err() {
                    break;
                }
            }
        }
    }
    let _ = to.shutdown().await;
}
