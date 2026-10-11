# goose-http

A proof of concept: a small, fast HTTP/1.1 server written in
[Goose](https://github.com/aardappel/goose), benchmarked against the fastest Rust and Odin
servers. It runs an event loop per core, on Linux, macOS, and Windows.

This repository is a Goose program, not an addition to Goose (2026-10-10). Gaps found
in the compiler or the standard library are recorded in
[docs/goose-findings.md](docs/goose-findings.md), not patched here. It may later grow
into the HTTP layer of a Goose port of snowtime-native; nothing here depends on that.

## The question

Can a Goose HTTP server match the fastest Rust and Odin servers on plaintext and JSON
benchmarks, in a small amount of code? Task 004 answers it for epoll, and task 005 for
io_uring.

## Event loops

`scripts/build.sh` builds one of two loops, both in Goose:

- `LOOP=epoll`, the default on Linux, and the only loop on macOS, over kqueue. It's the
  fastest on Linux so far, and the one the results below measure.
- `LOOP=uring`, over io_uring on Linux. On Windows it's the only loop, over I/O
  completion ports, and the default there as `LOOP=iocp`.

Task 005 measures the two against each other on Linux. When the repository becomes a
Goose package (task 011), both stay: `http::serve` is the portable loop, and
`http::serve_epoll` the epoll one for Linux and macOS.

## Results so far

On one machine (Ryzen 7 5800X3D, WSL2 kernel 6.18), with `bench/run.sh`'s defaults on
2026-10-11: TechEmpower's plaintext (pipelined 16 deep) and JSON, 1 and 4 workers on
CPUs 0-3, wrk on CPUs 4-15, medians of 3 runs of 15 s per cell. The epoll server at
`b6a26c5`, against the strongest servers of [HttpArena](https://www.http-arena.com/) and
TechEmpower that run on this machine:

| | Goose | vanilla-epoll (V) | tokio (Rust) | may-minihttp (Rust) |
|---|---:|---:|---:|---:|
| plaintext, 256 conns, 4 workers, req/s | 5.47 M | 5.53 M | 3.55 M | 2.39 M |
| plaintext, 4,096 conns, 4 workers, req/s | 5.12 M | 5.06 M | 3.35 M | 3.69 M |
| JSON, 256 conns, 4 workers, req/s | 0.408 M | 0.216 M | 0.377 M | 0.342 M |
| instructions per request (plaintext, 1 worker) | 2,255-2,371 | 1,756-1,765 | 4,330-4,375 | 2,983-3,011 |
| peak RSS, any cell | 2.1-2.6 MB | 5.6-57 MB, 15 GB in JSON | 12-184 MB | 40-639 MB |

Goose leads every JSON cell and four of six plaintext cells. It loses plaintext with 4
workers at 256 and 1,024 connections to vanilla-epoll by 1%, inside both servers' run
spreads; vanilla-epoll answers `GET /plaintext` from its first bytes without parsing the
request, so it runs about 700 fewer instructions per request. Goose's p99 latency trails
the best in six of ten cells, by 0.05-0.53 ms, and in HttpArena's `limited-conn` profile (a new
connection every 10 requests) it runs 2% behind tokio. Every number, how it was taken,
and the losses in full: [docs/results.md](docs/results.md).

## Scope

In scope: HTTP/1.1 with keep-alive and pipelining, `Content-Length` request bodies,
chunked request bodies that fit in the read buffer, TechEmpower's plaintext and JSON
endpoints and HttpArena's baseline and pipeline endpoints, and the C shim the server
needs for syscalls. Out of scope: TLS, HTTP/2, routing beyond a few fixed paths, and
Windows as a benchmark platform.

## Layout

```text
src/           the Goose program
shim/          the C the server calls, linked by goose build: sockets, epoll, io_uring,
               and kqueue (macOS) and IOCP (Windows) in their place
bench/         the competing servers, the load scripts, and the recorded results
scripts/       build and run scripts
docs/          architecture, development setup, and the Goose findings log
tasks/         task tracking (tasks/README.md)
```

Setup and the build commands are in [docs/development.md](docs/development.md).

## Pins

| What | Pin | Why |
|---|---|---|
| Goose compiler | `aardappel/goose` `efe3155` (`master`, 2026-10-10) | The language and stdlib change often |

Move the pin in its own commit, with the build and benchmark results that still hold.
