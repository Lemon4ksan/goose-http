// /plaintext and /json on hyper 1 and Tokio's multi-threaded runtime, the
// stack under Axum, configured as TechEmpower's hyper entry runs it with
// `--runtime multi-thread`: one listener, an accept loop task, a task per
// connection, and pipeline_flush so pipelined responses leave in one write.
//
//     WORKERS=n bench-hyper [port]

use std::convert::Infallible;
use std::net::{Ipv4Addr, SocketAddr};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::header::{HeaderValue, ALLOW, CONTENT_TYPE, SERVER};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use serde::Serialize;
use socket2::{Domain, Socket, Type};
use tokio::net::TcpListener;

static SERVER_NAME: HeaderValue = HeaderValue::from_static("hyper");
static TEXT_PLAIN: HeaderValue = HeaderValue::from_static("text/plain");
static APPLICATION_JSON: HeaderValue = HeaderValue::from_static("application/json");

#[derive(Serialize)]
struct Message {
    message: &'static str,
}

fn response(status: StatusCode, body: Full<Bytes>) -> Response<Full<Bytes>> {
    let mut r = Response::new(body);
    *r.status_mut() = status;
    r.headers_mut().insert(SERVER, SERVER_NAME.clone());
    r
}

async fn router(req: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let path = req.uri().path();
    let known = path == "/plaintext" || path == "/json";
    if known && req.method() != Method::GET && req.method() != Method::HEAD {
        // Read the body to its end, as the other servers do, so the
        // connection stays usable.
        let _ = req.into_body().collect().await;
        let mut r = response(StatusCode::METHOD_NOT_ALLOWED, Full::default());
        r.headers_mut().insert(ALLOW, HeaderValue::from_static("GET, HEAD"));
        return Ok(r);
    }
    Ok(match path {
        "/plaintext" => {
            let mut r = response(StatusCode::OK, Full::new(Bytes::from_static(b"Hello, World!")));
            r.headers_mut().insert(CONTENT_TYPE, TEXT_PLAIN.clone());
            r
        }
        "/json" => {
            let body = serde_json::to_vec(&Message { message: "Hello, World!" }).unwrap();
            let mut r = response(StatusCode::OK, Full::new(Bytes::from(body)));
            r.headers_mut().insert(CONTENT_TYPE, APPLICATION_JSON.clone());
            r
        }
        _ => response(StatusCode::NOT_FOUND, Full::default()),
    })
}

fn listener(port: u16) -> std::io::Result<std::net::TcpListener> {
    let addr = SocketAddr::from((Ipv4Addr::UNSPECIFIED, port));
    let socket = Socket::new(Domain::IPV4, Type::STREAM, None)?;
    socket.set_reuse_address(true)?;
    socket.set_tcp_nodelay(true)?;
    socket.set_nonblocking(true)?;
    socket.bind(&addr.into())?;
    socket.listen(4096)?;
    Ok(socket.into())
}

async fn serve(port: u16) -> std::io::Result<()> {
    let listener = TcpListener::from_std(listener(port)?)?;
    let mut http = http1::Builder::new();
    http.pipeline_flush(true);
    loop {
        let (stream, _) = listener.accept().await?;
        let http = http.clone();
        tokio::spawn(async move {
            let _ = http.serve_connection(TokioIo::new(stream), service_fn(router)).await;
        });
    }
}

fn main() -> std::io::Result<()> {
    let workers = std::env::var("WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()));
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(8080);
    println!("hyper: {workers} workers on port {port}");
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(workers)
        .build()?;
    // The accept loop runs as a task, so it's scheduled with the connections.
    runtime.block_on(async move { tokio::spawn(serve(port)).await.unwrap() })
}
