// What both builds of the server share: the command line, the worker count,
// and the limits a worker holds its connections to. src/main.goose builds the
// epoll loop (src/server.goose) and src/main_uring.goose the io_uring loop
// (src/uring.goose); each loop defines thread_fn worker.
import std;
import os;
import http;
import echo;

// A worker's buffers, which the connection it's driving uses. The read
// buffer holds the longest request head whole. The write buffer grows to
// hold any response whole, and past WBUF bytes the server sends what it
// holds before it answers more: WBUF takes the responses to a read's worth
// of pipelined requests, as 16 TechEmpower responses are about 2 KB.
let RBUF = http::MAX_HEAD;
let WBUF = 8192;

// The most connections one worker holds. One worker must be able to take
// TechEmpower's largest run, 16,384 connections, alone.
let MAX_CONNS = 16384;
let BACKLOG = 4096;

// In milliseconds of the monotonic clock. A request has REQUEST_MS from its
// first byte to arrive whole, and a response as long to leave once it stops
// moving. An idle keep-alive connection closes after IDLE_MS. A refused
// connection has LINGER_MS for the client to read the refusal and close.
let REQUEST_MS = 10000;
let IDLE_MS = 60000;
let LINGER_MS = 2000;

// A connection's states, in both loops.
let OPEN: u8 = 0;       // answering requests
let CLOSING: u8 = 1;    // sending what's left, then shutting down its side
let DRAINING: u8 = 2;   // shut down, and dropping what arrives until the client closes

// Answers the complete requests in rbuf[..rlen] for connection c, into wbuf,
// and moves the rest of rbuf to its front. Before a request, if wbuf holds
// WBUF bytes or more, it calls ROOM(), which empties wbuf and returns true,
// or returns false to stop there. Returns the bytes left in rbuf, the
// number of requests answered, and whether ROOM stopped it. A refused request
// leaves c CLOSING and rbuf empty.
fn answer<ROOM, C>(c: C&, rbuf: u8[:], rlen: i64, wbuf: u8[>..]&, date: const u8[:]) -> i64, i64, bool {
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
        if wbuf.len >= WBUF && !ROOM() {
            full = true;
            break;
        }
        let req, status = http::parse(rbuf[off..rlen]);
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
    if mode == "http" { serve_http(port); }
    else if mode == "echo-blocking" { echo_blocking(port); }
    else if mode == "echo-epoll" { echo_epoll(port); }
    else { usage(); }
}

fn serve_http(port: i32) {
    let n = workers();
    print("http: ", n, if n == 1 { " worker" } else { " workers" }, " on port ", port);
    var ids: i64[>..] = [];
    for i in n { ids.push(thread_spawn(worker, port)); }
    for id in ids { thread_wait(id); }
}

// WORKERS, or one worker per hardware thread.
fn workers() -> i64 {
    var v: u8[>..] = [];
    guard env("WORKERS", v) else { return max(1, hardware_threads()); }
    let n, ok = parse_int(v);
    guard ok && n > 0 else {
        write_stderr("WORKERS must be a positive number\n");
        exit(2);
    }
    return n;
}
