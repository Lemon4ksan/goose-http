// The REST benchmark's tiers (task 021) on hyper 1 and Tokio's multi-threaded
// runtime, set up as bench/hyper is. Tier A is HttpArena's production-stack
// application layer, answered from the generator's dataset files:
//
//   GET  /api/items/:id    the item, and servedAt, the time in seconds
//   GET  /api/me           the user X-User-Id names, and servedAt
//   POST /api/items/:id    a body of name, price, and quantity, each optional:
//                          204, or 422; the data doesn't change
//
//   REST_DATA=DIR WORKERS=n [JSON=template] rest-hyper [port]
//
// JSON=template answers from each record's JSON, written once at startup,
// with servedAt added per request; the default serializes each response with
// serde_json, the library Rust servers use.

use std::convert::Infallible;
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::{Arc, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::header::{HeaderValue, CONTENT_TYPE, SERVER};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use serde::{Deserialize, Serialize};
use socket2::{Domain, Socket, Type};
use tokio::net::TcpListener;

static SERVER_NAME: HeaderValue = HeaderValue::from_static("hyper");
static APPLICATION_JSON: HeaderValue = HeaderValue::from_static("application/json");

#[derive(Deserialize, Serialize)]
struct Rating {
    score: i64,
    count: i64,
}

#[derive(Deserialize, Serialize)]
struct Item {
    id: i64,
    name: String,
    category: String,
    price: i64,
    quantity: i64,
    active: bool,
    tags: Vec<String>,
    rating: Rating,
}

#[derive(Deserialize, Serialize)]
struct User {
    id: i64,
    name: String,
    email: String,
    plan: String,
}

// A record with servedAt after its fields, as one JSON object.
#[derive(Serialize)]
struct Served<'a, T> {
    #[serde(flatten)]
    record: &'a T,
    #[serde(rename = "servedAt")]
    served_at: u64,
}

// A write's body: each field optional, and of its type.
#[derive(Deserialize)]
#[allow(dead_code)]
struct Write {
    name: Option<String>,
    price: Option<i64>,
    quantity: Option<i64>,
}

struct Data {
    items: Vec<Item>,
    users: Vec<User>,
    // JSON=template's records, each without its closing brace.
    item_json: Vec<Vec<u8>>,
    user_json: Vec<Vec<u8>>,
    template: bool,
}

static DATA: OnceLock<Data> = OnceLock::new();

// The time in seconds, which a coarse clock gives as cheaply.
fn now_s() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

fn without_brace(mut v: Vec<u8>) -> Vec<u8> {
    v.pop();
    v
}

fn load(dir: &str) -> Data {
    let read = |name: &str| {
        std::fs::read(format!("{dir}/{name}")).unwrap_or_else(|e| panic!("{dir}/{name}: {e}; run bench/rest/gen.goose"))
    };
    let items: Vec<Item> = serde_json::from_slice(&read("arena-items.json")).expect("arena-items.json");
    let users: Vec<User> = serde_json::from_slice(&read("arena-users.json")).expect("arena-users.json");
    let template = std::env::var("JSON").as_deref() == Ok("template");
    let (item_json, user_json) = if template {
        (
            items.iter().map(|i| without_brace(serde_json::to_vec(i).unwrap())).collect(),
            users.iter().map(|u| without_brace(serde_json::to_vec(u).unwrap())).collect(),
        )
    } else {
        (Vec::new(), Vec::new())
    };
    Data { items, users, item_json, user_json, template }
}

fn response(status: StatusCode, body: Full<Bytes>) -> Response<Full<Bytes>> {
    let mut r = Response::new(body);
    *r.status_mut() = status;
    r.headers_mut().insert(SERVER, SERVER_NAME.clone());
    r
}

fn json(body: Vec<u8>) -> Response<Full<Bytes>> {
    let mut r = response(StatusCode::OK, Full::new(Bytes::from(body)));
    r.headers_mut().insert(CONTENT_TYPE, APPLICATION_JSON.clone());
    r
}

// A record's response: its prebuilt JSON with servedAt spliced in, or the
// record and servedAt serialized.
fn served<T: Serialize>(record: &T, prebuilt: Option<&Vec<u8>>) -> Response<Full<Bytes>> {
    let now = now_s();
    let body = match prebuilt {
        Some(p) => {
            let mut b = Vec::with_capacity(p.len() + 24);
            b.extend_from_slice(p);
            b.extend_from_slice(b",\"servedAt\":");
            b.extend_from_slice(now.to_string().as_bytes());
            b.push(b'}');
            b
        }
        None => serde_json::to_vec(&Served { record, served_at: now }).unwrap(),
    };
    json(body)
}

// id as a record's index, if it's one of n.
fn index_of(id: &str, n: usize) -> Option<usize> {
    id.parse::<usize>().ok().filter(|&v| v >= 1 && v <= n).map(|v| v - 1)
}

async fn route(req: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let data = DATA.get().unwrap();
    let path = req.uri().path();
    let method = req.method().clone();
    if let Some(id) = path.strip_prefix("/api/items/") {
        let Some(i) = index_of(id, data.items.len()) else {
            let _ = req.into_body().collect().await;
            return Ok(response(StatusCode::NOT_FOUND, Full::default()));
        };
        if method == Method::GET {
            return Ok(served(&data.items[i], data.template.then(|| &data.item_json[i])));
        }
        if method == Method::POST {
            let body = req.into_body().collect().await.map(|b| b.to_bytes()).unwrap_or_default();
            let ok = body.first() == Some(&b'{') && serde_json::from_slice::<Write>(&body).is_ok();
            return Ok(response(if ok { StatusCode::NO_CONTENT } else { StatusCode::UNPROCESSABLE_ENTITY },
                               Full::default()));
        }
    } else if path == "/api/me" && method == Method::GET {
        let user = req.headers().get("x-user-id").and_then(|v| v.to_str().ok())
            .and_then(|v| index_of(v, data.users.len()));
        return Ok(match user {
            Some(i) => served(&data.users[i], data.template.then(|| &data.user_json[i])),
            None => response(StatusCode::UNAUTHORIZED, Full::default()),
        });
    }
    let _ = req.into_body().collect().await;
    Ok(response(StatusCode::NOT_FOUND, Full::default()))
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
    let http = Arc::new(http1::Builder::new());
    loop {
        let (stream, _) = listener.accept().await?;
        let http = http.clone();
        tokio::spawn(async move {
            let _ = http.serve_connection(TokioIo::new(stream), service_fn(route)).await;
        });
    }
}

fn main() -> std::io::Result<()> {
    let dir = std::env::var("REST_DATA").unwrap_or_else(|_| "build/rest".into());
    let data = DATA.get_or_init(|| load(&dir));
    let workers = std::env::var("WORKERS").ok().and_then(|v| v.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()));
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(8080);
    println!("rest-hyper: {} items, {} users, {workers} workers on port {port}, {}", data.items.len(),
             data.users.len(), if data.template { "template" } else { "serialize" });
    let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().worker_threads(workers).build()?;
    runtime.block_on(async move { tokio::spawn(serve(port)).await.unwrap() })
}
