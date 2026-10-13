// The REST benchmark's tiers (task 021) on bench/tokio, HttpArena's tokio
// entry: its hand-written HTTP/1.1 parser on raw tokio, one current-thread
// runtime per worker, each with its own SO_REUSEPORT listener, and its read
// loop, which answers every request buffered before it writes them all. The
// routes are bench/rest/rust's, answering as bench/rest/hyper does.
//
// The entry waits for a request's whole body before it answers, so tier D's
// bodies are read whole here too: the CSV and the multipart body are given to
// their readers in one piece. What the tiers need on top of the entry:
//
// - The entry closes a connection whose buffer passes 1 MB. Tier D's bodies
//   reach 16 MB, so the buffer may hold one, and a chunked body is walked
//   chunk by chunk to its end before it's copied out once, where the entry
//   copied the whole body again on each read.
// - A body over its route's limit is refused with 413 as soon as its declared
//   length or the chunks read so far show it, and the connection closed.
// - A target that isn't UTF-8 gets 400, and the connection is closed.
//
//     REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-tokio [port]

use rest_app::writes::{self, Start};
use rest_app::{Head, Method, Resp};
use socket2::{Domain, Protocol, Socket, Type};
use std::cell::RefCell;
use std::net::SocketAddr;
use std::time::{Duration, SystemTime};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const READ_SIZE: usize = 16 * 1024;
// A 16 MB body, its chunks' framing, and its head.
const MAX_BUF: usize = 17 << 20;

thread_local! {
    static DATE: RefCell<[u8; 29]> = RefCell::new(http_date());
}

fn http_date() -> [u8; 29] {
    let mut d = [0u8; 29];
    d.copy_from_slice(httpdate::fmt_http_date(SystemTime::now()).as_bytes());
    d
}

fn main() {
    let config = rest_app::init("rest-tokio");
    let port = config.port;
    let mut handles = Vec::with_capacity(config.workers);
    for _ in 0..config.workers {
        handles.push(std::thread::spawn(move || {
            tokio::runtime::Builder::new_current_thread()
                .enable_io()
                .enable_time()
                .build()
                .expect("runtime")
                .block_on(serve(port));
        }));
    }
    for h in handles {
        let _ = h.join();
    }
}

async fn serve(port: u16) {
    tokio::spawn(async {
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        loop {
            tick.tick().await;
            DATE.with(|d| *d.borrow_mut() = http_date());
        }
    });
    let listener = bind_reuseport(port);
    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                tokio::spawn(handle(stream));
            }
            Err(_) => continue,
        }
    }
}

fn bind_reuseport(port: u16) -> TcpListener {
    let addr: SocketAddr = format!("0.0.0.0:{port}").parse().unwrap();
    let socket = Socket::new(Domain::IPV4, Type::STREAM, Some(Protocol::TCP)).unwrap();
    socket.set_reuse_address(true).unwrap();
    socket.set_reuse_port(true).unwrap();
    socket.set_nonblocking(true).unwrap();
    socket.bind(&addr.into()).unwrap();
    socket.listen(1024).unwrap();
    TcpListener::from_std(socket.into()).unwrap()
}

async fn handle(mut stream: TcpStream) {
    let _ = stream.set_nodelay(true);
    let mut buf: Vec<u8> = Vec::with_capacity(READ_SIZE);
    let mut out: Vec<u8> = Vec::with_capacity(READ_SIZE);
    let mut tmp = [0u8; READ_SIZE];

    loop {
        // Drain every complete request currently buffered, batching responses.
        let mut pos = 0;
        let mut keep = true;
        loop {
            match process(&buf[pos..], &mut out) {
                Outcome::Incomplete => break,
                Outcome::Complete { consumed, keep_alive } => {
                    pos += consumed;
                    if !keep_alive {
                        keep = false;
                        break;
                    }
                }
            }
        }
        if pos > 0 {
            buf.drain(..pos);
        }
        if !out.is_empty() {
            if stream.write_all(&out).await.is_err() {
                return;
            }
            out.clear();
        }
        if !keep || buf.len() > MAX_BUF {
            return;
        }
        let n = match stream.read(&mut tmp).await {
            Ok(0) | Err(_) => return,
            Ok(n) => n,
        };
        buf.extend_from_slice(&tmp[..n]);
    }
}

// ── Hand-rolled HTTP/1.1 ─────────────────────────────────────────────────────

enum Outcome {
    Incomplete,
    Complete { consumed: usize, keep_alive: bool },
}

/// Parse one request from buf; append its response to out. Returns Incomplete if
/// the request isn't fully buffered yet.
fn process(buf: &[u8], out: &mut Vec<u8>) -> Outcome {
    let he = match find(buf, b"\r\n\r\n") {
        Some(h) => h,
        None => return Outcome::Incomplete,
    };

    let mut lines = lines_crlf(&buf[..he]);
    let req_line = lines.next().unwrap_or(b"");
    let mut rl = req_line.split(|&c| c == b' ');
    let method = rl.next().unwrap_or(b"");
    let Ok(target) = std::str::from_utf8(rl.next().unwrap_or(b"")) else {
        respond(out, Method::Get, &bad_request());
        return Outcome::Complete { consumed: buf.len(), keep_alive: false };
    };
    let mut head = Head::new(method, target);

    let mut content_length: Option<usize> = None;
    let mut chunked = false;
    let mut close = false;
    for line in lines {
        if let Some(c) = find(line, b":") {
            let name = &line[..c];
            let val = trim(&line[c + 1..]);
            head.field(name, val);
            if ci_eq(name, b"content-length") {
                content_length = parse_usize(val);
            } else if ci_eq(name, b"transfer-encoding") && ci_contains(val, b"chunked") {
                chunked = true;
            } else if ci_eq(name, b"connection") && ci_eq(val, b"close") {
                close = true;
            }
        }
    }

    let is_writes = writes::is_writes(head.path);
    let body_start = he + 4;
    let decoded;
    let (body, consumed): (&[u8], usize) = if chunked {
        match walk_chunked(&buf[body_start..]) {
            Chunks::Done { size, used } => {
                decoded = copy_chunked(&buf[body_start..body_start + used], size);
                (&decoded, body_start + used)
            }
            Chunks::More { size } => return refuse_early(out, &head, is_writes, size),
        }
    } else if let Some(cl) = content_length {
        if buf.len() < body_start + cl {
            return refuse_early(out, &head, is_writes, buf.len() - body_start);
        }
        (&buf[body_start..body_start + cl], body_start + cl)
    } else {
        (&[][..], body_start)
    };

    let resp = if is_writes {
        match writes::start(&head) {
            Start::Answer(r) => r,
            Start::Read(mut w) => match w.push(body) {
                Some(r) => r,
                None => w.finish(),
            },
        }
    } else {
        rest_app::handle(&head, body)
    };
    respond(out, head.method, &resp);
    Outcome::Complete { consumed, keep_alive: !close && !resp.close }
}

// 413, before the rest of a body over its route's limit arrives, and the
// connection closed; or Incomplete, to wait for the rest.
fn refuse_early(out: &mut Vec<u8>, head: &Head, is_writes: bool, taken: usize) -> Outcome {
    if !is_writes {
        return Outcome::Incomplete;
    }
    match writes::over_limit(head, taken) {
        Some(r) => {
            respond(out, head.method, &r);
            Outcome::Complete { consumed: 0, keep_alive: false }
        }
        None => Outcome::Incomplete,
    }
}

fn bad_request() -> Resp {
    let mut r = Resp::empty(400);
    r.close = true;
    r
}

fn respond(out: &mut Vec<u8>, method: Method, r: &Resp) {
    out.extend_from_slice(b"HTTP/1.1 ");
    out.extend_from_slice(r.status.to_string().as_bytes());
    out.push(b' ');
    out.extend_from_slice(rest_app::reason(r.status).as_bytes());
    out.extend_from_slice(b"\r\nServer: tokio\r\nDate: ");
    DATE.with(|d| out.extend_from_slice(&*d.borrow()));
    out.extend_from_slice(b"\r\n");
    if r.json {
        out.extend_from_slice(b"Content-Type: application/json\r\n");
    }
    if r.close {
        out.extend_from_slice(b"Connection: close\r\n");
    }
    if r.status != 204 {
        out.extend_from_slice(b"Content-Length: ");
        out.extend_from_slice(r.body.len().to_string().as_bytes());
        out.extend_from_slice(b"\r\n");
    }
    out.extend_from_slice(b"\r\n");
    if method != Method::Head {
        out.extend_from_slice(&r.body);
    }
}

enum Chunks {
    /// The last chunk is in: the data's size, and the bytes the body takes.
    Done { size: usize, used: usize },
    /// The data's size so far.
    More { size: usize },
}

/// Walks a chunked body's chunk heads, stepping over their data. A malformed
/// one waits, as the entry's decode_chunked does.
fn walk_chunked(buf: &[u8]) -> Chunks {
    let mut size = 0;
    let mut pos = 0;
    loop {
        let Some(nl) = find(&buf[pos..], b"\r\n") else { return Chunks::More { size } };
        let Some(n) = parse_hex(&buf[pos..pos + nl]) else { return Chunks::More { size } };
        pos += nl + 2;
        if n == 0 {
            // final CRLF (no trailers)
            return match find(&buf[pos..], b"\r\n") {
                Some(end) => Chunks::Done { size, used: pos + end + 2 },
                None => Chunks::More { size },
            };
        }
        if buf.len() < pos + n + 2 || &buf[pos + n..pos + n + 2] != b"\r\n" {
            return Chunks::More { size: size + (buf.len() - pos).min(n) };
        }
        size += n;
        pos += n + 2;
    }
}

/// The data of a whole chunked body that walk_chunked found to be size bytes.
fn copy_chunked(buf: &[u8], size: usize) -> Vec<u8> {
    let mut body = Vec::with_capacity(size);
    let mut pos = 0;
    loop {
        let nl = find(&buf[pos..], b"\r\n").unwrap();
        let n = parse_hex(&buf[pos..pos + nl]).unwrap();
        pos += nl + 2;
        if n == 0 {
            return body;
        }
        body.extend_from_slice(&buf[pos..pos + n]);
        pos += n + 2;
    }
}

// ── byte helpers ─────────────────────────────────────────────────────────────

fn find(h: &[u8], n: &[u8]) -> Option<usize> {
    if n.is_empty() || h.len() < n.len() {
        return None;
    }
    h.windows(n.len()).position(|w| w == n)
}

fn lines_crlf(b: &[u8]) -> impl Iterator<Item = &[u8]> {
    b.split(|&c| c == b'\n').map(|l| {
        if l.last() == Some(&b'\r') {
            &l[..l.len() - 1]
        } else {
            l
        }
    })
}

fn trim(mut b: &[u8]) -> &[u8] {
    while matches!(b.first(), Some(b' ') | Some(b'\t')) {
        b = &b[1..];
    }
    while matches!(b.last(), Some(b' ') | Some(b'\t')) {
        b = &b[..b.len() - 1];
    }
    b
}

fn ci_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.eq_ignore_ascii_case(y))
}

fn ci_contains(h: &[u8], n: &[u8]) -> bool {
    !n.is_empty() && h.len() >= n.len() && h.windows(n.len()).any(|w| ci_eq(w, n))
}

fn parse_usize(b: &[u8]) -> Option<usize> {
    let b = trim(b);
    if b.is_empty() || !b.iter().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let mut n = 0usize;
    for &c in b {
        n = n.checked_mul(10)?.checked_add((c - b'0') as usize)?;
    }
    Some(n)
}

fn parse_hex(b: &[u8]) -> Option<usize> {
    let mut n = 0usize;
    let mut any = false;
    for &c in b {
        let d = match c {
            b'0'..=b'9' => c - b'0',
            b'a'..=b'f' => c - b'a' + 10,
            b'A'..=b'F' => c - b'A' + 10,
            b';' | b' ' => break, // chunk extensions / padding
            _ => return if any { Some(n) } else { None },
        };
        n = n.checked_mul(16)?.checked_add(d as usize)?;
        any = true;
    }
    if any {
        Some(n)
    } else {
        None
    }
}
