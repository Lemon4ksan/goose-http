# Architecture

How goose-http works, and why. The [API](api.md) describes each call,
[server patterns](patterns.md) which approach fits bodies, long responses, and slow
work, the [examples](../examples/README.md) show each in a program, and the
[benchmarks](benchmarks.md) give the measured costs. The decisions behind this design,
with their dates and the alternatives rejected, are in [decisions](decisions.md).

## What isn't Goose

Measuring Goose is the point, so everything that is HTTP is Goose: parsing, routing,
response building, the loops' state machines, the mailbox's messages, the timer table,
and JSON. The package uses the pinned Goose release without modifying it.

### C in the package

`http.build`, the package sidecar, compiles each platform's C files from `shim/` into
every program that imports the package, so Goose code needs no conditional
compilation:

| File | Platform | What it does |
|---|---|---|
| `shim/net.c` | Linux | Sockets, epoll, clocks, file reads, the stop counter, and the loops' waker, an `eventfd` |
| `shim/kqueue.c` | macOS | `shim/net.c`'s functions over kqueue, with the same Linux error codes; the waker is `EVFILT_USER` |
| `shim/net_win.c` | Windows | `shim/net.c`'s functions over Winsock |
| `shim/uring.c` | Linux | The io_uring ring, over liburing |
| `shim/iocp.c` | Windows | The same ring over a completion port, and the waker, a completion packet |
| `shim/ring_epoll.c` | Linux, macOS | The ring emulated over epoll or kqueue, where io_uring is blocked, and always on macOS |
| `shim/mail.c` | all | The mailboxes' bounded queue, and the list of loop wakers that `http::stop` wakes |
| `shim/store.c` | all | The shared store's blobs, written once at startup and read by every thread |

Each is C for one of four reasons:

- **Syscalls and kernel structures.** Goose calls C functions, not the kernel, and its
  structs are packed, so they don't match the kernel's own (`struct epoll_event` is 16
  bytes on ARM, 12 in Goose). So `shim/net.c`, `shim/kqueue.c`, and `shim/net_win.c`
  call the kernel and copy its structures into the package's.
- **Memory the kernel uses after a call returns.** A C function may not keep a
  pointer into Goose memory past the call (spec §7.10), but io_uring and IOCP read and
  write buffers while a request is in flight. So each ring owns its buffers in C.
- **Atomics, and a wait another thread can end.** Goose threads share no memory and
  have no atomics, and a Goose thread can't end another's wait in the kernel. So
  `shim/mail.c` holds each box's slots and the counts its senders change atomically,
  and each platform's waker ends a loop's wait.
- **Memory every thread reads.** Goose shares only static data between threads, and
  copies every other global a worker uses when it's spawned. `shim/store.c` holds
  byte blobs a program writes once, before its workers read them.

Each C file is a separate translation unit and declares the layouts it shares with
Goose; the [C interop guide](c-interop.md) describes them. Goose has no runtime
function pointers (§7.5), and `export fn` calls must stay on the thread that called
`goose_init` (§7.11), so libraries that call back into Goose don't fit the loop. A
list of slices can't cross `extern fn` (§7.10), so responses are batched in one buffer
rather than passed as an `iovec` list to `writev`.

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

## Event loops

### Workers and connections

The program spawns workers and passes each a flat `Config`. Each worker runs one loop
and owns its connections for their lifetime. Spawning stays in the program because `thread_spawn` can't take a `thread_fn` passed
through a package function.

`http::worker_count(cfg)` uses `Config.workers`, or the hardware thread count by
default. On macOS it defaults to the performance-core count, and the loop sets
user-interactive QoS. Linux workers bind separate listeners with `SO_REUSEPORT`;
macOS and Windows workers share a listener.

A connection is a slot in its worker's pool, and the slot is the event tag. Read and
write buffers belong to the worker; an incomplete request or output not yet sent goes
to a spill pool, so an idle connection holds no buffer. At `Config.max_conns`, or
after `EMFILE` or `ENFILE`, a worker pauses accepting and retries after a close or at
the next sweep; waiting clients stay in the backlog.

The epoll loop reads at most `Config.max_read` bytes, 16 KB by default, from one
connection per turn, and puts a connection left readable on a deferred list, so a
sustained upload can't take a worker for its whole body. On the completion loop, a
sustained upload can still delay other connections' reads.

### Completion loop

`http::serve` runs a completion loop, a proactor that submits I/O and learns when it is
done: io_uring on Linux, IOCP on Windows, and an emulation over epoll or kqueue
elsewhere. `http::serve_epoll` is a readiness loop, a reactor that learns a socket is
ready and then reads or writes; it uses less memory and works on Linux and macOS. The program chooses a loop by calling it, and a loop it
doesn't call isn't compiled in.

| Platform | `http::serve` | `http::serve_epoll` | Networking shim |
|---|---|---|---|
| Linux | io_uring, or emulated over epoll | epoll | `shim/net.c`, `shim/uring.c`, `shim/ring_epoll.c` |
| macOS | emulated over kqueue | kqueue | `shim/kqueue.c`, `shim/ring_epoll.c` |
| Windows | IOCP | fails with `ENOSYS` | `shim/net_win.c`, `shim/iocp.c` |

On Linux, each worker owns an io_uring ring on kernel 6.1 or later, set up so
completion work stays on the worker when it waits. Multishot accept takes connections,
and multishot receive fills provided buffers. The ring owns the memory the kernel
touches after a call returns: the shim copies sends into its own reused buffers, and
the loop copies receives out of provided buffers. A send of at least 64 KB with
nothing queued on its socket first tries a synchronous `send(2)`, so only unsent bytes
need a copy.

A connection has one send in flight, and later sends queue behind it, which keeps
order and batches pipelined responses. Past `Config.max_queued` bytes queued, the loop
stops receiving until the client reads. A completion carries the connection's slot
and generation, and the shim tracks each fd's generation, so a send left from a closed
connection never goes to a new one that reuses the fd.

Where io_uring isn't available, such as under Docker's default seccomp profile, with
io_uring disabled, or on an older kernel, the ring falls back to the emulation in
`shim/ring_epoll.c`. `http::ring_probe()` reports why, and `Config.emulate_ring`
selects the emulation for tests.

### Platforms

On macOS, workers share one listener, because separate `SO_REUSEPORT` listeners
didn't spread connections, and an accept counter keeps one worker from taking them
all. Apple Silicon has no CPU affinity.

On Windows, repeated `AcceptEx` and `WSARecv` operations stand in for multishot
requests, and zero-byte receives keep idle connections from using up the provided
buffers. Accepts are posted last-in first-out, which can leave workers unevenly
loaded. The server listens on loopback by default, to avoid a firewall prompt;
explicit IPv4 and IPv6 addresses work. On teardown the port and its buffers stay
allocated, because cancelled operations can still complete into them.

Goose sees Linux `errno` values on every platform: macOS and Windows translate theirs,
and `net_strerror` gives the platform's text. A code with no Linux equivalent becomes
1000 plus the platform's code.

## The handler and its events

The parser enforces CRLF, HTTP/1.1's single `Host`, the framing rules, and
configurable head, body, and field limits. HTTP/1.1 keeps connections alive by
default; HTTP/1.0 does so only when the client asks. Pipelined requests are answered
in order, and their responses batched. `Server` and `Date` are rendered once a second
per worker.

Goose can't suspend or store a handler (§7.6), so a handler with state is called again
for each part of an exchange, with a flat value of the program's type kept in the
connection's slot. Bodies, streamed responses, upgrades, and answers that wait all
resume this way. The [event table](api.md#streaming) defines each call and what it
may do.

A whole-request handler gets a body that fits with its head in the read buffer. A
longer body needs a handler with state, which can copy it whole up to a limit with
`http::gather`. A streamed response is asked for `MORE` only while its queued output
is below the write buffer's size on epoll, or `Config.max_queued` on the completion
loop. A whole response still occupies the worker's write buffer, which keeps the
pages its largest response touched.

A response sent before its request body ends drains the rest, up to
`Config.max_drain`, then closes. Under `Expect: 100-continue`, a body that fits gets
the interim response at once, and the handler may refuse a longer one first. Refusals
and timeouts send their response before shutting down and draining, so a reset
doesn't discard it. Head, body, write, and idle timeouts are separate, and a sweep
enforces them.

## Files and compression

`http::send_file` hands a file to the loop when the remaining response, with its
`Content-Length`, is at least 64 KB: `sendfile` on epoll and the emulated ring, splice
through a pipe on io_uring, and `TransmitFile` on IOCP. Smaller files, and chunked
responses, are read with `pread` in pieces, which costs less than a direct send for
small files ([measurements](results.md#static-files)). The loop closes a file handed
to it, including when the connection closes first. A handler that keeps a file
releases it at `CLOSED`.

Precompressed files need no codec. Dynamic gzip, deflate, and zstd come from the
optional `http.compression` module, over goose-compress's encoders, which are Goose
and import nothing of HTTP. Negotiation and response framing stay in `http`, so a
program that doesn't import the module needs no codec. TLS is outside this package.

## Mail between threads

A handler that waits for another thread calls `http::later`, which needs a time limit
and returns the exchange's address. The other thread sends its reply to that address
through the worker's bounded mailbox, and the loop calls the handler with `WAKE`, or
with `TIMEOUT` when the limit passes. [Mail between threads](patterns.md#mail-between-threads)
shows the pattern, and the API's [answers that wait](api.md#answers-that-wait) its
calls.

The mailboxes are C because Goose has neither atomics nor a wait that another thread
can end. Goose's typed queues have no bound, let any thread receive, and can't wake
an event loop. A loop opens a box and a timer table only when `Config.mail_slots` and
`Config.max_waiting` are positive.

Each worker's box tracks the keys of exchanges that wait, in an atomic table of
`Config.max_conns` entries: 8 bytes each, 128 KiB at the default. `later` marks the
exchange's key live before it returns, so a reply can arrive before the handler
returns. The key stays live through `WAKE`, so a reply sent in pieces finds it live
between one piece and the handler's next `later`, and is cleared once the handler
answers or stops waiting, and before `TIMEOUT` and `CLOSED`.

A send never blocks: it returns `SENT`, `FULL`, `TOO_LONG`, or `STALE`, the last for
an exchange that no longer waits, and `mail_live` asks the same without sending. A
send that saw a key live just before it was cleared can still be queued, so the loop
checks each delivered key and drops a message no exchange waits for.

A waiting exchange holds back the requests after it, which must wait their turn. An
upgraded connection is a stream both ways, so the loops go on reading it, and the
bytes that arrive reach the handler as `BODY` while the wait stands, in the order they
reached the worker.

## The shared store

`import http.store` gives a program byte blobs that one thread writes at startup and
every worker then reads, so data built once, such as a JSON catalog, isn't copied into
each worker. Writes must be ordered before reads by a queue, `thread_spawn`, or
`thread_wait`. A read copies a range into a Goose array, because an `extern fn` can't
return a view of C memory (§7.10). What the bytes mean, and the responses built from
them, are Goose. [State that workers share](patterns.md#state-that-workers-share)
says when to use it.

## Logging and shutdown

`http::peer` asks for a connection's address when it's needed. A forwarded address is
used only when the peer is in the program's trusted networks. With `Config.log`,
`DONE` reports the status, bytes, and loop time of each exchange, measured to its
completion in the write buffer, not its delivery to the client.

`http::stop`, or a signal installed by `http::stop_on_signals`, advances a counter and
wakes every loop; a loop started after a stop runs normally. The loops close their
listeners and idle connections, add `Connection: close` to the next response on the
others, and return when drained or after `Config.grace_ms`.
