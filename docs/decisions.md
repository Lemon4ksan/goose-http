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
lifetime. Where workers are spawned was replaced on 2026-10-18 by
[the package spawns the workers](#the-package-spawns-the-workers).

## Connection slots and a spill pool

Decided 2026-10-10, task 009.

Connections live in a worker's `reusable` pool. A slot as the event tag avoids an
fd-indexed table growing to the highest fd across all workers. Read and write buffers
belong to the worker; incomplete requests and output that could not be sent go to a
spill pool. Full buffers in every slot were rejected for their memory cost.

## HTTP in Goose, syscalls in a C shim

Decided 2026-10-11, tasks 010 and 011.

HTTP parsing, routing, response building, loop state machines, messages between threads,
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

## Waiting through bounded boxes in C

Decided 2026-10-12, task 015.

Waiting uses bounded boxes, a fixed-capacity timer table, and generation-checked
handles, each independent of HTTP. Boxes are C because Goose has neither atomics
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

## A store for read-only blobs

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

## Tests follow Goose's convention

Decided 2026-10-15, task 041, for goose-http, goose-rest, and goose-compress alike.
Tests follow Goose's own convention, as the Goose repository's `test/` and
`docs/testing.md` lay it out:

- A top-level `test/` holds the tests, in a folder per area.
- Each test is a small program: a `main` with `assert`s, which prints what it checks.
  Its expected output is a golden file, `test/expected/<name>.out`, with
  `<name>.stderr` for lines its standard error must hold, and `<name>.aborts` for a
  test that must abort.
- A test that must not compile carries `// error: <substring>` comments.
- The repository's own runner, `test/run_tests.py` in Python as Goose's is, finds the
  tests, compiles them in batches with `goose --multi-test`, runs each as a process of
  its own and in parallel, and reports every failure without stopping at the first.
  No runner is shared between repositories, as none is with Goose's. In goose-http the
  batch is the typecheck, and `goose build` builds each test, since most tests link C
  that a sidecar names, the package's shim or the box's, which `goose build`
  compiles.
- Helpers the tests share are one imported module, not a copy in each test.

This replaces the test programs `scripts/test.sh` runs by name, where the first failed
`assert` ends a program and hides the rest. A test framework inside Goose was rejected:
Goose has no reflection to find tests, and checking by printing against a golden file
needs none. So were tests beside the code: Goose's compiler already leaves out of a
build what its root doesn't import, so a separate `test/` costs nothing, and it matches
the convention any reader of Goose's own repository knows.

## One name for each place data lives

Decided 2026-10-16, with goose-rest. A thread's queue of messages is a *box*
(`http::Box`), and a message reaches it *by mail*; the shared blobs are the *store*
(`http.store`); a global with a literal value, compiled into the program, is a
*constant*; and the thread that does one kind of slow work, which workers send jobs to
by mail, is a *lane*. These replace "mailbox", "shared store", "a global with a literal
initializer", and, in the slow-work pattern, "service thread" and "backend thread".
The request's state in `http::serve` keeps its name, and no API name changed.

Decided 2026-10-16, with goose-rest: work of minutes that the handler answers with
`202 Accepted`, and that the client then polls, is a *background task*, not a job. A
*job* is the work a handler mails a lane and waits for, as in goose-rest, where a
background task is made of jobs: one that starts it, and one for each poll.

## A crash ends the process, and a service manager restarts it

Decided 2026-10-16.

A crash in any thread, worker or lane, ends the whole process. The service manager
restarts it, with a delay and a limit on restarts in a row
([a crash ends the process](patterns.md#a-crash-ends-the-process)). The package has no
supervisor of its own.

Tina restarts one Isolate after a crash and keeps the rest of its shard running ("let it
crash"). Goose can't do this inside a process: an abort, such as an index out of bounds
or a failed `assert`, ends the program and can't be caught (spec §9.3). A thread can't
be restarted after it fails. Running each lane as a child process would give that
boundary, but it needs boxes and wakes that work across processes on Linux, macOS, and
Windows, and a second way to start the program on Windows, which has no `fork`. That
cost is rejected.

Kept 2026-10-19, task 050. With `thread_spawn_contained`
([aardappel/goose#38](https://github.com/aardappel/goose/pull/38)) in the pin, an abort
can end only its thread, and `http::run` restarting an aborted worker was built and
tested on Linux and macOS. It is parked on the branch `restart-workers`: it added a
watcher thread per worker, two queues, C to close what the dead worker opened, and a
second mechanism for lanes, while the dead worker's connections still got no answer.
One finding stays for whoever picks it up: on Linux, a dead ring's io_uring multishot
accept keeps a closed listener in its `SO_REUSEPORT` group, and new connections hang
there, so shut the listener down before closing it.

## A stop is a flag in the box, not a message

Decided 2026-10-17, task 044; `mail_stopped`'s wait, 2026-10-18.

`http::mail_stop(box)` sets a flag in the box and wakes its owner, and
`http::mail_stopped(box)` is true once the box is stopped and empty. A `STOP` message
needs a free slot: to a full box at shutdown, its send returns `FULL`, the stop is
lost, and the lane waits forever, which goose-rest's lanes did. Tina reserves part of
its message pool for shutdown, timers, and restarts for that reason; a flag needs no
reserve, since traffic can't crowd it out. A send to a stopped box returns `STALE`, so
a lane that finds its box stopped and empty can close it without dropping a job sent
after. `mail_stopped` waits, yielding in the shim, for the sends in
flight across the stop, since returning `false` to a lane whose box workers were
polling made it spin at 100% CPU. The cost is one more load of the flag on every send,
a locked instruction under MSVC (task 047).

## No .env loader

Decided 2026-10-18, task 046.

`http::env_load`, which put a development `.env` file into the environment through the
placement file's line reader, since removed, was built and dropped. No program called it, and in
production systemd's `EnvironmentFile` and Compose's `env_file` already load one into
the environment that `env` reads.

## The package spawns the workers

Decided 2026-10-18, task 048; the worker's index went with placement on 2026-10-19.
Replaces the spawning in [workers own their connections](#workers-own-their-connections).

`http::run(cfg, worker)` spawns the workers, with up to two values of the program's
between `cfg` and the worker, and returns once every one has returned. Goose
`fb5698125` lets a generic function spawn the `thread_fn` its caller binds, which made
this possible; before it, every program wrote the same spawn loop. Goose has no
variadic parameters, so `run` has an overload for each count of values; two cover
every program in goose-http and goose-rest. The worker comes last, as Goose passes a
function value after a call's other arguments. `http::lane_open` spawns a lane's
threads the same way.

A program that picks the loop for its workers at run time, such as `server/app.goose`,
calls `run` once per choice (2026-10-18). Only a program that must interleave spawning
with other work, such as the REST benchmark servers with their startup handshake, keeps
its own spawn loop.

## Placement is removed until it is measured to help

Decided 2026-10-19, after an independent review; replaces the placement entries of
2026-10-17 and 2026-10-18, which the branch keeps.

Placement, a file per kind of machine that mapped the workers' and each lane's role to
cores, a priority, and `SO_INCOMING_CPU`, with `Config.place`, `Config.role`,
`Config.worker`, seats, `place.goose`, and `shim/place.c`, is off `main`, parked on the
branch `placement` in goose-http and goose-rest. It was never measured to help: on an M1 Pro no layout beat
the OS's own (task 045), and a `low` lane lost about 40% of its rate. It returns only
when bare-metal Linux measures a gain beyond the runs' spread, and then invisible to
programs: the library reads the file, or `GOOSE_PLACE`, and applies it inside `run`
and `lane_open`, with no seat or role in a program's code. A porter from Hono, Elysia,
or Axum shouldn't learn a concept that buys nothing measured.

## Lanes are goose-http's, and the one way to a pool

Decided 2026-10-19, after an independent review, with goose-rest.

`http::Lane`, `lane_open`, `lane`, `lane_send`, and `lane_stop` moved here from
goose-rest's `rest::lane`, so that goose-http's own programs and goose-rest's open,
run, and stop a lane the same way, whether it has one thread or several. A lane is the
one mechanism for threads that do slow work: the typed-queue pool of task 051 and
goose-rest's `ask_by`, which sent one key's jobs to one thread, went, so each thing is
done one way. `LaneConfig` keeps only `threads`, `slots`, and `size`. A thread that does
its own timed work between jobs, as `server/backend.goose` and goose-rest's reports
tutorial do, writes the four-line loop that `lane` is; a timed `lane` would add a
concept for two programs. `mail_queued` stays for `lane_send`, outside the user docs.

## Not yet decided

### Compression in an optional module

Implemented, with no recorded approval; task 022.

Precompressed files need no codec. Dynamic compression is implemented in the optional
`http.compression` module using goose-compress's pure-Goose gzip, deflate, and zstd
encoders. Negotiation and response framing stay in `http`; codecs import nothing of
HTTP. Programs without the module need no codec dependency. Compression remains part
of measuring Goose; TLS crypto is outside this project's scope. Task 022 retains the
split's unrecorded approval and remaining validation.
