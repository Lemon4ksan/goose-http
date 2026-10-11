// Two echo servers that exercise shim/net.c before the HTTP server depends on
// it: a blocking one that serves one client at a time, and a single
// edge-triggered epoll loop.
import http;

// Reports a call that failed with -err on stderr.
fn report(what: const u8[:], err) { http::report(http::Error { call: what, code: -err }); }

// Returns r, or reports it and exits if it's an error.
fn check(what: const u8[:], r) {
    if r < 0 {
        report(what, r);
        exit(1);
    }
    r
}

let BUF_SIZE = 16384;

fn echo_blocking(port: i32) {
    let lfd = check("listen", http::net_listen(-1, port, 128, 0));
    print("echo-blocking: listening on ", port);
    var buf: u8[BUF_SIZE] = [0; BUF_SIZE];
    loop {
        let fd = http::net_accept(lfd, 0);
        if fd < 0 {
            if fd != -http::EINTR { report("accept", fd); }
            continue;
        }
        echo_until_closed(fd, buf);
        http::net_close(fd);
    }
}

fn echo_until_closed(fd: i32, buf: u8[:]) {
    loop {
        let n = http::net_recv(fd, buf);
        if n == -http::EINTR { continue; }
        guard n > 0 else {
            if n < 0 { report("recv", n); }
            return;
        }
        var off = 0;
        while off < n {
            let w = http::net_send(fd, buf[off..n]);
            if w == -http::EINTR { continue; }
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
struct EchoConn { off: i64, len: i64, buf: u8[BUF_SIZE] }

fn echo_epoll(port: i32) {
    let lfd = check("listen", http::net_listen(-1, port, 4096, http::NONBLOCK));
    let ep = check("epoll_create", http::net_epoll_create());
    check("epoll_ctl", http::net_epoll_ctl(ep, http::EPOLL_CTL_ADD, lfd,
                                         http::EPOLLIN | http::EPOLLET, lfd as u64));
    print("echo-epoll: listening on ", port);

    // Indexed by fd. The kernel hands out the lowest free fd, so the table
    // grows to the most connections open at once.
    var conns: EchoConn[>..] = [];
    var events: http::PollEvent[256] = [http::PollEvent { events: 0, tag: 0 }; 256];
    loop {
        let n = http::net_epoll_wait(ep, events, -1);
        if n == -http::EINTR { continue; }
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
                http::net_close(fd);
            }
        }
    }
}

fn accept_all(lfd: i32, ep: i32, conns: EchoConn[>..]&) {
    loop {
        let fd = http::net_accept(lfd, http::NONBLOCK);
        if fd == -http::EAGAIN { return; }
        if fd == -http::EINTR || fd == -http::ECONNABORTED { continue; }
        guard fd >= 0 else {
            report("accept", fd);
            return;
        }
        while conns.len <= fd { conns.push(EchoConn { .. }); }
        let r = http::net_epoll_ctl(ep, http::EPOLL_CTL_ADD, fd,
                                    http::EPOLLIN | http::EPOLLOUT | http::EPOLLRDHUP | http::EPOLLET,
                                    fd as u64);
        if r < 0 {
            report("epoll_ctl", r);
            http::net_close(fd);
        }
    }
}

// Echoes until the socket would block. Edge-triggered epoll reports a socket
// again only after it changes state, so stopping earlier would strand it.
// Returns false once the connection is finished.
fn pump(fd: i32, c: EchoConn&) -> bool {
    loop {
        while c.off < c.len {
            let w = http::net_send(fd, c.buf[c.off..c.len]);
            if w == -http::EAGAIN { return true; }
            if w == -http::EINTR { continue; }
            guard w > 0 else {
                report("send", w);
                return false;
            }
            c.off += w;
        }
        c.off = 0;
        c.len = 0;
        let r = http::net_recv(fd, c.buf);
        if r == -http::EAGAIN { return true; }
        if r == -http::EINTR { continue; }
        guard r > 0 else {
            if r < 0 { report("recv", r); }
            return false;
        }
        c.len = r;
    }
}
