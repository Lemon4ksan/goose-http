# 010: Build with goose build and sidecar C

Status: in progress

Goose `efe3155` builds a program in one command, `goose build`, and compiles the C a
root file's sidecar names beside it, per platform (`c_sources_linux`, `_macos`,
`_windows`; the pinned checkout's `docs/packages.md`). The server moves to it: the shim
becomes C files of their own instead of headers spliced in with `--include`, which drops
two findings' workarounds, and task 006 picks each platform's shim in a sidecar instead
of in a build script. The servers it builds must run as fast as before.

## Acceptance criteria

- [x] `scripts/build.sh` runs `goose build --cc gcc --standalone`, with
      `src/main.build` and `src/main_uring.build` naming the shim and liburing
- [x] `shim/net.c` and `shim/uring.c` compile on their own: no generated types, no
      `-D_GNU_SOURCE` or `--include` on the command line
- [x] The unit, HTTP, and echo tests pass against both loops
- [x] `bench/compilers.sh`, `bench/build.sh`, and HttpArena's Goose image build with it
- [ ] The epoll build beside the last `scripts/build.sh` one, in `bench/run.sh`'s cells
      where Goose and vanilla-epoll are closest: the same rate within the runs' spread,
      or the difference recorded
- [ ] HttpArena's Goose image built and run once with `goose build`
- [x] `docs/development.md`, `docs/c-interop.md`, `docs/architecture/README.md`, and
      the two findings' workarounds updated

## Progress

### 2026-10-11

Both loops build with `goose build` at Goose `efe3155` and pass `scripts/test-unit.sh`,
`scripts/test-http.sh`, and `scripts/test-echo.sh`, run on CPU 15 beside task 009's final
run. The shim is no longer in the program's translation unit, so gcc can't inline
`net_recv`, `net_send`, and the rest into the loop; that is a call per syscall, to be
measured. The epoll binary grew from 68,376 to 72,736 bytes.
