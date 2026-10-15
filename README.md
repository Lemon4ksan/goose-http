# goose-http

An HTTP/1.1 server package for [Goose](https://github.com/aardappel/goose), with one
event loop per worker, inspired by [Tina](https://github.com/pmbanugo/tina): io_uring or
epoll on Linux, kqueue on macOS, and I/O completion ports on Windows.

Experimental: tested and benchmarked, not yet used in production, and the API still
changes between tags.

[Examples and API](examples/README.md) · [Benchmarks](docs/benchmarks.md) ·
[Architecture](docs/architecture/README.md) · [Embedded Linux](docs/embedded.md) ·
[Development](docs/development.md) · [Changelog](CHANGELOG.md)

For a framework on top, with typed routes, extractors, middleware, and routers generated
from OpenAPI, see [goose-rest](https://github.com/kaitk/goose-rest).

## Status

🟢 works · 🟡 planned or partial · 🔴 not planned

| | Protocol | Notes |
|---|---|---|
| 🟢 | HTTP/1.1 | Keep-alive, pipelining, chunked bodies, trailers, `Expect: 100-continue`. HTTP/1.0 too. |
| 🟢 | Compression | Brotli, Zstandard, and gzip files, and gzip, deflate, and Zstandard on the fly, with [goose-compress](https://github.com/kaitk/goose-compress). |
| 🟡 | HTTP/2 | Planned next. |
| 🟡 | TLS | Planned next, likely as a separate package. |
| 🔴 | WebSocket | `Upgrade` hands the connection to the program. |
| 🔴 | HTTP/3 | |

| | Platform | Notes |
|---|---|---|
| 🟢 | Linux | io_uring (kernel 6.1+) or epoll. |
| 🟢 | macOS | kqueue. |
| 🟢 | Windows | I/O completion ports. |
| 🟡 | Embedded Linux | aarch64 cross-builds and passes its tests under emulation, not yet on a board; two Goose bugs keep 32-bit ARM from running ([embedded Linux](docs/embedded.md)). |

## What it provides

The latest tag, `v0.3.1`, provides all of this on every platform above:

- A strict parser (smuggling, 414, 431, 501, 505), with header fields, path, query, and
  percent-decoding; response fields refuse CR, LF, and invalid names.
- A router with parameters, wildcards, `OPTIONS`, and 405 with `Allow`.
- Request bodies and responses of any size, streamed; form and multipart bodies; JSON
  responses.
- Static files with conditional `GET` and one byte range; files over 64 KB are sent
  without copying.
- Cookies, `Basic` authorization, media types, and `Accept` (406, 415).
- Limits and timeouts per connection and per route, graceful shutdown, and an access log.
- Answers that wait: on another thread, a timer, long polling, or SSE.
- The client's address, `Forwarded` from trusted proxies, IPv6, dual-stack, and, on
  Linux and macOS, Unix sockets.

Not here: an HTTP client, and what a framework adds, such as CORS, sessions, and
middleware ([goose-rest](https://github.com/kaitk/goose-rest)).

## Quick start

Install Goose [`v2026.1`](https://github.com/aardappel/goose/releases/tag/v2026.1): unpack
the archive for your platform and put its directory on `PATH`
([Goose's install notes](https://github.com/aardappel/goose#install-a-release)). Building
a program also needs a C compiler and, on Linux, liburing:

- **Linux:** gcc or clang, with `libc6-dev` and `liburing-dev` (Debian, Ubuntu).
- **macOS:** the Xcode command line tools (`xcode-select --install`).
- **Windows:** the Visual Studio 2022 or later Build Tools, with the C++ workload.

Save this as `hello.goose`:

```goose
import http from "github.com/kaitk/goose-http@v0.3.1";

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

Build it and run it, then open <http://localhost:8080/>:

```sh
goose build hello.goose
./hello
```

*Note: `goose hello.goose` runs a program inside the compiler, through TinyCC, which
can't start threads, so a server with workers needs `goose build`.*

Routes, JSON, uploads, files, and answers that wait are in the
[examples](examples/README.md).

## Concepts

- **Workers.** The program spawns a thread per worker, and each runs a loop with the
  same handler. Each worker has its own connections, and on Linux its own listener.
  `thread_spawn` can't take a `thread_fn` passed to a package function, so the
  spawning stays in the program. `goose hello.goose` runs in the compiler, which
  can't reach `thread_spawn`: call `http::serve` from `main` there, for one worker.
- **Two loops.** `http::serve` is io_uring on Linux, a ring emulated on kqueue on macOS,
  and IOCP on Windows; `http::serve_epoll` is epoll or kqueue. A program calls one, and
  only that one is compiled in.
- **A handler for whole requests**, `{ req, body, out => }`: the parsed head, the body
  if it fits in the read buffer, and one response of any size. `http::gather` gives a
  handler with state a longer body whole, up to a limit.
- **A handler with state**, `{ ev, st, out => }`, for everything else: the loop calls it
  for each event of an exchange (the head, each piece of a body, room to send more, a
  message from another thread, a time limit), with state of the program's own type kept
  per connection. Bodies and responses of any size, files, upgrades, and answers that
  wait all go through it.
- **A handler that returns early is a function.** A `return` in a block returns from
  the function the block is written in, past the loop, which then can't answer the
  request or close its connections, and Goose can't refuse it
  ([findings](docs/goose-findings.md#a-function-cant-keep-its-block-from-returning-past-it)).
  Pass such a handler by name, or call it from the block.
- **The request is borrowed.** The head, its fields, and route parameters are slices
  into the read buffer, valid until the handler returns; the router allocates nothing.
- **`http::Config`** holds the address, limits, timeouts, and buffer sizes, all with
  defaults. `http::stop()` or `http::stop_on_signals()` ends the loops gracefully.
- **Errors are `http::Error`**: the call that failed and its code. A loop,
  `http::stop_on_signals()`, and `http::mail_open` return one, `http::report` prints it,
  and `http::exit_on_error(e)` prints it and ends the process unless its code is 0.

The API by topic, with the examples that show it: [examples/](examples/README.md).

## Benchmarks

goose-http `v0.3.1` and Goose `v2026.1` on a Ryzen 7 5800X3D (WSL2), 4 workers per
server. [All results, the method, and the losses](docs/benchmarks.md).

Plaintext and JSON are tiny fixed responses over 256 connections, plaintext pipelined, so
they measure the event loop and the parser and little else. The REST APIs
[below](#rest-apis) are closer to a real program.

| Workload | Goose | Best other | |
|---|---:|---:|---|
| [Plaintext](docs/benchmarks.md#plaintext-and-json) | 6.84M req/s | 8.12M (vanilla-io_uring\*) | Fastest that parses requests |
| [JSON](docs/benchmarks.md#plaintext-and-json) | 512k req/s | 561k (zix) | Third of 8 |
| [Peak RSS](docs/benchmarks.md#plaintext-and-json), plaintext and JSON | 4.8-16 MB | 39 MB (zix) | Lowest |
| 1 MB [static files](docs/benchmarks.md#static-files)\*\* | 31.3 GB/s | 28.5 GB/s (nginx) | Behind only at 64 KB |
| [Compressed JSON](docs/benchmarks.md#compression)\*\* | 66.1k req/s | 62.6k (actix) | Fastest that compresses each response |

\* Answers without parsing the request; so does libreactorng, at 7.02M req/s.  
\*\* An earlier build than `v0.3.1`.

### REST APIs

Three APIs and an upload workload. Every server serves the same routes from the same
records, loaded at startup, and computes each response per request, without a
framework.

- **A** is [HttpArena](https://github.com/MDA2AV/HttpArena)'s `production-stack` API.
- **B** and **C** come from a time tracker and a clinic, with bigger, deeper JSON.
- **Templates** builds each record's JSON once at startup.
- **Reads p99** is C's latency at a fixed rate while uploads run.

| Workload | Goose | xitca-web (Rust) | dusty (Zig)\* |
|---|---:|---:|---:|
| [A](docs/benchmarks.md#tier-a): HttpArena's items, 0.2 KB | **598k req/s** | 407k | 343k |
| [B](docs/benchmarks.md#tier-b): sessions and time entries, 0.3-13 KB | **315k req/s** | 235k | 162k |
| [C](docs/benchmarks.md#tier-c): schedules and records, up to 728 KB | **62.4k req/s** | 38.2k | 24.6k |
| C, templates | **147k req/s** | 113k | 125k |
| [Uploads](docs/benchmarks.md#uploads): CSVs and multipart files, up to 8 MB | **1,128 req/s** | 1,016 | 1,125 |
| Reads p99 beside uploads | **1.8-2.6 ms** | 2.4-4.6 ms | 6.7-42 ms |

\* A framework; its peer is [goose-rest](https://github.com/kaitk/goose-rest).

Goose serves on io_uring, and on epoll for uploads and reads p99. Every server and
both Goose loops: [docs/benchmarks.md](docs/benchmarks.md#rest-apis).

## What isn't Goose

Everything that is HTTP is Goose: parsing, routing, responses, the loops, the mailboxes'
messages, timers, and JSON. The package's only other code is a thin layer of C in
`shim/`, for four things Goose can't do:

- Call the kernel and convert its structures: sockets, epoll, kqueue, and Winsock.
- Own buffers the kernel uses after a call returns: the io_uring and IOCP rings.
- Wait in a way another thread can end, with atomic counts: the mailboxes' queue.
- Hold memory every thread reads: the shared store's blobs.

Each file, and why it is C:
[architecture](docs/architecture/README.md#what-isnt-goose-and-why).

## Credits

The mailboxes take three ideas from [Tina](https://github.com/pmbanugo/tina), a
thread-per-core framework in Odin, and its author's post
[on async/await](https://pmbanugo.me/blog/why-async-await-complect-concurrency):

- Mailboxes bounded at open, whose send says at once that the box is full or the
  address stale, rather than blocking or growing.
- Work sent to a worker's address, not to a shared queue.
- A time limit required on every wait (`http::later`).
