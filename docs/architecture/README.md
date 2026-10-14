# Architecture

Current design, the decisions behind it, and the trade-offs that still matter.
The [API and examples](../../examples/README.md) describe how to use the package;
[benchmarks](../benchmarks.md) describe its measured costs.

<a id="settled"></a>
## Package boundaries

The package uses the pinned Goose checkout without modifying it. Compiler and stdlib
gaps that meet the reporting bar go to [Goose findings](../goose-findings.md)
(2026-10-10). The API may change when an idiom improves clarity without costing speed
or memory beyond the benchmark runs' spread (2026-10-13, task 027).

HTTP parsing, routing, response building, loop state machines, mailbox messages,
timers, and JSON are Goose. C in `shim/` wraps syscalls and kernel structures that
Goose cannot reach. The package sidecar, `http.build`, selects and compiles each
platform's C files; Goose code needs no conditional compilation (tasks 010 and 011,
2026-10-11).

Each C file is a separate translation unit and declares the layouts it shares with
Goose. The shim converts architecture-dependent kernel structures into the package's
own structs. The [C interop guide](../c-interop.md) describes layouts and calling rules.

Goose has no runtime function pointers (§7.5), and `export fn` calls must stay on the
thread that called `goose_init` (§7.11). Libraries requiring callbacks into Goose do
not fit the loop. IOCP's wait callback is C calling C; Goose runs only on threads it
started. A list of slices cannot cross `extern fn` (§7.10), so responses are batched
in one buffer rather than passed as an `iovec` list to `writev`.

## Workers and connection ownership

The program spawns workers and passes each a flat `Config`. A `thread_fn` is compiled
as its own program and copies the non-static globals it uses (§11.2). Spawning stays
in the program because `thread_spawn` cannot take a `thread_fn` passed through a
package function. Each worker runs one loop and owns its connections for their
lifetime (task 003, 2026-10-10).

`http::worker_count(cfg)` uses `Config.workers`, or the hardware thread count by
default. On macOS it defaults to the performance-core count, and the loop sets
user-interactive QoS; Apple Silicon has no CPU affinity. Linux workers bind separate
listeners with `SO_REUSEPORT`. macOS and Windows workers share a listener.

Connections live in a worker's `reusable` pool. A slot as the event tag avoids an
fd-indexed table growing to the highest fd across all workers. Read and write buffers
belong to the worker; incomplete requests and output that could not be sent go to a
spill pool. Full buffers in every slot were rejected for their memory cost
(task 009, 2026-10-10).

The epoll loop reads at most `Config.max_read` bytes from one connection per turn,
16 KB by default. A connection left readable goes on a deferred list because an
edge-triggered socket may raise no new event while its sender waits. This prevents
a sustained upload taking a worker for the entire body (task 021, 2026-10-12).
Completion-loop latency beside uploads remains open in task 026.

At `Config.max_conns`, or after `EMFILE` or `ENFILE`, a worker pauses accepting and
retries after a close or at the next sweep. Waiting clients remain in the backlog.

<a id="the-io_uring-loop-task-005"></a>
## Completion loop

`http::serve` is the default on Linux. `http::serve_epoll` remains buildable and tested
as a lower-memory alternative (task 005, 2026-10-11). Linux is the benchmark platform;
the [current comparisons](../benchmarks.md) record both wins and losses.

Each Linux worker owns an io_uring ring, through liburing, on kernel 6.1 or later.
`IORING_SETUP_SINGLE_ISSUER` and `IORING_SETUP_DEFER_TASKRUN` keep completion work on
the worker when it waits; a wait submits queued operations. Multishot accept takes
connections, and multishot receive fills provided buffers. A receive that runs out
of buffers ends and is queued again.

The ring owns memory the kernel touches after a call returns. The shim copies sends
into its own buffers, and the loop copies receives out of provided buffers, because
an `extern fn` cannot retain a Goose argument (§7.10). A send of at least 64 KB with
nothing queued on its socket first tries synchronous `send(2)`; only unsent bytes
need a retained copy. Smaller sends stay asynchronous because a syscall per response
cost small REST responses throughput (task 021, 2026-10-12).

The shim reuses send buffers, with small size classes and a bounded cache for large
buffers. A connection has one send in flight; later sends queue behind it to preserve
order and batch pipelined responses. The loop counts bytes handed over and completed.
Past `Config.max_queued`, it cancels receive and holds bytes already delivered until
the client reads. `ring_close` drops sends not yet started.

A completion tag carries the connection slot and generation. The shim also tracks
the fd's generation, so a short send from a closed connection is never sent to a new
connection reusing the fd. Closing queues cancellation followed by close: a kernel
request can otherwise keep the socket alive.

Where `io_uring_setup` fails, the ring falls back to `shim/ring_epoll.c`: Docker's
default seccomp profile, disabled io_uring, or an older kernel. The same emulation
runs over kqueue on macOS. `Config.emulate_ring` selects it for tests;
`http::ring_probe()` reports why native io_uring is unavailable. The package does not
log the fallback; the benchmark server does (task 011, 2026-10-11).

## HTTP exchanges and backpressure

The parser enforces CRLF, HTTP/1.1's single `Host`, framing rules, and configurable
head, body, and field limits. HTTP/1.1 keeps connections alive by default; HTTP/1.0
does so only when requested. Complete pipelined requests are answered in order and
responses batched. `Server` and `Date` are rendered once a second per worker.

A handler with state is called again for each part of an exchange, with a flat value
of the program's type kept in the connection slot. Goose cannot suspend or store a
handler (§7.6), so this is how bodies, streamed responses, upgrades, and waiting
answers resume (task 013, 2026-10-12). The
[event table](../../examples/README.md#streaming) defines each call and its lifetime.

A whole-request handler receives a body that fits with its head in the read buffer.
A longer body needs a handler with state, optionally through `http::gather` to copy
it whole up to a limit. Streaming responses request `MORE` only while queued output
is below the write-buffer size on epoll, or `Config.max_queued` on the completion
loop. Backpressure bounds queued output; a whole response still occupies the worker's
write buffer, which retains the pages its largest response touched.

A response before its request body ends drains the rest up to `Config.max_drain`,
then closes. Under `Expect: 100-continue`, a body that fits gets the interim response
at once; for a longer body, the handler may refuse it first. Refusals and timeouts send
their response before shutdown and bounded draining, avoiding a reset that discards
the response. Head, body, write, and idle timeouts are separate, enforced by a sweep.

## Files and compression

`http::send_file` hands a file to the loop when the remaining `Content-Length`
response is at least 64 KB: `sendfile` on epoll and the emulated ring, splice through
a pipe on io_uring, and `TransmitFile` on IOCP (task 020, 2026-10-12). Smaller files
and chunked responses use `pread` in pieces. The threshold avoids direct-send
overhead for small files; its [measurement](../results.md#static-files) and the
remaining 64 KB gap to nginx are recorded in task 024.

The loop closes a file handed to it, including when the connection closes first.
A handler retaining a file releases it at `CLOSED`, sent when an exchange ends while
the handler was owed another call. Epoll workers block `SIGPIPE` for `sendfile`;
ordinary sends use `MSG_NOSIGNAL`.

Precompressed files need no codec. Dynamic compression is implemented in the optional
`http.compression` module using goose-compress's pure-Goose gzip, deflate, and zstd
encoders. Negotiation and response framing stay in `http`; codecs import nothing of
HTTP. Programs without the module need no codec dependency. Compression remains part
of measuring Goose; TLS crypto is outside this project's scope. Task 022 retains the
split's unrecorded approval and remaining validation.

## Waiting answers, logging, and shutdown

Waiting uses bounded mailboxes, a fixed-capacity timer table, and generation-checked
handles, each independent of HTTP (task 015, 2026-10-12). Mailboxes are C because Goose
has neither atomics nor a wait another thread can end. Goose's typed queues have no
bound, allow any thread to receive, and cannot wake an event loop.

A loop allocates a box and timer table only when `Config.mail_slots` and
`Config.max_waiting` are positive. `http::later` requires a time limit and returns an
exchange address. Each HTTP worker's box tracks live keys in an atomic table of
`Config.max_conns` entries: 8 bytes each, 128 KiB at the default. The mailbox knows
only keys: its owner chooses the table size and the shift that selects an entry,
then marks and clears whole keys. Untracked boxes accept any key.

`later` marks the key before returning, so a reply from another thread can arrive
before the handler returns. The key stays live through a `WAKE` and is cleared after
the handler returns without waiting again, so a reply sent in pieces never finds it
stale between one piece and the handler's next `later` (2026-10-14). It is cleared
before `TIMEOUT` and `CLOSED`, when a timer cannot be armed, and when a handler answers
or stops waiting instead of waiting. `Stream.live` records whether the key is marked,
so only an exchange that waited pays for an atomic write. This covers io_uring,
epoll, kqueue, and IOCP through their shared Goose paths.
Send checks the key atomically before claiming a queue slot and returns `STALE` for
an exchange that no longer waits. `mail_live` gives any thread the same snapshot
without sending. A send that read a live key before it was cleared can still be
queued; the loop checks each delivered key and drops messages that no longer match
a waiting exchange. Repeating `later` on the same exchange marks its key live again.
Send returns `SENT`, `FULL`, `TOO_LONG`, or `STALE` without blocking; senders can query
the slot size, or -1 for a stale address (tasks 027 and 028, 2026-10-14).

`http::peer` asks for the socket address on demand. Forwarded addresses are used only
when the peer is in the program's trusted networks. With `Config.log`, `DONE` reports
status, bytes, and elapsed loop time. It measures completion in the write buffer, not
delivery to the client, which the loop does not track per response (task 015,
2026-10-12).

`http::stop`, or signals installed by `http::stop_on_signals`, advances a shim counter
and wakes every loop. A counter lets a loop started after a stop run normally. The
waker registry uses atomics because stop may run in a signal handler. Loops close
listeners and idle connections, add `Connection: close` to the next response on other
connections, and return when drained or after `Config.grace_ms`. On Windows the port
and buffers remain allocated on teardown because cancels can complete into them later.

## Shared read-only blobs

The store (`store.goose` over `shim/store.c`) holds byte blobs populated by one thread
and frozen before others read (task 025, 2026-10-14). Queues, `thread_spawn`, or
`thread_wait` order writes before reads. Reads copy ranges into Goose arrays because
an `extern fn` cannot return a view of C memory (§7.10). The data's meaning and
response construction remain Goose. The store imports nothing of HTTP and is reached
through `import http.store`.

This avoids a copy per worker for JSON built at startup. Loading it from disk per
request was rejected: it would move memory out of RSS into the page cache and add a
syscall per response. Other REST records still cost a copy per worker.

<a id="the-platform-and-its-error-codes-task-006"></a>
## Platform shims and error codes

| Platform | `http::serve` | `http::serve_epoll` | Networking shim |
|---|---|---|---|
| Linux | io_uring, or emulated over epoll | epoll | `shim/net.c`, `shim/uring.c`, `shim/ring_epoll.c` |
| macOS | emulated over kqueue | kqueue | `shim/kqueue.c`, `shim/ring_epoll.c` |
| Windows | IOCP | fails with `ENOSYS` | `shim/net_win.c`, `shim/iocp.c` |

The program chooses a loop by calling it; an unused generic loop is not compiled in.
The benchmark server links both, and `LOOP` selects one at run time. Its build script
defaults to uring on Linux, epoll on macOS, and iocp on Windows.

On macOS, kqueue filters become poll flags. Events for one fd are merged within a
batch so a second event cannot drive a slot freed by the first. Workers share a
listener because separate `SO_REUSEPORT` listeners did not distribute connections.
An accept counter limits an already-ahead worker; a level-triggered listener keeps
declined connections available to others. Near the fd limit, a locked free-fd check
avoids macOS dropping a connection on `EMFILE`. Writability is watched only while
output waits for room (task 012, 2026-10-11).

On Windows, repeated `AcceptEx` and `WSARecv` operations emulate multishot requests.
Receives use provided buffers while more than half are free, then zero-byte receives
followed by `recv`, so idle connections cannot exhaust buffers. Operations completing
immediately bypass the port. A shared listener belongs to no port; C wait callbacks
dispatch accepts to each worker's port. Pending operations hold socket references,
so a late completion cannot touch a reused handle. Last-posted-first accepts can
imbalance workers; task 017 tracks performance work. Loopback is the default to avoid
a firewall prompt; explicit IPv4 and IPv6 addresses work. `SO_EXCLUSIVEADDRUSE`
prevents a second server taking the port, and `SOMAXCONN_HINT` avoids the backlog cap.

Goose sees Linux errno values on every platform. Linux passes them through, macOS and
Windows translate, and `net_strerror` supplies platform text. An unmapped code becomes
1000 plus the platform code. The C shims own this mapping (task 006, 2026-10-11).
