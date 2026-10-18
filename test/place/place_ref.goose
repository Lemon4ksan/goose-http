// Placements the shim holds (place.goose): a registered placement's handle,
// the seats read back through it, and a handle of none, which places nothing. The
// machine is given, so the output is the same everywhere. The package is
// declared by place.goose alone; the sidecar beside it names the C.
import std;
import os;
import place from "../../";

fn cores(text: const u8[:]) -> http::Cores {
    let p, err = http::place_parse(str("set c = ", text), "cores");
    assert(err.len == 0);
    return p.sets[0].cores;
}

fn placed(text: const u8[:]) -> http::Place {
    var p, err = http::place_parse(text, "ref.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-7"), true);
    http::place_register(p);
    return p;
}

fn seat(ref: http::PlaceRef, role: const u8[:], i: i64) {
    let p = http::place_of(ref);
    let s = http::place_seat(p, role, i);
    print("  ", role, ": ", if http::cores_count(s.cores) == 0 { str("floats") } else { str(s.cores) });
}

fn main() {
    let a = placed("workers = 2 each 0-1\nhasher = 2 each 4-5\n");
    let b = placed("workers = 2 each 6-7\n");
    let ra = http::place_ref(a);
    let rb = http::place_ref(b);
    print("handles: ", ra.id > 0, " ", rb.id > 0, " ", ra.id != rb.id);
    print("a:");
    for i in 3 { seat(ra, "workers", i); }
    seat(ra, "hasher", 0);
    print("b:");
    seat(rb, "workers", 0);
    seat(rb, "other", 0);
    print("none:");
    seat(http::PlaceRef { .. }, "workers", 0);
    let back = http::place_of(ra);
    print("a, read back: ", back.roles.len, " roles, workers ", http::place_threads(back, "workers", 8));
    // A place_parse result that nothing checked: place_register records the machine.
    var q, err = http::place_parse("workers = 2 each 0-1\n", "unchecked.place");
    assert(err.len == 0);
    assert(http::cores_count(q.cpus) == 0);
    http::place_register(q);
    assert(http::cores_count(q.cpus) > 0);
    print("unchecked, registered: ", http::cores_count(http::place_of(http::place_ref(q)).cpus) > 0);
}
