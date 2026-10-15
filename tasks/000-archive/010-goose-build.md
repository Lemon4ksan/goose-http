# 010: Build with goose build and sidecar C

Status: done

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
- [x] The epoll build beside the last `scripts/build.sh` one, in `bench/run.sh`'s cells
      where Goose and vanilla-epoll are closest: the same rate within the runs' spread,
      or the difference recorded
- [x] HttpArena's Goose image built and run once with `goose build`
- [x] `docs/development.md`, `docs/c-interop.md`, `docs/architecture.md`, and
      the two findings' workarounds updated

## Progress

### 2026-10-11

Both loops build with `goose build` at Goose `efe3155` and pass `scripts/test-unit.sh`,
`scripts/test-http.sh`, and `scripts/test-echo.sh`, run on CPU 15 beside task 009's final
run. The shim is no longer in the program's translation unit, so gcc can't inline
`net_recv`, `net_send`, and the rest into the loop; that is a call per syscall, to be
measured. The epoll binary grew from 68,376 to 72,736 bytes.

The epoll build is as fast as before. `bench/run.sh` ran `goose-o`, task 009's final
binary built by the old `scripts/build.sh`, beside `goose-gb`, built by `goose build` at
`99a9ebb`: plaintext at 256 and 1,024 connections, 1 and 4 workers, `RUNS=5 DURATION=10
LATENCY=0`, alternating servers within each round. Machine: Ryzen 7 5800X3D, WSL2 kernel
6.18.40.1, Ubuntu 26.04.1, server on CPUs 0-3, wrk on 4-15 with 8 threads. Median wrk
rates, with the spread over the runs:

| Conns | Workers | `goose-o` | `goose-gb` | Ratio |
|---:|---:|---:|---:|---:|
| 256 | 1 | 1.701 M (1.613–1.887 M) | 1.688 M (1.604–1.813 M) | 0.99 |
| 256 | 4 | 5.188 M (4.735–5.669 M) | 5.628 M (5.363–5.711 M) | 1.08 |
| 1,024 | 1 | 1.733 M (1.481–1.845 M) | 1.802 M (1.695–1.874 M) | 1.04 |
| 1,024 | 4 | 5.244 M (5.047–5.516 M) | 5.467 M (5.113–5.651 M) | 1.04 |

Every `goose-gb` median is inside `goose-o`'s spread, so the lost inlining of the shim
calls doesn't show. Peak RSS (2.1 to 2.4 MB) and server CPU time are the same. The runs
are in `bench/results/2026-10-11-goose-build/`.

HttpArena's Goose image builds with `goose build` and passes `bench/httparena.sh
validate` (24 of 24). One `FRAMEWORKS=goose bench/httparena.sh run` at `93c7bc8`, on the
same machine with Docker 29.8.2, beside the Goose entry of task 009's final HttpArena run
(`httparena-2026-10-11-final2`, `scripts/build.sh` before this task). Each number is the
harness's best of 3 runs of 5 s:

| Profile | Before | `goose build` | Ratio |
|---|---:|---:|---:|
| baseline | 544,621 req/s | 520,410 req/s | 0.96 |
| limited-conn | 307,688 req/s | 309,822 req/s | 1.01 |
| latency-1m, CPU per request (lower is better) | 10.91 µs | 10.62 µs | 0.97 |
| pipelined | 7,070,060 req/s | 6,900,681 req/s | 0.98 |

The runs were hours apart, and a best of 3 has no spread to compare against. The
differences are within the 5% that sessions drift by (task 009), and `bench/run.sh`'s
interleaved runs above found no slowdown. The run is in
`bench/results/httparena-2026-10-11-goose-build/`.
