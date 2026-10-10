# Calling C from Goose

What the C in `shim/` sees of the Goose program, for writing the shim. The rules are in
the pinned checkout's spec, §7.10 and Appendix C; this page records how they come out in
the generated C. Checked on Goose `3536810` (2026-10-10) with TinyCC (`goose file.goose`)
and with gcc 15.2 (`goose -o file.c --standalone`, then `cc -O2 -Wall`). Recheck it
after moving the pin.

## Where the header goes

`goose --include shim/net.h` adds an `#include` of the header to the generated C after
the type declarations and the runtime's extern support, and before the prototypes for
the program's `extern fn`s. So the header can:

- Use the generated types and the runtime's `sl_u8` and `gs_rref`.
- Include system headers (`<sys/epoll.h>`, `<sys/socket.h>`, `<errno.h>`). Both
  TinyCC and gcc compile them.
- Define its functions `static`. Goose then emits a plain prototype for each `extern fn`,
  such as `int64_t shim_fill(sl_Ev_g);`, after the header. C accepts that and keeps the
  function static, with no warning under `-Wall`.

The header can't set feature-test macros such as `_GNU_SOURCE`: the runtime includes
`<stdint.h>`, `<stddef.h>`, `<string.h>`, `<stdio.h>`, `<stdlib.h>`, `<unistd.h>`,
`<signal.h>`, and `<sys/mman.h>` before it. `goose -D_GNU_SOURCE` writes the define at the
top of the generated C instead, for both backends; that is how `accept4` reaches the shim
([findings](goose-findings.md#an---include-header-cant-set-feature-test-macros)).

The path in the `#include` depends on the backend:

- With `-o`, the compiler rewrites the path relative to the output file's directory, so
  `scripts/build.sh` gets `#include "../shim/net.h"` in `build/server.c`. An `-o` without
  a directory breaks an absolute path
  ([findings](goose-findings.md#an---include-path-is-rewritten-wrongly-when--o-names-no-directory)).
- A TinyCC run uses the path as given, relative to the working directory, so pass an
  absolute one.

## Names and layouts

| Goose | C |
|---|---|
| `struct Ev { fd: i32, events: u32, tag: u64 }` | `Ev_g` with fields `fd_g`, `events_g`, `tag_g`, under `#pragma pack(1)` |
| `Ev[:]` | `sl_Ev_g`: `{ Ev_g *data; int64_t len; }` |
| `u8[:]`, `i32[:]` | `sl_u8`, `sl_i32`: scalar slices have no `_g` |
| `Ev&` | `Ev_g *` |
| `u8[>..]&` | `gs_rref`, appended to with `gs_bld_append(ref, p, n)` |
| `Ev[64]` | `a64_Ev_g`: `{ Ev_g e[64]; }` |
| `bool` | `uint8_t`, not C's `bool` |
| `namespace sys;` `struct Event` | `sys_Event_g3`, and its slice `sl_sys_Event_g3`: the namespace's length follows `_g` |
| `extern fn shim_fill(...)` | the symbol `shim_fill`, unchanged |

Goose structs are packed, with no padding. A struct of a `u32` and a `u64` is 12 bytes,
which matches `struct epoll_event` on x86-64 but not on ARM, where the kernel's struct is
16 bytes. That is why the shim converts epoll events into a struct of Goose's own instead
of letting the kernel write into Goose memory (task 002).

## On the Goose side

- A local fixed array must be initialized before it's passed to C, even when C only
  writes into it. `var evs: Ev[64];` is an error ("may be used before it is assigned");
  write `var evs: Ev[64] = [Ev { fd: 0, events: 0, tag: 0 }; 64];`. For a buffer that's
  reused across calls, declare it once outside the loop, and the fill runs once.
- `extern fn` parameters that C writes through must not be `const`, and a read-only one
  should be (`const u8[:]`), because a string literal is `const u8[:]` (spec §9.5).
- Returning `-errno` from C works as the task 002 convention expects: `close(-1)` comes
  back as `-9` (`EBADF`).
- Nested references and slices don't cross (spec §7.10): `extern fn wv(fd: i32, parts:
  const u8[:][:])` is rejected with "nested references and slices do not cross". So
  Goose can't hand C an `iovec` list, and the server batches its responses into one
  buffer for a single `send` instead of calling `writev`.

The checkout's `samples/24_call_c.goose` and `samples/call_c.h` are a complete worked
example.
