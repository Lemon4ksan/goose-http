# Benchmark

The servers tasks 004, 005, and 009 compare, the scripts that build and run them, and the
raw results. The results tables and what they mean are in those tasks' files, and for the
C compilers in task 008's.

```sh
bench/build.sh         # the servers into build/bench/, in release mode
bench/run.sh           # the matrix, into bench/results/<date>-<machine>/ (about 80 minutes)
bench/compilers.sh     # the Goose server built by gcc and clang, into build/bench/
bench/instructions.sh  # instructions per request of servers in build/bench/, with perf
bench/count.sh         # user instructions over a fixed request count, to compare builds
bench/parse.sh         # http::parse alone on the requests in bench/parse/
bench/httparena.sh     # HttpArena's harness, in Docker, with Goose as an entry
bench/run-macos.sh     # a short matrix natively on macOS, into bench/results/<date>-<machine>/
```

They need Linux (`taskset`, `perf`, `/proc`; on Windows, WSL), `GOOSE`, and
`~/.cargo/bin` on `PATH`. The environment configures them (see the comment at the top
of each). `docs/development.md` lists the tools and the traps they work around.

`bench/run-macos.sh` is the exception: it runs on macOS, without pinning, against the
Rust servers that build there, and records wrk's rate and peak RSS only. macOS's
loopback caps every server at the same rate, so its numbers show that a build works and
what it uses, and don't rank the servers (task 012).

## Servers

Each serves `GET /plaintext` and `GET /json` with the bodies and fields TechEmpower
requires (`Server`, `Date`, `Content-Type`, `Content-Length`), 405 for other methods on
those paths, and 404 elsewhere. Each takes its worker count from `WORKERS` and its port
as its first argument. The JSON body is serialized per request in all of them. The last
six, task 005's io_uring competitors and task 018's tina, run only when `SERVERS` names
them.

| Server | Pin | Build | Workers |
|---|---|---|---|
| goose | this repository, Goose at the pin in `README.md` | `LOOP=epoll scripts/build.sh`: `goose build`, `-O2` for Goose and gcc 15.2.0 | one thread per worker, each with its own `SO_REUSEPORT` listener and epoll loop |
| goose-uring | the same | `LOOP=uring scripts/build.sh`, liburing 2.14 | one thread per worker, each with its own `SO_REUSEPORT` listener and io_uring ring ([architecture](../docs/architecture/README.md#the-io_uring-loop-task-005)) |
| may-minihttp | `may_minihttp` 0.1.11, `may` 0.3.51 (`Cargo.lock`) | TechEmpower's: `opt-level = 3`, `codegen-units = 1`, thin LTO, `panic = "abort"`, `-C target-cpu=native`, mimalloc | `may` worker threads; one listener, a coroutine per connection |
| hyper | `hyper` 1.12.0, `tokio` 1.53.2 (`Cargo.lock`) | TechEmpower's: `opt-level = 3`, `codegen-units = 1`, fat LTO, plus `panic = "abort"`, `-C target-cpu=native` | Tokio's multi-threaded runtime with `WORKERS` worker threads; one listener, a task per connection, `pipeline_flush` |
| odin-http | `laytan/odin-http` `fac113f` (2026-08-26), Odin `dev-2026-10` | odin-http's own: `-o:speed -disable-assert -no-bounds-check` | `thread_count` threads, each with an io_uring event loop accepting on one shared listener |
| tokio | HttpArena's `tokio` entry at `0720ee5`, `tokio` 1.52.3 (`Cargo.lock`) | the entry's: `opt-level = 3`, `codegen-units = 1`, thin LTO, `panic = "abort"`, `-C target-cpu=native` | one current-thread runtime per worker, each with its own `SO_REUSEPORT` listener; a hand-written parser, responses batched per read |
| dusty | `lalinsky/dusty` `ae164fa`, `zio` 0.19.1 (`build.zig.zon`), Zig 0.16.0 | HttpArena's entry: `ReleaseFast`, `x86_64-linux-musl`, `-Dcpu=x86_64_v3+aes+pclmul+adx` | zio's work-stealing runtime with `WORKERS` executors, each with an io_uring ring (zio's choice on this kernel; it falls back to epoll); one listener with dusty's default accept loops; llhttp parser |
| vanilla-epoll | `enghitalo/vanilla` `091c014`, V `b99970b` | HttpArena's entry: `v -prod -gc none` (gcc `-O3 -flto`) | one thread per worker, each with its own `SO_REUSEPORT` listener and epoll loop |
| xitca-web | TechEmpower's `xitca-web` entry at `57d92fb`, `xitca-http` 0.8.2, `xitca-server` 0.6.1, `tokio-uring-xitca` 0.1.1 (`Cargo.lock`) | the entry's: `opt-level = 3`, `codegen-units = 1`, fat LTO, `panic = "abort"`, `-C target-cpu=native --cfg tokio_unstable`; features `io-uring`, `perf-json` (sonic-rs), `perf-allocator` (mimalloc) | `WORKERS` threads, each with a tokio-uring runtime accepting on one shared listener |
| zix | `prothegee/zix` `8b849c6` (tag 0.5.0, head of the `0.5.x` branch the entry fetches), Zig 0.16.0 | HttpArena's entry: `ReleaseFast`, `x86_64-linux-musl`, `-Dcpu=x86_64_v3+aes+pclmul+adx` | `.URING` dispatch: one thread per worker, each with its own `SO_REUSEPORT` listener and io_uring ring; responses staged per connection, one send per batch |
| zeemo | HttpArena's `zeemo` entry at `0720ee5`, which holds its source; Zig 0.16.0 | HttpArena's entry: `ReleaseFast`, `x86_64-linux-musl`, baseline CPU | one thread per worker, pinned to a CPU, each with its own `SO_REUSEPORT` listener and io_uring ring; multishot accept, one send per batch |
| libreactorng | `fredrikwidlund/libreactorng` `7a65f8b` with the entry's `connection-close.patch` | HttpArena's entry: `-O3 -march=native` (gcc 15.2.0), with libreactor's own `-flto` | one thread per worker, each with its own `SO_REUSEPORT` listener and reactor on an io_uring ring; picohttpparser |
| vanilla-io_uring | `enghitalo/vanilla` `091c014`, V `b99970b`, liburing 2.14 | HttpArena's entry: `v -prod` with V's default GC (gcc `-O3 -flto`) | vanilla-epoll's app on vanilla's io_uring backend: one thread per worker, each with its own `SO_REUSEPORT` listener and ring |
| tina | `pmbanugo/tina` `a2e8d4d` (2026-10-12), Odin `dev-2026-10` | Tina's production build: `-o:speed -define:TINA_ASSERTS=false`, bounds checks on | one shard per worker, each a thread with an io_uring ring and its own `SO_REUSEPORT` listener (`Reuse_Port`, faster than its primary `Coordinator` ingress: task 018) |

The configurations follow each project's fastest documented setup: TechEmpower's entries
for may-minihttp and hyper (`hyper --runtime multi-thread`), odin-http's
`comparisons/empty-ok-all` for its build flags, and
[HttpArena](https://github.com/MDA2AV/HttpArena)'s entries, at commit `0720ee5`, for
tokio, dusty, vanilla-epoll, zix, zeemo, libreactorng, and vanilla-io_uring.
xitca-web follows TechEmpower's default `xitca-web` test, built with `io-uring`; the
entry's `compio` test, on a pure io_uring runtime, needs a nightly Rust. Goose builds
with `scripts/build.sh`'s `-O2`, without `-march=native`, which the Rust builds get.

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
- The HttpArena entries serve HttpArena's endpoints (`/baseline11`, `/pipeline`), not
  TechEmpower's, and send no `Date`; tokio's and vanilla-epoll's send no `Server`
  either. Each app adds `/plaintext` and `/json` with those fields, and keeps the
  entry's serving model. tokio refreshes a cached `Date` from a timer task per runtime,
  dusty and vanilla-epoll per thread when the second changes.
- vanilla-epoll's entry answers its plaintext test, `/pipeline`, from fixed bytes when
  the request starts `GET /pipeline `, before parsing it. The app does the same for
  `GET /plaintext `.
- vanilla reads its worker count from `VANILLA_WORKERS` before `main` runs, so the app
  sets it from `WORKERS` and re-executes itself. vanilla-io_uring is the same app on the io_uring
  backend, in `bench/vanilla-io_uring`, built with `-d vanilla_io_uring`: HttpArena's two
  entries differ only in the backend.
- zeemo and libreactorng fork a process per worker. Their apps run a thread per worker
  instead, so `bench/run.sh`'s CPU time and peak RSS, read from one process, cover every
  worker, and stopping that process stops them all. Both keep per-worker state
  thread-local. zeemo's fd table grows from 4,096 entries to 65,536: one process's fds
  reach its connection count.
- zix's response helpers write no `Server`, and the entry turns `Date` off. The app
  frames its responses itself and appends them to zix's send sink with `writeAllFD`, as
  the entry's `/pipeline` and `/json` handlers do.
- zeemo's parser buffers 2 KiB per connection, sized for HttpArena's requests. With
  TechEmpower's headers, `bench/run.sh`'s requests are about 170 bytes, so a 16-deep
  batch takes two receives. The app keeps the entry's size.
- libreactorng sends `Server: *`. zeemo's parser reads only `GET` and `POST`, and
  libreactorng's and xitca-web's routes take only `GET`, so the three answer `HEAD`
  with 405.

On arm64 Linux (Docker Desktop on Apple Silicon, task 012), `bench/build.sh` differs from
the x86-64 builds above in three places, and every server builds:

- dusty, zix, and zeemo build for `aarch64-linux-musl`. dusty and zix take
  `-Dcpu=apple_m1` on Apple's CPUs, `native` on others: the VM hides the CPU's part
  number, and Zig's `native` there resolves to generic arm64 without the M1's features.
  zeemo names no CPU, as on x86-64, so it builds for baseline arm64.
- V bootstraps with gcc, which V's Makefile picks on arm64, and takes `libgc.a` from
  tccbin's `thirdparty-linux-arm64` branch head (`125ad2e`, 2024-07-08), where the
  x86-64 build takes tccbin `d6e7ac1` from the `thirdparty-linux-amd64` branch.
- libreactorng's and the Rust servers' `-march=native` and `-C target-cpu=native` are
  arm64's: gcc and LLVM read the CPU's features from `/proc/cpuinfo`.

### What each passes of `scripts/http_client.py`

Every server passed `tfb` (TechEmpower's checks, with `SERVER_NAME` set to its `Server`
value) and `many 4096` before it was measured, 2026-10-10. The io_uring servers of task
005 haven't been through `scripts/http_client.py` yet. In `pipeline`:

| Server | `pipeline` | Fails elsewhere |
|---|---|---|
| goose | passes | none |
| may-minihttp | passes | `keepalive`: no `Connection` field on HTTP/1.0 |
| hyper | passes | `keepalive`: answers HTTP/1.0 with an HTTP/1.0 status line |
| odin-http | passes up to the 512 KB request body, which it refuses with 413: it reads at most 256 KB of a body the handler didn't (`Max_Post_Handler_Discard_Bytes`); passes the 500 pipelined requests on their own | `keepalive`: keeps HTTP/1.0 without keep-alive open |
| tokio | passes | `keepalive`: keeps HTTP/1.0 without keep-alive open. `hostile`: never answers a request with bare-LF line ends, waiting for CRLF CRLF |
| dusty | passes | `keepalive`: no `Connection: keep-alive` on HTTP/1.0 keep-alive. `hostile`: closes on a bare-LF request without a response |
| vanilla-epoll | passes | as tokio |

`keepalive` fails on HTTP/1.0 in every competitor, and these were probed check by check
(2026-10-10, one worker each):

| Check | goose | may-minihttp | tokio | dusty | vanilla-epoll |
|---|---|---|---|---|---|
| HTTP/1.0 without keep-alive: `Connection: close`, then close | yes | stays open, no field | stays open, no field | yes | stays open, no field |
| HTTP/1.0 with `Connection: keep-alive`: echoed | yes | no field | no field | no field | no field |
| HTTP/1.1 `Connection: close` in a pipeline: stop after it | yes, with `close` | answers past it | yes, no field | yes, with `close` | yes, no field |
| `HEAD` | yes | yes | yes | yes | yes |

tokio's and vanilla-epoll's parsers don't read the HTTP version, so they serve HTTP/1.0
as 1.1. Reading it costs one comparison per request, so this is scope, not speed:
HttpArena and TechEmpower send only HTTP/1.1. None of these touch the measured requests,
which are HTTP/1.1 `GET`s without bodies.

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

### Reusing earlier cells

A competitor's cells are measured once per binary, not once per run. With `REUSE`
naming earlier result directories, `bench/run.sh` copies a cell's rows from the first
one that measured the same binary under the same `key.txt`, and runs only the rest:

```sh
REUSE="bench/results/2026-10-11-final2-plaintext bench/results/2026-10-11-final2-json" \
    SERVERS="goose goose-uring vanilla-epoll xitca-web" bench/run.sh
```

`key.txt` holds what a cell's numbers depend on besides the server: `METHOD`, which
`run.sh` bumps when it changes what a cell measures, the kernel and CPU, the CPU sets and
client threads, the durations, the wrk and h2load versions, and hashes of the helper files
the load runs use. `binaries.txt` holds each server binary's SHA-256. A copied row names
its source in the `from` column, and the summary in its From column. Goose builds always
run, so each run measures Goose fresh beside copied competitors. Separate sessions have
drifted by up to 5%; rerunning an unchanged Goose build beside its earlier numbers shows
the drift of the day.

In a closed-loop test that keeps every connection busy, latency follows from the rate:
the requests in flight divided by the requests per second (256 connections × 16 deep at
3.1 million per second is 1.3 ms). p50 says little beyond the rate; p99 shows how
evenly a server treats its connections.

## Results

Each run writes its own directory, `results/<date>-<machine>/` for `bench/run.sh` and
`results/httparena-<date>-<machine>/` for `bench/httparena.sh`, so runs from several
machines sit side by side. `MACHINE` names the machine, and defaults to the host name;
set it inside a container, whose host name is an ID, for example
`MACHINE=mac-docker`. `env.txt` records the machine in full, and a comparison uses
directories from one machine only. The directories dated 2026-10-11 and earlier are
all from the WSL2 machine in [docs/results.md](../docs/results.md#machine), and carry
a label in place of the machine name.

A directory holds, per cell, `<server>-w<workers>-<test>-c<conns>-r<run>` with
`.wrk`, `.h2load`, `.lat` (the latency summary), `.steps`, `.times`, and `.log` (the
server's output); `runs.tsv`, one line per cell; `summary.md`, from `summarize.py`;
and `env.txt`, the machine and the versions.
