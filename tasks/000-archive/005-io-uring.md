# 005: io_uring

Status: done

Add an event loop on io_uring's completion model beside the epoll loop, which stays
either way: it is the baseline io_uring is measured against, and the loop on kernels
without io_uring. The HTTP parser and response code from task 003 stay as they
are; only the event loop and the shim change.

liburing's helpers are mostly `static inline` functions, which `extern fn` can't bind, so
`shim/uring.c` wraps the ones the loop uses as plain functions. Each worker owns its own
ring, which matches Goose's shared-nothing workers.

Task 004's profile favors trying it: after the parser fix, 73% of a worker's cycles are in
the kernel, serving plaintext with 256 connections, and 27% in user code. Add
`xitca-web` in its io_uring configuration to `bench/` as the io_uring competitor; the
others in task 004 use epoll, except odin-http, whose cap there comes from one `send` per
response, not from io_uring. HttpArena's fastest io_uring servers are competitors too:
zix and zeemo (Zig), first and fifth in its pipelined test, and libreactorng (C), ninth
(task 009 has the source of these figures).

## Acceptance criteria

- [x] `shim/uring.c` over liburing, with the liburing version and minimum kernel
      recorded
- [x] An io_uring loop per worker with multishot accept, multishot receive into a
      provided buffer ring, and sends batched per loop iteration
- [x] The same behavior as task 003's server: its tests pass against both loops,
      selected at build time
- [x] xitca-web, zix, zeemo, and libreactorng in `bench/`, pinned and in their fastest
      documented configuration
- [x] Task 004's matrix rerun with both loops, and the results recorded here
- [x] A decision recorded in `docs/decisions.md`: which loop is the default,
      and why; the epoll loop stays buildable and tested

## Progress

### 2026-10-11

`LOOP=uring scripts/build.sh` builds the io_uring loop (`src/uring.goose`, over
`src/ring.goose` and `shim/uring.c`); `docs/architecture.md` describes it.
`scripts/test-unit.sh` and `scripts/test-http.sh` pass against both loops at Goose
`f084e52`. `scripts/test-echo.sh` is still to run against the io_uring build off CPU 15:
pinned to that one CPU beside the benchmark, its EPIPE check failed for both builds. The design follows from spec §7.10: the ring owns every
buffer the kernel touches after a call, so each receive and each send is copied once more
than in the epoll loop. Not yet measured: task 009's final run had the machine.

The io_uring loop's provided buffers went from 1,024 to 256 of 4 KB per worker: the
same rate, with half the peak RSS. `bench/run.sh` with 4 workers, `RUNS=3 DURATION=10
LATENCY=0`, on the machine of `docs/results.md`, at `07f43ff`; medians and spreads of
wrk's rate, and peak RSS:

| Cell | 1,024 buffers | 256 buffers |
|---|---|---|
| plaintext, 1,024 conns | 6.934 M (6.923–6.984 M), 21.9 MB | 6.934 M (6.823–7.005 M), 9.5 MB |
| plaintext, 4,096 conns | 6.354 M (6.270–6.499 M), 32.9 MB | 6.454 M (6.347–6.544 M), 15.3 MB |
| json, 256 conns | 0.479 M (0.479–0.495 M), 21.5 MB | 0.489 M (0.488–0.496 M), 9.4 MB |

The loop gives each buffer back in the pass that takes it, and running out only ends a
receive, which the loop queues again. The runs are in
`bench/results/2026-10-11-uring-bufs/`.

The io_uring loop is faster than the epoll loop in every cell, by 11% to 21%.
`bench/run.sh` with its defaults (3 runs of 15 s after 5 s of warm-up, interleaved,
latency step on) at `ae046c9`, on the machine of `docs/results.md`, `TESTS="plaintext:256
plaintext:1024 json:256"`, 1 worker on CPU 0 and 4 on CPUs 0-3. Median wrk rates, the
ratio to the epoll loop, and peak RSS:

| Cell | goose (epoll) | goose-uring | vanilla-io_uring | libreactorng | zix | zeemo | xitca-web |
|---|---:|---:|---:|---:|---:|---:|---:|
| plaintext 256, 1 w | 1.937 M | 2.159 M, 1.11 | 2.668 M, 1.38 | 2.352 M, 1.21 | 1.767 M, 0.91 | 0.836 M, 0.43 | 1.101 M, 0.57 |
| plaintext 256, 4 w | 6.003 M | 7.134 M, 1.19 | 8.145 M, 1.36 | 6.965 M, 1.16 | 5.133 M, 0.86 | 2.389 M, 0.40 | 3.302 M, 0.55 |
| plaintext 1,024, 1 w | 1.878 M | 2.163 M, 1.15 | 2.540 M, 1.35 | 2.441 M, 1.30 | 1.512 M, 0.81 | 0.759 M, 0.40 | 1.046 M, 0.56 |
| plaintext 1,024, 4 w | 5.784 M | 7.024 M, 1.21 | 8.250 M, 1.43 | 7.384 M, 1.28 | 5.442 M, 0.94 | 2.695 M, 0.47 | 3.518 M, 0.61 |
| json 256, 1 w | 0.145 M | 0.172 M, 1.19 | 0.148 M, 1.02 | 0.129 M, 0.89 | 0.152 M, 1.05 | 0.140 M, 0.97 | 0.098 M, 0.67 |
| json 256, 4 w | 0.426 M | 0.510 M, 1.20 | 0.456 M, 1.07 | 0.545 M, 1.28 | 0.552 M, 1.30 | 0.540 M, 1.27 | 0.419 M, 0.98 |
| Peak RSS, 4 w | 2.3–2.4 MB | 9.4–11.8 MB | 36.9–133.4 MB | 6.2–22.2 MB | 6.9–13.2 MB | 6.8–12.8 MB | 25.5–33.5 MB |

- vanilla-io_uring leads goose-uring in plaintext by 14% to 24%, and had 450 to 766
  wrk timeouts per run at 1 worker and 1,024 connections (1,837 errors in the cell).
  libreactorng leads it by 5% to 13%, except at 256 connections with 4 workers, where
  goose-uring leads by 2%.
- In JSON at 4 workers, zix, libreactorng, and zeemo lead goose-uring by 6% to 8%. At 1
  worker goose-uring leads every server.
- goose-uring's peak RSS is 4 to 5 times the epoll loop's: 256 provided buffers of 4 KB
  per worker, and the shim's send records.
- may-minihttp, hyper, tokio, and dusty were copied from task 009's final run
  (`REUSE`, same binaries and settings). The epoll loop ran 2% slower to 12% faster here
  than there (plaintext 256 with 4 workers: 6.003 M against 5.467 M), so those four
  compare with this run's Goose numbers at a disadvantage of up to 12%; compare them with
  task 009's instead. vanilla-epoll is left out: its JSON cells leak memory
  (`docs/development.md`), and task 009's run measured only one of them.

The runs are in `bench/results/2026-10-11-uring-matrix/`.

### Rechecked (2026-10-11, task 011)

`goose build` at the pin never recompiles a sidecar's C once a checkout has built it
([historical finding](https://github.com/kaitk/goose-http/blob/9a6afc695ff5d6b6791a40771aa0ded7d5c00fe6/docs/goose-findings.md#goose-build-on-linux-never-sees-a-sidecars-c-change)),
so the runs above may have linked a shim from before a change, such as the provided
buffers' count at `9291dd6`. Task 011 ran both again with every shim compiled afresh, on
the same machine, and both held:

- 256 provided buffers served within 1% of 1,024 in each of the three cells above, at
  half the peak RSS.
- The io_uring loop led the epoll loop in every cell of `TESTS="plaintext:256
  plaintext:1024 json:256"`, 1 and 4 workers: by 9% to 20% at `1bea5a0`, before
  the package, and by 9% to 24% in the package at `2d61b55`.

The numbers and their setup are in task 011's file.
