// serve_epoll, the readiness loop: each worker has its own edge-triggered
// epoll instance (kqueue on macOS), and its own SO_REUSEPORT listener on Linux
// (net_listen), and nothing else is shared between workers. A connection
// belongs to the worker that accepted it, in a slot of that worker's pool.
namespace http;

import std;
import os;
import sys;
import message;

// The listener's epoll tag. A connection's is its slot.
let EPOLL_LISTENER: u64 = 0xFFFFFFFFFFFFFFFF;

// Between events, a connection holds only what its socket left over: the
// start of a request not yet whole, and responses the socket didn't take.
// Both are runs of the worker's spill pool, empty almost always.
struct EpollConn<S> {
    fd: i32,            // -1 while the slot is free
    state: u8,
    watch_out: bool,    // OUT is registered: set while out holds bytes
    deadline: i64,      // the time after which the sweep closes it
    x: Exchange<S>,     // the request in progress past its handler's REQUEST call
    held: u8[:],        // received and not yet answered
    out: u8[:],         // still to send
}

// Serves HTTP as cfg says, answering each request with H, until a call fails
// or stop ends it, and returns its error, with every socket it opened
// closed. On Windows it fails at once with ENOSYS.
fn serve_epoll<H>(cfg: Config) -> Error {
    return serve_epoll(cfg, false) { ev, st, out => if whole_only(ev, out) { H(ev.req, ev.data, out); } };
}

// serve_epoll(cfg), with a handler H that's called for each Event of a
// request, with the request's state, which starts as fresh.
fn serve_epoll<S, H>(cfg: Config, fresh: S) -> Error {
    net_worker_start();
    let ip, ok = ipv4(cfg.address);
    guard ok else { return Error { call: "address", code: EINVAL }; }
    guard is_field_value(cfg.server) else { return Error { call: "server", code: EINVAL }; }
    var lfd = net_listen(ip, cfg.port, cfg.backlog, NONBLOCK | REUSEPORT);
    guard lfd >= 0 else { return Error { call: "listen", code: -lfd }; }
    let ep = net_epoll_create();
    guard ep >= 0 else {
        net_close(lfd);
        return Error { call: "epoll_create", code: -ep };
    }
    let added = net_epoll_ctl(ep, EPOLL_CTL_ADD, lfd, EPOLLIN | EPOLLET, EPOLL_LISTENER);
    guard added >= 0 else {
        net_close(ep);
        net_close(lfd);
        return Error { call: "epoll_ctl", code: -added };
    }

    let started = stops();
    var stopping = false;
    var stop_by: i64 = 0;
    reusable[] var spill: u8[>..] = [];
    reusable var conns: EpollConn<S>[>..] = [];
    var open = 0;
    // Set when accepting stopped before the backlog was empty: at cfg.max_conns,
    // or at the fd limit (EMFILE). The listener's edge has passed, so the
    // loop retries until the backlog is empty, and the waiting clients keep
    // their place in it.
    var paused = false;
    var now = net_clock_ms();
    var next_sweep = now + 1000;
    // On the heap: as a 112-byte array in the loop's frame, it cost the
    // io_uring loop 10-25 user instructions per request.
    var common: u8[>..] = [];
    var date_s: i64 = -1;
    var events: PollEvent[256] = [PollEvent { events: 0, tag: 0 }; 256];
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
            let fd = net_accept(lfd, NONBLOCK);
            if fd == -EAGAIN {
                paused = false;
                return;
            }
            if fd == -EINTR || fd == -ECONNABORTED { continue; }
            guard fd >= 0 else {
                // EMFILE, ENFILE, or out of memory: try again later.
                if !retry { report(Error { call: "accept", code: -fd }); }
                return;
            }
            let i = conns.alloc_index(EpollConn<S> { fd: fd, deadline: now + cfg.request_ms, .. });
            let r = net_epoll_ctl(ep, EPOLL_CTL_ADD, fd, EPOLLIN | EPOLLRDHUP | EPOLLET, i as u64);
            if r < 0 {
                report(Error { call: "epoll_ctl", code: -r });
                net_close(fd);
                conns[i].fd = -1;
                conns.free(i);
                continue;
            }
            open++;
        }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        abandon(c, H);
        net_close(c.fd);
        c.fd = -1;
        if c.held.len > 0 { spill.free_slice(c.held); }
        if c.out.len > 0 { spill.free_slice(c.out); }
        conns.free(i);
        open--;
    }

    // Moves a connection on as far as its socket allows, in the worker's
    // buffers, and keeps what's left over in spill. hup is whether the event
    // reported the client's side closed. False when the connection is done.
    fn drive(c: EpollConn<S>&, hup: bool) -> bool {
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
        let out: u32 = if want { EPOLLOUT } else { 0 };
        let r = net_epoll_ctl(ep, EPOLL_CTL_MOD, c.fd, EPOLLIN | out | EPOLLRDHUP | EPOLLET, i as u64);
        if r < 0 {
            report(Error { call: "epoll_ctl", code: -r });
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
    fn advance(c: EpollConn<S>&, hup: bool) -> bool {
        var progress = false;
        var drained = false;
        loop {
            var full = false;
            if c.state == OPEN && (rlen > 0 || c.x.stream.open && c.x.body.place == NO_BODY) {
                let rest, done, f = answer(c, rbuf, rlen, wbuf, common, cfg, fresh, stopping, now, H) { false };
                rlen = rest;
                if done > 0 { progress = true; }
                full = f;
            }
            while woff < wbuf.len {
                let w = net_send(c.fd, wbuf[woff..]);
                if w == -EAGAIN { return wait(c, progress); }
                if w == -EINTR { continue; }
                guard w > 0 else { return false; }   // EPIPE, ECONNRESET: the client left
                woff += w;
                progress = true;
            }
            wbuf.clear();
            woff = 0;
            if c.state == CLOSING {
                net_shutdown(c.fd, SHUT_WR);
                c.state = DRAINING;
                c.deadline = now + cfg.linger_ms;
            }
            if full { continue; }
            if drained { return wait(c, progress); }
            // answer leaves rbuf full only to refuse the request with 431 or
            // 413, so an OPEN connection always has room to read into.
            if rlen == 0 { c.x.since = now; }
            let room = if c.state == DRAINING { rbuf.len } else { rbuf.len - rlen };
            let r = if c.state == DRAINING { net_recv(c.fd, rbuf) }
                    else { net_recv(c.fd, rbuf[rlen..]) };
            if r == -EAGAIN { return wait(c, progress); }
            if r == -EINTR { continue; }
            guard r > 0 else { return false; }   // the client closed or reset
            if c.state == OPEN { rlen += r; }
            drained = r < room && !hup;
        }
    }

    // Moves the deadline of a connection that's waiting on its socket.
    // Progress restarts the clock; the first bytes of a request after an
    // idle spell shorten it.
    fn wait(c: EpollConn<S>&, progress: bool) -> bool {
        guard c.state != DRAINING else { return true; }
        let writing = woff < wbuf.len;
        let idle = rlen == 0 && c.x.body.place == NO_BODY && !c.x.stream.open && !writing;
        if progress { c.deadline = now + (if idle { cfg.idle_ms } else { busy_ms(c, writing, cfg) }); }
        else if !idle { c.deadline = min(c.deadline, now + busy_ms(c, writing, cfg)); }
        return true;
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is sent a 408 first, if its socket takes it, and then
    // shut down and drained as any refusal is.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now { continue; }
            if owes_408(c) {
                wbuf.clear();
                refuse(wbuf, 408, common);
                let sent = net_send(c.fd, wbuf) == wbuf.len;
                wbuf.clear();
                if sent {
                    if c.held.len > 0 {
                        spill.free_slice(c.held);
                        c.held = c.held[..0];
                    }
                    net_shutdown(c.fd, SHUT_WR);
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
    // Closes the listener and the connections between requests, and gives
    // the rest cfg.grace_ms to finish.
    fn begin_stop() {
        stopping = true;
        stop_by = now + cfg.grace_ms;
        net_close(lfd);
        lfd = -1;
        paused = false;
        for i in conns.len {
            let c .= conns[i];
            if c.fd >= 0 && c.state == OPEN && idle(c) && c.out.len == 0 { close_conn(i); }
        }
    }

    var hot = false;
    var failed = Error { call: "", code: 0 };
    loop {
        // A wait ends within a second, for a stop, the sweep, and a paused
        // accept's retry.
        let timeout: i32 = if hot { 0 } else { 1000 };
        let n = net_epoll_wait(ep, events, timeout);
        if n == -EINTR { continue; }
        guard n >= 0 else {
            failed = Error { call: "epoll_wait", code: -n };
            break;
        }
        hot = n > 0;
        now = net_clock_ms();
        let t = net_time_s();
        if t != date_s {
            common.clear();
            common_fields(common, cfg.server, t);
            date_s = t;
        }
        for ev in events[..n] {
            if ev.tag == EPOLL_LISTENER {
                accept_all();
                continue;
            }
            let i = ev.tag as i64;
            if !drive(conns[i], ev.events & (EPOLLRDHUP | EPOLLHUP | EPOLLERR) != 0) || !watch(i) {
                close_conn(i);
            }
        }
        if now >= next_sweep {
            sweep();
            next_sweep = now + 1000;
        }
        if paused { accept_all(); }
        if !stopping && stops() != started { begin_stop(); }
        if stopping && (open == 0 || now >= stop_by) { break; }
    }
    for i in conns.len {
        if conns[i].fd >= 0 { close_conn(i); }
    }
    net_close(ep);
    if lfd >= 0 { net_close(lfd); }
    return failed;
}
