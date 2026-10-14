// Unit tests for the mailboxes (mail.goose, shim/mail.c): FULL, TOO_LONG,
// and STALE at the send, the slot size from an address, many senders on
// threads of their own with nothing lost or reordered per sender, and a
// ping-pong between two threads, which needs a
// wakeup for every message, with no wait reaching its time limit. The
// package is declared by mail.goose alone, so this compiles only while the
// mailbox reaches nothing of the HTTP side. TinyCC can't run threads, so
// scripts/test-unit.sh builds this one with the C compiler.
import std;
import os;
import mail from "../";

fn put(out: u8[>..]&, v: i64) {
    for i in 8 { out.push(((v >> (8 * i)) & 0xFF) as! u8); }
}

fn got(b: const u8[:]) -> i64 {
    var v = 0;
    for i in 8 { v |= (b[i] as i64) << (8 * i); }
    return v;
}

fn test_full_and_stale() {
    let b, err = http::mail_open(4, 8);
    assert(err == 0);
    let to = http::address(b, 77);
    for i in 4 { assert(http::mail_send(to, i as i32, "12345678") == http::SENT); }
    assert(http::mail_send(to, 9, "x") == http::FULL);
    assert(!http::mail_wait(b, 0) == false);
    var tags: i64[>..] = [];
    let n = http::mail_take(b) { key, tag, bytes =>
        assert(key == 77 && bytes == "12345678");
        tags.push(tag);
    };
    assert(n == 4 && tags.len == 4 && tags[0] == 0 && tags[3] == 3);
    assert(!http::mail_pending(b));
    // One byte longer than a slot: TOO_LONG, with every slot free, and the
    // slot size known from the address.
    assert(http::mail_slot_size(to) == 8);
    assert(http::mail_send(to, 0, "123456789") == http::TOO_LONG);
    assert(http::mail_send(to, 0, "") == http::SENT);
    http::mail_close(b);
    assert(http::mail_send(to, 0, "") == http::STALE);
    assert(http::mail_send(to, 0, "123456789") == http::STALE);
    assert(http::mail_slot_size(to) == -1);
    // A box opened in the closed one's place has a new generation.
    let c, err2 = http::mail_open(4, 8);
    assert(err2 == 0 && c.handle.slot == b.handle.slot && c.handle.gen != b.handle.gen);
    assert(http::mail_send(to, 0, "") == http::STALE);
    assert(http::mail_send(http::address(c, 1), 0, "") == http::SENT);
    assert(http::mail_send(http::MailAddress { .. }, 0, "") == http::STALE);
    assert(http::mail_slot_size(http::MailAddress { .. }) == -1);
    http::mail_close(c);
    // Waiting with nothing sent ends at the time limit.
    let d, err3 = http::mail_open(2, 0);
    assert(err3 == 0 && !http::mail_wait(d, 20));
    http::mail_close(d);
    let _, bad = http::mail_open(3, 8);
    assert(bad < 0);
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
    let b, err = http::mail_open(64, 8);
    assert(err == 0);
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
}

// The other end of the ping-pong: opens a box, gives main its address, and
// sends back to back each number it gets, plus one, after pause_ms. main's
// address comes as an argument: any thread takes from a typed queue, so a
// thread that put its own address there and then took one could take its
// own back.
thread_fn ponger(back: http::MailAddress, rounds: i64, pause_ms: i64) {
    let b, err = http::mail_open(4, 8);
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
    let b, err = http::mail_open(4, 8);
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
}

fn main() {
    test_full_and_stale();
    test_senders();
    test_ping_pong(20000, 0);
    test_ping_pong(400, 1);
    print("test_mail: ok");
}
