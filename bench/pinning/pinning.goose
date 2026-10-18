// Task 045's spike: where threads run, measured. examples/later with a short
// route beside the slow one: GET /fast is answered in the handler, and GET
// /primes/N counts the primes below N on a CPU lane. bench/pinning.sh gives
// each layout as a placement file (place.goose): the workers' role is
// "workers" and the lane's "lane".
//
//   pinning [--port N] [--place FILE]
import std;
import os;
import http from "../../";

struct Job { reply: http::MailAddress, n: i64 }

let JOB: i32 = 1;
let JOB_SIZE: i32 = 64;
let MAX_N = 10000000;

thread_fn lane(box: http::Box, at: http::Seat) {
    http::take_seat(at);
    var reply: u8[>..] = [];
    while !http::mail_stopped(box) {
        http::mail_wait(box, -1);
        http::mail_take(box) { key, tag, bytes =>
            var j = Job { .. };
            if tag == JOB && http::mail_value(bytes, j) && http::mail_live(j.reply) {
                reply.clear();
                format(reply, primes_below(j.n), "\n");
                http::mail_send(j.reply, 0, reply);
            }
        };
    }
    http::mail_close(box);
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

thread_fn worker(cfg: http::Config, to: http::MailAddress) {
    let e = http::serve(cfg, false) { ev, st, out => handle(ev, out, to); };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn handle(ev: http::Event, out: http::Reply, to: http::MailAddress) {
    if ev.kind == http::REQUEST {
        var r = http::router(ev.req);
        if http::on(r, "GET", "/fast") {
            http::respond(out, 200, "text/plain", "ok\n");
        } else if http::on(r, "GET", "/primes/:n") {
            let n, ok = parse_int(http::param(r, "n"));
            guard ok && n >= 0 && n <= MAX_N else { http::respond(out, 404, "text/plain", ""); return; }
            guard http::mail_send_value(to, JOB, Job { reply: http::later(out, 2000), n: n }) == http::SENT else {
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
}

fn main() {
    var port: i64 = 8080;
    let a = args();
    for w, i in a {
        if w == "--port" && i + 1 < a.len {
            let p, ok = parse_int(a[i + 1]);
            if ok { port = p; }
        }
    }
    http::exit_on_error(http::stop_on_signals());
    let place = http::place_load();
    let cfg = http::Config { port: port as i32, place: http::place_ref(place), mail_slots: 256, max_waiting: 4096, .. };
    let b, err = http::mail_open(256, JOB_SIZE);
    http::exit_on_error(err);
    let lt = thread_spawn(lane, b, http::place_seat(place, "lane", 0));
    let n = http::worker_count(cfg);
    print("listening on port ", cfg.port, " with ", n, " workers");
    http::run(cfg, http::address(b, 0), worker);
    http::mail_stop(b);
    thread_wait(lt);
}
