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

### C behind a thin shim (task 002)

Goose calls C directly through `extern fn`, but C can't call Goose back at runtime: there
are no runtime function pointers (§7.5), and `export fn` calls must stay on the thread
that called `goose_init` (§7.11). So the shim only wraps calls that return: sockets,
epoll, `errno`, and the clock, in `shim/net.h`, and later io_uring in `shim/uring.h`.
The shim also hides layouts that differ by architecture, such as `struct epoll_event`,
which is packed on x86-64 but not on ARM.

Anything that needs a callback, such as llhttp, libuv, or a C HTTP server, is out.

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
