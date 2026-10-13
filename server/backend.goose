// The benchmark server's worker thread for /later and /events: it owns a box
// of its own, takes jobs from the HTTP workers, and answers each, after a
// delay its own timer table keeps, by mail to the exchange's address
// (http::later). A job asks for count replies, one every delay milliseconds:
// one for /later, as many as the events for /events.
import std;
import http;

// A job's tag: the kind of job. A reply's tag: whether more follow.
let JOB_LATER: i32 = 1;
let JOB_EVENTS: i32 = 2;
let REPLY_MORE: i32 = 1;
let REPLY_LAST: i32 = 2;

// A job as the backend keeps it, and as it crosses a box
// (http::mail_send_value).
struct Job { reply: http::MailAddress, delay: i64, count: i64, sent: i64, id: u8[..32] }

// The most bytes a job takes in a box: its image, which holds id's whole
// capacity, is 74 bytes.
let JOB_SIZE: i32 = 80;
// The most bytes a reply takes in a worker's box: the id and the reply's
// number.
let REPLY_SIZE: i32 = 64;

// Takes jobs from box until a job of no kind it knows, keeping up to
// capacity at once; a job past that is answered at once with "busy".
thread_fn backend(box: http::Box, capacity: i64) {
    var timers = http::timer_table(capacity);
    var jobs: Job[>..] = [];
    var free: i64[>..<] = [];
    for i in capacity {
        jobs.push(Job { .. });
        free.push(capacity - 1 - i);
    }
    var reply: u8[>..] = [];
    var running = true;

    // Sends job i its next reply, and frees it after the last.
    fn answer(i: i64, now: i64) {
        let j .= jobs[i];
        j.sent++;
        reply.clear();
        reply.append(j.id);
        format(reply, " ", j.sent);
        let last = j.sent >= j.count;
        // A FULL box loses this reply, as STALE does for an exchange that's
        // gone: the exchange waits out its time limit.
        http::mail_send(j.reply, if last { REPLY_LAST } else { REPLY_MORE }, reply);
        if last { free.push(i); }
        else { http::arm(timers, i as u64, now + j.delay); }
    }

    while running {
        let now = http::net_clock_ms();
        let due, any = http::next_due(timers);
        http::mail_wait(box, if any { min(max(due - now, 0), 1000) as i32 } else { 1000 });
        let t = http::net_clock_ms();
        http::mail_take(box) { key, tag, bytes =>
            var j = Job { .. };
            let ok = http::mail_value(bytes, j);
            j.delay = max(j.delay, 0);
            j.count = max(j.count, 1);
            j.sent = 0;
            if tag != JOB_LATER && tag != JOB_EVENTS || !ok {
                running = false;
            } else if free.len == 0 {
                http::mail_send(j.reply, REPLY_LAST, "busy");
            } else {
                let i = free.pop();
                jobs[i] = j;
                http::arm(timers, i as u64, t + j.delay);
            }
        };
        http::expire(timers, t) { key => answer(key as i64, t); };
    }
    http::mail_close(box);
}
