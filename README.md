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

- `LOOP=uring`, over io_uring, the default on Linux: 11% to 21% faster than the epoll
  loop in task 005's matrix, at 4 to 5 times its peak RSS (about 10 MB with 4 workers).
  It needs Linux 6.1 and liburing. Where `io_uring_setup` fails, as under Docker's
  default seccomp profile, it runs over an emulation of the ring on epoll. On Windows
  it's over I/O completion ports, built as `LOOP=iocp`, and on macOS over the same
  emulation on kqueue.
- `LOOP=epoll`, the only loop on macOS, over kqueue, and on Linux the loop for kernels
  and containers without io_uring. The results below measure it.

Both stay built and tested ([architecture](docs/architecture/README.md#the-io_uring-loop-task-005)).
When the repository becomes a Goose package (task 011), `http::serve` is the portable
loop, and `http::serve_epoll` the epoll one for Linux and macOS.

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
http.goose     the package's entry: the settings, the errors, and what both loops share
*.goose        its other modules, all namespace http: the parser and the response
               writers (message.goose), the loops (uring.goose, epoll.goose), and the
               shim's functions (sys.goose, ring.goose)
http.build     the package's sidecar: each platform's shim
shim/          the C the package calls, linked by goose build: sockets, epoll, io_uring,
               and kqueue (macOS) and IOCP (Windows) in their place
server/        the benchmark server, a program that imports the package from "../"
test/          the package's unit tests
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
