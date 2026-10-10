// The HTTP server: one worker per core, each with its own SO_REUSEPORT
// listener and edge-triggered epoll loop, and nothing shared between them.
// A connection belongs to the worker that accepted it, in a fixed-size slot
// of that worker's pool.
import std;
import os;
import sys;
import http;

// A connection's buffers. The read buffer holds the longest request head
// whole. The write buffer takes the responses to a read's worth of pipelined
// requests: 16 TechEmpower responses are about 2 KB. When it fills, the
// server sends it and answers the rest of the read buffer after.
let RBUF = http::MAX_HEAD;
let WBUF = 8192;

// The most connections one worker holds. One worker must be able to take
// TechEmpower's largest run, 16,384 connections, alone. A slot is about
// 16 KB, so that's 270 MB at most, committed as connections arrive.
let MAX_CONNS = 16384;
let BACKLOG = 4096;

// In milliseconds of the monotonic clock. A request has REQUEST_MS from its
// first byte to arrive whole, and a response as long to leave once it stops
// moving. An idle keep-alive connection closes after IDLE_MS. A refused
// connection has LINGER_MS for the client to read the refusal and close.
let REQUEST_MS = 10000;
let IDLE_MS = 60000;
let LINGER_MS = 2000;

// A connection's states.
let OPEN: u8 = 0;       // answering requests
let CLOSING: u8 = 1;    // sending what's left, then shutting down its side
let DRAINING: u8 = 2;   // shut down, and dropping what arrives until the client closes

// The listener's epoll tag. A connection's is its slot.
let LISTENER: u64 = 0xFFFFFFFFFFFFFFFF;

struct Conn {
    fd: i32,            // -1 while the slot is free
    state: u8,
    deadline: i64,      // the time after which the sweep closes it
    discard: i64,       // request body bytes still to drop
    rlen: i64,          // rbuf[..rlen] is received and not yet answered
    woff: i64,          // wbuf[woff..] is still to send
    rbuf: u8[RBUF],
    wbuf: u8[..WBUF],
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

thread_fn worker(port: i32) { serve(port); }

fn serve(port: i32) {
    let lfd = sys::check("listen", sys::listen(port, BACKLOG, sys::NONBLOCK | sys::REUSEPORT));
    let ep = sys::check("epoll_create", sys::epoll_create());
    sys::check("epoll_ctl", sys::epoll_ctl(ep, sys::CTL_ADD, lfd, sys::IN | sys::ET, LISTENER));

    // A closed connection's slot is reset field by field and kept in spare
    // for the next accept. A reusable pool's alloc_index takes a whole Conn,
    // which the compiler builds and copies through 16 KB temporaries
    // (docs/goose-findings.md).
    var conns: Conn[>..] = [];
    var spare: i64[>..<] = [];
    var open = 0;
    // Set when accepting stopped before the backlog was empty: at MAX_CONNS,
    // or at the fd limit (EMFILE). The listener's edge has passed, so the
    // loop retries until the backlog is empty, and the waiting clients keep
    // their place in it.
    var paused = false;
    var now = sys::clock_ms();
    var next_sweep = now + 1000;
    var date: u8[..32] = [];
    var date_s: i64 = -1;
    var events: sys::Event[256] = [sys::Event { events: 0, tag: 0 }; 256];

    fn accept_all() {
        let retry = paused;
        paused = true;
        while open < MAX_CONNS {
            let fd = sys::accept(lfd, sys::NONBLOCK);
            if fd == -sys::EAGAIN {
                paused = false;
                return;
            }
            if fd == -sys::EINTR || fd == -sys::ECONNABORTED { continue; }
            guard fd >= 0 else {
                // EMFILE, ENFILE, or out of memory: try again later.
                if !retry { sys::report("accept", fd); }
                return;
            }
            var i = conns.len;
            if spare.len > 0 {
                i = spare.pop();
                let c .= conns[i];
                c.fd = fd;
                c.deadline = now + REQUEST_MS;
            } else {
                conns.push(Conn { fd: fd, deadline: now + REQUEST_MS, .. });
            }
            let r = sys::epoll_ctl(ep, sys::CTL_ADD, fd, sys::IN | sys::OUT | sys::RDHUP | sys::ET,
                                   i as u64);
            if r < 0 {
                sys::report("epoll_ctl", r);
                sys::close(fd);
                conns[i].fd = -1;
                spare.push(i);
                continue;
            }
            open++;
        }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        sys::close(c.fd);
        c.fd = -1;
        c.state = OPEN;
        c.discard = 0;
        c.rlen = 0;
        c.woff = 0;
        c.wbuf.clear();
        spare.push(i);
        open--;
    }

    // Answers every complete request in rbuf while the responses fit in
    // wbuf, and moves the rest of rbuf to its front. Returns the number of
    // requests answered, and whether it stopped because wbuf was full.
    fn answer(c: Conn&) -> i64, bool {
        var off = 0;
        var done = 0;
        var full = false;
        while off < c.rlen {
            if c.discard > 0 {
                let k = min(c.discard, c.rlen - off);
                off += k;
                c.discard -= k;
                continue;
            }
            if c.wbuf.cap - c.wbuf.len < http::MAX_RESPONSE {
                full = true;
                break;
            }
            let req, status = http::parse(c.rbuf[off..c.rlen]);
            if status == http::INCOMPLETE { break; }
            if status != 200 {
                http::refuse(c.wbuf, status, date);
                c.state = CLOSING;
                off = c.rlen;
                break;
            }
            // A body the route reads, and a chunked one, are answered once
            // they are whole in rbuf; any other body is dropped as it comes.
            let b0 = off + req.len;
            let reads = http::reads_body(req);
            let whole = req.chunked || (req.body > 0 && reads);
            var wire = 0;
            if whole {
                let n, s = http::frame_body(c.rbuf[b0..c.rlen], req, RBUF - req.len);
                if s == http::INCOMPLETE { break; }
                if s != 200 {
                    http::refuse(c.wbuf, s, date);
                    c.state = CLOSING;
                    off = c.rlen;
                    break;
                }
                wire = n;
            }
            let blen = if !reads { 0 }
                       else if req.chunked { http::dechunk(c.rbuf[b0..b0 + wire]) }
                       else { wire };
            done++;
            off = b0 + wire;
            if !whole { c.discard = req.body; }
            if !http::respond(c.wbuf, req, c.rbuf[b0..b0 + blen], date) {
                c.state = CLOSING;
                off = c.rlen;
                break;
            }
        }
        let rest = c.rlen - off;
        if rest > 0 && off > 0 { copy_into(c.rbuf[..rest], c.rbuf[off..c.rlen]); }
        c.rlen = rest;
        return done, full;
    }

    // Moves a connection on as far as its socket allows: answers what it
    // can, sends the responses in one send, and reads more. Edge-triggered
    // epoll reports a socket again only after its state changes, so this
    // returns only once a send or a recv would block, or the connection is
    // done, which is false.
    fn drive(c: Conn&) -> bool {
        var progress = false;
        loop {
            var full = false;
            if c.state == OPEN && c.rlen > 0 {
                let done, f = answer(c);
                if done > 0 { progress = true; }
                full = f;
            }
            while c.woff < c.wbuf.len {
                let w = sys::send(c.fd, c.wbuf[c.woff..]);
                if w == -sys::EAGAIN { return wait(c, progress); }
                if w == -sys::EINTR { continue; }
                guard w > 0 else { return false; }   // EPIPE, ECONNRESET: the client left
                c.woff += w;
                progress = true;
            }
            c.wbuf.clear();
            c.woff = 0;
            if c.state == CLOSING {
                sys::shutdown(c.fd, sys::SHUT_WR);
                c.state = DRAINING;
                c.deadline = now + LINGER_MS;
            }
            if full { continue; }
            // answer leaves rbuf full only to refuse the request with 431 or
            // 413, so an OPEN connection always has room to read into.
            let r = if c.state == DRAINING { sys::recv(c.fd, c.rbuf) }
                    else { sys::recv(c.fd, c.rbuf[c.rlen..]) };
            if r == -sys::EAGAIN { return wait(c, progress); }
            if r == -sys::EINTR { continue; }
            guard r > 0 else { return false; }   // the client closed or reset
            if c.state == OPEN { c.rlen += r; }
        }
    }

    // Moves the deadline of a connection that's waiting on its socket.
    // Progress restarts the clock; the first bytes of a request after an
    // idle spell shorten it.
    fn wait(c: Conn&, progress: bool) -> bool {
        guard c.state != DRAINING else { return true; }
        let idle = c.rlen == 0 && c.discard == 0 && c.woff == c.wbuf.len;
        if progress { c.deadline = now + (if idle { IDLE_MS } else { REQUEST_MS }); }
        else if !idle { c.deadline = min(c.deadline, now + REQUEST_MS); }
        return true;
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is sent a 408 first, if its socket takes it.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now { continue; }
            if c.state == OPEN && c.rlen > 0 && c.wbuf.len == 0 {
                http::refuse(c.wbuf, 408, date);
                sys::send(c.fd, c.wbuf);
            }
            close_conn(i);
        }
    }

    loop {
        // Open connections need the sweep, and a paused accept its retry.
        let timeout: i32 = if open > 0 || paused { 1000 } else { -1 };
        let n = sys::epoll_wait(ep, events, timeout);
        if n == -sys::EINTR { continue; }
        sys::check("epoll_wait", n);
        now = sys::clock_ms();
        let t = sys::time_s();
        if t != date_s {
            date.clear();
            http::format_date(date, t);
            date_s = t;
        }
        for ev in events[..n] {
            if ev.tag == LISTENER {
                accept_all();
                continue;
            }
            let i = ev.tag as i64;
            if !drive(conns[i]) { close_conn(i); }
        }
        if now >= next_sweep {
            sweep();
            next_sweep = now + 1000;
        }
        if paused { accept_all(); }
    }
}
