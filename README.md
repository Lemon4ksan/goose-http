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
| 🟡 | Compression | Precompressed `.br`, `.zst`, and `.gz` files. gzip on the fly next (task 022). |
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

More in [examples/](examples/README.md): the router, JSON, and a handler written in C.

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

One file downloaded over and over, against nginx and Caddy, the usual static file
servers. Same machine, `bench/files.sh`, 2026-10-12, Goose at `fcfd80d`. Files on tmpfs.
1 worker on CPU 0 or 4 on CPUs 0-3, wrk on 4-15 with 12 threads and 96 connections.
Median of 3 runs of 10 s. Bold is the column's best.

| Server | 4 KB, 1 worker | 4 KB, 4 | 64 KB, 1 | 64 KB, 4 | 1 MB, 1 | 1 MB, 4 |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | **81.6 K/s** | **219 K/s** | 2.08 GB/s | 6.42 GB/s | 11.0 GB/s | 30.4 GB/s |
| Goose epoll | 56.0 K/s | 179 K/s | 2.23 GB/s | 7.41 GB/s | **11.6 GB/s** | **31.3 GB/s** |
| nginx 1.28.3 | 50.2 K/s | 173 K/s | **2.31 GB/s** | **8.15 GB/s** | 9.9 GB/s | 28.5 GB/s |
| Caddy 2.10.2 (Go) | 13.0 K/s | 47 K/s | 0.83 GB/s | 2.99 GB/s | 6.8 GB/s | 20.1 GB/s |

- nginx wins 64 KB, by 4% over epoll with 1 worker and 10% with 4. io_uring's
  splices through a pipe cost more than `sendfile` at that size.
- Goose copies files under 64 KB, which beats `sendfile` and the splices at 4 KB by 1.3
  to 1.8 times, and sends larger ones without copying.
- 1 MB with 4 workers is wrk's limit, not the servers'. Server CPU per request there:
  Goose epoll 106 µs, nginx 148 µs, Caddy 197 µs.
- Against this morning's `4a65d96`, which copied every file: 1 MB is 3.4 times faster on
  epoll and 8 to 11 times on io_uring.

Responses built in memory (`/bytes`, Goose only, the same setup): io_uring is level
with epoll at 1 MB (2.51 against 2.49 GB/s with 1 worker) and 25% ahead at 64 KB
(2.58 against 2.06). That morning it ran at half of epoll's rate.

On Windows, each file request costs 100-200 µs of kernel time, mostly opening the
file, so IOCP serves 5,000-17,000 files a second at every size. `TransmitFile` is 3 to
4 times faster than copying a 1 MB file with 1 worker, and no faster with 4, because
client Windows runs two at a time (task 020).

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
  - `http::authority(req)`: the host and port, from an absolute-form target before
    `Host` (RFC 9112 §3.2.2).
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

`Config.address` is where to listen: empty for every IPv4 address (127.0.0.1 on
Windows), an IPv4 or IPv6 address, `"::"` for every address, IPv4 too unless
`Config.ipv6_only`, or `"unix:/run/app.sock"` for a Unix socket on Linux and macOS,
whose path fits in 104 bytes on macOS and 108 on Linux. The server removes a socket file
left at the path before it binds, and its own when it stops.

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
- A literal segment matches an escape of an unreserved character (`/%75sers` is
  `/users`); an escaped `/` doesn't split a segment.
- A path with a `.` or `..` segment, escaped or not, or an escaped control byte, matches
  no route: a handler that checks access by a path's prefix can't be walked around.
- `http::otherwise`: 501 for a method the server doesn't know, 400 for a path the
  router refused, 204 for `OPTIONS *`, 405 with `Allow` from the routes whose path
  matched, 204 with it for `OPTIONS`, else 404.
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
| `WAKE` | A message came to the address `later` returned: its bytes in `ev.data`, its tag in `ev.tag`. ([Answers that wait](#answers-that-wait)) |
| `TIMEOUT` | `later`'s time limit passed first, or there was no room to wait. |
| `DONE` | With `Config.log`, the response is whole: `ev.status`, `ev.sent` bytes, and `ev.ms` from the head's first byte, for an access log. `ev.req` is the request only when it was answered at `REQUEST`. |

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
- `http::open_precompressed(req, path)`: the same, or in its place `path.br`,
  `path.zst`, or `path.gz`, whichever the request's `Accept-Encoding` weighs highest,
  and not older than `path`. `serve_file` then adds `Content-Encoding`, `Vary`, and an
  `ETag` of the copy's own. Responses aren't compressed on the fly yet (task 022).
- `http::serve_file(req, out, f, http::content_type_of(path), st.file)`: answers `GET`
  or `HEAD` with 200, 206, 304, or 416, with `ETag`, `Last-Modified`, and
  `Accept-Ranges`.
- `http::send_file(out, st.file)` at each `MORE` until false, then `http::end(out)`.
  With a `Content-Length` of 64 KB or more, it hands the file to the loop, which sends it without copying
  it through the program: `sendfile` on the epoll loop and the emulated ring, splice
  through a pipe on io_uring, and `TransmitFile` on IOCP. Client editions of Windows run
  two `TransmitFile` calls at a time across the system, so many downloads at once may
  queue there. A smaller file, which one read and a send serve faster, and a chunked
  response read up to 64 KB with `pread` per call.
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
- `http::peer(out)`: the connection's address and port. `http::client(req, out,
  trusted)`: the client a trusted proxy forwarded for, from `Forwarded` or
  `X-Forwarded-For`, with `trusted` from `http::network("10.0.0.0/8")`.
  `http::format_address(text, a)` writes one.

### Answers that wait

A handler given state can hand a request to another thread, or wait for a timer, and
answer later without blocking its worker. `Config.mail_slots` and `Config.max_waiting`
turn it on; both are 0 by default, and then a loop opens no box and arms no timer.

```goose
// At REQUEST: the reply's address, with a time limit the handler must give.
let reply = http::later(out, 5000);
guard http::mail_send(worker, JOB, job_for(reply)) == http::SENT
else { http::respond(out, 503, "text/plain", "busy"); return; }

// At WAKE: ev.data and ev.tag are what the worker sent to reply.
// At TIMEOUT: the limit passed first; answer 504.
```

- `http::later(out, ms)` makes the exchange wait for a message to the address it
  returns, then calls the handler with `WAKE` or `TIMEOUT`. After `begin`, or at
  `MORE`, it pauses an open response, for Server-Sent Events and long polling. A call
  that writes a whole response doesn't wait.
- Requests pipelined behind a waiting exchange wait in the read buffer, and reading
  stops once it's full.
- A message to an exchange that has ended, or to a connection that closed, is
  dropped. At stop, a waiting exchange gets `Config.grace_ms`, then `CLOSED`.
- A worker thread owns a box: `http::mail_open(slots, size)`, `http::mail_wait(box,
  ms)`, `http::mail_take(box) { key, tag, bytes => }`. `http::mail_send(address, tag,
  bytes)` returns `SENT`, `FULL`, or `STALE` at once, from any thread, and never blocks.
- `http::timer_table(n)`, `http::arm`, `http::cancel`, and `http::expire` are the
  loops' timers, for a worker's own.

The benchmark server's `/later` and `/events` (`server/routes.goose`) wait for a worker
thread with a box and a timer table of its own (`server/backend.goose`), with
`MAIL_SLOTS` set.

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
examples/      small servers, one with its handler in C
test/          unit tests
bench/         competing servers, load scripts, recorded results
scripts/       build and run scripts
docs/          architecture, development setup, results, Goose findings
tasks/         task tracking (tasks/README.md)
```

## Pins

| What | Pin | Why |
|---|---|---|
| Goose compiler | `aardappel/goose` `c38dc0f` (`master`, 2026-10-12) | The language and stdlib change often |

Move the pin in its own commit, with the build and benchmark results that still hold.
