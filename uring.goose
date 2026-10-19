// serve, the completion loop: each worker has its own ring (io_uring on Linux,
// a completion port on Windows, an emulation over epoll or kqueue elsewhere), and its own SO_REUSEPORT listener on Linux
// (net_listen), and nothing else is shared between workers. A multishot
// accept takes the listener's connections, and a multishot receive per
// connection fills the ring's provided buffers. The sends a pass over the
// completions queues go to the kernel together, in the next wait.
namespace http;

import std;
import os;
import sys;
import message;
import ring;

// A request's tag: the connection's slot in the low 32 bits and a
// generation above, so a completion that arrives after its connection
// closed isn't taken for one of the slot's next connection. The listener's
// slot is one no connection gets.
let RING_LISTENER: u64 = 0xFFFFFFFF;
// The tag of the waker's completions (ring_waker): mail in the box, or a stop.
let RING_WAKE: u64 = 0xFFFFFFFE;

// Between completions, a connection holds what it couldn't answer yet as a
// run of the worker's spill pool. Its responses wait in the ring, which
// sends them in order.
struct RingConn<S> {
    fd: i32,            // -1 while the slot is free
    tag: u64,
    state: u8,
    queued: i64,        // bytes given to ring_send and not yet sent
    reading: bool,      // its multishot receive is queued
    stalled: bool,      // stopped reading at cfg.max_queued, with held to answer
    deadline: i64,      // the time after which the sweep closes it
    x: Exchange<S>,     // the request in progress past its handler's REQUEST call
    held: u8[:],        // received and not yet answered
}

// Serves HTTP as cfg says, answering each request with H, until a call fails
// or stop ends it, and returns its error, with every socket it opened
// closed.
fn serve<H>(cfg: Config) -> Error {
    return serve(cfg, false) { ev, st, out => whole(ev, out, H); };
}

// serve(cfg), with a handler H that's called for each Event of a request,
// with the request's state, which starts as fresh.
fn serve<S, H>(cfg: Config, fresh: S) -> Error {
    net_worker_start();
    guard is_field_value(cfg.server) else { return Error { call: "server", code: EINVAL }; }
    var lfd, listening = listen_on(cfg);
    guard lfd >= 0 else { return listening; }
    let r = ring_create(cfg.ring_entries, cfg.ring_buffers, cfg.ring_buffer_size,
                        if cfg.emulate_ring { RING_EMULATE } else { 0 });
    guard r >= 0 else {
        net_close(lfd);
        return Error { call: "io_uring", code: -r };
    }
    let waker = ring_waker(r, RING_WAKE);
    guard waker >= 0 else {
        net_close(lfd);
        ring_destroy(r);
        return Error { call: "waker", code: -waker };
    }
    net_stop_watch(waker);
    let box, opened = open_waiting(cfg, waker);
    guard opened.code == 0 else {
        close_waiting(box, waker);
        net_close(lfd);
        ring_destroy(r);
        return opened;
    }
    let waiting = box.handle.slot >= 0;
    var timers = timer_table(if waiting { cfg.max_waiting } else { 0 });
    // Exchanges owed TIMEOUT for want of a timer, by their keys.
    var overdue: u64[>..] = [];
    let nothing = Request { .. };
    let none = Event { kind: NO_EVENT, req: nothing, data: "", whole: false, trailers: "" };
    ring_accept(r, lfd, RING_LISTENER);

    let started = stops();
    var stopping = false;
    var stop_by: i64 = 0;
    reusable[] var spill: u8[>..] = [];
    reusable var conns: RingConn<S>[>..] = [];
    var open = 0;
    var generation: u64 = 0;
    // Whether the listener's multishot accept is queued. It ends when the
    // worker reaches cfg.max_conns, and on an error such as EMFILE. Then it's
    // queued again once a connection closes, or at the next sweep.
    var accepting = true;
    var accept_failed = false;
    var closed = false;
    var now = net_clock_ms();
    var next_sweep = now + 1000;
    // On the heap: as a 112-byte array in the loop's frame, it cost the
    // io_uring loop 10-25 user instructions per request.
    var common: u8[>..] = [];
    var date_s: i64 = -1;
    var done: Completion[256] =
        [Completion { tag: 0, res: 0, buf: -1, more: false, send: false }; 256];
    // The driven connection's bytes: rbuf[..rlen] is received and not yet
    // answered, and wbuf is answered and not yet queued to send.
    var rbuf: u8[>..] = [];
    rbuf.resize(cfg.max_head, 0);
    var rlen = 0;
    var wbuf: u8[>..] = [];
    // Whether the driven connection answered a request or sent a response.
    var progress = false;

    fn accepted(cq: Completion) {
        if !cq.more { accepting = false; }
        let fd = cq.res;
        if fd < 0 {
            // EMFILE, ENFILE, or out of memory: try again later.
            if fd != -ECANCELED && !accept_failed { report(Error { call: "accept", code: -fd }); }
            accept_failed = fd != -ECANCELED;
            return;
        }
        accept_failed = false;
        guard open < cfg.max_conns && !stopping else {
            net_close(fd);
            return;
        }
        // A tag fits in 62 bits, and a free slot's is 0.
        generation = generation % 0x3FFFFFFF + 1;
        let i = conns.alloc_index(RingConn<S> { fd: fd, reading: true, deadline: now + cfg.request_ms, .. });
        let c .= conns[i];
        c.tag = (generation << 32) | (i as u64);
        c.x.stream.direct = true;
        c.x.stream.later = MailAddress { box: box.handle, key: later_base(i, generation) };
        ring_recv(r, fd, c.tag);
        open++;
        if open == cfg.max_conns && accepting { ring_cancel(r, RING_LISTENER); }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        abandon(c, H);
        cancel(timers, c.x.timer);
        ring_close(r, c.fd);
        c.fd = -1;
        if c.x.stream.file >= 0 {
            net_file_close(c.x.stream.file);
            c.x.stream.file = -1;
        }
        c.tag = 0;
        if c.held.len > 0 { spill.free_slice(c.held); }
        conns.free(i);
        open--;
        closed = true;
    }

    fn blocked(c: RingConn<S>&) -> bool { c.queued >= cfg.max_queued }

    // Queues wbuf to send, behind the connection's sends before it.
    fn flush(c: RingConn<S>&) {
        guard wbuf.len > 0 else { return; }
        let e = ring_send(r, c.fd, c.tag, wbuf);
        guard e >= 0 else { return Error { call: "send", code: -e } from spin; }
        c.queued += wbuf.len;
        wbuf.clear();
    }

    // Queues wbuf and then the file send_file gave the exchange
    // (Stream.direct), which the ring then owns.
    fn send_file(c: RingConn<S>&) {
        flush(c);
        let s .= c.x.stream;
        let e = ring_send_file(r, c.fd, c.tag, s.file, s.file_off, s.file_left);
        s.file = -1;
        guard e >= 0 else { return Error { call: "send", code: -e } from spin; }
        c.queued += s.file_left;
        s.file_left = 0;
    }

    // Answers n received bytes after rbuf[..rlen]: those of provided buffer
    // buf, or of src when buf is -1. rbuf takes them as it has room. If the
    // connection reaches cfg.max_queued, it stops reading and holds the rest;
    // while its exchange waits, unless upgraded (holds_input), it holds the
    // rest, and stops reading once it holds rbuf's worth. wake goes to answer
    // first (answer).
    fn pump(c: RingConn<S>&, buf: i32, src: const u8[:], n: i64, wake: const Event&) {
        // At least once, with no bytes, to go on with a response.
        var off: i64 = 0;
        var ev = wake;
        loop {
            let k = min(n - off, rbuf.len - rlen);
            if buf >= 0 { ring_take(r, buf, off, rbuf[rlen..rlen + k]); }
            else { copy_into(rbuf[rlen..rlen + k], src[off..off + k]); }
            rlen += k;
            off += k;
            let rest, done, full = answer(c, rbuf, rlen, wbuf, common, cfg, fresh, stopping, now, ev, H) {
                flush(c);
                !blocked(c)
            };
            ev.kind = NO_EVENT;
            rlen = rest;
            if done > 0 { progress = true; }
            // The ring sends the file in order, so answering goes on.
            if c.x.stream.file >= 0 {
                send_file(c);
                if c.state == OPEN && !blocked(c) && !holds_input(c.x) { continue; }
            }
            if c.state != OPEN {
                rlen = 0;
                break;
            }
            if blocked(c) || holds_input(c.x) {
                c.held = spill.alloc_slice(rlen + n - off);
                copy_into(c.held[..rlen], rbuf[..rlen]);
                if buf >= 0 { ring_take(r, buf, off, c.held[rlen..]); }
                else { copy_into(c.held[rlen..], src[off..n]); }
                rlen = 0;
                if blocked(c) || c.held.len >= rbuf.len {
                    c.stalled = true;
                    if c.reading { ring_cancel(r, c.tag); }
                }
                break;
            }
            if off >= n { break; }
        }
        if rlen > 0 {
            c.held = spill.alloc_slice(rlen);
            copy_into(c.held, rbuf[..rlen]);
        }
        flush(c);
        if c.x.stream.rearm && start_wait(c, timers, now) { overdue.push(c.x.stream.later.key); }
    }

    // Goes on with c's exchange, which waited, with ev, its WAKE or TIMEOUT,
    // and then with what c holds.
    fn resume(c: RingConn<S>&, ev: const Event&) {
        progress = false;
        c.stalled = false;
        let src = c.held;
        c.held = c.held[..0];
        rlen = 0;
        pump(c, -1, src, src.len, ev);
        if src.len > 0 { spill.free_slice(src); }
        if c.state != DRAINING && !c.reading && !c.stalled {
            ring_recv(r, c.fd, c.tag);
            c.reading = true;
        }
        touch(c);
    }

    // A message to key, for the exchange that waits for it, if any.
    fn delivered(key: u64, tag: i32, bytes: const u8[:]) {
        let i = later_slot(key);
        guard i < conns.len && waits_for(conns[i], key) else { return; }
        let c .= conns[i];
        cancel(timers, c.x.timer);
        c.x.stream.waiting = false;
        let ev = Event { kind: WAKE, req: nothing, data: bytes, whole: false, trailers: "", tag: tag };
        resume(c, ev);
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
        resume(c, ev);
    }

    // A receive's completion. False when the connection is done.
    fn received(c: RingConn<S>&, cq: Completion) -> bool {
        if !cq.more { c.reading = false; }
        if cq.res > 0 {
            let n = cq.res as i64;
            // A connection that isn't OPEN drops what arrives.
            if c.state != OPEN {
            } else if c.stalled || holds_input(c.x) {
                let m = c.held.len;
                if m == 0 { c.x.since = now; }
                c.held = if m == 0 { spill.alloc_slice(n) } else { spill.realloc_slice(c.held, m + n) };
                ring_take(r, cq.buf, 0, c.held[m..]);
                if !c.stalled && c.held.len >= rbuf.len {
                    c.stalled = true;
                    if c.reading { ring_cancel(r, c.tag); }
                }
            } else {
                rlen = c.held.len;
                if rlen == 0 { c.x.since = now; }
                if rlen > 0 {
                    copy_into(rbuf[..rlen], c.held);
                    spill.free_slice(c.held);
                    c.held = c.held[..0];
                }
                pump(c, cq.buf, "", n, none);
            }
            ring_give(r, cq.buf);
        } else if cq.res == 0 || (cq.res != -ENOBUFS && cq.res != -ECANCELED) {
            return false;   // the client closed or reset
        }
        if !c.reading && !c.stalled {
            ring_recv(r, c.fd, c.tag);
            c.reading = true;
        }
        return true;
    }

    // A send's completion. False when the connection is done.
    fn sent(c: RingConn<S>&, res: i32) -> bool {
        guard res >= 0 else { return false; }   // EPIPE, ECONNRESET: the client left
        c.queued -= res as i64;
        progress = true;
        if c.queued == 0 && c.state == CLOSING {
            net_shutdown(c.fd, SHUT_WR);
            c.state = DRAINING;
            c.deadline = now + cfg.linger_ms;
        }
        if c.stalled && !blocked(c) {
            c.stalled = false;
            let src = c.held;
            c.held = c.held[..0];
            rlen = 0;
            pump(c, -1, src, src.len, none);
            spill.free_slice(src);
        }
        if !c.reading && !c.stalled {
            ring_recv(r, c.fd, c.tag);
            c.reading = true;
        }
        return true;
    }

    // Moves the deadline of a connection after a completion. Progress
    // restarts the clock; the first bytes of a request after an idle spell
    // shorten it.
    fn touch(c: RingConn<S>&) {
        guard c.state != DRAINING else { return; }
        let sending = c.queued > 0;
        let idle = idle(c) && !sending;
        if progress { c.deadline = now + (if idle { cfg.idle_ms } else { busy_ms(c, sending, cfg) }); }
        else if !idle { c.deadline = min(c.deadline, now + busy_ms(c, sending, cfg)); }
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is refused with a 408 instead, which closes it as
    // any refusal does; cfg.linger_ms bounds the send. A close aborts a send in
    // flight on Windows, and io_uring's cancels one that hasn't gone out.
    // An exchange that waits has its own time limit instead.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now || c.x.stream.waiting { continue; }
            if owes_408(c, c.queued > 0) {
                wbuf.clear();
                refuse(wbuf, 408, common);
                flush(c);
                c.state = CLOSING;
                c.deadline = now + cfg.linger_ms;
                continue;
            }
            close_conn(i);
        }
    }

    // Closes the listener and the connections between requests, and gives
    // the rest cfg.grace_ms to finish. The listener's accept holds it open
    // until the accept is cancelled.
    fn begin_stop() {
        stopping = true;
        stop_by = now + cfg.grace_ms;
        if accepting { ring_cancel(r, RING_LISTENER); }
        net_close(lfd);
        lfd = -1;
        for i in conns.len {
            let c .= conns[i];
            if c.fd >= 0 && c.state == OPEN && idle(c) && c.queued == 0 { close_conn(i); }
            else if c.fd >= 0 && c.x.stream.waiting { c.x.keep_alive = false; }
        }
    }

    // The loop, until a call fails or a stop ends it: then the error, or one
    // with code 0, is returned from here.
    fn spin() -> Error {
        loop {
            // A wait ends within a second, for the sweep and a stopped
            // accept's retry, or at the next timer; the waker ends it for
            // mail and a stop.
            let n = ring_wait(r, done, if overdue.len > 0 { 0 } else { wait_for(timers, now) });
            if n == -EINTR { continue; }
            guard n >= 0 else { return Error { call: "wait", code: -n }; }
            now = net_clock_ms();
            let t = net_time_s();
            if t != date_s {
                common.clear();
                common_fields(common, cfg.server, t);
                date_s = t;
            }
            closed = false;
            for cq in done[..n] {
                if cq.tag == RING_LISTENER {
                    accepted(cq);
                    continue;
                }
                if cq.tag == RING_WAKE {                    if waiting { mail_take(box) { key, tag, bytes => delivered(key, tag, bytes); }; }
                    continue;
                }
                let i = (cq.tag & 0xFFFFFFFF) as i64;
                if i >= conns.len || conns[i].tag != cq.tag {
                    // The connection closed after the request was queued.
                    if cq.buf >= 0 { ring_give(r, cq.buf); }
                    continue;
                }
                let c .= conns[i];
                progress = false;
                let ok = if cq.send { sent(c, cq.res) } else { received(c, cq) };
                if ok { touch(c); } else { close_conn(i); }
            }
            if waiting { expire(timers, now) { key => timed_out(key, true); }; }
            // With or without a box: without one, every later is owed its TIMEOUT.
            let owed = overdue.len;
            for k in owed { timed_out(overdue[k], false); }
            drop_first(overdue, owed);
            let tick = now >= next_sweep;
            if tick {
                sweep();
                next_sweep = now + 1000;
            }
            if !accepting && !stopping && open < cfg.max_conns && (!accept_failed || closed || tick) {
                ring_accept(r, lfd, RING_LISTENER);
                accepting = true;
            }
            if !stopping && stops() != started { begin_stop(); }
            if stopping && (open == 0 || now >= stop_by) { return Error { call: "", code: 0 }; }
        }
    }

    let failed = spin();
    for i in conns.len {
        let c .= conns[i];
        if c.fd >= 0 {
            abandon(c, H);
            net_close(c.fd);
        }
    }
    if lfd >= 0 { net_close(lfd); }
    // Submits the closes still queued, then frees the ring, and after it the
    // waker, which io_uring's poll of it holds until then.
    ring_wait(r, done, 0);
    ring_destroy(r);
    close_waiting(box, waker);
    return failed;
}
