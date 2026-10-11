// The io_uring calls the server's io_uring loop makes, implemented in
// shim/uring.c over liburing, and on Windows in shim/iocp.c over a completion
// port. A ring is the shim's, and owns every buffer the kernel reads or
// writes after a call returns: receives land in its provided buffers, and a
// send copies its bytes. Calls that can fail return -errno, as sys's do.
namespace ring;

// One completion. tag is what its request was queued with. For a receive,
// buf is the provided buffer holding its res bytes, or -1 for none, and the
// buffer goes back to the ring with give. more is whether a multishot
// request goes on. A send's completion has send set, and res is every byte
// it was given, or its error: the shim queues a short send's rest itself.
struct Completion { tag: u64, res: i32, buf: i32, more: bool, send: bool }

// The errno values of completions, beyond sys's. shim/uring.c asserts them,
// and shim/iocp.c returns them.
let ENOBUFS = 105;
let ECANCELED = 125;

// A ring of entries submission entries, with nbufs provided buffers of
// buflen bytes; nbufs is a power of two. A tag fits in 62 bits.
extern "ur_create" fn create(entries: i32, nbufs: i32, buflen: i32) -> i64;
// Queue requests, which go to the kernel at the next wait.
extern "ur_accept" fn accept(r: i64, fd: i32, tag: u64);
extern "ur_recv" fn recv(r: i64, fd: i32, tag: u64);
extern "ur_send" fn send(r: i64, fd: i32, tag: u64, data: const u8[:]) -> i32;
extern "ur_cancel" fn cancel(r: i64, tag: u64);
// Cancels every request on fd, then closes it.
extern "ur_close" fn close(r: i64, fd: i32);
// Writes dst.len bytes of provided buffer buf, from off, into dst.
extern "ur_take" fn take(r: i64, buf: i32, off: i64, dst: u8[:]);
extern "ur_give" fn give(r: i64, buf: i32);
// Submits what's queued, waits up to timeout_ms (-1: no limit) for a
// completion, and writes up to out.len completions into out.
extern "ur_wait" fn wait(r: i64, out: Completion[:], timeout_ms: i32) -> i32;
