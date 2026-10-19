// Lanes (lane.goose): a lane's thread count from its LaneConfig, a job to the
// least busy thread, the jobs of one thread in the order sent, a value sent
// whole, a value passed to each thread, and a stop that ends every thread
// with the jobs queued before it taken, and waits for them; and lane_of, a lane
// of one box with no thread.
import std;
import http from "../../";

let JOB: i32 = 1;
// A job its thread holds until main lets it go.
let HOLD: i32 = 2;
let VALUE: i32 = 3;

// What a lane thread counted, which it puts in the queue for main, with its
// box's slot, once its box is stopped: its jobs, those that came out of the
// order sent, and the sum of the values it read.
struct Count { slot: i32, jobs: i64, unordered: i64, sum: i64 }

// What a thread puts in the queue once it holds a HOLD job, and what main
// puts there to let it go on.
struct Holding { slot: i32 }
struct Release { slot: i32 }

// A JOB's bytes are its number among the jobs sent; a VALUE's, an i64 that
// lane_send_value sent, which the thread adds to its sum times its base.
thread_fn counter(box: http::Box, base: i64) {
    var c = Count { slot: box.handle.slot, .. };
    var last: i64 = -1;
    http::lane(box) { tag, bytes =>
        if tag == HOLD {
            qput(Holding { slot: c.slot });
            qget<Release>();
        }
        c.jobs++;
        if tag == JOB && bytes.len == 1 {
            let n = bytes[0] as i64;
            if n <= last { c.unordered++; }
            last = n;
        }
        var v: i64 = 0;
        if tag == VALUE && http::mail_value(bytes, v) { c.sum += v * base; }
    };
    qput(c);
}

thread_fn idle(box: http::Box) {
    http::lane(box) { tag, bytes => {} };
}

// What each of lane's threads counted, in the order of its boxes.
fn counts(lane: const http::Lane&) -> Count[>..] {
    var all: Count[>..] = [];
    for b in lane.boxes { all.push(Count { .. }); }
    for k in lane.boxes.len {
        let c = qget<Count>();
        for b, i in lane.boxes { if b.handle.slot == c.slot { all[i] = c; } }
    }
    return all;
}

// The threads a lane of cfg gets.
fn threads(cfg: http::LaneConfig) -> i64 {
    let lane = http::lane_open(cfg, idle);
    http::lane_stop(lane);
    return lane.threads.len;
}

fn test_threads() {
    print("threads: ", threads(http::LaneConfig { .. }), " by default, ",
          threads(http::LaneConfig { threads: 3, .. }), " as asked, ",
          threads(http::LaneConfig { threads: 0, .. }), " for 0, ",
          threads(http::LaneConfig { threads: 100, slots: 2, size: 16 }), " for 100");
}

// Two threads, the first holding its job until main lets it go: the least
// busy box takes each job, so the idle thread, which main lets take each job
// before it sends the next, takes all of them, and none waits behind the
// held one.
fn test_least_busy() {
    let lane = http::lane_open(http::LaneConfig { threads: 2, slots: 8, .. }, 1, counter);
    assert(http::mail_send(http::address(lane.boxes[0], 0), HOLD, "") == http::SENT);
    let held = qget<Holding>();
    let idle_at = http::address(lane.boxes[1], 0);
    var sent = 0;
    for i in 12 {
        while http::mail_queued(idle_at) != 0 { sleep_ms(1); }
        if http::lane_send(lane, JOB, "") == http::SENT { sent++; }
    }
    qput(Release { slot: held.slot });
    http::lane_stop(lane);
    let c = counts(lane);
    print("least busy: ", sent, " of 12 sent, ", c[1].jobs, " to the idle thread, ", c[0].jobs, " to the held one");
}

// One thread: jobs sent faster than it takes them fill its box, which answers
// FULL, and those it took came in the order sent. Values arrive whole, each
// multiplied by the base lane_open passed. A stop takes what the box holds,
// and a send after it is STALE.
fn test_one_thread() {
    let lane = http::lane_open(http::LaneConfig { slots: 4, size: 32, .. }, 10, counter);
    assert(http::mail_send(http::address(lane.boxes[0], 0), HOLD, "") == http::SENT);
    let held = qget<Holding>();
    var sent = 0;
    var full = 0;
    for i in 8 {
        var job: u8[..1] = [];
        job.push(i as! u8);
        let r = http::lane_send(lane, JOB, job);
        if r == http::SENT { sent++; }
        if r == http::FULL { full++; }
    }
    qput(Release { slot: held.slot });
    while http::mail_queued(http::address(lane.boxes[0], 0)) != 0 { sleep_ms(1); }
    var values = 0;
    for v in [1, 2, 3] {
        let n: i64 = v;
        if http::lane_send_value(lane, VALUE, n) == http::SENT { values++; }
    }
    http::lane_stop(lane);
    let after = http::lane_send(lane, JOB, "");
    let c = counts(lane);
    print("one thread: ", sent, " sent, ", full, " full, ", c[0].unordered, " out of order; ",
          values, " values summing to ", c[0].sum, "; ", c[0].jobs, " jobs in all; after the stop, ",
          if after == http::STALE { "STALE" } else { "not STALE" });
}

// lane_of: one box, no thread, and the job reaches the box for the test to take.
fn test_lane_of() {
    let b, e = http::mail_open(2, 16);
    http::exit_on_error(e);
    let lane = http::lane_of(b);
    let sent = http::lane_send(lane, JOB, "x");
    let n = http::mail_take(b) { key, tag, bytes => assert(tag == JOB && bytes == "x"); };
    print("lane_of: ", lane.boxes.len, " box, ", lane.threads.len, " threads, ",
          if sent == http::SENT { "SENT" } else { "not SENT" }, ", ", n, " taken");
    http::mail_close(b);
}

fn main() {
    test_lane_of();
    test_threads();
    test_least_busy();
    test_one_thread();
}
