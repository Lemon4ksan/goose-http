// The HTTP server's io_uring loop: each worker has its own ring, and its own
// SO_REUSEPORT listener on Linux (sys::listen), and nothing else is shared
// between workers. A multishot accept takes the listener's connections, and
// a multishot receive per connection fills the ring's provided buffers. The
// sends a pass over the completions queues go to the kernel together, in the
// next wait.
import std;
import os;
import sys;
import ring;
import http;

// A connection's states, as in the epoll loop.
let OPEN: u8 = 0;       // answering requests
let CLOSING: u8 = 1;    // sending what's left, then shutting down its side
let DRAINING: u8 = 2;   // shut down, and dropping what arrives until the client closes

// The ring's size, and its provided buffers, which the kernel fills in
// turn. A receive that finds none left ends its multishot request, which
// the loop queues again. The loop gives each buffer back in the pass that
// takes it, so a wait's 256 completions use at most 256; 1,024 doubled
// peak RSS at the same rate (task 005).
let ENTRIES: i32 = 4096;
let NBUFS: i32 = 256;
let BUFLEN: i32 = 4096;

// The responses a connection may have waiting behind its send in flight.
// Past this, the loop stops reading from it until the client takes what it
// was sent, as the epoll loop does when a send would block.
let MAX_QUEUED = 65536;

// A request's tag: the connection's slot in the low 32 bits and a
// generation above, so a completion that arrives after its connection
// closed isn't taken for one of the slot's next connection. The listener's
// slot is one no connection gets.
let LISTENER: u64 = 0xFFFFFFFF;

// Between completions, a connection holds what it couldn't answer yet and
// the responses its send in flight left waiting, as runs of the worker's
// spill pool.
struct Conn {
    fd: i32,            // -1 while the slot is free
    tag: u64,
    state: u8,
    sending: bool,      // a send is in flight
    reading: bool,      // its multishot receive is queued
    stalled: bool,      // stopped reading at MAX_QUEUED, with held to answer
    deadline: i64,      // the time after which the sweep closes it
    discard: i64,       // request body bytes still to drop
    held: u8[:],        // received and not yet answered
    out: u8[:],         // answered, behind the send in flight
}

thread_fn worker(port: i32) { serve(port); }

fn serve(port: i32) {
    let lfd = sys::check("listen", sys::listen(port, BACKLOG, sys::NONBLOCK | sys::REUSEPORT));
    let r = sys::check("io_uring", ring::create(ENTRIES, NBUFS, BUFLEN));
    ring::accept(r, lfd, LISTENER);

    reusable[] var spill: u8[>..] = [];
    reusable var conns: Conn[>..] = [];
    var open = 0;
    var generation: u64 = 0;
    // Whether the listener's multishot accept is queued. It ends when the
    // worker reaches MAX_CONNS, and on an error such as EMFILE. Then it's
    // queued again once a connection closes, or at the next sweep.
    var accepting = true;
    var accept_failed = false;
    var closed = false;
    var now = sys::clock_ms();
    var next_sweep = now + 1000;
    var date: u8[..32] = [];
    var date_s: i64 = -1;
    var done: ring::Completion[256] =
        [ring::Completion { tag: 0, res: 0, buf: -1, more: false, send: false }; 256];
    // The driven connection's bytes: rbuf[..rlen] is received and not yet
    // answered, and wbuf is answered and not yet queued to send.
    var rbuf: u8[RBUF] = [0; RBUF];
    var rlen = 0;
    var wbuf: u8[..WBUF] = [];
    // Whether the driven connection answered a request or sent a response.
    var progress = false;

    fn accepted(cq: ring::Completion) {
        if !cq.more { accepting = false; }
        let fd = cq.res;
        if fd < 0 {
            // EMFILE, ENFILE, or out of memory: try again later.
            if fd != -ring::ECANCELED && !accept_failed { sys::report("accept", fd); }
            accept_failed = fd != -ring::ECANCELED;
            return;
        }
        accept_failed = false;
        guard open < MAX_CONNS else {
            sys::close(fd);
            return;
        }
        // A tag fits in 62 bits, and a free slot's is 0.
        generation = generation % 0x3FFFFFFF + 1;
        let i = conns.alloc_index(Conn { fd: fd, reading: true, deadline: now + REQUEST_MS, .. });
        let c .= conns[i];
        c.tag = (generation << 32) | (i as u64);
        ring::recv(r, fd, c.tag);
        open++;
        if open == MAX_CONNS && accepting { ring::cancel(r, LISTENER); }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        ring::close(r, c.fd);
        c.fd = -1;
        c.tag = 0;
        if c.held.len > 0 { spill.free_slice(c.held); }
        if c.out.len > 0 { spill.free_slice(c.out); }
        conns.free(i);
        open--;
        closed = true;
    }

    fn blocked(c: Conn&) -> bool { c.out.len >= MAX_QUEUED }

    // Queues wbuf to send, or keeps it behind the send in flight: one send
    // at a time keeps a connection's responses in order.
    fn flush(c: Conn&) {
        guard wbuf.len > 0 else { return; }
        if c.sending {
            let m = c.out.len;
            c.out = spill.realloc_slice(c.out, m + wbuf.len);
            copy_into(c.out[m..], wbuf);
        } else {
            sys::check("send", ring::send(r, c.fd, c.tag, wbuf));
            c.sending = true;
        }
        wbuf.clear();
    }

    // Answers every complete request in rbuf, and moves the rest of rbuf to
    // its front.
    fn answer(c: Conn&) {
        var off = 0;
        while off < rlen {
            if c.discard > 0 {
                let k = min(c.discard, rlen - off);
                off += k;
                c.discard -= k;
                continue;
            }
            if wbuf.cap - wbuf.len < http::MAX_RESPONSE { flush(c); }
            let req, status = http::parse(rbuf[off..rlen]);
            if status == http::INCOMPLETE { break; }
            if status != 200 {
                http::refuse(wbuf, status, date);
                c.state = CLOSING;
                off = rlen;
                break;
            }
            // A body the route reads, and a chunked one, are answered once
            // they are whole in rbuf; any other body is dropped as it comes.
            let b0 = off + req.len;
            let reads = http::reads_body(req);
            let whole = req.chunked || (req.body > 0 && reads);
            var wire = 0;
            if whole {
                let n, s = http::frame_body(rbuf[b0..rlen], req, RBUF - req.len);
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
            progress = true;
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
        rlen = rest;
    }

    // Answers n received bytes after rbuf[..rlen]: those of provided buffer
    // buf, or of src when buf is -1. rbuf takes them as it has room. If the
    // connection reaches MAX_QUEUED, it stops reading and holds the rest.
    fn pump(c: Conn&, buf: i32, src: const u8[:], n: i64) {
        var off: i64 = 0;
        while off < n {
            let k = min(n - off, RBUF - rlen);
            if buf >= 0 { ring::take(r, buf, off, rbuf[rlen..rlen + k]); }
            else { copy_into(rbuf[rlen..rlen + k], src[off..off + k]); }
            rlen += k;
            off += k;
            answer(c);
            if c.state != OPEN {
                rlen = 0;
                break;
            }
            if blocked(c) {
                c.held = spill.alloc_slice(rlen + n - off);
                copy_into(c.held[..rlen], rbuf[..rlen]);
                if buf >= 0 { ring::take(r, buf, off, c.held[rlen..]); }
                else { copy_into(c.held[rlen..], src[off..n]); }
                rlen = 0;
                c.stalled = true;
                if c.reading { ring::cancel(r, c.tag); }
                break;
            }
        }
        if rlen > 0 {
            c.held = spill.alloc_slice(rlen);
            copy_into(c.held, rbuf[..rlen]);
        }
        flush(c);
    }

    // A receive's completion. False when the connection is done.
    fn received(c: Conn&, cq: ring::Completion) -> bool {
        if !cq.more { c.reading = false; }
        if cq.res > 0 {
            let n = cq.res as i64;
            // A connection that isn't OPEN drops what arrives.
            if c.state != OPEN {
            } else if c.stalled {
                let m = c.held.len;
                c.held = spill.realloc_slice(c.held, m + n);
                ring::take(r, cq.buf, 0, c.held[m..]);
            } else {
                rlen = c.held.len;
                if rlen > 0 {
                    copy_into(rbuf[..rlen], c.held);
                    spill.free_slice(c.held);
                    c.held = c.held[..0];
                }
                pump(c, cq.buf, "", n);
            }
            ring::give(r, cq.buf);
        } else if cq.res == 0 || (cq.res != -ring::ENOBUFS && cq.res != -ring::ECANCELED) {
            return false;   // the client closed or reset
        }
        if !c.reading && !c.stalled {
            ring::recv(r, c.fd, c.tag);
            c.reading = true;
        }
        return true;
    }

    // A send's completion. False when the connection is done.
    fn sent(c: Conn&, res: i32) -> bool {
        c.sending = false;
        guard res >= 0 else { return false; }   // EPIPE, ECONNRESET: the client left
        progress = true;
        if c.out.len > 0 {
            sys::check("send", ring::send(r, c.fd, c.tag, c.out));
            c.sending = true;
            spill.free_slice(c.out);
            c.out = c.out[..0];
        } else if c.state == CLOSING {
            sys::shutdown(c.fd, sys::SHUT_WR);
            c.state = DRAINING;
            c.deadline = now + LINGER_MS;
        }
        if c.stalled {
            c.stalled = false;
            let src = c.held;
            c.held = c.held[..0];
            rlen = 0;
            pump(c, -1, src, src.len);
            spill.free_slice(src);
        }
        if !c.reading && !c.stalled {
            ring::recv(r, c.fd, c.tag);
            c.reading = true;
        }
        return true;
    }

    // Moves the deadline of a connection after a completion. Progress
    // restarts the clock; the first bytes of a request after an idle spell
    // shorten it.
    fn touch(c: Conn&) {
        guard c.state != DRAINING else { return; }
        let idle = c.held.len == 0 && c.discard == 0 && !c.sending;
        if progress { c.deadline = now + (if idle { IDLE_MS } else { REQUEST_MS }); }
        else if !idle { c.deadline = min(c.deadline, now + REQUEST_MS); }
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is refused with a 408 instead, which closes it as
    // any refusal does; LINGER_MS bounds the send. A close aborts a send in
    // flight on Windows, and io_uring's cancels one that hasn't gone out.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now { continue; }
            if c.state == OPEN && c.held.len > 0 && !c.sending {
                wbuf.clear();
                http::refuse(wbuf, 408, date);
                flush(c);
                c.state = CLOSING;
                c.deadline = now + LINGER_MS;
                continue;
            }
            close_conn(i);
        }
    }

    loop {
        // Open connections need the sweep, and a stopped accept its retry.
        let timeout: i32 = if open > 0 || !accepting { 1000 } else { -1 };
        let n = ring::wait(r, done, timeout);
        if n == -sys::EINTR { continue; }
        sys::check("io_uring_enter", n);
        now = sys::clock_ms();
        let t = sys::time_s();
        if t != date_s {
            date.clear();
            http::format_date(date, t);
            date_s = t;
        }
        closed = false;
        for cq in done[..n] {
            if cq.tag == LISTENER {
                accepted(cq);
                continue;
            }
            let i = (cq.tag & 0xFFFFFFFF) as i64;
            if i >= conns.len || conns[i].tag != cq.tag {
                // The connection closed after the request was queued.
                if cq.buf >= 0 { ring::give(r, cq.buf); }
                continue;
            }
            let c .= conns[i];
            progress = false;
            let ok = if cq.send { sent(c, cq.res) } else { received(c, cq) };
            if ok { touch(c); } else { close_conn(i); }
        }
        let tick = now >= next_sweep;
        if tick {
            sweep();
            next_sweep = now + 1000;
        }
        if !accepting && open < MAX_CONNS && (!accept_failed || closed || tick) {
            ring::accept(r, lfd, LISTENER);
            accepting = true;
        }
    }
}
