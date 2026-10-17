// Seats taken for real: a thread pinned each to a core of its own reads its
// affinity back, and a low thread lowers its priority without failing. Where
// threads can't be pinned (macOS), a seat has no cores, and taking it does
// nothing. The package is declared by place.goose alone; the sidecar beside it
// names the C.
import std;
import os;
import place from "../../";

// Takes s, then says whether the thread's cores are the seat's.
thread_fn seated(s: http::Seat, pins: bool) {
    http::take_seat(s);
    let now = http::place_current();
    qput(!pins || http::cores_same(now, s.cores));
}

fn main() {
    var cpus = http::Cores { .. };
    let pins = http::place_cpus_c(cpus.bits) > 0;
    // The process's first two cores, whichever they are, as a set.
    var two = http::Cores { .. };
    http::cores_add(two, http::cores_nth(cpus, 0));
    http::cores_add(two, http::cores_nth(cpus, min(1, http::cores_count(cpus) - 1)));
    let text = str("set two = ", two, "\nlane = 2 each two\nslow = 1 within two low\n");
    var p, err = http::place_parse(text, "seat.place");
    assert(err.len == 0);
    http::place_check(p, cpus, pins);
    var ids: i64[>..] = [];
    for i in 2 { ids.push(thread_spawn(seated, http::place_seat(p, "lane", i), pins)); }
    ids.push(thread_spawn(seated, http::place_seat(p, "slow", 0), pins));
    var ok = 0;
    for id in ids {
        thread_wait(id);
        if qget<bool>() { ok++; }
    }
    print(ok, " of 3 threads read their seats back");
}
