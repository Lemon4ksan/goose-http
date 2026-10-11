// The HTTP server's epoll loop: each worker has its own edge-triggered epoll
// instance, and its own SO_REUSEPORT listener on Linux (sys::listen), and
// nothing else is shared between workers. A connection belongs to the
// worker that accepted it, in a slot of that worker's pool.
import std;
import os;
import sys;
import http;

// The listener's epoll tag. A connection's is its slot.
let LISTENER: u64 = 0xFFFFFFFFFFFFFFFF;

// Between events, a connection holds only what its socket left over: the
// start of a request not yet whole, and responses the socket didn't take.
// Both are runs of the worker's spill pool, empty almost always.
struct Conn {
    fd: i32,            // -1 while the slot is free
    state: u8,
    deadline: i64,      // the time after which the sweep closes it
    discard: i64,       // request body bytes still to drop
    held: u8[:],        // received and not yet answered
    out: u8[:],         // still to send
}

// Serves HTTP as cfg says until a call fails, and returns its error, with
// every socket it opened closed.
fn serve(cfg: Config) -> Error {
    let ip, ok = ipv4(cfg.address);
    guard ok else { return Error { call: "address", code: sys::EINVAL }; }
    let lfd = sys::listen(ip, cfg.port, cfg.backlog, sys::NONBLOCK | sys::REUSEPORT);
    guard lfd >= 0 else { return Error { call: "listen", code: -lfd }; }
    let ep = sys::epoll_create();
    guard ep >= 0 else {
        sys::close(lfd);
        return Error { call: "epoll_create", code: -ep };
    }
    let added = sys::epoll_ctl(ep, sys::CTL_ADD, lfd, sys::IN | sys::ET, LISTENER);
    guard added >= 0 else {
        sys::close(ep);
        sys::close(lfd);
        return Error { call: "epoll_ctl", code: -added };
    }

    reusable[] var spill: u8[>..] = [];
    reusable var conns: Conn[>..] = [];
    var open = 0;
    // Set when accepting stopped before the backlog was empty: at cfg.max_conns,
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
    var rbuf: u8[>..] = [];
    rbuf.resize(cfg.max_head, 0);
    var rlen = 0;
    var wbuf: u8[>..] = [];
    var woff = 0;

    fn accept_all() {
        let retry = paused;
        paused = true;
        while open < cfg.max_conns {
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
            let i = conns.alloc_index(Conn { fd: fd, deadline: now + cfg.request_ms, .. });
            let r = sys::epoll_ctl(ep, sys::CTL_ADD, fd, sys::IN | sys::OUT | sys::RDHUP | sys::ET,
                                   i as u64);
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
                let rest, done, f = answer(c, rbuf, rlen, wbuf, date, cfg) { false };
                rlen = rest;
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
                c.deadline = now + cfg.linger_ms;
            }
            if full { continue; }
            if drained { return wait(c, progress); }
            // answer leaves rbuf full only to refuse the request with 431 or
            // 413, so an OPEN connection always has room to read into.
            let room = if c.state == DRAINING { rbuf.len } else { rbuf.len - rlen };
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
        if progress { c.deadline = now + (if idle { cfg.idle_ms } else { cfg.request_ms }); }
        else if !idle { c.deadline = min(c.deadline, now + cfg.request_ms); }
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
                    c.deadline = now + cfg.linger_ms;
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
    var failed = Error { call: "", code: 0 };
    loop {
        // Open connections need the sweep, and a paused accept its retry.
        let timeout: i32 = if hot { 0 } else if open > 0 || paused { 1000 } else { -1 };
        let n = sys::epoll_wait(ep, events, timeout);
        if n == -sys::EINTR { continue; }
        guard n >= 0 else {
            failed = Error { call: "epoll_wait", code: -n };
            break;
        }
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
            if !drive(conns[i], ev.events & (sys::RDHUP | sys::HUP | sys::ERR) != 0) { close_conn(i); }
        }
        if now >= next_sweep {
            sweep();
            next_sweep = now + 1000;
        }
        if paused { accept_all(); }
    }
    for i in conns.len {
        if conns[i].fd >= 0 { close_conn(i); }
    }
    sys::close(ep);
    sys::close(lfd);
    return failed;
}
