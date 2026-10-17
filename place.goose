// Placement: where each thread runs. The code names roles, the workers and
// each lane, and a placement file, one per kind of machine, maps roles to
// cores at the start (place_load). Without a file every thread floats, as the
// OS decides. The file, a line each, with # comments:
//
//   set front = 0-3 exclusive     a named set of cores; exclusive: a role
//   set flows = 4-5               that doesn't name it doesn't run on them
//   workers = 4 each front        4 threads, each on a core of its own in front
//   hasher = 1 within flows low   1 thread anywhere in flows, at low priority
//   writer = core 7               on core 7, with the code's thread count
//   reports = 2                   2 threads, floating
//
// each and within take a set's name or cores (4-5, 8). incoming: a thread on
// one core is given the connections whose interrupts that core takes
// (SO_INCOMING_CPU, Linux). A role the file doesn't name floats on the cores
// no exclusive set holds.
//
// Nothing about the hardware stops the start: cores the process can't use,
// more threads than a set's cores (they wrap around), cores an exclusive set
// holds (dropped), and a platform with no affinity (macOS) each print a
// warning. A file that doesn't parse does stop it.
//
// The calls are the shim's (shim/place.c), and the lines are read as a .env
// file's are (settings.goose). Nothing here knows HTTP, so that it can move
// to a package of its own unchanged, as mail.goose can.
namespace http;

import std;
import os;
import settings;

// The most cores a placement names, as Linux's CPU_SETSIZE.
let PLACE_CPUS: i64 = 1024;

// The environment variable naming a placement file when no --place is given.
let PLACE_ENV = "GOOSE_PLACE";

// A set of cores, a bit each.
struct Cores { bits: u64[16] }

// How a role's threads take its set's cores.
let PLACE_FLOAT: i32 = 0;
let PLACE_EACH: i32 = 1;
let PLACE_WITHIN: i32 = 2;

// A named set, or the cores a role names itself (anon, under the role's name).
struct PlaceSet { name: u8[..32], cores: Cores, exclusive: bool, anon: bool }

struct PlaceRole {
    name: u8[..32],
    threads: i64,       // 0: the code's count
    how: i32,
    set: i32 = -1,      // into Place.sets, for each and within
    low: bool,
    incoming: bool,
}

// A placement file's contents, flat, so that it crosses thread_spawn in a
// Config. cpus are the cores the process may use, and pins whether the
// platform pins threads, which place_load sets for this machine.
struct Place {
    sets: PlaceSet[..16],
    roles: PlaceRole[..32],
    cpus: Cores,
    pins: bool,
}

// Where one thread runs: its cores, none for wherever the OS puts it, its
// priority, and its one core for SO_INCOMING_CPU, or -1.
struct Seat { cores: Cores, low: bool, incoming: i64 = -1 }

// The shim's calls. place_cpus writes the process's cores into out and
// returns 1 where threads can be pinned, 0 where they can't (macOS), or
// -code; place_current writes the calling thread's. place_self pins the
// calling thread to cores, and place_low lowers its priority: 0 or -code.
// place_next returns role's next index, from 0, for threads that take their
// seats in the order they start. place_once is true the first time for what.
extern "place_cpus" fn place_cpus_c(out: u64[:]) -> i32;
extern "place_current" fn place_current_c(out: u64[:]) -> i32;
extern "place_self" fn place_self_c(cores: const u64[:]) -> i32;
extern "place_low" fn place_low_c() -> i32;
extern "place_next" fn place_next_c(role: i32) -> i64;
extern "place_once" fn place_once_c(what: i32) -> i32;
extern "place_incoming" fn place_incoming_c(fd: i32, cpu: i32) -> i32;

// What place_once tracks: a warning that a thread, not place_load, prints.
let PLACE_ONCE_PIN: i32 = 0;
let PLACE_ONCE_LOW: i32 = 1;
let PLACE_ONCE_INCOMING: i32 = 2;

fn cores_has(c: Cores, n: i64) -> bool { (c.bits[n >> 6] >> (n % 64)) & 1 != 0 }
fn cores_add(c: Cores&, n: i64) { c.bits[n >> 6] |= (1 as u64) << (n % 64); }

fn cores_count(c: Cores) -> i64 {
    var n = 0;
    for w in c.bits { n += popcount(w); }
    return n;
}

fn cores_and(a: Cores, b: Cores) -> Cores {
    var c = Cores { .. };
    for i in 16 { c.bits[i] = a.bits[i] & b.bits[i]; }
    return c;
}

fn cores_minus(a: Cores, b: Cores) -> Cores {
    var c = Cores { .. };
    for i in 16 { c.bits[i] = a.bits[i] & ~b.bits[i]; }
    return c;
}

fn cores_same(a: Cores, b: Cores) -> bool {
    for i in 16 { guard a.bits[i] == b.bits[i] else { return false; } }
    return true;
}

// The kth core of c, counting from 0, or -1.
fn cores_nth(c: Cores, k: i64) -> i64 {
    var left = k;
    for n in PLACE_CPUS {
        guard cores_has(c, n) else { continue; }
        if left == 0 { return n; }
        left--;
    }
    return -1;
}

// c as the file writes it: "0-3, 8".
fn format(out: u8[>..]&, c: Cores) {
    var first = true;
    var n = 0;
    while n < PLACE_CPUS {
        guard cores_has(c, n) else {
            n++;
            continue;
        }
        var m = n;
        while m + 1 < PLACE_CPUS && cores_has(c, m + 1) { m++; }
        if !first { out.append(", "); }
        first = false;
        if m > n { format(out, n, "-", m); } else { format(out, n); }
        n = m + 1;
    }
}

fn place_role_at(p: const Place&, role: const u8[:]) -> i64 {
    for r, i in p.roles { if r.name == role { return i; } }
    return -1;
}

fn place_set_at(p: const Place&, name: const u8[:]) -> i64 {
    for s, i in p.sets { if !s.anon && s.name == name { return i; } }
    return -1;
}

// Parses a placement file's text, name saying where it came from. Returns the
// placement, and "" or the error, as "name:line: message".
fn place_parse(text: const u8[:], name: const u8[:]) -> Place, u8[] {
    var p = Place { .. };
    var n = 0;

    fn fail(msg: const u8[:]) { return Place { .. }, str(name, ":", n, ": ", msg) from place_parse; }

    fn check_name(w: const u8[:]) {
        guard w.len > 0 && w.len < 32 else { fail(str("a name of 1 to 31 bytes, not \"", w, "\"")); }
        for c in w {
            guard (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' else {
                fail(str("a name of letters, digits, _ and -, not \"", w, "\""));
            }
        }
    }

    fn number(w: const u8[:]) -> i64 {
        let v, ok = parse_int(w);
        guard ok && v >= 0 && v < PLACE_CPUS else { fail(str("a core from 0 to ", PLACE_CPUS - 1, ", not \"", w, "\"")); }
        return v;
    }

    // The cores ws[at..] give, as "0-3, 8" (spaces anywhere), up to the first
    // word that doesn't start with a digit or a comma. Returns them, and the
    // index of that word.
    fn cores_from(ws: const u8[:][:], at: i64) -> Cores, i64 {
        var text: u8[>..] = [];
        var i = at;
        while i < ws.len && ((ws[i][0] >= '0' && ws[i][0] <= '9') || ws[i][0] == ',') {
            text.append(ws[i]);
            i++;
        }
        guard text.len > 0 else { fail("cores, as 0-3, 8"); }
        var c = Cores { .. };
        each_split(text, ',') {
            let dash = find(it, "-");
            let lo = number(if dash >= 0 { it[..dash] } else { it });
            let hi = if dash >= 0 { number(it[dash + 1..]) } else { lo };
            guard lo <= hi else { fail(str("a range from low to high, not \"", it, "\"")); }
            for k in lo..hi + 1 { cores_add(c, k); }
        };
        return c, i;
    }

    fn add_set(s: PlaceSet) -> i32 {
        guard p.sets.len < 16 else { fail("more than 16 sets, a role's own cores included"); }
        p.sets.push(s);
        return (p.sets.len - 1) as i32;
    }

    fn set_line(set: const u8[:], ws: const u8[:][:]) {
        check_name(set);
        guard place_set_at(p, set) < 0 else { fail(str("set ", set, " twice")); }
        let c, at = cores_from(ws, 0);
        var exclusive = false;
        if at < ws.len && ws[at] == "exclusive" {
            exclusive = true;
            guard at + 1 == ws.len else { fail(str("nothing after exclusive, not \"", ws[at + 1], "\"")); }
        } else if at < ws.len {
            fail(str("cores, then exclusive or nothing, not \"", ws[at], "\""));
        }
        add_set(PlaceSet { name: set, cores: c, exclusive: exclusive, anon: false });
    }

    fn role_line(role: const u8[:], ws: const u8[:][:]) {
        check_name(role);
        guard place_role_at(p, role) < 0 else { fail(str(role, " twice")); }
        guard p.roles.len < 32 else { fail("more than 32 roles"); }
        var r = PlaceRole { name: role, .. };
        var i = 0;
        if ws.len > 0 && ws[0][0] >= '0' && ws[0][0] <= '9' {
            let v, ok = parse_int(ws[0]);
            guard ok && v > 0 else { fail(str("a thread count of 1 or more, not \"", ws[0], "\"")); }
            r.threads = v;
            i = 1;
        }
        while i < ws.len {
            let w = ws[i];
            if w == "each" || w == "within" || w == "core" {
                guard r.set < 0 else { fail(str("one of each, within, or core, not two")); }
                guard i + 1 < ws.len else { fail(str(w, " needs ", if w == "core" { "a core" } else { "a set or cores" })); }
                let at = ws[i + 1][0];
                if w != "core" && !((at >= '0' && at <= '9') || at == ',') {
                    let s = place_set_at(p, ws[i + 1]);
                    guard s >= 0 else { fail(str("no set ", ws[i + 1], " above")); }
                    r.set = s as i32;
                    i += 2;
                } else {
                    let c, next = cores_from(ws, i + 1);
                    guard w != "core" || cores_count(c) == 1 else { fail("core takes one core: within takes several"); }
                    r.set = add_set(PlaceSet { name: role, cores: c, exclusive: false, anon: true });
                    i = next;
                }
                r.how = if w == "each" { PLACE_EACH } else { PLACE_WITHIN };
            } else if w == "low" {
                r.low = true;
                i++;
            } else if w == "incoming" {
                r.incoming = true;
                i++;
            } else {
                fail(str("a count, each, within, core, low, or incoming, not \"", w, "\""));
            }
        }
        p.roles.push(r);
    }

    fn line_of(name: const u8[:], value: const u8[:], eq: bool) {
        guard eq else { fail("NAME = ..., or set NAME = cores"); }
        let left = words(name);
        let right = words(value);
        if left.len == 2 && left[0] == "set" {
            set_line(left[1], right);
        } else if left.len == 1 {
            role_line(left[0], right);
        } else {
            fail("NAME = ..., or set NAME = cores");
        }
    }

    each_setting(text) { line, name, value, eq =>
        n = line;
        line_of(name, value, eq);
    };
    return p, "";
}

// The exclusive sets' cores but set's own.
fn place_exclusive(p: const Place&, set: i64) -> Cores {
    var c = Cores { .. };
    for s, i in p.sets {
        if s.exclusive && i != set {
            for k in 16 { c.bits[k] |= s.cores.bits[k]; }
        }
    }
    return c;
}

// The cores role r runs on, of the process's: its set's, but those an
// exclusive set of another holds. None for a role that floats, or whose
// cores were all dropped.
fn place_cores(p: const Place&, r: const PlaceRole&) -> Cores {
    guard r.set >= 0 else { return Cores { .. }; }
    return cores_minus(cores_and(p.sets[r.set].cores, p.cpus), place_exclusive(p, r.set));
}

fn place_warn(msg: const u8[:]) { write_stderr(str("place: ", msg, "\n")); }

// Records the machine in p, cpus and pins as place_cpus gives them, and
// prints a warning for each thing p names that the machine can't do.
fn place_check(p: Place&, cpus: Cores, pins: bool) {
    p.cpus = cpus;
    p.pins = pins;
    var places = false;
    for s in p.sets { if s.exclusive { places = true; } }
    for r in p.roles { if r.set >= 0 { places = true; } }
    guard pins else {
        if places { place_warn("this platform can't pin threads: every thread floats"); }
        return;
    }
    for s in p.sets {
        let gone = cores_minus(s.cores, cpus);
        if cores_count(gone) > 0 {
            place_warn(str(if s.anon { "role " } else { "set " }, s.name, ": cores ", gone,
                           " aren't the process's (", cpus, "); skipped"));
        }
    }
    for r in p.roles {
        guard r.set >= 0 else { continue; }
        let mine = cores_and(p.sets[r.set].cores, cpus);
        let taken = cores_and(mine, place_exclusive(p, r.set));
        guard cores_count(taken) > 0 else { continue; }
        let left = cores_minus(mine, taken);
        if cores_count(left) > 0 {
            place_warn(str("role ", r.name, ": cores ", taken, " belong to an exclusive set; it runs on ", left));
        } else {
            place_warn(str("role ", r.name, ": cores ", taken, " belong to an exclusive set; it floats"));
        }
    }
}

// The threads role gets: the file's count, or the code's, threads, where the
// file gives none. A count above max, unless max is 0, is cut to it, and a
// role placed each on fewer cores than its threads wraps around; each prints
// a warning.
fn place_threads(p: const Place&, role: const u8[:], threads: i64, max: i64 = 0) -> i64 {
    let at = place_role_at(p, role);
    guard at >= 0 else { return threads; }
    let r = p.roles[at];
    var n = if r.threads > 0 { r.threads } else { threads };
    if max > 0 && n > max {
        place_warn(str("role ", role, ": ", n, " threads cut to the code's most, ", max));
        n = max;
    }
    if r.how == PLACE_EACH && p.pins {
        let k = cores_count(place_cores(p, r));
        if k > 0 && n > k { place_warn(str("role ", role, ": ", n, " threads on ", k, " cores; they share them")); }
    }
    return n;
}

// The seat of role's thread i: its set's core i (wrapping around) for each,
// any of its cores for within, and otherwise the cores no exclusive set
// holds, or none where that's every core.
fn place_seat(p: const Place&, role: const u8[:], i: i64) -> Seat {
    var s = Seat { .. };
    let at = place_role_at(p, role);
    if at >= 0 {
        s.low = p.roles[at].low;
    }
    guard p.pins else { return s; }
    var c = if at >= 0 { place_cores(p, p.roles[at]) } else { Cores { .. } };
    let k = cores_count(c);
    if k == 0 {
        c = cores_minus(p.cpus, place_exclusive(p, -1));
        if cores_same(c, p.cpus) { c = Cores { .. }; }
    } else if p.roles[at].how == PLACE_EACH {
        let core = cores_nth(c, i % k);
        c = Cores { .. };
        cores_add(c, core);
    }
    s.cores = c;
    if at >= 0 && p.roles[at].incoming && cores_count(c) == 1 { s.incoming = cores_nth(c, 0); }
    return s;
}

// The seat of role's next thread to start, for threads that don't know their
// index, such as workers.
fn place_next_seat(p: const Place&, role: const u8[:]) -> Seat {
    let at = place_role_at(p, role);
    guard at >= 0 else { return place_seat(p, role, 0); }
    return place_seat(p, role, place_next_c(at as i32));
}

// Puts the calling thread on its seat: a thread calls it first, before it
// touches memory of its own, since Linux puts a page on the NUMA node of the
// thread that first writes it. A failure prints one warning per process, and
// the thread goes on where it is.
fn take_seat(s: Seat) {
    if cores_count(s.cores) > 0 {
        let e = place_self_c(s.cores.bits);
        if e < 0 && place_once_c(PLACE_ONCE_PIN) != 0 { place_warn(str("can't pin a thread to ", s.cores, ": error ", -e)); }
    }
    if s.low {
        let e = place_low_c();
        if e < 0 && place_once_c(PLACE_ONCE_LOW) != 0 { place_warn(str("can't lower a thread's priority: error ", -e)); }
    }
}

// Gives listener fd the connections whose interrupts s's core takes, where s
// asks for it. A failure prints one warning per process.
fn place_listener(s: Seat, fd: i32) {
    guard s.incoming >= 0;
    let e = place_incoming_c(fd, s.incoming as i32);
    if e < 0 && place_once_c(PLACE_ONCE_INCOMING) != 0 { place_warn(str("can't set SO_INCOMING_CPU: error ", -e)); }
}

// The cores the calling thread may run on, for a test to read a seat back.
fn place_current() -> Cores {
    var c = Cores { .. };
    place_current_c(c.bits);
    return c;
}

// The placement file the command line names, with --place FILE or
// --place=FILE, or else GOOSE_PLACE, checked against this machine; an empty
// placement, which floats every thread, when neither names one. A file that
// can't be read or doesn't parse ends the program with exit code 2.
fn place_load() -> Place {
    var path: u8[>..] = [];
    let a = args();
    for w, i in a {
        if w == "--place" && i + 1 < a.len { path.append(a[i + 1]); break; }
        if starts_with(w, "--place=") { path.append(w[8..]); break; }
    }
    if path.len == 0 { env(PLACE_ENV, path); }
    guard path.len > 0 else { return Place { .. }; }
    var text: u8[>..] = [];
    guard read_file(path, text) else {
        place_warn(str("can't read ", path));
        exit(2);
    }
    var p, err = place_parse(text, path);
    guard err.len == 0 else {
        place_warn(err);
        exit(2);
    }
    var cpus = Cores { .. };
    let pins = place_cpus_c(cpus.bits);
    place_check(p, cpus, pins > 0);
    return p;
}
