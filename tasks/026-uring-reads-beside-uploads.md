# 026: io_uring's reads beside uploads

Status: todo (asked for 2026-10-13)

In the REST benchmark's mixed run, tier C's reads at a fixed 16K a second beside
streaming uploads, the io_uring loop's read p99 is 7.8-11 ms and the epoll loop's
1.4-2.5 ms (`bench/results/2026-10-13-rest-rates`, step 4). Alone, both mostly stay
under 3 ms. io_uring is the default loop, so it should hold the epoll loop's latency without
losing its upload rate (754-773 a second there, epoll's 769-781).

## What's known (task 021, 2026-10-12 and 2026-10-13)

- The epoll loop reads at most `Config.max_read` (16 KB) from a connection per turn, so
  an upload yields to the other connections every 16 KB. Before that bound, reads beside
  uploads waited seconds.
- io_uring has no such turn: the kernel fills the ring's 4 KB provided buffers as data
  arrives, and a wait hands the worker up to 256 completions, most of them upload pieces
  during an upload. A read's completion waits behind every piece queued before it. That
  fits the remaining milliseconds, but isn't measured.
- A smaller completion batch doesn't help (`STEPS=4`, 2 rounds): read p99 6.8-11 ms at
  256, 8.9-17 at 64, 14-20 at 16, while plaintext fell from 6.62 M to 5.99 M requests a
  second. The loop keeps 256.
- A per-connection budget, holding a connection's bytes past 16 KB a pass and canceling
  its multishot receive while 8 KB were held, cut the read p99 to 4.2-10 ms but uploads
  alone from 1.1-1.2K to 275-282 a second. Dropped: canceling and re-arming the receive
  costs an upload far more than the reads gain.

## What to try

1. A budget that holds a connection's bytes without canceling its receive, bounded by
   the ring's 256 buffers rather than the 8 KB read buffer, so a busy upload yields its
   turn but keeps its receive armed.
2. Submitting a pass's sends, the reads' responses among them, before working through
   the held upload bytes.
3. Measure first where a read's time goes beside uploads: completions ahead of it per
   wait, and the time from its completion to its response's send.

## Acceptance criteria

- [ ] Where a read's milliseconds go beside uploads, measured
- [ ] The io_uring loop's read p99 beside uploads near the epoll loop's, with uploads
      alone and beside forms within 5% of today's, on the desktop (`STEPS="2 4"`, then
      `bench/run.sh` for plaintext and JSON)
- [ ] Each attempt's numbers recorded here, kept or dropped
