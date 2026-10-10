# 004: Benchmark against Rust and Odin

Status: todo

Measure the epoll server against the fastest servers in Rust and Odin, on the same
machine, with the same worker count, and record wins and losses plainly. This answers the
README's question for epoll, and sets the bar task 005 has to clear.

Competitors, each built in release mode and serving the same two endpoints:

- Rust, raw: `may-minihttp`, which ranks at the top of TechEmpower's Rust plaintext
  results.
- Rust, realistic: `hyper` on Tokio's multi-threaded runtime, the stack under Axum.
- Odin: `odin-http` (laytan/odin-http), in its fastest configuration.

If a faster server in either language turns up while setting these up, add it.

## Method

- Plaintext with 16-deep pipelining (`wrk` with a pipeline script), as TechEmpower runs
  it, at 256, 1,024, and 4,096 connections.
- JSON without pipelining, at 256 and 1,024 connections.
- Server and load generator pinned to separate cores (`taskset`), with the same worker
  count for every server, at 1 worker and at all server cores.
- Each run long enough to be stable (at least 15 seconds after a warm-up), repeated at
  least 3 times; the median reported with the spread.
- Requests per second, p50 and p99 latency, the server's peak RSS, and its CPU time.

WSL2 adds virtualization overhead to networking. If time allows, repeat the final run on
bare-metal Linux and record both.

## Acceptance criteria

- [ ] The competitors' sources and build commands in `bench/`, pinned to exact versions
- [ ] `bench/run.sh` runs the whole matrix and writes raw results to `bench/results/`
- [ ] A results table in this file, with the machine, kernel, compiler versions, and
      commands
- [ ] Where Goose loses, a profile (`perf`) saying where its time goes
- [ ] Fixes from that profile applied to the server, the matrix rerun, and before and
      after recorded
- [ ] Goose findings from this task in `docs/goose-findings.md`
