# Results

The Goose server's latest numbers against the competing servers. Each section's
numbers come from one machine, which the section names; numbers from different
machines aren't compared. How each number is taken is in [bench/README.md](../bench/README.md#method), and
the servers' pins and builds are in its [Servers](../bench/README.md#servers) table. The
runs behind each section, and the earlier ones, are recorded in task 009
([tasks/000-archive/009-more-competitors.md](../tasks/000-archive/009-more-competitors.md)), but for the WSL2
run of 2026-10-12, which this file alone describes; task 004
([archived](../tasks/000-archive/004-benchmark.md)) holds the first matrix and its
profile, and task 008 ([archived](../tasks/000-archive/008-clang-simd.md)) the compiler
comparison.

## Machine

- AMD Ryzen 7 5800X3D, 8 cores, 16 logical CPUs, 15 GB of memory for WSL2.
- Windows 11, WSL2 kernel 6.18.40.1-microsoft-standard-WSL2, Ubuntu 26.04.1.
- The Goose server at `ef09c0f`, built by Goose `5c83a5a` and gcc 15.2.0 (`-O2`), in
  both of the package's loops: epoll, and io_uring. rustc 1.99.0, Zig 0.16.0, and V 0.5.2
  for the others.
- Every server runs on CPUs 0-3 (two cores with both SMT threads), with the same worker
  count as Goose; the load generators run on CPUs 4-15.

WSL2 runs the loopback network in a VM, so the kernel's share of each request is larger
than it would be on bare metal.

## TechEmpower's tests

`bench/run.sh` with its defaults, on 2026-10-12: plaintext pipelined 16 deep and JSON
without pipelining, with TechEmpower's request headers; 1 worker on CPU 0 and 4 workers
on CPUs 0-3; wrk and h2load with 8 threads; a fresh server per cell; 3 runs of 15 s after
5 s of warm-up, interleaved. Medians of the 3 runs, from
[2026-10-12-full-plaintext](../bench/results/2026-10-12-full-plaintext/summary.md) and
[2026-10-12-full-json](../bench/results/2026-10-12-full-json/summary.md), which also
have each cell's spread, the h2load rate, and the clock steps. Nothing else ran on the
machine meanwhile. The Goose server ran with each loop: `goose` serves with the epoll
loop, and `goose-uring` with the io_uring loop.

Requests per second, from wrk:

| Test, conns, workers | Goose epoll | Goose io_uring | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 1.902 M | 2.131 M | 1.903 M | 1.375 M | 1.216 M | 0.860 M | 0.089 M |
| plaintext, 256, 4 | 5.830 M | 7.062 M | 6.097 M | 3.891 M | 2.390 M | 2.689 M | 0.408 M |
| plaintext, 1,024, 1 | 1.864 M | 2.119 M | 1.911 M | 1.347 M | 1.297 M | 0.692 M | 0.087 M |
| plaintext, 1,024, 4 | 5.773 M | 6.910 M | 5.855 M | 3.831 M | 4.310 M | 2.668 M | 0.357 M |
| plaintext, 4,096, 1 | 1.538 M | 1.875 M | 1.532 M | 1.190 M | 1.070 M | 0.713 M | 0.080 M |
| plaintext, 4,096, 4 | 5.532 M | 6.451 M | 5.463 M | 3.648 M | 3.953 M | 2.540 M | 0.338 M |
| json, 256, 1 | 0.145 M | 0.171 M | 0.071 M | 0.134 M | 0.123 M | 0.085 M | 0.083 M |
| json, 256, 4 | 0.430 M | 0.513 M | (0.216 M) | 0.394 M | 0.375 M | 0.303 M | 0.366 M |
| json, 1,024, 1 | 0.127 M | 0.153 M | 0.061 M | 0.116 M | 0.113 M | 0.072 M | 0.074 M |
| json, 1,024, 4 | 0.425 M | 0.501 M | (0.218 M) | 0.386 M | 0.364 M | 0.295 M | 0.316 M |

- The io_uring loop leads every cell, at 1.12-1.22 times the epoll loop.
- The epoll loop and vanilla-epoll are within each other's spreads in five of six
  plaintext cells. In the sixth, 4 workers at 256 connections, vanilla-epoll leads by 5%
  ([below](#where-goose-loses)).
- In JSON, the epoll loop leads every other server, at 1.08-1.10 times tokio, the next.
- vanilla-epoll's JSON ran in a run of its own,
  [2026-10-12-full-json-vanilla](../bench/results/2026-10-12-full-json-vanilla/runs.tsv),
  under a watchdog that stops it when the host's free memory falls below 3 GB.
  HttpArena builds it with `-gc none`, and its JSON encoder's allocations are never
  freed (`docs/development.md`). Its 1-worker cells finished one run each, at 5.6-6.1 GB
  of RSS. The watchdog stopped it in the first 4-worker cell, so those two cells, in
  parentheses, are from the matrix of 2026-10-11 at `7cb3e27`
  ([2026-10-11-matrix](../bench/results/2026-10-11-matrix/summary.md)), at 15 GB.

Latency, p50 / p99 in ms, from h2load. h2load runs slower than wrk here, so every fast
server sees about the same offered load, and p99 shows how evenly each treats its
connections:

| Test, conns, workers | Goose epoll | Goose io_uring | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 2.60 / 3.46 | 2.26 / 3.14 | 2.59 / 3.41 | 3.68 / 4.24 | 3.35 / 4.07 | 5.22 / 6.12 | 37.4 / 42.3 |
| plaintext, 256, 4 | 1.22 / 1.44 | 1.22 / 1.50 | 1.23 / 1.47 | 1.18 / 1.55 | 1.21 / 1.43 | 1.49 / 3.29 | 6.22 / 15.1 |
| plaintext, 1,024, 1 | 10.4 / 12.6 | 8.72 / 10.8 | 10.4 / 12.6 | 14.7 / 16.8 | 13.5 / 16.6 | 4.92 / 168 | 188 / 525 |
| plaintext, 1,024, 4 | 4.79 / 5.31 | 4.78 / 5.26 | 4.85 / 5.31 | 4.77 / 5.94 | 4.84 / 5.42 | 4.80 / 19.2 | 34.7 / 65.4 |
| plaintext, 4,096, 1 | 42.5 / 49.6 | 40.4 / 45.2 | 43.0 / 47.4 | 57.8 / 74.3 | 54.3 / 60.6 | 4.86 / 753 | 188 / 3,694 |
| plaintext, 4,096, 4 | 19.0 / 20.7 | 18.9 / 20.5 | 18.9 / 20.7 | 19.0 / 21.2 | 19.1 / 20.6 | 5.14 / 111 | 113 / 445 |
| json, 256, 1 | 2.05 / 2.39 | 1.75 / 2.12 | 3.62 / 5.16 | 2.19 / 2.51 | 2.29 / 2.57 | 2.83 / 3.33 | 2.17 / 2.69 |
| json, 256, 4 | 0.48 / 0.78 | 0.40 / 0.59 | – | 0.57 / 0.85 | 0.64 / 0.83 | 0.76 / 1.65 | 0.69 / 0.98 |
| json, 1,024, 1 | 8.03 / 9.57 | 7.09 / 8.14 | 14.3 / 19.8 | 8.66 / 9.64 | 8.98 / 10.7 | 2.82 / 171 | 2.57 / 157 |
| json, 1,024, 4 | 2.05 / 2.70 | 1.65 / 2.22 | – | 2.45 / 3.15 | 2.66 / 3.19 | 2.19 / 12.6 | 2.45 / 12.4 |

hyper and dusty answer some connections at once and starve others at 1,024 and 4,096
connections, so their p50 there is low and their p99 high.

Server CPU time per request in µs: the server's CPU time over the measured wrk run,
divided by the requests wrk counted, the median of the 3 runs. Every server used all of
its CPUs in every cell except may-minihttp at 256 connections with 4 workers, which used
32 of 60 CPU-seconds.

| Test, conns, workers | Goose epoll | Goose io_uring | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 0.53 | 0.47 | 0.53 | 0.73 | 0.82 | 1.17 | 11.3 |
| plaintext, 256, 4 | 0.69 | 0.57 | 0.66 | 1.04 | 0.88 | 1.50 | 9.87 |
| plaintext, 1,024, 1 | 0.54 | 0.47 | 0.53 | 0.75 | 0.77 | 1.46 | 11.4 |
| plaintext, 1,024, 4 | 0.70 | 0.58 | 0.69 | 1.05 | 0.92 | 1.51 | 11.2 |
| plaintext, 4,096, 1 | 0.65 | 0.53 | 0.65 | 0.84 | 0.93 | 1.42 | 12.3 |
| plaintext, 4,096, 4 | 0.72 | 0.62 | 0.73 | 1.10 | 1.01 | 1.58 | 11.8 |
| json, 256, 1 | 6.95 | 5.84 | 14.1 | 7.49 | 8.17 | 11.8 | 12.0 |
| json, 256, 4 | 9.33 | 7.77 | – | 10.2 | 10.7 | 13.2 | 11.0 |
| json, 1,024, 1 | 7.85 | 6.51 | 16.2 | 8.64 | 8.81 | 13.9 | 13.4 |
| json, 1,024, 4 | 9.36 | 7.95 | – | 10.3 | 11.0 | 13.5 | 12.6 |

Peak RSS (`VmHWM`) in MB, the largest of the cell's runs:

| Test, conns, workers | Goose epoll | Goose io_uring | vanilla-epoll | tokio | may-minihttp | hyper | dusty |
|---|---:|---:|---:|---:|---:|---:|---:|
| plaintext, 256, 1 | 2.4 | 5.3 | 5.6 | 13.8 | 71.6 | 8.0 | 8.8 |
| plaintext, 256, 4 | 2.6 | 9.8 | 6.0 | 13.4 | 77.5 | 9.5 | 9.0 |
| plaintext, 1,024, 1 | 2.4 | 5.5 | 15.7 | 46.5 | 178.9 | 22.0 | 30.1 |
| plaintext, 1,024, 4 | 2.7 | 12.3 | 16.2 | 47.4 | 206.7 | 25.7 | 30.3 |
| plaintext, 4,096, 1 | 2.9 | 6.0 | 56.1 | 183.2 | 618.6 | 78.2 | 77.0 |
| plaintext, 4,096, 4 | 3.2 | 15.9 | 57.0 | 183.3 | 621.0 | 88.4 | 116.6 |
| json, 256, 1 | 2.4 | 4.6 | 6,212 | 12.2 | 38.6 | 7.6 | 8.8 |
| json, 256, 4 | 2.6 | 9.7 | (14,988) | 13.2 | 40.6 | 8.3 | 9.0 |
| json, 1,024, 1 | 2.5 | 5.3 | 5,739 | 43.5 | 114.8 | 20.7 | 30.1 |
| json, 1,024, 4 | 2.7 | 11.4 | (15,065) | 45.1 | 122.8 | 21.4 | 30.3 |

The io_uring loop peaks 2-13 MB above the epoll loop; task 016 accounts for each
worker's memory. dusty dropped 1,361 requests at 4,096 connections with 1
worker; no other cell had errors.

## Instructions per request

`bench/instructions.sh`, on 2026-10-12: one worker on CPU 0, plaintext pipelined 16 deep
at 256 connections, wrk on CPUs 4-15 with 8 threads for 20 s, and `perf stat` on CPU 0
for 10 s from 5 s in, so the counts include the kernel's network work on that CPU. Three
runs per server
([2026-10-12-full-instructions](../bench/results/2026-10-12-full-instructions/instructions.tsv)),
the range of the three:

| Server | Instructions per request | In user code | Cycles per request | Peak RSS |
|---|---:|---:|---:|---:|
| Goose epoll | 2,418-2,469 | 1,494-1,527 | 1,921-1,933 | 2.4 MB |
| Goose io_uring | 2,503-2,517 | 1,545-1,554 | 1,719-1,740 | 5.3 MB |
| vanilla-epoll | 1,750-1,758 | 763-767 | 1,916-1,929 | 5.4 MB |
| may-minihttp | 2,999-3,023 | 1,957-1,973 | 2,761-2,772 | 66.7 MB |
| tokio | 4,369-4,399 | 3,428-3,452 | 2,666-2,676 | 10.0 MB |
| hyper | 6,286-6,365 | 5,327-5,405 | 4,072-4,151 | 7.3 MB |
| dusty | 20,264-20,293 | 7,990-7,992 | 26,811-27,263 | 8.8 MB |

The io_uring loop runs 20-60 more user instructions per request than the epoll loop,
and about 200 fewer cycles. Since 2026-10-11 (`b6a26c5`), the epoll loop's user
instructions rose from 1,351-1,427 to 1,494-1,527, for the package's streaming, files,
and settings (task 013 splits that cost by commit). Its cycles per request didn't rise:
1,921-1,933, against 1,974 and 2,107 in that run's two undisturbed runs.

Binary sizes, as `bench/build.sh` builds them: Goose 183,128 bytes with both loops,
vanilla-epoll 205,920, tokio 630,304, hyper 818,592, may-minihttp 931,456, and dusty
1,769,856. The package is 2,793 lines of Goose, the benchmark server 328, and the Linux
shim, `shim/net.c` and `shim/uring.c`, 642 lines of C.

## The package's build

Task 011 made the server a program over the package, with the routes as its handler.
On the machine above, on 2026-10-11, at `2d61b55` with Goose `fe6c543`, both loops run
as fast as `1bea5a0`, the last build before it, built fresh beside it with the same
compiler. `bench/instructions.sh` (as above, 3 runs):

| Build | Instructions per request | In user code | Cycles per request |
|---|---:|---:|---:|
| epoll, `2d61b55` | 2,286-2,311 | 1,349-1,364 | 1,888-1,921 |
| epoll, `1bea5a0` | 2,344-2,355 | 1,407-1,415 | 1,890-1,895 |
| io_uring, `2d61b55` | 2,370-2,378 | 1,405-1,410 | 1,694-1,701 |
| io_uring, `1bea5a0` | 2,417-2,439 | 1,453-1,467 | 1,702-1,725 |

`bench/run.sh` with its defaults, `TESTS="plaintext:256 plaintext:1024 json:256"`, 1
worker on CPU 0 and 4 on CPUs 0-3, 3 runs of 15 s: each loop's median wrk rate is
within 3% of `1bea5a0`'s in all 6 cells, inside the runs' spreads but for three cells
where the package's build is 2-3% faster. The epoll loop served 6.01 M requests per
second in plaintext at 256 connections with 4 workers, and the io_uring loop 7.45 M.
The cells, and the regression the first build had before its parser and response
writers were made `inline fn`, are in task 011
([tasks/000-archive/011-package.md](../tasks/000-archive/011-package.md#speed-2026-10-11)); the runs are in
`bench/results/2026-10-11-package/` and `bench/results/2026-10-11-package-instructions/`.

## HttpArena's profiles

[HttpArena](https://www.http-arena.com/)'s own harness at `0720ee5`, run by
`bench/httparena.sh run` under Docker Desktop 29.8.2 on 2026-10-12: each server's
container on CPUs 0-3, gcannon `11c802b` on CPUs 4-15 with 4 threads, the best of 3 runs
of 5 s per profile, and latency-1m at 200,000 requests per second instead of 1,000,000.
The script's header lists what else it changes in the checkout. The Goose entry is the
epoll loop, since Docker's default seccomp profile blocks io_uring, at `1a1f368` with
Goose `5c83a5a`; `env.txt` says "(modified)" for an edit to this file. Results in
[bench/results/httparena-2026-10-12-full](../bench/results/httparena-2026-10-12-full).

| Profile | Goose | tokio | vanilla-epoll | dusty |
|---|---:|---:|---:|---:|
| baseline (mixed GET and POST), req/s | 524K | 508K | 478K | 423K |
| limited-conn (10 requests per connection), req/s | 311K | 316K | 308K | 352K |
| pipelined, req/s | 7.39M | 6.72M | 7.18M | 0.59M |
| latency-1m, CPU per request | 10.58 µs | 10.71 µs | 11.00 µs | 14.64 µs |
| latency-1m, p99 | 230 µs | 159 µs | 176 µs | 181 µs |
| baseline, container memory | 34 MiB | 175 MiB | 76 MiB | 161 MiB |

Memory and CPU here are the container's, socket buffers included, so they compare
containers, not processes. The servers used 232-362% of their 400% CPU in baseline,
limited-conn, and pipelined, so those profiles measure gcannon as much as the servers.
latency-1m's p99 moved by up to 15 times between runs on 2026-10-11, so it ranks the
servers only roughly.

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

From the run of 2026-10-12 above. The io_uring loop leads every TechEmpower cell; the
losses are the epoll loop's, which is also the HttpArena entry, and memory.

- **The epoll loop, plaintext with 4 workers at 256 connections, to vanilla-epoll, by
  5%**: 5.830 M (5.799-5.874 M) against 6.097 M (5.983-6.104 M), beyond both spreads.
  In the other five plaintext cells the two are within each other's spreads. Profiled
  with `perf` on CPUs 0-3 on 2026-10-11 (`b6a26c5`, task 009), the two spent the same
  cycles per request, 2,819 against 2,787-2,819, and the same kernel instructions,
  about 1,000. Goose ran about 740 more instructions per request in user code: most are
  parsing, which vanilla-epoll skips for `GET /plaintext ` by matching the request's
  first bytes. Both spent about 5% of their cycles in the kernel's epoll wake-up lock
  under WSL2's paravirtual spinlocks.
- **Instructions per request, to vanilla-epoll**: 2,418-2,469 for the epoll loop against
  1,750-1,758, and 1,494-1,527 against 763-767 in user code, for the same reason.
  Cycles per request are even, 1,921-1,933 against 1,916-1,929.
- **p99 latency, in four plaintext cells.** The epoll loop trails a competitor by
  0.05 ms or less at 256 connections, by 0.1 ms at 4,096 with 4 workers, and by 2.2 ms
  at 4,096 with 1 worker (49.6 against 47.4 ms for vanilla-epoll). The io_uring loop
  has the lowest p99 of the servers that don't starve connections in every cell but
  plaintext with 4 workers at 256 connections: 1.50 ms against 1.43 ms for
  may-minihttp.
- **Peak RSS of the io_uring loop at 256 connections with 4 workers**: 9.7-9.8 MB, above
  vanilla-epoll's 6.0 MB, hyper's 8.3-9.5 MB, and dusty's 9.0 MB. The epoll loop's is
  the lowest in every cell (task 016).
- **HttpArena's limited-conn**, a new connection every 10 requests: 311K against tokio's
  316K and dusty's 352K. dusty's lead exists under Docker only: outside Docker, at the
  same settings, Goose ran 368-389K and dusty 334K (task 009). Goose and tokio make the
  same syscalls per request but two: Goose calls `epoll_wait` 0.30 times per request,
  tokio 0.11, and Goose calls `recv` once more per connection (task 009).
- **HttpArena's latency-1m p99**: 230 µs against 159-181 µs, a measure that moves by up
  to 15 times between runs.

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

### The full field, 3 workers

The same VM and image with Zig 0.16.0 and Odin `dev-2026-10` added, every server built for
arm64 by `bench/build.sh` (its notes in [bench/README.md](../bench/README.md#servers)),
on 2026-10-11. The Goose server is at `b2e0337`, built by Goose `efe3155`; `env.txt`
shows "(modified)" because the runs used a copy of the working tree:

```sh
MACHINE=m1pro-docker SERVERS="goose goose-uring tokio vanilla-epoll vanilla-io_uring \
    may-minihttp hyper xitca-web odin-http dusty zix zeemo libreactorng" \
    WORKER_COUNTS=3 SERVER_CPUS=0-2 CLIENT_CPUS=3-9 CLIENT_THREADS=8 \
    RUNS=3 DURATION=10 WARMUP=3 TESTS="plaintext:256 plaintext:1024" bench/run.sh
```

JSON ran the same way, with `TESTS=json:256` and without vanilla-epoll, whose JSON cells
grow its memory past the VM's 8 GB. That's 3 workers on VM CPUs 0-2 and wrk and h2load
with 8 threads on CPUs 3-9: a pilot with 4 workers left wrk at 50 of its 60 CPU seconds,
and with 2 workers the server was the limit. Medians of 3 interleaved runs of 10 s, from
[3w-plaintext](../bench/results/2026-10-11-m1pro-docker-3w-plaintext/summary.md) and
[3w-json](../bench/results/2026-10-11-m1pro-docker-3w-json/summary.md):

| Server | plaintext, 256 | plaintext, 1,024 | JSON, 256 | JSON p99 (h2load) |
|---|---:|---:|---:|---:|
| goose-uring | 6.65 M | 7.00 M | 0.826 M | 1.64 ms |
| goose | 6.90 M | 7.09 M | 0.749 M | 1.67 ms |
| zix | 4.65 M | 4.34 M | 0.742 M | 1.01 ms |
| zeemo | 2.74 M | 2.72 M | 0.737 M | 0.99 ms |
| libreactorng | 4.60 M | 5.17 M | 0.721 M | 0.99 ms |
| tokio | 5.26 M | 5.22 M | 0.624 M | 1.06 ms |
| may-minihttp | 2.92 M | 5.48 M | 0.579 M | 0.84 ms |
| vanilla-io_uring | 6.20 M | 6.16 M | 0.539 M | 2.56 ms |
| xitca-web | 1.88 M | 1.71 M | 0.504 M | 0.96 ms |
| dusty | 0.41 M | 0.28 M | 0.474 M | 0.86 ms |
| odin-http | 0.37 M | 0.35 M | 0.335 M | 1.76 ms |
| hyper | 2.24 M | 2.15 M | 0.334 M | 1.20 ms |
| vanilla-epoll | 6.03 M | 6.03 M | not run | |

- The two Goose loops lead plaintext, and goose-uring leads JSON, 10% ahead of the epoll
  loop, which ties zix, zeemo, and libreactorng within 4%. JSON is the cell that ranks
  the servers here: every server used all 30 of its CPU seconds, and wrk used 26-53 of its
  70.
- In plaintext both ends are near their limits in the top cells: the servers used 26-29
  of 30 CPU seconds, wrk 60-65 of 70. The plaintext order of Goose, goose-uring, and the
  vanilla servers is within run-to-run spreads of up to 20%.
- Rows other than the Goose builds, dusty, and zix were measured in a first pass and
  copied by `REUSE` (the summaries' From column). Goose drifted between the passes: 6.11 M
  against 6.90 M at 256 connections, and 0.717 M against 0.749 M in JSON, so the copied
  rows' gaps to Goose carry up to 13% of session drift. The first pass is in
  [field-plaintext](../bench/results/2026-10-11-m1pro-docker-field-plaintext/summary.md)
  and [field-json](../bench/results/2026-10-11-m1pro-docker-field-json/summary.md).
- dusty and zix were measured again because the first pass built them with Zig's
  `native`, which resolves to generic arm64 in the VM. With `apple_m1`, zix lost 10% in
  plaintext (5.19 M to 4.65 M) and held JSON; dusty gained 7% in JSON.
- dusty and odin-http serve pipelined plaintext at 0.3-0.5 M, below their JSON rate, as
  dusty did under HttpArena on WSL2 (0.60 M).

### HttpArena's profiles

HttpArena's harness at `0720ee5`, run by `bench/httparena.sh run` from a Linux container
on Docker Desktop (`docs/development.md`, "HttpArena under Docker on macOS"), on
2026-10-11 at `16528ea` with Goose `efe3155`, so the Goose entry is the epoll loop: each
server's container on VM CPUs 0-2, gcannon `11c802b` on CPUs 3-9 with 4 threads, the best
of 3 runs of 5 s per profile, and latency-1m at 200,000 requests per second. On arm64 the
script takes zrk's aarch64 release and tccbin's arm64 branch for vanilla-epoll; every
entry passed `validate`. Results in
[bench/results/httparena-2026-10-11-m1pro-docker](../bench/results/httparena-2026-10-11-m1pro-docker).

| Profile | Goose | tokio | vanilla-epoll | dusty |
|---|---:|---:|---:|---:|
| baseline (mixed GET and POST), req/s | 631K | 526K | 518K | 390K |
| limited-conn (10 requests per connection), req/s | 503K | 389K | 439K | 444K |
| pipelined, req/s | 6.59M | 6.26M | 6.58M | 0.55M |
| latency-1m, CPU per request | 8.05 µs | 8.35 µs | 8.42 µs | 10.84 µs |
| latency-1m, p99 | 210 µs | 200 µs | 323 µs | 332 µs |
| baseline, container memory | 53 MiB | 136 MiB | 77 MiB | 148 MiB |

Goose leads baseline by 20% and limited-conn by 13%, ties vanilla-epoll in pipelined, and
spends the least CPU per request at the fixed rate, 4% under tokio. On WSL2, dusty led
limited-conn; here it's third. The servers used 243-292% of their 300% CPU in baseline and
limited-conn, and 203-290% in pipelined (Goose 203%), so those profiles measure gcannon as
much as the servers.
Memory is the container's, socket buffers included, and inflated by the VM's
transparent huge pages, so it compares containers on this VM only. The latency-1m p99
moved by up to 15 times between runs on WSL2, so it ranks the servers only roughly.

The Goose entry at `ac399a3`, in the package layout with Goose `fe6c543` and still the
epoll loop, measured the same in a run of its own: 629K in baseline, 478K in
limited-conn, 6.61M in pipelined, and 8.09 µs per request in latency-1m
([httparena-2026-10-11-m1pro-docker-main](../bench/results/httparena-2026-10-11-m1pro-docker-main)).
limited-conn moves between sessions: alternated twice each, `1fb0ef3` measured 480K and
482K and `ac399a3` 474K and 480K.

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
