# goose-http

HTTP/1.1 server package for [Goose](https://github.com/aardappel/goose). One event loop
per worker: io_uring or epoll on Linux, kqueue on macOS, I/O completion ports on Windows.

Parsing, routing, and responses are Goose. C only for what Goose can't reach, in `shim/`
([below](#what-isnt-goose-and-why)). Compiler and stdlib gaps go to
[docs/goose-findings.md](docs/goose-findings.md), not into patches (2026-10-10).

Early work. No TLS yet.

## Status

🟢 works · 🟡 partial or next · 🔴 not yet

| | Protocol | Notes |
|---|---|---|
| 🟢 | HTTP/1.1 | Keep-alive, pipelining, chunked. HTTP/1.0 too. |
| 🔴 | HTTP/2 | Later. |
| 🔴 | TLS | Later, likely as a separate package. |
| 🟡 | Compression | Precompressed `.br`, `.zst`, and `.gz` files. On the fly next: gzip, deflate, and zstd, with [goose-compress](https://github.com/kaitk/goose-compress), pure-Goose encoders for all three (task 022). |
| 🔴 | WebSocket | Out of scope for now. `Upgrade` hands the connection to the program. |
| 🔴 | HTTP/3 | Out of scope for now. |

| | Platform | Notes |
|---|---|---|
| 🟢 | Linux | io_uring (kernel 6.1+) or epoll. |
| 🟢 | macOS | kqueue. |
| 🟢 | Windows | IOCP. 2 to 2.7 times slower than io_uring on WSL2 on the same machine, with oha on plaintext (task 017, 2026-10-12); not benchmarked further. |

The tag `v0.2.0` (2026-10-12) has everything in the table below, on both loops on
Linux, kqueue on macOS, and IOCP on Windows. `v0.1.0` had fixed-size requests and
responses only.

| | Feature |
|---|---|
| 🟢 | Strict parser: smuggling, 414, 431, 505, 501 |
| 🟢 | Header fields, path, query, percent-decoding |
| 🟢 | Router: parameters, wildcards, 405 with `Allow`, `OPTIONS` |
| 🟢 | Request bodies of any size, in pieces. `Expect: 100-continue`. Trailers. |
| 🟢 | Responses of any size, streamed or chunked. Trailers. |
| 🟢 | Conditional `GET` (304), one byte range (206, 416) |
| 🟢 | Static files: under 64 KB copied, larger ones sent without copying on every loop |
| 🟢 | CR, LF, and invalid names kept out of response fields |
| 🟢 | Cookies, `Authorization` with `Basic`, media types, `Accept` (415, 406) |
| 🟢 | Form and streamed multipart bodies, JSON responses |
| 🟢 | Limits and timeouts, per connection and per route. Graceful shutdown. |
| 🟢 | Answers that wait: another thread, a timer, long polling, SSE |
| 🟢 | Client address. `Forwarded` from trusted proxies. |
| 🟢 | IPv6 and dual-stack. Unix sockets on Linux and macOS. |
| 🟢 | Access log, as a `DONE` event |

CORS, sessions, middleware, and an HTTP client are out of scope. They belong to a
framework.

## Quick start

```goose
import http from "github.com/kaitk/goose-http@v0.2.0";

thread_fn worker(cfg: http::Config) {
    let e = http::serve(cfg) { req, body, out =>
        if http::path_of(req.target) == "/" {
            http::respond(out, 200, "text/plain", "Hello, World!");
        } else {
            http::respond(out, 404, "text/plain", "");
        }
    };
    http::report(e);
}

fn main() {
    let cfg = http::Config { port: 8080, .. };
    var ids: i64[>..] = [];
    for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
    for id in ids { thread_wait(id); }
}
```

```sh
goose build hello.goose
```

The first build fetches the package into `~/.goose` and compiles the shim. Linux needs
liburing (`liburing-dev`), Windows the Visual Studio Build Tools. Setup:
[docs/development.md](docs/development.md).

## Concepts

- **Workers.** The program spawns a thread per worker, and each runs a loop with the
  same handler. Each worker has its own connections, and on Linux its own listener.
  `thread_spawn` can't take a `thread_fn` passed to a package function
  ([findings](docs/goose-findings.md#thread_spawn-doesnt-take-a-function-value-bound-to-a-thread_fn)),
  so the spawning stays in the program. `goose hello.goose` runs in the compiler, which
  can't reach `thread_spawn`: call `http::serve` from `main` there, for one worker.
- **Two loops.** `http::serve` is io_uring on Linux, a ring emulated on kqueue on macOS,
  and IOCP on Windows; `http::serve_epoll` is epoll or kqueue. A program calls one, and
  only that one is compiled in.
- **A handler for whole requests**, `{ req, body, out => }`: the parsed head, the body
  if it fits in the read buffer, and one response of any size.
- **A handler with state**, `{ ev, st, out => }`, for everything else: the loop calls it
  for each event of an exchange (the head, each piece of a body, room to send more, a
  message from another thread, a time limit), with state of the program's own type kept
  per connection. Bodies and responses of any size, files, upgrades, and answers that
  wait all go through it.
- **The request is borrowed.** The head, its fields, and route parameters are slices
  into the read buffer, valid until the handler returns; the router allocates nothing.
- **`http::Config`** holds the address, limits, timeouts, and buffer sizes, all with
  defaults. `http::stop()` or `http::stop_on_signals()` ends the loops gracefully.

The API by topic, with the examples that show it: [examples/](examples/README.md).

## Benchmarks

All tables, spreads, and losses: [docs/results.md](docs/results.md).

### Plaintext and JSON

Tiny fixed responses. They measure the loop and the parser, nothing else. A real program
spends its time elsewhere.

Ryzen 7 5800X3D, WSL2, kernel 6.18. `bench/run.sh`, 2026-10-12. 4 workers on CPUs 0-3,
wrk on 4-15. Plaintext pipelined 16 deep, by connection count. Median of 3 runs of 15 s.
Goose at `73dd28c`, Goose compiler `6448f3f`. Some competitors' cells come from earlier
sessions with the same binaries, and sessions drift by up to 5%. Bold is the column's
best. Rows go by each server's average rank over the columns, peak RSS by its highest.

| Server | plaintext 256 | plaintext 1,024 | plaintext 4,096 | JSON 256 | JSON 1,024 | peak RSS |
|---|---:|---:|---:|---:|---:|---:|
| libreactorng (C)\* | 6.96 M | 7.38 M | 7.03 M | 545 K | 609 K | 6.1-80 MB |
| **Goose io_uring** | 6.74 M | 6.52 M | 6.02 M | 498 K | 487 K | 8.9-15 MB |
| vanilla-io_uring (V)\* | **8.14 M** | **8.25 M** | **7.60 M** | 456 K | 453 K | 37-154 MB |
| zix (Zig) | 5.13 M | 5.44 M | 4.97 M | **552 K** | **614 K** | 6.7-39 MB |
| **Goose epoll** | 5.37 M | 5.31 M | 5.24 M | 416 K | 408 K | **2.7-3.6 MB** |
| zeemo (Zig) | 2.39 M | 2.69 M | 2.21 M | 540 K | 606 K | 6.6-37 MB |
| xitca-web (Rust) | 3.30 M | 3.52 M | 3.21 M | 419 K | 442 K | 25-69 MB |
| vanilla-epoll (V) | 6.10 M | 5.85 M | 5.46 M | (216 K) | (218 K) | 6.0-57 MB, 15 GB in JSON |
| tokio (Rust) | 3.89 M | 3.83 M | 3.65 M | 394 K | 386 K | 12-183 MB |
| may-minihttp (Rust) | 2.39 M | 4.31 M | 3.95 M | 375 K | 364 K | 40-621 MB |
| Tina (Odin) | 0.73 M | 0.74 M | 0.47 M | 504 K | 446 K | 755 MB |
| hyper (Rust) | 2.69 M | 2.67 M | 2.54 M | 303 K | 295 K | 8.0-88 MB |

\* Answers plaintext without parsing the request.  
() vanilla-epoll's JSON is from 2026-10-11: it leaks 6-15 GB a cell.

The 1-worker table, latency, CPU per request, and notes:
[docs/results.md](docs/results.md#the-full-field).

### Large responses and files

One file downloaded over and over, against nginx and Caddy, the usual static file
servers. Same machine, `bench/files.sh`, 2026-10-12, Goose at `fcfd80d`, Goose compiler
`5c83a5a`. Files on tmpfs.
1 worker on CPU 0 or 4 on CPUs 0-3, wrk on 4-15 with 12 threads and 96 connections.
Median of 3 runs of 10 s. Bold is the column's best. Rows go by each server's average
rank over the columns.

| Server | 4 KB, 1 worker | 4 KB, 4 | 64 KB, 1 | 64 KB, 4 | 1 MB, 1 | 1 MB, 4 |
|---|---:|---:|---:|---:|---:|---:|
| **Goose epoll** | 56.0 K/s | 179 K/s | 2.23 GB/s | 7.41 GB/s | **11.6 GB/s** | **31.3 GB/s** |
| **Goose io_uring** | **81.6 K/s** | **219 K/s** | 2.08 GB/s | 6.42 GB/s | 11.0 GB/s | 30.4 GB/s |
| nginx 1.28.3 | 50.2 K/s | 173 K/s | **2.31 GB/s** | **8.15 GB/s** | 9.9 GB/s | 28.5 GB/s |
| Caddy 2.10.2 (Go) | 13.0 K/s | 47 K/s | 0.83 GB/s | 2.99 GB/s | 6.8 GB/s | 20.1 GB/s |

1 MB with 4 workers is wrk's limit, not the servers'. CPU per request, in-memory
responses, and Windows:
[docs/results.md](docs/results.md#static-files).

### REST APIs

Three API workloads and one of uploads, against servers that serve the same routes
without a framework. Responses are computed per request from records loaded at startup,
and checked before each run. Same machine, `bench/rest.sh`, 2026-10-13, Goose at
`23aa531`, Goose compiler `6448f3f`. 4 workers on CPUs 0-3, the load on 4-15. Median of 3 runs of 15 s.

- **A**: HttpArena's `production-stack` API, items of 0.2 KB.
- **B**: a time tracker's hot path, 0.3-13 KB of JSON.
- **C**: a clinic's schedule and records, up to 728 KB.
- **Uploads**: chunked CSVs of 2-8 MB and multipart files up to 1 MB.

"Reads p99" is tier C's reads at a fixed 16K a second while uploads stream in. Bold is
the column's best; rows go by average rank.

| Server | A | B | C | C, templates\* | Uploads | Reads p99 |
|---|---:|---:|---:|---:|---:|---:|
| **Goose io_uring** | **585 K/s** | **268 K/s** | 51.8 K/s | **144 K/s** | **1,152/s** | 7.8-11 ms |
| **Goose epoll** | 456 K/s | 222 K/s | **51.9 K/s** | 140 K/s | 1,147/s | **1.4-2.5 ms** |
| xitca-web (Rust) | 404 K/s | 233 K/s | 37.9 K/s | 110 K/s | 1,029/s | 1.7-13 ms |
| hyper (Rust) | 274 K/s | 150 K/s | 32.0 K/s | 119 K/s | 1,110/s | 18-19 ms |
| tokio (Rust) | 394 K/s | 183 K/s | 31.7 K/s | 101 K/s | 1,047/s | 5.0-7.4 s† |
| may-minihttp (Rust) | 383 K/s | 186 K/s | 32.3 K/s | 100 K/s | ✗ | ✗ |
| Tina (Odin) | 312 K/s | 52.2 K/s‡ | 3.4 K/s‡ | 99.8 K/s | ✗ | ✗ |
| odin-http (Odin) | 210 K/s | 47.4 K/s‡ | 3.4 K/s‡ | 38.3 K/s | 706/s | 12-13 s† |

\* Each record's JSON is prebuilt at startup, with the per-request values spliced in.  
† The server fell behind the fixed rate, so the reads queued.  
‡ Odin's JSON library is the limit here.  
✗ may-minihttp can't read a chunked body, and Tina crashes on some streamed ones.

Memory, in two parts: what the server holds at rest once its records are loaded (idle,
measured apart with the same binaries), plus what serving the benchmark added at its
peak. Every server keeps its records in memory. Bold is the column's lowest total.

| Server | A | B | C | C, templates | Uploads |
|---|---:|---:|---:|---:|---:|
| **Goose io_uring**\* | 28 + 4.4 MB | 88 + 6.8 MB | 125 + 15 MB | 372 + 15 MB | 125 + 80 MB |
| **Goose epoll**\* | 26 + 0.2 MB | 87 + 0.3 MB | 123 + 5.7 MB | 370 + 5.6 MB | 123 + 91 MB |
| xitca-web (Rust) | 24 + 8.1 MB | 48 + 22 MB | 48 + 428 MB | 78 + 427 MB | **48 + 137 MB** |
| hyper (Rust) | 7.5 + 5.5 MB | **17 + 11 MB** | **24 + 13 MB** | **62 + 13 MB** | 24 + 172 MB |
| tokio (Rust) | 6.8 + 9.2 MB | 17 + 13 MB | 23 + 277 MB | 61 + 307 MB | 23 + 454 MB |
| may-minihttp (Rust) | 25 + 20 MB | 57 + 15 MB | 47 + 391 MB | 95 + 395 MB | ✗ |
| Tina (Odin) | 482 + 0.1 MB | 517 + 0.2 MB | 517 + 132 MB | 554 + 119 MB | ✗ |
| odin-http (Odin) | **8.7 + 2.8 MB** | 44 + 39 MB | 44 + 369 MB | 80 + 396 MB | 44 + 1,211 MB |

\* Goose threads share no memory, so each of the 4 workers holds its own copy of the
records, where the others share one. This unusually large size is being fixed. Serving
adds only 0.2-15 MB on A to C.

Fixed-rate CPU, every route's latency, and how each server reads bodies:
[docs/results.md](docs/results.md#rest-apis).

## What isn't Goose, and why

Measuring Goose is the point, so everything that is HTTP is Goose: parsing, routing,
response building, the loops' state machines, the mailbox's messages, the timer table,
and JSON. What isn't Goose is listed here, all of it.

### In the package: C in `shim/`

Thin functions for what Goose can't do, which `http.build` compiles into every program
that imports the package, on each platform its own:

| File | Platform | What it does |
|---|---|---|
| `shim/net.c` | Linux | Sockets, epoll, clocks, file reads, the stop counter, and the loops' waker, an `eventfd` |
| `shim/kqueue.c` | macOS | `shim/net.c`'s functions over kqueue, with the same Linux error codes; the waker is `EVFILT_USER` |
| `shim/net_win.c` | Windows | `shim/net.c`'s functions over Winsock |
| `shim/uring.c` | Linux | The io_uring ring, over liburing |
| `shim/iocp.c` | Windows | The same ring over a completion port, and the waker, a completion packet |
| `shim/ring_epoll.c` | Linux, macOS | The ring emulated over epoll or kqueue, where io_uring is blocked, and always on macOS |
| `shim/mail.c` | all | The mailboxes' bounded queue, and the list of loop wakers that `http::stop` wakes |

Each is C for one of three reasons:

- **Syscalls and kernel structures.** Goose calls C functions, not the kernel, and its
  structs are packed, so they don't match the kernel's own (`struct epoll_event` is 16
  bytes on ARM, 12 in Goose). So `shim/net.c`, `shim/kqueue.c`, and `shim/net_win.c`
  call the kernel and copy its structures into the package's.
- **Memory the kernel uses after a call returns.** A C function may not keep a
  pointer into Goose memory past the call (spec §7.10), but io_uring and IOCP read and
  write buffers while a request is in flight. So each ring owns its buffers in C:
  `shim/uring.c`, `shim/iocp.c`, and `shim/ring_epoll.c`.
- **Atomics, and a wait another thread can end.** Goose threads share no memory and
  have no atomics, and a Goose thread can't end another's wait in the kernel. So
  `shim/mail.c` holds each box's slots and the counts its senders change atomically,
  and each platform's waker ends a loop's wait. The mailbox's design is Tina's
  ([Credits](#credits)). What goes in a message, the addresses, and everything above
  the queue are Goose (`mail.goose`).

`test/test_mail.build` names the same C for `test/test_mail.goose`, which declares the
package by `mail.goose` alone and so gets no sidecar from `http.build`.

### Outside the package

None of this is in a program that imports the package:

- **Competing servers, in `bench/`**, each in its own language, built in release mode
  by `bench/build.sh`: hyper, tokio, may-minihttp, and xitca-web (Rust); vanilla-epoll
  and vanilla-io_uring (V); dusty, zeemo, and zix (Zig); odin-http (Odin); and
  libreactorng (C). `bench/httparena/goose/` is the Dockerfile that builds this
  server for HttpArena.
- **Benchmark tools, in C**: `bench/latency.c` reads h2load's per-request log into
  percentiles, and `bench/wrk-monotonic.c`, preloaded into wrk, gives it the
  monotonic clock where WSL2 steps the wall clock.
- **Scripts.** Shell runs the builds, tests, and benchmarks (`scripts/*.sh`,
  `bench/*.sh`). Python drives the HTTP and echo checks (`scripts/http_client.py`,
  `scripts/echo_client.py`), summarizes benchmark runs (`bench/summarize.py`), and logs
  clock steps (`bench/clockstep.py`). Lua makes wrk pipeline its requests
  (`scripts/pipeline.lua`).

## Credits

The mailboxes take three ideas from [Tina](https://github.com/pmbanugo/tina), a
thread-per-core framework in Odin, and its author's post
[on async/await](https://pmbanugo.me/blog/why-async-await-complect-concurrency):

- Mailboxes bounded at open, whose send says at once that the box is full or the
  address stale, rather than blocking or growing.
- Work sent to a worker's address, not to a shared queue.
- A time limit required on every wait (`http::later`).

## Layout

```text
http.goose     the package's entry: settings, errors, what both loops share
*.goose        other modules, all namespace http: parser and response writers
               (message.goose), loops (uring.goose, epoll.goose), router
               (router.goose), files (file.goose), shim functions (sys.goose, ring.goose),
               and with nothing of HTTP in them, the mailbox (mail.goose), timer table
               (timers.goose), and handles (handle.goose)
http.build     the package's sidecar: each platform's shim
shim/          C for syscalls: sockets, epoll, io_uring, kqueue, IOCP, and mailboxes
server/        the benchmark server, importing the package from "../"
examples/      small servers, and the API by topic (examples/README.md)
test/          unit tests
bench/         competing servers, load scripts, recorded results
scripts/       build and run scripts
docs/          architecture, development setup, results, Goose findings
tasks/         task tracking (tasks/README.md)
```

## Pins

| What | Pin | Why |
|---|---|---|
| Goose compiler | `aardappel/goose` `a6249a4` (`master`, 2026-10-13) | The language and stdlib change often |
| Benchmarked | REST at `23aa531`, plaintext and JSON at `73dd28c`, both with Goose `6448f3f`; files at `fcfd80d` with Goose `5c83a5a` | Benchmarks run in overnight batches, so they lag the pin |

Move the pin in its own commit once the tests pass; benchmarks don't wait for it
([development.md](docs/development.md#move-the-pin)).
