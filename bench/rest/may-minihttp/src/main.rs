// The REST benchmark's tiers (task 021) on may-minihttp, configured as
// bench/may-minihttp is, after TechEmpower's entry: may's coroutines on
// WORKERS threads, one listener, mimalloc, and the crate's own Server and Date
// fields. The routes are bench/rest/rust's, answering as bench/rest/hyper does.
//
// may-minihttp frames a request body by Content-Length alone: its BodyReader
// reads that many bytes from the connection as the handler takes them, and a
// chunked body's bytes are left to be parsed as the next request. So tier D
// reads a Content-Length body as it arrives, the CSV and the multipart body
// in the pieces each read gives, and answers a chunked body with 411, after
// which the connection fails to parse its chunks and is closed. Tier D is
// therefore a gap: its load sends chunked imports.
//
// The crate can't close a connection after a response. An answer that
// should close, a 413 for a declared length over the limit, says so in its
// Connection field, and leaves the body unread.
//
//     REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-may-minihttp [port]

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use std::io::{self, BufRead, Read};

use may_minihttp::{HttpService, HttpServiceFactory, Request, Response};
use rest_app::writes::{self, Start};
use rest_app::{Head, Resp};

fn head_of<'a>(req: &'a Request) -> Head<'a> {
    let mut head = Head::new(req.method().as_bytes(), req.path());
    for h in req.headers() {
        head.field(h.name.as_bytes(), h.value);
    }
    head
}

// A request's head, copied, for a body that the handler reads before it
// answers, which takes the request.
struct Owned {
    method: Vec<u8>,
    target: String,
    fields: Vec<(Vec<u8>, Vec<u8>)>,
}

impl Owned {
    fn of(req: &Request) -> Owned {
        Owned {
            method: req.method().as_bytes().to_vec(),
            target: req.path().to_owned(),
            fields: req.headers().iter().map(|h| (h.name.as_bytes().to_vec(), h.value.to_vec())).collect(),
        }
    }

    fn head(&self) -> Head<'_> {
        let mut head = Head::new(&self.method, &self.target);
        for (name, value) in &self.fields {
            head.field(name, value);
        }
        head
    }
}

fn respond(rsp: &mut Response, r: Resp) {
    rsp.status_code(r.status as usize, rest_app::reason(r.status));
    if r.json {
        rsp.header("Content-Type: application/json");
    }
    if r.close {
        rsp.header("Connection: close");
    }
    rsp.body_vec(r.body);
}

struct Rest;

impl HttpService for Rest {
    fn call(&mut self, req: Request, rsp: &mut Response) -> io::Result<()> {
        let mut length = 0;
        let mut chunked = false;
        for h in req.headers() {
            if h.name.eq_ignore_ascii_case("content-length") {
                length = std::str::from_utf8(h.value).ok().and_then(|v| v.trim().parse().ok()).unwrap_or(0);
            } else if h.name.eq_ignore_ascii_case("transfer-encoding") {
                chunked = true;
            }
        }
        if chunked {
            let mut r = Resp::empty(411);
            r.close = true;
            respond(rsp, r);
            return Ok(());
        }
        if !writes::is_writes(req.path()) {
            if length == 0 {
                respond(rsp, rest_app::handle(&head_of(&req), &[]));
                return Ok(());
            }
            let owned = Owned::of(&req);
            let mut body = Vec::with_capacity(length);
            req.body().read_to_end(&mut body)?;
            respond(rsp, rest_app::handle(&owned.head(), &body));
            return Ok(());
        }
        let start = writes::start(&head_of(&req));
        let r = match start {
            Start::Answer(r) => {
                if !r.close {
                    io::copy(&mut req.body(), &mut io::sink())?;
                }
                r
            }
            Start::Read(mut w) => {
                let mut body = req.body();
                let mut early = None;
                loop {
                    let piece = body.fill_buf()?;
                    let n = piece.len();
                    if n == 0 {
                        break;
                    }
                    early = w.push(piece);
                    body.consume(n);
                    if early.is_some() {
                        break;
                    }
                }
                // Dropping the reader reads the rest of the body.
                drop(body);
                early.unwrap_or_else(|| w.finish())
            }
        };
        respond(rsp, r);
        Ok(())
    }
}

struct Server;

impl HttpServiceFactory for Server {
    type Service = Rest;

    fn new_service(&self, _: usize) -> Rest {
        Rest
    }
}

fn main() {
    let config = rest_app::init("rest-may-minihttp");
    may::config()
        .set_workers(config.workers)
        .set_pool_capacity(1000)
        .set_stack_size(0x1000);
    Server.start(("0.0.0.0", config.port)).unwrap().join().unwrap();
}
