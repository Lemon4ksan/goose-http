// Live keys (mail_mark): which keys a box takes mail for, the slot size and
// TOO_LONG for a live one, STALE for one cleared or out of range, and from
// another thread. The package is declared by mail.goose alone; the sidecar
// beside it names the C.
import std;
import os;
import mail from "../../";

thread_fn check_dead(to: http::MailAddress) {
    assert(!http::mail_live(to));
    assert(http::mail_send(to, 0, "") == http::STALE);
}

fn main() {
    let b, err = http::mail_open_code(2, 8, 0, 2, 60);
    assert(err == 0);
    let a = http::address(b, 7);
    let next = http::address(b, 8);
    let high = http::address(b, ((1 as u64) << 60) | 9);
    let outside = http::address(b, (2 as u64) << 60);
    assert(!http::mail_live(a));
    assert(http::mail_slot_size(a) == -1);
    assert(http::mail_send(a, 0, "123456789") == http::STALE);
    http::mail_mark(b, a.key, true);
    http::mail_mark(b, high.key, true);
    assert(http::mail_live(a) && http::mail_live(high));
    assert(http::mail_slot_size(a) == 8);
    assert(http::mail_send(a, 0, "123456789") == http::TOO_LONG);
    assert(http::mail_send(a, 1, "a") == http::SENT);
    assert(http::mail_send(high, 2, "b") == http::SENT);
    assert(http::mail_send(a, 0, "") == http::FULL);
    print("marked live: slot size 8, TOO_LONG, SENT, FULL");
    http::mail_mark(b, next.key, true);
    http::mail_mark(b, a.key, false);
    assert(!http::mail_live(a) && http::mail_live(next));
    assert(http::mail_send(a, 0, "") == http::STALE);
    http::mail_mark(b, outside.key, true);
    http::mail_mark(b, 0, true);
    assert(!http::mail_live(outside) && !http::mail_live(http::address(b, 0)));
    assert(http::mail_send(outside, 0, "") == http::STALE);
    // A clear doesn't remove messages already queued.
    assert(http::mail_take(b) { key, tag, bytes => assert(bytes.len == 1); } == 2);
    print("cleared and out of range: STALE; queued messages stay");
    http::mail_mark(b, high.key, false);
    thread_wait(thread_spawn(check_dead, high));
    http::mail_close(b);
    thread_wait(thread_spawn(check_dead, next));
    let _, bad_count = http::mail_open_code(2, 0, 0, -1);
    let _, bad_shift = http::mail_open_code(2, 0, 0, 2, 64);
    assert(bad_count < 0 && bad_shift < 0);
    print("from another thread: STALE; a bad key count and shift refused");
}
