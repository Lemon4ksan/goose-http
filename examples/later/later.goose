// An answer that waits for another thread: /primes/N counts the primes below
// N on a backend thread, so the worker goes on serving other requests
// meanwhile, and answers 504 if the count takes longer than 2 seconds. One
// backend thread takes every worker's jobs, one at a time.
//
//   curl localhost:8080/primes/1000000
import std;
import http from "../../";

// What a worker sends the backend: where to reply, and the job.
struct Job { reply: http::MailAddress, n: i64 }

let JOB: i32 = 1;
// The most bytes a job takes in the backend's box: its image
// (http::mail_send_value) is about 25.
let JOB_SIZE: i32 = 64;
let MAX_N = 10000000;

// Takes jobs from its box for as long as the process runs, and mails each
// count to the exchange that asked.
thread_fn backend(box: http::Box) {
    var reply: u8[>..] = [];
    loop {
        http::mail_wait(box, -1);
        http::mail_take(box) { key, tag, bytes =>
            var j = Job { .. };
            if tag == JOB && http::mail_value(bytes, j) {
                reply.clear();
                format(reply, primes_below(j.n), "\n");
                // STALE when the exchange has timed out or its client has
                // gone: nobody waits for this reply any more.
                http::mail_send(j.reply, 0, reply);
            }
        };
    }
}

fn primes_below(n: i64) -> i64 {
    guard n > 2 else { return 0; }
    var composite: bool[>..] = [];
    composite.resize(n, false);
    var count = 0;
    for i in 2..n {
        guard !composite[i] else { continue; }
        count++;
        var k = i * i;
        while k < n {
            composite[k] = true;
            k += i;
        }
    }
    return count;
}

// The handler needs state for WAKE and TIMEOUT, though it keeps none.
thread_fn worker(cfg: http::Config, backend: http::MailAddress) {
    let e = http::serve(cfg, false) { ev, st, out =>
        if ev.kind == http::REQUEST {
            var r = http::router(ev.req);
            if http::on(r, "GET", "/primes/:n") {
                let n, ok = parse_int(http::param(r, "n"));
                guard ok && n >= 0 && n <= MAX_N else { http::respond(out, 404, "text/plain", ""); return; }
                let job = Job { reply: http::later(out, 2000), n: n };
                guard http::mail_send_value(backend, JOB, job) == http::SENT else {
                    http::respond(out, 503, "text/plain", "busy\n");
                    return;
                }
            } else {
                http::otherwise(r, out);
            }
        } else if ev.kind == http::WAKE {
            http::respond(out, 200, "text/plain", ev.data);
        } else if ev.kind == http::TIMEOUT {
            http::respond(out, 504, "text/plain", "timeout\n");
        }
    };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn main() {
    let s = http::stop_on_signals();
    guard s == 0 else { http::report(http::Error { call: "sigaction", code: -s }); exit(1); }
    // mail_slots and max_waiting turn waiting on: each worker's box holds 256
    // replies at once, and up to 1024 exchanges wait at once.
    let cfg = http::Config { port: 8080, mail_slots: 256, max_waiting: 1024, .. };
    let b, err = http::mail_open(256, JOB_SIZE);
    guard err == 0 else { http::report(http::Error { call: "mail_open", code: -err }); exit(1); }
    thread_spawn(backend, b);
    print("listening on port ", cfg.port);
    var ids: i64[>..] = [];
    for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg, http::address(b, 0))); }
    for id in ids { thread_wait(id); }
}
