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
//
// For bodies and responses of any size, each loop also takes a handler that
// it calls again for each piece of the exchange (Event), with state of the
// program's own type that starts each request as fresh:
//
//   http::serve(cfg, fresh) { ev, st, out => ... }
//   http::serve_epoll(cfg, fresh) { ev, st, out => ... }
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
    // handler whole; a longer one in pieces, or dropped as it arrives.
    max_head: i64 = MAX_HEAD,
    // The longest body a request may have; a longer one is refused with 413.
    max_body: i64 = MAX_BODY,
    // The longest request line, past which a request is refused with 414,
    // and the most header fields, past which with 431.
    max_line: i64 = MAX_LINE,
    max_fields: i64 = MAX_FIELDS,
    // The most bytes of a body the handler answered without reading that
    // the connection drops to stay open; past them, it closes.
    max_drain: i64 = MAX_BODY,
    // A worker's write buffer grows to hold any response whole. Past this
    // many bytes, the worker sends what it holds before it answers more: the
    // default takes the responses to a read's worth of pipelined requests, as
    // 16 TechEmpower responses are about 2 KB.
    write_buffer: i64 = 8192,
    // In milliseconds of the monotonic clock. A request head has request_ms
    // from its first byte to arrive whole. A body that comes in pieces has
    // body_ms between them, and a response write_ms to move on once the
    // client stops taking it. A connection gets 408 or is closed past them.
    // An idle keep-alive connection closes after idle_ms. A refused
    // connection has linger_ms for the client to read the refusal and close.
    request_ms: i64 = 10000,
    body_ms: i64 = 10000,
    write_ms: i64 = 10000,
    idle_ms: i64 = 60000,
    linger_ms: i64 = 2000,
    // After stop, how long a loop goes on with the requests in progress
    // before it closes their connections and returns.
    grace_ms: i64 = 10000,
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

// What a handler given to serve(cfg, fresh) or serve_epoll(cfg, fresh) is
// called for: Event.kind.
let REQUEST: u8 = 0;    // a request's head, and its body if it came whole
let BODY: u8 = 1;       // the next piece of a body that didn't come whole
let END: u8 = 2;        // the end of that body
let MORE: u8 = 3;       // room for more of a response begun with begin, once the body has ended

struct Event {
    kind: u8,
    // REQUEST's parsed head. Its slices point into the read buffer, and last
    // until the handler returns. A reference, so that the request isn't
    // copied for each call: about 20 instructions per request.
    req: const Request&,
    // REQUEST's body, when whole; BODY's piece, decoded if chunked.
    data: const u8[:],
    // REQUEST's data is the whole body, as a body that fits in the read buffer
    // with its head always is, and no BODY or END follows.
    whole: bool,
}

// A request whose exchange outlasts the handler's REQUEST call: what of its
// body is still to come, what its response needs, and the handler's state.
// Each connection's slot holds one.
struct Exchange<S> {
    body: BodyReader,
    skip: bool,         // drop the rest of the body: the response is done without it
    taken: i64,         // body bytes so far, or dropped since skip, if chunked
    answered: bool,     // the handler's response is whole
    continued: bool,    // 100 Continue went out for the request in the read buffer
    expect: bool,       // the client asked for 100 Continue
    keep_alive: bool,
    head: bool,
    minor: i32,
    stream: Stream,
    state: S,
}

// The interim response a client that sent Expect: 100-continue waits for.
// A function: a thread_fn can't reach a global slice (spec §11.2).
fn interim() -> const u8[:] { "HTTP/1.1 100 Continue\r\n\r\n" }

// Answers the requests in rbuf[..rlen] for connection c with the handler H,
// into wbuf, and moves the rest of rbuf to its front. rbuf's length is the
// longest head it takes. A request's state starts as fresh, and while
// stopping, its response closes the connection. Before a
// request, a piece of a body, or a MORE call, if wbuf holds
// cfg.write_buffer bytes or more, it calls ROOM(), which empties wbuf and
// returns true, or returns false to stop there. Returns the bytes left in
// rbuf, the number of calls to H, and whether ROOM stopped it. A refused
// request, or a response that doesn't keep the connection open, leaves c
// CLOSING and rbuf empty.
fn answer<S, H, ROOM, C>(c: C&, rbuf: u8[:], rlen: i64, wbuf: u8[>..]&, date: const u8[:],
                         cfg: const Config&, fresh: const S&, stopping: bool) -> i64, i64, bool {
    var off = 0;
    var done = 0;
    var full = false;
    let x .= c.x;
    // The req of the events after REQUEST.
    let gone = Request { .. };

    // Sends what wbuf holds, and closes.
    fn close() {
        c.state = CLOSING;
        off = rlen;
    }

    // Refuses the request with status, unless its response has begun, and
    // closes.
    fn fail(status: i32) {
        if !x.answered && !x.stream.open { refuse(wbuf, status, date); }
        close();
    }

    // Calls H for ev on the request in x. Returns whether it wrote anything.
    fn call(ev: Event) -> bool {
        let before = wbuf.len;
        let was_open = x.stream.open;
        H(ev, x.state, Reply { buf: wbuf, date: date, keep_alive: x.keep_alive, minor: x.minor,
                               head: x.head, stream: x.stream });
        done++;
        let wrote = wbuf.len > before;
        if !x.stream.open && (wrote || was_open) { x.answered = true; }
        return wrote;
    }

    // Moves the request in x on after a call to H. False when the connection
    // closes.
    fn settle() -> bool {
        if x.body.place == NO_BODY {
            if x.stream.open { return true; }
            if !x.answered {
                fail(500);
                return false;
            }
            x.continued = false;
            if !x.keep_alive || stopping {
                close();
                return false;
            }
            return true;
        }
        if x.answered && !x.skip {
            // Answered before the body ended: the rest is dropped, unless the
            // client still waits for 100 Continue, or the rest is longer than
            // cfg.max_drain. Then the connection closes.
            x.skip = true;
            x.taken = 0;
            if (x.expect && !x.continued) || !x.keep_alive ||
               (x.body.place == LENGTH && x.body.left > cfg.max_drain) {
                close();
                return false;
            }
        }
        return true;
    }

    loop {
        if x.body.place != NO_BODY {
            guard off < rlen else { break; }
            if wbuf.len >= cfg.write_buffer && !ROOM() {
                full = true;
                break;
            }
            let d0, d1, s = read_body(rbuf[off..rlen], x.body);
            if s == INCOMPLETE {
                // A size or trailer line longer than rbuf can't fit.
                if off == 0 && rlen == rbuf.len { fail(400); }
                break;
            }
            if s != 200 {
                fail(400);
                break;
            }
            let piece = rbuf[off + d0..off + d1];
            off += d1;
            x.taken += piece.len;
            // A chunk's size tells, before its data, whether it's too long.
            let coming = if x.body.place == CHUNK_DATA { x.body.left } else { 0 };
            if x.skip {
                done++;
                if x.taken > cfg.max_drain {
                    close();
                    break;
                }
                if x.body.place == NO_BODY { guard settle() else { break; } }
                continue;
            }
            // A Content-Length beyond cfg.max_body is refused by parse.
            if x.taken + coming > cfg.max_body {
                fail(413);
                break;
            }
            if piece.len > 0 { call(Event { kind: BODY, req: gone, data: piece, whole: false }); }
            if x.body.place == NO_BODY && !x.answered { call(Event { kind: END, req: gone, data: "", whole: false }); }
            guard settle() else { break; }
            continue;
        }
        if x.stream.open {
            if wbuf.len >= cfg.write_buffer && !ROOM() {
                full = true;
                break;
            }
            // A MORE that neither sends nor ends would be called forever.
            x.stream.moved = false;
            if !call(Event { kind: MORE, req: gone, data: "", whole: false }) && !x.stream.moved && x.stream.open {
                close();
                break;
            }
            guard settle() else { break; }
            continue;
        }
        guard off < rlen else { break; }
        if wbuf.len >= cfg.write_buffer && !ROOM() {
            full = true;
            break;
        }
        let req, status = parse(rbuf[off..rlen], rbuf.len, cfg.max_body, cfg.max_line, cfg.max_fields);
        if status == INCOMPLETE { break; }
        if status != 200 {
            refuse(wbuf, status, date);
            close();
            break;
        }
        // A body that fits in rbuf with its head is answered once it's whole,
        // and so is a chunked one that turns out to fit. A longer one goes to
        // the handler in pieces.
        let b0 = off + req.len;
        let room = rbuf.len - req.len;
        var whole = !req.chunked && req.body <= room;
        var wire = 0;
        if req.chunked || (req.body > 0 && whole) {
            let n, s = frame_body(rbuf[b0..rlen], req, room);
            if s == INCOMPLETE {
                // The client may wait for this before it sends the body.
                if req.expect && !x.continued {
                    wbuf.append(interim());
                    x.continued = true;
                }
                break;
            }
            if s == 413 && req.chunked {
                whole = false;
            } else if s != 200 {
                refuse(wbuf, s, date);
                close();
                break;
            } else {
                whole = true;
                wire = n;
            }
        }
        let blen = if req.chunked && whole { dechunk(rbuf[b0..b0 + wire]) } else { wire };
        off = b0 + wire;
        // The request's state goes straight into c's slot, whose stream no
        // response holds open between requests.
        x.keep_alive = req.keep_alive && !stopping;
        x.state = fresh;
        let before = wbuf.len;
        H(Event { kind: REQUEST, req: req, data: rbuf[b0..b0 + blen], whole: whole }, x.state,
          Reply { buf: wbuf, date: date, keep_alive: x.keep_alive, minor: req.minor,
                  head: req.method == "HEAD", stream: x.stream });
        done++;
        if whole && !x.stream.open {
            if wbuf.len == before {
                // The handler didn't answer.
                refuse(wbuf, 500, date);
                close();
                break;
            }
            if req.expect { x.continued = false; }
            if !x.keep_alive {
                close();
                break;
            }
            continue;
        }
        // The exchange goes on past this call, in c's slot.
        x.body = if whole { BodyReader { .. } }
                 else if req.chunked { BodyReader { place: CHUNK_SIZE, left: 0 } }
                 else { BodyReader { place: LENGTH, left: req.body } };
        x.skip = false;
        x.taken = 0;
        x.answered = !x.stream.open && wbuf.len > before;
        x.expect = req.expect;
        x.head = req.method == "HEAD";
        x.minor = req.minor;
        if x.expect && !x.answered && !x.stream.open && !x.continued {
            wbuf.append(interim());
            x.continued = true;
        }
        guard settle() else { break; }
    }
    let rest = rlen - off;
    if rest > 0 && off > 0 { copy_into(rbuf[..rest], rbuf[off..rlen]); }
    return rest, done, full;
}

// Whether c's request has stopped short, for the sweep: the start of one in
// held, or a body not all arrived, that the handler hasn't answered yet.
fn owes_408(c) -> bool {
    return c.state == OPEN && !c.x.stream.open && c.out.len == 0 &&
        (c.held.len > 0 && c.x.body.place == NO_BODY || c.x.body.place != NO_BODY && !c.x.answered);
}

// How long connection c may wait without progress, in milliseconds, when it
// isn't idle: for the client to take a response, which writing says it
// hasn't yet, for a body's next piece, or for the rest of a request head.
fn busy_ms(c, writing: bool, cfg: const Config&) -> i64 {
    return if writing { cfg.write_ms } else if c.x.body.place != NO_BODY { cfg.body_ms } else { cfg.request_ms };
}

// Whether c is between requests, with nothing of one received or to send.
fn idle(c) -> bool {
    return c.held.len == 0 && c.x.body.place == NO_BODY && !c.x.stream.open;
}

// The handler of serve(cfg) and serve_epoll(cfg) on an Event, ahead of
// their H: whether H answers it, with the body when it came whole and an
// empty one otherwise, which is dropped as it arrives. H can't tell an empty
// chunked body from one dropped, so a chunked body that doesn't come whole
// is refused with 413. The loops call H themselves, and this returns only at
// its end: Goose inlines neither a function with an early return nor one
// that takes a function value, and as a call, gcc keeps it, and H, out of
// line, which cost 60-120 instructions per request.
inline fn whole_only(ev: Event, out: Reply) -> bool {
    let refused = ev.kind == REQUEST && ev.req.chunked && !ev.whole;
    if refused {
        out.keep_alive = false;
        start(out, 413);
        finish(out, "Content-Length: ", "");
    }
    return ev.kind == REQUEST && !refused;
}
