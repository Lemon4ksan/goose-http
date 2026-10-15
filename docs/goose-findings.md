# Goose findings

Gaps, bugs, and surprises in the pinned Goose compiler and stdlib, found while building
this port. Each entry has a minimal program that shows it, the Goose commit it was found
on, the workaround used here, and whether it has been reported upstream.

An entry stays only while its fix would help this package significantly: make a target
run, stop a silent wrong result, save memory or speed a benchmark shows, or let real
code or tests go. A gap that's cheap to work around here, where the fix would be real
work in Goose, is worked around and not recorded (2026-10-14).

The entries come in two parts: [bugs](#bugs), where Goose does something wrong or other
than its spec says, then [feature requests](#feature-requests), for what it lacks. Each
part runs from the least work a fix is expected to take to the most, so the cheap fixes
come first. The order is an estimate from reading the compiler. Place a new entry where
its expected work puts it, and delete an entry once the pin has its fix: git keeps it.

Format:

```markdown
### Short title

Found on `<goose commit>`, task NNN. Status: open | reported

What happens and what was expected.

    minimal program

Workaround: ...
```

## Bugs

### `thread_spawn` writes its packet's lengths through misaligned `int64_t` pointers

Found on `46356c2`, task 030. Status: open (not reported)

`thread_spawn` packs the thread's arguments, then each global the thread uses, into a
packet on a data stack, each global behind its length as an `int64_t`. The generated C
writes that length through a plain `int64_t *` at whatever offset the arguments end on,
and the thread's start reads it back the same way:

    int64_t *t1 = (int64_t *)t3;            /* t3 is 1 byte past the stack's top */
    ...
    *t1 = t3 - (uint8_t *)(t1 + 1);
    ...
    int64_t sz = *(int64_t *)p; p += 8;     /* in gs_tmain_worker_g */

A misaligned access through an `int64_t *` is undefined in C. On 32-bit ARM, gcc 15.2
compiles the store to `strd`, which requires word alignment, and the program dies
with `SIGBUS` (`BUS_ADRALN`) on emulated armv7. x86-64 and aarch64 allow the
misaligned access, so the bug doesn't show there. Spec C.2 says loads and stores may be
unaligned, so the generated C must make them through `memcpy` or a packed type.
Expected: the program prints 8.

    fn seven() -> i64 { return 7; }
    let G = seven();

    thread_fn worker(b: u8) { print(G + b); }

    fn main() {
        let b: u8 = 1;
        let id = thread_spawn(worker, b);
        thread_wait(id);
    }

    $ goose build --cc /usr/bin/arm-linux-gnueabihf-gcc --standalone -o m1 m1.goose
    $ ./m1    # in an arm/v7 container
    goose runtime error: data stack overflow: a value on main's data stacks grew past
    the 2 GB reserved for it; --stack-reserve or -DGS_STACK_RESERVE raises the
    reservation, up to 256 TB

The message is a second defect: the runtime's fault handler (`gs_fault_handler` in
`src/runtime/runtime_impl.h`) reports any `SIGSEGV` or `SIGBUS` whose address falls in a
data stack's region as an overflow, including an alignment fault in the region's usable
part. Expected: a fault in the usable part, or any `SIGBUS` with `BUS_ADRALN`, left to
the default action, or reported as what it is.

Every goose-http program hits this at start: its workers use four `ByteSet` globals
built at run time (293 bytes each), which follow the 353-byte `http::Config` in the
packet. Found with qemu-arm 10.2.3 (Docker Desktop 29.8.2) running the armv7 build.
qemu delivers the fault. A 32-bit ARM Linux kernel fixes up a user `ldrd` or `strd` by
default instead, slowly, but not a misaligned VFP or NEON access, and an arm64 kernel
running armhf programs fixes them up only with `CONFIG_COMPAT_ALIGNMENT_FIXUPS`. Not
yet tried on a board.

Workaround: none clean. Sizing the arguments and every copied global to multiples of 8
would align the lengths only while the stack's top is aligned at the spawn, which
nothing here controls.

### A block given a local struct writes to a copy of it

Found on `5c83a5a`, task 021. Status: open (unchanged at `46356c2`)

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
(`bench/rest/goose/rest.goose`, `load_each`). Or pass the local's reference, `F(&c)`,
which the block then binds (goose-rest, 2026-10-13).

The loops met it too: `serve(cfg, fresh) { ev, st, out => ... }` gave the block a copy
of the per-request state, so what a handler kept there at REQUEST was gone at WAKE.
Found by goose-rest's task 009 (2026-10-13); the loops pass `&x.state`. The same copy
happens when the struct is a field reached through a reference, `F(x.state)` with `x` a
`Conn&`, and there the compiler warns of the `&` that prevents it: "redundant &:
x.state is passed by reference without it (§4.1)". Without the `&`, the block's writes
are lost as above (checked at `46356c2`).

### Slices and references in a struct take 64-bit sizes on a 32-bit target

Found on `46356c2`, task 030. Status: open (not reported)

`CodeGen::FixedSize` (`src/codegen_types.h`) sizes every slice at 16 bytes and every
reference at 8 (16 for one to a resizable), whatever the target. The C compiler lays out
the same structs with its own pointer size: a slice is 12 bytes on armhf, and a
reference 4. So on a 32-bit target, code that steps by the compiler's size and code that
indexes with C's disagree. Below, `push` advances the stack's top by 24 bytes per `W`
(`t24 += 24;`), and `ws[1]` reads `ws.data[1]`, 20 bytes in. Expected: 2, which x86-64
and aarch64 print. armv7 prints 8589934592.

    struct W { s: u8[:], n: i64 }

    fn second(ws: W[:]) -> i64 { return ws[1].n; }

    fn main() {
        var text: u8[>..] = [];
        text.append("ab");
        var ws: W[>..] = [];
        ws.push(W { s: text[0..1], n: 1 });
        ws.push(W { s: text[1..2], n: 2 });
        print(second(ws));
    }

The same program with `struct R { r: i64&, n: i64 }` advances by 16 per element and
prints garbage too. goose-http's `http::RingConn` is pushed with a stride of 183 bytes,
which `sizeof` contradicts on armhf. Expected: `FixedSize` taking the target's pointer
size, or the generated C asserting `sizeof(void *) == 8` so a 32-bit build fails to
compile instead of running wrong.

Workaround: none here. The package keeps slices in its structs throughout.

## Feature requests

### `json::format_string` scans a byte at a time

Found on `46356c2`, task 033. Status: open (not reported)

`json::plain`, which `format_string` and `format_key` call on every string, tests each
byte in a loop. In the REST server's tier C it takes about a third of the user cycles,
and the same instructions take up to 7% more of them when the binary's layout puts
the loop across a cache line, which any edit to the program can do. std's own
`find_any` runs a `ByteSet` over 16 bytes at a time:

    let ESCAPED = escaped_set();
    fn escaped_set() -> ByteSet {
        var m = [false; 256];
        for i in 256 { m[i] = i < 0x20 || i == '"' || i == '\\'; }
        return byte_set(m);
    }
    fn plain(s: u8[:]) -> bool { find_any(s, ESCAPED) < 0 }

In std it would be json's first computed global, so every thread that uses `json` would
carry its own copy of the 293-byte `ByteSet` (globals are copied per thread, next entry).
With that change, std's own `stdlib_json` test gives the same output, both compiled
and under the JIT.

Workaround: the package's `http::json_string` looks for a byte to escape with
`find_any`, and appends the runs between escapes whole. The REST server, the HttpArena
server, and the examples write their JSON strings with it. Checking with
`find_any` first served serialized B and C 11-23% faster
([measurement](results.md#2026-10-14-rest-strings-scanned-16-bytes-at-a-time)). Object
keys still go through `format_key`, and the REST dataset generator still calls
`format_string`.

### A worker holds its globals twice, and its spawner keeps a third copy

Found on `0bdbd18`, task 025. Status: open (unchanged at `46356c2`)

`thread_spawn` copies the globals a worker uses through three buffers, and only the
worker's own stacks are needed once it starts:

- The spawning thread builds an image of the arguments and of each global on one of
  its data stacks (`thread_spawn` in `src/codegen_builtins.h`).
- `gs_thread_start` copies that image into a `malloc`ed packet, which
  `gs_thread_main` frees only when the worker returns (`src/runtime/runtime_threads.h`).
- The worker's entry thunk copies each global out of the packet into a data stack of
  its own.

No data stack gives its pages back while its thread runs: there is no `madvise` or
decommit, so a scope's end or a `clear()` lowers the stack's top and nothing else. So
each worker holds its globals twice, the packet and its stacks, and the spawning thread
keeps the image's pages committed, beside its own globals, for its life. That matches
task 025's idle VmRSS table: a tier C worker costs 21 MB serialized and 71 MB templated,
about twice the 11 and 37 MB its globals take (estimated from the record types). The
1-worker intercept, 58 and 156 MB, is about main's globals, the image, the 12 MB file
it parsed, and that worker. Expected: the packet freed once the thunk has unpacked
it, or the globals unpacked straight from the spawner's image.

    import std;
    import os;

    var big: u8[>..];

    // VmRSS, in MB.
    fn rss() -> i64 {
        var text: u8[>..] = [];
        guard read_file("/proc/self/status", text) else { return -1; }
        var at = find(text, "VmRSS:");
        var n: i64 = 0;
        for c in text[at + 6..] {
            if c >= '0' && c <= '9' { n = n * 10 + (c - '0'); }
            else if n > 0 { break; }
        }
        return n / 1024;
    }

    thread_fn worker(n: i64) {
        print("worker sees ", big.len / 1048576, " MB; process ", rss(), " MB");
        qget<i64>();
    }

    fn main() {
        for i in 100000000 { big.push(1); }
        print("main filled 95 MB; process ", rss(), " MB");
        let id = thread_spawn(worker, 0);
        qput(0);
        thread_wait(id);
        print("after the worker returned; process ", rss(), " MB");
    }

Measured on the desktop (WSL2 kernel 6.18.54.1, `goose build --cc gcc --standalone`,
2026-10-14): 97 MB after main fills `big`, 383 MB while the worker runs (`big`, the
image, the packet, and the worker's copy: four of 95 MB), and 192 MB after it returns
(`big` and the image, still in main).

Workaround: `rest.goose` loads the records on a loader thread, which spawns the workers
and returns, so the runtime unmaps its stacks, the image among them. It clears what
the workers don't read before it spawns them. Nothing here frees the packet.

### An optional passed as `null` at one call and a value at another specializes twice

Found on `0bdbd18`, task 027. Status: open (unchanged at `46356c2`)

A function that takes `const T?` and is called with the constant `null` at one site and
with a value at another is specialized once for each, and so is every function it
passes the optional on to. Task 027's p1 (`a9783c8`) passed the loops' wake that way
through `go`, `drive`, `advance`, `pump`, and `answer`, which grew `.text` from 267 to
424 KB and cost 39.5 user instructions per request on epoll and 45.0 on uring, and was
reverted. The idiom it would have replaced is a sentinel: the event as a struct with a
`u8` kind, a placeholder `NO_EVENT` passed as `const Event&`, and a flag beside it.

A program in four variants tells the two parts of p1 apart: the event as a struct with
a kind or as a fixed-mode enum matched by its tag, and the wake as `const Ev&` with a
flag or as `const Ev?` passed `null` from one site and a value from another. With the
optional, Goose makes 97 specializations where it makes 93 with the reference, struct
or enum alike; the enum makes none more. gcc then folds all four to the same machine
code: 10 user instructions per iteration (`perf stat -e instructions:u`, 10 and 110
million iterations, the difference, 3 runs each, Ryzen 7 5800X3D, WSL2 kernel
6.18.54.1, gcc 15.2.0, `goose build --cc gcc --standalone`) and the same 3,373 bytes of
`.text`. So matching on the tag costs nothing, and the second specialization costs
nothing where gcc can merge it. In the loops, whose `answer` holds the whole inlined
handler (about 17 KB), the two copies stay apart, and p1's instructions came with
them. The struct variant, alone:

    struct Req { a: i64, b: i64 }
    struct Ev { kind: u8, req: const Req&, data: const u8[:], tag: i32 = 0 }
    var sink: i64 = 0;

    fn handle(ev: Ev) { if ev.kind == 0 { sink += ev.req.a + ev.data.len; } else { sink += ev.tag; } }
    fn answer(r: const Req&, data: const u8[:], wake: const Ev?) {
        if wake { handle(wake); }
        handle(Ev { kind: 0, req: r, data: data });
    }
    fn drive(r: const Req&, data: const u8[:], wake: const Ev?) {
        for k in 4 { if k == 0 { answer(r, data[k..], wake); } else { answer(r, data[k..], null); } }
    }
    fn go(r: const Req&, data: const u8[:], wake: const Ev?) { drive(r, data, wake); }

    fn main() {
        let r = Req { a: 1, b: 2 };
        let w = Ev { kind: 6, req: r, data: "", tag: 3 };
        for i in 100000000 {
            if i % 1024 == 1023 { go(r, "GET /x HTTP/1.1", w); } else { go(r, "GET /x HTTP/1.1", null); }
        }
        print(sink);
    }

`goose --check` reports 10 specializations for it, and 6 with `wake: const Ev&`, a
`woke: bool` beside it, and a placeholder event where it passes `null`.

Workaround: the sentinel the loops kept: `Event` with a `u8` kind and `NO_EVENT`,
passed as `const Event&`. An enum `Event` would be free if Goose specialized a function
once for an optional argument, whatever its call sites pass.

### A function can't keep its block from returning past it

Found on `46356c2`, task 027. Status: open

A `return` in a block returns from the function the block is written in, through the
function that calls the block, whose frames unwind with nothing of theirs run (spec
§7.6). Goose has no `finally` or `defer`, and nothing a function can declare to refuse
such a block, as Kotlin's `crossinline` does. So a loop that calls a handler block
can't close its sockets or answer the request when the block returns early, and can't
tell that it did. In `examples/`, three handlers written as blocks returned early; each
ended its worker's loop with the request unanswered and the client waiting, and the
compiler said nothing. Expected: a way for a function to refuse a block that returns
past it, or to run its cleanup when one does.

    fn serve<H>(n: i64) {
        print("open");
        for i in n { H(i); }
        print("closed");
    }

    fn worker() {
        serve(3) { i =>
            if i == 1 { return; }
            print("answered ", i);
        };
        print("serve returned");
    }

    fn main() { worker(); }

    $ goose blockret.goose
    open
    answered 0

Workaround: a handler that returns early is a function, passed by name or called from
the block (`docs/api.md`, "Handler").

### Data built at run time can't be shared read-only between threads

Found on `46356c2`, task 025. Status: open (not asked; contact waits on the maintainer
being allowed)

Threads share only static data (spec §11.2): string literals, `let` globals that lead
only to them, and `const` globals of fixed type with compile-time-evaluable
initializers. Every other global a worker uses is copied at `thread_spawn`. So records
that main loads at startup, and never writes again, cost one copy per worker: a REST
server with 4 workers holds tier C's records and prebuilt JSON four times, 17.4 MB
each, where hyper's threads share one (task 025). Expected: a way to share data that
is read-only from the first spawn on, as static data is shared, for example a global
frozen before any thread starts.

A `const` whose initializer calls a function isn't static data either. It compiles,
and is copied to each worker like a `var`, with nothing to say so:

    struct Rec { id: i64, n: i32 }

    fn make() -> Rec[4] {
        var r: Rec[4] = [Rec { id: 0, n: 0 }; 4];
        for i in 4 { r[i] = Rec { id: i * 10, n: i as i32 }; }
        return r;
    }

    const RECS: Rec[4] = make();

    thread_fn worker(i: i64) { print(RECS[i].id); }

    fn main() { thread_wait(thread_spawn(worker, 2)); }

The generated C fills `GS_GL->RECS_g` at startup and copies it into the worker's
globals (`memcpy(&GS_GL->RECS_g, img, ...)`).

`embed_file(path)` is the one way to share bytes made outside the program: every worker
views the same static data. The bytes are compiled into the program (a 10 MB file
makes 47 MB of generated C), and a worker must read them in place, since parsing them
into its own arrays copies them again.

Workaround: none for the copy itself. Task 025 works on keeping it to one per worker,
without the second that `thread_spawn`'s packet keeps.
