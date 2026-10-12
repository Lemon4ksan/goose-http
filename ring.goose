// The io_uring calls of http::serve's loop, implemented in shim/uring.c over
// liburing, on Windows in shim/iocp.c over a completion port, and on macOS in
// shim/ring_epoll.c over kqueue. A ring is the shim's, and owns every buffer
// the kernel reads or writes after a call returns: receives land in its
// provided buffers, and a send copies its bytes. Calls that can fail return
// -errno, as net_*'s do.
namespace http;

// One completion. tag is what its request was queued with. For a receive,
// buf is the provided buffer holding its res bytes, or -1 for none, and the
// buffer goes back to the ring with ring_give. more is whether a multishot
// request goes on. A send's completion has send set, and res is every byte
// it was given, or its error: the shim queues a short send's rest itself.
struct Completion { tag: u64, res: i32, buf: i32, more: bool, send: bool }

// The errno values of completions, beyond sys.goose's. shim/uring.c asserts
// them, and shim/iocp.c returns them.
let ENOBUFS = 105;
let ECANCELED = 125;

// A ring of entries submission entries, with nbufs provided buffers of
// buflen bytes; nbufs is a power of two. A tag fits in 62 bits. On Linux the
// ring is shim/ring_epoll.c's emulation over epoll where io_uring_setup
// fails, or with RING_EMULATE in flags; on macOS it always is, over kqueue.
extern "ur_create" fn ring_create(entries: i32, nbufs: i32, buflen: i32, flags: i32) -> i64;

// ring_create's flag.
let RING_EMULATE: i32 = 1;

// Whether ring_create gets the platform's own ring: 0, or -code for why it
// falls back to the emulation (ENOSYS on macOS, which has no other). A
// program can call it at startup to say which ring serve runs on.
extern "ur_probe" fn ring_probe() -> i32;

// Queue requests, which go to the kernel at the next wait.
extern "ur_accept" fn ring_accept(r: i64, fd: i32, tag: u64);
extern "ur_recv" fn ring_recv(r: i64, fd: i32, tag: u64);
extern "ur_send" fn ring_send(r: i64, fd: i32, tag: u64, data: const u8[:]) -> i32;
extern "ur_cancel" fn ring_cancel(r: i64, tag: u64);
// Cancels every request on fd, then closes it.
extern "ur_close" fn ring_close(r: i64, fd: i32);
// Writes dst.len bytes of provided buffer buf, from off, into dst.
extern "ur_take" fn ring_take(r: i64, buf: i32, off: i64, dst: u8[:]);
extern "ur_give" fn ring_give(r: i64, buf: i32);
// A waker (net_waker, mail.goose) on the ring: each wake ends the ring's
// wait with a completion of tag, res 0, and no buffer. Returns it, or -code.
// The box that owns it is closed after the ring is destroyed.
extern "ur_waker" fn ring_waker(r: i64, tag: u64) -> i64;
// Tears the ring down, with whatever is still queued on it. Windows keeps a
// completion port's memory: it completes the cancels of closed sockets'
// requests later (shim/iocp.c).
extern "ur_destroy" fn ring_destroy(r: i64);
// Submits what's queued, waits up to timeout_ms (-1: no limit) for a
// completion, and writes up to out.len completions into out.
extern "ur_wait" fn ring_wait(r: i64, out: Completion[:], timeout_ms: i32) -> i32;
