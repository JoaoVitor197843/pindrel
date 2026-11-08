//! What the file routes need from the gateway: their own rate limit, a bounded amount of request body held in memory,
//! longer windows for a piece and for joining a file, and downloads that stream with Range intact.
mod common;

use std::{
    convert::Infallible,
    net::SocketAddr,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};

use bytes::Bytes;
use common::*;
use http_body_util::{BodyExt, Full};
use hyper::{body::Incoming, service::service_fn, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use pindrel_gateway::{config::Config, server};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    task::JoinHandle,
    time,
};

/// A replica that answers with whatever `f` makes of the request; it also counts how many requests it holds at once.
struct Replica {
    addr: SocketAddr,
    peak: Arc<AtomicUsize>,
    _task: JoinHandle<()>,
}

async fn replica<F, Fut>(f: F) -> Replica
where
    F: Fn(Request<Incoming>) -> Fut + Clone + Send + Sync + 'static,
    Fut: std::future::Future<Output = Response<Full<Bytes>>> + Send + 'static,
{
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let (now, peak) = (Arc::new(AtomicUsize::new(0)), Arc::new(AtomicUsize::new(0)));
    let (n2, p2) = (now.clone(), peak.clone());
    let task = tokio::spawn(async move {
        loop {
            let Ok((s, _)) = listener.accept().await else { return };
            let (f, now, peak) = (f.clone(), n2.clone(), p2.clone());
            tokio::spawn(async move {
                let svc = service_fn(move |req| {
                    let (f, now, peak) = (f.clone(), now.clone(), peak.clone());
                    async move {
                        let held = now.fetch_add(1, Ordering::SeqCst) + 1;
                        peak.fetch_max(held, Ordering::SeqCst);
                        let res = f(req).await;
                        now.fetch_sub(1, Ordering::SeqCst);
                        Ok::<_, Infallible>(res)
                    }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(TokioIo::new(s), svc)
                    .await;
            });
        }
    });
    Replica { addr, peak, _task: task }
}

fn ok(body: impl Into<Bytes>) -> Response<Full<Bytes>> {
    Response::new(Full::new(body.into()))
}

async fn gateway_for(r: &Replica, tweak: impl FnOnce(&mut Config)) -> server::Running {
    let mut cfg = Config::new(vec![r.addr]);
    cfg.port = 0;
    cfg.mdns = false;
    cfg.probe_interval = Duration::from_secs(3600);
    tweak(&mut cfg);
    server::start_with(cfg, None).await.expect("gateway starts")
}

/// Sends a body of `n` bytes with a Content-Length and returns the reply.
async fn put(gw: SocketAddr, method: &str, path: &str, n: usize) -> Reply {
    let mut b = Request::builder()
        .method(method)
        .uri(format!("http://127.0.0.1:{}{path}", gw.port()));
    b = b.header("content-length", n.to_string());
    let resp = client()
        .request(b.body(Full::new(Bytes::from(vec![7u8; n]))).unwrap())
        .await
        .expect("request");
    let (p, inc) = resp.into_parts();
    Reply {
        status: p.status,
        headers: p.headers,
        body: inc.collect().await.unwrap().to_bytes(),
    }
}

#[tokio::test]
async fn files_have_their_own_limit_and_do_not_spend_the_general_one() {
    let r = replica(|_| async { ok("ok") }).await;
    let gw = gateway_for(&r, |_| {}).await;
    // far more than the general burst of 20, and none refused
    for i in 0..100 {
        assert_eq!(get(gw.addr, "/files/abc").await.status, StatusCode::OK, "request {i}");
    }
    // the general limit is untouched by all of that
    assert_eq!(get(gw.addr, "/x").await.status, StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn the_files_limit_still_exists() {
    let r = replica(|_| async { ok("ok") }).await;
    let gw = gateway_for(&r, |_| {}).await;
    let mut refused = 0;
    for _ in 0..400 {
        if get(gw.addr, "/files/abc").await.status == StatusCode::TOO_MANY_REQUESTS {
            refused += 1;
        }
    }
    assert!(refused > 0, "400 requests in a burst must hit the limit of the file routes");
    gw.shutdown().await;
}

#[tokio::test]
async fn bodies_held_in_memory_never_pass_the_budget() {
    let r = replica(|req| async move {
        let _ = req.into_body().collect().await;
        time::sleep(Duration::from_millis(300)).await;
        ok("done")
    })
    .await;
    // a budget of 2 MiB holds four pieces of 512 KiB at the same time
    let gw = gateway_for(&r, |c| c.body_budget = 2 << 20).await;
    let addr = gw.addr;
    let mut all = Vec::new();
    for _ in 0..12 {
        all.push(tokio::spawn(async move {
            put(addr, "PUT", "/files/uploads/u/0", 512 << 10).await.status
        }));
    }
    for t in all {
        assert_eq!(t.await.unwrap(), StatusCode::OK, "every piece gets through, queued");
    }
    assert!(
        r.peak.load(Ordering::SeqCst) <= 4,
        "{} pieces were in flight, the budget allows 4",
        r.peak.load(Ordering::SeqCst)
    );
    assert!(
        r.peak.load(Ordering::SeqCst) >= 2,
        "the budget must still let pieces run side by side"
    );
    gw.shutdown().await;
}

#[tokio::test]
async fn a_gateway_with_no_room_says_try_again_in_a_moment() {
    let r = replica(|req| async move {
        let _ = req.into_body().collect().await;
        time::sleep(Duration::from_millis(1500)).await;
        ok("done")
    })
    .await;
    let gw = gateway_for(&r, |c| {
        c.body_budget = 1 << 20;
        c.body_queue = Duration::from_millis(150);
    })
    .await;
    let addr = gw.addr;
    let first = tokio::spawn(async move { put(addr, "PUT", "/files/uploads/u/0", 1 << 20).await.status });
    time::sleep(Duration::from_millis(200)).await;
    let busy = put(gw.addr, "PUT", "/files/uploads/u/1", 1 << 20).await;
    assert_eq!(busy.status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(busy.header("retry-after"), "1");
    assert_eq!(error_of(&busy).code, "server_busy");
    assert_eq!(first.await.unwrap(), StatusCode::OK);
    // once the room is back, the same request goes through
    assert_eq!(put(gw.addr, "PUT", "/files/uploads/u/1", 1 << 20).await.status, StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn small_bodies_do_not_wait_for_the_budget() {
    let r = replica(|req| async move {
        let _ = req.into_body().collect().await;
        time::sleep(Duration::from_millis(800)).await;
        ok("done")
    })
    .await;
    let gw = gateway_for(&r, |c| {
        c.body_budget = 1 << 20;
        c.body_queue = Duration::from_millis(100);
    })
    .await;
    let addr = gw.addr;
    let big = tokio::spawn(async move { put(addr, "PUT", "/files/uploads/u/0", 1 << 20).await.status });
    time::sleep(Duration::from_millis(150)).await;
    // a login-sized body passes while the budget is spent
    let small = put(gw.addr, "POST", "/auth/login/", 200).await;
    assert_eq!(small.status, StatusCode::OK);
    assert_eq!(big.await.unwrap(), StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn a_body_over_the_limit_is_refused_and_gives_its_room_back() {
    let r = replica(|req| async move {
        let _ = req.into_body().collect().await;
        ok("done")
    })
    .await;
    let gw = gateway_for(&r, |c| c.body_budget = 1 << 20).await;
    for _ in 0..5 {
        // each one is over MAX_BODY_BYTES: refused, and the budget it reserved must come back
        assert_eq!(
            put(gw.addr, "PUT", "/files/uploads/u/0", (1 << 20) + 1).await.status,
            StatusCode::PAYLOAD_TOO_LARGE
        );
    }
    assert_eq!(put(gw.addr, "PUT", "/files/uploads/u/0", 1 << 20).await.status, StatusCode::OK);
    gw.shutdown().await;
}

#[tokio::test]
async fn ranges_head_and_conditional_requests_pass_through_untouched() {
    let r = replica(|req| async move {
        let mut res = ok(Bytes::new());
        let range = req.headers().get("range").and_then(|v| v.to_str().ok()).map(str::to_string);
        res.headers_mut().insert("accept-ranges", "bytes".parse().unwrap());
        res.headers_mut().insert("etag", "\"abc\"".parse().unwrap());
        res.headers_mut()
            .insert("content-disposition", "attachment; filename=a.zip".parse().unwrap());
        res.headers_mut()
            .insert("content-security-policy", "sandbox; default-src 'none'".parse().unwrap());
        if req.headers().get("if-none-match").is_some() {
            *res.status_mut() = StatusCode::NOT_MODIFIED;
        } else if req.method() == "HEAD" {
            res.headers_mut().insert("content-length", "100".parse().unwrap());
        } else if let Some(r) = range {
            if r == "bytes=500-600" {
                *res.status_mut() = StatusCode::RANGE_NOT_SATISFIABLE;
                res.headers_mut().insert("content-range", "bytes */100".parse().unwrap());
            } else {
                *res.status_mut() = StatusCode::PARTIAL_CONTENT;
                res.headers_mut().insert("content-range", "bytes 0-9/100".parse().unwrap());
                *res.body_mut() = Full::new(Bytes::from_static(b"0123456789"));
            }
        } else {
            *res.body_mut() = Full::new(Bytes::from(vec![1u8; 100]));
        }
        res
    })
    .await;
    let gw = gateway_for(&r, |_| {}).await;
    let partial = send(gw.addr, "GET", "/files/x", &[("range", "bytes=0-9")], "").await;
    assert_eq!(partial.status, StatusCode::PARTIAL_CONTENT);
    assert_eq!(partial.header("content-range"), "bytes 0-9/100");
    assert_eq!(&partial.body[..], b"0123456789");
    assert_eq!(partial.header("etag"), "\"abc\"");
    assert_eq!(partial.header("content-security-policy"), "sandbox; default-src 'none'");
    assert_eq!(partial.header("content-disposition"), "attachment; filename=a.zip");
    let beyond = send(gw.addr, "GET", "/files/x", &[("range", "bytes=500-600")], "").await;
    assert_eq!(
        (beyond.status, beyond.header("content-range")),
        (StatusCode::RANGE_NOT_SATISFIABLE, "bytes */100")
    );
    let head = send(gw.addr, "HEAD", "/files/x", &[], "").await;
    assert_eq!(
        (head.status, head.header("content-length"), head.body.len()),
        (StatusCode::OK, "100", 0)
    );
    let cached = send(gw.addr, "GET", "/files/x", &[("if-none-match", "\"abc\"")], "").await;
    assert_eq!((cached.status, cached.body.len()), (StatusCode::NOT_MODIFIED, 0));
    gw.shutdown().await;
}

/// A replica written by hand that sends `total` bytes in blocks with a pause between them.
async fn slow_streamer(total: usize, block: usize, gap: Duration) -> (SocketAddr, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let task = tokio::spawn(async move {
        loop {
            let Ok((mut s, _)) = listener.accept().await else { return };
            tokio::spawn(async move {
                let mut head = Vec::new();
                let mut buf = [0u8; 1024];
                while !head.windows(4).any(|w| w == b"\r\n\r\n") {
                    match s.read(&mut buf).await {
                        Ok(0) | Err(_) => return,
                        Ok(n) => head.extend_from_slice(&buf[..n]),
                    }
                }
                let _ = s
                    .write_all(
                        format!("HTTP/1.1 200 OK\r\ncontent-type: application/octet-stream\r\ncontent-length: {total}\r\n\r\n").as_bytes(),
                    )
                    .await;
                let mut sent = 0;
                while sent < total {
                    let n = block.min(total - sent);
                    if s.write_all(&vec![9u8; n]).await.is_err() {
                        return;
                    }
                    sent += n;
                    time::sleep(gap).await;
                }
            });
        }
    });
    (addr, task)
}

#[tokio::test]
async fn a_download_streams_and_is_not_cut_by_the_time_to_first_byte_limit() {
    // 4 MiB in 16 blocks, 150 ms apart: about 2.4 s in all, with a time limit for headers of 1 s
    let (addr, _task) = slow_streamer(4 << 20, 256 << 10, Duration::from_millis(150)).await;
    let mut cfg = Config::new(vec![addr]);
    cfg.port = 0;
    cfg.mdns = false;
    cfg.probe_interval = Duration::from_secs(3600);
    cfg.upstream_timeout = Duration::from_secs(1);
    let gw = server::start_with(cfg, None).await.unwrap();
    let started = Instant::now();
    let mut s = TcpStream::connect(gw.addr).await.unwrap();
    s.write_all(b"GET /files/big HTTP/1.1\r\nhost: x\r\nconnection: close\r\n\r\n")
        .await
        .unwrap();
    let mut first = vec![0u8; 4096];
    let n = s.read(&mut first).await.unwrap();
    assert!(
        n > 0 && started.elapsed() < Duration::from_millis(900),
        "the first bytes must arrive while the rest is still being produced"
    );
    let mut total = n;
    let mut rest = Vec::new();
    s.read_to_end(&mut rest).await.unwrap();
    total += rest.len();
    assert!(
        started.elapsed() > Duration::from_millis(1500),
        "the body takes longer than the header limit and still arrives"
    );
    // headers + 4 MiB
    assert!(total > 4 << 20, "{total} bytes received");
    gw.shutdown().await;
}

#[tokio::test]
async fn a_piece_gets_a_long_window_to_arrive_and_other_bodies_do_not() {
    let r = replica(|req| async move {
        let b = req.into_body().collect().await.map(|b| b.to_bytes()).unwrap_or_default();
        ok(b)
    })
    .await;
    let gw = gateway_for(&r, |c| {
        c.body_timeout = Duration::from_millis(300);
        c.file_body_timeout = Duration::from_secs(3);
    })
    .await;
    async fn slow(gw: SocketAddr, method: &str, path: &str) -> String {
        let mut s = TcpStream::connect(gw).await.unwrap();
        s.write_all(format!("{method} {path} HTTP/1.1\r\nhost: x\r\ncontent-length: 10\r\nconnection: close\r\n\r\nabcde").as_bytes())
            .await
            .unwrap();
        time::sleep(Duration::from_millis(900)).await;
        let _ = s.write_all(b"fghij").await;
        let mut out = String::new();
        let _ = s.read_to_string(&mut out).await;
        out
    }
    let piece = slow(gw.addr, "PUT", "/files/uploads/u/0").await;
    assert!(piece.starts_with("HTTP/1.1 200") && piece.ends_with("abcdefghij"), "{piece}");
    let other = slow(gw.addr, "POST", "/notes/x").await;
    assert!(other.starts_with("HTTP/1.1 408"), "{other}");
    gw.shutdown().await;
}

#[tokio::test]
async fn joining_a_large_file_gets_a_long_window_and_other_routes_do_not() {
    let r = replica(|_| async {
        time::sleep(Duration::from_millis(1200)).await;
        ok("done")
    })
    .await;
    let gw = gateway_for(&r, |c| {
        c.upstream_timeout = Duration::from_millis(400);
        c.file_finish_timeout = Duration::from_secs(5);
    })
    .await;
    assert_eq!(
        send(gw.addr, "POST", "/files/uploads/abc/finish", &[], "").await.status,
        StatusCode::OK
    );
    assert_eq!(
        send(gw.addr, "POST", "/files/abc/link", &[], "").await.status,
        StatusCode::GATEWAY_TIMEOUT
    );
    assert_eq!(
        send(gw.addr, "GET", "/files/uploads/abc/finish", &[], "").await.status,
        StatusCode::GATEWAY_TIMEOUT,
        "only the POST that joins"
    );
    gw.shutdown().await;
}
