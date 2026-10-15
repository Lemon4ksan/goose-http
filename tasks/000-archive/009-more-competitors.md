# 009: More competitors from HttpArena

Status: done

Add the strongest epoll-era servers from [HttpArena](https://www.http-arena.com/) to
`bench/` and run them against Goose in task 004's matrix. may-minihttp, the fastest Rust
server task 004 found, has no published HttpArena results; raw servers there pipeline
3 to 4 times faster than hyper. HttpArena's numbers come from a 64-core Threadripper PRO
3995WX with 64 load threads and 4,096 connections, so none of them carries over to this
machine: each server is built and measured here.

From HttpArena's results on 2026-10-10 (`data.json`), requests per second at 4,096
connections:

| Server | Language, I/O | Pipelined 16 deep | Baseline | Role here |
|---|---|---:|---:|---|
| `tokio` entry | Rust, raw tokio (epoll), one current-thread runtime per core | 54.8 M (3rd) | 4.19 M (8th) | the fastest Rust bar on epoll |
| dusty | Zig, zio runtime (io_uring, epoll fallback), a framework | 4.4 M (49th) | 3.31 M (19th) | the realistic Zig server, beside hyper |
| vanilla-epoll | V, epoll, `SO_REUSEPORT` per thread | 40.1 M (10th) | 4.12 M (10th) | optional: a second raw epoll server |

dusty leads HttpArena's composite score, which sums 27 profiles, TLS, compression,
WebSocket, and databases among them; on the two this repository runs it is mid-table.
The `tokio` entry's source is in [MDA2AV/HttpArena](https://github.com/MDA2AV/HttpArena),
not in a crate of its own. The io_uring servers at the top of HttpArena (zix, zeemo,
libreactorng) belong to task 005.

## Acceptance criteria

- [x] The `tokio` entry and dusty in `bench/`, pinned to exact commits, built in their
      fastest documented configuration, with any deviation from it explained in a comment
      (`bench/README.md`)
- [x] Each passes `scripts/http_client.py tfb` and `many 4096`, with what else it passes
      recorded as in `bench/README.md`
- [x] Zig's version and install in `docs/development.md`
- [x] Task 004's matrix rerun with them, and the results, wins and losses, in this file
- [x] vanilla-epoll added too, or the reason it wasn't recorded here
- [x] HttpArena's own harness (MIT) run locally with Goose as an entry: its endpoints and
      a Dockerfile, `scripts/validate.sh` passing, and its `baseline` (mixed GET and POST
      with query parsing), `limited-conn` (10 requests per connection), and `latency-1m`
      (CPU per request at a fixed offered load) profiles run for Goose and the servers
      above, the results recorded here
- [x] The parser microbenchmark parses picohttpparser's and httparse's benchmark request
      (a browser's, with a long cookie) beside wrk's and a Chrome request, so its numbers
      compare with those parsers' published ones
- [x] Where Goose loses a cell by more than the spread of its runs, the winner's source
      and a `perf` profile of both servers say what it does differently, as task 004's
      profile did; each idea is tried here or recorded with why not (a Goose finding, or
      a behavior the tests require)
- [x] `bench/instructions.sh` run for every server too, with peak RSS added to what it
      records
- [x] A results page, `docs/results.md`: the latest matrix for every server, with requests
      per second, p50 and p99 latency, instructions and cycles per request, peak RSS, server
      CPU time, and binary size, the machine and commands, and links to the task files
      that hold the runs behind it
- [x] `README.md` gives a few headline numbers against the strongest competitors
      (requests per second, instructions per request, and peak RSS), losses included, and
      links `docs/results.md`

## Progress, 2026-10-10

Done, at Goose `e7792d7`:

- `bench/tokio`, `bench/dusty`, and `bench/vanilla-epoll`, built by `bench/build.sh` and
  run by default in `bench/run.sh`; their pins, flags, and deviations are in
  `bench/README.md`. dusty runs on io_uring here, zio's choice on this kernel, as
  odin-http does.
- All three pass `tfb` and `many 4096`. `keepalive` fails on HTTP/1.0 in every
  competitor; `bench/README.md` breaks it down check by check.
- The Goose server accepts chunked request bodies and serves `/baseline11` and
  `/pipeline` (`docs/architecture.md`), and `bench/httparena/goose` is its
  HttpArena entry. HttpArena's `scripts/validate.sh` passes for it: 24 of 24 checks,
  including all 1,047 split offsets of `validate-frag.py`.
- `bench/httparena.sh validate` and `run` drive HttpArena's harness at `0720ee5` under
  Docker Desktop; the comment at its top lists what it changes in the checkout.
- odin-http is out of `bench/run.sh`'s default `SERVERS` (2026-10-10): it matches
  hyper in JSON and reaches 5-8% of Goose in plaintext, as in task 004. `bench/build.sh`
  still builds it.
- A full matrix of Goose alone, before the change below: `bench/results/2026-10-10-baseline`.

### HttpArena's profiles

All runs on the Ryzen 7 5800X3D (16 logical CPUs), WSL2 kernel
6.18.40.1-microsoft-standard-WSL2, Docker Desktop 29.8.2, with
`bench/httparena.sh run`: each server on CPUs 0-3, gcannon on CPUs 4-15 with 4 threads,
the best of 3 runs of 5 s per cell, latency-1m at 200,000 requests per second, Goose at
`453a852`. Results in `bench/results/httparena-2026-10-10`. Memory is the container's,
socket buffers included.

| Profile | Goose | tokio | vanilla-epoll | dusty |
|---|---:|---:|---:|---:|
| baseline, req/s | 469K | 500K | 461K | 403K |
| limited-conn, req/s | 304K | 298K | 294K | 348K |
| pipelined, req/s | 6.62M | 6.24M | 6.78M | 0.58M |
| latency-1m, CPU per request | 11.13 µs | 10.80 µs | 11.33 µs | 14.43 µs |
| latency-1m, p99 | 231 µs | 226 µs | 327 µs | 168 µs |
| baseline, memory | 101 MiB | 168 MiB | 78 MiB | 176 MiB |

Every server held at least 99.5% of latency-1m's rate. The servers used 205-354% of their
400% CPU, so baseline and pipelined may measure gcannon as much as the servers. dusty's
limited-conn lead is unexplained: the cost of accepting in Goose isn't it (below).

### A quick pass of the matrix

`RUNS=1 DURATION=3 WARMUP=1 LATENCY=0 bench/run.sh` for all seven servers takes about 6
minutes (`bench/results/2026-10-10-quick`). Three such runs of Goose alone
(`bench/results/2026-10-10-quick-noise`) spread by 0.8-7.5% per cell, under 2% in most
4-worker cells, so one pass settles only differences above about 8%; for tuning, compare
medians of `RUNS=3`. Against Goose, in that one pass:

- vanilla-epoll: 1.10-1.15 times Goose in plaintext with 4 workers, level with 1. It
  answers `GET /plaintext ` from fixed bytes before parsing (`bench/README.md`). In JSON
  it reaches 0.52-0.59 times Goose with 600 MB to 2.1 GB of RSS: `-gc none`, HttpArena's
  build, never frees the JSON encoder's allocations.
- tokio 0.69-0.79 in plaintext and 0.96-1.00 in JSON; may-minihttp 0.64-0.82 and
  0.93-0.98; hyper 0.40-0.53 and 0.63-0.73; dusty 0.05-0.07 and 0.62-0.90.

### Connection slots without buffers

Goose's 16 KB slots, with both buffers inline, were resident in full: the compiler writes
the whole `Conn` on every accept (`docs/goose-findings.md`, two entries). The buffers now
belong to the worker, and a slot keeps leftovers in a `reusable[]` spill pool
(`docs/decisions.md`). An intermediate version, kept as
`bench/results/2026-10-10-slots/server-a.goose`, reused freed slots field by field
instead of through `alloc_index`.

Medians of `SERVERS="goose-o goose-a goose-b" RUNS=3 DURATION=3 WARMUP=1 LATENCY=0
bench/run.sh` (`bench/results/2026-10-10-slots`): `goose-o` is `453a852`, `goose-a` the
intermediate version, `goose-b` the change.

| Cell | o req/s | a req/s | b req/s | o RSS | b RSS |
|---|---:|---:|---:|---:|---:|
| plaintext, 256 conns, 4 workers | 4.946 M | 5.026 M | 5.016 M | 6.8 MB | 2.3 MB |
| plaintext, 4,096, 1 | 1.342 M | 1.301 M | 1.365 M | 66.3 MB | 2.3 MB |
| plaintext, 4,096, 4 | 4.591 M | 4.566 M | 4.701 M | 68.2 MB | 2.5 MB |
| json, 1,024, 1 | 0.106 M | 0.108 M | 0.113 M | 18.2 MB | 2.2 MB |
| json, 1,024, 4 | 0.364 M | 0.367 M | 0.379 M | 19.0 MB | 2.4 MB |

The other five cells move by 1-3% either way, inside their spreads; vanilla-epoll holds
54.8 MB at 4,096 connections and 4 workers. HttpArena for `goose-b`
(`bench/results/httparena-2026-10-10-slots`, settings as above): baseline 492K, pipelined
6.86M, latency-1m 10.91 µs per request with p99 203 µs, container memory 33 MiB in
baseline against 78 MiB for vanilla-epoll. limited-conn, three rounds of o, a, and b in
turn (`bench/results/httparena-2026-10-10-limited-conn`): 307K to 314K for all three,
with 141-150 MiB for o and a and 36-37 MiB for b.

### The parser corpus request

`bench/parse/pico.goose` parses picohttpparser's benchmark request (`bench.c` at
`h2o/picohttpparser` `465a7ff`, 725 bytes), and `bench/parse/httparse.goose` httparse's
(`benches/parse.rs` at `seanmonstar/httparse` `a0fa552`), which adds 17 bytes of cookie.
picohttpparser's README shows only a chart from fast-http's 2014 benchmark, and httparse's
README shows no numbers, so both parsers' benchmarks ran here too.

All on the Ryzen 7 5800X3D, WSL2 kernel 6.18.40.1-microsoft-standard-WSL2, gcc 15.2.0,
rustc 1.99.0, pinned to CPU 2, Goose at `e7792d7`. Goose and picohttpparser: 10 M parses
per process, instructions from `perf stat -e instructions:u`, the best of 5 runs, and the
median of 3 such runs (`bench/parse.sh` for Goose). httparse: its `req` benchmark under
`cargo bench` with its `[profile.bench]` (`lto = true`, `codegen-units = 1`,
`opt-level = 3`), criterion 0.3.6, the median of 3 runs' estimates.

| Parser, build | Request | Instructions per parse | ns per parse |
|---|---|---:|---:|
| Goose, `goose -O2`, gcc `-O2` | picohttpparser's | 3,497 | 155.9 |
| Goose, the same | httparse's | 3,511 | 156.6 |
| picohttpparser, gcc `-O2` | picohttpparser's | 5,207 | 217.8 |
| picohttpparser, gcc `-O2 -msse4.2` | picohttpparser's | 1,770 | 108.0 |
| httparse 1.10.1, default (runtime SIMD detection) | httparse's | | 168.0 |
| httparse 1.10.1, `-C target-cpu=native` | httparse's | | 144.7 |

Goose takes 44% longer than picohttpparser built with SSE4.2, whose fast path compiles
in only under that flag, and 8% longer than httparse built for this CPU. It beats
picohttpparser without SSE4.2 by 28% and httparse's default build by 7%. The comparison
favors the other two: Goose's `parse` also checks `Host`, `Content-Length`,
`Transfer-Encoding`, and `Connection`, while they only split the head into slices, and
`pico.goose` cycles through four copies of the request where `bench.c` parses one
buffer.

## Progress, 2026-10-11

Goose at `752c3ce`. Measured on the machine above, as root where `perf` counts.

### Instructions and peak RSS before tuning

`bench/instructions.sh` (one worker on CPU 0, plaintext pipelined 16 deep at 256
connections, 3 runs) now records peak RSS. Before the rounds below, Goose at `135fed2`
(`bench/results/2026-10-11-instructions`; `goose-b` is the same source on the old pin):

| Server | req/s | Instructions per request | In user code | Cycles per request | Peak RSS |
|---|---:|---:|---:|---:|---:|
| goose | 1.48-1.56 M | 2,619-2,664 | 1,634-1,662 | 2,132-2,204 | 2.2 MB |
| vanilla-epoll | 1.57-1.65 M | 1,731-1,745 | 754-760 | 1,991-2,062 | 5.6 MB |
| tokio | 1.15-1.20 M | 4,342-4,400 | 3,405-3,450 | 2,774-2,889 | 10.3 MB |
| may-minihttp | 1.10-1.13 M | 2,969-3,047 | 1,938-1,991 | 2,785-2,847 | 68.3 MB |
| hyper | 0.75-0.77 M | 6,205-6,275 | 5,254-5,325 | 4,294-4,421 | 7.3 MB |
| dusty | 0.08 M | 20,390-20,493 | 8,034-8,076 | 27,475-29,209 | 9.0 MB |

The pin move changed nothing here: `goose-b` counts 2,619-2,647.

### Tuning rounds

Each round was built beside the previous one and measured side by side; the tables are
in `bench/results/2026-10-11-rounds` and `bench/results/2026-10-11-r1`.

1. Kept (`10e1a5d`): a `recv` that returns less than it was given emptied the socket,
   so `advance` no longer follows it with one that returns `EAGAIN`, unless the event
   reported a hang-up; tokio's `recv` count under limited-conn (below) shows it does
   the same. The quick matrix (`RUNS=3 DURATION=3`): JSON 1.06-1.08 times the previous
   version in all four cells, plaintext 1.03-1.07 in five of six; plaintext at 4,096
   connections and one worker read 0.96, with a spread of 1.29-1.42 M and three clock
   steps. After this round and the next, HttpArena's baseline rose from 469K to 549K,
   ahead of tokio's 518K, and limited-conn from 304K to 318K, against tokio's 320K and
   dusty's 357K (`bench/results/httparena-2026-10-11-r2`, settings as on 2026-10-10).
2. Kept (`bfd9605`): `eq_fold` compares `c | 32` without a branch and is an `inline fn`,
   and `find_any` scans field names and the target. Per parse, `bench/parse.sh`:

   | `parse` | Chrome's | picohttpparser's | wrk's | wrk's without `Connection` |
   |---|---:|---:|---:|---:|
   | before | 6,184 / 285 ns | 3,497 / 156 ns | 1,285 / 58.7 ns | 762 / 32.9 ns |
   | `eq_fold` alone | 5,991 / 273 ns | 3,321 / 145 ns | 1,130 / 48.6 ns | 746 / 32.6 ns |
   | all three | 5,022 / 223 ns | 2,802 / 124 ns | 1,179 / 50.7 ns | 813 / 35.3 ns |

   A `find_any` call costs more than a byte loop over a 4- to 10-byte name, so the two
   scans cost wrk's short request 2 ns and save 20-60 ns on the browser requests; at
   about 600 ns per request in the server, 2 ns is 0.3%. Testing the first 16 bytes one
   at a time before calling `find_any` doubled the cost of every request instead. In the
   server, user instructions per request fell from about 1,640 to 1,490. Goose now
   parses picohttpparser's request in 124 ns, against 108 ns for picohttpparser with
   SSE4.2 and 145 ns for httparse built for this CPU.
3. Dropped: registering a new socket for `EPOLLOUT` only once a `send` would block.
   A writable socket reports at once when added, so each new connection took a wakeup
   and a `recv` that returned `EAGAIN`. The change removed that `recv` (1.2 to 1.1 per
   request under limited-conn) and moved no rate: HttpArena's limited-conn 315K against
   318K, and 376-389K against 387-389K locally. The test it needed stays
   (`3f4fcdd`): a client that reads only after the server's `send` blocked.
4. Kept (`7cb3e27`): a response takes 7 appends instead of 11; the status line carries
   `Server` and the start of `Date`. User instructions per request 1,408-1,426 against
   1,497-1,515, cycles 1,889-1,913 against 1,917-1,939.
5. Dropped: `inline fn` on `http::parse`. 1,376-1,400 user instructions per request
   against 1,419-1,426, but cycles moved both ways and the rate fell 1-2%.
6. Kept (`823d5f6`), after the matrix below: a wait that returned events is followed by
   one with timeout 0, and the worker blocks only after that comes back empty, as
   vanilla-epoll's loop does (`server/backend_epoll/worker_linux.c.v` at `091c014`).
   `RUNS=5 DURATION=10` in three cells, beside the previous version and vanilla-epoll
   (`bench/results/2026-10-11-r6b`): 1.01-1.02 times the previous version in all six,
   inside the spreads, where vanilla-epoll read 0.99-1.04. The quick matrix
   (`bench/results/2026-10-11-r6`) read 0.99-1.10. Under HttpArena
   (`bench/results/httparena-2026-10-11-r6`), limited-conn 313K against 310K, and
   latency-1m 10.59 µs of CPU per request against 10.44 µs, with p99.9 at 2.9 ms
   against 12.7 ms. Locally, limited-conn read 375-378K against 379-382K.

### limited-conn

dusty's limited-conn lead exists under Docker only. Run outside Docker with gcannon
`11c802b` built in WSL, at the same settings (`bench/results/2026-10-11-rounds/
limited-conn-local.txt`), tokio reached 400K, Goose 368-389K, and dusty 334K, with
Goose's four workers within 5% of each other in CPU time. Goose and tokio make the same
syscalls per request but two: Goose calls `epoll_wait` 0.30 times per request where
tokio calls it 0.11 times, and `recv` once more per connection (round 3 above). Under
Docker, Goose's container reports 226% of its 400% CPU in limited-conn, where the same
load outside Docker keeps its workers about 80% busy. The likely cause is kernel network
work that the container's cgroup isn't charged for; per-thread CPU times inside the
container would settle it. Either way, HttpArena's CPU and memory columns compare
containers, not processes.

### The matrix

`bench/run.sh` with its defaults, Goose at `7cb3e27` (after round 5): six servers,
servers on CPUs 0-3, wrk and h2load on CPUs 4-15 with 8 threads, 3 runs of 15 s after
5 s of warm-up per cell, about 115 minutes (`bench/results/2026-10-11-matrix`, whose
`summary.md` has every column). Requests per second from wrk, medians, as a multiple of
Goose's:

| Cell | Goose | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|
| plaintext, 256 conns, 1 worker | 1.773 M | 1.09 | 0.76 | 0.68 | 0.48 | 0.05 |
| plaintext, 256, 4 | 5.719 M | 1.07 | 0.67 | 0.42 | 0.47 | 0.07 |
| plaintext, 1,024, 1 | 1.939 M | 0.99 | 0.69 | 0.67 | 0.36 | 0.04 |
| plaintext, 1,024, 4 | 5.717 M | 1.05 | 0.67 | 0.75 | 0.47 | 0.06 |
| plaintext, 4,096, 1 | 1.537 M | 0.99 | 0.78 | 0.71 | 0.45 | 0.06 |
| plaintext, 4,096, 4 | 5.756 M | 0.95 | 0.63 | 0.69 | 0.44 | 0.06 |
| json, 256, 1 | 0.145 M | 0.49 | 0.91 | 0.86 | 0.59 | 0.65 |
| json, 256, 4 | 0.435 M | 0.50 | 0.90 | 0.85 | 0.69 | 0.85 |
| json, 1,024, 1 | 0.122 M | 0.50 | 0.91 | 0.90 | 0.59 | 0.61 |
| json, 1,024, 4 | 0.423 M | 0.51 | 0.90 | 0.85 | 0.71 | 0.76 |

Goose leads every JSON cell and every plaintext cell but three, which vanilla-epoll
takes. Two of those are outside the spread of Goose's runs: at 256 connections,
vanilla-epoll's slowest run (1.900 M with one worker, 6.051 M with four) beats Goose's
fastest (1.898 M, 5.807 M). At 1,024 connections and four workers the runs overlap
(5.336-5.946 M against 5.940-6.000 M). Goose's peak RSS is 2.1-2.6 MB in every cell;
the others range from 5.6 MB (vanilla-epoll) to 621 MB (may-minihttp at 4,096
connections), and vanilla-epoll's grows to 5.9-15.1 GB in JSON, the `-gc none` leak.

Latency, from h2load, which is slower than wrk here and offers each server about the
same load (3.4-3.6 M requests per second in plaintext with four workers):

- Goose's p50 is the lowest or within 0.04 ms of it, except in four cells at 1,024 and
  4,096 connections where hyper or dusty answers some connections at once and starves
  others: their p50 is 2.6-5.2 ms there, and their p99 111-773 ms.
- Goose's p99 trails in plaintext at 256 and 1,024 connections: 3.87 ms against
  vanilla-epoll's 3.13 ms with one worker at 256; with four workers, 1.74 ms against
  1.43-1.53 ms (may-minihttp, vanilla-epoll, tokio) at 256, and 5.56 ms against
  5.30-5.32 ms at 1,024. In the other seven cells Goose's p99 is the lowest.
- dusty dropped 1,266 requests at 4,096 connections with one worker; no other cell had
  errors.

HttpArena's four profiles at the same version, settings as on 2026-10-10
(`bench/results/httparena-2026-10-11-r5`):

| Profile | Goose | tokio | vanilla-epoll | dusty |
|---|---:|---:|---:|---:|
| baseline, req/s | 529K | 503K | 488K | 438K |
| limited-conn, req/s | 310K | 316K | 313K | 353K |
| pipelined, req/s | 7.34M | 6.69M | 7.05M | 0.59M |
| latency-1m, CPU per request | 10.44 µs | 10.67 µs | 11.03 µs | 14.54 µs |
| latency-1m, p99 | 173 µs | 172 µs | 204 µs | 162 µs |
| baseline, memory | 33 MiB | 170 MiB | 77 MiB | 159 MiB |

Goose loses limited-conn to all three, by 1-2% to tokio and vanilla-epoll, inside the 304-318K
that Goose's own runs of it spread over since 2026-10-10, and by 12% to dusty, whose lead exists under Docker only (above).

### The final run, stopped

A run of everything at `823d5f6` (round 6) started at 03:30: the matrix, then
`bench/instructions.sh` for all six servers, then HttpArena's four profiles. Claude Code
stopped it at 120 of the matrix's 180 cells, in round 2, when the host ran short of
memory in vanilla-epoll's JSON cell at 1,024 connections with four workers
(`docs/development.md`, the `-gc none` leak). Its first two rounds are in
`bench/results/2026-10-11-final/runs.tsv`, without a summary. In them Goose read 1.90-1.94
M in plaintext at 256 connections with one worker, against vanilla-epoll's 1.90 M, and
5.77-5.79 M with four workers, against 6.12-6.13 M: round 6 closed the one-worker gap,
and the four-worker one is still about 6%.

An earlier `bench/instructions.sh` for all servers, at `7cb3e27`, stopped at
vanilla-epoll in its first round: wrk's connections were refused, though `nc -z` had
connected. The run before tuning (above) had none of that in three rounds. Goose in its
first round: 2,332 instructions per request, 1,403 in user code, 1,909 cycles, and
2.2 MB.

### The final run

Everything again at `b6a26c5` (round 6, Goose `f084e52`), from 07:26 to 09:38: the matrix
split in two, plaintext for all six servers and JSON for all but vanilla-epoll; then
`bench/instructions.sh`, `bench/parse.sh`, `perf` profiles of Goose and vanilla-epoll in
the plaintext cells, HttpArena's four profiles, and last vanilla-epoll's JSON cells under
a memory watchdog. The watchdog stopped vanilla-epoll in its first JSON cell, when the
host's free memory fell below 3 GB. Results in `bench/results/2026-10-11-final2-*` and
`bench/results/httparena-2026-10-11-final2`, and as tables in `docs/results.md`, which
also lists every loss. Builds and tests ran pinned to CPU 15 beside it.

- Plaintext: Goose leads four of six cells. vanilla-epoll leads with 4 workers at 256 and
  1,024 connections by 1%, inside both servers' spreads, where the `7cb3e27` matrix had
  it ahead by 7% and 5%.
- JSON: Goose leads all four cells, 1.03-1.08 times tokio, the next.
- Instructions per request with one worker: Goose 2,255-2,371, vanilla-epoll
  1,756-1,765, may-minihttp 2,983-3,011, tokio 4,330-4,375.
- The `perf` profiles with 4 workers (`*.prof`, `*.stat` beside the instruction counts):
  Goose and vanilla-epoll spend the same cycles per request, 2,819 against
  2,787-2,819, and the same kernel instructions, about 1,000. Goose runs about 740 more
  in user code, 1,464-1,520 against 780-791, most of them in `parse`.
- HttpArena: Goose leads baseline (545K against tokio's 496K) and pipelined (7.07M
  against vanilla-epoll's 7.01M), ties tokio on latency-1m's CPU per request (10.91 µs
  against 10.90 µs), and trails tokio (314K) and dusty (348K) in limited-conn at 308K.

vanilla-epoll's idea, answering `GET /plaintext ` from its first bytes, isn't taken here:
the server then skips the checks the tests require of every request, such as a 400 for an
HTTP/1.1 request without `Host` (`scripts/http_client.py hostile`). What remains of the
gap is `parse`'s cost; 43% of its cycles on wrk's request are in `find_any`, which costs
more per call than the 4- to 10-byte names it scans (task 004's profile and
`docs/goose-findings.md`, "The stdlib has no fast byte search, and no word loads").

Settings for the next session:

- The pin is at `efe3155`. All tests, every finding's minimal program, and the `simd fn`
  finding's timing give the same results there as at `752c3ce`, where everything above
  before the final run was measured. `efe3155` generates the same C for the server as
  `f084e52`, where the final run's servers were built, but for the stdlib's file paths.
- For a tuning change, build each version as `build/bench/goose-<name>` and run them
  side by side, `SERVERS="goose-o goose-b" RUNS=3 DURATION=3 WARMUP=1 LATENCY=0
  bench/run.sh`, about 5 minutes for two; `RUNS=5 DURATION=10` with `TESTS` for a
  difference near 2%. Separate sessions drifted by up to 5%.
- `bench/httparena.sh` copies `src/` from the working tree, so swapping
  `src/server.goose` between runs compares versions under HttpArena too.
