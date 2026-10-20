# 057: Engine ideas from Aegon

Status: done (2026-10-20). The setting that requires io_uring is in; the three ideas
measured on the desktop were set aside, with their numbers under "Left out".

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
- **Parsing in the provided buffer** (measured 2026-10-20). goose-http copies a
  receive out of its provided buffer (`ur_take`'s `memcpy`) into the connection's read
  buffer. Parsing in place would save that copy, but would hold the buffer while the
  request runs, so the ring would need more buffers under load. The copy is about 1%
  of a request: a build whose `ur_take` copies twice, with a compiler barrier between
  the copies, costs 22.5 user instructions per request more on `/plaintext` (1,952.7
  against 1,930.2) and 21.7 more on `/json` (2,139.7 against 2,118.0). The counts
  were the same in every run. User cycles per request (458-476 against 458-467 on
  `/plaintext`, 496-501 against 506-507 on `/json`) and the rate (1.66-1.73 M a
  second on both) show nothing beyond the runs' spread. So the copy is set aside: a
  gain of 1% at most doesn't pay for a larger pool. Measured on the desktop: Ryzen 7
  5800X3D, WSL2 kernel `6.18.54.1-microsoft-standard-WSL2`, Goose `f114b5a`,
  goose-http `a4bcb7a3`. Both builds came from `ONLY=goose bench/build.sh` in
  `git archive` trees, the variant's `shim/uring.c` changed only there. Each ran
  `RUNS=3 bench/count.sh goose-uring goose-uring-double` with `TARGET` `/plaintext`
  and `/json`: one worker on io_uring on CPU 0, and h2load on CPUs 4-15 with 8
  threads, 256 connections, and 16 in flight on each, 10 M requests. With 16 in
  flight a read brings several requests, so a request's share of the copy is
  smaller than one receive's. goose-rest's tier A wasn't measured. Its requests are
  longer, so the copy's share there is somewhat larger, but the parse and the
  answer grow with them too.
- **Registered descriptors** (measured 2026-10-20). `IORING_OP_ACCEPT_DIRECT` and
  fixed files skip the fd table on every operation. The fd table costs 0.8% of the
  server's CPU, so registered descriptors can save no more than that. `perf record -C
  0` for 8 s, with kernel symbols, on `goose-uring` (goose-http `a4bcb7a3`, one worker
  on CPU 0) under the same h2load load as `bench/count.sh` (CPUs 4-15, 256
  connections, 16 in flight): `fget` 0.62%, `fput` 0.11%, and `io_file_get_normal`
  0.06% of CPU 0's samples on `/plaintext`, and 0.67%, 0.08%, and 0.05% on `/json`.
  The kernel took 73-75% of the CPU, mostly in TCP, and the server 21-22%. That's
  below the rate's run-to-run spread, and direct descriptors have no fd for the
  direct `send(2)` of bodies from 64 KB, or for `sendfile`, so they're set aside
  without building them. Same desktop and Goose as above.

  On bare metal the share is smaller still, 0.2% (2026-10-20): `fget` 0.08%, `fput`
  0.11%, and `io_file_get_normal` 0.03% on `/plaintext`, and 0.06%, 0.10%, and 0.04%
  on `/json`. The kernel took 47-49% of the CPU, Bazzite's `nf_tables` and
  `nf_conntrack` on loopback 15%, and the server 31-33%, at 5.2-5.4 M requests a
  second. Ryzen 5 9600X, Bazzite 43, kernel `6.17.7-ba29.fc43.x86_64`, in a Fedora
  43 distrobox, Goose `f114b5a`; `goose-uring` from `ONLY=goose bench/build.sh` at
  goose-http `ed811653` ("uring loop"), one worker on CPU 0; h2load 1.66.0 on CPUs
  1-5 and 7-11 with `bench/count.sh`'s options for 14 s, and `perf record -C 0` for
  8 s of it, with kernel symbols. One run per target.
- **Wider vector scanning in the parser** (measured 2026-10-20). Aegon falls back
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
  wider scan depends on what the C compiler vectorizes, which may decide the result.

  A wider scan wins only under clang and only from about 4 KB of head, so it is set
  aside. `parse` alone, 10 M times, on a REST call with a bearer JWT and a session
  cookie, the two split evenly, from 248 B to 8.5 KB of head. The value scan was
  either `find_any` or a `simd fn` that skips whole 32- or 64-byte blocks: it
  OR-reduces a flag per byte with no exit in the block, and `parse`'s byte loop
  finds the end within the block. Goose has no movemask, so the block can't say
  where the byte is. Best of 5 runs, in ns per parse, on CPU 2; user instructions per
  parse in brackets:

  | Head | `find_any`, gcc (as built) | `find_any`, clang | 32-byte, clang | 64-byte, clang | 64-byte, gcc |
  |---:|---:|---:|---:|---:|---:|
  | 248 B | **73 (1,588)** | 102 (1,798) | 133 (2,477) | 132 (2,470) | 107 (2,417) |
  | 513 B | **78 (1,797)** | 106 (1,985) | 137 (2,707) | 136 (2,652) | 121 (2,791) |
  | 1,043 B | **89 (2,192)** | 119 (2,380) | 137 (2,794) | 151 (3,004) | 149 (3,491) |
  | 2,106 B | **130 (2,997)** | 166 (3,185) | 175 (3,373) | 148 (2,993) | 180 (4,346) |
  | 4,232 B | 198 (4,593) | 227 (4,781) | 214 (4,162) | **175 (3,722)** | 287 (6,631) |
  | 8,481 B | 318 (7,773) | 348 (7,961) | 313 (6,442) | **256 (5,144)** | 461 (11,171) |

  - Under gcc, which builds the servers, `simd` does nothing (spec §7.12), and the
    blocks lose at every size, up to 1.4 times slower at 8 KB.
  - Under clang, with AVX2 (the desktop's Zen 3 has no AVX-512), the 64-byte block
    beats clang's `find_any` from about 2 KB of head, about 1 KB a value. It beats
    the gcc build only from about 4 KB: by 12% at 4.2 KB and 20% at 8.5 KB.
  - Choosing the scan by the value's length would need the whole server on clang,
    which costs 28-36 ns on every head here and more elsewhere (task 008). goose-rest's
    tier C heads are about 1.2 KB. So nothing is taken, and goose-rest's tier A wasn't
    run.
  - No finding was recorded: no benchmark of this package has heads where a wider
    scan pays.

  Ryzen 7 5800X3D, WSL2 kernel `6.18.54.1-microsoft-standard-WSL2`, Goose `f114b5a`
  (`-O2`), goose-http `0b28e4e4`'s `message.goose`, gcc 15.2.0 and clang 21.1.8 at
  `-O2`. The binaries ran on the desktop, with `perf stat -e instructions:u`. The
  generated C holds the AVX2 and AVX-512 versions and dispatches at run time. The
  programs and scripts weren't committed: like `bench/parse/*.goose`, each builds the
  request and parses it, and the block variant replaces `parse`'s `find_any` with
  the block skip.

## Taken

- **Requiring io_uring**, as Aegon's `AEGON_ENGINE=io_uring` does, so that running on
  epoll by mistake is visible: `Config.require_ring` (2026-10-20). `serve` then fails
  with call `io_uring` where it would emulate the ring. `test/http/require_ring.goose`
  checks it on macOS (`ENOSYS`) and on Linux, arm64 in Docker Desktop (`ubuntu:26.04`,
  kernel 7.0.14-linuxkit): under the default seccomp profile `serve` fails with
  `EPERM`, and with `seccomp=unconfined` it starts on io_uring.
- The benchmark servers and scripts don't set it (2026-10-20). They measure only on
  Linux machines where io_uring works, the server's startup line already names an
  emulated ring and its reason in each run's log, and setting it would need
  exceptions for macOS checks and for `-uring-epoll`.

## Acceptance criteria

- [x] Each idea under "To measure" measured and adopted, or set aside with its numbers
      (2026-10-20: all three set aside, under "Left out")
- [x] A setting that requires io_uring, in `docs/api.md`'s event loops section
      (2026-10-20)
