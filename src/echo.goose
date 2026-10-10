// Two echo servers that exercise shim/net.h before the HTTP server depends on
// it: a blocking one that serves one client at a time, and a single
// edge-triggered epoll loop.
import os;
import sys;

let BUF_SIZE = 16384;

// Reports a call that failed with -err on stderr.
fn report(what: const u8[:], err) {
    var msg: u8[>..] = [];
    format(msg, what, ": ");
    sys::strerror(-err, msg);
    msg.push('\n');
    write_stderr(msg);
}

// Returns r, or reports it and exits if it's an error.
fn check(what: const u8[:], r) {
    if r < 0 {
        report(what, r);
        exit(1);
    }
    r
}

fn echo_blocking(port: i32) {
    let lfd = check("listen", sys::listen(port, 128, 0));
    print("echo-blocking: listening on ", port);
    var buf: u8[BUF_SIZE] = [0; BUF_SIZE];
    loop {
        let fd = sys::accept(lfd, 0);
        if fd < 0 {
            if fd != -sys::EINTR { report("accept", fd); }
            continue;
        }
        echo_until_closed(fd, buf);
        sys::close(fd);
    }
}

fn echo_until_closed(fd: i32, buf: u8[:]) {
    loop {
        let n = sys::recv(fd, buf);
        if n == -sys::EINTR { continue; }
        guard n > 0 else {
            if n < 0 { report("recv", n); }
            return;
        }
        var off = 0;
        while off < n {
            let w = sys::send(fd, buf[off..n]);
            if w == -sys::EINTR { continue; }
            guard w > 0 else {
                report("send", w);
                return;
            }
            off += w;
        }
    }
}

// A connection of the epoll server: buf[off..len] is received data not yet
// sent back. It reads again only once that is all sent, so a client that
// doesn't read stops being read from.
struct Conn { off: i64, len: i64, buf: u8[BUF_SIZE] }

fn echo_epoll(port: i32) {
    let lfd = check("listen", sys::listen(port, 4096, sys::NONBLOCK));
    let ep = check("epoll_create", sys::epoll_create());
    check("epoll_ctl", sys::epoll_ctl(ep, sys::CTL_ADD, lfd, sys::IN | sys::ET, lfd as u64));
    print("echo-epoll: listening on ", port);

    // Indexed by fd. The kernel hands out the lowest free fd, so the table
    // grows to the most connections open at once.
    var conns: Conn[>..] = [];
    var events: sys::Event[256] = [sys::Event { events: 0, tag: 0 }; 256];
    loop {
        let n = sys::epoll_wait(ep, events, -1);
        if n == -sys::EINTR { continue; }
        check("epoll_wait", n);
        for ev in events[..n] {
            let fd = ev.tag as i32;
            if fd == lfd {
                accept_all(lfd, ep, conns);
                continue;
            }
            // Every event, readable, writable, or hangup, is handled the same
            // way: send what's pending and read until the kernel has nothing
            // more. Errors show up as results of those calls.
            let c .= conns[fd];
            if !pump(fd, c) {
                c.off = 0;
                c.len = 0;
                sys::close(fd);
            }
        }
    }
}

fn accept_all(lfd: i32, ep: i32, conns: Conn[>..]&) {
    loop {
        let fd = sys::accept(lfd, sys::NONBLOCK);
        if fd == -sys::EAGAIN { return; }
        if fd == -sys::EINTR || fd == -sys::ECONNABORTED { continue; }
        guard fd >= 0 else {
            report("accept", fd);
            return;
        }
        while conns.len <= fd { conns.push(Conn { .. }); }
        let r = sys::epoll_ctl(ep, sys::CTL_ADD, fd,
                               sys::IN | sys::OUT | sys::RDHUP | sys::ET, fd as u64);
        if r < 0 {
            report("epoll_ctl", r);
            sys::close(fd);
        }
    }
}

// Echoes until the socket would block. Edge-triggered epoll reports a socket
// again only after it changes state, so stopping earlier would strand it.
// Returns false once the connection is finished.
fn pump(fd: i32, c: Conn&) -> bool {
    loop {
        while c.off < c.len {
            let w = sys::send(fd, c.buf[c.off..c.len]);
            if w == -sys::EAGAIN { return true; }
            if w == -sys::EINTR { continue; }
            guard w > 0 else {
                report("send", w);
                return false;
            }
            c.off += w;
        }
        c.off = 0;
        c.len = 0;
        let r = sys::recv(fd, c.buf);
        if r == -sys::EAGAIN { return true; }
        if r == -sys::EINTR { continue; }
        guard r > 0 else {
            if r < 0 { report("recv", r); }
            return false;
        }
        c.len = r;
    }
}
