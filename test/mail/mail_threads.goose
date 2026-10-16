// Boxes between threads: many senders with nothing lost or reordered per
// sender, and a ping-pong between two threads, which needs a wakeup for
// every message, with no wait reaching its time limit. The package is
// declared by mail.goose alone; the sidecar beside it names the C.
import std;
import os;
import mail from "../../";

fn put(out: u8[>..]&, v: i64) {
    for i in 8 { out.push(((v >> (8 * i)) & 0xFF) as! u8); }
}

fn got(b: const u8[:]) -> i64 {
    var v = 0;
    for i in 8 { v |= (b[i] as i64) << (8 * i); }
    return v;
}

let SENDERS = 8;
let EACH = 20000;

// Sends EACH numbered messages to to, trying again while the box is full.
thread_fn sender(to: http::MailAddress, id: i64) {
    var msg: u8[>..] = [];
    for i in EACH {
        msg.clear();
        put(msg, i);
        while http::mail_send(to, id as i32, msg) == http::FULL {}
    }
}

// SENDERS threads into a box of 64 slots: every message arrives, each
// sender's in order, and the owner never waits out its time limit.
fn test_senders() {
    let b, err = http::mail_open_code(64, 8, 0, 1, 63);
    assert(err == 0);
    http::mail_mark(b, 5, true);
    var ids: i64[>..] = [];
    for s in SENDERS { ids.push(thread_spawn(sender, http::address(b, 5), s)); }
    var next: i64[>..] = [];
    for s in SENDERS { next.push(0); }
    var total = 0;
    var timeouts = 0;
    while total < SENDERS * EACH {
        if !http::mail_pending(b) && !http::mail_wait(b, 2000) { timeouts++; }
        total += http::mail_take(b) { key, tag, bytes =>
            assert(key == 5 && got(bytes) == next[tag]);
            next[tag]++;
        };
        assert(timeouts < 3);
    }
    for id in ids { thread_wait(id); }
    for n in next { assert(n == EACH); }
    assert(!http::mail_pending(b));
    http::mail_close(b);
    print(SENDERS, " senders: ", total, " messages, each sender's in order");
}

// The other end of the ping-pong: opens a box, gives main its address, and
// sends back to back each number it gets, plus one, after pause_ms. main's
// address comes as an argument: any thread takes from a typed queue, so a
// thread that put its own address there and then took one could take its
// own back.
thread_fn ponger(back: http::MailAddress, rounds: i64, pause_ms: i64) {
    let b, err = http::mail_open_code(4, 8);
    assert(err == 0);
    qput(http::address(b, 0));
    var msg: u8[>..] = [];
    var done = false;
    while !done {
        assert(http::mail_wait(b, 2000));
        http::mail_take(b) { key, tag, bytes =>
            let v = got(bytes);
            if pause_ms > 0 { sleep_ms(pause_ms); }
            msg.clear();
            put(msg, v + 1);
            assert(http::mail_send(back, 0, msg) == http::SENT);
            // main sends nothing after the reply to this.
            if v + 2 >= rounds { done = true; }
        };
    }
    http::mail_close(b);
}

// One message in flight at a time, each way: every message moves its box's
// count from 0 to 1, so a lost wakeup would stall a wait to its limit. With
// pause_ms, each side sleeps before it replies, so every wait outlasts the
// spin and sleeps in the kernel.
fn test_ping_pong(rounds: i64, pause_ms: i64) {
    let b, err = http::mail_open_code(4, 8);
    assert(err == 0);
    let id = thread_spawn(ponger, http::address(b, 0), rounds, pause_ms);
    let to = qget<http::MailAddress>();
    var msg: u8[>..] = [];
    put(msg, 0);
    assert(http::mail_send(to, 0, msg) == http::SENT);
    var last = 0;
    while last + 1 < rounds {
        assert(http::mail_wait(b, 2000));
        http::mail_take(b) { key, tag, bytes =>
            last = got(bytes);
            if last + 1 < rounds {
                if pause_ms > 0 { sleep_ms(pause_ms); }
                msg.clear();
                put(msg, last + 1);
                assert(http::mail_send(to, 0, msg) == http::SENT);
            }
        };
    }
    thread_wait(id);
    // The ponger closed its box on the way out.
    assert(http::mail_send(to, 0, msg) == http::STALE);
    http::mail_close(b);
    print("ping-pong: ", rounds, " rounds, ", pause_ms, " ms pause, last ", last);
}

fn main() {
    test_senders();
    test_ping_pong(20000, 0);
    test_ping_pong(400, 1);
}
