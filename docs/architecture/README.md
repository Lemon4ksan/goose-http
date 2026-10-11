# Architecture

Decisions for the server. Each says who decided it and when. A proposed decision stands
until the task named beside it confirms or replaces it.

## Settled

- **A Goose program, not a Goose feature.** This repository uses Goose as the pinned
  checkout ships it. Gaps go to `docs/goose-findings.md` (Kait, 2026-10-10).
- **Simple first, then io_uring.** The first server is an epoll loop per core; io_uring
  follows once epoll is measured (Kait, 2026-10-10).
- **Linux is the benchmark platform.** The fast paths (`SO_REUSEPORT`, epoll, io_uring)
  are Linux APIs, and that is where the competing servers are compared. Development runs
  on WSL2 Ubuntu.
- **C behind a thin shim.** Goose calls C directly through `extern fn`, but C can't call
  Goose back at runtime: there are no runtime function pointers (§7.5), and `export fn`
  calls must stay on the thread that called `goose_init` (§7.11). So `shim/net.h` only
  wraps calls that return, and returns `-errno` instead of `-1` and `errno`. It covers
  sockets, epoll, coarse clocks, and `strerror`; `shim/uring.h` covers io_uring
  ([below](#the-io_uring-loop-task-005)).
  Anything that needs a callback, such as llhttp, libuv, or a C HTTP server, is out
  (confirmed by task 002, 2026-10-10). Details:
  - The shim owns the kernel structures whose layout varies by architecture.
    `epoll_wait` fills a local `struct epoll_event` array, which is packed on x86-64 and
    padded on arm64, and copies it into `sys::Event`, a struct of the program's own.
  - `send` passes `MSG_NOSIGNAL`, so a write to a closed connection is `-EPIPE`, not a
    `SIGPIPE` that ends the process. There is no signal handler to install.
  - There is no `writev`: spec §7.10 doesn't let a list of slices cross to C. Responses
    are built into one buffer and sent with one `send`.

- **One event loop per core, nothing shared.** Goose workers share no memory: a
  `thread_fn` is compiled as its own program, takes flat arguments, and copies the
  globals it uses (spec §11.2). The fastest Rust plaintext servers use the same shape
  (proposed for task 003, confirmed by it, 2026-10-10):
  - `main` spawns one worker per `hardware_threads()`, or `WORKERS` if set, and passes
    each only the port.
  - Each worker opens its own listener with `SO_REUSEPORT`, so the kernel spreads
    connections across workers, and runs its own edge-triggered epoll loop.
  - A connection belongs to one worker for its life, in a slot of that worker's
    `reusable` pool; its epoll tag is the slot. A table indexed by fd was rejected: fds
    are numbered across the process, so every worker's table would grow to the highest
    fd of all of them.
  - The buffers belong to the worker, not the connection: an 8 KB read buffer, which
    holds the longest request head whole, and an 8 KB write buffer, which takes the
    responses to a read's worth of pipelined requests (16 TechEmpower responses are
    about 2 KB). The connection being driven uses them. Nothing grows per request: the
    parser returns slices of the read buffer, and the JSON body is built in a fixed array
    on the native stack.
  - Between events, a slot holds about 50 bytes and two slices into the worker's
    `reusable[]` spill pool: the start of a request not yet whole, and responses the
    socket didn't take, both empty almost always (task 009, 2026-10-10). Slots of 16 KB
    with the buffers inline were rejected: every slot was written whole, so 4,096
    connections held 66 MB, against 2.5 MB now and 55 MB for vanilla-epoll, which
    allocates its buffers per connection and writes only what it uses.
  - A worker holds at most 16,384 connections, so one worker can take TechEmpower's
    largest run alone. At the
    limit, and when `accept` fails with `EMFILE` or `ENFILE`, the worker stops accepting
    and retries after each close and once a second. Waiting clients keep their place in
    the listen backlog rather than being refused, and `EMFILE` is logged once per pause.
- **HTTP/1.1, the parts benchmarks use** (proposed for task 003, confirmed by it,
  2026-10-10):
  - Keep-alive by default, `Connection: close` honored, and HTTP/1.0 kept alive only
    when it asks.
  - Pipelining: every complete request in the read buffer is answered, and the responses
    go out in one `send`. When the write buffer fills, the server sends it and answers
    the rest.
  - `Content-Length` request bodies are read and dropped as they arrive. Chunked bodies
    are accepted in HTTP/1.1 (task 009, for HttpArena's `baseline` profile, 2026-10-10):
    the message must fit in the 8 KB read buffer with its head, or it gets 413. So must
    a `Content-Length` body the route reads, which only `POST /baseline11` does. A
    chunked body the route reads is decoded in place. Another transfer coding gets 501, and `Transfer-Encoding`
    with `Content-Length`, or in HTTP/1.0, gets 400.
  - Routes: `/plaintext` and `/json` for TechEmpower's tests, and `/baseline11` and
    `/pipeline` for HttpArena's (`bench/httparena/goose`).
  - Lines end in CRLF only; a bare LF is 400. HTTP/1.1 needs one `Host`.
  - Limits, in `src/http.goose`: a 4 KB request line (414), an 8 KB head or 100 fields
    (431), and a 1 MB body (413).
  - A refused request closes the connection after the response. The server shuts down
    its side and drops what the client still sends for up to 2 s, so the refusal isn't
    lost to a reset.
  - Timeouts, against slow clients: a request has 10 s from its first byte to arrive
    whole (else 408), a response 10 s without progress to leave, and an idle connection
    60 s. A sweep once a second enforces them.
  - The `Date` header is rendered when the second changes, at most once a second per
    worker, after the worker's `epoll_wait` returns. Responses are literals around the
    date and the length.

## Proposed

### The io_uring loop (task 005)

`LOOP=uring scripts/build.sh` builds the server with an io_uring loop
(`src/uring.goose`) in place of the epoll loop; `src/app.goose` holds what both share.
The epoll loop stays the default until task 005 measures both, and stays buildable and
tested either way (2026-10-11):

- `shim/uring.h` wraps liburing 2.14, whose helpers are static inline functions that
  `extern fn` can't bind, and needs Linux 6.1. Each worker owns a ring, created with
  `IORING_SETUP_SINGLE_ISSUER` and `IORING_SETUP_DEFER_TASKRUN`: the kernel completes
  requests only while the worker waits, and each wait submits everything queued since
  the last one.
- A multishot accept takes the listener's connections, and a multishot receive per
  connection fills the ring's provided buffers, 1,024 of 4 KB per worker. A receive
  that finds no buffer left ends, and the loop queues it again.
- The ring owns every buffer the kernel touches after a call returns. The kernel reads a
  send's bytes and writes a receive's after the call that queued them, and spec §7.10
  forbids C to keep a Goose argument past a call. So the loop copies each receive out of
  a provided buffer into its read buffer, and the shim copies each send's bytes into a
  buffer of its own. The epoll loop makes neither copy; the kernel's own copy into and
  out of the socket is the same in both.
- A connection has one send in flight, which keeps its responses in order. Responses
  answered meanwhile wait in the spill pool. Past 64 KB waiting, the loop cancels the
  connection's receive and holds what still arrives until the client reads, as the epoll
  loop stops reading when a send would block.
- A request's tag is the connection's slot and a generation, so a completion that
  arrives after its connection closed isn't taken for the slot's next connection.
- Closing a connection queues a cancel of its requests and, linked after it, the close.
  A queued request holds a reference to the socket, so a `close` alone would leave the
  connection open.
- At 16,384 connections the worker cancels its accept, and closes any connection
  accepted before the cancel lands. After `EMFILE` or `ENFILE` it queues the accept
  again after a close or at the next sweep, so waiting clients keep their place in the
  backlog, as with epoll.
