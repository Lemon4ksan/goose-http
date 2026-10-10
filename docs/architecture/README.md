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

## Proposed

### One event loop per core, nothing shared (task 003)

Goose workers share no memory: a `thread_fn` is compiled as its own program, takes flat
arguments, and copies the globals it uses (spec §11.2). The fastest Rust plaintext
servers use the same shape, so the server leans into it:

- `main` spawns one worker per `hardware_threads()`, or `WORKERS` if set.
- Each worker opens its own listening socket with `SO_REUSEPORT`, so the kernel spreads
  connections across workers, and runs its own edge-triggered epoll loop.
- A connection belongs to one worker for its life. Its state is a flat struct with
  fixed-size read and write buffers, in a `reusable` pool or a table indexed by fd.
- A request's data lives in the scope that handles it, so the data stacks free it when
  the response is written.

### HTTP/1.1, the parts benchmarks use (task 003)

- Keep-alive by default, and `Connection: close` honored.
- Pipelining: every complete request in the read buffer is parsed, and their responses
  go out in one `write`.
- `Content-Length` request bodies only. A chunked request gets 501.
- Limits on the request line, the header block, and the body, refused with 414, 431, and
  413.
- A `Date` header rendered once a second per worker, and static response templates.

### io_uring later (task 005)

Multishot accept and receive, provided buffer rings, and batched submission, through a
shim over liburing, whose helpers are mostly inline functions that `extern fn` can't bind
directly. It replaces the epoll loop only if task 005 measures it faster.
