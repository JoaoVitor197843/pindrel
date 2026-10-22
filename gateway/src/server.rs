//! Wires everything together: listener, background tasks, graceful shutdown.
use std::{io, net::SocketAddr, sync::Arc, time::Duration};

use hyper::service::service_fn;
use hyper_util::{
    rt::{TokioIo, TokioTimer},
    server::graceful::GracefulShutdown,
};
use tokio::{
    net::TcpListener,
    sync::{watch, Semaphore},
    task::JoinHandle,
    time,
};

use crate::{
    config::Config,
    discovery::{self, Registry},
    handler::{handle, App},
};

pub struct Running {
    pub addr: SocketAddr,
    pub app: Arc<App>,
    shutdown: watch::Sender<bool>,
    task: JoinHandle<()>,
    mdns: Option<mdns_sd::ServiceDaemon>,
}

impl Running {
    /// Stops accepting, lets in-flight requests finish (up to 5 s) and leaves the mDNS group.
    pub async fn shutdown(self) {
        if let Some(d) = &self.mdns {
            let _ = d.shutdown();
        }
        let _ = self.shutdown.send(true);
        let _ = self.task.await;
    }
}

/// Binds `0.0.0.0:cfg.port` (0 = any free port) and starts serving.
pub async fn start(cfg: Config) -> io::Result<Running> {
    let listener = TcpListener::bind(("0.0.0.0", cfg.port)).await?;
    let addr = listener.local_addr()?;
    let lan = discovery::lan_ip();
    let own_ips = lan.map(|i| vec![i.to_string()]).unwrap_or_default();
    let registry = Arc::new(Registry::new(addr.port(), own_ips));

    let mut mdns = None;
    if cfg.mdns {
        match discovery::start(&cfg.server_name, addr.port(), lan, &cfg.mdns_interfaces, registry.clone()) {
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

    let app = Arc::new(App::new(cfg, registry));
    let (tx, rx) = watch::channel(false);

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
                _ = tick.tick() => a.limiters.prune(Duration::from_secs(1800)),
                _ = stop.changed() => return,
            }
        }
    });
    app.pool.probe().await; // so the first request already knows who is up

    let task = tokio::spawn(accept_loop(app.clone(), listener, rx));
    Ok(Running {
        addr,
        app,
        shutdown: tx,
        task,
        mdns,
    })
}

async fn accept_loop(app: Arc<App>, listener: TcpListener, mut stop: watch::Receiver<bool>) {
    let permits = Arc::new(Semaphore::new(app.cfg.max_connections));
    let graceful = GracefulShutdown::new();
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
        let _ = stream.set_nodelay(true);
        let app2 = app.clone();
        let conn = hyper::server::conn::http1::Builder::new()
            .timer(TokioTimer::new())
            .header_read_timeout(app.cfg.header_timeout)
            .serve_connection(TokioIo::new(stream), service_fn(move |req| handle(app2.clone(), peer, req)));
        let conn = graceful.watch(conn);
        tokio::spawn(async move {
            let _ = conn.await;
            drop(permit);
        });
    }
    tokio::select! {
        _ = graceful.shutdown() => {}
        _ = time::sleep(Duration::from_secs(5)) => eprintln!("shutdown: some connections were still open after 5 s"),
    }
}
