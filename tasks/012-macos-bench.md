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

Goose leads every cell of the short matrix, by 5-17% over tokio and by more over the
rest; the epoll loop leads the io_uring loop by 4-8% in plaintext. wrk used most of its
6 CPUs in the top cells, so the matrix is client-bound there, and vanilla-epoll, the
closest competitor on WSL2, didn't build for arm64 (the details are in `docs/results.md`).
Next: build vanilla-epoll and the Zig servers for `aarch64-linux`, and give wrk more of
the VM's CPUs.

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

Each is a candidate change, unmeasured here:

1. Accept only what kqueue reports. `EVFILT_READ` on a listener returns the backlog's
   length in `data`; nginx accepts that many and no more. Level-triggered registration
   with a cap per wake-up leaves the rest to other workers. A dedicated acceptor thread,
   as actix-server runs, spreads them evenly.
2. Register `EVFILT_WRITE` only after a send returns `EAGAIN`, as libuv does.
   `src/server.goose:73` adds it for every connection. With `EV_CLEAR` it fires as each
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

## Acceptance criteria

- [x] The tests pass natively, and `slow` passes 10 of 10 runs
- [x] The short Docker matrix measured and recorded with its setup
- [x] A native comparison with `bench/run-macos.sh`, recorded with its setup
- [x] A profile of the kqueue server, and the listener's spread measured
- [ ] Docker: vanilla-epoll and the Zig servers built for `aarch64-linux`, and the full
      matrix with wrk on more CPUs
- [ ] `bench/httparena.sh` under Docker on the Mac
- [ ] Items 1 and 2 above tried, with the listener's spread and `kevent` calls per
      request before and after
