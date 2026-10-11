# 013: HTTP/1.1 essentials

Status: in-progress (asked for 2026-10-11; design with task 011)

The server parses and frames HTTP/1.1 well enough to pass the smuggling, limit, and
keep-alive checks the competitors fail (`bench/README.md`), but it only serves its own
fixed routes. A program that imports it (task 011) also needs the parts listed below:
header access, bodies and responses of any size, and shutdown. They are ordered by
priority within each group. Line numbers are at `9623c6a`.

Already in place, and kept: tchar methods, 414, 431 (8 KB head, 100 fields), 505 for a
major version other than 1, 501 for a `Transfer-Encoding` other than `chunked`, 400 for
`Content-Length` and `Transfer-Encoding` together or for differing `Content-Length`s,
exactly one `Host` in HTTP/1.1, HTTP/1.0 keep-alive, pipelining, `HEAD`, a cached `Date`,
write backpressure, 10 s head and body timeouts that trickled bytes don't extend, 60 s
idle close, and a cap of 16,384 connections per worker.

Items 6, 7, and 8 decide the shape of task 011's handler: a handler called once with
`(req, body, out)` can't stream. Decided (2026-10-11, task 011): `v0.1.0` serves
fixed-size requests and responses only, and items 7 and 8 come as another entry point
later; task 011's file has the reasons. Items 3, 7, 8, 11, and 13
change the per-connection state, in both of task 011's loops, `http::serve` and
`http::serve_epoll`, unless task 011's shared request handling carries them.

## Correctness (RFC 9110, RFC 9112)

1. Absolute-form targets. A server must accept `GET http://host/path` (RFC 9112 §3.2.2);
   `path_of` (`src/http.goose:328`) takes it for a path, so it gets 404.
2. `Host` value. A `Host` with an invalid value must get 400 (RFC 9112 §3.2); only the
   count is checked (`src/http.goose:185-190`).
3. `Expect: 100-continue` (RFC 9110 §10.1.1). curl sends it with large bodies and waits
   up to 1 s for an answer before sending the body anyway. Answer `100 Continue` before reading the body, or
   the final status at once (413, 405); any other expectation gets 417.
4. Response framing a handler can't break: no body or `Content-Length` on 1xx, 204, and
   304; `HEAD` gets `GET`'s fields; no `Transfer-Encoding` to an HTTP/1.0 client, whose
   streamed body ends at close (RFC 9110 §8.6, RFC 9112 §6). The fixed routes are right
   by construction; a program's handler won't be.
5. `OPTIONS *` gets 404 today (RFC 9110 §9.3.7), and an unknown method on an unknown path
   gets 404 where 501 is expected.

## A library a program can use (task 011)

6. Header access. `Request` (`src/http.goose:50-58`) drops every field the parser doesn't
   interpret. The handler looks a field up by case-insensitive name and iterates them,
   as slices into the read buffer, repeated fields included.
7. Bodies larger than the read buffer. A body must fit in the 8 KB buffer with the head
   (`src/http.goose:209-228`) or gets 413. The handler reads `Content-Length` and chunked
   bodies in buffer-sized pieces, up to a configurable limit; a body it ignores is still
   drained. This is the largest change to the io_uring loop.
8. Large and streamed responses. A response of any size goes whole into the worker's
   growable write buffer (task 011), so the handler can send one, but not stream one.
   The handler can send a body of any size without holding it whole, and stream one with
   chunked encoding, while backpressure pauses the handler instead of buffering
   without bound. Check what shape spec §7.6's compile-time function values allow for a
   handler that resumes.
9. Path and query decoding. Only `query_int` exists (`src/http.goose:378`), without
   percent-decoding.
10. Limits and timeouts as configuration, not constants (`src/http.goose:11-23`,
    `src/app.goose`), with a body and a write timeout apart from the head's.
11. Graceful shutdown. The loop never returns. On `SIGTERM` or a call, workers close
    their listeners, answer the next request on each connection with `Connection: close`,
    finish what's in flight within a grace period, and return. Needs a wakeup in each shim's
    wait: epoll, io_uring, kqueue, and IOCP. A loop called again after it returned must
    work: on macOS, `shim/kqueue.c`'s table of shared listeners keeps the first worker's
    fd for the listener and never forgets a worker, so it would dup a closed fd. Each
    worker would need to leave the table in `net_close`, with the table holding a
    reference of its own (task 011).
12. Error responses from the handler that keep the connection open when the request was
    read whole; `refuse` always closes.

## Later

13. `Upgrade`, so a handler can answer 101 and take over the connection (WebSocket;
    task 014's `h2c` upgrade, if it's ever wanted).
14. Request trailers (skipped at `src/http.goose:246-257`), and response trailers on
    chunked responses.
15. A router: method and path patterns with parameters, 405 with `Allow` from the routes.
16. Response helpers: a configurable or absent `Server` (hard-coded in `status_line`),
    conditional `GET` (304), `Range`, static files through `sendfile`.

## Progress

- Items 1 and 2 came with task 007's Http11Probe fixes (`b73d527`).
- Item 6 (2026-10-11): `parse` keeps the field lines as `Request.fields`, and
  `http::field_of(req, name)` and `http::each_field(req) { name, value => }` scan them
  only when a handler asks. `bench/instructions.sh` (3 runs, as in task 011) measured
  1,423-1,441 user instructions per request for the epoll loop against 1,400-1,431
  before, and 1,482-1,501 for the uring loop against 1,488-1,507: no cost.
- Item 9 (2026-10-11): `http::decode(s, out, plus)`, `http::query_of`, and
  `http::each_query`, and 400 from `parse` for a target with a `%` that doesn't start
  an escape, checked only when the target has one. Values stay encoded until the
  handler decodes them, since a decoded path can hold a `/` that wasn't a separator.
- Item 4 (2026-10-11): `http::start` sets `Reply.bodyless` for 1xx, 204, and 304, and
  `http::finish` then writes neither a `Content-Length` nor the body. Streamed bodies to
  HTTP/1.0 wait for item 8.
- Item 5 (2026-10-11): `http::known_method`, and the benchmark server answers
  `OPTIONS *` with 200 and `Allow`, and a method it doesn't recognize with 501, on any
  path. Which methods a program recognizes is its own choice, so the package doesn't.

- Items 4, 5, and 9 cost 50-100 user instructions per request against `856f99b`. Split
  (2026-10-12) by building `915c34f` without each change, in WSL2 as `bench/README.md`
  describes, and counting with `bench/instructions.sh` (one worker on CPU 0, wrk on CPUs
  4-15, plaintext 16 deep at 256 connections, 3 runs each). In user instructions per
  request:

  | Build | epoll | uring |
  |---|---|---|
  | `856f99b`, before the three | 1,411-1,441 | 1,467-1,530 |
  | `915c34f` | 1,483-1,491 | 1,543-1,584 |
  | without the `%` check | 1,425-1,438 | 1,510-1,518 |
  | without `Reply.bodyless` | 1,493-1,511 | 1,548-1,559 |
  | without item 5's routes | 1,455-1,481 | 1,515-1,553 |
  | without all three | 1,395-1,455 | 1,467-1,499 |

  The `%` check was the cost: `position` scans the target a byte at a time. `parse`'s
  search for the target's end now stops at a `%` too, and checks the escapes only of a
  target that has one. In a second set of 3 runs, that measured 1,448-1,465 (epoll) and
  1,503-1,523 (uring), against 1,425-1,435 and 1,487-1,512 for `856f99b` and
  1,485-1,518 and 1,547-1,578 for `915c34f`. The rest, 10-25, is within what the route
  changes measured, and within the runs' spread.

- Items 7, 8, and 3 (2026-10-12), as [the design](#streaming-design-2026-10-12) says:
  `http::serve(cfg, fresh)` and `http::serve_epoll(cfg, fresh)` call their handler
  with an `http::Event`, `http::begin`, `http::send`, and `http::end` write a response
  in pieces, and `http::read_body` decodes a body in pieces. `Expect: 100-continue`
  gets `100 Continue` as the design says, and any other expectation 417. The
  benchmark server serves through `serve(cfg, fresh)`, with `/upload`, `/echo`,
  `/stream`, and `/bytes` sent in pieces, and `http_client.py`'s `stream` mode tests
  them: 100 MB uploads with a `Content-Length` and chunked, dropped bodies below and
  past `max_drain`, `Expect`, 10 MB echoed both ways, 10 MB and 100 MB downloads, and
  HTTP/1.0's body ending at the close. After it, the server's peak RSS was 2.7 MB
  (epoll), 8.5 MB (uring), and 7.8 MB (uring over epoll) in WSL2.
  - `serve(cfg)` is a wrapper over `serve(cfg, fresh)`. The handler's call takes the
    request by reference (`Event.req`): copying it cost nothing measurable.
  - Goose doesn't inline a function that takes a function value
    ([findings](../docs/goose-findings.md#an-inline-fn-that-takes-a-function-value-stays-a-call)),
    and gcc kept the wrapper's out of line, which cost 60-120 instructions per request
    until the loops called the program's handler themselves.

Open: the streaming loop costs about 50 user instructions per request on the
benchmark routes. `bench/instructions.sh`, 2 runs each, as above, after the request's
state went straight into the slot: 1,511-1,524 (epoll) and 1,560-1,571 (uring),
against 1,460-1,484 and 1,513-1,517 at `1e9dddb`, with cycles per request within 1-2%.
`serve(cfg)`, the wrapper, measured the same as the server's own streaming handler:
1,526-1,531 and 1,565-1,571. Isolating parts of it before that: the `Expect` field's
check in `parse` is about 14, and the server's new routes 10-25; the rest is the
loop's per-request state (the handler's state, and the checks for a body or a
response still open).

- Item 10 (2026-10-12): `Config.max_line`, `max_fields`, `body_ms`, and `write_ms`,
  beside `max_head`, `max_body`, `request_ms`, and `idle_ms`. A connection waits
  `write_ms` for the client to take a response, `body_ms` for a body's next piece, and
  `request_ms` for the rest of a head. The benchmark server takes `REQUEST_MS`,
  `BODY_MS`, and `WRITE_MS` from the environment, and `test-http.sh` runs the slow
  clients against 4, 3, and 5 s; `test_http.goose`'s `test_limits` parses at limits
  other than the defaults.
- Item 12 (2026-10-12): a handler's error response keeps the connection open like any
  other, and since items 7 and 8, so does one that comes before the body has arrived,
  which is dropped up to `Config.max_drain`. `refuse`, for what `parse` refuses, still
  closes: past a malformed head, where the next request starts isn't known.

- Item 11 (2026-10-12): `http::stop()` and `http::stop_on_signals()`, with
  `Config.grace_ms`, as the architecture records, where a counter that each loop checks
  after a wait of at most a second replaced a wakeup in each shim's wait. The
  benchmark server stops on `SIGTERM` and exits 0, and `http_client.py`'s `stop`
  mode checks it on Linux: an idle connection closed within 2.5 s, the listener
  refusing within 3 s, a request in progress answered with `Connection: close`, a
  20 MB response in progress finished, and the process gone. Not tested: the stop on
  Windows, where nothing in the test scripts can send Ctrl+Break to the server, and
  on macOS, where `shim/kqueue.c`'s table change passed only a syntax check (clang,
  with stub macOS headers, in WSL). With `SERVER_RUNS=2`, the benchmark server serves again
  after a stop, and `test-http.sh` checks that the loops started again serve
  (`keepalive`) and stop.

- Item 15 (2026-10-12): `router.goose`. `http::router(req)`, `http::on(r, method,
  pattern)` in an `if` chain, `http::param(r, name)`, and `http::otherwise(r, out)`,
  which answers 405 with `Allow` from the routes whose path matched, 204 with it for
  `OPTIONS`, and otherwise 404. A route is tried by matching its pattern against the
  path, segment by segment, with no table and no allocation: the handler's order is
  the routes' order. `test_http.goose`'s `test_router` checks parameters, a wildcard,
  `HEAD` on a `GET` route, absolute-form targets, 405, `OPTIONS`, and 404.

- Item 13 (2026-10-12): `http::upgrade_of(req)` and `http::upgrade(out, protocol)`,
  which answers 101 and leaves the response open in a raw mode: the body reader's
  `RAW` place hands every later byte to the handler as `BODY`, `send` writes bytes
  unframed, and `end` closes the connection. An upgraded connection waits `idle_ms`
  for the client, not `body_ms`. The benchmark server's `/upgrade` switches to an
  echo, which `http_client.py`'s `stream` mode checks with bytes that came with the
  request, an HTTP request line, and 100 KB, and a request without `Upgrade` gets
  426.

- Items 16 and 14, in part (2026-10-12): `http::not_modified`, `http::range_of`, and
  `http::content_range` for conditional `GET` and one byte range, with
  `http::parse_date` for IMF-fixdate (not the obsolete forms, which leave a condition
  ignored), and response trailers through `http::end(out, trailers)`.
  `test_http.goose`'s `test_conditional` and `test_stream` check them. Request
  trailers come in `Event.trailers`, at `END` or with a whole chunked body, as field
  lines that `http::field_in` searches, checked to be field lines; `/echo` sends a
  chunked body's back as its response's, which `stream` checks. Not yet: a
  configurable or
  absent `Server` field, which every status line has as a literal, so that a constant
  status costs one append; and files through `sendfile`, which needs the shims.

Next, in order:

1. Run the tests on macOS: the kqueue table change, and the stop.
2. Split the streaming loop's cost further, and remove what can go.
3. The rest of item 16.

## Streaming design (2026-10-12)

How servers with a streaming API shape it, read in their sources:

- may-minihttp 0.1.11 reads the body inside the handler, which runs as a stackful
  coroutine, and has no streamed response. A handler that never asks for the body leaves
  it to be parsed as the next request.
- hyper 1.x pulls a response body with `poll_frame` only while its write buffer has
  room, and frames it with `Content-Length` when the size is known, chunked when not.
  A request body goes through a one-item channel, so at most one piece waits. It sends
  `100 Continue` on the first poll of the body, so an unwanted body never gets one, and
  it closes rather than drain a body the handler dropped, past what has already arrived.
- actix-http pulls a response with `poll_next` while the write buffer is below its
  size. It stops reading the socket while the request payload's buffer is over 32 KB,
  drains a dropped chunked body, and closes for an unfinished `Content-Length` one. Body
  limits are set per route (`PayloadConfig`, 256 KB by default).
- h2o calls a generator's `proceed` once the last batch has gone: one batch in flight
  per request, and backpressure is "called again". A request body comes in pieces through
  a callback, and h2o stops reading until the receiver asks for more. A handler that
  doesn't stream gets the body whole, and so does a streaming one when it's all there
  already.
- picohttpparser's `phr_decode_chunked` decodes in place with a small resumable state.
- nginx drains a discarded body through a small buffer, bounded by time
  (`lingering_time`), and checks `client_max_body_size` against `Content-Length` before
  reading and per chunk after.
- odin-http drains an unread body up to 256 KB when the handler responds, and closes past
  that.

What fits Goose: a handler can't be suspended or stored (spec §7.6), but the loop can
call one again, as h2o's callbacks are called again, with its state in the connection's
slot. So:

- One more entry point per loop, `http::serve(cfg, fresh) { ev, st, out => ... }` and
  `http::serve_epoll(cfg, fresh) { ... }`. `fresh` is the program's per-request state, a
  flat value of any type; each connection's slot holds one, reset to `fresh` before each
  request, and the handler gets it as `st`. `ev` is an event: `REQUEST`, with the
  parsed head and the body when it arrived whole with the head (`ev.whole`); `BODY`, a
  piece of the body; `END`, once the body is all there; and `MORE`, room to write more of
  an open response. The fixed-size `serve(cfg) { req, body, out => }` becomes a wrapper
  that answers `REQUEST` only, so it serves as today.
- A body that fits in the read buffer with its head still arrives whole, as today:
  h2o's fast path, and the benchmark's. A longer one comes in `BODY` pieces of what each
  read brings, `Content-Length` and chunked alike. Chunked bodies are decoded in the
  read buffer as they arrive, by a decoder whose place and the chunk's remaining length
  live in the slot.
- A response is whole, as today (`start`, `field`, `finish`), or open: `http::begin(out,
  status, length)` writes the head with `Content-Length` for a known length, or chunked
  for -1 (HTTP/1.0 then closes at its end), `http::send(out, bytes)` writes a piece,
  one chunk per call, and `http::end(out)` ends it. While a response is open and its
  request body is done, the loop calls the handler with `MORE` each time the
  connection's queued output is below `cfg.write_buffer`, so memory per connection stays
  bounded. A `MORE` that writes nothing and doesn't end closes the connection, rather
  than spin.
- Backpressure on the body is the loops' backpressure on requests: neither reads more
  while the connection's output is past its limit.
- A response finished before its body arrived drains the rest without events, up to
  `cfg.max_drain` bytes, and closes past that. An `Expect: 100-continue` body that would
  fit in the read buffer gets `100 Continue` at once; a longer one gets it after the
  handler's `REQUEST` call, unless the handler responded, which closes the connection
  once the response is sent (hyper's lazy `100 Continue`).
- Not yet: request trailers, which the decoder checks and skips (item 14), and an
  event for a connection closed mid-stream: the state is flat data, with nothing to free.

## Acceptance criteria

- [x] `GET http://tfb-server/plaintext` answers as `GET /plaintext` (2026-10-11, `b73d527`;
      `http_client.py`'s `tfb` checks it)
- [x] `Host: a b` and `Host: [::1` get 400; `Host: x:8080`, `Host: [::1]:80`, and an
      empty `Host` get 200 (2026-10-11, `b73d527`)
- [x] A `POST` with `Expect: 100-continue` gets `100 Continue` before its body is read, or
      its final status without one; `Expect: other` gets 417 (2026-10-12, `http_client.py`'s
      `stream` and `hostile`)
- [x] Unit tests show 204, 304, and `HEAD` without a body, and a streamed body to an
      HTTP/1.0 client ending at close, whatever the handler writes (2026-10-12,
      `test_http.goose`'s `test_reply` and `test_stream`)
- [x] `OPTIONS *` gets 200 with `Allow`; an unknown method gets 501 (2026-10-11, the
      benchmark server's routes)
- [x] The handler reads any request field by name, and iterates them (2026-10-11:
      `http::field_of` and `http::each_field`)
- [x] A handler reads a 100 MB `Content-Length` body and a 100 MB chunked body in pieces;
      a handler that ignores them leaves the connection usable for the next request
      (2026-10-12; up to `Config.max_drain`, past which it closes)
- [x] A handler sends a 10 MB body, and streams a chunked one, with each connection's
      memory bounded (2026-10-12; `test-http.sh` checks the peak RSS after 100 MB)
- [x] Decoded path and query, with 400 for an invalid `%` escape (2026-10-11)
- [x] Limits and timeouts set by the program, with tests at non-default values
      (2026-10-12)
- [x] `SIGTERM` drains and stops every worker within the grace period, in `serve` and
      `serve_epoll` (2026-10-12, Linux; Windows and macOS untested)
- [ ] Every item above has a check in `scripts/http_client.py` or `src/test_http.goose`
- [ ] The benchmark routes, served through the handler, keep their rate in
      `bench/run.sh`'s closest cells within the runs' spread
