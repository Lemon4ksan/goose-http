# 006.01: kqueue on macOS

Status: in-progress

The epoll loop of `src/server.goose` running on macOS through kqueue, behind
`shim/kqueue.h`, and passing the tests it passes on Linux ([task 006](README.md)). macOS
is for running the server correctly, not for benchmarks.

Measured on a MacBook Pro (`MacBookPro18,3`, Apple M1 Pro, 10 cores), macOS 26.3.1
(Darwin 25.3.0, `xnu-12377.91.3`), Apple clang 21.0.0, 2026-10-11. The probes are small
C programs, run once each unless a count is given.

## Design

### One loop, two shims

`src/server.goose`, `src/echo.goose`, and `src/main.goose` don't change. `shim/kqueue.h`
defines the same C functions as `shim/net.h`, with the same arguments and results, so
`src/sys.goose` binds either one. The functions keep their `net_epoll_*` names, and
`sys::` keeps `epoll_create`, `epoll_ctl`, and `epoll_wait`: renaming them would change
the Linux build's files and change nothing it does.

`net_epoll_ctl` turns a registration into kevent changes:

| `sys::` | kevent |
|---|---|
| `IN` | `EVFILT_READ` |
| `OUT` | `EVFILT_WRITE` |
| `ET` | `EV_CLEAR` on each filter |
| `RDHUP` | nothing: kqueue reports a peer's close on `EVFILT_READ` unasked |
| `CTL_ADD` | `EV_ADD` for each filter asked for |
| `CTL_MOD` | `EV_ADD` for each filter asked for, `EV_DELETE` for the other |
| `CTL_DEL` | `EV_DELETE` for both |
| `tag` | `udata` of each filter |

It submits them in one `kevent` call with `EV_RECEIPT`, so each change reports its own
error, and a delete of a filter that isn't registered (`ENOENT`) isn't one.

`net_epoll_wait` copies each kernel event into `sys::Event`, as `shim/net.h` does: `struct
kevent` is 32 bytes on arm64 and `sys::Event` is a packed 12. `EVFILT_READ` sets `IN`,
`EVFILT_WRITE` sets `OUT`. `EV_EOF` on `EVFILT_READ` sets `RDHUP`, and on `EVFILT_WRITE`
sets `HUP`. With `EV_EOF`, a nonzero `fflags` is the socket's error and sets `ERR`. A
timeout of -1 passes no `timespec`, and any other is converted from milliseconds.

The shim merges the events of one fd within a wait into one `sys::Event`. epoll reports
one event per fd per wait, holding both directions, and kqueue reports one per filter.
The loop depends on that: a connection driven to its close on its read event has its slot
freed, and its write event, later in the same batch, would drive the freed slot, closing
fd -1 and counting the close twice. The kernel drops a closed fd's queued events, so only
events within one batch can be stale. The merge scans the events already copied, at most
`out.len` (256 in the loop), for the same fd. That costs up to about 33,000 comparisons for a
full batch, which only a batch of 256 busy connections reaches.

The loop doesn't change. `kevent` with `EV_CLEAR` reports a filter again only when the
socket's state changes, as edge-triggered epoll does, which is what `advance` relies on:
a `recv` that fills less than its buffer empties the socket, and the next byte to arrive
raises a new event.

### Portability gaps

| Linux | macOS | Measured |
|---|---|---|
| `socket` with `SOCK_NONBLOCK` and `SOCK_CLOEXEC` | `socket`, then `fcntl` for `O_NONBLOCK` and `FD_CLOEXEC` | |
| `accept4` with the same flags | `accept`, then `fcntl` for `FD_CLOEXEC` and `ioctl(FIONBIO)` for the blocking mode asked for | `O_NONBLOCK` is inherited from the listener, `FD_CLOEXEC` isn't |
| `MSG_NOSIGNAL` | `MSG_NOSIGNAL`: the macOS 26 SDK defines it, and the kernel honors it, so `SO_NOSIGPIPE` isn't needed | a `send` to a closed socket returned `EPIPE` with no signal |
| `CLOCK_MONOTONIC_COARSE` | `CLOCK_MONOTONIC_RAW_APPROX`, the value cached at the last context switch | at most 1.8 ms behind `CLOCK_MONOTONIC_RAW` over 20 million reads in a spin; 6.5 ns a read |
| `CLOCK_REALTIME_COARSE` | `CLOCK_REALTIME`, which macOS reads without a syscall | 13.4 ns a read |
| `TCP_NODELAY` copied to accepted sockets | the same: no `setsockopt` after `accept` | `getsockopt` on an accepted socket read it set |
| `-D_GNU_SOURCE`, for `accept4` | none: macOS declares everything unless `_POSIX_C_SOURCE` is defined. `scripts/build.sh` passes `-D_GNU_SOURCE` only on Linux, and `shim/net.h` keeps its `#error` | |
| `accept` at the fd limit leaves the connection in the backlog | macOS drops the connection when `accept` fails with `EMFILE` | after freeing an fd, the next `accept` returned `EAGAIN` |
| `listen` backlog up to `net.core.somaxconn` (4096) | `kern.ipc.somaxconn` is 128, and `listen(4096)` is cut to it silently | |

The `EMFILE` row breaks the server's pause at the fd limit: on macOS the clients past the
limit would be reset instead of waiting. So `net_accept` first reserves an fd with
`fcntl(F_DUPFD_CLOEXEC)` and closes it. When that fails, it returns the error without
calling `accept`, and the client stays in the backlog. Another worker can take the free fd
between the close and the `accept`, and then that one connection is dropped, as it is
without the check. That costs two more syscalls per connection.

### Accepting across workers

macOS's `SO_REUSEPORT` lets every worker bind the port, but doesn't spread connections.
With four listeners bound in one process, the last one bound accepted all 400 of 400
connections. Per-worker listeners would leave one worker serving everything.

The candidates, measured with four threads, each with its own kqueue, accepting 400
connections opened in bursts:

| Strategy | Spread of 400 connections | Cost |
|---|---|---|
| Per-worker listeners with `SO_REUSEPORT` | 0, 0, 0, 400 | none |
| One listener in every worker's kqueue | 12, 15, 22, 351 (bursts of 1); 2, 113, 265, 20 (16); 35, 9, 287, 53 (64) | every worker wakes for each burst, and the ones that lose get `EAGAIN` |
| One acceptor handing out fds | even, by construction | a thread passing fds over a pipe: either a change to the loop, or a C thread in the shim |

The decision is one shared listener. Every worker serves connections, and the loop doesn't
change. With `sys::REUSEPORT`, the first `net_listen` on a port opens the listener, and
each later call returns a copy of it from `fcntl(F_DUPFD_CLOEXEC)`. Each worker then owns
an fd and registers it in its own kqueue. The shim keeps the open listeners in a static
table under a mutex, the one piece of state it keeps between calls. It doesn't set
`SO_REUSEPORT`, so a second server on the same port fails to bind.

The spread is uneven: the first worker to wake takes the whole backlog. That matters for
throughput, which macOS doesn't measure, and not for the tests. An acceptor is the fix if
macOS ever becomes a benchmark platform. It isn't built now, because it needs a thread the
Linux loop doesn't have, for a platform that isn't measured. A worker paused at
`MAX_CONNS` leaves the backlog to the others, where on Linux its own listener's clients
wait for it.

### Error codes

The constants in `src/sys.goose` become the project's own error codes, keeping their Linux
values, as libuv's are the negated errno on Unix. Every shim returns them:

- `shim/net.h` passes errno through, and its `_Static_assert`s pin the values.
- `shim/kqueue.h` translates each errno with `net_err`. Codes 1 to 34 are Unix V7's and
  equal on both systems, and the shim asserts the ones `sys::` names. From 35 up, a table
  keyed by macOS's names gives the Linux number: `EAGAIN` 35 becomes 11, `ECONNABORTED` 53
  becomes 103, `ECONNRESET` 54 becomes 104, and `EADDRINUSE` 48 becomes 98. An errno
  with no Linux counterpart, such as `EPROCLIM` or `EQFULL`, becomes 1000 plus its macOS
  number, so it can't be taken for a Linux code.
- `net_strerror` translates back, so `sys::report` prints macOS's text for the error.

Goose code never sees a platform's own numbers.

### File layout and platform choice

- `shim/kqueue.h` is a header of its own, not one half of a split `shim/net.h`. Every
  function in it differs from its Linux counterpart: each return translates errno, and
  listen, accept, the clocks, and the poller differ beyond that. A shared POSIX half would
  hold `recv`, `shutdown`, `close`, and `strerror`, which still differ in their errno
  handling. And a split would change the Linux build's header for no change in what it does.
- `scripts/build.sh` picks the platform with `uname -s`. `Linux` keeps today's
  `-D_GNU_SOURCE --include shim/net.h`, and `Darwin` passes `--include shim/kqueue.h`.
  Both compile `src/main.goose`. `LOOP=uring` on macOS stops with an error.
- What changes in files the Linux build also uses: `scripts/build.sh` (the platform
  choice), comments in `src/sys.goose`, and the test scripts, where a Linux-ism is
  replaced by something portable. Nothing in the loop or in `shim/net.h` changes.

### Goose on macOS

The pinned compiler's TinyCC backend looks for system headers in `/usr/include`, which
macOS doesn't have, so `scripts/test-unit.sh` fails with "include file 'stdint.h' not
found". Upstream fixed it in `7a52bb9`, 19 commits after the pin. The workaround, until
the pin moves, is a CMake flag that names the SDK's include directory as `7a52bb9` does
(`docs/goose-findings.md`). Threads and `hardware_threads` are listed for checking as the
build comes up, and each gap found goes to the findings.

### Tests

`scripts/test-unit.sh`, `scripts/test-http.sh`, and `scripts/test-echo.sh` run on macOS
against the kqueue build. The Linux-isms in them are fixed so that one script serves both
systems. The first found is `nc -N`, which on macOS sets a count of keepalive probes
instead of shutting down after the input ends.

## Acceptance criteria

- [ ] `shim/kqueue.h`, and the epoll loop on macOS through it passing `test-unit.sh`,
      `test-http.sh`, and `test-echo.sh`
- [ ] The macOS build and its environment recorded in `docs/development.md`, with one wrk
      run on `/plaintext`
- [ ] The error codes and the platform choice recorded in `docs/architecture/README.md`
- [ ] macOS gaps in the Goose compiler, runtime, or stdlib recorded in
      `docs/goose-findings.md`
