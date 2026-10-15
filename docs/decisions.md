# Decisions

The record for contributors and agents: each design decision, dated, with its reason,
what was rejected, and the task that measured it. How the package works now is in
[architecture](architecture.md); this page keeps why it came to work that way. Entries
run oldest first, and a later entry that replaces an earlier one says so.

## Goose unmodified

Decided 2026-10-10.

The package uses the pinned Goose checkout without modifying it. Compiler and stdlib
gaps that meet the reporting bar go to [Goose findings](goose-findings.md).

## Workers own their connections

Decided 2026-10-10, task 003.

The program spawns workers and passes each a flat `Config`. A `thread_fn` is compiled
as its own program and copies the non-static globals it uses (§11.2). Spawning stays
in the program because `thread_spawn` cannot take a `thread_fn` passed through a
package function. Each worker runs one loop and owns its connections for their
lifetime.

## Connection slots and a spill pool

Decided 2026-10-10, task 009.

Connections live in a worker's `reusable` pool. A slot as the event tag avoids an
fd-indexed table growing to the highest fd across all workers. Read and write buffers
belong to the worker; incomplete requests and output that could not be sent go to a
spill pool. Full buffers in every slot were rejected for their memory cost.

## HTTP in Goose, syscalls in a C shim

Decided 2026-10-11, tasks 010 and 011.

HTTP parsing, routing, response building, loop state machines, mailbox messages,
timers, and JSON are Goose. C in `shim/` wraps syscalls and kernel structures that
Goose cannot reach. The package sidecar, `http.build`, selects and compiles each
platform's C files; Goose code needs no conditional compilation.

## io_uring is the default loop on Linux

Decided 2026-10-11, task 005.

`http::serve` is the default on Linux. `http::serve_epoll` remains buildable and tested
as a lower-memory alternative. Linux is the benchmark platform; the
[current comparisons](benchmarks.md) record both wins and losses.

## The ring falls back to an emulation

Decided 2026-10-11, task 011.

Where `io_uring_setup` fails, the ring falls back to `shim/ring_epoll.c`: Docker's
default seccomp profile, disabled io_uring, or an older kernel. The same emulation
runs over kqueue on macOS. `Config.emulate_ring` selects it for tests;
`http::ring_probe()` reports why native io_uring is unavailable. The package does not
log the fallback; the benchmark server does.

## macOS over kqueue

Decided 2026-10-11, task 012.

On macOS, kqueue filters become poll flags. Events for one fd are merged within a
batch so a second event cannot drive a slot freed by the first. Workers share a
listener because separate `SO_REUSEPORT` listeners did not distribute connections.
An accept counter limits an already-ahead worker; a level-triggered listener keeps
declined connections available to others. Near the fd limit, a locked free-fd check
avoids macOS dropping a connection on `EMFILE`. Writability is watched only while
output waits for room.

## Linux error codes on every platform

Decided 2026-10-11, task 006.

Goose sees Linux errno values on every platform. Linux passes them through, macOS and
Windows translate, and `net_strerror` supplies platform text. An unmapped code becomes
1000 plus the platform code. The C shims own this mapping.

## A handler with state is called again

Decided 2026-10-12, task 013.

A handler with state is called again for each part of an exchange, with a flat value
of the program's type kept in the connection slot. Goose cannot suspend or store a
handler (§7.6), so this is how bodies, streamed responses, upgrades, and waiting
answers resume. The [event table](api.md#streaming) defines each call and its lifetime.

## The epoll loop bounds reads per turn

Decided 2026-10-12, task 021.

The epoll loop reads at most `Config.max_read` bytes from one connection per turn,
16 KB by default. A connection left readable goes on a deferred list because an
edge-triggered socket may raise no new event while its sender waits. This prevents
a sustained upload taking a worker for the entire body. Completion-loop latency
beside uploads remains open in task 026.

## Large io_uring sends go inline

Decided 2026-10-12, task 021.

The ring owns memory the kernel touches after a call returns. The shim copies sends
into its own buffers, and the loop copies receives out of provided buffers, because
an `extern fn` cannot retain a Goose argument (§7.10). A send of at least 64 KB with
nothing queued on its socket first tries synchronous `send(2)`; only unsent bytes
need a retained copy. Smaller sends stay asynchronous because a syscall per response
cost small REST responses throughput.

## Files of 64 KB or more go to the loop

Decided 2026-10-12, task 020.

`http::send_file` hands a file to the loop when the remaining `Content-Length`
response is at least 64 KB: `sendfile` on epoll and the emulated ring, splice through
a pipe on io_uring, and `TransmitFile` on IOCP. Smaller files and chunked responses
use `pread` in pieces. The threshold avoids direct-send overhead for small files; its
[measurement](results.md#static-files) and the remaining 64 KB gap to nginx are
recorded in task 024.

## Waiting through bounded mailboxes in C

Decided 2026-10-12, task 015.

Waiting uses bounded mailboxes, a fixed-capacity timer table, and generation-checked
handles, each independent of HTTP. Mailboxes are C because Goose has neither atomics
nor a wait another thread can end. Goose's typed queues have no bound, allow any
thread to receive, and cannot wake an event loop.

## The log measures the write buffer

Decided 2026-10-12, task 015.

With `Config.log`, `DONE` reports status, bytes, and elapsed loop time. It measures
completion in the write buffer, not delivery to the client, which the loop does not
track per response.

## The API isn't frozen

Decided 2026-10-13, task 027.

The API may change when an idiom improves clarity without costing speed or memory
beyond the benchmark runs' spread.

## Sends to an exchange that no longer waits are stale

Decided 2026-10-14, tasks 027 and 028.

Send checks the key atomically before claiming a queue slot and returns `STALE` for
an exchange that no longer waits. `mail_live` gives any thread the same snapshot
without sending. A send that read a live key before it was cleared can still be
queued; the loop checks each delivered key and drops messages that no longer match
a waiting exchange. Repeating `later` on the same exchange marks its key live again.
Send returns `SENT`, `FULL`, `TOO_LONG`, or `STALE` without blocking; senders can query
the slot size, or -1 for a stale address.

As first decided, both Goose loops cleared the key before `WAKE`, `TIMEOUT`, or
`CLOSED`, when a timer could not be armed, or when a handler answered instead of
waiting. The next entry replaces that for `WAKE`.

## A waiting key stays live through WAKE

Decided 2026-10-14. Replaces clearing the key before `WAKE`, in the entry above.

`later` marks the key before returning, so a reply from another thread can arrive
before the handler returns. The key stays live through a `WAKE` and is cleared after
the handler returns without waiting again, so a reply sent in pieces never finds it
stale between one piece and the handler's next `later`. It is cleared before
`TIMEOUT` and `CLOSED`, when a timer cannot be armed, and when a handler answers or
stops waiting instead of waiting. `Stream.live` records whether the key is marked, so
only an exchange that waited pays for an atomic write. This covers io_uring, epoll,
kqueue, and IOCP through their shared Goose paths.

## A shared store for read-only blobs

Decided 2026-10-14, task 025.

The store (`store.goose` over `shim/store.c`) holds byte blobs populated by one thread
and frozen before others read. Queues, `thread_spawn`, or `thread_wait` order writes
before reads. Reads copy ranges into Goose arrays because an `extern fn` cannot return
a view of C memory (§7.10). The data's meaning and response construction remain Goose.
The store imports nothing of HTTP and is reached through `import http.store`.

This avoids a copy per worker for JSON built at startup. Loading it from disk per
request was rejected: it would move memory out of RSS into the page cache and add a
syscall per response. Other REST records still cost a copy per worker.

## An upgraded connection is read while it waits

Decided 2026-10-15, task 038.

A waiting exchange holds back the bytes after it, since the next request must wait
its turn, except an upgraded one: its connection is a stream both ways, so the loops
go on reading it and `answer` hands what arrives to the handler as `BODY` while the
wait stands (`holds_input`). The wait still ends only with `WAKE`, `TIMEOUT`, `end`,
or `CLOSED`, so this adds no state, and the handler sees bytes and the reply in the
order they reached the worker.

## Not yet decided

### Compression in an optional module

Implemented, with no recorded approval; task 022.

Precompressed files need no codec. Dynamic compression is implemented in the optional
`http.compression` module using goose-compress's pure-Goose gzip, deflate, and zstd
encoders. Negotiation and response framing stay in `http`; codecs import nothing of
HTTP. Programs without the module need no codec dependency. Compression remains part
of measuring Goose; TLS crypto is outside this project's scope. Task 022 retains the
split's unrecorded approval and remaining validation.
