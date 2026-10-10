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

Found on `3536810`, task 001. Status: open

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

Found on `3536810`, task 002. Status: open (unchanged upstream:
`origin/master` was still `3536810` on 2026-10-10)

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

Workaround: give `-o` a path with a directory, as `scripts/build.sh` does
(`-o "$root/build/server.c"`). The header is then included as `../shim/net.h`.

## An --include header can't set feature-test macros

Found on `3536810`, task 002. Status: open (unchanged upstream:
`origin/master` was still `3536810` on 2026-10-10)

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
for both backends. `scripts/build.sh` passes it, and `shim/net.h`
stops with an `#error` without it.

## A long-distance return can't carry a struct holding a slice of a parameter

Found on `3536810`, task 003. Status: open

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
    rf.goose:8: error: a long-distance return may only carry references to globals or static data

Returning `Word { w: s[..0] }` from `first_word` itself, or `s[..0], false from
first_word` without the struct, compiles.

Workaround: the failure carries `Word { .. }`, whose empty slice points at nothing.
`http::parse` refuses a request with `Request { .. }` and a status, and it returns
directly instead of through nested helpers.

## One unproven change to an index costs every bounds check on it

Found on `3536810`, task 004. Status: open

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

Workaround: `http::parse` calls `is_tchar` in its loops' bodies, not their conditions,
and spells the guard of its eight-byte loop `pos < buf.len - 7`, with the bytes read in
the loop rather than by a function given `pos`. Its comments point here.

## The stdlib has no fast byte search, and no word loads

Found on `3536810`, task 004. Status: open

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

Workaround: `http::parse` scans header values eight bytes at a time with the word above
and a SWAR test (`may_end_value`), and finishes a byte at a time. It is the profile's
largest single change: about 700 fewer instructions per request.
