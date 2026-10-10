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

Found on `3536810`, task 002. Status: open

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

Found on `3536810`, task 002. Status: open

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
for both backends. `scripts/build.sh` and `scripts/run.sh` pass it, and `shim/net.h`
stops with an `#error` without it.
