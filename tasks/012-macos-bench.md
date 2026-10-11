# 012: Benchmark on the Mac, natively and in Docker

Status: in-progress (asked for 2026-10-11)

Task 006 made the kqueue build pass its tests on macOS, with one wrk run. This task
measures it: natively against the servers that build on macOS, and the Linux build
under Docker Desktop's VM, with `bench/run.sh`. It also profiles the kqueue server, to
find where a request's time goes and how evenly the shared listener spreads connections.
The numbers are in [docs/results.md](../docs/results.md), in the two M1 Pro sections;
they aren't compared with the WSL2 machine's.

## Tests at `9623c6a` (2026-10-11)

On the M1 Pro, with Goose `efe3155` built from `git archive efe3155` of a plain checkout,
so no checkout moved:

- `scripts/test-unit.sh`, `scripts/test-http.sh`, and `scripts/test-echo.sh` pass.
- `scripts/http_client.py PORT slow` passed 10 of 10 runs against one server with 4
  workers, which was still running after them.

## Docker

With 4 workers, Goose led every cell of the short matrix, by 5-17% over tokio; wrk used
most of its 6 CPUs in the top cells, so the matrix was client-bound there.

The whole field builds for arm64 since `16528ea` (2026-10-11): `bench/build.sh` builds
the Zig servers for `aarch64-linux-musl` and V with tccbin's arm64 `libgc.a`. With 3
workers on CPUs 0-2 and wrk on CPUs 3-9, JSON is server-bound: goose-uring leads by 10%,
and the epoll loop ties zix, zeemo, and libreactorng within 4%. Plaintext is near both
the servers' and wrk's limits, and Goose's two loops and the vanilla servers end within
their run-to-run spreads. Under HttpArena's harness, Goose leads baseline by 20% and
limited-conn by 13%, and ties vanilla-epoll in pipelined. The numbers and their caveats
are in `docs/results.md`.

## Native

macOS's loopback limits every server to about 35,000-40,000 request-response exchanges a
second, whatever the server: two independent server and wrk pairs split that rate
between them. Goose, hyper, tokio, and may-minihttp end within 5% of each other, and
Goose's memory is the smallest (1.9 MB against 7-194 MB). macOS native numbers show that
a build works and how much memory it uses, nothing more.

### Profile

`sample` on the server with 4 workers under pipelined plaintext (256 connections, 16
deep, 567 K requests per second), 5 s: of the samples not waiting in `kevent` or on the
main thread's condition variable, `sendto` took 1,591, `recvfrom` 1,291, and the Goose
code (`serve_g`) 127, about 4%. The kernel holds nearly all of a request's time, and
most of the workers' time is waiting for it. Under JSON load, `top` showed the 4 workers
at 92% of one core in all, wrk at 100%, `kernel_task` at 103%, and the machine 70% idle.

### The shared listener

Per-thread CPU time after 3 s of JSON load at 256 connections: 0.39, 0.46, 1.17, and
0.54 s. One worker serves about twice the others' share. The listener is registered
edge-triggered in every worker's kqueue and `accept_all` takes the whole backlog, so the
first worker to wake takes each burst (task 006 measured 351 of 400). It doesn't change
the rate here, which the kernel caps.

### What fast servers do on macOS that this one doesn't

Each was a candidate change, measured in [The kqueue changes](#the-kqueue-changes-2026-10-11):

1. Accept only what kqueue reports. `EVFILT_READ` on a listener returns the backlog's
   length in `data`; nginx accepts that many and no more. Level-triggered registration
   with a cap per wake-up leaves the rest to other workers. A dedicated acceptor thread,
   as actix-server runs, spreads them evenly.
2. Register `EVFILT_WRITE` only after a send returns `EAGAIN`, as libuv does.
   The epoll loop added it for every connection. With `EV_CLEAR` it fires as each
   ACK frees buffer space: in a one-connection probe of 20,000 request-response round
   trips, `kevent` waits rose 39% and `recv` calls that returned `EAGAIN` doubled.
   Against the loopback cap, every extra wake-up is kernel time.
3. Fewer syscalls per accepted connection: `shim/kqueue.c` spends six (`F_DUPFD_CLOEXEC`
   and `close` for the `EMFILE` probe, `accept`, `FD_CLOEXEC`, `FIONBIO`, and the
   `kevent` add). The `FIONBIO` is redundant when the listener is non-blocking.
4. Keep workers on the performance cores with
   `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`; Apple Silicon has no
   CPU affinity. Default `WORKERS` to `hw.perflevel0.logicalcpu` (8 on the M1 Pro)
   rather than `hardware_threads()` (10).

## The kqueue changes (2026-10-11)

Measured natively before and after each change, with `WORKERS=4` and `wrk -t 4 -c 256
-d 10`, JSON and pipelined plaintext, 3 runs each, at a load average of 2-5. Syscalls
come from counters a script added to a copy of `shim/kqueue.c` for the measurement,
printed on `SIGUSR1`; per-worker CPU time from `ps -M`. Worker CPU and connections are
ranges over the JSON runs, the syscall columns are per JSON request, and all but the
ranges are medians of the 3 runs:

| Commit | worker CPU, s | connections per worker | `kevent` waits | events | `recv` | `recv` `EAGAIN` | JSON req/s | plaintext req/s |
|---|---|---|---:|---:|---:|---:|---:|---:|
| `b2e0337`, before | 0.8-4.4 | not counted | 1.95 | 1.91 | 1.47 | 0.47 | 35.96 K | 559 K |
| `e9399bb`, item 1 | 2.4-2.5 | 63-66 | 2.26 | 1.95 | 1.57 | 0.57 | 35.27 K | 549 K |
| `7d2ecad`, item 2 | 2.1-2.3 | 62-66 | 1.60 | 1.01 | 1.00 | 0 | 36.48 K | 572 K |
| `e87d7bf`, item 3 | 2.1-2.3 | 62-66 | 1.57 | 1.01 | 1.00 | 0 | 36.00 K | 568 K |
| `7a1b76b`, item 4 | 2.1-2.3 | 61-66 | 1.61 | 1.01 | 1.00 | 0 | 35.96 K | 564 K |

The rates stay at the loopback's limit; the syscalls show what changed.

1. Spread. Neither option in item 1 above spread connections: capping accepts at 16
   per pass left 21-126 per worker, and a level-triggered listener with one accept per
   wake left 12-113. The worker already awake, polling with a zero timeout, sees each
   arriving connection first. The shim now counts each worker's accepts on the shared
   listener and declines with `EAGAIN` while a worker has taken more than one past the
   average, with the listener level-triggered so a declined connection stays reported.
   More workers wake, so `kevent` waits rose 16% and the rate fell 2%. At the fd limit
   the decliners spun, 2 CPU seconds a second with 4 workers; `0edeac1` stops declining
   once the accepted count hasn't moved for 2 ms, and CPU at the limit is back to 0.02 s.
2. Write filter. Registering `EVFILT_WRITE` only while a send is pending halved the
   events per request and removed every `recv` that returned `EAGAIN`: the write filter
   had woken the worker as each ACK freed buffer space, and that wake-up drove a `recv`
   with nothing to read. JSON gained 3.6% and plaintext 4%. No send returned `EAGAIN`
   under this load, so the filter was never registered. On Linux the epoll loop measured
   the same before and after, within 0.7%, in Docker
   ([watch-out](../bench/results/2026-10-11-m1pro-docker-watch-out/summary.md)), and both
   loops pass their tests there.
3. Accept. `accept` costs three syscalls (`accept`, `FD_CLOEXEC`, and the `kevent` add)
   where it cost six: the `FIONBIO` was redundant, and the free-fd check runs only once an
   accepted fd comes within 64 of `getdtablesize()`. This load opens 256 connections, so
   the counts don't move. With 4 workers, a 300-fd limit, and 400 clients, the check
   raced: two workers passed it for the last free fd, and the loser's `accept` failed
   with `EMFILE`, dropping 0-9 of the 250 clients still waiting (also at `b2e0337`). The
   check and the `accept` now hold a lock near the limit, and 5 of 5 runs answered all
   250.
4. QoS. Workers take `QOS_CLASS_USER_INTERACTIVE`, confirmed with
   `pthread_get_qos_class_np`, and `WORKERS` defaults to `hw.perflevel0.logicalcpu` (8).
   Nothing measurable changed: with the machine 70% idle, the scheduler keeps the workers
   on the performance cores anyway. 8 workers served 35.6 K, with 25-34 connections each.

`scripts/test-unit.sh`, `scripts/test-http.sh`, and `scripts/test-echo.sh` passed
natively after each change, and `http_client.py slow` and `pipeline` 3 of 3 after
item 2.

## Acceptance criteria

- [x] The tests pass natively, and `slow` passes 10 of 10 runs
- [x] The short Docker matrix measured and recorded with its setup
- [x] A native comparison with `bench/run-macos.sh`, recorded with its setup
- [x] A profile of the kqueue server, and the listener's spread measured
- [x] Docker: vanilla-epoll and the Zig servers built for `aarch64-linux`, and the short
      matrix with wrk on more CPUs
- [ ] Docker: the full matrix (every test, 1 and 3 workers)
- [x] `bench/httparena.sh` under Docker on the Mac
- [x] Items 1 to 4 above tried, with the listener's spread and `kevent` calls per
      request before and after
