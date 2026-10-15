// The mailboxes (mail.goose, shim/mail.c): FULL, TOO_LONG, and STALE at the
// send, the slot size from an address, and the slot counts a box allows with
// FULL at each one's capacity. The package is declared by mail.goose alone,
// so this compiles only while the mailbox reaches nothing of the HTTP side;
// the sidecar beside it names the C.
import std;
import os;
import mail from "../../";

fn test_full_and_stale() {
    let b, err = http::mail_open_code(4, 8);
    assert(err == 0);
    let to = http::address(b, 77);
    assert(http::mail_live(to));
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
    print("4 sent, FULL at the fifth, ", n, " taken in order");
    // One byte longer than a slot: TOO_LONG, with every slot free, and the
    // slot size known from the address.
    assert(http::mail_slot_size(to) == 8);
    assert(http::mail_send(to, 0, "123456789") == http::TOO_LONG);
    assert(http::mail_send(to, 0, "") == http::SENT);
    http::mail_close(b);
    assert(!http::mail_live(to));
    assert(http::mail_send(to, 0, "") == http::STALE);
    assert(http::mail_send(to, 0, "123456789") == http::STALE);
    assert(http::mail_slot_size(to) == -1);
    // A box opened in the closed one's place has a new generation.
    let c, err2 = http::mail_open_code(4, 8);
    assert(err2 == 0 && c.handle.slot == b.handle.slot && c.handle.gen != b.handle.gen);
    assert(http::mail_send(to, 0, "") == http::STALE);
    assert(http::mail_send(http::address(c, 1), 0, "") == http::SENT);
    assert(http::mail_send(http::MailAddress { .. }, 0, "") == http::STALE);
    assert(http::mail_slot_size(http::MailAddress { .. }) == -1);
    http::mail_close(c);
    print("TOO_LONG past the slot size; STALE once closed and in a new box's place");
    // Waiting with nothing sent ends at the time limit.
    let d, err3 = http::mail_open_code(2, 0);
    assert(err3 == 0 && !http::mail_wait(d, 20));
    http::mail_close(d);
    let _, bad = http::mail_open_code(3, 8);
    assert(bad < 0);
    print("a wait with nothing sent ends at its limit; 3 slots refused");
}

// A box takes as many messages as it has slots, then reports FULL. One slot
// can't tell full from free, so a box has at least two: fewer is EINVAL (22).
fn test_slot_counts() {
    for slots in [-1, 0, 1] {
        let _, bad = http::mail_open_code(slots as i32, 8);
        assert(bad == -22);
    }
    for slots in [2, 4] {
        let b, err = http::mail_open_code(slots as i32, 8);
        assert(err == 0);
        let to = http::address(b, 1);
        for i in slots { assert(http::mail_send(to, i as i32, "x") == http::SENT); }
        assert(http::mail_send(to, 0, "x") == http::FULL);
        assert(http::mail_send(to, 0, "x") == http::FULL);
        let n = http::mail_take(b) { key, tag, bytes => assert(bytes == "x"); };
        assert(n == slots);
        http::mail_close(b);
        print(slots, " slots: FULL after ", n);
    }
    print("-1, 0, and 1 slots: EINVAL");
}

fn main() {
    test_full_and_stale();
    test_slot_counts();
}
