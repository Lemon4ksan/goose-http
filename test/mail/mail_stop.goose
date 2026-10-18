// Stopping a lane: a stop sent as a message is lost when the box is full, and
// the lane then waits for mail forever. The lane here waits with a time limit
// instead, so that the test ends, and reports that the stop never came.
// The package is declared by mail.goose alone; the sidecar beside it names
// the C.
import std;
import os;
import mail from "../../";

let JOB: i32 = 1;
let STOP: i32 = 2;
let SLOTS: i32 = 8;

// A lane as programs write it today: until a STOP message. It gives up after
// three waits in a row that find nothing, where a real lane waits on.
thread_fn lane_by_message(box: http::Box) {
    var running = true;
    var jobs = 0;
    var idle = 0;
    while running && idle < 3 {
        if !http::mail_wait(box, 100) {
            idle++;
            continue;
        }
        idle = 0;
        http::mail_take(box) { key, tag, bytes =>
            if tag == JOB { jobs++; } else if tag == STOP { running = false; }
        };
    }
    print("lane by message: ", jobs, " jobs taken, ", if running { "no stop came" } else { "stopped" });
    http::mail_close(box);
}

// A box filled to its slots before its lane runs: the STOP finds it FULL.
fn test_stop_by_message() {
    let b, err = http::mail_open_code(SLOTS, 8);
    assert(err == 0);
    let to = http::address(b, 0);
    for i in SLOTS { assert(http::mail_send(to, JOB, "") == http::SENT); }
    print("STOP to a full box: ", if http::mail_send(to, STOP, "") == http::FULL { "FULL" } else { "sent" });
    thread_wait(thread_spawn(lane_by_message, b));
}

// A lane as mail_stop lets it be written: no time limit, and no STOP tag.
thread_fn lane(box: http::Box) {
    var jobs = 0;
    while !http::mail_stopped(box) {
        http::mail_wait(box, -1);
        http::mail_take(box) { key, tag, bytes => if tag == JOB { jobs++; } };
    }
    print("lane: ", jobs, " jobs taken, stopped");
    http::mail_close(box);
}

// The same full box: the stop can't be refused, a send after it is STALE,
// and the lane takes every job queued before it and returns.
fn test_stop_full() {
    let b, err = http::mail_open_code(SLOTS, 8);
    assert(err == 0);
    let to = http::address(b, 0);
    assert(http::mail_queued(to) == 0);
    for i in SLOTS { assert(http::mail_send(to, JOB, "") == http::SENT); }
    assert(http::mail_queued(to) == SLOTS);
    assert(http::mail_live(to));
    assert(http::mail_slot_size(to) == 8);
    http::mail_stop(b);
    assert(!http::mail_live(to));
    assert(http::mail_slot_size(to) == -1);
    assert(http::mail_send(to, JOB, "") == http::STALE);
    assert(http::mail_queued(to) == -1);
    assert(!http::mail_stopped(b));
    thread_wait(thread_spawn(lane, b));
}

// A lane already asleep in mail_wait with no limit: the stop wakes it. The
// pause lets the wait outlast its spin and sleep in the kernel.
fn test_stop_wakes() {
    let b, err = http::mail_open_code(SLOTS, 8);
    assert(err == 0);
    let id = thread_spawn(lane, b);
    assert(http::mail_send(http::address(b, 0), JOB, "") == http::SENT);
    sleep_ms(50);
    http::mail_stop(b);
    thread_wait(id);
}

fn main() {
    test_stop_by_message();
    test_stop_full();
    test_stop_wakes();
}
