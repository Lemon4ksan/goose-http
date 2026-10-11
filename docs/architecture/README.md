# Architecture

Decisions for the server. Each says when it was decided. A proposed decision stands
until the task named beside it confirms or replaces it.

## Settled

- **A Goose program, not a Goose feature.** This repository uses Goose as the pinned
  checkout ships it. Gaps go to `docs/goose-findings.md` (2026-10-10).
- **Simple first, then io_uring.** The first server is an epoll loop per core; io_uring
  follows once epoll is measured (2026-10-10).
- **Linux is the benchmark platform.** The fast paths (`SO_REUSEPORT`, epoll, io_uring)
  are Linux APIs, and that is where the competing servers are compared. Development runs
  on WSL2 Ubuntu.
- **C behind a thin shim.** Goose calls C directly through `extern fn`, but C can't call
  Goose back at runtime: there are no runtime function pointers (§7.5), and `export fn`
  calls must stay on the thread that called `goose_init` (§7.11). So `shim/net.c` only
  wraps calls that return, and returns `-errno` instead of `-1` and `errno`. It covers
  sockets, epoll, coarse clocks, and `strerror`; `shim/uring.c` covers io_uring
  ([below](#the-io_uring-loop-task-005)), and `shim/kqueue.c` is `shim/net.c` for macOS,
  returning the same Linux codes ([below](#the-platform-and-its-error-codes-task-006)).
  On Windows, `shim/net_win.c` is `shim/net.c` over Winsock, and `shim/iocp.c` is
  `shim/uring.c` over a completion port. `shim/iocp.c` is the one shim that isn't thin:
  it emulates io_uring's multishot requests with reference-counted records, and a
  callback on a system wait thread hands accepts to each worker's port. The callback is
  C calling C, so Goose still never runs on a thread it didn't start.
  Anything that needs a callback, such as llhttp, libuv, or a C HTTP server, is out
  (confirmed by task 002, 2026-10-10). Details:
  - `goose build` compiles the shim as C files of their own, which the package's
    sidecar names (`http.build`), and links them (task 010, 2026-10-11; a package's
    sidecar since task 011). The C sees
    none of the generated C, so it spells out the layouts it shares with Goose. Headers
    spliced in with `--include` were dropped: they needed `-D_GNU_SOURCE` from the
    command line and an `-o` with a directory, two compiler findings. A sidecar's
    `c_sources_linux`, `_macos`, and `_windows` keys pick each platform's shim with no
    conditional compilation in Goose.
  - The shim owns the kernel structures whose layout varies by architecture.
    `epoll_wait` fills a local `struct epoll_event` array, which is packed on x86-64 and
    padded on arm64, and copies it into `http::Event`, a struct of the package's own.
  - `send` passes `MSG_NOSIGNAL`, so a write to a closed connection is `-EPIPE`, not a
    `SIGPIPE` that ends the process. There is no signal handler to install. Windows has
    no `SIGPIPE`, and such a write is `-ECONNRESET` there.
  - There is no `writev`: spec §7.10 doesn't let a list of slices cross to C. Responses
    are built into one buffer and sent with one `send`.

- **One event loop per core, nothing shared.** Goose workers share no memory: a
  `thread_fn` is compiled as its own program, takes flat arguments, and copies the
  globals it uses (spec §11.2). The fastest Rust plaintext servers use the same shape
  (proposed for task 003, confirmed by it, 2026-10-10):
  - The program spawns `http::worker_count(cfg)` workers, `Config.workers` or by default
    one per `hardware_threads()`, and passes each a copy of the settings, one flat
    struct (`Config`, 2026-10-11); the benchmark server sets `Config.workers` from
    `WORKERS`. On macOS the default is one worker per performance core, and each loop
    gives its worker the user-interactive QoS class, which keeps it on those cores:
    Apple Silicon has no CPU affinity (2026-10-11).
  - Each worker opens its own listener with `SO_REUSEPORT`, so the kernel spreads
    connections across workers, and runs its own edge-triggered epoll loop. On macOS and
    Windows the workers share one listener instead
    ([below](#the-platform-and-its-error-codes-task-006)).
  - A connection belongs to one worker for its life, in a slot of that worker's
    `reusable` pool; its epoll tag is the slot. A table indexed by fd was rejected: fds
    are numbered across the process, so every worker's table would grow to the highest
    fd of all of them.
  - The buffers belong to the worker, not the connection: an 8 KB read buffer, which
    holds the longest request head whole, and a write buffer that takes 8 KB of
    responses before the server sends them, a read's worth of pipelined requests (16
    TechEmpower responses are about 2 KB). The write buffer is a growable array, so a
    response of any size goes into it whole, and what the socket doesn't take goes to
    the spill pool, as any response does (2026-10-11). The connection being driven
    uses them. Nothing grows per request in the benchmarks: the parser returns slices
    of the read buffer, and the JSON body is built in a fixed array on the native
    stack. The write buffer keeps the pages its largest response touched.
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
    go out in one `send`. Past 8 KB of responses, the server sends them and answers
    the rest.
  - A request body that fits in the 8 KB read buffer with its head is answered once
    it's whole, and the handler gets it; a longer `Content-Length` body is dropped as
    it arrives, and the handler gets an empty one (task 011, 2026-10-11). Chunked
    bodies are accepted in HTTP/1.1 (task 009, for HttpArena's `baseline` profile,
    2026-10-10): the message must fit in the read buffer with its head, or it gets
    413, and the body is decoded in place. Another coding before chunked gets 501.
    A `Transfer-Encoding` whose last coding isn't chunked, as RFC 9112 §6.3 requires, or
    that's malformed, with `Content-Length`, or in HTTP/1.0, gets 400 (2026-10-11).
  - Routes: `/plaintext` and `/json` for TechEmpower's tests, `/baseline11` and
    `/pipeline` for HttpArena's (`bench/httparena/goose`), and `/bytes?n=N`, N bytes
    up to 16 MB, for testing large responses.
  - Lines end in CRLF only; a bare LF is 400. HTTP/1.1 needs one `Host`.
  - Limits: a 4 KB request line (414), an 8 KB head or 100 fields (431), and a 1 MB
    body (413). The head and body limits, the timeouts, and the buffer sizes are
    settings (`Config`); the rest are constants in `message.goose`.
  - A refused request closes the connection after the response. The server shuts down
    its side and drops what the client still sends for up to 2 s, so the refusal isn't
    lost to a reset.
    The sweep's 408 goes the same way, so no loop closes a socket with that send in
    flight: Windows' `closesocket` aborts it.
  - Timeouts, against slow clients: a request has 10 s from its first byte to arrive
    whole (else 408), a response 10 s without progress to leave, and an idle connection
    60 s. A sweep once a second enforces them.
  - The `Date` header is rendered when the second changes, at most once a second per
    worker, after the worker's `epoll_wait` returns. Responses are literals around the
    date and the length.

## Proposed

### The io_uring loop (task 005)

The io_uring loop (`http::serve`, `uring.goose`) is the default on Linux, and the epoll
loop (`http::serve_epoll`, `epoll.goose`) stays buildable and tested as `LOOP=epoll`
(decided 2026-10-11); `http.goose` holds what both share. Task 005's matrix on the x86 machine of `docs/results.md` had the
io_uring loop 11% to 21% ahead in every cell, with the server's CPUs saturated, and
task 011 found 9% to 24% with every shim compiled afresh (2026-10-11). Against
it:

- In Docker Desktop's VM on an M1 Pro (task 012), the epoll loop led by 4% to 8% in
  plaintext and tied in JSON, in cells where wrk, not the server, used its CPUs up.
- Docker's default seccomp profile blocks io_uring, so the HttpArena image builds the
  epoll loop, and `bench/build.sh` builds both, as `goose` and `goose-uring`. The
  io_uring loop runs there too since task 011, over the emulation below, but that's
  the epoll loop with copies added.
- Its peak RSS is 4 to 5 times the epoll loop's, about 10 MB against 2.4 MB with 4
  workers.

Going back is one line of `scripts/build.sh`, if a server-bound run on another machine
puts the epoll loop ahead. On Windows the io_uring loop is the only one, over
`shim/iocp.c` ([below](#the-platform-and-its-error-codes-task-006)):

- `shim/uring.c` wraps liburing 2.14, whose helpers are static inline functions that
  `extern fn` can't bind, and needs Linux 6.1. Each worker owns a ring, created with
  `IORING_SETUP_SINGLE_ISSUER` and `IORING_SETUP_DEFER_TASKRUN`: the kernel completes
  requests only while the worker waits, and each wait submits everything queued since
  the last one.
- A multishot accept takes the listener's connections, and a multishot receive per
  connection fills the ring's provided buffers, 256 of 4 KB per worker, as many as a
  wait's batch of completions, which served as fast as 1,024 with half the peak RSS
  (task 005, and again in task 011 with the shim compiled afresh). A receive
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
  The shim queues the rest of a short send itself, so it keeps a generation per fd as
  well, which `ur_close` advances: a rest left over from a closed connection is
  reported cancelled, never sent to a later connection that got the same fd.
- Closing a connection queues a cancel of its requests and, linked after it, the close.
  A queued request holds a reference to the socket, so a `close` alone would leave the
  connection open.
- Where `io_uring_setup` fails, `ur_create` returns `shim/ring_epoll.c`'s emulation of
  the ring instead (task 011, 2026-10-11), as libuv falls back from io_uring to epoll:
  under Docker's default seccomp profile, with `io_uring_disabled` set, or on a kernel
  before 6.1. The emulation is written against the shim's own `net_epoll_*` calls, so
  on macOS the same file, over `shim/kqueue.c`, is `http::serve`'s ring. Its multishot
  accept and receive accept and read until `EAGAIN` at each edge-triggered event, into
  the same provided buffers; a send's bytes are copied and sent in the next wait, and
  the rest waits for the socket's writable edge, watched only then; completions that
  don't fit in a wait's batch wait for the next. The listener is watched only while an
  accept goes on: on macOS it's level-triggered, and would end every wait at once
  while the worker isn't accepting. Its handle is its address with the low bit set, and
  each `ur_*` call in `shim/uring.c` passes such a handle on. `Config.emulate_ring`
  asks for it where io_uring works, which is how the tests run it. The package writes
  nothing about the fallback itself; `http::ring_probe()` returns why there's no
  io_uring, and the benchmark server's startup line says "on an emulated ring" with
  that reason.
- At 16,384 connections the worker cancels its accept, and closes any connection
  accepted before the cancel lands. After `EMFILE` or `ENFILE` it queues the accept
  again after a close or at the next sweep, so waiting clients keep their place in the
  backlog, as with epoll.

### The platform and its error codes (task 006)

The package's sidecar, `http.build`, chooses the platform's shim, because the spec has
no conditional compilation, and the program chooses the loop by calling it (2026-10-11):

| Platform | `http::serve` | `http::serve_epoll` | Shim |
|---|---|---|---|
| Linux | io_uring, or emulated over epoll | epoll | `shim/net.c`, `shim/uring.c`, `shim/ring_epoll.c` |
| macOS | emulated over kqueue | kqueue | `shim/kqueue.c`, `shim/ring_epoll.c` |
| Windows | IOCP | fails with `ENOSYS` | `shim/net_win.c`, `shim/iocp.c` |

Each loop runs unchanged on every platform it builds for. The benchmark server links
both, and `LOOP` picks one: at run time, or at build time for its default, where
`scripts/build.sh` builds `server/server.goose` (uring) or `server/server_epoll.goose`
(epoll), and refuses `LOOP=uring` and `LOOP=epoll` on Windows, and `LOOP=iocp` off
Windows.

On macOS:

- `shim/kqueue.c` defines the same C functions as `shim/net.c`, so `sys.goose` binds
  either. `IN` and `OUT` become `EVFILT_READ` and `EVFILT_WRITE`, `ET` becomes
  `EV_CLEAR`, and `EV_EOF` is reported as `RDHUP` on the read filter and `HUP` on the
  write filter. The events are copied into `http::Event`, as on Linux, because `struct
  kevent` is 32 bytes on arm64.
- The shim merges the events of one fd within a wait into one `http::Event`, as epoll
  reports them. kqueue reports each filter apart, and the loop frees a connection's slot on
  the event that closes it, so a second event for it in the same batch would drive the
  freed slot. Without the merge, 3,000 connections at once hung.
- The workers share one listener per port: macOS's `SO_REUSEPORT` gave every connection
  to the last listener bound. Each worker gets its own fd for the listener and watches it
  in its own kqueue. Left to the kernel, the worker already awake took most connections,
  with the listener edge- or level-triggered, and capping accepts per pass didn't change
  that. So the shim counts each worker's accepts, a worker declines with `EAGAIN` while it
  has taken more than one past the average, and the listener is level-triggered, so a
  declined connection stays reported until another worker takes it (2026-10-11, task
  012 has the measurements).
- macOS drops a connection whose `accept` fails with `EMFILE`, so near the fd limit the
  shim checks for a free fd first and leaves the client in the backlog when there's
  none, as Linux does. The check and the `accept` hold a lock across workers, so two
  can't both pass the check for the last free fd; far from the limit there's no check
  (2026-10-11).
- A connection's writability is watched only while a send waits for room, as libuv
  does: kqueue reports `EV_CLEAR`'s write filter as each ACK frees buffer space, a
  wake-up per response. The epoll loop and the ring's emulation register `OUT` after a
  send returns `EAGAIN` and drop it once the bytes are out, on Linux too (2026-10-11,
  task 012).

On Windows ([task 006.02](../../tasks/006-kqueue-iocp/02-iocp-windows.md) has the
details):

- `shim/iocp.c` implements `ring.goose` over a completion port. IOCP completes one
  operation per request, so a multishot accept is an `AcceptEx` posted again after each
  completion, and a multishot receive is a `WSARecv` kept posted. While more than half
  the ring's buffers are free, it reads into one of them. Otherwise it's a zero-byte
  `WSARecv`, whose completion the shim follows with one non-blocking `recv` into a free
  buffer, so past half the buffers an idle connection holds none, as with io_uring's
  provided buffers; a buffer posted per connection deadlocked 10,000 connections.
- Accepted sockets skip the completion port when a request completes at once
  (`FILE_SKIP_COMPLETION_PORT_ON_SUCCESS`), as most sends do: the shim reports it from
  its own list. With the buffered receive, that served 7-9% more requests a second
  (2026-10-11, [development](../development.md#against-wsl)). Nearly all of a request's
  time is the kernel's, about 11 µs on loopback, against 0.8 µs in user code.
- The workers share one listener, which belongs to no completion port, because a
  socket can belong to only one. Each ring's `AcceptEx` signals an event, and a wait
  registered on it posts the completion to that ring's port, as libuv does. Windows
  serves the most recently posted `AcceptEx` first, so one worker takes most
  connections. That costs throughput, not correctness.
- `closesocket` ends every request on the socket and aborts a send still pending. Each
  pending request holds a reference to its socket's record, so a late completion never
  touches a reused handle.
- The server listens on 127.0.0.1 only, because Windows Defender Firewall prompts for
  any other address, with `SO_EXCLUSIVEADDRUSE`, so a second server gets `EADDRINUSE`,
  and `SOMAXCONN_HINT`, because a plain backlog stops at 200.

The constants in `sys.goose` are the project's own error codes, Linux's errno values
on every platform, as libuv's are the negated errno on Unix. `shim/net.c` passes errno
through, and its `_Static_assert`s pin the values. `shim/kqueue.c` translates: codes 1 to
34 are equal on both systems, a table maps macOS's codes from 35 up to Linux's (`EAGAIN`
35 to 11, `ECONNABORTED` 53 to 103), and a code with no Linux counterpart becomes 1000
plus its own. `net_strerror` translates back, for the platform's text. Goose code never
sees a platform's own numbers. `shim/net_win.c` maps Winsock's and Win32's errors onto
the same codes (`net_win_err`), as libuv's `uv_translate_sys_error` does, with 1000
plus the Windows code for any it doesn't map; `shim/iocp.c` uses the same mapping.
