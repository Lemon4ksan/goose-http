# 024: Close the 64 KB file gap to nginx

Status: todo (asked for 2026-10-13)

nginx beats Goose at 64 KB files, the one size in `bench/files.sh` where it wins: 2.31
GB/s against epoll's 2.23 and io_uring's 2.08 with 1 worker, and 8.15 against 7.41 and
6.42 with 4 ([results](../docs/results.md#static-files), 2026-10-12, `fcfd80d`).

## What's known (2026-10-13)

- A file of 64 KB and up already takes the zero-copy path: `send_file` copies a body
  only under `DIRECT_MIN` (`file.goose`), and the test is `>=`. The 64 KB column
  measures `sendfile` on epoll and two splices through a pipe on io_uring.
- Copying wouldn't do better. Task 020's sweep
  ([2026-10-12-files-cutoff](../bench/results/2026-10-12-files-cutoff/summary.md), 1
  worker, 2 runs of 5 s, one build) put copy and zero-copy at 64 KB at 2.01 / 2.28 GB/s
  on epoll and 2.03 / 2.13 on io_uring. With 4 workers only `4a65d96`, which copied
  every file, was measured: 6.79 GB/s against the current epoll loop's 7.41.
- The emulated ring, which also sends with `sendfile`, is faster than the epoll loop and
  than nginx with 1 worker: 2.90 GB/s with 1 worker and 7.85 with 4, against epoll's
  2.23 and 7.41. Its CPU per request at 64 KB is 22.8 µs against epoll's 29.7 and
  nginx's 28.6. Nothing records why.
- nginx runs with `tcp_nopush` (`TCP_CORK`), which puts the head and the file's first
  bytes in the same segments. Whether Goose sends its head in a segment of its own isn't
  measured.

## Plan

1. Find what the emulated ring does differently from the epoll loop at 64 KB: the
   syscalls per request (`strace -c`), the segments per response (`ss -ti` or a
   capture on loopback), and how each sends the head before `sendfile`.
2. Try sending the head and the file's start together on epoll: `MSG_MORE` on the head's
   `send`, or `TCP_CORK` around the pair, and measure 64 KB and 1 MB.
3. Then io_uring: whether `IORING_OP_SEND` with `MSG_MORE` before the splices helps, or
   whether its splices lose to `sendfile` at 64 KB anyway (task 020 saw them cost more
   from 32 KB up), so that a copy or another path wins below a higher cutoff there.

## Acceptance criteria

- [ ] Why the emulated ring beats the epoll loop at 64 KB, measured and recorded here
- [ ] Each loop's 64 KB rate against nginx, 1 and 4 workers, on the desktop, before
      and after any change, in `docs/results.md`
- [ ] `DIRECT_MIN` per loop rechecked if the paths change, with the sweep's sizes
