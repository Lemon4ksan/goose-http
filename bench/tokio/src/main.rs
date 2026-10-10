// HttpArena's tokio entry (MDA2AV/HttpArena frameworks/tokio/src/main.rs, MIT,
// at the commit in bench/build.sh): a hand-rolled HTTP/1.1 parser on raw tokio,
// one current-thread runtime per worker, each with its own SO_REUSEPORT
// listener. Its parser, read loop, and response batching are unchanged. What
// this repository's benchmark needs on top:
//
// - /plaintext and /json, with the Server and Date fields TechEmpower requires,
//   which the entry doesn't send; 405 for other methods on them, and 404 for
//   paths the entry doesn't serve, where it answered every one as /baseline11.
// - Each runtime refreshes a cached Date once a second from a timer task.
// - WORKERS sets the runtime count and the first argument the port, where the
//   entry takes the CPU count and PORT.
//
//     WORKERS=n bench-tokio [port]

use serde::Serialize;
use socket2::{Domain, Protocol, Socket, Type};
use std::cell::RefCell;
use std::net::SocketAddr;
use std::time::{Duration, SystemTime};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const READ_SIZE: usize = 16 * 1024;
const MAX_BUF: usize = 1 << 20;

thread_local! {
    static DATE: RefCell<[u8; 29]> = RefCell::new(http_date());
}

fn http_date() -> [u8; 29] {
    let mut d = [0u8; 29];
    d.copy_from_slice(httpdate::fmt_http_date(SystemTime::now()).as_bytes());
    d
}

fn main() {
    let threads = std::env::var("WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()));
    let port: u16 = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(8080);
    println!("tokio: {threads} workers on port {port}");
    let mut handles = Vec::with_capacity(threads);
    for _ in 0..threads {
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
        let mut delay_ms: u64 = 0;
        loop {
            match process(&buf[pos..], &mut out) {
                Outcome::Incomplete => break,
                Outcome::Complete { consumed, keep_alive, delay } => {
                    pos += consumed;
                    // Summed, not maxed: pipelined requests are answered in
                    // order, so a batch of them finishes when the last one's
                    // wait is over. The async profile never pipelines, where
                    // the sum is just the single request's own delay.
                    delay_ms += delay;
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
        // The wait, and the whole point of the async profile: the task parks on
        // a timer and the worker thread goes back to the scheduler to drive
        // every other connection it owns. Nothing is held but this task's state.
        if delay_ms > 0 {
            tokio::time::sleep(Duration::from_millis(delay_ms)).await;
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
    /// `delay` is milliseconds the response must not be sent before. Parsing is
    /// synchronous, the waiting is not, so it is handed back to handle().
    Complete { consumed: usize, keep_alive: bool, delay: u64 },
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
    let target = rl.next().unwrap_or(b"");

    let mut content_length: Option<usize> = None;
    let mut chunked = false;
    let mut close = false;
    for line in lines {
        if let Some(c) = find(line, b":") {
            let name = &line[..c];
            let val = trim(&line[c + 1..]);
            if ci_eq(name, b"content-length") {
                content_length = parse_usize(val);
            } else if ci_eq(name, b"transfer-encoding") && ci_contains(val, b"chunked") {
                chunked = true;
            } else if ci_eq(name, b"connection") && ci_eq(val, b"close") {
                close = true;
            }
        }
    }

    let body_start = he + 4;
    let (body_int, consumed) = if chunked {
        match decode_chunked(&buf[body_start..]) {
            Some((body, used)) => (parse_i64(&body), body_start + used),
            None => return Outcome::Incomplete,
        }
    } else if let Some(cl) = content_length {
        if buf.len() < body_start + cl {
            return Outcome::Incomplete;
        }
        (parse_i64(&buf[body_start..body_start + cl]), body_start + cl)
    } else {
        (0, body_start)
    };

    let delay = respond(out, method, target, body_int);
    Outcome::Complete { consumed, keep_alive: !close, delay }
}

#[derive(Serialize)]
struct Message {
    message: &'static str,
}

/// Writes the response and returns how long it must be held back, in ms.
fn respond(out: &mut Vec<u8>, method: &[u8], target: &[u8], body_int: i64) -> u64 {
    const DELAY: &[u8] = b"/delay/";
    let q = find(target, b"?");
    let path = match q {
        Some(i) => &target[..i],
        None => target,
    };
    if path == b"/plaintext" || path == b"/json" {
        let head = method == b"HEAD";
        if method != b"GET" && !head {
            write_tfb(out, b"405 Method Not Allowed", b"Allow: GET, HEAD\r\n", b"", false);
        } else if path == b"/plaintext" {
            write_tfb(out, b"200 OK", b"Content-Type: text/plain\r\n", b"Hello, World!", head);
        } else {
            let body = serde_json::to_vec(&Message { message: "Hello, World!" }).unwrap();
            write_tfb(out, b"200 OK", b"Content-Type: application/json\r\n", &body, head);
        }
        0
    } else if path == b"/pipeline" {
        write_resp(out, b"ok");
        0
    } else if path.len() > DELAY.len() && &path[..DELAY.len()] == DELAY {
        // The delay is echoed back so the parameter can be checked from the
        // response, and it is a local -- there is no per-server or
        // per-connection slot for two overlapping requests to share.
        let ms = parse_i64(&path[DELAY.len()..]).max(0) as u64;
        write_resp(out, ms.to_string().as_bytes());
        ms
    } else if path == b"/baseline11" {
        let query = match q {
            Some(i) => &target[i + 1..],
            None => &[][..],
        };
        let (a, b) = parse_ab(query);
        let s = (a + b + body_int).to_string();
        write_resp(out, s.as_bytes());
        0
    } else {
        write_tfb(out, b"404 Not Found", b"", b"", false);
        0
    }
}

fn write_resp(out: &mut Vec<u8>, body: &[u8]) {
    out.extend_from_slice(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ");
    out.extend_from_slice(body.len().to_string().as_bytes());
    out.extend_from_slice(b"\r\n\r\n");
    out.extend_from_slice(body);
}

/// A response with TechEmpower's fields. `fields` ends in CRLF.
fn write_tfb(out: &mut Vec<u8>, status: &[u8], fields: &[u8], body: &[u8], head: bool) {
    out.extend_from_slice(b"HTTP/1.1 ");
    out.extend_from_slice(status);
    out.extend_from_slice(b"\r\nServer: tokio\r\nDate: ");
    DATE.with(|d| out.extend_from_slice(&*d.borrow()));
    out.extend_from_slice(b"\r\n");
    out.extend_from_slice(fields);
    out.extend_from_slice(b"Content-Length: ");
    out.extend_from_slice(body.len().to_string().as_bytes());
    out.extend_from_slice(b"\r\n\r\n");
    if !head {
        out.extend_from_slice(body);
    }
}

fn parse_ab(query: &[u8]) -> (i64, i64) {
    let (mut a, mut b) = (0i64, 0i64);
    for kv in query.split(|&c| c == b'&') {
        if let Some(eq) = find(kv, b"=") {
            let (k, v) = (&kv[..eq], &kv[eq + 1..]);
            if k == b"a" {
                a = parse_i64(v);
            } else if k == b"b" {
                b = parse_i64(v);
            }
        }
    }
    (a, b)
}

/// Decode a chunked body. Returns (decoded_bytes, bytes_consumed) or None if the
/// terminating 0-chunk isn't fully buffered yet.
fn decode_chunked(buf: &[u8]) -> Option<(Vec<u8>, usize)> {
    let mut body = Vec::new();
    let mut pos = 0;
    loop {
        let nl = find(&buf[pos..], b"\r\n")?;
        let size = parse_hex(&buf[pos..pos + nl])?;
        pos += nl + 2;
        if size == 0 {
            let end = find(&buf[pos..], b"\r\n")?; // final CRLF (no trailers)
            return Some((body, pos + end + 2));
        }
        if buf.len() < pos + size + 2 {
            return None;
        }
        body.extend_from_slice(&buf[pos..pos + size]);
        pos += size;
        if &buf[pos..pos + 2] != b"\r\n" {
            return None;
        }
        pos += 2;
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

fn parse_i64(b: &[u8]) -> i64 {
    let b = trim(b);
    let (neg, b) = match b.first() {
        Some(b'-') => (true, &b[1..]),
        _ => (false, b),
    };
    let mut n = 0i64;
    for &c in b {
        if c.is_ascii_digit() {
            n = n * 10 + (c - b'0') as i64;
        } else {
            break;
        }
    }
    if neg {
        -n
    } else {
        n
    }
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
