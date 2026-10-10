# 009: More competitors from HttpArena

Status: in-progress

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
- [ ] Task 004's matrix rerun with them, and the results, wins and losses, in this file
- [x] vanilla-epoll added too, or the reason it wasn't recorded here
- [ ] HttpArena's own harness (MIT) run locally with Goose as an entry: its endpoints and
      a Dockerfile, `scripts/validate.sh` passing, and its `baseline` (mixed GET and POST
      with query parsing), `limited-conn` (10 requests per connection), and `latency-1m`
      (CPU per request at a fixed offered load) profiles run for Goose and the servers
      above, the results recorded here
- [ ] The parser microbenchmark parses picohttpparser's and httparse's benchmark request
      (a browser's, with a long cookie) beside wrk's and a Chrome request, so its numbers
      compare with those parsers' published ones
- [ ] Where Goose loses a cell by more than the spread of its runs, the winner's source
      and a `perf` profile of both servers say what it does differently, as task 004's
      profile did; each idea is tried here or recorded with why not (a Goose finding, or
      a behavior the tests require)
- [ ] `bench/instructions.sh` run for every server too, with peak RSS added to what it
      records
- [ ] A results page, `docs/results.md`: the latest matrix for every server, with requests
      per second, p50 and p99 latency, instructions and cycles per request, peak RSS, server
      CPU time, and binary size, the machine and commands, and links to the task files
      that hold the runs behind it
- [ ] `README.md` gives a few headline numbers against the strongest competitors
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
  `/pipeline` (`docs/architecture/README.md`), and `bench/httparena/goose` is its
  HttpArena entry. HttpArena's `scripts/validate.sh` passes for it: 24 of 24 checks,
  including all 1,047 split offsets of `validate-frag.py`.
- `bench/httparena.sh validate` and `run` drive HttpArena's harness at `0720ee5` under
  Docker Desktop; the comment at its top lists what it changes in the checkout.
- odin-http is out of `bench/run.sh`'s default `SERVERS` (Kait, 2026-10-10): it matches
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
(`docs/architecture/README.md`). An intermediate version, kept as
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

Next, in the order of the criteria:

1. vanilla-epoll stays in the matrix unless Kait decides otherwise: it is the one server
   ahead of Goose in plaintext, though only because it skips parsing.
2. The parser corpus request (criterion 7), `bench/instructions.sh` with peak RSS, the
   matrix (about 120 minutes for six servers), profiles of any losses, then
   `docs/results.md` and the README summary.
3. Ideas to measure once the competitor profiles show where Goose loses, in this order:
   the `Connection` field (about 520 of the 1,270 instructions per parse of wrk's
   request, task 008); `inline fn`, new at `e7792d7` (spec §7.13), on `http::parse` and
   `answer`, separately; and fewer appends per response. `/baseline11` scans its query
   once per key, which matters only for HttpArena's profiles. dusty's limited-conn lead
   needs a profile.
