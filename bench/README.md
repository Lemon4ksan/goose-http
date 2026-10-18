# Benchmark

Build and run the competing servers, configure the workloads, and interpret the raw
result files. The [benchmark summary](../docs/benchmarks.md) owns the current comparisons;
[measurement records](../docs/results.md) link their provenance. Tasks retain evidence
for implementation decisions and rejected changes.

```sh
bench/build.sh         # the servers into build/bench/, in release mode
bench/run.sh           # the matrix, into bench/results/<date>-<machine>/ (about 80 minutes)
bench/compilers.sh     # the Goose server built by gcc and clang, into build/bench/
bench/instructions.sh  # instructions per request of servers in build/bench/, with perf
bench/count.sh         # user instructions over a fixed request count, to compare builds
bench/parse.sh         # http::parse alone on the requests in bench/parse/
bench/store.sh         # reads from http.store: scalars and records against store_append
bench/httparena.sh     # HttpArena's harness, in Docker, with Goose as an entry
bench/run-macos.sh     # a short matrix natively on macOS, into bench/results/<date>-<machine>/
bench/files.sh         # static files, and /bytes from memory, against nginx and Caddy
bench/oha.sh           # Goose builds with oha, on Windows (Git Bash) or Linux, for IOCP
bench/pinning.sh       # task 045's spike: /fast's latency beside a CPU lane, per placement
bench/rest.sh          # task 021's REST tiers, 9 servers: build, then run (about 2 h 25 min)
bench/table.py         # README.md's plaintext and JSON table from run.sh's runs.tsv files
```

`bench/files.sh` compares static files with the usual file servers rather than the
servers below, most of which can't serve a file: nginx, Ubuntu's (`apt install nginx`;
`systemctl disable --now nginx` keeps its service off the benchmark's CPUs), and Caddy,
the release binary `bench/build.sh` fetches and checks against a pinned SHA-256. The
script writes each one's configuration in its `start` function.

They need Linux (`taskset`, `perf`, `/proc`; on Windows, WSL), `GOOSE`, and
`~/.cargo/bin` on `PATH`. The environment configures them (see the comment at the top
of each). [Toolchain](#toolchain) lists the tools beyond the
[development setup](../docs/development.md#linux), and
[known issues](../docs/known-issues.md#benchmarks) the traps they work around. Run a
benchmark with no competing work on the machine, and compare only compatible machines,
kernels, and settings.

`bench/codegen.sh REV...` compares generated code without serving traffic. It keeps
generated C under `~/goose-http-codegen/` and reports function-family sizes and hot
function instruction counts. Specialization numbers change between builds, so compare
families. Static counts include cold branches; `bench/count.sh` measures executed
user instructions over a fixed request count. Neither substitutes for rate and
memory measurements.

`bench/run-macos.sh` is the exception: it runs on macOS, without pinning, against the
Rust servers that build there, and records wrk's rate and peak RSS only. macOS's
loopback caps every server at the same rate, so its numbers show that a build works and
what it uses, and don't rank the servers (task 012).

`bench/pinning.sh` runs on Linux and macOS, with oha and curl from the
[development setup](../docs/development.md#build-and-test). It gives
`bench/pinning/pinning.goose` each layout as a placement file
([tuning](../docs/tuning.md)), and writes `runs.tsv` and `summary.tsv` under
`build/bench/pinning/`. macOS can't pin threads, so there it runs only `over`, `fewer`,
and `nice`. A VM's virtual CPUs pin nothing real, so a pinned layout's result counts
only from bare metal.

## Toolchain

Beyond the [Linux test tools](../docs/development.md#linux), the benchmarks need these,
on Ubuntu 26.04 in WSL2:

| Tool | Source | Version used (2026-10-10) |
|---|---|---|
| perf | apt `linux-perf` | 7.0.14 (package `7.0.0-38.38`) |
| Rust | rustup ([Linux test tools](../docs/development.md#linux)) | rustc 1.99.0, cargo 1.99.0, for the Rust servers |
| Odin | `/opt/odin-dev-2026-10` | `dev-2026-10` (`dev-2026-10-nightly:84bc3fc`, LLVM 20.1.8), for odin-http |
| Zig | `/opt/zig-0.16.0` | 0.16.0, for dusty, zix, and zeemo |
| V | built by `bench/build.sh` in its cache | 0.5.2 `b99970b`, for vanilla-epoll; needs apt `liburing-dev` (2.14) |
| Docker | Docker Desktop; on Linux without it, apt `docker.io` with the user in the `docker` group | 29.8.2, for HttpArena's harness |
| nginx | apt `nginx`, service disabled | 1.28.3, for `bench/files.sh` |
| Caddy | fetched by `bench/build.sh` | 2.10.2, for `bench/files.sh` |

Odin comes from its GitHub release; `bench/build.sh` refuses any other version, because
odin-http follows Odin's master branch. Odin links with clang:

```sh
curl -sSLf -o /tmp/odin.tgz \
    https://github.com/odin-lang/Odin/releases/download/dev-2026-10/odin-linux-amd64-dev-2026-10.tar.gz
mkdir -p /tmp/odin && tar -xzf /tmp/odin.tgz -C /tmp/odin
sudo mv /tmp/odin/odin-linux-amd64-nightly+2026-10-06 /opt/odin-dev-2026-10
sudo ln -sf /opt/odin-dev-2026-10/odin /usr/local/bin/odin
```

Zig comes from ziglang.org; `bench/build.sh` refuses any other version, because dusty
pins `minimum_zig_version = "0.16.0"` and Zig's standard library changes between
releases. The tarball's SHA-256 is
`70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00`, as
`https://ziglang.org/download/index.json` lists it:

```sh
curl -sSLf -o /tmp/zig.tar.xz https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz
mkdir -p /tmp/zig && tar -xJf /tmp/zig.tar.xz -C /tmp/zig
sudo mv /tmp/zig/zig-x86_64-linux-0.16.0 /opt/zig-0.16.0
sudo ln -sf /opt/zig-0.16.0/zig /usr/local/bin/zig
```

`bench/build.sh` builds V itself, at the commits HttpArena's vanilla-epoll image pins.
vanilla's io_uring module needs liburing's header even in an epoll build, and
libreactorng builds with autotools:

```sh
sudo apt-get install -y liburing-dev
sudo apt-get install -y autoconf automake libtool libltdl-dev
```

### HttpArena under Docker on macOS

`bench/httparena.sh` drives HttpArena's harness, which needs bash 4, GNU `stat` and
`timeout`, and `nproc`; macOS has bash 3.2 and none of the rest. Run it in a Linux
container that talks to Docker Desktop through its socket, with the cache and the working
tree mounted at the same paths as on the Mac, so the paths the harness passes to `docker
run -v` resolve on the Mac. `--network host` puts the container on the VM's host network,
where the servers listen, and its `nproc` is the VM's 10 CPUs, which the harness reads
for its CPU limits. The image, 2026-10-11:

```dockerfile
FROM docker:29.8.2-cli AS cli
FROM ubuntu:26.04
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    bash ca-certificates curl git jq python3 openssl util-linux procps bc
COPY --from=cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
```

```sh
docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME/.cache/goose-http-bench:$HOME/.cache/goose-http-bench" -v "$PWD:$PWD" \
    -e HOME="$HOME" -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
    -e GIT_CONFIG_VALUE_0='*' -e SERVER_CPUS=0-2 -e LOAD_CPUS=3-9 -e MACHINE=m1pro-docker \
    -w "$PWD" goose-http-arena bench/httparena.sh run
```

- The buildx plugin is needed: without it, `docker build` doesn't set `TARGETARCH`,
  and dusty's Dockerfile then builds for x86-64.
- The safe.directory setting lets the container's git read a working tree owned by
  another user.
- HttpArena's zrk image downloads an x86-64 binary, and its vanilla-epoll image pins
  tccbin's x86-64 branch, whose `libgc.a` V's bootstrap links. On an arm64 Docker host,
  `bench/httparena.sh` swaps in zrk's aarch64 release and tccbin's arm64 branch.

## Servers

Each serves `GET /plaintext` and `GET /json` with the bodies and fields TechEmpower
requires (`Server`, `Date`, `Content-Type`, `Content-Length`), 405 for other methods on
those paths, and 404 elsewhere. Each takes its worker count from `WORKERS` and its port
as its first argument. The JSON body is serialized per request in all of them. The last
six, task 005's io_uring competitors and task 019's tina, run only when `SERVERS` names
them.

| Server | Pin | Build | Workers |
|---|---|---|---|
| goose | this repository, Goose at the pin in `README.md` | `LOOP=epoll scripts/build.sh`: `goose build`, `-O2` for Goose and gcc 15.2.0 | one thread per worker, each with its own `SO_REUSEPORT` listener and epoll loop |
| goose-uring | the same | `LOOP=uring scripts/build.sh`, liburing 2.14 | one thread per worker, each with its own `SO_REUSEPORT` listener and io_uring ring ([architecture](../docs/architecture.md#completion-loop)) |
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
| tina | `pmbanugo/tina` `a2e8d4d` (2026-10-12), Odin `dev-2026-10` | Tina's production build: `-o:speed -define:TINA_ASSERTS=false`, bounds checks on | one shard per worker, each a thread with an io_uring ring and its own `SO_REUSEPORT` listener (`Reuse_Port`, faster than its primary `Coordinator` ingress: task 019) |

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
| tina | passes the 16 pipelined requests and the one sent a byte at a time, then resets the connection during the 512 KB request body | `forms`: answers an absolute-form target with 400. `keepalive`: keeps HTTP/1.0 without keep-alive open. `hostile`: never answers a request with bare-LF line ends. `many 4096` with 1 worker: closes connections past its 4,096 slots per shard; `many 4000` passes |

Tina was checked on the desktop on 2026-10-13, 1 worker, `SERVER_NAME=tina`; it passes
`tfb`.

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

### How long `bench/rest.sh run` takes

`bench/rest.sh` notes the start of every cell in `times.txt`. The full run of
2026-10-13 on the desktop, 8 servers with the defaults (3 rounds, 5 s of warm-up and
15 s measured per cell), took 2 h 08 min
([times.txt](results/2026-10-13-rest/times.txt)):

| Part | Cells | Time |
|---|---:|---:|
| WSL's git rereading the checkout, for `env.txt` | | 2.3 min |
| The checks, `check.py` on every tier | 54 | 1.3 min |
| Step 1, tiers A to C at saturation | 144 | 49.6 min |
| Step 2, tier D | 36 | 12.8 min |
| Step 3, tiers A to C at a fixed rate | 144 | 49.3 min |
| Step 4, the mixed run | 36 | 12.3 min |

A cell takes 20.5-21.4 s: its warm-up and measured run, and about 1 s to start the
server, stop it, and wait for its port. A server with tier D takes 16.6 min of the run
and one without 12.5 min, so the time grows with the server count alone. Steps 3 and 4
again for all eight servers (`STEPS="3 4"`) took 63 min, plus 2.7 min of git.

What would shorten a run, by how much at 8 servers, and what it costs:

- Run only the servers whose binary changed, and keep the others' cells, as
  `bench/run.sh`'s `REUSE` does ([above](#reusing-earlier-cells)). Goose's two loops
  alone take 33 min. This saves the most, at the cost of comparing across sessions:
  Goose's and hyper's cells moved by up to 3.3% between 2026-10-12 and 2026-10-13. `bench/rest.sh` has no `REUSE` yet; this is the change
  to make first.
- `DURATION=10`: about 34 min. Every saturation run fell within 5% of its cell's median
  at 15 s; whether 10 s keeps that isn't measured.
- `RUNS=2` for steps 3 and 4: about 20 min. Their CPU per request varied under 5%
  between rounds for every server that held the rate, but a cell's p99 outlier often
  comes from one round of three.
- Step 3 in one JSON way on tiers A and B, where the two ways' CPU per request differs
  by 2-14% at a fixed rate for the servers that hold it: about 16 min, and the template
  column on A and B is lost.
- Running `git status` in WSL before the run takes the 2-3 min of rereading out of the
  measured session; it doesn't shorten the session.

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

`main` tracks only what the docs cite and what `REUSE` reads: notes (`*.md`), tables
(`*.tsv`), batch scripts, `env.txt`, `key.txt`, `binaries.txt`, `revs.txt`,
`times.txt`, and `instructions.txt`. `.gitignore` keeps the per-cell output out, since
70 commits of it had grown `main` past 31,000 files (2026-10-15). Commit another file a
doc cites with `git add -f`. The raw output travels between machines on the
`bench-raw` branch, which shares no history with `main`. The first push creates it;
delete it once its sessions are written up:

```sh
bench/raw.sh push bench/results/<dir>   # on the benchmark machine
bench/raw.sh pull                       # elsewhere: list the directories
bench/raw.sh pull <dir>                 # extract one into bench/results/
```

The raw output of sessions up to 2026-10-15 stays in `main`'s history, at `30876c1a`:
`git archive 30876c1a bench/results/<dir> | tar -x` restores one.
