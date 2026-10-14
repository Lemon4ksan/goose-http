# 017: Bring the IOCP loop closer to io_uring

Status: in-progress (asked for 2026-10-12)

The IOCP loop trails io_uring on the same machine, with most of its request time in
the kernel (the baseline below). Read the kernel trace before attributing the gap to
particular Winsock calls. Evaluate changes against that baseline and record losses
as well as gains.

## Setup

1. Install Ubuntu 26.04 in WSL2, beside the distributions already there. Ubuntu 22.04's
   liburing and kernel may be older than the io_uring loop needs (kernel 6.1+).
2. Build the Linux compiler in it and run `scripts/test.sh` (`docs/development.md`,
   "Set up the Goose compiler"). Record the kernel, liburing, and gcc versions in the
   toolchain table.
3. Before a new comparison, measure both sides at the same commit with the baseline's
   method below: oha 1.16.0, `-n 2000000 -c 256`, 1 and 4 workers. Record the source
   and compiler pins, kernel, run count, and CPU settings.

## Candidates

Measure where the kernel time goes first, with Windows Performance Recorder (`wpr
-start CPU`) during an oha run, and order these by what the trace shows:

- **Registered I/O (RIO).** `RIOSend` and `RIOReceive` into registered buffers, with
  completions in a RIO completion queue, skip the per-call buffer locking and IRP of
  overlapped I/O. It fits the ring's design: the ring already owns every buffer the
  kernel touches. The cost is a second code path in `shim/iocp.c`, since `AcceptEx` and
  file sends stay overlapped.
- **The accept path.** Each `AcceptEx` completion goes through an event and a registered
  thread-pool wait before it reaches the ring's port, a second thread and a context
  switch per connection. It matters for connection-heavy loads, not keep-alive ones.
- **Fewer receive calls.** Count how often a receive takes the zero-byte `WSARecv` and
  `recv` path rather than a direct `WSARecv` under the oha load, and whether more
  buffers per ring (`ring_buffers`) shift it.

## Acceptance criteria

Queued sends behind the one in flight are already implemented in `shim/iocp.c`.
They are no longer a candidate for this task's plaintext gap.

- [x] Ubuntu 26.04 in WSL2 runs `scripts/test.sh` on all three Linux loops, with its
      versions in `docs/development.md` (2026-10-12, on the desktop)
- [x] A baseline of both sides at one commit, measured as above (2026-10-12)
- [ ] A CPU trace of the IOCP loop under oha, with the top kernel costs per request
      recorded here: recorded, not yet read (below)
- [ ] Each candidate tried is recorded with its rate against the baseline, kept or
      reverted, and `scripts/test.sh` passing in Git Bash for each kept change
- [ ] The README's Windows row updated with the new ratio and how it was measured

## Baseline (2026-10-12)

The desktop of the earlier measurements (Ryzen 7 5800X3D, Windows 11 Pro 10.0.26200,
WSL2 Ubuntu 26.04.1 with kernel 6.18.40.1), both sides the code of `fcfd80d`, Goose
`5c83a5a`:
the IOCP build by MSVC 19.51 (`scripts/build.sh`), the Linux builds by gcc 15.2.0
(`bench/build.sh`). `bench/oha.sh` on each side: oha 1.16.0 (the Windows release, and
`cargo install` in WSL), `-n 2000000 -c 256` on `/plaintext`, 3 runs, nothing pinned,
CPU per request from the server's user and kernel time over the oha run. Results in
`bench/results/2026-10-12-iocp-plaintext` and `2026-10-12-uring-plaintext-oha`.

| Server | Workers | Requests per second | CPU per request, user/kernel |
|---|---:|---:|---|
| Windows, IOCP | 1 | 81,877-83,171 | 0.8-1.0/11.0-11.4 µs |
| Windows, IOCP | 4 | 224,625-246,586 | 1.3-1.6/14.8-16.2 µs |
| WSL2, io_uring | 1 | 160,811-164,676 | 0.2/5.8-5.9 µs |
| WSL2, io_uring | 4 | 598,151-614,809 | 0.3/5.9-6.1 µs |
| WSL2, epoll | 1 | 145,030-146,988 | 0.4/6.4 µs |
| WSL2, epoll | 4 | 478,401-520,197 | 0.7/6.9-7.4 µs |

IOCP trails io_uring by 2.0 times with 1 worker and 2.5-2.7 times with 4, as on
2026-10-11: the send-record size classes changed nothing measurable.

The trace: `wpr -start CPU` for 30 s in an elevated shell, during an oha run of 16
million requests against 1 worker (2026-10-12), a 688 MB `.etl` kept outside the
repository. The Windows Performance Toolkit installed here, 10.0.20348, can't read a
trace of this Windows build: `xperf -a profile` stops with `ISession::ProcessEvents
[0x80070032]`, with `-tle -tti` too. Reading it needs the current Windows Performance
Analyzer, from the Microsoft Store, or a fresh trace taken once it is installed.

## A/B on a second machine

The desktop isn't always at hand, so candidates are first compared on a laptop: Windows
11 Pro 10.0.26200, Ryzen 7 PRO 6850U (8 cores, 16 threads), Balanced power plan, other
programs open. Its absolute rates are a third of the desktop's, at 35-40 µs of kernel
time per request against 11, and drift with its temperature, so only pairs run back to
back count: each round runs every build once, with oha 1.16.0's Windows release, `-n
1000000 -c 256 --no-tui http://127.0.0.1:29380/plaintext`, 15 s apart. CPU per request
is the server's `UserProcessorTime` and `PrivilegedProcessorTime` as oha ends. Every
request returned 200. Base is `9d31cb1`, built by `scripts/build.sh` (MSVC 19.51).

**Receive paths.** With 1 worker and 256 connections, 2 of 3 receives take the zero-byte
`WSARecv` and `recv` path: 256 connections can't each hold one of the 256 buffers while
half must stay free. With 4 workers, 64 connections each, 99.4% go straight into a
buffer. `ring_buffers = 1024` won 4 rounds of 4 with 1 worker, by 0-13%, about 5% on
average: too close to the noise to keep, and on Linux 1,024 buffers cost twice the peak
RSS of 256 for nothing (task 005). Reverted.

**Where the time goes.** A plaintext server of about 200 lines of C over overlapped
`WSARecv` and `WSASend`, single-threaded, with no Goose in it, serves what the Goose
build does with 1 worker: 22,363-23,548 against 22,170-23,133 per second over 3 rounds,
at the same 40-42 µs of kernel time. Goose and the shim cost about 1%; the rest is the
kernel's.

**Registered I/O.** The same C server over `RIOReceive` and `RIOSend`, with its
completion queue signalling the port (`RIO_IOCP_COMPLETION`) and AcceptEx left
overlapped, gains 17-24% over the Goose build in each of 5 rounds with 1 worker
(26,715-32,051 per second), at 30-36 µs of kernel time. A zero-length `RIOReceive`
doesn't wait for data, as a zero-byte `WSARecv` does: it completes at once, so the
server spins on `recv` returning `WSAEWOULDBLOCK` and serves 7,237-7,333 per second.
Nor can a RIO socket fall back to a zero-byte overlapped `WSARecv`: once the socket has a
request queue, `WSARecv` fails with `WSAENOTSOCK` (10038), whether the socket was
associated with the port before the queue or not. A socket made with
`WSA_FLAG_REGISTERED_IO` rejects every overlapped `WSARecv` with the same error, even
with no request queue, so a socket is RIO or overlapped from its `WSASocket` on. So over
RIO, every connection with a
receive posted holds a registered buffer, unlike the shim's design, where idle
connections hold at most half of them.

A RIO socket past a cap can't fall back to the overlapped path either, tried in the
prototype and in `shim/iocp.c` (2026-10-12):

- AcceptEx gives a RIO socket a working receive only from a listener made with
  `WSA_FLAG_REGISTERED_IO`: from a plain one, its first `RIOReceive` completes at once
  with 0 bytes, as at end of stream.
- `SO_UPDATE_ACCEPT_CONTEXT` passes the flag on, so every socket accepted from a RIO
  listener refuses `FIONBIO` (`WSAEOPNOTSUPP`), RIO or not. A full-buffer overlapped
  `WSARecv` works on a plain socket from a RIO listener, but a zero-byte one never
  completes, and a 1-byte one completes with `FIONREAD` reporting 0 bytes waiting.
- `ProcessSocketNotifications` accepts a RIO socket's registration but never signals
  it readable, so a RIO receive can't wait for data before it takes a buffer.

So with RIO, every connection with a receive posted holds a buffer.

Not pursued (2026-10-12): a gain of about a fifth doesn't pay for dropping the buffer
bound and a second I/O path in the shim. The shim stays overlapped.
