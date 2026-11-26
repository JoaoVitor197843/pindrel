use std::{collections::HashMap, net::TcpStream, path::Path, process::ExitCode, time::Duration};

use pindrel_gateway::{config::Config, envfile, server};

/// `gateway healthcheck`: exit 0 when the local listener accepts connections (Docker HEALTHCHECK, no wget needed).
fn healthcheck(port: Option<String>) -> ExitCode {
    let port: u16 = port.and_then(|p| p.trim().parse().ok()).unwrap_or(8080);
    match TcpStream::connect_timeout(&([127, 0, 0, 1], port).into(), Duration::from_secs(2)) {
        Ok(_) => ExitCode::SUCCESS,
        Err(_) => ExitCode::FAILURE,
    }
}

/// `--config <file>` / GATEWAY_CONFIG: settings from a file (none named: no file).
fn settings_file(args: &[String]) -> Result<HashMap<String, String>, String> {
    match envfile::path_from(args.iter().cloned(), |k| std::env::var(k).ok())? {
        None => Ok(HashMap::new()),
        Some(path) => envfile::load(Path::new(&path)),
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
    let args: Vec<String> = std::env::args().skip(1).collect();
    let file = match settings_file(&args) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("invalid configuration:\n - {e}");
            return ExitCode::FAILURE;
        }
    };
    // a variable that is really set wins over the file
    let lookup = |k: &str| std::env::var(k).ok().or_else(|| file.get(k).cloned());
    if args.first().map(String::as_str) == Some("healthcheck") {
        return healthcheck(lookup("GATEWAY_PORT"));
    }
    let cfg = match Config::from_lookup(lookup) {
        Ok(c) => c,
        Err(errs) => {
            eprintln!("invalid configuration:\n - {}", errs.join("\n - "));
            return ExitCode::FAILURE;
        }
    };
    if let Some(why) = cfg.unsupported() {
        eprintln!("invalid configuration:\n - {why}");
        return ExitCode::FAILURE;
    }
    // `--check`: the settings are valid, nothing was started (installers run it before enabling the service)
    if args.iter().any(|a| a == "--check") {
        println!("configuration ok");
        return ExitCode::SUCCESS;
    }
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
