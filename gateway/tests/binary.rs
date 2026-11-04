//! The compiled `gateway` binary: configuration errors, healthcheck and signal handling.
use std::{
    io::{BufRead, BufReader},
    net::TcpStream,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

fn gateway() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_gateway"));
    c.env_clear();
    c
}

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}

#[test]
fn bad_configuration_exits_with_all_the_problems() {
    let out = gateway().env("GATEWAY_PORT", "0").env("MDNS_ENABLED", "maybe").output().unwrap();
    assert!(!out.status.success());
    let err = String::from_utf8_lossy(&out.stderr);
    for want in ["GATEWAY_PORT", "MDNS_ENABLED", "UPSTREAMS"] {
        assert!(err.contains(want), "stderr should mention {want}: {err}");
    }
}

#[test]
fn healthcheck_fails_when_nothing_listens() {
    let status = gateway()
        .arg("healthcheck")
        .env("GATEWAY_PORT", free_port().to_string())
        .status()
        .unwrap();
    assert_eq!(status.code(), Some(1));
}

#[cfg(unix)]
#[test]
fn serves_reports_healthy_and_stops_cleanly_on_sigterm() {
    let port = free_port();
    let mut child = gateway()
        .env("GATEWAY_PORT", port.to_string())
        .env("UPSTREAMS", "127.0.0.1:1")
        .env("MDNS_ENABLED", "false")
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut log = BufReader::new(child.stderr.take().unwrap());
    // Warnings come first when the environment asks for them (a container with the default limit of 1024 open files gets
    // one): wait for the line that says it listens instead of expecting it to be the first.
    let mut seen = Vec::new();
    loop {
        let mut line = String::new();
        let n = log.read_line(&mut line).unwrap();
        assert!(n > 0 && seen.len() < 20, "the gateway never said it listens; log so far: {seen:?}");
        if line.contains("listening") {
            break;
        }
        seen.push(line);
    }

    assert!(TcpStream::connect(("127.0.0.1", port)).is_ok());
    let status = gateway().arg("healthcheck").env("GATEWAY_PORT", port.to_string()).status().unwrap();
    assert!(status.success(), "healthcheck should pass while the gateway listens");

    Command::new("kill").args(["-TERM", &child.id().to_string()]).status().unwrap();
    let t = Instant::now();
    let exit = loop {
        if let Some(s) = child.try_wait().unwrap() {
            break s;
        }
        assert!(t.elapsed() < Duration::from_secs(8), "did not stop after SIGTERM");
        std::thread::sleep(Duration::from_millis(50));
    };
    assert!(exit.success(), "a clean shutdown exits with 0, got {exit}");
    assert!(TcpStream::connect(("127.0.0.1", port)).is_err());
}
