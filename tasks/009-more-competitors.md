# 009: More competitors from HttpArena

Status: todo

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

- [ ] The `tokio` entry and dusty in `bench/`, pinned to exact commits, built in their
      fastest documented configuration, with any deviation from it explained in a comment
      (`bench/README.md`)
- [ ] Each passes `scripts/http_client.py tfb` and `many 4096`, with what else it passes
      recorded as in `bench/README.md`
- [ ] Zig's version and install in `docs/development.md`
- [ ] Task 004's matrix rerun with them, and the results, wins and losses, in this file
- [ ] vanilla-epoll added too, or the reason it wasn't recorded here
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
