# Calling C from Goose

What the C in `shim/` shares with the Goose program, for writing the shim. The rules are
in the pinned release's spec, §7.10 and Appendix C; this page records how they come out
in the generated C. Checked on Goose `3536810` (2026-10-10) with TinyCC (`goose file.goose`)
and with gcc 15.2 (`goose -o file.c --standalone`, then `cc -O2 -Wall`). Recheck it
after moving the pin.

## Where the shim goes

The shim is plain C files that the package's sidecar names, `c_sources_linux =
["shim/net.c", "shim/uring.c"];` in `http.build`. `goose build` compiles each with the C compiler
and links it with the program (the pinned release's `docs/packages.md`). Goose emits a
prototype for each `extern fn`, such as `int64_t net_recv(int32_t, sl_u8);`, from the
declaration, and the shim defines the function under that name.

A shim file is its own translation unit, so:

- It sees none of the generated C. It declares the layouts it shares with Goose itself,
  from the table below, all packed: `typedef struct { uint8_t *data; int64_t len; }
  net_bytes;` for a `u8[:]`, and `http::PollEvent`, each under `#pragma pack(push,
  1)`. A `_Static_assert` checks each size: `sizeof(void *) + 8` for a slice, which
  holds on 32-bit and 64-bit targets alike.
- It can't reach the runtime, so it can't append to a `u8[>..]&` (`gs_bld_append`).
  `net_strerror` writes into a `u8[:]` and returns the length instead.
- It sets its own feature-test macros: `shim/net.c` starts with `#define _GNU_SOURCE`.
- The C compiler doesn't inline its functions into the program's C.
- MSVC compiles C as C89 with extensions unless asked for more, and the shim uses C11's
  `_Static_assert`, so `http.build` passes `c_flags_msvc = ["/std:c11"]`.
  MSVC has no `__attribute__((packed))`, so every shim packs with `#pragma pack(push,
  1)`, which gcc and clang accept too.

`goose --include header.h` still splices a header into the generated C, after the type
declarations and before the `extern fn` prototypes, where it can use the generated types.
The server used it before task 010. Such a header can't set feature-test macros: the
runtime's system headers come first, so `-D_GNU_SOURCE` or a shim C file that defines
it does.

## Names and layouts

| Goose | C |
|---|---|
| `struct Ev { fd: i32, events: u32, tag: u64 }` | `Ev_g` with fields `fd_g`, `events_g`, `tag_g`, under `#pragma pack(1)` |
| `Ev[:]` | `sl_Ev_g`: `{ Ev_g *data; int64_t len; }`, packed: 16 bytes on a 64-bit target, 12 on a 32-bit one |
| `u8[:]`, `i32[:]` | `sl_u8`, `sl_i32`: scalar slices have no `_g` |
| `Ev&` | `Ev_g *` |
| `u8[>..]&` | `gs_rref`, appended to with `gs_bld_append(ref, p, n)` |
| `Ev[64]` | `a64_Ev_g`: `{ Ev_g e[64]; }` |
| `bool` | `uint8_t`, not C's `bool` |
| `namespace sys;` `struct PollEvent` | `sys_PollEvent_g3`, and its slice `sl_sys_PollEvent_g3`: the namespace's length follows `_g` |
| `extern fn shim_fill(...)` | the symbol `shim_fill`, unchanged |

Goose structs are packed, with no padding. A struct of a `u32` and a `u64` is 12 bytes,
which matches `struct epoll_event` on x86-64 but not on ARM, where the kernel's struct is
16 bytes. That is why the shim converts epoll events into a struct of Goose's own instead
of letting the kernel write into Goose memory (task 002).

The slice struct is packed too. On a 64-bit target that changes nothing, but on a 32-bit
one an unpacked `{ uint8_t *data; int64_t len; }` is 16 bytes, aligned to 8, and passes
in different registers from Goose's 12. A shim that declared it unpacked received every
slice garbled on armhf (task 030).

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

The release's `samples/24_call_c.goose` and `samples/call_c.h` are a complete worked
example.
