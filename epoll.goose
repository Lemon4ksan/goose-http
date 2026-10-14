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
// The waker's tag (net_waker): mail in the box, or a stop.
let EPOLL_WAKE: u64 = 0xFFFFFFFFFFFFFFFE;

// Between events, a connection holds only what its socket left over: the
// start of a request not yet whole, and responses the socket didn't take.
// Both are runs of the worker's spill pool, empty almost always.
struct EpollConn<S> {
    fd: i32,            // -1 while the slot is free
    state: u8,
    watch_out: bool,    // OUT is registered: set while out holds bytes
    ready: bool,        // stopped reading at cfg.max_read, with the socket not empty
    listed: bool,       // in turns
    deadline: i64,      // the time after which the sweep closes it
    x: Exchange<S>,     // the request in progress past its handler's REQUEST call
    held: u8[:],        // received and not yet answered
    out: u8[:],         // still to send
}

// Serves HTTP as cfg says, answering each request with H, until a call fails
// or stop ends it, and returns its error, with every socket it opened
// closed. On Windows it fails at once with ENOSYS.
fn serve_epoll<H>(cfg: Config) -> Error {
    return serve_epoll(cfg, false) { ev, st, out => whole(ev, out, H); };
}

// serve_epoll(cfg), with a handler H that's called for each Event of a
// request, with the request's state, which starts as fresh.
fn serve_epoll<S, H>(cfg: Config, fresh: S) -> Error {
    net_worker_start();
    guard is_field_value(cfg.server) else { return Error { call: "server", code: EINVAL }; }
    var lfd, listening = listen_on(cfg);
    guard lfd >= 0 else { return listening; }
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
    let waker = net_waker(ep, EPOLL_WAKE);
    guard waker >= 0 else {
        net_close(ep);
        net_close(lfd);
        return Error { call: "waker", code: -waker };
    }
    net_stop_watch(waker);
    let box, opened = open_waiting(cfg, waker);
    guard opened.code == 0 else {
        close_waiting(box, waker);
        net_close(ep);
        net_close(lfd);
        return opened;
    }
    let waiting = box.handle.slot >= 0;
    var timers = timer_table(if waiting { cfg.max_waiting } else { 0 });
    // Exchanges owed TIMEOUT for want of a timer, by their keys.
    var overdue: u64[>..] = [];
    // Connections that stopped at cfg.max_read, by slot, for another turn.
    var turns: u64[>..] = [];
    var generation: u64 = 0;
    let nothing = Request { .. };
    let none = Event { kind: NO_EVENT, req: nothing, data: "", whole: false, trailers: "" };

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
    // Whether files go out with sendfile: on Linux and macOS, whose shims
    // refuse fd -1 with EBADF.
    let direct = net_sendfile(-1, -1, 0, 0) != -ENOSYS;
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
            conns[i].x.stream.direct = direct;
            let r = net_epoll_ctl(ep, EPOLL_CTL_ADD, fd, EPOLLIN | EPOLLRDHUP | EPOLLET, i as u64);
            if r < 0 {
                report(Error { call: "epoll_ctl", code: -r });
                net_close(fd);
                conns[i].fd = -1;
                conns.free(i);
                continue;
            }
            if waiting {
                generation = generation % 0xFFFFFF + 1;
                conns[i].x.stream.later = MailAddress { box: box.handle, key: later_base(i, generation) };
            }
            open++;
        }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        abandon(c, H);
        cancel(timers, c.x.timer);
        net_close(c.fd);
        c.fd = -1;
        if c.x.stream.file >= 0 {
            net_file_close(c.x.stream.file);
            c.x.stream.file = -1;
        }
        if c.held.len > 0 { spill.free_slice(c.held); }
        if c.out.len > 0 { spill.free_slice(c.out); }
        conns.free(i);
        open--;
    }

    // Moves a connection on as far as its socket allows, in the worker's
    // buffers, and keeps what's left over in spill. hup is whether the event
    // reported the client's side closed, and wake goes to answer first
    // (answer). False when the connection is done.
    fn drive(c: EpollConn<S>&, hup: bool, wake: const Event&) -> bool {
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
        guard advance(c, hup, wake) else { return false; }
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
        let want = c.out.len > 0 || c.x.stream.file >= 0;
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
    // empty, the connection is done, which is false, or it has read
    // cfg.max_read bytes, which sets ready for another turn (go). A recv that
    // filled less than it was given emptied the socket, and the next byte to
    // arrive raises a new event, so it isn't followed by a recv that would
    // block, unless hup: a close that arrived with the last bytes raises none.
    // While the exchange waits, it stops reading once rbuf is full.
    fn advance(c: EpollConn<S>&, hup: bool, wake: const Event&) -> bool {
        var progress = false;
        var drained = false;
        var got = 0;
        c.ready = false;
        var ev = wake;
        loop {
            var full = false;
            if c.state == OPEN && c.x.stream.file < 0 && (rlen > 0 || c.x.stream.open && c.x.body == BodyReader.None || ev.kind != NO_EVENT) {
                let rest, done, f = answer(c, rbuf, rlen, wbuf, common, cfg, fresh, stopping, now, ev, H) { false };
                ev.kind = NO_EVENT;
                rlen = rest;
                if done > 0 { progress = true; }
                full = f;
                if c.x.stream.rearm && start_wait(c, timers, now) { overdue.push(c.x.stream.later.key); }
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
            while c.x.stream.file >= 0 {
                let s .= c.x.stream;
                let w = net_sendfile(c.fd, s.file, s.file_off, s.file_left);
                if w == -EAGAIN { return wait(c, progress); }
                if w == -EINTR { continue; }
                // The client left, or the file ended short of what the head
                // promised.
                guard w > 0 else { return false; }
                s.file_off += w;
                s.file_left -= w;
                progress = true;
                if s.file_left == 0 {
                    net_file_close(s.file);
                    s.file = -1;
                    full = true;    // to answer what arrived meanwhile
                }
            }
            if c.state == CLOSING {
                net_shutdown(c.fd, SHUT_WR);
                c.state = DRAINING;
                c.deadline = now + cfg.linger_ms;
            }
            if full { continue; }
            if drained { return wait(c, progress); }
            if cfg.max_read > 0 && got >= cfg.max_read {
                c.ready = true;
                return wait(c, progress);
            }
            // answer leaves rbuf full only to refuse the request with 431 or
            // 413, so an OPEN connection always has room to read into.
            if rlen == 0 { c.x.since = now; }
            let room = if c.state == DRAINING { rbuf.len } else { rbuf.len - rlen };
            if room == 0 && c.x.stream.waiting { return wait(c, progress); }
            let r = if c.state == DRAINING { net_recv(c.fd, rbuf) }
                    else { net_recv(c.fd, rbuf[rlen..]) };
            if r == -EAGAIN { return wait(c, progress); }
            if r == -EINTR { continue; }
            guard r > 0 else { return false; }   // the client closed or reset
            got += r;
            if c.state == OPEN { rlen += r; }
            drained = r < room && !hup;
        }
    }

    // Moves the deadline of a connection that's waiting on its socket.
    // Progress restarts the clock; the first bytes of a request after an
    // idle spell shorten it.
    fn wait(c: EpollConn<S>&, progress: bool) -> bool {
        guard c.state != DRAINING else { return true; }
        let writing = woff < wbuf.len || c.x.stream.file >= 0;
        let idle = rlen == 0 && c.x.body == BodyReader.None && !c.x.stream.open && !c.x.stream.waiting && !writing;
        if progress { c.deadline = now + (if idle { cfg.idle_ms } else { busy_ms(c, writing, cfg) }); }
        else if !idle { c.deadline = min(c.deadline, now + busy_ms(c, writing, cfg)); }
        return true;
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is sent a 408 first, if its socket takes it, and then
    // shut down and drained as any refusal is. An exchange that waits has its
    // own time limit instead.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now || c.x.stream.waiting { continue; }
            if owes_408(c, c.out.len > 0 || c.x.stream.file >= 0) {
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
            if c.fd >= 0 && c.state == OPEN && idle(c) && c.out.len == 0 && c.x.stream.file < 0 { close_conn(i); }
            else if c.fd >= 0 && c.x.stream.waiting { c.x.keep_alive = false; }
        }
    }

    // Goes on with the exchange of connection i, which waited, with ev, its
    // WAKE or TIMEOUT, and then with what it holds.
    fn resume(i: i64, ev: const Event&) { go(i, false, ev); }

    // Drives connection i, and lists it for another turn if it stopped at
    // cfg.max_read: its socket raises no new event until the client sends
    // more, which it may not while the socket is full.
    fn go(i: i64, hup: bool, ev: const Event&) {
        guard drive(conns[i], hup, ev) && watch(i) else {
            close_conn(i);
            return;
        }
        let c .= conns[i];
        if c.ready && !c.listed {
            c.listed = true;
            turns.push(i as u64);
        }
    }

    // A message to key, for the exchange that waits for it, if any.
    fn delivered(key: u64, tag: i32, bytes: const u8[:]) {
        let i = later_slot(key);
        guard i < conns.len && waits_for(conns[i], key) else { return; }
        cancel(timers, conns[i].x.timer);
        conns[i].x.stream.waiting = false;
        let ev = Event { kind: WAKE, req: nothing, data: bytes, whole: false, trailers: "", tag: tag };
        resume(i, ev);
    }

    // The exchange of key, which waited, or wanted to and found no timer,
    // is owed TIMEOUT.
    fn timed_out(key: u64, waited: bool) {
        let i = later_slot(key);
        guard i < conns.len else { return; }
        let c .= conns[i];
        guard c.fd >= 0 && c.state == OPEN && c.x.stream.later.key == key && c.x.stream.waiting == waited else { return; }
        c.x.stream.waiting = false;
        retire(c.x.stream);
        let ev = Event { kind: TIMEOUT, req: nothing, data: "", whole: false, trailers: "" };
        resume(i, ev);
    }

    var hot = false;
    var failed = Error { call: "", code: 0 };
    loop {
        // A wait ends within a second, for the sweep and a paused accept's
        // retry, or at the next timer; the waker ends it for mail and a stop.
        let timeout: i32 = if hot || overdue.len > 0 || turns.len > 0 { 0 } else { wait_for(timers, now) };
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
            if ev.tag == EPOLL_WAKE {
                if waiting { mail_take(box) { key, tag, bytes => delivered(key, tag, bytes); }; }
                continue;
            }
            let i = ev.tag as i64;
            // A WAKE earlier in the batch may have closed it.
            if conns[i].fd < 0 { continue; }
            go(i, ev.events & (EPOLLRDHUP | EPOLLHUP | EPOLLERR) != 0, none);
        }
        // One more turn each for the connections listed so far, after this
        // pass's events. A slot that closed and opened again since has ready
        // unset. hup, since a close may have come with the bytes left.
        let listed = turns.len;
        for k in listed {
            let i = turns[k] as i64;
            conns[i].listed = false;
            if conns[i].fd >= 0 && conns[i].ready { go(i, true, none); }
        }
        drop_first(turns, listed);
        if waiting {
            expire(timers, now) { key => timed_out(key, true); };
            let owed = overdue.len;
            for k in owed { timed_out(overdue[k], false); }
            drop_first(overdue, owed);
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
    close_waiting(box, waker);
    net_close(ep);
    if lfd >= 0 { net_close(lfd); }
    return failed;
}
