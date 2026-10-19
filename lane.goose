// Lanes: threads that take a program's slow work from the workers, each with
// a box of its own (mail.goose). lane_open spawns them, each the program's
// thread_fn, whose body is a lane block; a handler sends a job with
// lane_send, which picks the least busy thread; and once the workers have
// returned, lane_stop stops every thread and waits for it.
//
//   thread_fn counter(box: http::Box) {
//       http::lane(box) { tag, bytes => ... };
//   }
//
//   let primes = http::lane_open(http::LaneConfig { threads: 2, .. }, counter);
//   http::run(cfg, primes, worker);      // a worker sends with http::lane_send
//   http::lane_stop(primes);
namespace http;

import std;
import mail;

// A lane's threads, at least 1 and at most LANE_MOST, and each box's slots, a
// power of two of at least 2, of size bytes each.
struct LaneConfig {
    threads: i64 = 1,
    slots: i32 = 64,
    size: i32 = 256,
}

// The most threads one lane has: Lane's arrays are fixed, so that it's flat
// and crosses thread_spawn.
let LANE_MOST: i64 = 64;

// A lane's boxes, and its threads' ids, one of each per thread.
struct Lane { boxes: Box[..64], threads: i64[..64] }

// Where this thread's next lane_send starts its scan. Each thread has its
// own copy of a global, so it needs no synchronization.
var lane_turn: i64 = 0;

// Opens a lane of cfg.threads threads, each the thread_fn W with a box of its
// own, and a, where given. A box that fails to open ends the program, as a
// configuration that can't start does.
//
//   http::lane_open(cfg, reader);       // thread_fn reader(box: http::Box)
//   http::lane_open(cfg, db, reader);   // thread_fn reader(box: http::Box, db: Db)
fn lane_open<W>(cfg: LaneConfig) -> Lane {
    return lane_spawn(cfg) { b => thread_spawn(W, b) };
}
fn lane_open<W>(cfg: LaneConfig, a) -> Lane {
    return lane_spawn(cfg) { b => thread_spawn(W, b, a) };
}

// lane_open's work: SPAWN starts a thread with its box and returns its id. A
// package whose lane threads take other parameters opens its lanes with it.
fn lane_spawn<SPAWN>(cfg: LaneConfig) -> Lane {
    var n = max(cfg.threads, 1);
    if n > LANE_MOST {
        write_stderr(str("lane: ", n, " threads cut to the most, ", LANE_MOST, "\n"));
        n = LANE_MOST;
    }
    var lane = Lane { .. };
    for i in n {
        let b, e = mail_open(cfg.slots, cfg.size);
        exit_on_error(e);
        lane.boxes.push(b);
        lane.threads.push(SPAWN(b));
    }
    return lane;
}

// A lane of box alone, with no thread: for a test that plays the lane, taking
// the jobs from box itself.
fn lane_of(box: Box) -> Lane {
    var lane = Lane { .. };
    lane.boxes.push(box);
    return lane;
}

// A lane thread's loop: F with each job's tag and bytes, in the order they
// came, until the box is stopped and empty; then closes the box.
fn lane<F>(box: Box) {
    while !mail_stopped(box) {
        // No time limit: a stop wakes this wait too.
        mail_wait(box, -1);
        mail_take(box) { key, tag, bytes => F(tag, bytes); };
    }
    mail_close(box);
}

// Stops every thread of lane, each of which takes what its box holds and
// returns from lane, and waits for them. A full box can't refuse the stop.
// The thread that opened the lane calls it, once the workers have returned.
fn lane_stop(lane: const Lane&) {
    for b in lane.boxes { mail_stop(b); }
    for id in lane.threads { thread_wait(id); }
}

// Sends image with tag to the least busy of lane's boxes, the one holding
// the fewest jobs, and to the others in turn while each is full. Returns
// SENT, FULL when every box is, TOO_LONG, or STALE once the lane is stopped.
// Any thread may call it.
fn lane_send(lane: const Lane&, tag: i32, image: const u8[:]) -> i32 {
    let n = lane.boxes.len;
    guard n > 0 else { return STALE; }
    // Each send starts the scan one box further on, so that ties don't all
    // go to one box and senders don't all read the same box's counts first.
    let start = lane_turn % n;
    lane_turn++;
    var best = start;
    var least: i64 = -1;
    for k in n {
        let i = (start + k) % n;
        let q = mail_queued(address(lane.boxes[i], 0));
        if q >= 0 && (least < 0 || q < least) {
            least = q;
            best = i;
            if q == 0 { break; }
        }
    }
    var r = STALE;
    for k in n {
        let sent = mail_send(address(lane.boxes[(best + k) % n], 0), tag, image);
        if sent == SENT || sent == TOO_LONG { return sent; }
        if sent == FULL { r = sent; }
    }
    return r;
}

// Sends v, a flat value, as lane_send does, for mail_value to read: as
// mail_send_value writes it.
fn lane_send_value(lane: const Lane&, tag: i32, v) -> i32 {
    var one = [v];
    var image: u8[>..] = [];
    one.to_bytes(image);
    return lane_send(lane, tag, image);
}
