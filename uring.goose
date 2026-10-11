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

// Between completions, a connection holds what it couldn't answer yet and
// the responses its send in flight left waiting, as runs of the worker's
// spill pool.
struct RingConn {
    fd: i32,            // -1 while the slot is free
    tag: u64,
    state: u8,
    sending: bool,      // a send is in flight
    reading: bool,      // its multishot receive is queued
    stalled: bool,      // stopped reading at cfg.max_queued, with held to answer
    deadline: i64,      // the time after which the sweep closes it
    discard: i64,       // request body bytes still to drop
    held: u8[:],        // received and not yet answered
    out: u8[:],         // answered, behind the send in flight
}

// Serves HTTP as cfg says, answering each request with H, until a call fails,
// and returns its error, with every socket it opened closed. The ring stays:
// closing one with requests in flight is task 013's graceful shutdown.
fn serve<H>(cfg: Config) -> Error {
    let ip, ok = ipv4(cfg.address);
    guard ok else { return Error { call: "address", code: EINVAL }; }
    let lfd = net_listen(ip, cfg.port, cfg.backlog, NONBLOCK | REUSEPORT);
    guard lfd >= 0 else { return Error { call: "listen", code: -lfd }; }
    let r = ring_create(cfg.ring_entries, cfg.ring_buffers, cfg.ring_buffer_size,
                        if cfg.emulate_ring { RING_EMULATE } else { 0 });
    guard r >= 0 else {
        net_close(lfd);
        return Error { call: "io_uring", code: -r };
    }
    ring_accept(r, lfd, RING_LISTENER);

    reusable[] var spill: u8[>..] = [];
    reusable var conns: RingConn[>..] = [];
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
    var date: u8[..32] = [];
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
        guard open < cfg.max_conns else {
            net_close(fd);
            return;
        }
        // A tag fits in 62 bits, and a free slot's is 0.
        generation = generation % 0x3FFFFFFF + 1;
        let i = conns.alloc_index(RingConn { fd: fd, reading: true, deadline: now + cfg.request_ms, .. });
        let c .= conns[i];
        c.tag = (generation << 32) | (i as u64);
        ring_recv(r, fd, c.tag);
        open++;
        if open == cfg.max_conns && accepting { ring_cancel(r, RING_LISTENER); }
    }

    fn close_conn(i: i64) {
        let c .= conns[i];
        ring_close(r, c.fd);
        c.fd = -1;
        c.tag = 0;
        if c.held.len > 0 { spill.free_slice(c.held); }
        if c.out.len > 0 { spill.free_slice(c.out); }
        conns.free(i);
        open--;
        closed = true;
    }

    fn blocked(c: RingConn&) -> bool { c.out.len >= cfg.max_queued }

    // Queues wbuf to send, or keeps it behind the send in flight: one send
    // at a time keeps a connection's responses in order.
    fn flush(c: RingConn&) {
        guard wbuf.len > 0 else { return; }
        if c.sending {
            let m = c.out.len;
            c.out = spill.realloc_slice(c.out, m + wbuf.len);
            copy_into(c.out[m..], wbuf);
        } else {
            let e = ring_send(r, c.fd, c.tag, wbuf);
            guard e >= 0 else { return Error { call: "send", code: -e } from spin; }
            c.sending = true;
        }
        wbuf.clear();
    }

    // Answers n received bytes after rbuf[..rlen]: those of provided buffer
    // buf, or of src when buf is -1. rbuf takes them as it has room. If the
    // connection reaches cfg.max_queued, it stops reading and holds the rest.
    fn pump(c: RingConn&, buf: i32, src: const u8[:], n: i64) {
        var off: i64 = 0;
        while off < n {
            let k = min(n - off, rbuf.len - rlen);
            if buf >= 0 { ring_take(r, buf, off, rbuf[rlen..rlen + k]); }
            else { copy_into(rbuf[rlen..rlen + k], src[off..off + k]); }
            rlen += k;
            off += k;
            let rest, done, full = answer(c, rbuf, rlen, wbuf, date, cfg, H) {
                flush(c);
                true
            };
            rlen = rest;
            if done > 0 { progress = true; }
            if c.state != OPEN {
                rlen = 0;
                break;
            }
            if blocked(c) {
                c.held = spill.alloc_slice(rlen + n - off);
                copy_into(c.held[..rlen], rbuf[..rlen]);
                if buf >= 0 { ring_take(r, buf, off, c.held[rlen..]); }
                else { copy_into(c.held[rlen..], src[off..n]); }
                rlen = 0;
                c.stalled = true;
                if c.reading { ring_cancel(r, c.tag); }
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
    fn received(c: RingConn&, cq: Completion) -> bool {
        if !cq.more { c.reading = false; }
        if cq.res > 0 {
            let n = cq.res as i64;
            // A connection that isn't OPEN drops what arrives.
            if c.state != OPEN {
            } else if c.stalled {
                let m = c.held.len;
                c.held = spill.realloc_slice(c.held, m + n);
                ring_take(r, cq.buf, 0, c.held[m..]);
            } else {
                rlen = c.held.len;
                if rlen > 0 {
                    copy_into(rbuf[..rlen], c.held);
                    spill.free_slice(c.held);
                    c.held = c.held[..0];
                }
                pump(c, cq.buf, "", n);
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
    fn sent(c: RingConn&, res: i32) -> bool {
        c.sending = false;
        guard res >= 0 else { return false; }   // EPIPE, ECONNRESET: the client left
        progress = true;
        if c.out.len > 0 {
            let e = ring_send(r, c.fd, c.tag, c.out);
            guard e >= 0 else { return Error { call: "send", code: -e } from spin; }
            c.sending = true;
            spill.free_slice(c.out);
            c.out = c.out[..0];
        } else if c.state == CLOSING {
            net_shutdown(c.fd, SHUT_WR);
            c.state = DRAINING;
            c.deadline = now + cfg.linger_ms;
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
            ring_recv(r, c.fd, c.tag);
            c.reading = true;
        }
        return true;
    }

    // Moves the deadline of a connection after a completion. Progress
    // restarts the clock; the first bytes of a request after an idle spell
    // shorten it.
    fn touch(c: RingConn&) {
        guard c.state != DRAINING else { return; }
        let idle = c.held.len == 0 && c.discard == 0 && !c.sending;
        if progress { c.deadline = now + (if idle { cfg.idle_ms } else { cfg.request_ms }); }
        else if !idle { c.deadline = min(c.deadline, now + cfg.request_ms); }
    }

    // Closes the connections past their deadline. One still waiting for the
    // rest of a request is refused with a 408 instead, which closes it as
    // any refusal does; cfg.linger_ms bounds the send. A close aborts a send in
    // flight on Windows, and io_uring's cancels one that hasn't gone out.
    fn sweep() {
        for i in conns.len {
            let c .= conns[i];
            if c.fd < 0 || c.deadline > now { continue; }
            if c.state == OPEN && c.held.len > 0 && !c.sending {
                wbuf.clear();
                refuse(wbuf, 408, date);
                flush(c);
                c.state = CLOSING;
                c.deadline = now + cfg.linger_ms;
                continue;
            }
            close_conn(i);
        }
    }

    // The loop, until a call fails: then the error is returned from here.
    fn spin() -> Error {
        loop {
            // Open connections need the sweep, and a stopped accept its retry.
            let timeout: i32 = if open > 0 || !accepting { 1000 } else { -1 };
            let n = ring_wait(r, done, timeout);
            if n == -EINTR { continue; }
            guard n >= 0 else { return Error { call: "wait", code: -n }; }
            now = net_clock_ms();
            let t = net_time_s();
            if t != date_s {
                date.clear();
                format_date(date, t);
                date_s = t;
            }
            closed = false;
            for cq in done[..n] {
                if cq.tag == RING_LISTENER {
                    accepted(cq);
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
            let tick = now >= next_sweep;
            if tick {
                sweep();
                next_sweep = now + 1000;
            }
            if !accepting && open < cfg.max_conns && (!accept_failed || closed || tick) {
                ring_accept(r, lfd, RING_LISTENER);
                accepting = true;
            }
        }
    }

    let failed = spin();
    for c in conns {
        if c.fd >= 0 { net_close(c.fd); }
    }
    net_close(lfd);
    return failed;
}
