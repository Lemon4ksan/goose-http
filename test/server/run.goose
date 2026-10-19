// http::run (http.goose): it spawns worker_count(cfg) workers, each with its
// index in Config.worker and so a seat of its own, hands each the values
// after cfg, and returns after the last worker has, which the slowest is
// here. A placed worker spawned without an index floats, with a warning. The
// machine is given, so the output is the same everywhere.
import std;
import http from "../../";

struct Ran { worker: i64, core: i64, a: i64, b: i64 }

fn cores(text: const u8[:]) -> http::Cores {
    let p, err = http::place_parse(str("set c = ", text), "cores");
    assert(err.len == 0);
    return p.sets[0].cores;
}

// Queues the worker's index, the one core of the seat its loop would take, or
// -1 where it floats, and its values, after a wait that grows with its index.
fn ran(cfg: const http::Config&, a: i64, b: i64) {
    sleep_ms(20 * max(cfg.worker, 0));
    let s = http::worker_seat(cfg);
    let core = if http::cores_count(s.cores) == 1 { http::cores_nth(s.cores, 0) } else { -1 };
    qput(Ran { worker: cfg.worker, core: core, a: a, b: b });
}

thread_fn worker(cfg: http::Config) { ran(cfg, -1, -1); }
thread_fn worker_a(cfg: http::Config, a: i64) { ran(cfg, a, -1); }
thread_fn worker_ab(cfg: http::Config, a: i64, b: i64) { ran(cfg, a, b); }

// What n workers queued, by index, and that nothing more is queued.
fn show(name: const u8[:], n: i64) {
    print(name, ":");
    var got: Ran[>..] = [];
    for i in n {
        let r, ok = qpoll<Ran>();
        assert(ok);
        got.push(r);
    }
    let r, more = qpoll<Ran>();
    assert(!more);
    sort(got) { x, y => x.worker < y.worker };
    for g in got {
        print("  worker ", g.worker, ": ", if g.core < 0 { str("floats") } else { str("core ", g.core) },
              ", values ", g.a, " ", g.b);
    }
}

fn main() {
    var p, err = http::place_parse("workers = 3 each 4-7\n", "run.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-7"), true);
    http::place_register(p);
    let placed = http::Config { workers: 1, place: http::place_ref(p), .. };
    http::run(placed, worker);
    show("placed", 3);
    http::run(placed, 5, worker_a);
    show("placed, one value", 3);
    http::run(http::Config { workers: 2, .. }, 5, 6, worker_ab);
    show("unplaced, two values", 2);
    thread_wait(thread_spawn(worker, placed));
    show("placed, outside run", 1);
}
