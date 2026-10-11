# Results

The Goose server's latest numbers against the competing servers. Each section's
numbers come from one machine, which the section names; numbers from different
machines aren't compared. How each number is taken is in [bench/README.md](../bench/README.md#method), and
the servers' pins and builds are in its [Servers](../bench/README.md#servers) table. The
runs behind each section, and the earlier ones, are recorded in task 009
([tasks/009-more-competitors.md](../tasks/009-more-competitors.md)); task 004
([archived](../tasks/000-archive/004-benchmark.md)) holds the first matrix and its
profile, and task 008 ([archived](../tasks/000-archive/008-clang-simd.md)) the compiler
comparison.

## Machine

- AMD Ryzen 7 5800X3D, 8 cores, 16 logical CPUs, 15 GB of memory for WSL2.
- Windows 11, WSL2 kernel 6.18.40.1-microsoft-standard-WSL2, Ubuntu 26.04.1.
- The Goose server at `b6a26c5`, built by Goose `f084e52` and gcc 15.2.0 (`-O2`). Goose
  `efe3155`, the pin since, generates the same C for it but for the stdlib's file paths.
  rustc 1.99.0, Zig 0.16.0, and V 0.5.2 for the others.
- Every server runs on CPUs 0-3 (two cores with both SMT threads), with the same worker
  count as Goose; the load generators run on CPUs 4-15.

WSL2 runs the loopback network in a VM, so the kernel's share of each request is larger
than it would be on bare metal.

## TechEmpower's tests

`bench/run.sh` with its defaults, on 2026-10-11: plaintext pipelined 16 deep and JSON
without pipelining, with TechEmpower's request headers; 1 worker on CPU 0 and 4 workers
on CPUs 0-3; wrk and h2load with 8 threads; a fresh server per cell; 3 runs of 15 s after
5 s of warm-up, interleaved. Medians of the 3 runs, from
[2026-10-11-final2-plaintext](../bench/results/2026-10-11-final2-plaintext/summary.md) and
[2026-10-11-final2-json](../bench/results/2026-10-11-final2-json/summary.md), which also
have each cell's spread, the h2load rate, and the clock steps.

The session ran beside builds and tests pinned to CPU 15, one of the load generators'
CPUs. Its cells differ from the morning's full matrix at `7cb3e27`
([2026-10-11-matrix](../bench/results/2026-10-11-matrix/summary.md)) by −13% to +9%, most
of them lower, for Goose and the competitors alike.

Requests per second, from wrk:

| Test, conns, workers | Goose | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 1.826 M | 1.795 M | 1.304 M | 1.188 M | 0.826 M | 0.089 M |
| plaintext, 256, 4 | 5.467 M | 5.534 M | 3.546 M | 2.394 M | 2.554 M | 0.375 M |
| plaintext, 1,024, 1 | 1.924 M | 1.874 M | 1.348 M | 1.299 M | 0.695 M | 0.088 M |
| plaintext, 1,024, 4 | 5.388 M | 5.427 M | 3.497 M | 4.063 M | 2.586 M | 0.348 M |
| plaintext, 4,096, 1 | 1.543 M | 1.508 M | 1.162 M | 1.104 M | 0.715 M | 0.085 M |
| plaintext, 4,096, 4 | 5.121 M | 5.059 M | 3.349 M | 3.692 M | 2.453 M | 0.334 M |
| json, 256, 1 | 0.129 M | (0.072 M) | 0.125 M | 0.121 M | 0.083 M | 0.082 M |
| json, 256, 4 | 0.408 M | (0.216 M) | 0.377 M | 0.342 M | 0.287 M | 0.360 M |
| json, 1,024, 1 | 0.131 M | (0.061 M) | 0.121 M | 0.114 M | 0.069 M | 0.075 M |
| json, 1,024, 4 | 0.388 M | (0.218 M) | 0.371 M | 0.346 M | 0.281 M | 0.280 M |

vanilla-epoll's JSON cells, in parentheses, are from the morning's matrix. In this run a
watchdog stopped vanilla-epoll in its first JSON cell, when the host's free memory fell
below 3 GB: HttpArena builds it with `-gc none`, and its JSON encoder's allocations are
never freed (6-15 GB per cell in the morning's matrix; `docs/development.md`). Goose's
JSON at 256 connections with 1 worker spread from 0.101 to 0.145 M, one run slowed by the
work on CPU 15.

Latency, p50 / p99 in ms, from h2load. h2load runs slower than wrk here, so every fast
server sees about the same offered load (3.3-3.6 M requests per second in plaintext with
4 workers), and p99 shows how evenly each treats its connections:

| Test, conns, workers | Goose | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 2.51 / 3.26 | 2.68 / 4.05 | 3.65 / 4.55 | 3.35 / 4.55 | 5.19 / 7.05 | 38.1 / 46.3 |
| plaintext, 256, 4 | 1.23 / 1.70 | 1.24 / 1.47 | 1.19 / 1.52 | 1.21 / 1.45 | 1.60 / 3.51 | 8.33 / 14.9 |
| plaintext, 1,024, 1 | 10.2 / 13.6 | 10.3 / 13.4 | 14.6 / 19.4 | 13.4 / 16.1 | 4.92 / 170 | 188 / 526 |
| plaintext, 1,024, 4 | 4.80 / 5.46 | 4.82 / 5.61 | 4.79 / 5.57 | 4.86 / 5.58 | 5.12 / 19.2 | 34.4 / 67.7 |
| plaintext, 4,096, 1 | 42.3 / 53.6 | 43.1 / 58.6 | 57.8 / 87.3 | 54.1 / 63.2 | 4.84 / 756 | 175 / 3,048 |
| plaintext, 4,096, 4 | 19.2 / 21.0 | 19.2 / 20.8 | 19.0 / 21.3 | 19.4 / 23.0 | 5.62 / 110 | 115 / 509 |
| json, 256, 1 | 2.02 / 3.38 | – | 2.20 / 3.66 | 2.29 / 3.85 | 2.86 / 5.39 | 2.53 / 3.84 |
| json, 256, 4 | 0.53 / 0.94 | – | 0.58 / 0.89 | 0.67 / 1.04 | 0.80 / 1.74 | 0.70 / 1.33 |
| json, 1,024, 1 | 8.25 / 12.9 | – | 8.64 / 12.6 | 9.12 / 13.9 | 2.84 / 170 | 2.58 / 157 |
| json, 1,024, 4 | 2.13 / 3.80 | – | 2.53 / 3.27 | 2.72 / 3.39 | 2.26 / 12.7 | 2.71 / 13.8 |

hyper and dusty answer some connections at once and starve others at 1,024 and 4,096
connections, so their p50 there is low and their p99 high.

Server CPU time per request in µs: the server's CPU time over the measured wrk run,
divided by the requests wrk counted, the median of the 3 runs. Every server used all of
its CPUs in every cell except may-minihttp at 256 connections with 4 workers, which used
32 of 60 CPU-seconds.

| Test, conns, workers | Goose | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 0.55 | 0.56 | 0.77 | 0.84 | 1.22 | 11.2 |
| plaintext, 256, 4 | 0.74 | 0.72 | 1.14 | 0.90 | 1.58 | 10.7 |
| plaintext, 1,024, 1 | 0.52 | 0.54 | 0.75 | 0.77 | 1.45 | 11.4 |
| plaintext, 1,024, 4 | 0.75 | 0.74 | 1.15 | 0.98 | 1.56 | 11.5 |
| plaintext, 4,096, 1 | 0.65 | 0.66 | 0.86 | 0.90 | 1.41 | 11.5 |
| plaintext, 4,096, 4 | 0.78 | 0.79 | 1.20 | 1.08 | 1.63 | 11.9 |
| json, 256, 1 | 7.75 | – | 8.01 | 8.28 | 11.8 | 12.1 |
| json, 256, 4 | 9.80 | – | 10.6 | 11.7 | 14.0 | 11.1 |
| json, 1,024, 1 | 7.60 | – | 8.29 | 8.71 | 14.4 | 13.3 |
| json, 1,024, 4 | 10.2 | – | 10.8 | 11.6 | 14.2 | 14.1 |

Peak RSS (`VmHWM`) in MB, over the whole cell:

| Test, conns, workers | Goose | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 2.1 | 5.6 | 14.0 | 69.6 | 8.0 | 8.8 |
| plaintext, 256, 4 | 2.3 | 6.0 | 13.7 | 75.2 | 9.6 | 9.0 |
| plaintext, 1,024, 1 | 2.2 | 15.7 | 47.2 | 178.9 | 21.9 | 30.1 |
| plaintext, 1,024, 4 | 2.4 | 16.2 | 45.7 | 208.9 | 25.3 | 30.3 |
| plaintext, 4,096, 1 | 2.3 | 56.1 | 184.0 | 638.5 | 78.2 | 52.2 |
| plaintext, 4,096, 4 | 2.6 | 57.0 | 184.2 | 614.7 | 92.0 | 117.9 |
| json, 256, 1 | 2.1 | (6,451) | 12.2 | 40.1 | 7.5 | 8.8 |
| json, 256, 4 | 2.3 | (14,988) | 13.1 | 41.6 | 8.0 | 9.0 |
| json, 1,024, 1 | 2.2 | (5,905) | 44.0 | 120.9 | 20.8 | 30.1 |
| json, 1,024, 4 | 2.4 | (15,065) | 45.6 | 124.0 | 21.6 | 30.3 |

dusty dropped 1,782 requests at 4,096 connections with 1 worker; no other cell had
errors.

## Instructions per request

`bench/instructions.sh`, on 2026-10-11: one worker on CPU 0, plaintext pipelined 16 deep
at 256 connections, wrk on CPUs 4-15 with 8 threads for 20 s, and `perf stat` on CPU 0
for 10 s from 5 s in, so the counts include the kernel's network work on that CPU. Three
runs per server
([2026-10-11-final2-instructions](../bench/results/2026-10-11-final2-instructions/instructions.tsv)),
the range of the three:

| Server | Instructions per request | In user code | Cycles per request | Peak RSS |
|---|---:|---:|---:|---:|
| Goose | 2,255-2,371 | 1,351-1,427 | 1,974-2,543 | 2.1 MB |
| vanilla-epoll | 1,756-1,765 | 763-767 | 1,907-1,955 | 5.4 MB |
| may-minihttp | 2,983-3,011 | 1,946-1,963 | 2,699-2,952 | 66.6 MB |
| tokio | 4,330-4,375 | 3,394-3,428 | 2,702-2,732 | 10.1 MB |
| hyper | 6,185-6,342 | 5,234-5,381 | 4,135-4,203 | 7.2 MB |
| dusty | 20,239 | 7,958 | 26,778 | 8.8 MB |

dusty has one run: its first refused wrk's connections, and the retry kept only its
first round. Goose's third run, at 1.20 M requests per second against 1.57-1.67 M, ran
beside work on CPU 15; its 2,543 cycles per request are that run's.

Binary sizes, as `bench/build.sh` builds them: Goose 68,376 bytes, vanilla-epoll 205,920,
tokio 630,304, hyper 818,592, may-minihttp 931,456, and dusty 1,769,856. The Goose
server is 1,081 lines: `src/server.goose`, `src/http.goose`, `src/sys.goose`,
`src/main.goose`, and `shim/net.h`.

## HttpArena's profiles

[HttpArena](https://www.http-arena.com/)'s own harness at `0720ee5`, run by
`bench/httparena.sh run` under Docker Desktop 29.8.2 on 2026-10-11: each server's
container on CPUs 0-3, gcannon `11c802b` on CPUs 4-15 with 4 threads, the best of 3 runs
of 5 s per profile, and latency-1m at 200,000 requests per second instead of 1,000,000.
The script's header lists what else it changes in the checkout. Results in
[bench/results/httparena-2026-10-11-final2](../bench/results/httparena-2026-10-11-final2).

| Profile | Goose | tokio | vanilla-epoll | dusty |
|---|---:|---:|---:|---:|
| baseline (mixed GET and POST), req/s | 545K | 496K | 455K | 416K |
| limited-conn (10 requests per connection), req/s | 308K | 314K | 305K | 348K |
| pipelined, req/s | 7.07M | 6.51M | 7.01M | 0.60M |
| latency-1m, CPU per request | 10.91 µs | 10.90 µs | 11.29 µs | 14.92 µs |
| latency-1m, p99 | 356 µs | 2,609 µs | 449 µs | 490 µs |
| baseline, container memory | 33 MiB | 188 MiB | 77 MiB | 163 MiB |

Memory and CPU here are the container's, socket buffers included, so they compare
containers, not processes. The servers used 274-362% of their 400% CPU in baseline,
limited-conn, and pipelined, so those profiles measure gcannon as much as the servers.
latency-1m's p99 moved by up to 15 times between this run and the morning's for the same
servers (tokio 172 µs then), so it ranks them only roughly.

## The parser alone

`bench/parse.sh` and the parsers' own benchmarks, on CPU 2, per parse of
picohttpparser's benchmark request (725 bytes, a browser's with a long cookie). Goose at
`b6a26c5`; the others as task 009 records them.

| Parser, build | ns per parse |
|---|---:|
| picohttpparser, gcc `-O2 -msse4.2` | 108.0 |
| Goose's `http::parse`, `goose -O2`, gcc `-O2` | 124.0 |
| httparse 1.10.1, `-C target-cpu=native` (httparse's own request, 17 bytes longer) | 144.7 |
| httparse 1.10.1, default build (the same) | 168.0 |
| picohttpparser, gcc `-O2` | 217.8 |

Goose's `parse` also checks `Host`, `Content-Length`, `Transfer-Encoding`, and
`Connection`, where the other two only split the head into slices.

## Where Goose loses

- **Plaintext with 4 workers at 256 and 1,024 connections, to vanilla-epoll, by 1%.**
  The runs overlap in both cells (5.375-5.575 M against 5.486-5.762 M at 256), so this
  run calls them even. The morning's matrix at `7cb3e27` had vanilla-epoll ahead by 7%
  and 5%, the first beyond the spread; round 6 (`823d5f6`, task 009) closed most of it.
  Profiled with `perf` on CPUs 0-3, the two spend the same cycles per request, 2,819
  against 2,787-2,819, and the same kernel instructions, about 1,000. Goose runs about
  740 more instructions per request in user code, 1,464-1,520 against 780-791: most are
  parsing, which vanilla-epoll skips for `GET /plaintext ` by matching the request's
  first bytes. Both spend about 5% of their cycles in the kernel's epoll wake-up lock
  under WSL2's paravirtual spinlocks.
- **Instructions per request, to vanilla-epoll**: 2,255-2,371 against 1,756-1,765, for the
  same reason.
- **p99 latency in six of ten cells.** Goose's p99 trails at plaintext with 4 workers
  and 256 connections (1.70 ms against 1.45-1.52 ms for may-minihttp, vanilla-epoll, and
  tokio); at plaintext with 1 worker and 1,024 connections and with 4 workers and 4,096,
  by 0.2 ms to vanilla-epoll; and in three JSON cells, by 0.05-0.53 ms to tokio. Its p50
  is the lowest or within 0.2 ms of it in every cell where no server starves
  connections.
- **HttpArena's limited-conn**, a new connection every 10 requests: 308K against tokio's
  314K and dusty's 348K. dusty's lead exists under Docker only: outside Docker, at the
  same settings, Goose ran 368-389K and dusty 334K (task 009). Goose and tokio make the
  same syscalls per request but two: Goose calls `epoll_wait` 0.30 times per request,
  tokio 0.11, and Goose calls `recv` once more per connection.
- **HttpArena's latency-1m CPU per request**: even with tokio, 10.91 µs against 10.90 µs.

## M1 Pro, Linux in Docker

The same matrix, shortened, in Docker Desktop's Linux VM on a MacBook Pro
(`MacBookPro18,3`, Apple M1 Pro, 8 performance and 2 efficiency cores, macOS 26.3.1).
The VM had 10 CPUs and 8 GB, kernel 7.0.14-linuxkit, and ran `ubuntu:26.04` with gcc
15.2.0, rustc 1.99.0, wrk 4.1.0, and h2load 1.68.0. The Goose server is at `9623c6a`,
built by Goose `efe3155`. On 2026-10-11:

```sh
MACHINE=m1pro-docker SERVERS="goose goose-uring may-minihttp hyper tokio xitca-web" \
    WORKER_COUNTS=4 SERVER_CPUS=0-3 CLIENT_CPUS=4-9 CLIENT_THREADS=8 \
    RUNS=3 DURATION=10 WARMUP=3 TESTS="plaintext:256 plaintext:1024 json:256" bench/run.sh
```

That's 4 workers on VM CPUs 0-3 and wrk and h2load with 8 threads on CPUs 4-9, 3
interleaved runs of 10 s after 3 s of warm-up. Medians, from
[2026-10-11-m1pro-docker](../bench/results/2026-10-11-m1pro-docker/summary.md):

| | Goose | goose-uring | tokio | may-minihttp | hyper | xitca-web |
|---|---:|---:|---:|---:|---:|---:|
| plaintext, 256 conns, req/s | 6.96 M | 6.42 M | 6.10 M | 2.98 M | 3.31 M | 2.44 M |
| plaintext, 1,024 conns, req/s | 6.89 M | 6.60 M | 5.89 M | 5.90 M | 3.21 M | 2.37 M |
| JSON, 256 conns, req/s | 0.870 M | 0.870 M | 0.828 M | 0.816 M | 0.580 M | 0.643 M |
| p99 (h2load), JSON | 3.01 ms | 3.08 ms | 3.02 ms | 2.90 ms | 1.20 ms | 1.72 ms |

Goose leads every cell. The epoll loop runs 4-8% ahead of the io_uring loop in
plaintext and even in JSON. In JSON, hyper's and xitca-web's p99 is 1.2-1.7 ms against
2.9-3.1 ms for the four faster servers, at two thirds of their rate.

- The field is partial: vanilla-epoll, odin-http, and the Zig servers didn't build here.
  `bench/build.sh` builds the Zig servers for `x86_64-linux-musl`, and V's bootstrap is
  pinned for x86-64.
- wrk used 51-58 s of the 60 CPU seconds its 6 CPUs had, in every Goose, goose-uring,
  and tokio cell, so the client bounds those cells and the gaps among the three are
  likely smaller than the servers' own.
- The VM runs transparent huge pages set to `always`, so peak RSS (30-36 MB for Goose)
  is mostly 2 MB pages: an idle Goose server with 4 workers held 22 MB, 20 MB of it in
  `AnonHugePages`. RSS doesn't compare with the WSL2 machine's here.
- The VM's CPUs are macOS threads, shared with macOS's own load (a load average of 4-10
  during the session, from other work on the machine).

## M1 Pro, macOS native

The kqueue build on the same MacBook Pro, natively, against the Rust servers that build on
macOS, with `bench/run-macos.sh` on 2026-10-11: 4 workers per server and wrk 4.2.0 with
4 threads, on the same machine with nothing pinned; plaintext pipelined 16 deep and JSON,
with TechEmpower's headers; 3 interleaved runs of 10 s after 3 s of warm-up; on AC
power, under `caffeinate -i`, with `kern.ipc.somaxconn` at its default of 128. Medians,
from [2026-10-11-m1pro-native](../bench/results/2026-10-11-m1pro-native/runs.tsv):

| | Goose | hyper | tokio | may-minihttp |
|---|---:|---:|---:|---:|
| plaintext, 256 conns, req/s | 558 K | 560 K | 587 K | 538 K |
| plaintext, 1,024 conns, req/s | 537 K | 536 K | 554 K | 513 K |
| JSON, 256 conns, req/s | 35.9 K | 35.8 K | 37.2 K | 35.0 K |
| peak RSS, any cell | 1.9 MB | 7-23 MB | 15-56 MB | 56-194 MB |

These numbers rank the kernel, not the servers. Every server lands within 5% of Goose,
and the limit is one exchange per round trip that macOS's loopback carries, about
35,000-40,000 a second:

- Goose with 1 worker serves JSON at the same 36 K as with 4. wrk, h2load, and oha all
  reach 35-38 K, and 16 connections reach 40 K.
- Two independent pairs, two Goose servers each loaded by its own wrk, ran 36.0 K alone
  and 17.9 K each together.
- Under load the machine is 70% idle: Goose's 4 workers take one core between them, wrk
  one, and `kernel_task` one.
- Plaintext reaches 550 K because wrk sends 16 requests per write: about 34,000 writes a
  second, as in JSON.

tokio leads by 3-5%, with its `SO_REUSEPORT` listeners, which macOS doesn't balance:
the last one bound takes every connection (task 006); under load, one of its 4 threads
used CPU and the other three none.
With the kernel as the limit, fewer threads waking is an advantage. Goose's rank here
says nothing about its code; task 012 has the profile.
