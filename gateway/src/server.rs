//! Wires everything together: listener, background tasks, graceful shutdown.
use std::{io, net::SocketAddr, sync::Arc, time::Duration};

use hyper::service::service_fn;
use hyper_util::{
    rt::{TokioIo, TokioTimer},
    server::graceful::GracefulShutdown,
};
use tokio::{
    net::TcpListener,
    sync::{oneshot, watch, Semaphore},
    task::JoinHandle,
    time,
};

use crate::{
    config::Config,
    discovery::{self, Lan, Registry},
    handler::{handle, App},
    identity, known,
    limiter::ConnLimit,
};

pub struct Running {
    pub addr: SocketAddr,
    pub app: Arc<App>,
    shutdown: watch::Sender<bool>,
    task: JoinHandle<()>,
    /// Fires once the listener is closed.
    closed: oneshot::Receiver<()>,
    mdns: Option<mdns_sd::ServiceDaemon>,
}

impl Running {
    /// Stops accepting, leaves the mDNS group and lets in-flight requests finish (up to 5 s).
    /// The port is closed *before* the goodbye: the others check a server that stops being
    /// announced by connecting to it, and must not find it still open.
    pub async fn shutdown(self) {
        let _ = self.shutdown.send(true);
        let _ = time::timeout(Duration::from_secs(2), self.closed).await;
        if let Some(d) = &self.mdns {
            let _ = d.shutdown();
        }
        let _ = self.task.await;
    }
}

/// Binds `0.0.0.0:cfg.port` (0 = any free port) and starts serving.
pub async fn start(cfg: Config) -> io::Result<Running> {
    start_with(cfg, Lan::detect()).await
}

/// Like `start`, with the local network given (tests use one that contains loopback).
pub async fn start_with(cfg: Config, local_net: Option<Lan>) -> io::Result<Running> {
    let listener = TcpListener::bind(("0.0.0.0", cfg.port)).await?;
    let addr = listener.local_addr()?;
    let lan = discovery::lan_ip();
    let own_ips = lan.map(|i| vec![i.to_string()]).unwrap_or_default();
    let id = identity::load_or_create(cfg.server_id_file.as_deref());
    let registry = Arc::new(Registry::new(addr.port(), own_ips).with_lan(local_net).with_id(id.clone()));

    let mut mdns = None;
    if cfg.mdns {
        match discovery::start(
            &cfg.server_name,
            &id,
            addr.port(),
            lan,
            &cfg.mdns_interfaces,
            cfg.mdns_refresh,
            registry.clone(),
        ) {
            Ok(d) => {
                eprintln!(
                    "mDNS: announcing {:?} as {} on port {}",
                    cfg.server_name,
                    discovery::SERVICE_TYPE,
                    addr.port()
                );
                mdns = Some(d);
            }
            Err(e) => eprintln!("mDNS disabled: {e}"),
        }
    }

    let remember = cfg.known_interval > Duration::ZERO && (cfg.mdns || cfg.known_file.is_some());
    let (known_file, known_interval) = (cfg.known_file.clone(), cfg.known_interval);
    let address = lan.map(|ip| format!("{ip}:{}", addr.port()));
    let app = Arc::new(App::new(cfg, registry.clone(), address));
    let (tx, rx) = watch::channel(false);

    if remember {
        tokio::spawn(known::run(registry, local_net, known_file, known_interval, rx.clone()));
    }

    // keeps the list of live replicas fresh
    let (a, mut stop) = (app.clone(), rx.clone());
    tokio::spawn(async move {
        // the first probe is done right below, so the periodic ones start one interval from now
        let mut tick = time::interval_at(time::Instant::now() + a.cfg.probe_interval, a.cfg.probe_interval);
        loop {
            tokio::select! {
                _ = tick.tick() => a.pool.probe().await,
                _ = stop.changed() => return,
            }
        }
    });
    // forgets idle clients of the rate limiters
    let (a, mut stop) = (app.clone(), rx.clone());
    tokio::spawn(async move {
        let mut tick = time::interval_at(time::Instant::now() + Duration::from_secs(600), Duration::from_secs(600));
        loop {
            tokio::select! {
                _ = tick.tick() => a.limiters.prune(),
                _ = stop.changed() => return,
            }
        }
    });
    app.pool.probe().await; // so the first request already knows who is up

    #[cfg(feature = "tls")]
    if let Some(t) = app.cfg.tls.clone() {
        start_tls(&app, &t, rx.clone()).await?;
    }
    #[cfg(not(feature = "tls"))]
    if app.cfg.tls.is_some() {
        eprintln!("TLS_PORT is set but this build has no TLS (build with --features tls or http3)");
    }

    let (closed_tx, closed) = oneshot::channel();
    let task = tokio::spawn(accept_loop(app.clone(), listener, rx, closed_tx));
    Ok(Running {
        addr,
        app,
        shutdown: tx,
        task,
        closed,
        mdns,
    })
}

async fn accept_loop(app: Arc<App>, listener: TcpListener, mut stop: watch::Receiver<bool>, closed: oneshot::Sender<()>) {
    let permits = Arc::new(Semaphore::new(app.cfg.max_connections));
    let graceful = GracefulShutdown::new();
    let per_ip = ConnLimit::new(app.cfg.max_connections_per_ip);
    loop {
        // a permit per open connection bounds the memory a flood of connections can take
        let permit = tokio::select! {
            p = permits.clone().acquire_owned() => p.unwrap(),
            _ = stop.changed() => break,
        };
        let (stream, peer) = tokio::select! {
            r = listener.accept() => match r { Ok(c) => c, Err(_) => continue },
            _ = stop.changed() => break,
        };
        // a declared proxy (a tunnel) carries many clients over its own connections: those are limited per request
        let slot = if app.cfg.client_ip.is_proxy(peer.ip()) {
            None
        } else {
            match per_ip.acquire(peer.ip()) {
                Some(g) => Some(g),
                None => continue, // this client already holds its share: closed without reading anything
            }
        };
        let _ = stream.set_nodelay(true);
        let app2 = app.clone();
        let conn = hyper::server::conn::http1::Builder::new()
            .timer(TokioTimer::new())
            .header_read_timeout(app.cfg.header_timeout)
            .serve_connection(TokioIo::new(stream), service_fn(move |req| handle(app2.clone(), peer, req)));
        let conn = graceful.watch(conn);
        tokio::spawn(async move {
            let _ = conn.await;
            drop((permit, slot));
        });
    }
    drop(listener); // nobody can connect any more, even while the open requests finish
    let _ = closed.send(());
    tokio::select! {
        _ = graceful.shutdown() => {}
        _ = time::sleep(Duration::from_secs(5)) => eprintln!("shutdown: some connections were still open after 5 s"),
    }
}

#[cfg(feature = "tls")]
async fn start_tls(app: &Arc<App>, t: &crate::config::TlsConfig, stop: watch::Receiver<bool>) -> io::Result<()> {
    let h3 = cfg!(feature = "http3") && t.http3;
    let tcp = TcpListener::bind(("0.0.0.0", t.port)).await?;
    let tcp_cfg = crate::tls::server_config(&t.cert, &t.key, &[b"h2", b"http/1.1"])?;
    let alt_svc = h3.then(|| format!("h3=\":{}\"; ma=86400", t.port));
    tokio::spawn(crate::tls::accept_loop(app.clone(), tcp, tcp_cfg, alt_svc, stop.clone()));
    eprintln!("TLS: HTTP/1.1 + HTTP/2 on port {}", t.port);
    #[cfg(feature = "http3")]
    if h3 {
        let quic_cfg = crate::tls::server_config(&t.cert, &t.key, &[b"h3"])?;
        let endpoint = crate::h3::endpoint(quic_cfg, ([0, 0, 0, 0], t.port).into())?;
        tokio::spawn(crate::h3::accept_loop(app.clone(), endpoint, stop));
        eprintln!("TLS: HTTP/3 on udp port {}", t.port);
    }
    Ok(())
}
