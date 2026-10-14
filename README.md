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
| 🟢 | Compression | Precompressed `.br`, `.zst`, and `.gz` files, and gzip, deflate, and zstd on the fly by `Accept-Encoding`, whole or streamed, with [goose-compress](https://github.com/kaitk/goose-compress)'s pure-Goose encoders, in the module `http.compression` (task 022). |
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
  The program writes the spawn loop: `thread_spawn` takes a `thread_fn` passed to a
  package function only since Goose `0073357`, and the package doesn't use that yet. `goose hello.goose` runs in the compiler, which
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

Ryzen 7 5800X3D, WSL2, 4 workers against the same worker count, Goose at `e4f7b55` with
compiler `0bdbd18` (2026-10-14) unless a row says otherwise. Every table, the method,
and every loss: [docs/benchmarks.md](docs/benchmarks.md).

| Workload | Goose | Best other | Where Goose stands |
|---|---:|---:|---|
| Plaintext, pipelined, 256 connections | 6.90 M/s | vanilla-io_uring 8.12 M/s\* | Fastest of the servers that parse the request |
| JSON, 1,024 connections | 489 K/s | zix 614 K/s | Third of 8 |
| REST tiers A / B / C ([below](#rest-apis)) | 588 K / 278 K / 52.3 K/s | xitca-web 407 K / 235 K / 38.2 K/s | Fastest on every tier |
| Static files, 1 MB (2026-10-12) | 31.3 GB/s | nginx 28.5 GB/s | On a par with nginx: ahead at 4 KB and 1 MB, behind at 64 KB |
| Compressed JSON, json-comp (`6f584e2`) | 66.1 K/s | actix 62.6 K/s | Fastest of the servers that compress each response |
| Peak RSS, plaintext and JSON | 4.8-13 MB | zix 39 MB | Lowest |

\* Answers without parsing the request.

### REST APIs

The workloads closest to a real program: three APIs and uploads, against servers that
serve the same routes without a framework. Each server loads its records at startup,
computes every response per request, and passes a checker before each run.

- **A**: HttpArena's `production-stack` API, items of 0.2 KB.
- **B**: a time tracker's hot path, 0.3-13 KB of JSON, with a session cookie.
- **C**: a clinic's schedule and records, responses up to 728 KB.
- **Uploads**: chunked CSVs of 2-8 MB and multipart files up to 1 MB.

"Templates" prebuilds each record's JSON at startup and splices in the per-request
values. "Reads p99" is tier C's reads at a fixed 16,000 a second while uploads stream
in. 4 workers, 3 runs of 15 s, medians; bold is the column's best.

| Server | A | B | C | C, templates | Uploads | Reads p99 |
|---|---:|---:|---:|---:|---:|---:|
| **Goose io_uring** | **588 K/s** | **278 K/s** | **52.3 K/s** | **142 K/s** | 1,154/s | 7.8-10.6 ms |
| **Goose epoll** | 448 K/s | 222 K/s | 51.3 K/s | 136 K/s | **1,166/s** | **1.0-2.0 ms** |
| xitca-web (Rust) | 407 K/s | 235 K/s | 38.2 K/s | 113 K/s | 1,016/s | 2.4-4.6 ms |
| dusty (Zig)\* | 343 K/s | 162 K/s | 24.6 K/s | 125 K/s | 1,125/s | 6.7-42 ms |
| hyper (Rust) | 271 K/s | 151 K/s | 32.1 K/s | 120 K/s | 1,107/s | 11-29 ms |
| tokio (Rust) | 393 K/s | 183 K/s | 31.6 K/s | 100 K/s | 1,034/s | 1.1-5.8 s† |

\* A framework: its peer is goose-rest, the framework planned on this package.  
† Fell behind the fixed rate, so the reads queued.

**Memory grows with workers.** Goose threads share no memory, so each worker holds its
own copy of the records, where hyper's threads share one. With one worker Goose holds
less than hyper on every tier; each added worker adds a copy. Idle, records loaded:

| Tier | Goose, 1 worker | Goose, 4 workers | Each added worker | hyper, 4 workers |
|---|---:|---:|---:|---:|
| A | 4.5 MB | 8.9 MB | +1.5 MB | 7.5 MB |
| B | 11 MB | 36 MB | +8.2 MB | 17 MB |
| C | 23 MB | 84 MB | +20 MB | 24 MB |
| C, templates | 38 MB | 143 MB | +35 MB | 62 MB |

Serving adds little on top: Goose's peak RSS at saturation is 15, 47, 104, and 177 MB
on these four, where tokio's reaches 365 MB and xitca-web's 512 MB on tier C. Task 025
cuts the per-worker copy: idle tier C templated went from 379 MB to 143 so far. Goose
idle on the epoll loop at `9408035` (2026-10-14); hyper idle on 2026-10-13, which stays
flat with workers: 23 MB on tier C at 1, 2, and 4.

Every table, tier D beside forms, and the losses:
[docs/benchmarks.md](docs/benchmarks.md#rest-apis).

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
| Goose compiler | `aardappel/goose` `46356c2` (`master`, 2026-10-13) | The language and stdlib change often |
| Benchmarked | Per workload in [docs/benchmarks.md](docs/benchmarks.md#pins): plaintext, JSON, and REST at `e4f7b55` with Goose `0bdbd18` | Benchmarks run in overnight batches, so they lag the pin |

Move the pin in its own commit once the tests pass; benchmarks don't wait for it
([development.md](docs/development.md#move-the-pin)).
