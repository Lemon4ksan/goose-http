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
  sockets, epoll, coarse clocks, and `strerror`; io_uring will get `shim/uring.h`.
  Anything that needs a callback, such as llhttp, libuv, or a C HTTP server, is out
  (confirmed by task 002, 2026-10-10). Details:
  - The shim owns the kernel structures whose layout varies by architecture.
    `epoll_wait` fills a local `struct epoll_event` array, which is packed on x86-64 and
    padded on arm64, and copies it into `sys::Event`, a struct of the program's own.
  - `send` passes `MSG_NOSIGNAL`, so a write to a closed connection is `-EPIPE`, not a
    `SIGPIPE` that ends the process. There is no signal handler to install.
  - There is no `writev`: spec §7.10 doesn't let a list of slices cross to C. Responses
    are built into one buffer per connection and sent with one `send`.

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
  - A slot is a flat struct of about 16 KB: an 8 KB read buffer, which holds the longest
    request head whole, and an 8 KB write buffer, which takes the responses to a read's
    worth of pipelined requests (16 TechEmpower responses are about 2 KB). Nothing grows
    per request: the parser returns slices of the read buffer, and the JSON body is
    built in a fixed array on the native stack.
  - A worker holds at most 16,384 connections, so one worker can take TechEmpower's
    largest run alone: 270 MB of slots at most, committed as connections arrive. At the
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
  - `Content-Length` request bodies are read and dropped. Any `Transfer-Encoding` gets
    501, since the end of the body is then unknown.
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

### io_uring later (task 005)

Multishot accept and receive, provided buffer rings, and batched submission, through a
shim over liburing, whose helpers are mostly inline functions that `extern fn` can't bind
directly. It replaces the epoll loop only if task 005 measures it faster.
