# Goose findings

Gaps, bugs, and surprises in the pinned Goose compiler and stdlib, found while building
this port. Each entry has a minimal program that shows it, the Goose commit it was found
on, the workaround used here, and whether it has been reported upstream.

Format:

```markdown
## Short title

Found on `<goose commit>`, task NNN. Status: open | reported | fixed in `<commit>`

What happens and what was expected.

    minimal program

Workaround: ...
```

## A missing stdlib is reported as a missing file next to the program

Found on `3536810`, task 001. Status: open (unchanged at `fe6c543`)

A compiler binary moved out of its checkout, run without `--stdlib` or `GOOSE_STDLIB`,
can't find the stdlib. It then reports the import as missing beside the root file, the
first place it looked, and says nothing about the stdlib directories it tried
(`StdlibDirs` in `src/main.cpp`: `--stdlib`, `GOOSE_STDLIB`, up to four levels above the
binary, then `./stdlib/`). Expected: an error that says no stdlib was found and where the
compiler looked.

    // /tmp/repro/main.goose, compiled by a copy of the compiler at /tmp/goose
    import std;

    fn main() { print(max(1, 2)); }

    $ cd /tmp && ./goose repro/main.goose
    cannot open file: /tmp/repro/std.goose

Workaround: build the compiler inside its checkout, or set `GOOSE_STDLIB` for a copied
binary (`docs/development.md`).

## An --include path is rewritten wrongly when -o names no directory

Found on `3536810`, task 002. Status: open (unchanged at `fe6c543`)

`goose -o out.c --include /abs/net.h` writes `#include "abs/net.h"`, without the leading
slash, and the C compiler can't find the header; `-o ./out.c` does the same. The compiler
rewrites each `--include` path relative to the output file's directory (`RelativeTo` in
`src/main.cpp`), and for a bare file name that directory is the empty string, which
`PathParts` reads as the root. Expected: `#include "/abs/net.h"`, or a path relative to
the working directory.

    // main.goose
    extern fn shim_one() -> i32;
    fn main() { print(shim_one()); }

    // net.h
    static int32_t shim_one(void) { return 1; }

    $ goose -o out.c --standalone --include "$PWD/net.h" main.goose
    $ grep 'net\.h' out.c
    #include "home/me/repro/net.h"

Workaround: give `-o` a path with a directory. Since task 010 the server's shim is C
files that `goose build` compiles on their own, with no `--include`.

## An --include header can't set feature-test macros

Found on `3536810`, task 002. Status: open (unchanged at `fe6c543`)

The generated C includes `<stdio.h>`, `<unistd.h>`, and the runtime's other system
headers before it includes an `--include` header, so a `#define _GNU_SOURCE` in the
header comes too late. glibc then hides Linux-only declarations such as `accept4`, and
gcc 15 rejects the call as an implicit declaration. Expected: a way for a header to run
before the runtime's includes, or a note in spec §7.10 that `-D` is the way.

    // main.goose
    extern fn shim_accept(fd: i32) -> i32;
    fn main() { print(shim_accept(-1)); }

    // net.h
    #define _GNU_SOURCE
    #include <sys/socket.h>
    static int32_t shim_accept(int32_t fd) { return accept4(fd, 0, 0, 0); }

    $ goose -o build/out.c --standalone --include "$PWD/net.h" main.goose
    $ cc build/out.c -o out -lm -pthread
    net.h: error: implicit declaration of function 'accept4'

Workaround: `goose -D_GNU_SOURCE`, which the compiler writes at the top of the generated C
for both backends. Since task 010 the server's shim is C files that `goose build`
compiles on their own, and `shim/net.c` defines `_GNU_SOURCE` itself.

## A long-distance return can't carry a struct holding a slice of a parameter

Found on `3536810`, task 003. Status: open (unchanged at `fe6c543`)

`return E from f` accepts a slice of `f`'s own parameter as `E`, but not a struct
holding that slice: "a long-distance return may only carry references to globals or
static data". The slice outlives the call of `f` either way, and spec §7.9 states no
such limit. Expected: both forms accepted, or the limit in §7.9.

    struct Word { w: u8[:] }

    fn first_word(s: u8[:]) -> Word, bool {
        fn scan() -> i64 {
            var i = 0;
            while i < s.len && s[i] != ' ' { i++; }
            guard i < s.len else { return Word { w: s[..0] }, false from first_word; }
            return i;
        }
        return Word { w: s[..scan()] }, true;
    }

    fn main() {
        var text: u8[>..] = [];
        text.append("hello world");
        let w, ok = first_word(text);
        print(w.w, " ", ok);
    }

    $ goose rf.goose
    rf.goose:7: error: a long-distance return may only carry references to globals or static data

Returning `Word { w: s[..0] }` from `first_word` itself, or `s[..0], false from
first_word` without the struct, compiles.

Workaround: the failure carries `Word { .. }`, whose empty slice points at nothing.
`http::parse` refuses a request with `Request { .. }` and a status, and it returns
directly instead of through nested helpers.

## One unproven change to an index costs every bounds check on it

Found on `3536810`, task 004. Status: open for the `pos + 8` guard (unchanged at
`fe6c543`). The inliner's case no longer loses checks at `bab8b6f`, where the program
below has 3/3 elided at `-O2`.

The bounds-check analysis proves `0 <= pos <= buf.len` for a whole function at once. A
single write to `pos` that it can't prove stays in range, anywhere in the function,
drops the proof, and with it every check indexed by `pos`, including those in loops that
run before the write. Two ordinary spellings give it such a write:

- A call in a loop condition, once inlined. At `-O1` and up, the optimizer runs before
  the analysis and binds the call's argument to a fresh local (`let x = buf[pos]`).
  `HasKillEffects` (`src/bce.h`) counts that binding as a mutation, so the condition
  contributes no facts, and the loop's `pos++` is then unguarded.
- A guard of the form `pos + 8 <= buf.len`. `CmpAdmissible` (`src/bce.h`) rejects
  "variable + constant" as an operand, because the sum could have wrapped, and nothing
  rewrites it to the equivalent `pos <= buf.len - 8`, which it accepts.

Expected: the checks the function proved without these writes, at least those before
them.

    fn pred(x: u8) -> bool { x == 'z' }

    fn scan(buf: const u8[:]) -> i64 {
        var pos = 0;
        while pos < buf.len && buf[pos] == 'a' { pos++; }
        while pos < buf.len && !pred(buf[pos]) { pos++; }
        while pos < buf.len && buf[pos] == 'b' { pos++; }
        return pos;
    }

    fn main() { print(scan("aa  bbc")); }

    $ goose -O0 --check z1.goose
    bce: elided 3/3 index and 0/0 slice checks
    $ goose -O2 --check z1.goose
    bce: elided 0/3 index and 0/0 slice checks

The generated C then checks every byte of all three loops:

    uint8_t t11 = t10[GS_IDX((int64_t)(t9), buf_g.len, gs_file0, 5)];
    uint8_t x_g = t18[GS_IDX((int64_t)(t17), buf_g.len, gs_file0, 6)];
    uint8_t t27 = t26[GS_IDX((int64_t)(t25), buf_g.len, gs_file0, 7)];

Writing the middle loop as `while pos < buf.len { if pred(buf[pos]) { break; } pos++; }`
keeps all three elided at every level. Between the first and last loop, `pos += 8;`
alone, `if pos + 8 <= buf.len { pos += 8; }`, and `pos = next(pos);` each lose all
checks; `while pos < buf.len - 7 { pos += 8; }` keeps them. An `assert(pos < buf.len)`
or `assert(pos <= buf.len)` right before an increment also restores them, but
`assert(pos >= 0)` doesn't: the missing fact is the upper bound that proves the
increment can't wrap.

In `http::parse`, swapping a large `is_tchar`, which wasn't inlined, for a two-line one
that was dropped the elided checks from 23 of 30 to 8 of 30.

A fix that would cover the inliner's case: `HasKillEffects` ignores writes to variables
declared inside the expression it scans, since no operand read before them can refer to
them. Admitting `v + c` in `CmpAdmissible` where the addition is provably exact would
cover the second.

Adding a variable to the index is a third such write (found on `bab8b6f`, task 008).
`pos += k` with a `k` that isn't a literal loses every check on `pos`, even under a
guard that proves the sum in range: `Assign::BceMark` (`src/bce.h`) puts the variable
in `wbad` for any compound assignment but a literal or a unit step. `pos = pos + k`
under `k <= buf.len - pos` keeps them, but only where `pos <= buf.len` was established
right before, as a kept check of `buf[pos..]` does, and only at `-O0` when the search is
std's `position`, which `-O2` inlines between the two:

    import std;

    fn scan(buf: const u8[:]) -> i64 {
        var pos = 0;
        while pos < buf.len && buf[pos] == 'a' { pos++; }
        let k = position(buf[pos..], 'b');
        if k > 0 && k <= buf.len - pos { pos = pos + k; }
        while pos < buf.len && buf[pos] == 'b' { pos++; }
        return pos;
    }

    fn main() { print(scan("aaxxbbc")); }

    $ goose -O0 --check m.goose
    bce: elided 2/2 index and 0/1 slice checks
    $ goose -O2 --check m.goose
    bce: elided 0/2 index and 0/1 slice checks

With `pos += k` in place of `pos = pos + k`, both levels elide 0/2. Expected: `pos += k`
treated as `pos = pos + k`, and the guard's facts kept across an inlined call that
writes neither `pos` nor `buf`.

Workaround: `http::parse` calls `is_tchar` in its loops' bodies, not their conditions,
and advances past `find_any`'s result, an external call, with `pos = pos + k` under
`k <= buf.len - pos`. Its comments point here.

## The stdlib has no fast byte search, and no word loads

Found on `3536810`, task 004. Status: open for word loads (unchanged at `fe6c543`).
`std` has had a byte search since `72b1bc5`: `find_any`, which scans 16 bytes at a time
on x86-64.

`position(xs, v)` and `find(xs, sub)` in `stdlib/std.goose` compare one element per
iteration, so a search for `'\r'` in a header costs about as much as a hand-written byte
loop, where C's `memchr` compares 16 or 32 bytes at a time. Goose also has no way to
read a `u64` out of a `u8` buffer. The workaround that works is to assemble the word
from eight bytes with shifts, which gcc 15 at `-O2` compiles to one 64-bit load once the
bounds checks are gone:

    let b = buf[pos..pos + 8];
    let w = b[0] | (b[1] as u64 << 8) | (b[2] as u64 << 16) | (b[3] as u64 << 24) |
            (b[4] as u64 << 32) | (b[5] as u64 << 40) | (b[6] as u64 << 48) |
            (b[7] as u64 << 56);

Expected: a byte search in the stdlib that the backend can vectorize or hand to
`memchr`, or a word read like `binary`'s `read_u32le` for `u64` that's documented to
compile to one load.

Workaround, until task 008: `http::parse` scanned header values eight bytes at a time
with the word above and a SWAR test, and finished a byte at a time. It was the profile's
largest single change: about 700 fewer instructions per request. Since task 008 it
calls `find_any`, which saved another 175 user instructions per request; nothing here
needs a word load now.

## A simd fn parser ran slower than its baseline

Found on `bab8b6f`, task 008. Status: open (unchanged at `fe6c543`)

`simd` (spec §7.12) on `http::parse` made it slower under clang 21 on a Ryzen 7 5800X3D,
which runs the AVX2 version. The spec allows this: a `simd fn` suits a function that
runs a loop, and the header loops are mostly shorter than one vector. It is recorded
because the cost was there even where `parse` held a vectorized loop, and nothing warns
of it. Instructions per parse in user code, from `bench/parse.sh`'s programs:

| `parse`'s value scan | Build | wrk's request (170 B) | Chrome's request (1.9 KB) |
|---|---|---:|---:|
| A 32-byte block reduced to its first end byte | clang `-DGS_SIMD=0` | 1,321 | 8,032 |
| The same | clang, AVX2 version | 1,532 | 7,035 |
| `find_any` | clang `-DGS_SIMD=0` | 1,383 | 7,590 |
| The same | clang, AVX2 version | 1,633 | 7,615 |

The AVX2 version took fewer instructions only for the block on the long request. In
time, best of 5 runs of 10 M parses on one CPU, `find_any`'s took 70.6 ns for wrk's
request against 56.8 ns without versions, and 317 ns against 315 ns for Chrome's. Under
gcc, which ignores `simd`, the same source was faster than either clang build.

Timed again at `752c3ce` with clang 21.1.8, on the parser after task 009's changes:
`simd fn parse` took 63.5 ns and 1,311 instructions per parse of wrk's request, against
55.8 ns and 1,200 under `-DGS_SIMD=0`, and 279.7 ns against 285.3 ns for Chrome's. gcc
took 50.6 ns and 222.3 ns without `simd`. At `f084e52`: 63.5 ns against 55.3 ns, 280.2 ns
against 282.6 ns, and gcc 50.4 ns and 221.0 ns. `efe3155` generates the same C for `parse` as
`f084e52`.

Workaround: `http::parse` isn't a `simd fn`.

## Goose can't express a movemask and count trailing zeros

Found on `bab8b6f`, task 008. Status: open (unchanged at `fe6c543`)

The fast HTTP parsers find the first byte of a set in a 32-byte block with a compare,
`movemask`, and a trailing-zero count (httparse's AVX2 path), about six instructions.
The Goose spelling builds the mask a bit per byte, and neither gcc 15 nor clang 21 turns
it into `pmovmskb`; `std`'s `ctz` is a loop over the bits. In `http::parse`, this cost
2,462 instructions per parse of wrk's request under gcc, against 1,356 for a block
reduced with a minimum and 1,270 for `find_any`:

    var ends: u32 = 0;
    for c, i in buf[pos..pos + 32] {
        let bit: u32 = 1;
        if (c < ' ' && c != '\t') || c == 0x7f { ends |= bit << i; }
    }
    if ends != 0 { let k = ctz(ends as u64); ... }

Expected: a `ctz` the C compilers see as one (`__builtin_ctzll`), and a mask-building loop
the backend writes in a shape the C compilers recognize, or a stdlib function for it.

Workaround: `std`'s `find_any`, whose runtime does the movemask and count in C.

## A limited array's `..` default writes its whole capacity

Found on `e7792d7`, task 009. Status: open (unchanged at `fe6c543`)

Spec §4.2 says constructing a limited array writes only its metadata and any provided
elements, and leaves the rest of its capacity uninitialized; C.2 and C.4 add that its
pages aren't touched. The C backend zeroes the whole array instead. A struct literal
whose `..` defaults a `u8[..8192]` field compiles to a `memset` of all 8,194 bytes:

    struct Slot { fd: i32, n: i64, buf: u8[..8192] }

    fn main() {
        var pool: Slot[>..] = [];
        for i in 3 { pool.push(Slot { fd: i as i32, .. }); }
        print(pool.len + pool[2].buf.len);
    }

The generated C has `memset(&(*t5), 0, sizeof((*t5)))` on an `l8192_u8` temporary.
Every element of an array of such structs is then resident in full, whatever it holds.
Expected: the length written, the capacity left alone.

Workaround: the server's connection slots hold no buffers (`docs/architecture/README.md`).

## A struct literal is built in whole temporaries and copied

Found on `e7792d7`, task 009. Status: open (unchanged at `fe6c543`)

Spec §4.2 says a struct literal is constructed "directly into each field; no temporaries
or copies are introduced". The C backend builds each field in a temporary, copies it
into a temporary of the struct, copies that into a second struct temporary, and copies
that into the destination. For the `Slot` above, gcc 15 at `-O2` keeps 2 `memset`s and 3
`memcpy`s of 8 KB each for `pool.push(Slot { fd: i as i32, .. })`, and 4 `memcpy`s for
`alloc_index` on a `reusable` pool. Copying fixed-size values is allowed (§4.1), so this
is a cost, not a wrong result: the server's 16 KB slots wrote about 65 KB per accepted
connection. Expected: each field written once, in the destination.

Workaround: as above. Measured with HttpArena's `limited-conn` (a new connection every
10 requests), the copies cost nothing visible: 307K to 314K requests per second with and
without them (task 009).

## Two threads that exit at once crash on Windows

Found on `efe3155`, task 006. Status: open (unchanged at `fe6c543`)

When two threads each print and then call `exit(1)` with their output redirected, the
program crashes with `0xC0000005` (access violation) instead of exiting with 1. It
crashes every time from Git Bash, or from .NET with pipes, and 3 times in 5 with the
output going to a file. It never crashes with one such thread, from a PowerShell console,
or on Linux. `gs_exit` calls C's `exit()` while another thread is still inside stdio.

    import os;
    thread_fn w(i: i32) { write_stderr("bye\n"); exit(1); }
    fn main() { var ids: i64[>..] = []; for i in 2 { ids.push(thread_spawn(w, i as i32)); } for id in ids { thread_wait(id); } }

The server hits it when every worker fails `listen` at once, for example on a port in
use. Workaround: none yet.

## `goose build` on Linux never sees a sidecar's C change

Found on `efe3155`, tasks 011 and 012. Status: open (unchanged at `fe6c543`)

`goose build` keeps the compiled C of a sidecar with a stamp of the newest mtime of its
C sources and the sidecar: a program's under `~/.goose/build/prog/<name>-<hash>/native/`,
and a local package's under `~/.goose/build/pkg/local/`. On Linux the mtime in the
stamp is always 0, so editing a C source never makes the build stale, and the program
links the old objects: silently when the edit changes only a body, and with an
undefined reference when it adds a function. Here the old `net_listen(port, backlog,
flags)` was called with a new fourth argument, so every argument landed one place over
and two of four workers failed with `EADDRINUSE`. Expected: a changed C source is
compiled again.

    // stale.goose, with stale.build: c_sources = ["answer.c"];
    // and answer.c: int32_t answer(void) { return 1; }
    extern fn answer() -> i32;

    fn main() { print(answer()); }

    $ goose build stale.goose && ./stale
    1
    $ sed -i 's/return 1/return 2/' answer.c
    $ goose build stale.goose && ./stale
    1

`NewestMtime` in `src/native.h` keeps `std::max` of 0 and each file's
`last_write_time(...).time_since_epoch().count()`. libstdc++'s file clock counts from
2174, so today's times are negative and the maximum stays 0. macOS's libc++ counts from
1970 and MSVC's from 1601, so macOS and Windows rebuild as they should. The cache
directories are named by a hash of the source's path, so a checkout at a new path, or
a new `GOOSE_HOME`, builds the objects once.

Workaround: `scripts/build.sh` deletes the stamp of the local package whose link list
has the shim's objects before each build, which compiles the shim again, about a
second.

## `thread_spawn` doesn't take a function value bound to a `thread_fn`

Found on `efe3155`, task 011. Status: open (unchanged at `fe6c543`)

A generic function can't spawn the `thread_fn` it was passed. Spec §7.6 lets a function
value be "a function name (including a bound generic function parameter)", and §11.2's
`thread_spawn(worker, args…)` takes a `thread_fn`'s name, but the two don't combine:

    thread_fn worker(n: i32) { print("worker ", n); }

    fn spawn<W>(n: i32) -> i64 { thread_spawn(W, n) }

    fn main() { thread_wait(spawn(1, worker)); }

    min.goose:3: error: thread_spawn's first argument names a thread_fn

Expected: `W` is bound to `worker`, a `thread_fn`, so the spawn is the same as
`thread_spawn(worker, n)`. It's what task 011 planned as `http::spawn_workers(worker,
cfg)`.

Workaround: the package gives the worker count, `http::worker_count(cfg)`, and the
program writes the spawn loop itself.

## An `inline fn` that takes a function value stays a call

Found on `fee060c`, task 013. Status: open

Goose inlines an `inline fn` itself, early returns and all, unless it takes a function
value: then it emits a C function and leaves the inlining to the C compiler, which may
not do it. Spec §7.13 says `inline` asks for inlining "however big it is and however
many calls there are", and names only functions returning several values as ones Goose
can't inline itself. Here `only` stays a C function, `only_g`, called from both of
`loop2`'s calls of the block:

    import std;

    struct Ev { kind: u8, x: i64 }

    inline fn only<H>(ev: Ev, out: i64[>..]&) {
        if ev.kind == 0 { H(ev.x, out); }
    }

    fn loop2<H>(n: i64, out: i64[>..]&) {
        for i in n {
            H(Ev { kind: 0, x: i }, out);
            if i % 7 == 0 { H(Ev { kind: 1, x: i }, out); }
        }
    }

    fn serve<H>(n: i64, out: i64[>..]&) {
        loop2(n, out) { ev, o => only(ev, o, H); };
    }

    fn main() {
        var out: i64[>..] = [];
        serve(100, out) { x, o => o.push(x * 2); };
        print(out.len);
    }

`goose -o fv.c fv.goose` writes `static void only_g(Ev_g p0, ...)` and two calls of it.
The same `only` without `H`, returning whether to call it, is inlined, early return
included. In the benchmark server, gcc kept such a function out of line, with the
handler inlined into it: 60-120 more instructions per request.

Workaround: `http::whole_only` takes no function value and returns whether the loop
should call the handler, and the loops' wrappers call it themselves.

## A data stack takes a 2 MB huge page for its first byte

Found on `5c83a5a`, task 016. Status: open

Where Linux runs transparent huge pages set to `always`, the first write to a data stack
can fault in a whole 2 MB page. The runtime reserves each stack as a 2 GB anonymous
mapping (`gs_os_reserve`), and the kernel backs a write into an aligned 2 MB range of it
with a huge page whenever a free one is available. A worker that writes a few bytes to
each of its stacks then commits 2 MB a stack, not one 4 KB page. Expected: data stacks
commit what they hold, for example by `madvise(MADV_NOHUGEPAGE)` on each region, or on
its first 2 MB.

    import std;
    import os;

    // One value on each of two data stacks, then the process's huge pages.
    thread_fn worker(n: i64) {
        var a: u8[>..] = [];
        a.push(1);
        var b: i64[>..] = [];
        b.push(n);
        var smaps: u8[>..] = [];
        if read_file("/proc/self/smaps_rollup", smaps) { print(smaps); }
    }

    fn main() {
        thread_wait(thread_spawn(worker, 1));
    }

    $ cat /sys/kernel/mm/transparent_hugepage/enabled
    [always] madvise never
    $ goose build -o thp thp.goose && ./thp | grep -E '^(Rss|AnonHugePages)'
    Rss:                5544 kB
    AnonHugePages:      4096 kB

Run with `prctl(PR_SET_THP_DISABLE)` set, the same program has 1,460 KB RSS and no huge
pages. Measured in Docker Desktop's Linux VM on an M1 Pro (kernel 7.0.14-linuxkit,
`defrag` set to `madvise`), 2026-10-12. In the benchmark server, one worker held
6.4-13.1 MB RSS with huge pages and 1.8-5.8 MB without (task 016). WSL2's 2.2-5.4 MB
suggest its kernel doesn't back these mappings with huge pages.

Workaround: none in the package. Run the server where transparent huge pages are
`madvise` or `never`, or start it under `PR_SET_THP_DISABLE`.

## A closure that keeps a slice through two nested blocks doesn't settle

Found on `5c83a5a`, task 015. Status: open

A function that stores a slice its block was given into a variable of its own, where
the block is called from a block nested two deep, fails to check: "this loop's
checking does not settle (internal limit of 16 passes)", pointing at the innermost
loop. It checks when the slices point at a literal instead of a growable array, and
when only one block sits between the loop and the store. Expected: it checks, as the
one-block version does.

    import std;

    fn each_pair<F>(text: const u8[:]) {
        var pos = 0;
        while pos < text.len {
            F(text[pos..pos + 1]);
            pos++;
        }
    }

    fn each_part<F>(text: const u8[:]) {
        each_pair(text) { p =>
            each_split(p, ';') { F(it); };
        };
    }

    fn final_part(text: const u8[:]) -> const u8[:] {
        var v = text[..0];
        each_part(text) { p => v = p; };
        return v;
    }

    fn main() {
        var buf: u8[>..] = [];
        buf.append("a;b");
        print(final_part(buf));
    }

Workaround: `each_cookie` (`cookie.goose`) reads the `Cookie` fields with its own loops
over `field_at` instead of `each_field` and `each_split`, so `cookie_of`'s block is the
only one.

## A shrink in a `for` loop over a literal is refused for the literal's sake

Found on `5c83a5a`, task 015. Status: open

A call that shrinks a growable array declared inside a `for` loop's body is refused
when the loop walks an array literal of strings: "the for loop iterates [...], whose
elements may refer into buf". The literal's elements are static strings, and the array
is created after the loop starts, so none can refer into it. Expected: it checks, as
it does when the loop walks a range.

    import std;

    fn refill(buf: u8[>..]&, text: const u8[:]) {
        buf.clear();
        buf.append(text);
    }

    fn main() {
        for s in ["a", "b"] {
            var buf: u8[>..] = [];
            refill(buf, s);
            print(buf);
        }
    }

Workaround: the tests call a function of their own for each element, which declares
the array there (`test/test_api.goose`, `basic_ok`).

## A string literal in a struct makes it refer into any array a callee shrinks

Found on `5c83a5a`, task 015. Status: open

A callee that shrinks an array it was given by reference, and then reads another
argument, a struct of slices, is refused when one of the struct's slices points at a
string literal: "cannot clear h while r is still used: a reference into it was stored
there", naming the line that built the struct. The struct's slices point at a local
buffer and at static data, neither of which is the shrunk array. With only the buffer's
slice in the struct, it checks. Expected: it checks either way. A `Request` from
`parse` has such a slice, so any helper that takes one and shrinks a buffer of the
caller's meets it.

    import std;

    struct Req { a: const u8[:], b: const u8[:] }
    struct Holder { held: u8[>..] = [] }

    fn start(r: Req, h: Holder&) -> bool {
        h.held.clear();
        return r.a.len > 0;
    }

    fn main() {
        var buf: u8[>..] = [];
        buf.append("abc");
        var h = Holder { .. };
        let r = Req { a: buf, b: "/" };
        print(start(r, h));
    }

Workaround: the helper shrinks only an array of its own and appends that to the
caller's (`basic_auth`, `auth.goose`), or is done with the request before it shrinks
anything. A limited array, as `Multipart.held` is, isn't refused.

## The stdlib's JSON parser and reader take only a whole text

Found on `5c83a5a`, task 015. Status: open

`json::parse` and `json::reader` read one slice that holds the whole JSON text. A
request body longer than the read buffer reaches the handler in `BODY` pieces, and
neither can take one piece and resume with the next: a piece that ends inside a value
fails as malformed. Expected, for a server: a parser that takes a body in pieces, or
one that says it needs more, so that a large JSON body needn't sit whole in memory.

    import std;
    import json;

    fn main() {
        // A body that came in two BODY pieces: each fails on its own, and
        // neither the parser nor the reader can be resumed with the next.
        let first = "{\"name\": \"goo";
        let second = "se\", \"n\": 1}";
        var doc: json::Node[>..] = [];
        var decoded: u8[>..] = [];
        let root, err = json::parse(first, doc, decoded);
        print(err);
        var r = json::reader(first);
        var scratch: u8[>..] = [];
        json::each_member(r) { key => print(key, " = ", json::read_string(r, scratch)); };
        print(json::finish(r), " ", json::message(r));
    }

It prints `json: bad string at byte 9` twice.

Workaround: a handler joins the pieces, up to a limit of its own, and
parses at `END`; a body that fits the read buffer comes whole at `REQUEST`.

## A reference variable can't be rebound to one with another root

Found on `5c83a5a`, task 015. Status: open

A `var` reference bound to a parameter's target can't be rebound with `.=` to a local's,
and the error says so. The loops wanted one variable for "the event for the next call":
the caller's WAKE first, then a local "no event". Expected: a variable whose root is the
shorter-lived of the two, as two separate bindings would be.

    struct E { k: i32 }

    fn f(w: const E&) {
        let none = E { k: 0 };
        var e .= w;
        print(e.k);
        e .= none;      // error: re-binding e with a reference rooted at a
        print(e.k);     // different scope depth is not supported (§9.2)
    }

    fn main() {
        let a = E { k: 1 };
        f(a);
    }

Workaround: copy the value into a local and change its field (`var ev = wake; ...
ev.kind = NO_EVENT;`, in `uring.goose`'s `pump` and `epoll.goose`'s `advance`).

## A struct literal can't be passed to a `const T&` parameter

Found on `5c83a5a`, task 015. Status: open

A call that passes a struct literal, or any temporary, to a `const T&` parameter finds
no overload, where C++ would bind the reference to the temporary. Expected: the
temporary lives until the call returns, as the in-place construction rule (spec §4.3)
already places it.

    struct E { k: i32 }

    fn g(e: const E&) -> i32 { e.k }

    fn main() { print(g(E { k: 1 })); }   // error: cannot pass E as const E&

Workaround: bind the literal to a local first (`let ev = Event { ... }; resume(c, ev);`
in the loops' `delivered` and `timed_out`).

## A package's JIT library links the externs of every file under its root

Found on `5c83a5a`, task 020. Status: open

`PackageExternNames` (`src/native.h`) collects the extern fns of every `.goose` file
under a library package's root, examples included, and the package's JIT library must
link each one. `examples/c/app.goose` declares `extern fn gh_handle`, which its own
`handler.c` defines, not the package. So every `goose file.goose` that imports the
package fails, on Linux at load (`undefined symbol: gh_handle`) and on Windows at link
(`lld-link: error: undefined symbol: gh_handle`). A cached library built before the
example was added hides it until the cache under `~/.goose/build/pkg/local/` is
cleared. Expected: a program under the root that the package doesn't import, with its
own `.build`, isn't part of the package.

    // pkg/lib.build: c_sources = ["lib.c"];
    // pkg/lib.goose:  extern fn lib_f() -> i32;
    // pkg/ex/app.goose, with pkg/ex/app.build naming its own app.c:
    extern fn app_g() -> i32;
    // A program that imports pkg's lib and runs with `goose main.goose` fails:
    // undefined symbol: app_g

Workaround: `examples/c` is off `main`, on the `examples-c` branch, until a package
can leave a program under its root out (2026-10-12). Any `.goose` file under the root
with an `extern fn` that the package's own C doesn't define breaks in-process runs of
every program that imports the package.

## A block given a local struct writes to a copy of it

Found on `5c83a5a`, task 021. Status: open

A function that calls its block with a local struct variable, `F(c)`, gives the block a
copy, so whatever the block changes through it is lost, without an error. Called with a
reference parameter instead, the same block writes through to the caller's value. A
block's parameters can't be typed, so it can't ask for a reference either. The REST
server met this with `json::Reader`: a loader that read each file's records with
`json::each_element(r) { F(r); }` saw the cursor never move, and the parse failed at
byte 1. Expected: the block's parameter binds the argument as a call to an untyped
function parameter does, or the compiler refuses the write to a copy.

    struct Cursor { pos: i64 }

    fn advance(c: Cursor&) { c.pos++; }

    fn each_twice<F>() {
        var c = Cursor { pos: 0 };
        F(c);
        F(c);
        print(c.pos);       // 0, and the block printed 1 twice
    }

    fn main() { each_twice() { it => advance(it); print(it.pos); }; }

Workaround: pass the block a struct that holds a reference, `struct Cursor { r:
json::Reader& }`, and bind it in the block with `let r .= c.r;`
(`bench/rest/goose/rest.goose`, `load_each`).

## A worker can't read a string constant

Found on `5c83a5a`, task 021. Status: open

A `let` global holding a string literal is a slice, so a thread program refuses it as a
global that isn't flat (spec §11.2), though the literal is read-only static data that
every thread shares. Expected: a `const u8[:]` into static data counts as flat.

    let NAME = "goose";

    thread_fn worker() { print(NAME); }   // error: thread programs may access only
                                          // flat globals (§11.2): NAME holds references
    fn main() { thread_wait(thread_spawn(worker)); }

Workaround: a function that returns the literal, `fn app_url() -> const u8[:] {
"https://..." }` (`bench/rest/goose/rest.goose`).

## `format_uint` and `format_int` don't take a limited array

Found on `5c83a5a`, task 021. Status: open

`format` appends to a `u8[..k]` as to a builder, but `format_uint` and `format_int`
take only a `u8[>..]&`, so a padded or hexadecimal number can't go straight into a
struct's inline string. Expected: the same destinations as `format`.

    var s: u8[..16] = "";
    format(s, 255);                     // fine
    format_uint(s, 255, 16, 2, '0');    // error: cannot pass u8[..16] as u8[>..]&

Workaround: format into a `u8[>..]` and append that (`bench/rest/gen.goose`, `uuid`).

## A call's two results can't be assigned to existing variables

Found on `5c83a5a`, task 021. Status: open

Several results are received only by `let a, b = f();` (spec §7.1). Assigning them to
variables declared earlier, as a loop or block that updates outer state needs, is an
error whose message speaks of a block's value instead. Expected: `a, b = f();` assigns
both, or an error that says a call's results need a `let`.

    fn two() -> i64, bool { return 1, true; }

    fn main() {
        var a = 0;
        var ok = false;
        a, ok = two();      // error: several values exist only in `return a, b;` and in
        print(a, ok);       // a call's results, so a block or branch cannot end in `a, b`
    }

Workaround: `let d, fits = description_of(r, scratch);` and assign each
(`bench/rest/goose/rest.goose`, `patch_entry`).

## The stdlib's `find` compares the whole subsequence at every offset

Found on `6448f3f`, task 021. Status: open

`find(xs, sub)` in `stdlib/std.goose` compares `xs[i..i + sub.len]` with `sub` at each
offset `i`, so every byte of `xs` costs a call to the runtime's memory compare, even
where the byte can't start `sub`. In a multipart body, whose delimiter starts with a CR
that file data rarely holds, perf put 19% of an upload's time in that compare
(`gs_memeq_long` and `gs_memeq`), against 0.2% for Rust's `memchr::memmem` in hyper's
multer. Expected: a search that skips to where `sub`'s first byte is, as `memmem` does.

    import std;

    fn main() {
        var xs: u8[>..] = [];
        for i in 10000000 { xs.push('a'); }
        xs.append("\r\n--end");
        // One memory compare per byte of xs: 10 million calls.
        print(find(xs, "\r\n--end"));
    }

Workaround: `http::find_bytes` (`form.goose`) compares only where `sub`'s first byte is.

## A `null` branch doesn't take an optional type from its sibling branch

Found on `a6249a4`, task 027. Status: open

An `if` whose one branch is an optional reference and whose other is `null` is
rejected where it has no typed destination, such as a call's argument. Expected: the
optional's type, since a literal branch adapts to the others' type (spec §6.4), and
`null` is the empty value of any optional type (§3.8). With a typed destination, as in
`let p: const E? = if c { o } else { null };`, it compiles.

    struct E { k: i32 }

    fn f(e: const E?) -> i32 { if e { e.k } else { -1 } }

    fn main() {
        let a = E { k: 1 };
        let o: const E? = a;
        let c = true;
        // error: branches have mismatched types: const E? vs void?
        print(f(if c { o } else { null }));
    }

Workaround: bind it to a typed local first (`let first: const Event? = if woke { wake }
else { null };`, as task 027's `Event` enum did in the loops, `a9783c8`, since reverted).
