// Placement files (place.goose): what a file parses to, the error for each
// kind of mistake, the warnings for what a machine can't do, and the seat
// each thread gets. The machine is given, not this one's, so the output is
// the same everywhere. The package is declared by place.goose alone; the
// sidecar beside it names the C.
import std;
import os;
import place from "../../";

// The desktop of task 046: 8 cores, 16 hardware threads, CPU n and n+8 on
// one core.
let DESKTOP = """
    # place/desktop.place
    set front = 0-3        exclusive   # no other role may use these
    set flows = 4-5                    # shared by the workflows
    set db    = 6-7, 12-15
    workers  = 4 each front incoming   # one per core
    hasher   = 1 within flows
    checkout = 1 within flows low
    writer   = core 7
    reports  = 4 within db
    """;

fn show(p: http::Place) {
    for s in p.sets {
        print("set ", s.name, if s.anon { " (a role's own)" } else { "" }, " = ", s.cores,
              if s.exclusive { " exclusive" } else { "" });
    }
    for r in p.roles {
        let how = if r.how == http::PLACE_EACH { " each" } else if r.how == http::PLACE_WITHIN { " within" } else { "" };
        print(r.name, " = ", r.threads, how, if r.set >= 0 { str(" ", p.sets[r.set].name) } else { str("") },
              if r.low { " low" } else { "" }, if r.incoming { " incoming" } else { "" });
    }
}

fn cores(text: const u8[:]) -> http::Cores {
    let p, err = http::place_parse(str("set c = ", text), "cores");
    assert(err.len == 0);
    return p.sets[0].cores;
}

fn seat(p: const http::Place&, role: const u8[:], i: i64) {
    let s = http::place_seat(p, role, i);
    print("  ", role, " ", i, ": ", if http::cores_count(s.cores) == 0 { str("floats") } else { str(s.cores) },
          if s.low { " low" } else { "" }, if s.incoming >= 0 { str(" incoming ", s.incoming) } else { str("") });
}

fn test_desktop() {
    var p, err = http::place_parse(DESKTOP, "desktop.place");
    assert(err.len == 0);
    show(p);
    // The whole desktop: no warnings.
    http::place_check(p, cores("0-15"), true);
    print("seats on 16 cores:");
    for i in 5 { seat(p, "workers", i); }
    seat(p, "hasher", 0);
    seat(p, "checkout", 0);
    seat(p, "writer", 0);
    seat(p, "reports", 3);
    seat(p, "mailer", 0);
    print("threads: workers ", http::place_threads(p, "workers", 16), ", writer ", http::place_threads(p, "writer", 1),
          ", mailer ", http::place_threads(p, "mailer", 2));
}

// The same file on a smaller machine, a container given cores 0-1 and 4-7:
// cores it lacks are skipped, and 4 workers share the 2 cores of front left.
fn test_small_machine() {
    var p, err = http::place_parse(DESKTOP, "desktop.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-1, 4-7"), true);
    print("seats on cores 0-1, 4-7:");
    for i in 3 { seat(p, "workers", i); }
    seat(p, "reports", 0);
    seat(p, "mailer", 0);
    print("threads: workers ", http::place_threads(p, "workers", 16));
}

// A role on cores an exclusive set holds loses them, and floats when none
// are left; a count above the code's most is cut to it.
fn test_exclusive_and_max() {
    var p, err = http::place_parse("""
        set front = 0-3 exclusive
        workers = 4 each front
        writer = core 2
        reports = 3 within 2-5
        """, "overlap.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-7"), true);
    print("seats with an exclusive set:");
    seat(p, "writer", 0);
    seat(p, "reports", 0);
    seat(p, "other", 0);
    print("threads: reports ", http::place_threads(p, "reports", 1, 2));
}

// Exclusive sets that hold every core leave a role the file doesn't name
// nowhere of its own, so it floats onto them; incoming on a role whose
// threads have several cores, or none, can't apply. Each warns. A negative
// index is taken as 0.
fn test_warnings() {
    var p, err = http::place_parse("""
        set front = 0-3 exclusive
        set back = 4-7 exclusive
        workers = 4 each front
        hasher = 1 within back incoming
        writer = core 2 incoming
        reports = 2 incoming
        """, "full.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-7"), true);
    print("seats with every core exclusive:");
    seat(p, "other", 0);
    seat(p, "writer", 0);
    seat(p, "workers", -1);
}

// macOS: no affinity, so one warning and every thread floats; low stays.
fn test_no_affinity() {
    var p, err = http::place_parse(DESKTOP, "desktop.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-9"), false);
    print("seats where threads can't be pinned:");
    seat(p, "workers", 0);
    seat(p, "checkout", 0);
}

fn test_dev() {
    var p, err = http::place_parse("""
        # place/dev.place: a 2-core laptop. Nothing exclusive, nothing pinned.
        workers = 2
        hasher  = 1 low
        """, "dev.place");
    assert(err.len == 0);
    http::place_check(p, cores("0-1"), true);
    print("dev: workers ", http::place_threads(p, "workers", 8));
    seat(p, "workers", 0);
    seat(p, "hasher", 0);
}

// A file written on Windows, with CRLF line ends, and tabs between words and
// before a comment.
fn test_crlf_and_tabs() {
    let p, err = http::place_parse("# crlf.place\r\nset\tfront = 0-1,\t3\texclusive\t# a comment\r\n\r\nworkers\t=\t2\teach front\r\nhasher = 1 low\r\n", "crlf.place");
    print("crlf and tabs: error \"", err, "\"");
    show(p);
}

fn test_errors() {
    let bad = [
        "workers 4",
        "workers = 0",
        "workers = 4 each",
        "workers = 4 each front",
        "workers = 4 everywhere",
        "workers = 4 core 1-2",
        "workers = 4 core 1 within 2",
        "set front = 0-3 shared",
        "set front = 3-0",
        "set front = 0-1024",
        "set front =",
        "set front = 0\nset front = 1",
        "set a b = 0",
        "w√rkers = 1",
        "workers = 1\nworkers = 2",
    ];
    for text in bad {
        let p, err = http::place_parse(text, "bad.place");
        print(err);
    }
}

fn main() {
    test_desktop();
    test_small_machine();
    test_exclusive_and_max();
    test_warnings();
    test_no_affinity();
    test_dev();
    test_crlf_and_tabs();
    test_errors();
}
