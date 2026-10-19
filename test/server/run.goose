// http::run (http.goose): it spawns worker_count(cfg) workers, hands each the
// values after cfg, and returns after the last worker has, which each one's
// wait makes later than the spawn.
import std;
import http from "../../";

struct Ran { a: i64, b: i64 }

fn ran(a: i64, b: i64) {
    sleep_ms(30);
    qput(Ran { a: a, b: b });
}

thread_fn worker(cfg: http::Config) { ran(-1, -1); }
thread_fn worker_a(cfg: http::Config, a: i64) { ran(a, -1); }
thread_fn worker_ab(cfg: http::Config, a: i64, b: i64) { ran(a, b); }

// What n workers queued, and that nothing more is queued.
fn show(name: const u8[:], n: i64) {
    print(name, ":");
    for i in n {
        let r, ok = qpoll<Ran>();
        assert(ok);
        print("  values ", r.a, " ", r.b);
    }
    let r, more = qpoll<Ran>();
    assert(!more);
}

fn main() {
    http::run(http::Config { workers: 3, .. }, worker);
    show("no values", 3);
    http::run(http::Config { workers: 3, .. }, 5, worker_a);
    show("one value", 3);
    http::run(http::Config { workers: 2, .. }, 5, 6, worker_ab);
    show("two values", 2);
}
