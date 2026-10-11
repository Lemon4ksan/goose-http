// The HTTP server's epoll loop: each worker has its own edge-triggered epoll
// instance, and its own SO_REUSEPORT listener on Linux (sys::listen), and
// nothing else is shared between workers. A connection belongs to the
// worker that accepted it, in a slot of that worker's pool.
import std;
import os;
import sys;
import http;

// A connection's states.
let OPEN: u8 = 0;       // answering requests
let CLOSING: u8 = 1;    // sending what's left, then shutting down its side
let DRAINING: u8 = 2;   // shut down, and dropping what arrives until the client closes

// The listener's epoll tag. A connection's is its slot.
let LISTENER: u64 = 0xFFFFFFFFFFFFFFFF;

// Between events, a connection holds only what its socket left over: the
// start of a request not yet whole, and responses the socket didn't take.
// Both are runs of the worker's spill pool, empty almost always.
struct Conn {
    fd: i32,            // -1 while the slot is free
    state: u8,
    watch_out: bool,    // OUT is registered: set while out holds bytes
    deadline: i64,      // the time after which the sweep closes it
    discard: i64,       // request body bytes still to drop
    held: u8[:],        // received and not yet answered
    out: u8[:],         // still to send
}

thread_fn worker(port: i32) {
    sys::worker_start();
    serve(port);
}

// The worker count without WORKERS (app.goose).
fn default_workers() -> i64 {
    let n = sys::default_workers();
    return if n > 0 { n } else { hardware_threads() };
}

fn serve(port: i32) {
    let lfd = sys::check("listen", sys::listen(port, BACKLOG, sys::NONBLOCK | sys::REUSEPORT));
    let ep = sys::check("epoll_create", sys::epoll_create());
    sys::check("epoll_ctl", sys::epoll_ctl(ep, sys::CTL_ADD, lfd, sys::IN | sys::ET, LISTENER));

    reusable[] var spill: u8[>..] = [];
    reusable var conns: Conn[>..] = [];
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
    // The driven connection's bytes: rbuf[..rlen] is received and not yet
    // answered, and wbuf[woff..] is still to send.
    var rbuf: u8[RBUF] = [0; RBUF];
    var rlen = 0;
    var wbuf: u8[..WBUF] = [];
    var woff = 0;

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
            let i = conns.alloc_index(Conn { fd: fd, deadline: now + REQUEST_MS, .. });
            let r = sys::epoll_ctl(ep, sys::CTL_ADD, fd, sys::IN | sys::RDHUP | sys::ET, i as u64);
            if r < 0 {
                sys::report("epoll_ctl", r);
                sys::close(fd);
                conns[i].fd = -1;
                conns.free(i);
                continue;
            }
            open++;
        }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        sys::close(c.fd);
        c.fd = -1;
        if c.held.len > 0 { spill.free_slice(c.held); }
        if c.out.len > 0 { spill.free_slice(c.out); }
        conns.free(i);
        open--;
    }

    // Answers every complete request in rbuf while the responses fit in
    // wbuf, and moves the rest of rbuf to its front. Returns the number of
    // requests answered, and whether it stopped because wbuf was full.
    fn answer(c: Conn&) -> i64, bool {
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
            if wbuf.cap - wbuf.len < http::MAX_RESPONSE {
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
        rlen = rest;
        return done, full;
    }

    // Moves a connection on as far as its socket allows, in the worker's
    // buffers, and keeps what's left over in spill. hup is whether the event
    // reported the client's side closed. False when the connection is done.
    fn drive(c: Conn&, hup: bool) -> bool {
        rlen = c.held.len;
        if rlen > 0 {
            copy_into(rbuf[..rlen], c.held);
            spill.free_slice(c.held);
            c.held = c.held[..0];
        }
        wbuf.clear();
        woff = 0;
        if c.out.len > 0 {
            wbuf.append(c.out);
            spill.free_slice(c.out);
            c.out = c.out[..0];
        }
        guard advance(c, hup) else { return false; }
        if rlen > 0 {
            c.held = spill.alloc_slice(rlen);
            copy_into(c.held, rbuf[..rlen]);
        }
        if woff < wbuf.len {
            c.out = spill.alloc_slice(wbuf.len - woff);
            copy_into(c.out, wbuf[woff..]);
        }
        return true;
    }

    // Registers OUT while the connection has bytes the socket didn't take, and
    // drops it once they're sent, as libuv does: kqueue reports EV_CLEAR's
    // write filter as each ACK frees buffer space, a wake-up per response.
    // False if epoll_ctl fails.
    fn watch(i: i64) -> bool {
        let c .= conns[i];
        let want = c.out.len > 0;
        if want == c.watch_out { return true; }
        let out: u32 = if want { sys::OUT } else { 0 };
        let r = sys::epoll_ctl(ep, sys::CTL_MOD, c.fd, sys::IN | out | sys::RDHUP | sys::ET, i as u64);
        if r < 0 {
            sys::report("epoll_ctl", r);
            return false;
        }
        c.watch_out = want;
        return true;
    }

    // Answers what it can, sends the responses in one send, and reads more.
    // Edge-triggered epoll reports a socket again only after its state
    // changes, so this returns only once a send would block, the socket is
    // empty, or the connection is done, which is false. A recv that filled
    // less than it was given emptied the socket, and the next byte to arrive
    // raises a new event, so it isn't followed by a recv that would block,
    // unless hup: a close that arrived with the last bytes raises none.
    fn advance(c: Conn&, hup: bool) -> bool {
        var progress = false;
        var drained = false;
        loop {
            var full = false;
            if c.state == OPEN && rlen > 0 {
                let done, f = answer(c);
                if done > 0 { progress = true; }
                full = f;
            }
            while woff < wbuf.len {
                let w = sys::send(c.fd, wbuf[woff..]);
                if w == -sys::EAGAIN { return wait(c, progress); }
                if w == -sys::EINTR { continue; }
                guard w > 0 else { return false; }   // EPIPE, ECONNRESET: the client left
                woff += w;
                progress = true;
            }
            wbuf.clear();
            woff = 0;
            if c.state == CLOSING {
                sys::shutdown(c.fd, sys::SHUT_WR);
                c.state = DRAINING;
                c.deadline = now + LINGER_MS;
            }
            if full { continue; }
            if drained { return wait(c, progress); }
            // answer leaves rbuf full only to refuse the request with 431 or
            // 413, so an OPEN connection always has room to read into.
            let room = if c.state == DRAINING { RBUF } else { RBUF - rlen };
            let r = if c.state == DRAINING { sys::recv(c.fd, rbuf) }
                    else { sys::recv(c.fd, rbuf[rlen..]) };
            if r == -sys::EAGAIN { return wait(c, progress); }
            if r == -sys::EINTR { continue; }
            guard r > 0 else { return false; }   // the client closed or reset
            if c.state == OPEN { rlen += r; }
            drained = r < room && !hup;
        }
    }

    // Moves the deadline of a connection that's waiting on its socket.
    // Progress restarts the clock; the first bytes of a request after an
    // idle spell shorten it.
    fn wait(c: Conn&, progress: bool) -> bool {
        guard c.state != DRAINING else { return true; }
        let idle = rlen == 0 && c.discard == 0 && woff == wbuf.len;
        if progress { c.deadline = now + (if idle { IDLE_MS } else { REQUEST_MS }); }
        else if !idle { c.deadline = min(c.deadline, now + REQUEST_MS); }
        return true;
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is sent a 408 first, if its socket takes it, and then
    // shut down and drained as any refusal is.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now { continue; }
            if c.state == OPEN && c.held.len > 0 && c.out.len == 0 {
                wbuf.clear();
                http::refuse(wbuf, 408, date);
                let sent = sys::send(c.fd, wbuf) == wbuf.len;
                wbuf.clear();
                if sent {
                    spill.free_slice(c.held);
                    c.held = c.held[..0];
                    sys::shutdown(c.fd, sys::SHUT_WR);
                    c.state = DRAINING;
                    c.deadline = now + LINGER_MS;
                    continue;
                }
            }
            close_conn(i);
        }
    }

    // Whether the last wait returned events. Under load the next ones are
    // usually queued by the time a batch is done, so the next wait only polls,
    // and the worker sleeps only after a poll comes back empty: that skips the
    // wakeup a blocking wait costs each batch.
    var hot = false;
    loop {
        // Open connections need the sweep, and a paused accept its retry.
        let timeout: i32 = if hot { 0 } else if open > 0 || paused { 1000 } else { -1 };
        let n = sys::epoll_wait(ep, events, timeout);
        if n == -sys::EINTR { continue; }
        sys::check("epoll_wait", n);
        hot = n > 0;
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
            if !drive(conns[i], ev.events & (sys::RDHUP | sys::HUP | sys::ERR) != 0) || !watch(i) {
                close_conn(i);
            }
        }
        if now >= next_sweep {
            sweep();
            next_sweep = now + 1000;
        }
        if paused { accept_all(); }
    }
}
