//! Optional HTTP/3 listener (QUIC over UDP). Build feature `http3`.
use std::{net::SocketAddr, sync::Arc, time::Duration};

use bytes::{Buf, BufMut, Bytes, BytesMut};
use http_body_util::{BodyExt, Full};
use hyper::{Request, Response, StatusCode};
use quinn::crypto::rustls::QuicServerConfig;
use tokio::{
    sync::{watch, Semaphore},
    time,
};

use crate::{
    handler::{handle, App},
    limiter::ConnLimit,
};

pub fn endpoint(tls: Arc<rustls::ServerConfig>, addr: SocketAddr) -> std::io::Result<quinn::Endpoint> {
    let crypto = QuicServerConfig::try_from(tls).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))?;
    let mut cfg = quinn::ServerConfig::with_crypto(Arc::new(crypto));
    let mut transport = quinn::TransportConfig::default();
    // bounds on what one client can make us hold
    transport
        .max_concurrent_bidi_streams(64u32.into())
        .max_concurrent_uni_streams(8u32.into())
        .stream_receive_window((256u32 << 10).into())
        .receive_window((1u32 << 20).into())
        .send_window(1 << 20)
        .max_idle_timeout(Some(Duration::from_secs(30).try_into().unwrap()))
        .keep_alive_interval(None);
    cfg.transport_config(Arc::new(transport));
    quinn::Endpoint::server(cfg, addr)
}

pub async fn accept_loop(app: Arc<App>, endpoint: quinn::Endpoint, mut stop: watch::Receiver<bool>) {
    let permits = Arc::new(Semaphore::new(app.cfg.max_connections));
    let per_ip = ConnLimit::new(app.cfg.max_connections_per_ip);
    loop {
        let permit = tokio::select! {
            p = permits.clone().acquire_owned() => p.unwrap(),
            _ = stop.changed() => break,
        };
        let incoming = tokio::select! {
            i = endpoint.accept() => match i { Some(i) => i, None => break },
            _ = stop.changed() => break,
        };
        let peer = incoming.remote_address();
        let slot = if app.cfg.client_ip.is_proxy(peer.ip()) {
            None
        } else {
            match per_ip.acquire(peer.ip()) {
                Some(g) => Some(g),
                None => {
                    incoming.refuse();
                    continue;
                }
            }
        };
        let app = app.clone();
        tokio::spawn(async move {
            if let Ok(Ok(conn)) = time::timeout(app.cfg.header_timeout, async { incoming.await }).await {
                serve_connection(app, conn, peer).await;
            }
            drop((permit, slot));
        });
    }
    endpoint.close(0u32.into(), b"shutdown");
    endpoint.wait_idle().await;
}

async fn serve_connection(app: Arc<App>, conn: quinn::Connection, peer: SocketAddr) {
    let Ok(mut h3conn) = h3::server::Connection::new(h3_quinn::Connection::new(conn)).await else {
        return;
    };
    while let Ok(Some(resolver)) = h3conn.accept().await {
        let app = app.clone();
        tokio::spawn(async move {
            if let Ok((req, stream)) = resolver.resolve_request().await {
                let _ = request(app, peer, req, stream).await;
            }
        });
    }
}

async fn request<S>(
    app: Arc<App>,
    peer: SocketAddr,
    req: Request<()>,
    mut stream: h3::server::RequestStream<S, Bytes>,
) -> Result<(), h3::error::StreamError>
where
    S: h3::quic::BidiStream<Bytes>,
{
    // the same bound the HTTP/1.1 path applies: the body is read whole, up to MAX_BODY_BYTES
    let mut body = BytesMut::new();
    let read = time::timeout(app.cfg.body_timeout, async {
        while let Some(mut chunk) = stream.recv_data().await? {
            if body.len() + chunk.remaining() > app.cfg.max_body {
                return Ok::<bool, h3::error::StreamError>(false);
            }
            body.put(chunk.copy_to_bytes(chunk.remaining()));
        }
        Ok(true)
    })
    .await;
    let (parts, ()) = req.into_parts();
    let response = match read {
        Ok(Ok(true)) => match handle(app, peer, true, Request::from_parts(parts, Full::new(body.freeze()))).await {
            Ok(r) => r,
            Err(e) => match e {},
        },
        Ok(Ok(false)) => status_only(StatusCode::PAYLOAD_TOO_LARGE),
        Ok(Err(e)) => return Err(e),
        Err(_) => status_only(StatusCode::REQUEST_TIMEOUT),
    };
    let (head, mut out) = response.into_parts();
    stream.send_response(Response::from_parts(head, ())).await?;
    while let Some(Ok(frame)) = out.frame().await {
        if let Ok(data) = frame.into_data() {
            stream.send_data(data).await?;
        }
    }
    stream.finish().await
}

fn status_only(status: StatusCode) -> Response<crate::handler::Body> {
    let mut r = Response::new(Full::new(Bytes::new()).map_err(|never| match never {}).boxed());
    *r.status_mut() = status;
    r
}
