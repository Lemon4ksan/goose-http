// The kernel calls the server makes, implemented in shim/net.c. Each returns
// what its syscall returns on success and -errno on failure, so a caller
// compares against the negated constants below: `if n == -sys::EAGAIN`.
//
// Spec §7.10 leaves C three obligations: keep the types of what it writes
// through an argument, keep no argument after the call, and only append to a
// builder. The shim keeps nothing; where a call writes into an argument, its
// comment says how much.
namespace sys;

import os;

// One readiness event, in a layout of the program's own (shim/net.c).
struct Event { events: u32, tag: u64 }

// Flags of listen and accept.
let NONBLOCK: i32 = 1;
let REUSEPORT: i32 = 2;   // listen only

// The errno values the server tells apart. shim/net.c asserts each one.
let EINTR = 4;
let EAGAIN = 11;
let ENFILE = 23;
let EMFILE = 24;
let EPIPE = 32;
let EADDRINUSE = 98;
let ECONNABORTED = 103;
let ECONNRESET = 104;

// epoll event bits and epoll_ctl ops, also asserted in shim/net.c.
let IN: u32 = 0x001;
let OUT: u32 = 0x004;
let ERR: u32 = 0x008;
let HUP: u32 = 0x010;
let RDHUP: u32 = 0x2000;
let ET: u32 = 0x80000000;
let CTL_ADD: i32 = 1;
let CTL_DEL: i32 = 2;
let CTL_MOD: i32 = 3;

// shutdown's how, asserted in shim/net.c.
let SHUT_WR: i32 = 1;

// A TCP listener on every IPv4 address, with SO_REUSEADDR and TCP_NODELAY,
// which accepted sockets inherit.
extern "net_listen" fn listen(port: i32, backlog: i32, flags: i32) -> i32;
extern "net_accept" fn accept(fd: i32, flags: i32) -> i32;
// Writes up to buf.len bytes into buf; 0 means the peer closed.
extern "net_recv" fn recv(fd: i32, buf: u8[:]) -> i64;
// Sends with MSG_NOSIGNAL: a closed peer is -EPIPE, never SIGPIPE.
extern "net_send" fn send(fd: i32, data: const u8[:]) -> i64;
extern "net_shutdown" fn shutdown(fd: i32, how: i32) -> i32;
extern "net_close" fn close(fd: i32) -> i32;

extern "net_epoll_create" fn epoll_create() -> i32;
// The kernel keeps tag with fd's registration and returns it in Event.tag.
// It's a number, not a reference into Goose memory.
extern "net_epoll_ctl" fn epoll_ctl(ep: i32, op: i32, fd: i32, events: u32, tag: u64) -> i32;
// Writes the ready events into out[..n], n at most out.len and 1024.
extern "net_epoll_wait" fn epoll_wait(ep: i32, out: Event[:], timeout_ms: i32) -> i32;

// Coarse clocks, up to one scheduler tick old: monotonic milliseconds, and
// wall-clock seconds since the epoch.
extern "net_clock_ms" fn clock_ms() -> i64;
extern "net_time_s" fn time_s() -> i64;

// Writes the C library's text for an errno value (positive) into out, cut to
// fit, and returns its length.
extern "net_strerror" fn strerror(err: i64, out: u8[:]) -> i64;

// Reports a call that failed with -err on stderr.
fn report(what: const u8[:], err) {
    var msg: u8[>..] = [];
    format(msg, what, ": ");
    var text: u8[128] = [0; 128];
    let n = strerror(-err, text);
    msg.append(text[..n]);
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
