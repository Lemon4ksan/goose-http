// The benchmark server's thread for /later and /events: it takes jobs from
// the HTTP workers off Goose's queue of Job, and answers each, after a delay
// its own timer table keeps, by mail to the exchange's address (http::later).
// A job asks for count replies, one every delay milliseconds: one for
// /later, as many as the events for /events.
import std;
import os;
import http;

// A reply's tag: whether more follow.
let REPLY_MORE: i32 = 1;
let REPLY_LAST: i32 = 2;

// A job as the backend keeps it, and as it crosses the queue.
struct Job { reply: http::MailAddress, delay: i64, count: i64, sent: i64, id: u8[..32] }

// The most jobs the queue holds: a worker that finds it full answers 503.
let JOBS_QUEUED: i64 = 256;
// The most bytes a reply takes in a worker's box: the id and the reply's
// number.
let REPLY_SIZE: i32 = 64;

// Takes jobs for as long as the process runs, keeping up to capacity at
// once; a job past that is answered at once with "busy".
thread_fn backend(capacity: i64) {
    var check: u8[>..] = [];
    let check_stale = env("MAIL_CHECK_STALE", check) && check == "1";
    var timers = http::timer_table(capacity);
    var jobs: Job[>..] = [];
    var free: i64[>..<] = [];
    for i in capacity {
        jobs.push(Job { .. });
        free.push(capacity - 1 - i);
    }
    var reply: u8[>..] = [];

    // Sends job i its next reply, and frees it after the last.
    fn answer(i: i64, now: i64) {
        let j .= jobs[i];
        j.sent++;
        reply.clear();
        reply.append(j.id);
        format(reply, " ", j.sent);
        let last = j.sent >= j.count;
        // A FULL box loses this reply, as STALE does for an exchange that's
        // gone: the exchange waits out its time limit. REPLY_SIZE holds any
        // reply, so none is TOO_LONG.
        var result = http::mail_send(j.reply, if last { REPLY_LAST } else { REPLY_MORE }, reply);
        if check_stale && (j.id == "gone" || j.id == "expired") {
            assert(result == http::STALE && !http::mail_live(j.reply));
            print("mail stale: ", j.id);
        }
        // A burst's pieces go back to back, retrying a full box as
        // goose-rest's rest::answer does: none may find the exchange stale
        // while it waits again for the next.
        if check_stale && j.id == "burst" {
            while result == http::FULL { result = http::mail_send(j.reply, if last { REPLY_LAST } else { REPLY_MORE }, reply); }
            assert(result == http::SENT);
        }
        if last { free.push(i); }
        else { http::arm(timers, i as u64, now + j.delay); }
    }

    while true {
        let now = http::net_clock_ms();
        let due, any = http::next_due(timers);
        var j, got = qget<Job>(if any { min(max(due - now, 0), 1000) } else { 1000 });
        let t = http::net_clock_ms();
        while got {
            j.delay = max(j.delay, 0);
            j.count = max(j.count, 1);
            j.sent = 0;
            if free.len == 0 {
                http::mail_send(j.reply, REPLY_LAST, "busy");
            } else {
                let i = free.pop();
                jobs[i] = j;
                http::arm(timers, i as u64, t + j.delay);
            }
            j, got = qpoll<Job>();
        }
        http::expire(timers, t) { key => answer(key as i64, t); };
    }
}
