// goose-http: an HTTP/1.1 server for Goose programs, with an event loop per
// worker and nothing shared between workers. A program calls one of two
// loops from a thread_fn of its own, with its handler:
//
//   http::serve(cfg) { req, body, out => ... }        io_uring on Linux, IOCP on Windows,
//                                                      emulated over kqueue on macOS
//   http::serve_epoll(cfg) { req, body, out => ... }  epoll on Linux, kqueue on macOS
//
// The handler gets the parsed request (Request, message.goose), its body, and
// a Reply to write one whole response into. Goose compiles a generic function
// only where it's called, so the loop a program doesn't call isn't in it.
namespace http;

import std;
import os;
import message;
import sys;
import ring;
import epoll;
import uring;

// The server's settings. Each worker gets a copy, as thread_spawn copies
// flat values.
struct Config {
    // An IPv4 address to listen on, or empty for every address (127.0.0.1 on
    // Windows).
    address: u8[..16] = "",
    port: i32 = 8080,
    // 0 for one per hardware thread, or on macOS one per performance core
    // (worker_count).
    workers: i64 = 0,
    backlog: i32 = 4096,
    // The most connections one worker holds. The default lets one worker take
    // TechEmpower's largest run, 16,384 connections, alone.
    max_conns: i64 = 16384,
    // The longest request head, and the size of a worker's read buffer, which
    // holds one whole. A body that fits in it with its head goes to the
    // handler; a longer one is dropped as it arrives.
    max_head: i64 = MAX_HEAD,
    max_body: i64 = MAX_BODY,
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
    // serve's ring: its submission entries, and its provided buffers, which
    // the kernel fills in turn, a power of two of them. A receive that finds
    // none left ends its multishot request, which the loop queues again. The
    // loop gives each buffer back in the pass that takes it, and 256, a
    // wait's batch, served as fast as 1,024, with half the peak RSS (task
    // 005).
    ring_entries: i32 = 4096,
    ring_buffers: i32 = 256,
    ring_buffer_size: i32 = 4096,
    // On Linux, serve's ring is the emulation over epoll it falls back to
    // where io_uring_setup fails, as in Docker's default seccomp profile: for
    // testing that fallback.
    emulate_ring: bool = false,
    // The responses a serve connection may have waiting behind its send in
    // flight. Past this, the loop stops reading from it until the client
    // takes what it was sent, as serve_epoll does when a send would block.
    max_queued: i64 = 65536,
}

// Why a loop stopped: the call that failed, and its error code, one of
// sys.goose's. report writes it to stderr.
struct Error { call: const u8[:], code: i64 }

// The number of workers cfg asks for. A program spawns them itself, each a
// thread_fn that calls a loop: thread_spawn can't take a thread_fn passed to
// a generic function (docs/goose-findings.md).
//
//   for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
fn worker_count(cfg: Config) -> i64 {
    guard cfg.workers <= 0 else { return cfg.workers; }
    let n = net_default_workers();
    return if n > 0 { n } else { max(1, hardware_threads()) };
}

// An address as net_listen takes it: -1 for none, or an IPv4 address in host
// byte order. False if text isn't one.
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

// Answers the complete requests in rbuf[..rlen] for connection c with the
// handler H, into wbuf, and moves the rest of rbuf to its front. rbuf's
// length is the longest head it takes. Before a request, if wbuf holds
// cfg.write_buffer bytes or more, it calls ROOM(), which empties wbuf and
// returns true, or returns false to stop there. Returns the bytes left in
// rbuf, the number of requests answered, and whether ROOM stopped it. A
// refused request, or a response that doesn't keep the connection open,
// leaves c CLOSING and rbuf empty.
fn answer<H, ROOM, C>(c: C&, rbuf: u8[:], rlen: i64, wbuf: u8[>..]&, date: const u8[:],
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
        let req, status = parse(rbuf[off..rlen], rbuf.len, cfg.max_body);
        if status == INCOMPLETE { break; }
        if status != 200 {
            refuse(wbuf, status, date);
            c.state = CLOSING;
            off = rlen;
            break;
        }
        // A body that fits in rbuf with its head is answered once it's whole,
        // and so is a chunked one, which must fit. A longer Content-Length
        // body is dropped as it comes, and answered as an empty one.
        let b0 = off + req.len;
        let room = rbuf.len - req.len;
        let whole = req.chunked || (req.body > 0 && req.body <= room);
        var wire = 0;
        if whole {
            let n, s = frame_body(rbuf[b0..rlen], req, room);
            if s == INCOMPLETE { break; }
            if s != 200 {
                refuse(wbuf, s, date);
                c.state = CLOSING;
                off = rlen;
                break;
            }
            wire = n;
        }
        let blen = if req.chunked { dechunk(rbuf[b0..b0 + wire]) } else { wire };
        done++;
        off = b0 + wire;
        if !whole { c.discard = req.body; }
        var keep = req.keep_alive;
        H(req, rbuf[b0..b0 + blen],
          Reply { buf: wbuf, date: date, keep_alive: keep, minor: req.minor, head: req.method == "HEAD" });
        if !keep {
            c.state = CLOSING;
            off = rlen;
            break;
        }
    }
    let rest = rlen - off;
    if rest > 0 && off > 0 { copy_into(rbuf[..rest], rbuf[off..rlen]); }
    return rest, done, full;
}
