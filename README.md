# goose-http

HTTP/1.1 server package for [Goose](https://github.com/aardappel/goose). One event loop
per worker: io_uring or epoll on Linux, kqueue on macOS, I/O completion ports on Windows.

Parsing, routing, and responses are Goose. C only for syscalls, in `shim/`. Compiler and
stdlib gaps go to [docs/goose-findings.md](docs/goose-findings.md), not into patches
(2026-10-10).

Early work. No TLS yet.

## Status

🟢 works · 🟡 partial or next · 🔴 not yet

| | Protocol | Notes |
|---|---|---|
| 🟢 | HTTP/1.1 | Keep-alive, pipelining, chunked. HTTP/1.0 too. |
| 🔴 | HTTP/2 | Later. |
| 🔴 | TLS | Later, likely as a separate package. |
| 🔴 | Compression | Later. |
| 🔴 | WebSocket | Out of scope for now. `Upgrade` hands the connection to the program. |
| 🔴 | HTTP/3 | Out of scope for now. |

| | Platform | Notes |
|---|---|---|
| 🟢 | Linux | io_uring (kernel 6.1+) or epoll. |
| 🟢 | macOS | kqueue. |
| 🟢 | Windows | IOCP. About 2 to 2.5 times slower than io_uring on WSL2 on the same machine, in [a speed check](docs/development.md#after-the-iocp-changes); not benchmarked. |

HTTP/1.1 on `main`. The tag `v0.1.0` has fixed-size requests and responses only.

| | Feature | When |
|---|---|---|
| 🟢 | Strict parser: smuggling, 414, 431, 505, 501 | |
| 🟢 | Header fields, path, query, percent-decoding | |
| 🟢 | Router: parameters, wildcards, 405 with `Allow`, `OPTIONS` | |
| 🟢 | Request bodies of any size, in pieces. `Expect: 100-continue`. Trailers. | |
| 🟢 | Responses of any size, streamed or chunked. Trailers. | |
| 🟢 | Conditional `GET` (304), one byte range (206, 416) | |
| 🟢 | Static files | |
| 🟢 | CR, LF, and invalid names kept out of response fields | |
| 🟢 | Cookies, `Authorization` with `Basic`, media types, `Accept` (415, 406) | |
| 🟢 | Form and streamed multipart bodies, JSON responses | |
| 🟢 | Limits and timeouts, per connection and per route. Graceful shutdown. | |
| 🟡 | `sendfile` on the epoll loop | Very soon |
| 🟡 | Large responses on io_uring without the extra copy | Very soon |
| 🔴 | Answers that wait: another thread, a timer, long polling, SSE | Soon |
| 🔴 | Client address. `Forwarded` from trusted proxies. | Soon |
| 🔴 | IPv6, dual-stack, Unix sockets | Soon |
| 🔴 | Access log | Soon, after the client address |

CORS, sessions, middleware, and an HTTP client are out of scope. They belong to a
framework.

## Quick start

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

```sh
goose build hello.goose
```

The first build fetches the package into `~/.goose` and compiles the shim. Linux needs
liburing (`liburing-dev`), Windows the Visual Studio Build Tools. Setup:
[docs/development.md](docs/development.md).

## Benchmarks

All tables, spreads, and losses: [docs/results.md](docs/results.md).

### Plaintext and JSON

Tiny fixed responses. They measure the loop and the parser, nothing else. Goose is at
the top here. A real program spends its time elsewhere.

Ryzen 7 5800X3D, WSL2, kernel 6.18. `bench/run.sh` defaults, 2026-10-12. Servers on
CPUs 0-3, wrk on 4-15. Plaintext pipelined 16 deep. Median of 3 runs of 15 s. Goose at
`ef09c0f`, Goose compiler `5c83a5a`, both loops.

| | Goose io_uring | Goose epoll | vanilla-epoll (V) | tokio (Rust) | may-minihttp (Rust) |
|---|---:|---:|---:|---:|---:|
| plaintext, 256 conns, 4 workers, req/s | 7.06 M | 5.83 M | 6.10 M | 3.89 M | 2.39 M |
| plaintext, 4,096 conns, 4 workers, req/s | 6.45 M | 5.53 M | 5.46 M | 3.65 M | 3.95 M |
| JSON, 256 conns, 4 workers, req/s | 0.513 M | 0.430 M | 0.216 M | 0.394 M | 0.375 M |
| instructions per request (plaintext, 1 worker) | 2,503-2,517 | 2,418-2,469 | 1,750-1,758 | 4,369-4,399 | 2,999-3,023 |
| peak RSS, any cell | 4.6-16 MB | 2.4-3.2 MB | 5.6-57 MB, 6-15 GB in JSON | 12-183 MB | 39-621 MB |

- The io_uring loop wins every cell, plaintext and JSON.
- The epoll loop wins every JSON cell, and is within vanilla-epoll's run spread in 5 of
  6 plaintext cells. It loses plaintext with 4 workers at 256 connections, by 5%.
  vanilla-epoll answers without parsing the request.
- The epoll loop's p99 latency trails a competitor's in 4 of 10 cells, by 0.01-2.2 ms.
- HttpArena's `limited-conn` profile: 2% behind tokio.
- The streaming handler costs nothing measurable in these cells since 2026-10-12.

### Large responses and files

No competitor measured yet. This compares the two loops only.

Same machine, 2026-10-12, `4a65d96`, Goose `5c83a5a`. One worker on CPU 0, wrk on
4-15, 8 threads, 64 connections, 10 s, files on tmpfs, 2 runs.

| Path | epoll | io_uring |
|---|---:|---:|
| `/files/`, 64 KB file | 1.90-1.91 GB/s | 1.21-1.22 GB/s |
| `/files/`, 1 MB file | 3.25-3.30 GB/s | 0.98 GB/s |
| `/bytes?n=1048576` | 2.32 GB/s (1 run) | 1.02-1.05 GB/s |

Since then the io_uring shim reuses large send records: `/bytes` at 1.72-1.73 GB/s.
Files not measured again. Very soon: no extra copy on io_uring, `sendfile` on
epoll.

### REST APIs

Not measured yet. The helpers are in, under [Helpers for APIs](#helpers-for-apis); a
REST benchmark is next.

## API

### Handler

- **`req`**: the parsed head, `http::Request`. Slices into the read buffer, valid until
  the handler returns.
  - `http::field_of(req, name)`: a field's value, and whether it's there. Name is
    case-insensitive.
  - `http::each_field(req) { name, value => }`: all fields, repeats included.
  - `http::path_of(req.target)`, `http::query_of(req.target, key)`,
    `http::each_query(req.target) { key, value => }`: still percent-encoded.
  - `http::decode(s, out)`: decodes one. With `plus` set, `+` is a space.
  - A target with a bad `%` escape gets 400.
- **`body`**: the whole body, if it fits in the read buffer with the head. Chunked is
  decoded. A longer body is dropped and `body` is empty; see
  [Streaming](#streaming).
- **`out`**: an `http::Reply`. One whole response, any size.
  - `http::respond(out, status, content_type, body)`, or
  - `http::start(out, status)`, `http::field(out, name, value)`,
    `http::finish(out, fields, body)`.
  - `http::field` drops a field with CR, LF, or an invalid name, so request data can't
    split the response; `http::is_field(name, value)` checks one first. `finish`'s
    `fields` are written as they are, for constant text.
  - Clear `out.keep_alive` before `start` to close after the response.

A handler passed by name, `http::serve(cfg, route)`, should be an `inline fn`, as in
`server/routes.goose`. As a call, it keeps `http::start` from folding a constant status:
about 190 instructions per request in the benchmark server.

The program spawns its own workers. `thread_spawn` can't take a `thread_fn` passed to a
package function
([findings](docs/goose-findings.md#thread_spawn-doesnt-take-a-function-value-bound-to-a-thread_fn)).
`goose hello.goose` runs in the compiler, which can't reach `thread_spawn`: call
`http::serve` from `main` there, for one worker.

### Config and shutdown

`http::Config`: address, port, workers, limits, timeouts, buffer sizes. All have
defaults.

A loop returns:

- when a call fails, with an `http::Error`. `http::report` prints it to stderr.
- after `http::stop()`, with error code 0. The listener and idle connections close.
  Each other connection gets `Connection: close` on its next response. The loop returns
  when they close, or after `Config.grace_ms`.

`http::stop_on_signals()` makes `SIGTERM` and `SIGINT` stop the loops.

### Routes

```goose
var r = http::router(req);
if http::on(r, "GET", "/users/:id") { show(http::param(r, "id"), out); }
else if http::on(r, "PUT", "/users/:id") { update(http::param(r, "id"), body, out); }
else if http::on(r, "GET", "/files/*path") { file(http::param(r, "path"), out); }
else { http::otherwise(r, out); }
```

- `:name` matches one segment, `*name` the rest of the path, last only.
- A `GET` route takes `HEAD` too.
- `http::otherwise`: 405 with `Allow` from the routes whose path matched, 204 with it
  for `OPTIONS`, else 404.
- Parameters are slices of the target, still encoded, valid until the handler returns.
  Nothing allocates.

### Conditional requests and ranges

- `http::not_modified(req, etag, modified)`: whether a `GET` gets 304. `If-None-Match`
  first, else `If-Modified-Since`.
- `http::range_of(req, size, etag)`: the one byte range asked for, with 206, 416, or
  200 for the whole (for example when `If-Range` names another entity tag).
- `http::content_range(out, start, end, size)`: writes `Content-Range`.

### Streaming

Each loop also takes a handler it calls again for each part of an exchange. `st` is
state of the program's own type, reset to `fresh` per request, kept in the connection's
slot.

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

| Event | When |
|---|---|
| `REQUEST` | Head parsed, in `ev.req`. With `ev.whole`, the body is in `ev.data`, as it always is when it fits in the read buffer with the head. |
| `BODY` | A piece of a longer body, decoded if chunked, up to `Config.max_body`. |
| `END` | The body is complete. Request trailers are in `ev.trailers`, here or at a whole body's `REQUEST`; `http::field_in` finds one. |
| `MORE` | A response is open, the body has ended, and the connection has room to send. |
| `CLOSED` | The connection closed while the handler was owed a call. Release what `st` holds. |

- `http::begin(out, status, length)` opens a response: `Content-Length`, or chunked
  for -1. HTTP/1.0 then closes at the end.
- `http::send(out, bytes)` writes a piece. `http::end(out)` ends it;
  `http::end(out, trailers)` adds trailer fields to a chunked one.
- A response before the body has arrived drops the rest, up to `Config.max_drain`,
  then closes.
- `Expect: 100-continue` gets `100 Continue` unless the handler answers at `REQUEST`.
- `http::upgrade_of(req)`: the protocol asked for, such as `websocket`.
  `http::upgrade(out, protocol)` answers 101. After that, bytes come as `BODY`,
  `http::send` writes them raw, and `http::end` closes.

### Files

- `http::open_file(path)`: opens a regular file, or 404 or 403.
- `http::serve_file(req, out, f, http::content_type_of(path), st.file)`: answers `GET`
  or `HEAD` with 200, 206, 304, or 416, with `ETag`, `Last-Modified`, and
  `Accept-Ranges`.
- `http::send_file(out, st.file)` at each `MORE` until false, then `http::end(out)`.
  Reads up to 64 KB with `pread` per call.
- `http::close_body(st.file)` at `CLOSED`.
- `http::is_safe_path(path)`: rejects `.` and `..` segments, backslashes, and colons.
  Check the decoded path before joining it to a directory.

The benchmark server serves the directory in `FILES` at `/files/`.

### Helpers for APIs

- Media types: `http::require_type(req, out, "application/json")` answers 415 for
  another `Content-Type`; `http::accept_or_406(req, out, ["application/json",
  "text/csv"])` picks an offer by `Accept`, or answers 406. `http::media_type` and
  `http::param_of` parse a type and its parameters.
- Cookies: `http::cookie_of(req, name)`, `http::each_cookie(req) { name, value => }`,
  and `http::set_cookie(out, http::Cookie { name: "sid", value: id, max_age: 3600,
  http_only: true, same_site: "Lax", .. })`.
- `http::authorization(req)`: the scheme and credentials. `http::basic_auth(req,
  decoded)`: the user and password. `http::challenge(out, "Basic realm=\"api\"")`:
  401.
- Forms: `http::form_value(body, key, out)` and `http::each_form(body) { key, value =>
  }`. Multipart: `http::start_multipart(req, st.parts)` at `REQUEST`, then
  `http::each_part(st.parts, ev.data) { kind, data => }` for each piece of the body, with
  `http::disposition` for a part's name and filename.
- `http::respond_json(out, status) { b => json::format_key(b, "id"); ... }`.
- `Config.max_requests` caps a connection's requests. `http::body_within(st.taken, ev,
  out, limit)` at `REQUEST` and each `BODY` answers 413 past a route's own limit.

### Event loops

The program calls one. Goose compiles a generic function only where it's called, so the
other isn't in the binary.

| Loop | Linux | macOS | Windows |
|---|---|---|---|
| `http::serve` | io_uring, kernel 6.1+ | ring emulated on kqueue | IOCP |
| `http::serve_epoll` | epoll | kqueue | `ENOSYS` |

- `http::serve` is the default. On Linux 12-22% faster than epoll, at 2-5 times the
  peak RSS, 10-16 MB with 4 workers. Where
  `io_uring_setup` fails, as under Docker's default seccomp profile, it emulates the
  ring on epoll; `http::ring_probe()` says why.
- `http::serve_epoll` is faster on macOS, and on Linux uses a quarter of the memory.
  The plaintext and JSON numbers above are this loop.

The benchmark server links both. `LOOP` picks: `uring` (`iocp` on Windows), `epoll`,
or `uring-epoll`. See [architecture](docs/architecture/README.md#the-io_uring-loop-task-005).

## Layout

```text
http.goose     the package's entry: settings, errors, what both loops share
*.goose        other modules, all namespace http: parser and response writers
               (message.goose), loops (uring.goose, epoll.goose), router
               (router.goose), files (file.goose), shim functions (sys.goose, ring.goose)
http.build     the package's sidecar: each platform's shim
shim/          C for syscalls: sockets, epoll, io_uring, kqueue, IOCP
server/        the benchmark server, importing the package from "../"
test/          unit tests
bench/         competing servers, load scripts, recorded results
scripts/       build and run scripts
docs/          architecture, development setup, results, Goose findings
tasks/         task tracking (tasks/README.md)
```

## Pins

| What | Pin | Why |
|---|---|---|
| Goose compiler | `aardappel/goose` `5c83a5a` (`master`, 2026-10-12) | The language and stdlib change often |

Move the pin in its own commit, with the build and benchmark results that still hold.
