use std::{net::TcpStream, process::ExitCode, time::Duration};

use pindrel_gateway::{config::Config, server};

/// `gateway healthcheck`: exit 0 when the local listener accepts connections (Docker HEALTHCHECK, no wget needed).
fn healthcheck() -> ExitCode {
    let port: u16 = std::env::var("GATEWAY_PORT")
        .ok()
        .and_then(|p| p.trim().parse().ok())
        .unwrap_or(8080);
    match TcpStream::connect_timeout(&([127, 0, 0, 1], port).into(), Duration::from_secs(2)) {
        Ok(_) => ExitCode::SUCCESS,
        Err(_) => ExitCode::FAILURE,
    }
}

async fn wait_for_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = signal(SignalKind::terminate()).expect("SIGTERM handler");
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    }
    #[cfg(not(unix))]
    let _ = tokio::signal::ctrl_c().await;
}

// one thread for the runtime: the gateway only shuffles bytes, and every extra thread costs RAM
#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    if std::env::args().nth(1).as_deref() == Some("healthcheck") {
        return healthcheck();
    }
    let cfg = match Config::from_env() {
        Ok(c) => c,
        Err(errs) => {
            eprintln!("invalid configuration:\n - {}", errs.join("\n - "));
            return ExitCode::FAILURE;
        }
    };
    let upstreams = cfg.upstreams.len();
    let running = match server::start(cfg).await {
        Ok(r) => r,
        Err(e) => {
            eprintln!("could not start: {e}");
            return ExitCode::FAILURE;
        }
    };
    eprintln!("gateway listening on {} ({upstreams} possible upstreams)", running.addr);
    wait_for_signal().await;
    eprintln!("shutting down...");
    running.shutdown().await;
    ExitCode::SUCCESS
}
