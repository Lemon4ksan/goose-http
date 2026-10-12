# goose-http

An HTTP/1.1 server written in [Goose](https://github.com/aardappel/goose), as a package
that Goose programs import. It runs an event loop per worker on Linux, macOS, and
Windows, and is benchmarked against the fastest Rust, Zig, V, and C servers. It's an
early work in progress.

The repository is a Goose package, not an addition to Goose (2026-10-10). Gaps found in
the compiler or the standard library are recorded in
[docs/goose-findings.md](docs/goose-findings.md), not patched here.

## What it has

| Protocol or platform | Status | Notes |
|---|---|---|
| HTTP/1.1 | Yes | Keep-alive, pipelining, chunked bodies; HTTP/1.0 too |
| HTTP/2 | No | Out of scope for now; task 014 proposes it |
| TLS (HTTPS) | No | Out of scope for now; task 014 proposes a separate `goose-tls` package |
| WebSocket | Partial | `Upgrade` answers 101 and hands the connection to the program, which does the framing |
| HTTP/3 | No | Not planned |
| Compression | No | Task 014 or later |
| Linux | Yes | io_uring (kernel 6.1 or later) or epoll |
| macOS | Yes | kqueue |
| Windows | Yes | I/O completion ports; not a benchmark platform |

Within HTTP/1.1, on `main`. The tag `v0.1.0` serves requests and responses of a fixed
size only.

| Feature | Status |
|---|---|
| Strict parsing: rejects smuggling, oversized heads (414, 431), other major versions (505), unknown transfer codings (501) | Yes |
| Header fields by name and in order, path and query with percent-decoding | Yes |
| Router: method and path patterns, parameters, wildcards, 405 with `Allow`, `OPTIONS` | Yes |
| Request bodies of any size, in pieces; `Expect: 100-continue`; request trailers | Yes |
| Responses of any size, streamed or chunked; response trailers | Yes |
| Conditional `GET` (304), one byte range (206, 416) | Yes |
| Static files, read in 64 KB pieces | Yes |
| Limits and timeouts set by the program; graceful shutdown on `SIGTERM` | Yes |
| `sendfile` for files on the epoll loop | Next (task 013) |
| Large responses on the io_uring loop without the extra copy | Next (task 013) |
| Answers that wait for another thread or a timer (long polling, Server-Sent Events) | Planned (task 015) |
| The client's address, and from `Forwarded` behind trusted proxies | Planned (task 015) |
| IPv6, dual-stack, and Unix sockets | Planned (task 015) |
| Response fields checked for CR and LF | Planned (task 015) |
| Cookies, `Authorization`, media types and `Accept` (415, 406) | Planned (task 015) |
| Form and multipart bodies, JSON responses, a log after each response | Planned (task 015) |
| CORS, sessions, middleware, an HTTP client | No; a framework's job |

## Quick start

Declare the package in your program's root file, and call a loop from a `thread_fn` of
your own, with your handler:

```goose
import http from "github.com/kaitk/goose-http@v0.1.0";

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

`goose build hello.goose` makes an executable. The first build fetches the package into
`~/.goose` and compiles its C shim, which needs liburing (apt `liburing-dev`) on Linux
and the Visual Studio Build Tools on Windows. The rest of the API is in
[Using the package](#using-the-package), and setup in
[docs/development.md](docs/development.md).

## Benchmarks

Every number below names its machine, build, and method; the full tables and the
losses are in [docs/results.md](docs/results.md).

### Plaintext and JSON: fast, and synthetic

TechEmpower's plaintext and JSON tests answer a fixed, tiny response, so they measure
the event loop and the parser and little else. Goose is at or near the top here, which
says little about a real program, whose time goes elsewhere.

On one machine (Ryzen 7 5800X3D, WSL2 kernel 6.18), with `bench/run.sh`'s defaults on
2026-10-11: plaintext pipelined 16 deep and JSON, 1 and 4 workers on CPUs 0-3, wrk on
CPUs 4-15, medians of 3 runs of 15 s per cell. The epoll server at `b6a26c5`, against
the strongest servers of [HttpArena](https://www.http-arena.com/) and TechEmpower that
run on this machine:

| | Goose | vanilla-epoll (V) | tokio (Rust) | may-minihttp (Rust) |
|---|---:|---:|---:|---:|
| plaintext, 256 conns, 4 workers, req/s | 5.47 M | 5.53 M | 3.55 M | 2.39 M |
| plaintext, 4,096 conns, 4 workers, req/s | 5.12 M | 5.06 M | 3.35 M | 3.69 M |
| JSON, 256 conns, 4 workers, req/s | 0.408 M | 0.216 M | 0.377 M | 0.342 M |
| instructions per request (plaintext, 1 worker) | 2,255-2,371 | 1,756-1,765 | 4,330-4,375 | 2,983-3,011 |
| peak RSS, any cell | 2.1-2.6 MB | 5.6-57 MB, 15 GB in JSON | 12-184 MB | 40-639 MB |

Goose leads every JSON cell and four of six plaintext cells. It loses plaintext with 4
workers at 256 and 1,024 connections to vanilla-epoll by 1%, inside both servers' run
spreads; vanilla-epoll answers `GET /plaintext` from its first bytes without parsing
the request. Goose's p99 latency trails the best in six of ten cells, by 0.05-0.53 ms,
and in HttpArena's `limited-conn` profile (a new connection every 10 requests) it runs
2% behind tokio. The streaming handler added since cost 0-3% in these cells (task
013).

### Large responses and files: not compared yet

Sending a 64 KB or 1 MB response, or a file, measures how the loop moves bytes rather
than how it parses. No competitor has been measured on it yet, so these numbers say
how the two loops compare, not where Goose ranks.

On the same machine on 2026-10-12, at `4a65d96` with Goose `5c83a5a`: one worker on
CPU 0, wrk on CPUs 4-15 with 8 threads and 64 connections for 10 s, files from tmpfs, 2
runs each:

| Path | epoll | io_uring |
|---|---:|---:|
| `/files/`, a 64 KB file | 1.90-1.91 GB/s | 1.21-1.22 GB/s |
| `/files/`, a 1 MB file | 3.25-3.30 GB/s | 0.98 GB/s |
| `/bytes?n=1048576`, 1 MB generated | 2.32 GB/s (1 run) | 1.02-1.05 GB/s |

Since then, `shim/uring.c` reuses its large send records, which took the io_uring loop's
`/bytes` to 1.72-1.73 GB/s; its files weren't measured again. The io_uring loop still
copies each piece once more than it needs to, and the epoll loop reads files with
`pread` where `sendfile` would save a copy. Both are task 013's next steps.

### REST and JSON APIs: to be measured

An API spends its time in routing, JSON in both directions, and waiting on other work,
such as a database. Nothing measures that yet; it follows task 015, which adds what an
API needs.

## Using the package

The program spawns its workers itself, because `thread_spawn` can't take a `thread_fn`
a package function was passed
([findings](docs/goose-findings.md#thread_spawn-doesnt-take-a-function-value-bound-to-a-thread_fn)).
`goose hello.goose` runs a program in the compiler, which can't run one that reaches
`thread_spawn`: there, call `http::serve` from `main`, for one worker.

The handler gets:

- `req`, the parsed request head (`http::Request` in `message.goose`): method, target,
  version, keep-alive, the body's announced length, and slices into the read buffer.
  `http::field_of(req, name)` gives a header field's value and whether it's there,
  ignoring the name's case, and `http::each_field(req) { name, value => ... }` goes
  through them all, repeats included. `http::path_of(req.target)` is the path,
  `http::query_of(req.target, key)` a query's value and whether it's there, and
  `http::each_query(req.target) { key, value => ... }` its pairs, all still encoded;
  `http::decode(s, out)` decodes one, with `+` as a space when its `plus` is set. A
  target with a `%` that doesn't start an escape gets 400. Every slice lasts until the
  handler returns.
- `body`, the whole body when it fits in the read buffer with its head, chunked bodies
  decoded. A longer body is dropped as it arrives, and `body` is empty.
- `out`, an `http::Reply`, to write one whole response of any size into:
  `http::respond(out, status, content_type, body)`, or `http::start(out, status)`,
  `http::field(out, name, value)`, and `http::finish(out, fields, body)`. Clearing
  `out.keep_alive` before `start` closes the connection after the response.

A handler passed by name, `http::serve(cfg, route)`, is best an `inline fn`, as the
benchmark server's is (`server/routes.goose`): both loops call it, and as a call it
keeps `http::start` from folding a constant status, which cost the benchmark server
about 190 instructions per request.

`http::Config` holds the address, port, worker count, limits, timeouts, and buffer
sizes, with defaults. A loop returns when a call fails, with an `http::Error` that
`http::report` writes to stderr, or after `http::stop()`, with an error whose code is
0. A stopped loop closes its listener and idle connections, answers the next request
on each other connection with `Connection: close`, and returns once they have closed,
or after `Config.grace_ms`; `http::stop_on_signals()` makes `SIGTERM` and `SIGINT`
stop the loops (on `main`, after 0.1).

### Routes

`http::router(req)` routes a request through an `if` chain, with method and path
patterns: a literal segment, `:name` for one segment, and `*name` last for the rest
of the path. A `GET` route takes `HEAD` too, and a request no route takes gets 405
with the `Allow` of the routes whose path matched, 204 with it for `OPTIONS`, or 404:

```goose
var r = http::router(req);
if http::on(r, "GET", "/users/:id") { show(http::param(r, "id"), out); }
else if http::on(r, "PUT", "/users/:id") { update(http::param(r, "id"), body, out); }
else if http::on(r, "GET", "/files/*path") { file(http::param(r, "path"), out); }
else { http::otherwise(r, out); }
```

Parameters are slices of the target, still percent-encoded, and last until the handler
returns; nothing allocates.

### Conditional requests and ranges

`http::not_modified(req, etag, modified)` says whether a `GET` gets 304, from
`If-None-Match` against an entity tag, or else `If-Modified-Since` against a time.
`http::range_of(req, size, etag)` gives the one byte range `Range` asks for, with 206,
416, or 200 for the whole (as when `If-Range` names another entity tag), and
`http::content_range(out, start, end, size)` writes its field. `http::end(out,
trailers)` ends a chunked response with trailer fields, and a chunked request's come in
`ev.trailers`, at `END` or with a whole body, where `http::field_in(ev.trailers, name)`
finds one.

### Bodies and responses of any size

On `main`, after 0.1, each loop also takes a handler that it calls again for each part
of an exchange, with state of the program's own type, which starts each request as
`fresh` and lives in the connection's slot:

```goose
struct Upload { bytes: i64 = 0 }

thread_fn worker(cfg: http::Config) {
    let e = http::serve(cfg, Upload { .. }) { ev, st, out =>
        if ev.kind == http::REQUEST && !ev.whole {
            // The body comes in BODY pieces; answer at END.
        } else if ev.kind == http::REQUEST || ev.kind == http::END {
            st.bytes += ev.data.len;
            var text: u8[..24] = [];
            format(text, st.bytes);
            http::respond(out, 200, "text/plain", text);
        } else if ev.kind == http::BODY {
            st.bytes += ev.data.len;
        }
    };
    http::report(e);
}
```

- `REQUEST` comes with `ev.req`, and with the body in `ev.data` when `ev.whole` is set,
  as a body that fits in the read buffer with its head always is. A longer body comes
  in `BODY` pieces, decoded if chunked, up to `Config.max_body`, and then `END`.
- A response is whole, as above, or begun with `http::begin(out, status, length)`, with
  a `Content-Length`, or chunked for a `length` of -1 (HTTP/1.0 then closes at its end).
  `http::send(out, bytes)` writes each piece, and `http::end(out)` ends it. While it's
  open and the body has ended, the loop calls the handler with `MORE` each time the
  connection has room to send, so a response of any size never sits whole in memory.
- A response that comes before the body has all arrived drops the rest, up to
  `Config.max_drain`, past which the connection closes. A client that sends `Expect:
  100-continue` gets `100 Continue` unless the handler answers at `REQUEST`.
- `http::upgrade_of(req)` is the protocol a request asks to switch to, such as
  `websocket`, and `http::upgrade(out, protocol)` answers 101 and switches: every byte
  after the request comes as `BODY`, and `http::send` writes bytes as they are, until
  `http::end` closes the connection. The protocol itself, WebSocket's framing for one,
  is the program's.
- When a connection closes while the handler is still owed a call, a response open or a
  body unread, the handler gets `CLOSED`, to release what its state holds.

### Files

`http::open_file(path)` opens a regular file, with 404 or 403 when it can't.
`http::serve_file(req, out, f, http::content_type_of(path), st.file)` answers a `GET`
or `HEAD` for it with 200, 206 for a range, 304, or 416, with `ETag`, `Last-Modified`,
and `Accept-Ranges`; the handler then calls `http::send_file(out, st.file)` at each
`MORE` until it returns false, and `http::end(out)`. Each call reads up to 64 KB with
`pread`, so a file of any size goes out in pieces on every loop, and
`http::close_body(st.file)` at `CLOSED` closes a file whose client left.
`http::is_safe_path(path)` rejects a decoded path with a `.` or `..` segment, a
backslash, or a colon, before it's joined to a directory. The benchmark server serves
the directory `FILES` names at `/files/`.

### Event loops

The package has two loops, and a program picks one by calling it. Goose compiles a
generic function only where it's called, so the other isn't in the program:

- `http::serve`, the loop to call everywhere: over io_uring on Linux, 9% to 24% faster
  than the epoll loop in task 011's recheck of task 005's matrix, at 4 to 5 times its
  peak RSS (about 10 MB with 4 workers). It needs Linux 6.1, and where
  `io_uring_setup` fails, as under Docker's default seccomp profile, it runs over an
  emulation of the ring on epoll; `http::ring_probe()` says why. On Windows it's over
  I/O completion ports, and on macOS over the same emulation on kqueue.
- `http::serve_epoll`, over epoll on Linux and kqueue on macOS, and failing with
  `ENOSYS` on Windows: the faster loop on macOS, and on Linux the one with a quarter of
  the memory. The plaintext and JSON results above measure it.

The benchmark server in `server/` links both, and `LOOP` picks one: `uring` (`iocp` on
Windows), `epoll`, or `uring-epoll`, the io_uring loop over its emulation. Both stay
tested ([architecture](docs/architecture/README.md#the-io_uring-loop-task-005)).

## Layout

```text
http.goose     the package's entry: the settings, the errors, and what both loops share
*.goose        its other modules, all namespace http: the parser and the response
               writers (message.goose), the loops (uring.goose, epoll.goose), the
               router (router.goose), files (file.goose), and the shim's functions
               (sys.goose, ring.goose)
http.build     the package's sidecar: each platform's shim
shim/          the C the package calls, linked by goose build: sockets, epoll, io_uring,
               and kqueue (macOS) and IOCP (Windows) in their place
server/        the benchmark server, a program that imports the package from "../"
test/          the package's unit tests
bench/         the competing servers, the load scripts, and the recorded results
scripts/       build and run scripts
docs/          architecture, development setup, results, and the Goose findings log
tasks/         task tracking (tasks/README.md)
```

## Pins

| What | Pin | Why |
|---|---|---|
| Goose compiler | `aardappel/goose` `5c83a5a` (`master`, 2026-10-12) | The language and stdlib change often |

Move the pin in its own commit, with the build and benchmark results that still hold.
