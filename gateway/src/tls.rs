//! Optional TLS listener: HTTP/1.1 and HTTP/2 over TCP (negotiated by ALPN). Build feature `tls`.
use std::{sync::Arc, time::Duration};

use hyper::service::service_fn;
use hyper_util::{
    rt::{TokioExecutor, TokioIo, TokioTimer},
    server::conn::auto,
};
use rustls::ServerConfig;
use tokio::{net::TcpListener, sync::watch, time};
use tokio_rustls::TlsAcceptor;

use crate::handler::{handle, App};

/// HTTP/2 flow-control windows: what one stream, and one connection, may send before the gateway reads it.
pub const H2_STREAM_WINDOW: u32 = 64 * 1024;
pub const H2_CONNECTION_WINDOW: u32 = 128 * 1024;

pub async fn accept_loop(app: Arc<App>, listener: TcpListener, config: Arc<ServerConfig>, mut stop: watch::Receiver<bool>) {
    let acceptor = TlsAcceptor::from(config);
    let (permits, per_ip) = (app.conn_slots.clone(), app.conn_per_ip.clone());
    // one builder for the life of the process: a connection borrows it
    let mut builder = auto::Builder::new(TokioExecutor::new());
    builder.http1().timer(TokioTimer::new()).header_read_timeout(app.cfg.header_timeout);
    // h2 takes DATA frames up to the flow-control windows and keeps them until the handler reads the body, which it does
    // only once the body budget lets it: with hyper's 1 MiB windows a client could park ~1 MiB per connection outside
    // that budget (64 connections, 64 MiB, over the 48 MiB cap). Small windows bound it; a LAN still fills them fast.
    builder
        .http2()
        .timer(TokioTimer::new())
        .initial_stream_window_size(H2_STREAM_WINDOW)
        .initial_connection_window_size(H2_CONNECTION_WINDOW)
        .max_send_buf_size(H2_STREAM_WINDOW as usize)
        .max_concurrent_streams(64)
        .keep_alive_interval(Some(Duration::from_secs(30)))
        .keep_alive_timeout(Duration::from_secs(20));
    let builder: &'static auto::Builder<TokioExecutor> = Box::leak(Box::new(builder));
    loop {
        let permit = tokio::select! {
            p = permits.clone().acquire_owned() => p.unwrap(),
            _ = stop.changed() => break,
        };
        let (stream, peer) = tokio::select! {
            r = listener.accept() => match r { Ok(c) => c, Err(_) => continue },
            _ = stop.changed() => break,
        };
        let slot = if app.cfg.client_ip.is_proxy(peer.ip()) {
            None
        } else {
            match per_ip.acquire(peer.ip()) {
                Some(g) => Some(g),
                None => continue,
            }
        };
        let _ = stream.set_nodelay(true);
        let (app2, acceptor, mut stop2) = (app.clone(), acceptor.clone(), stop.clone());
        let handshake_budget = app.cfg.header_timeout;
        tokio::spawn(async move {
            // a client that opens a connection and never speaks TLS must not hold a slot for long
            if let Ok(Ok(tls)) = time::timeout(handshake_budget, acceptor.accept(stream)).await {
                let service = service_fn(move |req| {
                    let app = app2.clone();
                    async move { handle(app, peer, true, req).await }
                });
                let conn = builder.serve_connection_with_upgrades(TokioIo::new(tls), service);
                tokio::pin!(conn);
                tokio::select! {
                    _ = conn.as_mut() => {}
                    _ = stop2.changed() => {
                        // let the requests in flight finish, up to 5 s
                        conn.as_mut().graceful_shutdown();
                        let _ = time::timeout(Duration::from_secs(5), conn.as_mut()).await;
                    }
                }
            }
            drop((permit, slot));
        });
    }
    drop(listener);
}
