# Changelog

What each tag adds. Each release names the Goose compiler it was built and tested with.

## v0.4.2 (2026-10-20)

Bearer tokens and header lines scanned 16 bytes at a time. Goose master `f114b5a`,
goose-hash `v0.0.4`, goose-tls `v0.0.1`, and goose-compress `v0.1.1`.

- `http::bearer` checks a token's token68 bytes, and `http::field_at` finds a line's
  colon and its end, with std's `find_any`, where each scanned a byte at a time. What
  they accept is unchanged: the tests try a bad byte and an `=` at every position of
  tokens up to 48 bytes. On tier C, whose tokens are 560 bytes, a request costs about
  7,600 fewer user instructions on goose-rest, which calls both, and 3,100 fewer on
  this repository's REST server, which calls `field_at`; plaintext's count is
  unchanged.
- The REST benchmark server checks tier C's JWT shape with `find_any` too, as
  goose-rest's does, so both servers do the same work outside the framework: 6,100
  fewer user instructions per tier C request. Tier C templated runs 5-8% faster on
  both.
- Each test program gets a `TMPDIR` of its own, where a test that listens on a Unix
  socket puts it, so the suite passes from a checkout on WSL's `/mnt/c`.

## v0.4.1 (2026-10-20)

`v0.4.0`'s benchmark server back to `v0.3.7`'s cost. The package itself is unchanged.
Goose master `f114b5a`, goose-hash `v0.0.4`, goose-tls `v0.0.1`, and goose-compress
`v0.1.1`.

- The benchmark server echoes a WebSocket from a function outside its inlined handler,
  and keeps each WebSocket in a pool, with only an index in the request state. Inside
  the handler, the WebSocket's frame loop changed how Goose inlined the event loop's
  call to it, and cost about 140 user instructions per plaintext request that never
  upgrades. Plaintext counts 1,609-1,610 on epoll and 1,648-1,661 on io_uring, as
  `v0.3.7` does.
- The benchmark server's TLS listener is a build of its own, `server/server_tls.goose`
  (`TLS=1` in `scripts/build.sh`), so the plaintext epoll server doesn't map OpenSSL:
  3.8 MB of peak RSS where `v0.4.0`'s held 6.0 MB. HttpArena's image starts the TLS
  build when a certificate is mounted.

## v0.4.0 (2026-10-19)

HTTP/2 over TCP (h2c), HTTPS, WebSocket, outbound connections, `http::run`, and lanes
in the package. Goose master `f114b5a`, since no release has
[aardappel/goose#37](https://github.com/aardappel/goose/pull/37) yet, which `http::run`
and `http::lane_open` need; goose-hash `v0.0.4` for WebSocket, goose-tls `v0.0.1` for
TLS, and goose-compress `v0.1.1`.

- h2c, HTTP/2 with prior knowledge, in the epoll, kqueue, and io_uring loops and the
  ring's emulation: HPACK and HTTP/2's frames written in Goose, `Config.h2c` for the
  main port, and `Config.h2_max_streams`, `h2_stream_window`, and `h2_conn_window`.
  Handlers don't change: each stream is an exchange. Expect is answered on a stream, a
  handler that ends keep-alive ends the connection with a GOAWAY, and flood budgets are
  set from what h2load, nghttp, and curl spend. It passes h2spec, 146 of 146 cases, and
  147 of 147 with `-S`. Translating a response's head into HPACK takes one pass over
  it, and lowercases names in place
  ([api](docs/api.md#several-ports-and-h2c)).
- Several listeners per loop: `Config.listeners` adds up to `http::MAX_LISTENERS` (3)
  ports on the same address, each an `http::Listener { port, h2c, tls }`, served by the
  same workers. `http::ring_listeners()` says how many a ring takes; IOCP takes one.
- HTTP/1.1 over TLS 1.3 in `serve_epoll` on Linux and macOS, from the module
  `http.tls` with goose-tls over OpenSSL 3: `Config.tls` or a `Listener`'s `tls`,
  `http::tls_server(ctx)` per worker, and `http::release` after the loop
  ([api](docs/api.md#https)).
- WebSocket (RFC 6455) in the module `http.websocket`, over HTTP/1.1 and TLS:
  `http::ws_upgrade`, `ws_read`, `ws_send`, and `ws_close`, with pings, Close, and the
  protocol's errors handled by the package. It passes Autobahn's test suite, but for
  the extension sections ([api](docs/api.md#websocket)).
- Outbound connections, TCP or a Unix socket: `http::connect`, `send_all`, and `recv`
  with time limits block a lane's thread; `http::connect_start`, `wait_socket`,
  `connected`, `send`, and `recv` drive a socket from a handler on `serve_epoll`, where
  the exchange waits for it as for mail, with `WAKE` and `http::SOCKET_READY`
  ([api](docs/api.md#outbound-connections)).
- `http::run(cfg, worker)` spawns the workers, up to two values passed to each beside
  its `Config`, and returns once all have returned.
- Lanes are in the package: `http::lane_open` spawns a lane's threads, each with a box,
  `http::lane(box)` is a thread's loop, `lane_send` and `lane_send_value` send to the
  least busy, `lane_stop` stops and waits for them, `lane_of(box)` is a lane of one box
  for a test, and `lane_spawn` lets a package start lane threads of its own
  ([api](docs/api.md#lanes)).
- A `later` while waiting isn't configured (`Config.mail_slots` and `max_waiting` 0)
  gets `TIMEOUT` on the loop's next pass, and its address takes no message.
- The benchmark server serves h2c on its port + 2 (`H2C_PORT`), TLS on its port + 1
  with `LOOP=epoll` (`TLS_CERT`, `TLS_KEY`, `TLS_PORT`), `/ws`, and HttpArena's
  `/baseline2`. `bench/h2c.sh` runs HttpArena's h2c profiles.
- Removed: placement (`http::place_load`, seats, and `docs/tuning.md`), which hadn't
  been measured to help, and 32-bit ARM. aarch64 builds with Goose's default stack
  reserve.

Not yet: TLS and `wait_socket` on `http::serve`'s loops (io_uring, its emulation, and
IOCP) fail with `ENOSYS`, so Windows has no TLS; h2 over TLS and the kernel's TLS are
still to come; h2c is untested on Windows; host names other than `localhost` aren't
resolved.

## v0.3.7 (2026-10-19)

A lane stops with a flag a full box can't refuse, and threads can be placed on cores
from a file per machine, as an experiment. Goose `v2026.2` (`3ee3871`).

- `http::mail_stop(b)` stops a box from any thread, and `http::mail_stopped(b)` tells
  its owner that it is stopped and empty, with every message sent before the stop
  taken. A send to a stopped box returns `STALE`, `mail_live` is false, and
  `mail_slot_size` is -1. After a stop, `mail_wait` returns at once: true while
  messages are pending, false once the box is empty
  ([api](docs/api.md#answers-that-wait)). `examples/later` stops its lane.
- `http::mail_queued(to)` gives how many messages a box holds, from any thread, for
  picking the least busy of several.
- Placement, experimental until measured on real cores: a placement file, read by
  `http::place_load()` from `--place`, `--place=`, or `GOOSE_PLACE`, or from a path the
  program gives, maps roles to cores, `each` core of a set, `within` a set, or one
  `core`, with `exclusive` sets, `low` priority, and `incoming` (`SO_INCOMING_CPU`).
  Workers take their seats from `Config.place`, `http::place_ref(place)`, by
  `Config.role`, `"workers"` by default, and any other thread with
  `http::place_seat` and `http::take_seat`. A file's count for the workers' role
  replaces `Config.workers`. Nothing about the hardware stops the start: each
  shortfall prints a warning and the program runs without it; a file that doesn't
  parse ends it with exit code 2. Without a file, nothing changes
  ([tuning](https://github.com/kaitk/goose-http/blob/placement/docs/tuning.md), on the
  branch `placement` since it left `main`).
- `docs/tuning.md` covers worker counts, placement files, what each platform does, and
  what has been measured: on an M1 Pro, no layout beat the default.
- `bench/pinning.sh` measures a short route's latency beside a busy CPU lane in each
  layout of workers and lane.

## v0.3.6 (2026-10-16)

The store reads numbers and records by value, and the release builds with Goose
`v2026.2` (`3ee3871`) and goose-compress `v0.1.1`.

- `http::store_i64`, `store_u32`, `store_u8`, and `store_f64` read a little-endian
  value at a byte offset of a blob, and `http::store_record<T>(b, i, read)` reads record
  `i` of a flat fixed-size `T` through a C function the program declares for `T`. Each
  returns the value and whether the read was in range, with no buffer. A record read
  costs 2.6 ns on an M1 Pro, against 10.3 ns for `store_append` and `from_bytes`
  ([api](docs/api.md#the-store)).
- `docs/api.md` documents the store, `store_append` included.
- The REST benchmark server's application, its records, loaders, writers, templates,
  and tier D's body work, is `bench/rest/goose/app.goose`, which goose-rest's benchmark
  server imports.
- goose-compress `v0.1.1`, the same encoders built with `v2026.2`.

## v0.3.5 (2026-10-16)

A part of a multipart body read whole comes as slices of it. Goose `v2026.1` (`ac759c3`).

- `http::find_part(req, body, name)` gives the first part named `name` of a whole
  `multipart/form-data` body: its content and its head fields, both slices of the body,
  and a status, `PART_FOUND`, `PART_ABSENT`, `PART_TYPE`, or `PART_BAD`. It follows
  `each_part`'s rules, and doesn't read the parts after the one it finds.

## v0.3.4 (2026-10-16)

The emulated ring serves every connection under load. Goose `v2026.1` (`ac759c3`).

- The ring's emulation, over epoll where io_uring isn't available and over kqueue on
  macOS, collects the kernel's events on every wait. It returned the completions of its
  busy connections without them, so under load a connection waiting to send or to read
  could wait for seconds.

## v0.3.3 (2026-10-15)

JSON strings are written faster, an upgraded connection is read while it waits, and the
tests follow Goose's own convention. Goose `v2026.1` (`ac759c3`).

- `http::json_string` looks for a byte to escape 16 bytes at a time and appends the
  bytes between escapes whole. Its output equals `json::format_string`'s, and the
  examples and the benchmark servers write their JSON strings with it.
- `http::json_string` writes a newline, tab, carriage return, backspace, and form feed
  in their short forms (`\n`, not `\u000a`), as `json::format_string` does.
- An upgraded connection's bytes keep coming as `BODY` while its exchange waits with
  `later`, where they waited for the wait to end.
- The architecture is two pages: how goose-http works, for users, and the decisions
  behind it, for contributors.
- The tests are small programs by area under `test/`, each checked against a golden
  file, and `test/run_tests.py` runs them.

## v0.3.2 (2026-10-15)

A mailbox of one slot is refused, goose-compress is imported by its tag, and the
documentation is split by topic. Goose `v2026.1` (`ac759c3`).

- `http::mail_open` refuses fewer than two slots with `EINVAL`, and a `Config.mail_slots`
  of 1 stops the loop with that error. A box of one slot reported `SENT` for every send,
  overwriting the message not yet taken.
- `http.compression` imports goose-compress at `v0.1.0`, the same code as the commit
  v0.3.1 named. A program that compresses declares it at that tag.
- The API reference, server patterns (request bodies, long responses, mail, slow work,
  limits, and shared state), development setup, and known issues are pages of their
  own.
- Builds with the official Goose release that `scripts/goose.sh` pins.

## v0.3.1 (2026-10-14)

A send to an exchange that no longer waits says so at once, so a service can stop
working for a client that has gone. Goose `46356c2`.
[Release notes](https://github.com/kaitk/goose-http/releases/tag/v0.3.1).

- `http::mail_send` returns `STALE` for a reply to an exchange whose client closed or
  whose wait timed out, where it returned `SENT` and the loop dropped the message.
- `http::mail_live(address)` checks, from any thread and without sending, whether an
  exchange still waits.
- A reply sent in pieces is never refused between pieces.
- Boxes of a program's own can track keys: `http::mail_open(slots, size, waker,
  live_keys, key_shift)` and `http::mail_mark`. The new parameters are optional.
- REST strings' JSON escapes are found 16 bytes at a time.

## v0.3.0 (2026-10-14)

A revised API, compression, files sent without copying on every loop, and a shared
store for immutable data. Goose `46356c2`.
[Release notes](https://github.com/kaitk/goose-http/releases/tag/v0.3.0), with the
migration from `v0.2.0`.

- Precompressed Brotli, Zstandard, and gzip files, and gzip, deflate, and Zstandard on
  the fly through `http.compression`.
- Large files sent without copying on io_uring, its epoll emulation, and IOCP.
- `http.store`: immutable byte blobs shared by every worker.
- `insert_field`, `file_path`, `fail_multipart`, typed mail helpers, and
  `exit_on_error`.
- API changes: request helpers take `const Request&`; `BodyReader`, multipart `Part`,
  and `Stream` framing are enums; `query_int` returns `(value, found)`;
  `stop_on_signals` returns `http::Error` and `mail_open` returns `(Box, Error)`.

## v0.2.0 (2026-10-12)

The HTTP/1.1 essentials: a strict parser, the router, bodies and responses of any size,
conditional and range requests, static files, cookies and `Basic` authorization, forms
and multipart, limits and timeouts, answers that wait, the client's address, IPv6, and
Unix sockets, on io_uring, epoll, kqueue, and IOCP.

## v0.1.0 (2026-10-11)

The first tag: an event loop per worker, `http::serve` (io_uring, IOCP, or a ring over
kqueue) and `http::serve_epoll`, with keep-alive. Requests and responses
are fixed in size: no header lookup, bodies read in pieces, or streamed responses.
