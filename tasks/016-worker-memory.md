# 016: What each worker commits

Status: todo (asked for 2026-10-12)

The Goose maintainer, shown the server's peak RSS, remarked that its workers commit some
memory, though not much (2026-10-12). Nothing here says where a worker's memory goes.
The numbers so far are totals: in `bench/instructions.sh`'s runs with one worker, the
epoll build peaks at 2.2-2.4 MB and the io_uring build at 5.0-5.4 MB (task 013, at
`28c478c`), and in the 4-worker matrix the io_uring build reached 12.4 MB with JSON at
1,024 connections (task 013, `bench/results/2026-10-12-night/`). After task 013's
100 MB streaming tests, peak RSS was 2.7 MB for epoll and 8.5 MB for io_uring.

Account for a worker's committed memory by source, then shrink what can be shrunk
without costing requests per second. Sources to measure, per worker:

- The thread itself: the stack `thread_spawn` gives it, and what the Goose runtime
  allocates per thread.
- glibc's malloc arena for the thread, and what stays committed in it after a burst
  (the spill pool, a grown `wbuf`, the connection slots).
- The read buffer (`Config.max_head`), the write buffer, the spill pool, and the
  connection slots, which grow with the connections a worker holds and never shrink.
- io_uring: the submission and completion rings (`Config.ring_entries`), the provided
  buffers (`ring_buffers` × `ring_buffer_size`, 1 MB by default), and `shim/uring.c`'s
  cache of freed send records, up to 4 MB a ring.
- The emulated ring (`shim/ring_epoll.c`) and IOCP (`shim/iocp.c`), which keep their
  own records.

Ask the maintainer which of the runtime's per-thread commits the remark meant, before
changing anything on the Goose side: that would be a finding for `docs/goose-findings.md`,
not a change here.

## Acceptance criteria

- [ ] A table of each worker's committed memory by source, for both loops on Linux,
      idle, after `bench/run.sh`'s largest plaintext cell, and after the streaming
      tests, with how each number was measured (`/proc/PID/smaps`, or allocator
      statistics)
- [ ] Each source that can shrink without costing requests per second does, measured
      with `bench/run.sh`'s cells or `bench/count.sh`, or is recorded as kept, with
      the reason
- [ ] What the maintainer's remark referred to, and whether anything on the Goose side
      is worth a finding
