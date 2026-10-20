# 057: Engine ideas from Aegon

Status: in-progress. The verdicts below were set 2026-10-20; the setting that requires
io_uring is in.

Aegon's I/O engine (io_uring, epoll, and IOCP behind one interface,
[its guide](https://udaykhare09.github.io/Aegon/guide/core/io-engine)) is close to
goose-http's: multishot accept and receive into provided buffer rings,
`DEFER_TASKRUN` and `SINGLE_ISSUER`, a fallback to epoll, `AcceptEx` and `TransmitFile`,
and `SO_REUSEPORT`. goose-http also has kqueue, which Aegon plans. goose-rest's task 048
measures Aegon itself; its task 056 covers the API.

goose-http's memory is its lead. No idea is taken that trades memory for rate.

Whoever works on these, or on goose-http's WebSocket (task 054) or outbound connections
(task 053), reads the matching pages of Aegon's guide first, under
`https://udaykhare09.github.io/Aegon/guide/`: `core/io-engine`, `core/io-uring`,
`core/event-loop`, `core/buffer-pool`, `core/task`, `server`, `websocket`, and
`http-client`. They hold option names, defaults, and edge cases to check against.

## Left out

- **Large prefaulted buffer pools.** Aegon's HttpArena entry registers 16,384 buffers of
  4 KB per thread, mapped with `MAP_POPULATE` on 2 MB huge pages when it can: 4 GiB on
  64 threads, faulted in at startup, at 10K requests per second as at 4 M. It buys no
  rate on goose-rest's tiers: on 2026-10-19, with 4 workers, 256 buffers a thread came
  within 2.4% of 16,384 in every column, at 27 MB peak RSS on tier A against 282 MB
  (goose-rest's `docs/benchmarks.md`).
- **`SEND_ZC` for every send.** Zero-copy sends pay only for large bodies; from 64 KB
  goose-http already tries a direct `send(2)` (`docs/architecture.md`).

## To measure

Each on the Linux desktop, on goose-http's tiers and goose-rest's tier A, with
instructions per request, rate, and peak RSS before and after:

- **Parsing in the provided buffer.** goose-http copies a receive out of its provided
  buffer. Parsing in place saves that copy but holds the buffer while the request runs,
  so the ring needs more buffers under load. Measure the copy's share first; adopt only
  if the pool can stay at its size now.
- **Registered descriptors.** `IORING_OP_ACCEPT_DIRECT` and fixed files skip the fd
  table on every operation.
- **Wider vector scanning in the parser, at least for long headers.** Aegon falls back
  from AVX-512 to AVX2, SSE4.2, and scalar code. `message.goose` scans names and values
  with `find_any`, 16 bytes at a time with SSE2. Task 008 (archived) found no wider scan
  faster, but measured mostly short requests: wrk's 170 bytes, and one 1.9 KB Chrome
  request whose 1 KB cookie took parsing from 60 to 278 ns. goose-rest's requests carry
  bearer JWTs and session cookies, so long values are common there, and that verdict may
  have come too early (2026-10-20). Measure a parse-only run at header sizes from about
  256 B to 8 KB, with JWTs and cookies, comparing `find_any` with 32- and 64-byte scans
  under `simd` (AVX2, and AVX-512 where the desktop has it). Find whether a wider scan
  wins always, from some value length up, or never. If it wins only from some length,
  choose the scan by the value's length. Then confirm the gain on goose-rest's tier A
  with such a request. Goose has no explicit vector types or movemask (spec §7.12), so a
  wider scan depends on what the C compiler vectorizes, which may decide the result; an
  operation found missing goes in `docs/goose-findings.md`.

## Taken

- **Requiring io_uring**, as Aegon's `AEGON_ENGINE=io_uring` does, so that running on
  epoll by mistake is visible: `Config.require_ring` (2026-10-20). `serve` then fails
  with call `io_uring` where it would emulate the ring, and the benchmark servers exit
  with `REQUIRE_RING=1`, which `bench/run.sh`, `bench/rest.sh`, and `bench/files.sh`
  set. `test/http/require_ring.goose` checks it on macOS (`ENOSYS`) and on Linux, arm64
  in Docker Desktop (`ubuntu:26.04`, kernel 7.0.14-linuxkit): under the default seccomp
  profile the server exits with `EPERM`, and with `seccomp=unconfined` it serves on
  io_uring.

## Acceptance criteria

- [ ] Each idea under "To measure" measured and adopted, or set aside with its numbers
- [x] A setting that requires io_uring, in `docs/api.md`'s event loops section
      (2026-10-20)
