// The REST benchmark's tiers (task 021) on hyper 1 and Tokio's multi-threaded
// runtime, set up as bench/hyper is, answering as bench/rest/goose/rest.goose
// does from the generator's dataset files. Tier A is HttpArena's
// production-stack application layer:
//
//   GET  /api/items/:id    the item, and servedAt, the time in seconds
//   GET  /api/me           the user X-User-Id names, and servedAt
//   POST /api/items/:id    a body of name, price, and quantity, each optional:
//                          204, or 422; the data doesn't change
//
// Tier B is snowtime's k6 hot path, under /api/v1 (snow.rs), tier C a
// clinic's schedule and records, under /api/v2 (heavy.rs), and tier D writes
// with large bodies, under /api/v3 (writes.rs), served beside tier C.
//
//   REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-hyper [port]
//
// TIER picks the dataset to load, tier A's by default. JSON=template answers
// from each record's JSON, written once at startup, with the per-request
// values added; the default serializes each response with serde_json, the
// library Rust servers use. Tier D's answers are written the one way.

mod heavy;
mod snow;
mod writes;

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
use serde::{Deserialize, Deserializer, Serialize, Serializer};
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
    snow: snow::Snow,
    heavy: heavy::Heavy,
    template: bool,
}

static DATA: OnceLock<Data> = OnceLock::new();

type Resp = Response<Full<Bytes>>;

const DAY: i64 = 86_400_000;
const MINUTE: i64 = 60_000;

// The time in seconds, which a coarse clock gives as cheaply.
fn now_s() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

fn without_brace(mut v: Vec<u8>) -> Vec<u8> {
    v.pop();
    v
}

fn read_file(dir: &str, name: &str) -> Vec<u8> {
    std::fs::read(format!("{dir}/{name}")).unwrap_or_else(|e| panic!("{dir}/{name}: {e}; run bench/rest/gen.goose"))
}

fn load(dir: &str, tier: &str, template: bool) -> Data {
    let mut data = Data {
        items: Vec::new(),
        users: Vec::new(),
        item_json: Vec::new(),
        user_json: Vec::new(),
        snow: snow::Snow::default(),
        heavy: heavy::Heavy::default(),
        template,
    };
    match tier {
        "a" => {
            data.items = serde_json::from_slice(&read_file(dir, "arena-items.json")).expect("arena-items.json");
            data.users = serde_json::from_slice(&read_file(dir, "arena-users.json")).expect("arena-users.json");
            if template {
                data.item_json = data.items.iter().map(|i| without_brace(serde_json::to_vec(i).unwrap())).collect();
                data.user_json = data.users.iter().map(|u| without_brace(serde_json::to_vec(u).unwrap())).collect();
            }
        }
        "b" => data.snow = snow::Snow::load(dir, template),
        "c" | "d" => data.heavy = heavy::Heavy::load(dir, template),
        _ => panic!("TIER is a, b, c, or d"),
    }
    data
}

fn response(status: StatusCode, body: Full<Bytes>) -> Resp {
    let mut r = Response::new(body);
    *r.status_mut() = status;
    r.headers_mut().insert(SERVER, SERVER_NAME.clone());
    r
}

fn json_status(status: StatusCode, body: impl Into<Bytes>) -> Resp {
    let mut r = response(status, Full::new(body.into()));
    r.headers_mut().insert(CONTENT_TYPE, APPLICATION_JSON.clone());
    r
}

fn json(body: Vec<u8>) -> Resp {
    json_status(StatusCode::OK, body)
}

// A record's response: its prebuilt JSON with servedAt spliced in, or the
// record and servedAt serialized.
fn served<T: Serialize>(record: &T, prebuilt: Option<&Vec<u8>>) -> Resp {
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

// Whether path, split at '/', matches pattern's segments, a ":name" one taking
// any segment but an empty one, into params in order.
fn matches<'a>(path: &'a str, pattern: &str, params: &mut [&'a str; 2]) -> bool {
    let mut n = 0;
    let mut segs = path.split('/');
    let mut lits = pattern.split('/');
    loop {
        match (lits.next(), segs.next()) {
            (None, None) => return true,
            (Some(lit), Some(seg)) => {
                if lit.starts_with(':') {
                    if seg.is_empty() {
                        return false;
                    }
                    params[n] = seg;
                    n += 1;
                } else if lit != seg {
                    return false;
                }
            }
            _ => return false,
        }
    }
}

// The value of key in the query, as sent; the first, if it repeats. A key
// without '=' has an empty value.
fn query_of<'a>(query: Option<&'a str>, key: &str) -> Option<&'a str> {
    query?.split('&').find_map(|pair| {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        (!pair.is_empty() && k == key).then_some(v)
    })
}

// s with its percent-escapes decoded, or None for a '%' without two hex
// digits after it.
fn decode(s: &str) -> Option<Vec<u8>> {
    let s = s.as_bytes();
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        if s[i] == b'%' {
            let hex = |c: u8| (c as char).to_digit(16);
            let (Some(a), Some(b)) = (s.get(i + 1).and_then(|&c| hex(c)), s.get(i + 2).and_then(|&c| hex(c))) else {
                return None;
            };
            out.push((a * 16 + b) as u8);
            i += 3;
        } else {
            out.push(s[i]);
            i += 1;
        }
    }
    Some(out)
}

// A form's key or value decoded: '+' as a space, and percent-escapes, or None
// for a '%' without two hex digits after it.
fn decode_form(s: &[u8]) -> Option<Vec<u8>> {
    let hex = |c: u8| (c as char).to_digit(16);
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        match s[i] {
            b'%' => {
                let (Some(a), Some(b)) = (s.get(i + 1).and_then(|&c| hex(c)), s.get(i + 2).and_then(|&c| hex(c)))
                else {
                    return None;
                };
                out.push((a * 16 + b) as u8);
                i += 3;
            }
            c => {
                out.push(if c == b'+' { b' ' } else { c });
                i += 1;
            }
        }
    }
    Some(out)
}

fn parse_int(s: &[u8]) -> Option<i64> {
    std::str::from_utf8(s).ok()?.parse().ok()
}

// Whether body's JSON value, if any, is an object, which a struct's
// Deserialize would otherwise take from an array too.
fn is_object(body: &[u8]) -> bool {
    body.trim_ascii_start().first() == Some(&b'{')
}

fn is_json(body: &[u8]) -> bool {
    serde_json::from_slice::<serde::de::IgnoredAny>(body).is_ok()
}

// A present member that must be a string: null is refused, where an Option
// would take it for absent.
fn de_string<'de, D: Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    String::deserialize(d).map(Some)
}

// ms since the epoch as JavaScript's toISOString writes it, from Howard
// Hinnant's civil_from_days.
struct Iso([u8; 24]);

impl Iso {
    fn new(ms: i64) -> Iso {
        fn digits(b: &mut [u8], v: i64) {
            let mut v = v;
            for c in b.iter_mut().rev() {
                *c = b'0' + (v % 10) as u8;
                v /= 10;
            }
        }
        let day = ms.div_euclid(DAY);
        let t = ms.rem_euclid(DAY);
        let z = day + 719_468;
        let era = (if z >= 0 { z } else { z - 146_096 }) / 146_097;
        let doe = z - era * 146_097;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let m = if mp < 10 { mp + 3 } else { mp - 9 };
        let mut b = *b"0000-00-00T00:00:00.000Z";
        digits(&mut b[0..4], yoe + era * 400 + i64::from(m <= 2));
        digits(&mut b[5..7], m);
        digits(&mut b[8..10], doy - (153 * mp + 2) / 5 + 1);
        digits(&mut b[11..13], t / 3_600_000);
        digits(&mut b[14..16], t / MINUTE % 60);
        digits(&mut b[17..19], t / 1000 % 60);
        digits(&mut b[20..23], t % 1000);
        Iso(b)
    }

    fn as_str(&self) -> &str {
        std::str::from_utf8(&self.0).unwrap()
    }
}

fn iso<S: Serializer>(ms: &i64, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_str(Iso::new(*ms).as_str())
}

fn iso_or_null<S: Serializer>(ms: &Option<i64>, s: S) -> Result<S::Ok, S::Error> {
    match ms {
        Some(v) => iso(v, s),
        None => s.serialize_none(),
    }
}

// A time as a JSON string, for a template's splice.
fn push_iso(out: &mut Vec<u8>, ms: i64) {
    out.push(b'"');
    out.extend_from_slice(&Iso::new(ms).0);
    out.push(b'"');
}

fn number_at(s: &[u8], at: usize, n: usize) -> i64 {
    let mut v = 0;
    for &c in &s[at..at + n] {
        if !c.is_ascii_digit() {
            return -1;
        }
        v = v * 10 + i64::from(c - b'0');
    }
    v
}

// Howard Hinnant's days_from_civil.
fn days_from(y: i64, m: i64, d: i64) -> i64 {
    let yy = if m <= 2 { y - 1 } else { y };
    let era = (if yy >= 0 { yy } else { yy - 399 }) / 400;
    let yoe = yy - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
}

// "YYYY-MM-DDTHH:MM:SS.sssZ", or without the milliseconds, as ms since the
// epoch.
fn parse_iso(s: &[u8]) -> Option<i64> {
    let n = s.len();
    if !((n == 24 || n == 20) && s[4] == b'-' && s[7] == b'-' && s[10] == b'T' && s[13] == b':' && s[16] == b':'
        && s[n - 1] == b'Z')
    {
        return None;
    }
    let (y, m, d) = (number_at(s, 0, 4), number_at(s, 5, 2), number_at(s, 8, 2));
    let (h, mi, sec) = (number_at(s, 11, 2), number_at(s, 14, 2), number_at(s, 17, 2));
    let ms = if n == 24 && s[19] == b'.' { number_at(s, 20, 3) } else if n == 20 { 0 } else { -1 };
    let ok = y >= 0 && (1..=12).contains(&m) && (1..=31).contains(&d) && (0..24).contains(&h)
        && (0..60).contains(&mi) && (0..60).contains(&sec) && ms >= 0;
    ok.then(|| days_from(y, m, d) * DAY + ((h * 60 + mi) * 60 + sec) * 1000 + ms)
}

// "YYYY-MM-DD" as ms since the epoch at its midnight in UTC.
fn parse_day(s: &[u8]) -> Option<i64> {
    if !(s.len() == 10 && s[4] == b'-' && s[7] == b'-') {
        return None;
    }
    let (y, m, d) = (number_at(s, 0, 4), number_at(s, 5, 2), number_at(s, 8, 2));
    (y >= 0 && (1..=12).contains(&m) && (1..=31).contains(&d)).then(|| days_from(y, m, d) * DAY)
}

fn de_iso<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    parse_iso(String::deserialize(d)?.as_bytes()).ok_or_else(|| serde::de::Error::custom("a time that isn't toISOString's"))
}

fn de_iso_or_null<'de, D: Deserializer<'de>>(d: D) -> Result<Option<i64>, D::Error> {
    match Option::<String>::deserialize(d)? {
        None => Ok(None),
        Some(s) => parse_iso(s.as_bytes()).map(Some)
            .ok_or_else(|| serde::de::Error::custom("a time that isn't toISOString's")),
    }
}

// A JSON array of what F makes of each of a slice's elements, serialized
// without collecting them first.
struct SeqOf<'a, T, F>(&'a [T], F);

// The bound gives the closure its signature, so that what it makes may borrow
// the element.
fn seq_of<'a, T, F, O>(items: &'a [T], f: F) -> SeqOf<'a, T, F>
where
    F: Fn(&'a T) -> O,
    O: Serialize,
{
    SeqOf(items, f)
}

impl<'a, T, F, O> Serialize for SeqOf<'a, T, F>
where
    F: Fn(&'a T) -> O,
    O: Serialize,
{
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_seq(self.0.iter().map(&self.1))
    }
}

// Prebuilt records joined with ',' between "[" and "]", or other ends.
fn join<'a>(out: &mut Vec<u8>, open: &[u8], parts: impl Iterator<Item = &'a [u8]>, close: &[u8]) {
    out.extend_from_slice(open);
    for (k, p) in parts.enumerate() {
        if k > 0 {
            out.push(b',');
        }
        out.extend_from_slice(p);
    }
    out.extend_from_slice(close);
}

async fn route(req: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let data = DATA.get().unwrap();
    let path = req.uri().path();
    let method = req.method().clone();
    if path.starts_with("/api/v3/") {
        return Ok(writes::handle(req).await);
    }
    if path.starts_with("/api/v1/") || path.starts_with("/api/v2/") {
        let (parts, body) = req.into_parts();
        let body = body.collect().await.map(|b| b.to_bytes()).unwrap_or_default();
        let (path, query) = (parts.uri.path(), parts.uri.query());
        return Ok(if path.starts_with("/api/v1/") {
            data.snow.handle(data.template, &parts.method, path, query, &parts.headers, &body)
        } else {
            data.heavy.handle(data.template, &parts.method, path, query, &parts.headers)
        });
    }
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
    let tier = std::env::var("TIER").unwrap_or_else(|_| "a".into());
    let template = std::env::var("JSON").as_deref() == Ok("template");
    let data = DATA.get_or_init(|| load(&dir, &tier, template));
    let workers = std::env::var("WORKERS").ok().and_then(|v| v.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()));
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(8080);
    let records = data.items.len() + data.snow.records() + data.heavy.records();
    println!("rest-hyper: tier {tier}, {records} records, {workers} workers on port {port}, {}",
             if data.template { "template" } else { "serialize" });
    let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().worker_threads(workers).build()?;
    runtime.block_on(async move { tokio::spawn(serve(port)).await.unwrap() })
}
