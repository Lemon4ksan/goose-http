// Mailboxes: a box has a fixed number of slots of a fixed size, allocated
// when it opens, and one owner, the thread that takes from it. Any thread
// sends to it by address, and the send says at once whether the message
// went in: SENT, FULL (no slot free, or the message longer than a slot), or
// STALE (the box is closed, or opened again since the address was taken). A
// send never blocks or grows the box. An address is the box's handle and a
// 64-bit key the box doesn't read, which comes back with each message sent
// to it: the owner gives it its meaning.
//
// The queue and the wakeup are C (shim/mail.c, and each platform's net_waker),
// since Goose has neither atomics nor a wait another thread can end. Nothing
// here knows HTTP: this file imports nothing of the package's HTTP side, so
// that it can move to a package of its own unchanged.
//
//   let b, err = http::mail_open(256, 512);
//   http::mail_send(http::address(b, key), tag, bytes);   // from any thread
//   http::mail_wait(b, 1000);                             // in b's owner
//   http::mail_take(b) { key, tag, bytes => ... };
namespace http;

import std;
import handle;

// The owner's handle to its box. Flat, so it crosses thread_spawn and
// queues, but only the owner takes, waits, or closes.
struct Box { handle: Handle = Handle { .. } }

// Where a message goes: a box, and the key it comes with.
struct MailAddress { box: Handle = Handle { .. }, key: u64 = 0 }

// What mail_send returns.
let SENT: i32 = 0;
let FULL: i32 = 1;
let STALE: i32 = 2;

// The shim's calls, on a box's key (key_of its handle). shim/mail.c says
// what each does. mail_take_one writes up to out.len bytes into out and 2
// values into head.
extern "mail_open" fn mail_open_c(slots: i32, size: i32, waker: i64) -> i64;
extern "mail_close" fn mail_close_c(box: u64);
extern "mail_send" fn mail_send_c(to: u64, key: u64, tag: i32, data: const u8[:]) -> i32;
extern "mail_pending" fn mail_pending_c(box: u64) -> i64;
extern "mail_size" fn mail_size_c(box: u64) -> i32;
extern "mail_take_one" fn mail_take_one_c(box: u64, out: u8[:], head: i64[:]) -> i64;
extern "mail_settle" fn mail_settle_c(box: u64, n: i64) -> i32;
extern "mail_wait" fn mail_wait_c(box: u64, ms: i32) -> i32;

// A waker for a loop's epoll or kqueue instance ep: each wake makes the
// loop's wait report tag as readable. Returns it, or -code. A box opened
// with it owns it, and the box is closed before ep.
extern fn net_waker(ep: i32, tag: u64) -> i64;

// Opens a box of slots messages, a power of two, of up to size bytes each.
// waker is a loop's (net_waker, ring_waker), which the box then owns, or 0
// for one the box makes for mail_wait. Returns the box, and 0 or -code.
fn mail_open(slots: i32, size: i32, waker: i64 = 0) -> Box, i64 {
    let k = mail_open_c(slots, size, waker);
    guard k >= 0 else { return Box { .. }, k; }
    return Box { handle: handle_of(k as u64) }, 0;
}

// Closes b, and drops what it holds: sends to it return STALE from then on.
fn mail_close(b: Box) { mail_close_c(key_of(b.handle)); }

// The address of b with key.
fn address(b: Box, key: u64) -> MailAddress { MailAddress { box: b.handle, key: key } }

// Sends data with tag to to's box, at once. Any thread may call it.
fn mail_send(to: MailAddress, tag: i32, data: const u8[:]) -> i32 {
    return mail_send_c(key_of(to.box), to.key, tag, data);
}

// Whether b holds messages it hasn't taken: one atomic load.
fn mail_pending(b: Box) -> bool { mail_pending_c(key_of(b.handle)) > 0 }

// Waits up to ms milliseconds (-1: no limit) for a message, in b's owner when
// b has no loop's waker. Returns whether one is pending: false at the time
// limit, or after a wake whose message was taken already.
fn mail_wait(b: Box, ms: i32) -> bool { mail_wait_c(key_of(b.handle), ms) > 0 }

// Calls F with each message b holds, in the order sent: the key of the
// address it was sent to, its tag, and its bytes, valid until F returns.
// Returns how many it took. Messages that come while it runs are taken too.
fn mail_take<F>(b: Box) -> i64 {
    let k = key_of(b.handle);
    var buf: u8[>..] = [];
    buf.resize(mail_size_c(k), 0);
    var head: i64[2] = [0; 2];
    var total = 0;
    loop {
        var n = 0;
        loop {
            let len = mail_take_one_c(k, buf, head);
            guard len >= 0 else { break; }
            F(head[0] as! u64, head[1] as! i32, buf[..len]);
            n++;
        }
        total += n;
        guard mail_settle_c(k, n) != 0 else { break; }
    }
    return total;
}
