# Goose findings

Gaps, bugs, and surprises in the pinned Goose compiler and stdlib, found while building
this port. Each entry has a minimal program that shows it, the Goose commit it was found
on, the workaround used here, and whether it has been reported upstream.

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

### `thread_spawn` doesn't take a `thread_fn` bound in another module

Found on `efe3155`, task 011. Status: open; rewritten at `46356c2` to what remains

A generic function can spawn the `thread_fn` it was passed only when both are in the
same module. Spec §7.6 lets a function value be "a function name (including a bound
generic function parameter)", and §11.2's `thread_spawn(worker, args…)` takes a
`thread_fn`'s name. Within one file, `fn spawn<W>(n: i32) -> i64 { thread_spawn(W, n) }`
called as `spawn(1, worker)` compiles at `46356c2`. With the generic function in a
module the program imports, a package's or a plain one, it is refused:

    // mylib.goose
    namespace mylib;

    struct Cfg { n: i32 }

    fn run<W>(c: Cfg) { thread_wait(thread_spawn(W, c)); }

    // main.goose
    import mylib;

    thread_fn worker(c: mylib::Cfg) { print("worker ", c.n); }

    fn main() { mylib::run(mylib::Cfg { n: 1 }, worker); }

    $ goose --check main.goose
    mylib.goose:5: error: thread_spawn's first argument names a thread_fn

Expected: `W` is bound to `worker`, a `thread_fn`, so the spawn is the same as
`thread_spawn(worker, c)` wherever `run` is declared. It's what task 011 planned as
`http::spawn_workers(worker, cfg)`.

Workaround: the package gives the worker count, `http::worker_count(cfg)`, and the
program writes the spawn loop itself.

### A `null` branch doesn't take an optional type from its sibling branch

Found on `a6249a4`, task 027. Status: open (unchanged at `46356c2`)

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

### A long-distance return can't carry a struct holding a slice of a parameter

Found on `3536810`, task 003. Status: open (unchanged at `46356c2`)

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

### A string literal in a struct makes it refer into any array a callee shrinks

Found on `5c83a5a`, task 015. Status: open (unchanged at `46356c2`)

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

### A `for` over a literal array of strings refers into any array its body shrinks

Found on `46356c2`, task 027. Status: open (not reported)

A `for` loop over an array literal of string literals is refused when its body calls a
function that shrinks an array declared before the loop: "cannot call shrink, which
shrinks p: the for loop at a.goose:5 iterates ["a", "b"], whose elements may refer into
p (§5.1)". The elements point at static data, not into `p`. The same literal bound to a
`let` first, before or after `p`, checks, and so does a literal of integers. Expected:
it checks as the named array does.

    fn shrink(out: u8[>..]&) { out.resize(0); }

    fn main() {
        var p: u8[>..] = [];
        for e in ["a", "b"] {
            shrink(p);
            print(e);
        }
    }

Workaround: bind the literal to a `let` and iterate that (`test_files`,
`test/test_http.goose`).

### A limited array's `..` default writes its whole capacity

Found on `e7792d7`, task 009. Status: open (unchanged at `46356c2`)

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

### One unproven change to an index costs every bounds check on it

Found on `3536810`, task 004. Status: open; rewritten at `46356c2` to what remains

The bounds-check analysis proves `0 <= pos <= buf.len` for a whole function at once. A
single write to `pos` that it can't prove stays in range, anywhere in the function,
drops the proof, and with it every check indexed by `pos`, including those in loops that
run before the write. Two guarded writes still count as unproven:

- One under a guard of the form `pos + 8 <= buf.len`. `CmpAdmissible` (`src/bce.h`)
  rejects "variable + constant" as an operand, because the sum could have wrapped, and
  nothing rewrites it to the equivalent `pos <= buf.len - 8`, which it accepts.
- One under a guard on a search's result, `k <= buf.len - pos`, at `-O2` when the search
  is std's `position`, which `-O2` inlines between the guard and the write. At `-O0`
  the guard keeps them.

Expected: the checks the function proved without these writes, at least those before
them.

    fn scan(buf: const u8[:]) -> i64 {
        var pos = 0;
        while pos < buf.len && buf[pos] == 'a' { pos++; }
        if pos + 8 <= buf.len { pos += 8; }
        while pos < buf.len && buf[pos] == 'b' { pos++; }
        return pos;
    }

    fn main() { print(scan("aa  bbcxxxxxxxxxx")); }

    $ goose -O0 --check z2.goose
    bce: elided 0/2 index and 0/0 slice checks

`while pos < buf.len - 7 { pos += 8; }` keeps them. Admitting `v + c` in
`CmpAdmissible` where the addition is provably exact would cover it. The second:

    import std;

    fn scan(buf: const u8[:]) -> i64 {
        var pos = 0;
        while pos < buf.len && buf[pos] == 'a' { pos++; }
        let k = position(buf[pos..], 'b');
        if k > 0 && k <= buf.len - pos { pos += k; }
        while pos < buf.len && buf[pos] == 'b' { pos++; }
        return pos;
    }

    fn main() { print(scan("aaxxbbc")); }

    $ goose -O0 --check m.goose
    bce: elided 2/2 index and 0/1 slice checks
    $ goose -O2 --check m.goose
    bce: elided 0/2 index and 0/1 slice checks

Expected: the guard's facts kept across an inlined call that writes neither `pos` nor
`buf`.

Workaround: `http::parse` advances past `find_any`'s result, an external call, under
`k <= buf.len - pos`. Its comment points here.

### A struct literal is built in whole temporaries and copied

Found on `e7792d7`, task 009. Status: open (unchanged at `46356c2`)

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

## Feature requests

### An --include header can't set feature-test macros

Found on `3536810`, task 002. Status: open (unchanged at `46356c2`)

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

### `goose build` takes no C flags for a cross compiler

Found on `46356c2`, task 029. Status: open

`goose build --cc` takes one path, and passes the compiler only `-O2` (or `-O0 -g`) and
what sidecars name. A Yocto SDK's compiler is a command with flags, `$CC`, such as
`aarch64-poky-linux-gcc -mcpu=cortex-a53 --sysroot=/opt/poky/...`: the SDK's
environment script keeps the target's flags in `$CC`, not in the compiler. Expected: a way to pass flags for the
program's, the runtime's, and every package's C, such as `--cflags` or `GOOSE_CFLAGS`,
which a cross build needs for all three alike. A bare cross compiler's name fails too:

    $ goose build --cc aarch64-linux-gnu-gcc -o hello examples/hello/hello.goose
    unknown C compiler name aarch64-linux-gnu-gcc (--cc): the names are clang, gcc and cc, or give a path

Workaround: a script that runs `$CC "$@"`, given to `--cc` by its path
([embedded Linux](embedded.md#with-a-yocto-sdk)).

### The stdlib has no word loads

Found on `3536810`, task 004. Status: open; rewritten at `46356c2` to what remains

Goose has no way to read a `u64` out of a `u8` buffer: `binary` reads `u16` and `u32`
(`read_u16le`, `read_u32le`), and nothing longer. The workaround that works is to
assemble the word from eight bytes with shifts, which gcc 15 at `-O2` compiles to one
64-bit load once the bounds checks are gone:

    let b = buf[pos..pos + 8];
    let w = b[0] | (b[1] as u64 << 8) | (b[2] as u64 << 16) | (b[3] as u64 << 24) |
            (b[4] as u64 << 32) | (b[5] as u64 << 40) | (b[6] as u64 << 48) |
            (b[7] as u64 << 56);

Expected: a word read like `binary`'s `read_u32le` for `u64` that's documented to
compile to one load.

Workaround, until task 008: `http::parse` scanned header values eight bytes at a time
with the word above and a SWAR test, and finished a byte at a time. It was the profile's
largest single change: about 700 fewer instructions per request. Since task 008 it
calls `std`'s `find_any`, which scans 16 bytes at a time, and saved another 175 user
instructions per request; nothing here needs a word load now.

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

### A struct literal can't be passed to a `const T&` parameter

Found on `5c83a5a`, task 015. Status: open (unchanged at `46356c2`)

A call that passes a struct literal, or any temporary, to a `const T&` parameter finds
no overload, where C++ would bind the reference to the temporary. Expected: the
temporary lives until the call returns, as the in-place construction rule (spec §4.3)
already places it.

    struct E { k: i32 }

    fn g(e: const E&) -> i32 { e.k }

    fn main() { print(g(E { k: 1 })); }   // error: cannot pass E as const E&

Workaround: bind the literal to a local first (`let ev = Event { ... }; resume(c, ev);`
in the loops' `delivered` and `timed_out`).

### Goose can't express a movemask

Found on `bab8b6f`, task 008. Status: open; rewritten at `46356c2` to what remains

The fast HTTP parsers find the first byte of a set in a 32-byte block with a compare,
`movemask`, and a trailing-zero count (httparse's AVX2 path), about six instructions.
The Goose spelling builds the mask a bit per byte, and neither gcc 15 nor clang 21 turns
it into `pmovmskb`. `std`'s `ctz` is now the C compilers' builtin. In `http::parse`, the
mask with a loop for `ctz` cost 2,462 instructions per parse of wrk's request under gcc,
against 1,356 for a block reduced with a minimum and 1,270 for `find_any`:

    var ends: u32 = 0;
    for c, i in buf[pos..pos + 32] {
        let bit: u32 = 1;
        if (c < ' ' && c != '\t') || c == 0x7f { ends |= bit << i; }
    }
    if ends != 0 { let k = ctz(ends as u64); ... }

Expected: a mask-building loop the backend writes in a shape the C compilers recognize,
or a stdlib function for it.

Workaround: `std`'s `find_any`, whose runtime does the movemask and count in C.

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

### A reference variable can't be rebound to one with another root

Found on `5c83a5a`, task 015. Status: open (unchanged at `46356c2`)

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
the block (`examples/README.md`, "Handler").

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

### The stdlib's JSON parser and reader take only a whole text

Found on `5c83a5a`, task 015. Status: open (unchanged at `46356c2`)

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

### A simd fn parser ran slower than its baseline

Found on `bab8b6f`, task 008. Status: open (last timed at `f084e52`; not timed again at
`46356c2`)

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
