# Benchmark

The servers task 004 compares, the scripts that build and run them, and the raw
results. The results tables and what they mean are in task 004's file.

```sh
bench/build.sh    # the four servers into build/bench/, in release mode
bench/run.sh      # the matrix, into bench/results/<date>/ (about 80 minutes)
```

Both run in WSL, need `GOOSE` and `~/.cargo/bin` on `PATH`, and are configured through
the environment (see the comment at the top of each). `docs/development.md` lists the
tools and the traps they work around.

## Servers

Each serves `GET /plaintext` and `GET /json` with the bodies and fields TechEmpower
requires (`Server`, `Date`, `Content-Type`, `Content-Length`), 405 for other methods on
those paths, and 404 elsewhere. Each takes its worker count from `WORKERS` and its port
as its first argument. The JSON body is serialized per request in all four.

| Server | Pin | Build | Workers |
|---|---|---|---|
| goose | this repository, Goose at the pin in `README.md` | `scripts/build.sh`: `goose -O2`, `cc -O2` (gcc 15.2.0) | one thread per worker, each with its own `SO_REUSEPORT` listener and epoll loop |
| may-minihttp | `may_minihttp` 0.1.11, `may` 0.3.51 (`Cargo.lock`) | TechEmpower's: `opt-level = 3`, `codegen-units = 1`, thin LTO, `panic = "abort"`, `-C target-cpu=native`, mimalloc | `may` worker threads; one listener, a coroutine per connection |
| hyper | `hyper` 1.12.0, `tokio` 1.53.2 (`Cargo.lock`) | TechEmpower's: `opt-level = 3`, `codegen-units = 1`, fat LTO, plus `panic = "abort"`, `-C target-cpu=native` | Tokio's multi-threaded runtime with `WORKERS` worker threads; one listener, a task per connection, `pipeline_flush` |
| odin-http | `laytan/odin-http` `fac113f` (2026-08-26), Odin `dev-2026-10` | odin-http's own: `-o:speed -disable-assert -no-bounds-check` | `thread_count` threads, each with an io_uring event loop accepting on one shared listener |

The configurations follow each project's fastest documented setup: TechEmpower's entries
for may-minihttp and hyper (`hyper --runtime multi-thread`), and odin-http's
`comparisons/empty-ok-all` for its build flags. Goose builds with `scripts/build.sh`'s
`-O2`, without `-march=native`, which the Rust builds get.

Where a server needed more than its defaults to do the same work as the others, the app
says so in a comment:

- may-minihttp leaves a request body it wasn't asked to read in its buffer, where it is
  parsed as the next request. The app reads and drops every body, as the Goose server
  does.
- odin-http's `respond_json` sends the body with chunked encoding. The app marshals it
  per request into the request's temporary allocator and sends it with a
  `Content-Length`.
- odin-http's io_uring accept doesn't set `TCP_NODELAY`, though Odin's own `core:net`
  accept does by default. Without it, Nagle's algorithm held each pipelined response
  until the client acknowledged the one before, about 92,000 requests per second at any
  worker count. The app sets it on the listener, which accepted sockets copy.

### What each passes of `scripts/http_client.py`

Every server passed `tfb` (TechEmpower's checks, with `SERVER_NAME` set to its `Server`
value) and `many 4096` before it was measured, 2026-10-10. In `pipeline`:

| Server | `pipeline` | Fails elsewhere |
|---|---|---|
| goose | passes | none |
| may-minihttp | passes | `keepalive`: no `Connection` field on HTTP/1.0 |
| hyper | passes | `keepalive`: answers HTTP/1.0 with an HTTP/1.0 status line |
| odin-http | passes up to the 512 KB request body, which it refuses with 413: it reads at most 256 KB of a body the handler didn't (`Max_Post_Handler_Discard_Bytes`); passes the 500 pipelined requests on their own | `keepalive`: keeps HTTP/1.0 without keep-alive open |

None of these touch the measured requests: the benchmark sends HTTP/1.1 `GET`s without
bodies.

## Method

`bench/run.sh` runs, for each round, worker count, server, and test:

- Plaintext pipelined 16 deep (`scripts/pipeline.lua`) at 256, 1,024, and 4,096
  connections, and JSON without pipelining at 256 and 1,024, with TechEmpower's request
  headers.
- 1 worker on CPU 0, and 4 workers on CPUs 0 to 3 (two cores with both SMT threads). The
  load generators run on CPUs 4 to 15 with 8 threads.
- A fresh server per cell; wrk for 5 s to warm up; wrk for 15 s, measured; then h2load
  for 15 s after a 2 s warm-up, for latency.
- 3 rounds, interleaved, so each server's runs spread over the session.

Where each number comes from:

| Number | Source |
|---|---|
| Requests per second | wrk 4.1.0, with `wrk-monotonic.so` preloaded so WSL2's clock steps can't turn requests into timeouts |
| p50 and p99 latency | h2load 1.68.0, from its per-request log (monotonic clock), summarized by `latency.c`. h2load keeps 16 requests in flight per connection, where wrk sends them in batches of 16, and it runs slower than wrk, so its own rate is recorded beside its latency. |
| Peak RSS | the server's `VmHWM` at the end of the cell, warm-up and both load runs included |
| Server CPU time | `utime + stime` of the server's process over the measured wrk run |
| wrk CPU time | the shell's `times` for the measured wrk run, to show whether the client had room |
| Clock steps | `clockstep.py`, during the measured wrk run |

In a closed-loop test that keeps every connection busy, latency follows from the rate:
the requests in flight divided by the requests per second (256 connections × 16 deep at
3.1 million per second is 1.3 ms). p50 says little beyond the rate; p99 shows how
evenly a server treats its connections.

## Results

`results/<date>/` holds, per cell, `<server>-w<workers>-<test>-c<conns>-r<run>` with
`.wrk`, `.h2load`, `.lat` (the latency summary), `.steps`, `.times`, and `.log` (the
server's output); `runs.tsv`, one line per cell; `summary.md`, from `summarize.py`;
and `env.txt`, the machine and the versions.
