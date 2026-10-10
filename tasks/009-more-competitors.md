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
  Docker Desktop; the comment at its top lists what it changes in the checkout. Smoke
  runs only so far (one run each, not results): `baseline` at 4 gcannon threads gave
  Goose 466K, tokio 473K, and vanilla-epoll 463K requests per second.

Next, in the order of the criteria:

1. `bench/httparena.sh run` for the four frameworks. Not yet checked: that dusty holds
   latency-1m's 200,000 requests per second (`LATENCY_RATE`), and how long the
   competitors' images take to build the first time (vanilla-epoll's builds Mbed TLS).
2. The parser corpus request (criterion 7), `bench/instructions.sh` with peak RSS, the
   matrix (about 140 minutes for seven servers), profiles of any losses, then
   `docs/results.md` and the README summary.
3. Ideas to measure once the competitor profiles show where Goose loses, in this order:
   the `Connection` field (about 520 of the 1,270 instructions per parse of wrk's
   request, task 008); `inline fn`, new at `e7792d7` (spec §7.13), on `http::parse` and
   `answer`, separately; and fewer appends per response. `/baseline11` scans its query
   once per key, which matters only for HttpArena's profiles.

Kait asked (2026-10-10) to decide which servers and suites to keep once their run times
are known; `SERVERS` and `FRAMEWORKS` already let a follow-up rerun only Goose against
recorded competitor runs.
