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

Found on `3536810`, task 001. Status: open (unchanged at `efe3155`)

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

Found on `3536810`, task 002. Status: open (unchanged at `efe3155`)

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

Found on `3536810`, task 002. Status: open (unchanged at `efe3155`)

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

Found on `3536810`, task 003. Status: open (unchanged at `efe3155`)

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
`efe3155`). The inliner's case no longer loses checks at `bab8b6f`, where the program
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

Found on `3536810`, task 004. Status: open for word loads (unchanged at `efe3155`).
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

Found on `bab8b6f`, task 008. Status: open (unchanged at `efe3155`)

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

Found on `bab8b6f`, task 008. Status: open (unchanged at `efe3155`)

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

Found on `e7792d7`, task 009. Status: open (unchanged at `efe3155`)

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

Found on `e7792d7`, task 009. Status: open (unchanged at `efe3155`)

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

Found on `efe3155`, task 006. Status: open

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
