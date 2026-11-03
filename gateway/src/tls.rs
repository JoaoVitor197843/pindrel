//! Optional TLS listener: HTTP/1.1 and HTTP/2 over TCP (negotiated by ALPN). Build feature `tls`.
use std::{convert::Infallible, io, path::Path, sync::Arc, time::Duration};

use hyper::service::service_fn;
use hyper_util::{
    rt::{TokioExecutor, TokioIo, TokioTimer},
    server::conn::auto,
};
use rustls::ServerConfig;
use rustls_pki_types::{pem::PemObject, CertificateDer, PrivateKeyDer};
use tokio::{
    net::TcpListener,
    sync::{watch, Semaphore},
    time,
};
use tokio_rustls::TlsAcceptor;

use crate::{
    handler::{handle, App},
    limiter::ConnLimit,
};

/// The rustls configuration for `alpn` (`h2`/`http/1.1` for TCP, `h3` for QUIC), from PEM files.
pub fn server_config(cert: &Path, key: &Path, alpn: &[&[u8]]) -> io::Result<Arc<ServerConfig>> {
    let bad = |e: rustls_pki_types::pem::Error| io::Error::new(io::ErrorKind::InvalidData, e.to_string());
    let certs = CertificateDer::pem_file_iter(cert)
        .map_err(bad)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(bad)?;
    let key = PrivateKeyDer::from_pem_file(key).map_err(bad)?;
    let mut cfg = ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;
    cfg.alpn_protocols = alpn.iter().map(|p| p.to_vec()).collect();
    Ok(Arc::new(cfg))
}

pub async fn accept_loop(
    app: Arc<App>,
    listener: TcpListener,
    config: Arc<ServerConfig>,
    alt_svc: Option<String>,
    mut stop: watch::Receiver<bool>,
) {
    let acceptor = TlsAcceptor::from(config);
    let permits = Arc::new(Semaphore::new(app.cfg.max_connections));
    let per_ip = ConnLimit::new(app.cfg.max_connections_per_ip);
    // one builder for the life of the process: a connection borrows it
    let mut builder = auto::Builder::new(TokioExecutor::new());
    builder.http1().timer(TokioTimer::new()).header_read_timeout(app.cfg.header_timeout);
    builder
        .http2()
        .timer(TokioTimer::new())
        .max_concurrent_streams(64)
        .keep_alive_interval(Some(Duration::from_secs(30)))
        .keep_alive_timeout(Duration::from_secs(20));
    let builder: &'static auto::Builder<TokioExecutor> = Box::leak(Box::new(builder));
    let alt_svc: Option<&'static str> = alt_svc.map(|s| &*Box::leak(s.into_boxed_str()));
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
                    async move {
                        let mut resp = handle(app, peer, req).await.unwrap_or_else(|e: Infallible| match e {});
                        if let Some(v) = alt_svc {
                            resp.headers_mut().insert("alt-svc", hyper::header::HeaderValue::from_static(v));
                        }
                        Ok::<_, Infallible>(resp)
                    }
                });
                let conn = builder.serve_connection(TokioIo::new(tls), service);
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
