# Examples and API

The examples, and the package's API by topic, each with the code that shows it. The
concepts come first in the [README](../README.md#concepts).

## Examples

Each example imports the package from this checkout (`"../../"`), not from GitHub. A
program of your own imports it as the [Quick start](../README.md#quick-start) does.

| Example | What it shows |
|---|---|
| [`hello/`](hello/hello.goose) | One route, one worker per core: the Quick start |
| [`routes/`](routes/routes.goose) | The router: parameters, 404 and 405, a JSON response, a request body, and a stop on Ctrl+C |
| [`server/`](../server/routes.goose) | The benchmark server: bodies and responses in pieces, files, an upgrade, answers that wait, the access log |

Build and run one from the repository's root:

```sh
goose build -o build/examples/routes examples/routes/routes.goose
./build/examples/routes
curl localhost:8080/users/42
```

Each one listens on port 8080. `scripts/test.sh` typechecks them.

## Requests and responses

### Handler

Shown in `hello/` and `routes/`.

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
  decoded. A longer body is dropped and `body` is empty; see [Streaming](#streaming).
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

### Routes

Shown in `routes/`.

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

### Helpers for APIs

`respond_json` is shown in `routes/`, the client address in `server/`; the rest have no
example yet.

The helpers that read a request take it as `const http::Request&`, so a call doesn't
copy it. Pass them a variable, such as the handler's `req`: Goose doesn't yet bind a
call's result to a reference parameter
([findings](../docs/goose-findings.md#a-struct-literal-cant-be-passed-to-a-const-t-parameter)).

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

### Conditional requests and ranges

`http::serve_file` uses these ([Files](#files)); no example uses them alone yet.

- `http::not_modified(req, etag, modified)`: whether a `GET` gets 304. `If-None-Match`
  first, else `If-Modified-Since`.
- `http::range_of(req, size, etag)`: the one byte range asked for, with 206, 416, or
  200 for the whole (for example when `If-Range` names another entity tag).
- `http::content_range(out, start, end, size)`: writes `Content-Range`.

## Bodies and responses of any size

### Streaming

Shown in `server/`: `/upload`, `/echo`, `/bytes`, `/stream`, and `/upgrade`.

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

Shown in `server/`: `/files/NAME` serves the directory in `FILES`.

- `http::open_file(path)`: opens a regular file, or 404 or 403.
- `http::open_precompressed(req, path)`: the same, or in its place `path.br`,
  `path.zst`, or `path.gz`, whichever the request's `Accept-Encoding` weighs highest,
  and not older than `path`. `serve_file` then adds `Content-Encoding`, `Vary`, and an
  `ETag` of the copy's own. Responses aren't compressed on the fly yet: task 022 adds
  gzip, deflate, and zstd through [goose-compress](https://github.com/kaitk/goose-compress).
- `http::serve_file(req, out, f, http::content_type_of(path), st.file)`: answers `GET`
  or `HEAD` with 200, 206, 304, or 416, with `ETag`, `Last-Modified`, and
  `Accept-Ranges`.
- `http::send_file(out, st.file)` at each `MORE` until false, then `http::end(out)`.
  With a `Content-Length` of 64 KB or more, it hands the file to the loop, which sends
  it without copying it through the program: `sendfile` on the epoll loop and the
  emulated ring, splice through a pipe on io_uring, and `TransmitFile` on IOCP. Client
  editions of Windows run two `TransmitFile` calls at a time across the system, so many
  downloads at once may queue there. A smaller file, which one read and a send serve
  faster, and a chunked response read up to 64 KB with `pread` per call.
- `http::close_body(st.file)` at `CLOSED`.
- `http::is_safe_path(path)`: rejects `.` and `..` segments, backslashes, and colons.
  Check the decoded path before joining it to a directory.

## Answers that wait

Shown in `server/`: `/later` and `/events` wait for a worker thread with a box and a
timer table of its own (`server/backend.goose`), with `MAIL_SLOTS` set, and `/delay/MS`
for a timer.

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

## Running a server

### Config and shutdown

The stop on Ctrl+C is shown in `routes/`.

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

### Event loops

The program calls one. Goose compiles a generic function only where it's called, so the
other isn't in the binary.

| Loop | Linux | macOS | Windows |
|---|---|---|---|
| `http::serve` | io_uring, kernel 6.1+ | ring emulated on kqueue | IOCP |
| `http::serve_epoll` | epoll | kqueue | `ENOSYS` |

- `http::serve` is the default. On Linux 12-22% faster than epoll, at 2-5 times the
  peak RSS, 10-16 MB with 4 workers. Where `io_uring_setup` fails, as under Docker's
  default seccomp profile, it emulates the ring on epoll; `http::ring_probe()` says why.
- `http::serve_epoll` is faster on macOS, and on Linux uses a quarter of the memory.

The benchmark server links both. `LOOP` picks: `uring` (`iocp` on Windows), `epoll`,
or `uring-epoll`. See
[architecture](../docs/architecture/README.md#the-io_uring-loop-task-005).

## A handler in C, on a branch

The `examples-c` branch has `examples/c/`, an experiment (2026-10-12): the package's
server with a handler written in C, which `goose build` compiles from the example's
sidecar. It's off `main` until Goose leaves examples out of a package: Goose links the
C function of every `extern fn` under the package's root into the package's library
for in-process runs, so the example's `gh_handle`, which only its own C defines, broke
every `goose file.goose` that imported the package
([findings](../docs/goose-findings.md#a-packages-jit-library-links-the-externs-of-every-file-under-its-root)).
