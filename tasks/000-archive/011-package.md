# 011: goose-http as a Goose package

Status: done (asked for 2026-10-11, done 2026-10-11)

Goose `efe3155` has packages: a program declares one in its root file,
`import http from "github.com/kaitk/goose-http@v0.1.0";`, and the compiler fetches the
repository, compiles the C its sidecar names, and links it (the pinned checkout's
`docs/packages.md`). This repository becomes such a package, so a program can serve HTTP
with its own routes; the benchmark server becomes one program that uses it.

The design, proposed:

- The package is `http`, with its entry `http.goose` at the repository root and every
  module in `namespace http`: a package has one namespace, and namespaces don't nest
  (`namespace http::sys;` is a parse error at `efe3155`). `sys::` and `ring::` become
  part of `http::`.
- `http.build` names each platform's shim, which picks the backend at compile time, as
  libuv's build and Go's build tags do: `shim/net.c` and `shim/uring.c` with liburing on
  Linux, `shim/kqueue.c` on macOS, and `shim/net_win.c` and `shim/iocp.c` on Windows.
- A program passes its routes to the loop as a function value, which Goose compiles into
  the loop, with no runtime function pointers (spec §7.6). `thread_spawn` copies only
  flat arguments (§11.2), so the program owns the `thread_fn` and calls the loop from it:

  ```goose
  import http from "github.com/kaitk/goose-http@v0.1.0";

  thread_fn worker(port: i32) {
      http::serve(port) { req, body, out => http::text(out, req, "Hello, World!") }
  }

  fn main() { http::spawn_workers(worker, 8080); }
  ```

  A prototype at `efe3155` ran this shape: a package from a directory, with sidecar C,
  whose generic loop a program's `thread_fn` called with a block.
  `http::spawn_workers` taking a `thread_fn` as a function value doesn't compile at
  `efe3155`: `thread_spawn` rejects a function value bound to a `thread_fn`
  (`docs/goose-findings.md`). So the program spawns its workers itself, with
  `http::worker_count(cfg)` (2026-10-11), and the loops take a `Config`, not a port.
- The routes in `http::respond` today, TechEmpower's and HttpArena's, move into the
  benchmark server's handler, a program in `server/` that imports the package from
  `"../"`. The parser, the response helpers, and the date stay in the package.
- Two entry points, and the program picks one by calling it (decided 2026-10-11). Goose
  compiles a generic function only where it's called, so the one a program doesn't call
  never reaches its binary, and the choice needs no flag:
  - `http::serve` is the portable loop, today's `src/uring.goose`, over the ring API of
    `src/ring.goose`, as Boost.Asio and libxev put one completion API over every
    platform. Linux runs it on io_uring, Windows on IOCP (`shim/iocp.c`), and macOS on a
    ring emulated over kqueue in C, as `shim/iocp.c` emulates multishot requests. On
    Linux, `ur_create` falls back to the same emulation over epoll when
    `io_uring_setup` fails, as in a container whose seccomp profile blocks io_uring.
  - `http::serve_epoll` is today's readiness loop, `src/server.goose`, on Linux (epoll)
    and macOS (kqueue). On Linux it uses a quarter of the io_uring loop's memory and runs
    where io_uring is blocked, and on macOS it skips the emulation's copies. On Windows it fails at startup with `ENOSYS`.
  The benchmark server reads `LOOP=epoll|uring` at startup and calls one of them,
  uring by default on Linux, as task 005 decided. A runtime pick inside the package was
  rejected: no event-loop library we looked at does it, except as a fallback from
  io_uring to epoll. The cost of one sidecar: every Linux program that imports `http`
  links liburing, even one that calls only `serve_epoll`.
- Before the handler can go in, the loops' request handling becomes one function both
  call: `answer` was nearly the same in `src/server.goose` and `src/uring.goose`, with
  routes wired into it (`http::respond`, and `http::reads_body`'s `/baseline11`).
  A handler's response must not abort the process. Done (2026-10-11): `answer` in
  `src/app.goose` serves both loops, and the write buffer grows to take a response of
  any size whole.
- A library can't end the process: `http::serve` returns errors that `sys::check`
  and the shims turned into exits, and takes its settings (address, limits,
  timeouts, buffer sizes, workers) as one flat struct instead of constants and
  `WORKERS`. Done (2026-10-11): `Config` and `Error` in `src/app.goose`. The loops
  still write two notes to stderr, `accept` at the fd limit and an `epoll_ctl` that
  failed for one connection, as they go on serving.

## The handler (decided 2026-10-11)

Task 013's items 6, 7, and 8 decide the handler's shape: a handler called once per
request can't read a body in pieces or stream a response. `v0.1.0` serves requests and
responses of a fixed size, the second of task 013's options, and the handler is:

```goose
http::serve(cfg) { req, body, out => ... }
```

- `req` is `http::Request`, the parsed head, with slices into the read buffer: method,
  target, version, keep-alive, the announced body length, and chunked framing.
- `body` is the whole request body when it fits in the read buffer (`max_head`) with its
  head, chunked bodies decoded. A longer `Content-Length` body is dropped as it arrives,
  and `body` is empty while `req.body` gives its length, so the handler can refuse it.
  This replaces the routes' `reads_body`: the loop needs no second function value to
  ask whether to keep a body. Implemented in this step.
- `out` is a reply: the worker's growable write buffer, with what the response's
  framing needs from the request (keep-alive, version, `HEAD`) and the cached `Date`.
  The handler writes one whole response of any size through helpers that write the
  status line and the fields every response has, the handler's own fields, and the
  body with its `Content-Length`. Status codes are a table the helpers look up, any
  code the handler names.
- Why not more now: header lookup (013 item 6) adds functions over `req`, and a
  `Request` field for the whole head, without changing the handler. Bodies read in
  pieces (item 7) and streamed responses (item 8) need a handler that resumes, which
  spec §7.6 rules out as a stored function value; they would come as another entry
  point, with per-connection state for the body or the stream, after `v0.1.0`.

## Where it stands (2026-10-11)

Steps 1 to 7 of the plan are done, each its own commit, with the unit tests,
`test-http.sh`, and `test-echo.sh` passing on Linux (the uring and epoll builds, and
`LOOP=uring-epoll`) and on Windows (iocp):

1. One `answer` in `http.goose` serves both loops.
2. A response of any size goes out through the growable write buffer and the spill
   pool (`/bytes`, `http_client.py large`).
3. The loops take `http::Config` and return `http::Error`.
4. The handler's shape, above.
5. The package layout, with the server in `server/`.
6. The fallback to a ring emulated over epoll, tested under Docker's default seccomp
   profile.
7. A program outside the repository, importing the package from GitHub at
   `bfd951a53a6c`, built with `goose build` and run with `goose run` on Linux and
   Windows. `goose run` can't run a program that reaches `thread_spawn`, so its
   program calls `http::serve` from `main`.
8. Task 012's macOS changes, merged into the package: `shim/kqueue.c` spreads a shared
   listener's connections across workers, with the listener level-triggered, and
   accepts with fewer syscalls; both loops register `OUT` only while a send waits;
   `http::worker_count` defaults to one worker per performance core on macOS, and
   both loops start with `net_worker_start`, which gives the worker the
   user-interactive QoS class there. `shim/ring_epoll.c` watches the listener only
   while an accept goes on, since a level-triggered listener left watched would end
   every wait at once, and watches `OUT` only while a send waits, as the epoll loop
   does.

9. Goose moved to `fe6c543`, which fixes neither of the two findings this task
   recorded.
10. The speed checks, below: the package's builds run as fast as the last build before
    this task, once the parser, the response writers, and the benchmark's route are
    `inline fn`.
11. macOS, 2026-10-11, at `bcac9ed` with Goose `fe6c543`, on the Mac of
    `docs/development.md`: `scripts/test-unit.sh`; then `LOOP=uring scripts/build.sh`
    and `LOOP=epoll scripts/build.sh`, each followed by `scripts/test-http.sh` and
    `scripts/test-echo.sh`, with `TIME_WAIT` drained between runs. All passed, and so
    did `http_client.py PORT slow` and `pipeline` against each loop with `WORKERS=4`.
    An fd-limit probe, `ulimit -n 300` with 4 workers and 400 clients, served 289 at
    the limit, used no measurable CPU over the 3 s it held them, and served the other
    111 once the first closed, in both loops. An idle uring server used no CPU over
    5 s: the emulation's level-triggered listener doesn't spin. Nothing needed a fix.

12. Tagged `v0.1.0` at `3c4761a`, which the README's example imports. That example,
    in a directory of its own, builds against the tag and serves `/` and a 404 on
    Linux and Windows.

Left for task 013's graceful shutdown: on macOS, `shim/kqueue.c`'s table of shared
listeners keeps the first worker's fd for the listener and never forgets a worker, so
a program that calls a loop again after one returned dups a closed fd.

## Speed (2026-10-11)

Measured on the machine of `docs/results.md`: Ryzen 7 5800X3D, WSL2 kernel
6.18.40.1-microsoft-standard-WSL2, Ubuntu 26.04.1, gcc 15.2.0, Goose `fe6c543`. Every
Goose binary was built after deleting `~/.goose/build/prog/*/native` and
`~/.goose/build/pkg/local/*/*/stamp`, so none links a shim compiled before a change
([historical finding](https://github.com/kaitk/goose-http/blob/9a6afc695ff5d6b6791a40771aa0ded7d5c00fe6/docs/goose-findings.md#goose-build-on-linux-never-sees-a-sidecars-c-change)).
The comparison builds are `1bea5a0`, the last commit before this task, built in a
copy of its tree at its own path: `goose-pre011` (`LOOP=epoll`) and `goose-pre011-uring`.

### Instructions per request

`bench/instructions.sh` (1 worker on CPU 0, plaintext pipelined 16 deep, 256
connections, wrk on CPUs 4-15 with 8 threads, `perf stat` for 10 s), 3 runs, the range
of the three. The first measurement, at `9eb5c0b`, found a regression:

| Build | Instructions per request | In user code | Cycles per request | Requests per second |
|---|---:|---:|---:|---:|
| epoll, `9eb5c0b` | 2,548-2,589 | 1,622-1,648 | 2,028-2,056 | 1.66-1.69 M |
| epoll, `1bea5a0` | 2,318-2,346 | 1,394-1,412 | 1,890-1,900 | 1.79-1.86 M |
| uring, `9eb5c0b` | 2,630-2,651 | 1,673-1,687 | 1,809-1,827 | 1.91-1.99 M |
| uring, `1bea5a0` | 2,418-2,458 | 1,457-1,481 | 1,711-1,725 | 2.01-2.05 M |

All of it was user code, about 230 instructions per request in both loops. The
generated C showed why. Before, Goose inlined `start` and `finish` into the routes, so
a constant status picked its status line at compile time, and gcc inlined `parse` into
the loop's only `answer`. Now the routes are the program's handler, a function of
their own; `http::start`, `http::finish`, and `http::status_line` were calls taking the
48-byte `http::Reply` by value, every append reloaded the write buffer's top and
length through it, and `parse` stayed a call, since the server links three `answer`s,
one for the epoll loop and two for the uring loop. `inline fn` (spec §7.13) on the
writers and the route took about 190 of the 230 back, and on `parse` the rest. At
`2d61b55`, with both:

| Build | Instructions per request | In user code | Cycles per request | Requests per second |
|---|---:|---:|---:|---:|
| epoll, `2d61b55` | 2,286-2,311 | 1,349-1,364 | 1,888-1,921 | 1.81-1.84 M |
| epoll, `1bea5a0` | 2,344-2,355 | 1,407-1,415 | 1,890-1,895 | 1.86-1.90 M |
| uring, `2d61b55` | 2,370-2,378 | 1,405-1,410 | 1,694-1,701 | 2.07-2.10 M |
| uring, `1bea5a0` | 2,417-2,439 | 1,453-1,467 | 1,702-1,725 | 2.06-2.07 M |

Both loops run about 55 fewer instructions per request than before this task, and the
epoll loop is inside task 009's 2,255-2,371. Its rate in this test was 3% below
`1bea5a0`'s at the same cycles per request; `bench/run.sh` below doesn't show it. The
runs are in `bench/results/2026-10-11-package-instructions/`.

### `bench/run.sh`'s closest cells

`bench/run.sh` with its defaults (3 runs of 15 s after 5 s of warm-up, interleaved,
latency step on), `TESTS="plaintext:256 plaintext:1024 json:256"`, 1 worker on CPU 0
and 4 on CPUs 0-3, wrk and h2load on CPUs 4-15 with 8 threads, at `2d61b55`. Median wrk
rates, with the spread of the 3 runs:

| Cell | goose (epoll) | goose-pre011 | goose-uring | goose-pre011-uring |
|---|---:|---:|---:|---:|
| plaintext 256, 1 w | 1.926 M (1.896-1.945) | 1.874 M (1.863-1.895) | 2.099 M (2.099-2.205) | 2.102 M (2.088-2.169) |
| plaintext 256, 4 w | 6.013 M (5.912-6.089) | 6.101 M (6.068-6.201) | 7.451 M (7.392-7.470) | 7.290 M (7.185-7.333) |
| plaintext 1,024, 1 w | 1.966 M (1.956-1.967) | 1.960 M (1.952-1.971) | 2.179 M (2.169-2.183) | 2.134 M (2.122-2.136) |
| plaintext 1,024, 4 w | 5.944 M (5.898-6.061) | 6.001 M (5.958-6.061) | 7.264 M (7.161-7.328) | 7.197 M (7.039-7.306) |
| json 256, 1 w | 0.148 M (0.146-0.152) | 0.146 M (0.143-0.153) | 0.169 M (0.167-0.177) | 0.169 M (0.169-0.179) |
| json 256, 4 w | 0.441 M (0.437-0.441) | 0.442 M (0.441-0.442) | 0.522 M (0.520-0.526) | 0.521 M (0.514-0.523) |

Each loop's rate is within 3% of `1bea5a0`'s in every cell. The spreads overlap in
all but three: the epoll loop is 3% faster at 256 connections with 1 worker, and the
uring loop 2% faster at 256 with 4 workers and at 1,024 with 1. Peak RSS is 2.2-2.4 MB
for the epoll loop, against 2.1-2.4 MB, and 4.7-11.8 MB for the uring loop, against
4.7-9.5 MB; the 11.8 MB is one cell, at 1,024 connections with 4 workers. may-minihttp, hyper,
tokio, and dusty were copied from task 009's final run (`REUSE`, the same binaries and
settings). The runs are in `bench/results/2026-10-11-package/`.

### Task 005's results, rechecked

Task 005's measurements ran in a checkout whose shim `goose build` may not have
recompiled after a change, so they were run again with clean builds:

- The io_uring loop still leads the epoll loop in every cell above: by 9% to 24% at
  `2d61b55`, and 9% to 20% between the two `1bea5a0` builds, against task 005's 11% to
  21%. io_uring stays the default.
- 256 provided buffers against 1,024, `bench/run.sh` with 4 workers, `RUNS=3
  DURATION=10 LATENCY=0`, at `2d61b55`, a copy of it with `ring_buffers` set to 1,024:

  | Cell | 256 buffers | 1,024 buffers |
  |---|---|---|
  | plaintext, 1,024 conns | 7.266 M (7.257-7.327 M), 12.1 MB | 7.309 M (7.286-7.353 M), 24.1 MB |
  | plaintext, 4,096 conns | 6.699 M (6.694-6.771 M), 15.0 MB | 6.604 M (6.545-6.608 M), 30.7 MB |
  | json, 256 conns | 0.519 M (0.506-0.520 M), 9.4 MB | 0.516 M (0.516-0.521 M), 21.4 MB |

  The same rate within 1%, at half the peak RSS, as task 005 found. The runs are in
  `bench/results/2026-10-11-package-uring-bufs/`.

## Acceptance criteria

- [x] `http.goose` and `http.build` at the root, every module in `namespace http`
- [x] `http::serve` and `http::serve_epoll` take the program's handler; the benchmark
      server in `server/` serves TechEmpower's and HttpArena's routes through either,
      picked by `LOOP`
- [x] `http::serve` runs on Linux, macOS, and Windows, and on Linux without io_uring
      (2026-10-11; on macOS over the emulation on kqueue)
- [x] A program outside the repository imports the package from git at a commit, and
      `goose build` and `goose run` both work with it
- [x] The tests pass, and the server's rate in `bench/run.sh`'s closest cells matches
      task 010's build within the runs' spread (2026-10-11, against `1bea5a0`, the
      last build before this task)
- [x] `README.md` says how to use the package, and which entry
      point to call: `serve` everywhere, `serve_epoll` for the fastest loop on Linux
      and macOS
- [x] Tagged `v0.1.0`, the ref the README's example imports (2026-10-11)
