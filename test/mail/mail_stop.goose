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

fn main() {
    test_stop_by_message();
}
