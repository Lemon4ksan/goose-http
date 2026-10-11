// The kernel calls the loops make, implemented in shim/net.c on Linux, in
// shim/kqueue.c on macOS, which gives the epoll calls below over kqueue, and
// in shim/net_win.c on Windows, where the epoll calls fail with ENOSYS.
// Each returns what its syscall returns on success and -code on failure,
// where code is one of the constants below, Linux's errno values on every
// platform. A caller compares against them negated: `if n == -http::EAGAIN`.
//
// Spec §7.10 leaves C three obligations: keep the types of what it writes
// through an argument, keep no argument after the call, and only append to a
// builder. The shim keeps no argument; where a call writes into an argument,
// its comment says how much.
namespace http;

import os;

// One readiness event, in a layout of the package's own (shim/net.c). On
// macOS it holds every filter kqueue reported for the fd in that wait.
struct PollEvent { events: u32, tag: u64 }

// Flags of net_listen and net_accept.
let NONBLOCK: i32 = 1;
let REUSEPORT: i32 = 2;   // net_listen only

// The error codes the loops tell apart, Linux's errno values. shim/net.c
// asserts each one, shim/kqueue.c translates macOS's errno to them, and
// shim/net_win.c Winsock's and Win32's errors.
let EINTR = 4;
let EAGAIN = 11;
let EINVAL = 22;
let ENFILE = 23;
let EMFILE = 24;
let EPIPE = 32;
let ENOSYS = 38;
let EADDRINUSE = 98;
let ECONNABORTED = 103;
let ECONNRESET = 104;

// epoll event bits and epoll_ctl ops, also asserted in shim/net.c, and
// mapped to kqueue's filters in shim/kqueue.c.
let EPOLLIN: u32 = 0x001;
let EPOLLOUT: u32 = 0x004;
let EPOLLERR: u32 = 0x008;
let EPOLLHUP: u32 = 0x010;
let EPOLLRDHUP: u32 = 0x2000;
let EPOLLET: u32 = 0x80000000;
let EPOLL_CTL_ADD: i32 = 1;
let EPOLL_CTL_DEL: i32 = 2;
let EPOLL_CTL_MOD: i32 = 3;

// shutdown's how, asserted in shim/net.c.
let SHUT_WR: i32 = 1;

// A TCP listener on IPv4 address ip, in host byte order, with SO_REUSEADDR
// and TCP_NODELAY, which accepted sockets inherit. An ip of -1 is every
// address, or 127.0.0.1 on Windows, where the listener has
// SO_EXCLUSIVEADDRUSE. With REUSEPORT, each worker gets a listener of its own
// on Linux, and the workers share one on macOS and Windows, which net_close
// closes after the last worker closes it.
extern fn net_listen(ip: i64, port: i32, backlog: i32, flags: i32) -> i32;
// flags must be the listener's NONBLOCK: macOS takes it from the listener. On
// macOS a shared listener's net_accept also fails with EAGAIN while the
// calling worker has taken more than its share of the connections.
extern fn net_accept(fd: i32, flags: i32) -> i32;
// Writes up to buf.len bytes into buf; 0 means the peer closed.
extern fn net_recv(fd: i32, buf: u8[:]) -> i64;
// Sends with MSG_NOSIGNAL: a closed peer is -EPIPE, never SIGPIPE.
extern fn net_send(fd: i32, data: const u8[:]) -> i64;
extern fn net_shutdown(fd: i32, how: i32) -> i32;
extern fn net_close(fd: i32) -> i32;

extern fn net_epoll_create() -> i32;
// The kernel keeps tag with fd's registration and returns it in PollEvent.tag.
// It's a number, not a reference into Goose memory.
extern fn net_epoll_ctl(ep: i32, op: i32, fd: i32, events: u32, tag: u64) -> i32;
// Writes the ready events into out[..n], n at most out.len and 1024.
extern fn net_epoll_wait(ep: i32, out: PollEvent[:], timeout_ms: i32) -> i32;

// Coarse clocks, up to one scheduler tick old: monotonic milliseconds, and
// wall-clock seconds since the epoch.
extern fn net_clock_ms() -> i64;
extern fn net_time_s() -> i64;

// Readies the calling thread to run a loop. On macOS it gets the
// user-interactive QoS class, which keeps it on the performance cores: Apple
// Silicon has no CPU affinity. Nothing elsewhere.
extern fn net_worker_start();
// The worker count when Config.workers is 0: the performance cores on macOS,
// and 0 elsewhere, for one worker per hardware thread.
extern fn net_default_workers() -> i32;

// Writes the C library's text for an error code (positive) into out, cut to
// fit, and returns its length.
extern fn net_strerror(err: i64, out: u8[:]) -> i64;

// Writes "call: text of the error" to stderr.
fn report(e: Error) {
    var msg: u8[>..] = [];
    format(msg, e.call, ": ");
    var text: u8[128] = [0; 128];
    let n = net_strerror(e.code, text);
    msg.append(text[..n]);
    msg.push('\n');
    write_stderr(msg);
}
