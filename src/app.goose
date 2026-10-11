// What both builds of the server share: the command line, the settings, the
// workers, and how a loop answers requests. src/main.goose builds the epoll
// loop (src/server.goose) and src/main_uring.goose the io_uring loop
// (src/uring.goose); each loop defines serve.
import std;
import os;
import sys;
import http;
import echo;

// The server's settings. Each worker gets a copy, as thread_spawn copies
// flat values.
struct Config {
    // An IPv4 address to listen on, or empty for every address (127.0.0.1 on
    // Windows).
    address: u8[..16] = "",
    port: i32 = 8080,
    // 0 for one per hardware thread.
    workers: i64 = 0,
    backlog: i32 = 4096,
    // The most connections one worker holds. The default lets one worker take
    // TechEmpower's largest run, 16,384 connections, alone.
    max_conns: i64 = 16384,
    // The longest request head, and the size of a worker's read buffer, which
    // holds one whole.
    max_head: i64 = http::MAX_HEAD,
    max_body: i64 = http::MAX_BODY,
    // A worker's write buffer grows to hold any response whole. Past this
    // many bytes, the worker sends what it holds before it answers more: the
    // default takes the responses to a read's worth of pipelined requests, as
    // 16 TechEmpower responses are about 2 KB.
    write_buffer: i64 = 8192,
    // In milliseconds of the monotonic clock. A request has request_ms from
    // its first byte to arrive whole, and a response as long to leave once it
    // stops moving. An idle keep-alive connection closes after idle_ms. A
    // refused connection has linger_ms for the client to read the refusal and
    // close.
    request_ms: i64 = 10000,
    idle_ms: i64 = 60000,
    linger_ms: i64 = 2000,
    // The io_uring loop's ring: its submission entries, and its provided
    // buffers, which the kernel fills in turn, a power of two of them. A
    // receive that finds none left ends its multishot request, which the loop
    // queues again. The loop gives each buffer back in the pass that takes
    // it, and 256, a wait's batch, served as fast as 1,024, with half the
    // peak RSS (task 005).
    ring_entries: i32 = 4096,
    ring_buffers: i32 = 256,
    ring_buffer_size: i32 = 4096,
    // The responses an io_uring connection may have waiting behind its send
    // in flight. Past this, the loop stops reading from it until the client
    // takes what it was sent, as the epoll loop does when a send would block.
    max_queued: i64 = 65536,
}

// Why a loop stopped: the call that failed, and its error code, one of sys's.
struct Error { call: const u8[:], code: i64 }

// An address as sys::listen takes it: -1 for none, or an IPv4 address in
// host byte order. False if text isn't one.
fn ipv4(text: const u8[:]) -> i64, bool {
    guard text.len > 0 else { return -1, true; }
    let parts = split(text, '.');
    guard parts.len == 4 else { return 0, false; }
    var ip = 0;
    for p in parts {
        guard p.len > 0 && p.len <= 3 else { return 0, false; }
        var n = 0;
        for c in p {
            guard c >= '0' && c <= '9' else { return 0, false; }
            n = n * 10 + (c - '0');
        }
        guard n <= 255 else { return 0, false; }
        ip = ip * 256 + n;
    }
    return ip, true;
}

// A connection's states, in both loops.
let OPEN: u8 = 0;       // answering requests
let CLOSING: u8 = 1;    // sending what's left, then shutting down its side
let DRAINING: u8 = 2;   // shut down, and dropping what arrives until the client closes

// Answers the complete requests in rbuf[..rlen] for connection c, into wbuf,
// and moves the rest of rbuf to its front. rbuf's length is the longest head
// it takes. Before a request, if wbuf holds cfg.write_buffer bytes or more,
// it calls ROOM(), which empties wbuf and returns true, or returns false to
// stop there. Returns the bytes left in rbuf, the
// number of requests answered, and whether ROOM stopped it. A refused request
// leaves c CLOSING and rbuf empty.
fn answer<ROOM, C>(c: C&, rbuf: u8[:], rlen: i64, wbuf: u8[>..]&, date: const u8[:],
                   cfg: const Config&) -> i64, i64, bool {
    var off = 0;
    var done = 0;
    var full = false;
    while off < rlen {
        if c.discard > 0 {
            let k = min(c.discard, rlen - off);
            off += k;
            c.discard -= k;
            continue;
        }
        if wbuf.len >= cfg.write_buffer && !ROOM() {
            full = true;
            break;
        }
        let req, status = http::parse(rbuf[off..rlen], rbuf.len, cfg.max_body);
        if status == http::INCOMPLETE { break; }
        if status != 200 {
            http::refuse(wbuf, status, date);
            c.state = CLOSING;
            off = rlen;
            break;
        }
        // A body the route reads, and a chunked one, are answered once they
        // are whole in rbuf; any other body is dropped as it comes.
        let b0 = off + req.len;
        let reads = http::reads_body(req);
        let whole = req.chunked || (req.body > 0 && reads);
        var wire = 0;
        if whole {
            let n, s = http::frame_body(rbuf[b0..rlen], req, rbuf.len - req.len);
            if s == http::INCOMPLETE { break; }
            if s != 200 {
                http::refuse(wbuf, s, date);
                c.state = CLOSING;
                off = rlen;
                break;
            }
            wire = n;
        }
        let blen = if !reads { 0 }
                   else if req.chunked { http::dechunk(rbuf[b0..b0 + wire]) }
                   else { wire };
        done++;
        off = b0 + wire;
        if !whole { c.discard = req.body; }
        if !http::respond(wbuf, req, rbuf[b0..b0 + blen], date) {
            c.state = CLOSING;
            off = rlen;
            break;
        }
    }
    let rest = rlen - off;
    if rest > 0 && off > 0 { copy_into(rbuf[..rest], rbuf[off..rlen]); }
    return rest, done, full;
}

fn usage() {
    write_stderr("usage: server http|echo-blocking|echo-epoll [port]\n");
    exit(2);
}

fn run() {
    let argv = args();
    guard argv.len >= 2 else { usage(); }
    var port: i32 = 8080;
    if argv.len > 2 {
        let p, ok = parse_int(argv[2]);
        guard ok && p > 0 && p < 65536 else { usage(); }
        port = p as i32;
    }
    let mode = argv[1];
    if mode == "http" { serve_http(Config { port: port, workers: workers(), .. }); }
    else if mode == "echo-blocking" { echo_blocking(port); }
    else if mode == "echo-epoll" { echo_epoll(port); }
    else { usage(); }
}

// A worker that reports why its loop stopped, and ends the process.
thread_fn worker(cfg: Config) {
    let e = serve(cfg);
    sys::report(e.call, -e.code);
    exit(1);
}

fn serve_http(cfg: Config) {
    let n = if cfg.workers > 0 { cfg.workers } else { max(1, hardware_threads()) };
    print("http: ", n, if n == 1 { " worker" } else { " workers" }, " on port ", cfg.port);
    var ids: i64[>..] = [];
    for i in n { ids.push(thread_spawn(worker, cfg)); }
    for id in ids { thread_wait(id); }
}

// WORKERS, or 0 without it.
fn workers() -> i64 {
    var v: u8[>..] = [];
    guard env("WORKERS", v) else { return 0; }
    let n, ok = parse_int(v);
    guard ok && n > 0 else {
        write_stderr("WORKERS must be a positive number\n");
        exit(2);
    }
    return n;
}
