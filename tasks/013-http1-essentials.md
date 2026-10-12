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

The streaming loop cost 60-80 user instructions per request on the benchmark routes, until
the split below ("The request path's cost, split"). `bench/instructions.sh`, 2 runs each, as above, all built with Goose at
`fee060c`:

| Build | epoll | uring | epoll cycles | epoll req/s |
|---|---|---|---|---|
| `1e9dddb`, before streaming | 1,459-1,465 | 1,513 | 1,900-1,904 | 1.934-1.939 M |
| `d80d662` | 1,545-1,546 | 1,582-1,591 | 1,942-1,943 | 1.864-1.883 M |
| `d80d662`, through `serve(cfg)` | 1,546-1,557 | 1,601-1,602 | 1,927 | 1.886-1.904 M |
| `66f28eb` | 1,525-1,539 | 1,579-1,585 | 1,931-1,939 | 1.864-1.886 M |

`66f28eb` compares the benchmark's two paths before the server's other routes, which
saved 5-15. Earlier, isolating parts of it: the `Expect` field's check in `parse` was
about 14, and the server's new routes 10-25; the rest is the loop's per-request state
(the handler's state, and the checks for a body or a response still open). A profile
by line of the generated C, built with `-g`, spread the difference too thin to name
one cause. Under `perf` and one worker, the epoll build's rate is 3% lower.

In the benchmark's cells, that is 0-3%, and outside the runs' spread only with 4
workers on plaintext. `bench/run.sh` (2026-10-12, `bench/results/2026-10-12-streaming/`):
WSL2, kernel 6.18.40.1, Ryzen 7 5800X3D; the server on CPUs 0-3 and wrk and h2load on
4-15 with 8 threads; plaintext pipelined 16 deep, JSON not; 15 s runs after a 5 s
warm-up, 3 runs a cell, the median. `goose-v-start` and `goose-v-start-uring` are
`915c34f`, before items 7 and 8; `goose-v-end` and `goose-v-end-uring` are `03c7b67`;
all built with Goose at `fee060c` and cc 15.2.

| Cells | epoll, end / start | uring, end / start |
|---|---|---|
| plaintext, 1 worker, 256 / 1,024 / 4,096 connections | 0.99 / 0.99 / 1.00 | 0.99 / 1.00 / 1.02 |
| plaintext, 4 workers, 256 / 1,024 / 4,096 | 0.97 / 0.97 / 0.98 | 0.98 / 0.98 / 0.98 |
| JSON, 1 worker, 256 / 1,024 | 1.01 / 0.98 | 0.99 / 0.99 |
| JSON, 4 workers, 256 / 1,024 | 1.00 / 0.99 | 1.00 / 0.98 |

At the end of the night (2026-10-12, `bench/results/2026-10-12-night/`, as above with
`WORKER_COUNTS=4`), `2b10d24` on Goose `5c83a5a` against `03c7b67` on `fee060c` (the
`goose-v-end` builds above; `env.txt` names only the current pin): every cell within
0-1.2%, and the spreads overlap in all but uring plaintext at 1,024 connections, 0.4%
lower (6.79 M against 6.82 M). The night's later changes, the `Server` field, files,
and the shims' reused send buffers, moved no cell.

Three cells' spreads don't overlap: epoll plaintext with 4 workers and 1,024
connections (5.53 M against 5.71 M requests per second), and uring plaintext with 4
workers and 256 and 1,024 connections (6.90 M against 7.04 M, and 6.77 M against
6.89 M). Peak RSS grew by at most 1.1 MB in a cell (uring JSON, 4 workers, 1,024
connections: 12.4 MB against 11.3 MB).

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
  20 MB response in progress finished, and the process gone. On Windows, the same
  checks by Ctrl+Break (`stop-break`, 2026-10-12), with the exit status 0, and on macOS
  by `SIGTERM` (2026-10-12, below). With `SERVER_RUNS=2`, the benchmark server serves
  again after a stop, and `test-http.sh` checks that the loops started again serve
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
  chunked body's back as its response's, which `stream` checks.
- Item 16, the `Server` field (2026-10-12): `Config.server`, `goose` by default, or
  empty for none, checked at start to be a field value. Each loop renders it with the
  `Date` field, once a second, into one buffer (`http::common_fields`), and the status
  lines' literals end at their CRLF, so a response still takes one append for both.
  `Reply.date` became `Reply.common`. The buffer is on the heap: as a 112-byte array
  in the loop's frame, it raised the io_uring build from 1,567-1,584 user
  instructions per request to 1,593-1,616, and as a 64-byte one to 1,585-1,592; on
  the heap, 1,587-1,593, with cycles per request at or below the old build's
  (`bench/instructions.sh`, 2 runs a build, as above).
- Item 16, files (2026-10-12): `file.goose`. h2o's file handler, read for it, sends a
  file with `pread` in pieces by default and with `sendfile` where the platform has
  one, through a pipe on io_uring, and closes the file when its generator is
  disposed. Here, `http::open_file`, `http::serve_file` (304, 416, 206, or 200, with
  `ETag`, `Last-Modified`, and `Accept-Ranges`), and `http::send_file`, which reads up
  to 64 KB at each `MORE` with a shim function per platform (`pread`, or `ReadFile`
  at an offset on Windows), and the event `CLOSED`, which the loops send a handler
  still owed a call when its connection closes, so that it can close the file. Also
  `http::is_safe_path` and `http::content_type_of`, and 206 and 416 among the status
  lines. Each piece is read into a buffer of its own and copied: `Reply.common` is a
  byte slice that, for all the checker knows, points into the write buffer, so the
  write buffer can't shrink back past a failed read (spec §5.1). `http_client.py`'s
  `files` checks the benchmark server's `/files/` on every loop, Linux and Windows,
  and `test-http.sh` that no file stays open after clients leave halfway, which it
  failed with `CLOSED` ignored; `test_http.goose`'s `test_files` checks the helpers.
  On macOS, `test-http.sh` asks `lsof` instead of `/proc` (2026-10-12, below).

Neither the move to Goose `5c83a5a` nor files changed the benchmark path's cost
(`bench/instructions.sh`, 2 runs a build, as above, 2026-10-12): user instructions per
request were 1,550-1,569 (epoll, `743609f`) and 1,601-1,614 (uring, `61ef340`) on
`fee060c`, 1,539-1,562 and 1,579-1,601 for `31a1410` on `5c83a5a`, and 1,550-1,572 and 1,602-1,606
for `a3cf843` on `5c83a5a`, within the runs' spread of about 15. Keeping
`keep_alive` and the stream in locals during `REQUEST`, and copying them into the slot
only when the exchange goes on, changed nothing either (1,542-1,575 and 1,600-1,603).

Large responses (2026-10-12). One worker on CPU 0, wrk on CPUs 4-15 with 8 threads and
64 connections for 10 s, 2 runs each, WSL2 as above, files from tmpfs, all built with
Goose at `5c83a5a`:

| Build | Path | epoll | uring |
|---|---|---|---|
| `4a65d96` | `/files/` 64 KB | 1.90-1.91 GB/s | 1.21-1.22 GB/s |
| `4a65d96` | `/files/` 1 MB | 3.25-3.30 GB/s | 0.98 GB/s |
| `4a65d96` | `/bytes?n=1048576` | 2.32 GB/s (1 run) | 1.02-1.05 GB/s |
| `4a65d96`, `max_queued` 512 KB | `/bytes?n=1048576` | | 1.15 GB/s |
| with `shim/uring.c` keeping big send records | `/bytes?n=1048576` | | 1.72-1.73 GB/s |

The io_uring loop sent a large response at a third of epoll's rate, files or not. Under
`perf record`, page faults and page clearing took about 15% of CPU 0: `ur_send` copies a
send into a record of its own, and gave each one over 8 KB back to malloc, which
returned it to the kernel, so the next one faulted its pages in again. The shim now
keeps freed records over 8 KB, sized in 64 KB steps, up to 4 MB a ring, and reuses
one that's big enough: +65%, with plaintext's instructions per request unchanged
(1,606-1,614 against 1,601-1,604). What's left is the loop's: `flush` took 47% of
CPU 0, appending each piece to `c.out` in the spill pool behind the send in flight
(the pool's span bookkeeping, a zero fill, and a copy), before the shim copies it
again. Gathering the pieces in `wbuf` and moving them to `c.out` once changed nothing
(1.66-1.67 GB/s). The fix is in the shims: queue a send behind the one in flight per
connection, in the shim, so `flush` always hands bytes over once.

Sends queued in the shim (2026-10-12). `shim/uring.c` and `shim/iocp.c` now keep each
fd's sends in order behind the one in flight, as `shim/ring_epoll.c` did, and a send
that waits takes later ones into its record while it has room. The loop calls
`ring_send` for every piece and counts the bytes not yet sent; `max_queued` now counts
the send in flight too. Measured on the Windows laptop (AMD Ryzen 7 PRO 6850U, 8 cores,
16 threads), WSL2 Ubuntu 26.04, kernel 6.18.40.1-microsoft-standard-WSL2, gcc 15.2.0,
Goose `5c83a5a`: one worker on CPU 0, wrk on CPUs 4-15 with 8 threads and 64
connections for 10 s, 2 runs each, files on tmpfs. Before is `59740a7`; these compare
only with each other, not with the desktop's numbers above.

| Loop | Path | Before | After |
|---|---|---|---|
| epoll (unchanged) | `/bytes?n=1048576` | 1.61-1.62 GB/s | 1.86-1.87 GB/s |
| epoll (unchanged) | `/files/` 64 KB | 0.96-1.04 GB/s | 1.05-1.08 GB/s |
| epoll (unchanged) | `/files/` 1 MB | 2.29-2.34 GB/s | 2.37-2.44 GB/s |
| uring | `/bytes?n=1048576` | 1.14-1.17 GB/s | 1.25-1.42 GB/s |
| uring | `/files/` 64 KB | 1.19-1.21 GB/s | 1.20-1.22 GB/s |
| uring | `/files/` 1 MB | 0.65-0.86 GB/s | 1.16-1.23 GB/s |
| uring-epoll | `/bytes?n=1048576` | 0.64-0.80 GB/s | 1.04-1.05 GB/s |
| uring-epoll | `/files/` 64 KB | 0.36-0.78 GB/s | 0.98-1.01 GB/s |
| uring-epoll | `/files/` 1 MB | 0.58-0.68 GB/s | 1.09-1.11 GB/s |

The epoll loop didn't change and still moved 2-15% between the two sessions, so only
the larger gains count: io_uring's 1 MB file +40-80%, and the emulated ring's every
path. The laptop's runs spread far wider than the desktop's. Small responses didn't
regress: `bench/instructions.sh`, 2 runs, as above on this laptop, gave
1,598-1,628 user instructions and 2,799-2,844 cycles per request on io_uring before,
and 1,540-1,556 and 2,651-2,708 after; epoll, unchanged, 1,440-1,521 and 1,484-1,502.
`bench/run.sh` with `SERVERS="goose goose-uring" WORKER_COUNTS=1 TESTS="plaintext:256
json:256" RUNS=1 DURATION=5 WARMUP=2 LATENCY=0`: plaintext 0.956 M and then 0.974 M on
io_uring, 0.735 M and 0.722 M on epoll; JSON 0.072 M and 0.071 M, 0.054 M and
0.051 M. `scripts/test.sh` passes in WSL, and in Git Bash on the laptop with the IOCP
loop. Measuring `shim/iocp.c`'s queue on Windows waits for the desktop.

`sendfile` on the epoll loop (2026-10-12). Under `perf record` on the laptop, epoll
serving the 1 MB file spent 8.8% of CPU 0 in `pread`'s copy, 7.1% in `send`'s, and
7.9% clearing pages, besides the copies in user code. On Linux, `send_file` now gives
the loop the file and the rest of a `Content-Length` body, and the loop sends it with
`sendfile` and closes the file. As above, the same laptop and settings, before is
`781964f`:

| Loop | Path | Before | After |
|---|---|---|---|
| epoll | `/files/` 64 KB | 1.05-1.08 GB/s | 1.16 GB/s |
| epoll | `/files/` 1 MB | 2.37-2.44 GB/s | 6.54-7.01 GB/s |
| epoll | `/bytes?n=1048576` | 1.86-1.87 GB/s | 1.85-1.87 GB/s |
| uring | `/files/` 1 MB | 1.16-1.23 GB/s | 1.14-1.16 GB/s |

`bench/instructions.sh`, 2 runs: epoll 1,491 user instructions per request against
1,484-1,502 before; io_uring 1,575-1,577 against 1,540-1,556, and 2,720-2,723
cycles against 2,651-2,708. That cost on io_uring, which never sends a file this way,
is the check `answer` makes for a file before each request, and is kept. The quick
`bench/run.sh` cells: plaintext 0.719 M epoll and 0.965 M io_uring, JSON 0.049 M and
0.074 M. `scripts/test.sh` passes; the first run found that a client leaving
mid-file killed the server with `SIGPIPE`, so worker threads block it now. macOS
kept reading in pieces until the next paragraph.

macOS (2026-10-12): `scripts/test.sh` passed twice at `6c34442` (the code of
`10d46e5`), with Goose `5c83a5a`, on the MacBook Pro in `docs/development.md`, macOS
26.3.1, Apple clang 21.0.0: both loops, after the shared changes since the last Mac run
(queued send bytes in `uring.goose`, `ring_send` queueing behind the send in flight,
`answer` stopping before a file the loop sends, `owes_408`'s `sending`), and IPv6,
dual-stack, and Unix sockets. Then `sendfile` on the epoll loop on macOS:
`net_sendfile` in `shim/kqueue.c` calls `sendfile(fd, s, off, &len, NULL, 0)`, returns
`len` when it's above 0, `EAGAIN` with a partial send included, -`EAGAIN` only when
nothing went, 0 at the file's end, and `EBADF` for fd -1, which the loop's check at
start takes for sendfile being there. `net_worker_start` blocks `SIGPIPE`, as on Linux,
rather than `SO_NOSIGPIPE` on each accepted socket. `scripts/test.sh` passed twice
after it, `files` included: pipelined files, ranges, and `lsof` finding no file open
after clients leave mid-file. A 1 MB file through the same build, by wrk `-t2 -c16
-d3`, one worker, one run each, a check of the path and not a benchmark: 1.82 GB/s on
epoll with `sendfile`, 1.31 GB/s on the uring loop, which reads in pieces.

`shim/ring_epoll.c`, the ring on macOS and under Docker's seccomp profile, allocated
every send's record, small ones too. It now reuses them as `shim/uring.c` does. With
`LOOP=uring-epoll`, as above: `/bytes?n=1048576` went from 0.99 to 1.58-1.60 GB/s,
and plaintext (`bench/instructions.sh`, 2 runs) from 1.67-1.70 to 1.78-1.85 M requests
per second, 1,658-1,662 to 1,608-1,634 user instructions and 2,239-2,246 to
2,041-2,044 cycles per request, with peak RSS 1.1 MB higher.

macOS (2026-10-12): `scripts/test.sh` passes at `806f46a` with Goose `5c83a5a`, twice,
with nothing to fix: both loops, the ring over kqueue (`shim/ring_epoll.c`, with its
reused send records) and `LOOP=epoll`, through `stream`, `files`, the `SIGTERM` stop,
and the restart with `SERVER_RUNS=2` on 4 workers sharing `shim/kqueue.c`'s listener
table, then the fd limit run and `test-echo.sh`. `test-http.sh` now checks with `lsof`
that no file stays open after `files`, which passed on both loops. The peak RSS check
after `stream` still runs on Linux only. On the MacBook Pro in `docs/development.md`,
macOS 26.3.1, Apple clang 21.0.0; each run took 3 minutes.

The request path's cost, split (2026-10-12). `bench/count.sh` counts the user
instructions a server spends on exactly 10 million plaintext requests from h2load, and
repeats to within 0.1 per request, where `bench/instructions.sh` spreads by about 15.
Its totals run about 300 higher, since h2load brings fewer requests per read than wrk,
so it compares builds only. Each commit since `1e9dddb` that changed the request
path, built with Goose `5c83a5a`, one run each (1,746.1 for epoll and 1,789.2 for
io_uring at `1e9dddb`), in user instructions per request against the commit before:

| Commit | epoll | uring |
|---|---|---|
| `408edfc`, streaming | +65.9 | +54.4 |
| `eee987f`, the request's state in its slot | -20.0 | -0.2 |
| `e8d0a8d`, limits and timeouts as settings | +13.2 | +13.2 |
| `8f5b338`, the stop | +3.2 | +13.7 |
| `d80d662`, `Upgrade` | +9.0 | +1.8 |
| `cc9a9e1`, conditional `GET` and ranges | 0 | +5.0 |
| `66f28eb`, TechEmpower's routes first | -11.1 | -16.8 |
| `03c7b67`, request trailers | +9.0 | +5.8 |
| `743609f`, the `Server` field | +17.2 | +12.7 |
| `61ef340` | 0 | +0.2 |
| `a3cf843`, files | +3.9 | +10.2 |
| `806f46a`, in all | +90.3 | +100.4 |

`28c478c` removes 49.7 (epoll) and 57.5 (uring) of them, each change measured on top of
the ones before it:

- `common_fields` ends in its CRLF, so an HTTP/1.1 keep-alive response appends nothing
  after it: -29.9 and -25.1. The append that it saves picked one of three literals by
  `keep_alive`, which lives in the connection's slot.
- `answer` reads `cfg.max_body`, `max_line`, `max_fields`, and `write_buffer` once per
  call, not once per request: -6.9 and -14.5. gcc can't tell an append to `wbuf` from a
  write to `cfg`, so a read per request is a load per request. And `parse` counts the
  fields down from `max_fields`, so that the limit doesn't hold a register through its
  loop: -7.0 and -7.0.
- The trailers are sliced only from a whole chunked body: -5.9 and -10.9. Not sliced at
  all, the build measured -14.8 and -18.1; the rest is the value kept live into the
  handler.

That leaves 40.6 and 42.9 above `1e9dddb`. Resetting the handler's state to `fresh`
before each request is 9.3 and 9.4 of it: a copy of the benchmark server's 56-byte
`Transfer`, which the package can't skip without knowing whether the handler wrote it.
The rest is spread over the commits above, a few instructions each. Keeping
`keep_alive` and the stream in locals during `REQUEST` measured +5.2 and -2.1, and
stayed out. With `bench/instructions.sh`, 2 runs each, as above:

| Build | epoll user instructions | epoll cycles | uring user instructions | uring cycles |
|---|---|---|---|---|
| `1e9dddb` | 1,451-1,464 | 1,940-1,953 | 1,503-1,514 | 1,719-1,721 |
| `806f46a` | 1,546-1,577 | 1,962-1,993 | 1,599-1,609 | 1,740-1,746 |
| `28c478c` | 1,500-1,510 | 1,903-1,927 | 1,540-1,551 | 1,720-1,723 |

In `bench/run.sh`'s 4-worker cells (`bench/results/2026-10-12-cut/`, as above with
`WORKER_COUNTS=4`; 3 runs a cell, the median), `28c478c` against `1e9dddb`, both on
Goose `5c83a5a`: every cell's spread overlaps. `goose-v-cut` is `28c478c`, which
`env.txt` names, and `goose-v-before` is `1e9dddb`, which it doesn't.

| Cells, 4 workers | epoll, `28c478c` / `1e9dddb` | uring, `28c478c` / `1e9dddb` |
|---|---|---|
| plaintext, 256 / 1,024 / 4,096 connections | 0.99 / 1.00 / 1.00 | 1.00 / 1.00 / 1.01 |
| JSON, 256 / 1,024 | 1.00 / 0.99 | 0.99 / 1.00 |

The three cells that were lower before overlap now: epoll plaintext at 1,024
connections, 5.606 M (5.556-5.674 M) against 5.605 M (5.603-5.662 M); uring plaintext
at 256, 6.901 M (6.871-6.943 M) against 6.871 M (6.805-6.883 M), and at 1,024, 6.740 M
(6.682-6.775 M) against 6.722 M (6.697-6.775 M). Peak RSS was 0.2-0.9 MB higher in
every cell but uring JSON at 1,024 connections, 0.9 MB lower.

Both items that were next are done (2026-10-12): sends queued in the ring shims, and
`sendfile` on the epoll loop. Left: measuring both on the desktop, and `shim/iocp.c`'s
queue under load on Windows.

Measured on the desktop (2026-10-12): the Ryzen 7 5800X3D, WSL2 kernel 6.18.40.1, Goose
`5c83a5a`, `bench/files.sh` with `SIZES="bytes:65536 bytes:1048576"`: `/bytes`, sent in
16 KB pieces, the server on CPU 0 or CPUs 0-3, wrk on CPUs 4-15 with 12 threads and 96
connections, 3 runs of 10 s, medians in GB/s. Before is `4a65d96`; results in
`bench/results/2026-10-12-bytes`.

| Response | epoll | io_uring | emulation | `4a65d96` epoll | `4a65d96` io_uring |
|---|---:|---:|---:|---:|---:|
| 64 KB, 1 worker | 2.06 | 2.58 | 1.15 | 2.03 | 1.09 |
| 64 KB, 4 workers | 6.67 | 7.72 | 5.21 | 6.72 | 3.59 |
| 1 MB, 1 worker | 2.49 | 2.51 | 1.20 | 2.51 | 1.08 |
| 1 MB, 4 workers | 8.63 | 8.55 | 5.42 | 8.62 | 4.02 |

- io_uring went from 0.43-0.54 times epoll to 1.0-1.25 times.
- `perf record` of CPU 0 under io_uring at 1 MB: 86% kernel, 11.5% of it zeroing new
  pages for TCP's send buffers (`sk_page_frag_refill` to `clear_page_erms`) and 8.5%
  copying into them; libc 11.6%, the copy into the shim's send record; Goose 2.7%.
- The emulated ring runs at half of epoll's rate on these; it's the fallback where
  io_uring is blocked, and wasn't measured before.

`shim/iocp.c`'s queue on Windows, the same desktop, `bench/oha.sh` with 20,000
requests of `/bytes?n=1048576` over 256 connections, 3 runs, against `e9035fc`, the
commit before the queue (`bench/results/2026-10-12-iocp-large`): with 1 worker, 960-1,444
requests per second against 1,104-1,638; with 4, 4,473-5,056 against 5,813-6,685, at
690-790 µs of kernel time per request against 480-550. A loss of about 25% with 4
workers, not yet explained; every build ran about 30% slower in round 2 than in round 1,
so the 1-worker numbers say little.

Checked against Tina's tests (2026-10-12). Tina's HTTP server (`a2e8d4d`) tests its
parser, router, and connection states in `test_*` procedures, and reports 33 of 33 on
uNetworking's h1spec. Its suite and ours compared, by reading both, found:

- Fixed: the router's `otherwise` answered a method the server doesn't know with 404
  or 405; it now answers 501 (RFC 9110 §9.1). `OPTIONS *` got 404 through the router;
  now 204 (§9.3.7). Both chunk-size parsers refused whitespace before an extension's
  `;`, which RFC 9112 §7.1.1 allows (BWS); now taken, while a size with trailing
  whitespace and no extension is still 400.
- Decided (2026-10-12): the router refuses a path with a `.` or `..` segment, escaped
  or not, or an escaped control byte, with 400 from `otherwise`, and a literal segment
  matches an escape of an unreserved character, as Tina's canonicalizer does before
  matching. Parameters stay encoded slices, so the router allocates nothing.
- Added: `http::authority`, an absolute-form target's authority before `Host` (RFC 9112
  §3.2.2); `scripts/http_client.py`'s `forms` (absolute-form and `OPTIONS *`, out of
  `tfb`, which TechEmpower's requests alone now make) and `max-conns`; and unit cases
  for a tab separator, whitespace before the first field line, an invalid name, bytes
  before the request line, a bare CR, obs-text, and four malformed `Content-Length`s,
  among them h1spec's 4 cases that no test covered.
- Where Tina differs and we keep ours, as the RFCs have it: it refuses absolute-form,
  HTTP/1.0, and obs-text, and answers `Transfer-Encoding: gzip` with 501 where RFC 9112
  §6.3 asks for 400.
- `pipeline` now takes a 405 with `Connection: close` from a server other than Goose,
  which RFC 9112 §9.6 allows; Goose still has to drain the body and stay open.

`scripts/test.sh` passed on macOS and in Docker on all three Linux loops after them.

Tagged `v0.2.0` at `c633dee` (2026-10-12), which the README's Quick start imports. The
Quick start, in a directory of its own on macOS, fetched the tag from GitHub with Goose
`5c83a5a`, built, and served 200 at `/` and 404 elsewhere.

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
- Not yet: an event for a connection closed mid-stream: the state is flat data, with
  nothing to free. (Request trailers came later, in `Event.trailers`.)

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
      `serve_epoll` (2026-10-12, Linux and macOS, and on Windows by Ctrl+Break)
- [x] Every item above has a check in `scripts/http_client.py` or `test/test_http.goose`
      (2026-10-12; item 11's on Linux, macOS, and Windows)
- [x] The benchmark routes, served through the handler, keep their rate in
      `bench/run.sh`'s closest cells within the runs' spread (2026-10-12, `28c478c`:
      every 4-worker cell's spread overlaps `1e9dddb`'s; see Progress)
