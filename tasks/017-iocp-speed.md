# 017: Bring the IOCP loop closer to io_uring

Status: todo (asked for 2026-10-12)

On the same machine, the IOCP loop serves 2 to 2.5 times fewer requests per second than
io_uring in WSL2 (`docs/development.md`, "After the IOCP changes"): 83-84 K against
172 K with 1 worker, and 248-254 K against 630-647 K with 4. Each request costs about
11 µs of kernel time and under 1 µs of user time, so the gap is in the Winsock calls a
request makes, not in Goose. Find which calls cost most, cut them, and record the rate
after each change, losses included. Run it on the desktop of the earlier measurements.

## Setup

1. Install Ubuntu 26.04 in WSL2, beside the distributions already there. Ubuntu 22.04's
   liburing and kernel may be older than the io_uring loop needs (kernel 6.1+).
2. Build the Linux compiler in it and run `scripts/test.sh` (`docs/development.md`,
   "Set up the Goose compiler"). Record the kernel, liburing, and gcc versions in the
   toolchain table.
3. Measure the current commit as the baseline, both sides, with the method of "After the
   IOCP changes": oha 1.16.0, `-n 2000000 -c 256`, 1 and 4 workers. The baseline
   includes the IOCP send-record size classes of task 016, which no measurement covers
   yet.

## Candidates

Measure where the kernel time goes first, with Windows Performance Recorder (`wpr
-start CPU`) during an oha run, and order these by what the trace shows:

- **Registered I/O (RIO).** `RIOSend` and `RIOReceive` into registered buffers, with
  completions in a RIO completion queue, skip the per-call buffer locking and IRP of
  overlapped I/O. It fits the ring's design: the ring already owns every buffer the
  kernel touches. The cost is a second code path in `shim/iocp.c`, since `AcceptEx` and
  file sends stay overlapped.
- **A queued send behind the one in flight** (task 013, "Next"). The loop copies a large
  response's pieces into `c.out` because `shim/iocp.c` holds one send per connection.
  It affects large responses, not the plaintext rate.
- **The accept path.** Each `AcceptEx` completion goes through an event and a registered
  thread-pool wait before it reaches the ring's port, a second thread and a context
  switch per connection. It matters for connection-heavy loads, not keep-alive ones.
- **Fewer receive calls.** Count how often a receive takes the zero-byte `WSARecv` and
  `recv` path rather than a direct `WSARecv` under the oha load, and whether more
  buffers per ring (`ring_buffers`) shift it.

## Acceptance criteria

- [ ] Ubuntu 26.04 in WSL2 runs `scripts/test.sh` on all three Linux loops, with its
      versions in `docs/development.md`
- [ ] A baseline of both sides at one commit, measured as above
- [ ] A CPU trace of the IOCP loop under oha, with the top kernel costs per request
      recorded here
- [ ] Each candidate tried is recorded with its rate against the baseline, kept or
      reverted, and `scripts/test.sh` passing in Git Bash for each kept change
- [ ] The README's Windows row updated with the new ratio and how it was measured
