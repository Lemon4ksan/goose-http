# Measurement records

Provenance and limitations for the [current benchmarks](benchmarks.md), plus selected
earlier measurements that still explain a decision or an open issue. Raw run
directories remain in `bench/results/`; superseded tables and session narratives are
recoverable from git. [bench/README.md](../bench/README.md) owns the harness and method.

## Machine

Desktop comparisons use an AMD Ryzen 7 5800X3D, 8 cores and 16 logical CPUs, Windows 11,
and WSL2 Ubuntu 26.04.1 with 15 GB assigned to WSL. Servers use CPUs 0-3, load generators
4-15; one-worker cells use CPU 0. Goose is built with gcc 15.2.0 at `-O2`, competitors
in release mode with the configurations in
[the server table](../bench/README.md#servers).

WSL2 loopback runs through a VM; its kernel cost differs from bare metal. Runs through
2026-10-12 use kernel 6.18.40.1-microsoft-standard-WSL2. The 2026-10-14 runs use
6.18.54.1-microsoft-standard-WSL2. Each run's `env.txt` records the environment.

## 2026-10-14: main after tasks 022.03, 025, and 027

The field run uses server `e4f7b55` and Goose `0bdbd18`, before the final worker-load
and shared-store merges. Current throughput tables are in
[benchmarks](benchmarks.md); later memory measurements have separate build labels.

### Plaintext and JSON

`bench/run.sh` with `SERVERS="goose goose-uring libreactorng vanilla-io_uring zix
xitca-web tokio hyper" WORKER_COUNTS=4 LATENCY=0`: 4 workers, wrk 4.1.0 with 8 threads,
3 runs of 15 s after 5 s of warm-up. Plaintext uses 16-deep pipelines at 256, 1,024,
and 4,096 connections; JSON uses 256 and 1,024 without pipelining.
[Summary](../bench/results/2026-10-14-field/summary.md).

`RUNS=3 bench/count.sh` uses one worker and 10 million requests to compare executed
user instructions with `2afc12f`, rebuilt at the same Goose pin. Task 027 records
the comparisons and unresolved benchmark checks.

### REST APIs

`bench/rest.sh build`, then `bench/rest.sh run` with
`SERVERS="goose-uring goose-epoll xitca-web hyper tokio dusty"`: 4 workers, 3 rounds of
15 s after 5 s of warm-up, with each server checked first. Saturation uses wrk with
8 threads and 256 connections. Uploads alone use 1 thread and 32 connections;
the mixed run offers tier C reads at 16,000 requests per second beside uploads.
[Field summary](../bench/results/2026-10-14-rest-field/summary.md).

The later task 025 comparison uses Goose `46356c2` and variant
`goose-uring-27s` at `effcd47`, on the same machine and kernel with the same load
settings. It records the final store and worker-load memory reduction:
[variant summary](../bench/results/2026-10-14-rest-027-025/summary.md).
Its `env.txt` names the orchestration checkout as modified; task 025 identifies
each variant's source commit. The final epoll peak memory has not been remeasured.

Idle memory at `1818526`, Goose `46356c2`, uses the epoll loop, 1, 2, and 4 workers,
one sample of VmRSS 3 s after listening, with no requests:
[idle.tsv](../bench/results/2026-10-14-rest-idle-main/idle.tsv).
Task 025 records the measurement and its remaining accounting work.

## The full field

The earlier desktop matrix at `73dd28c`, Goose `6448f3f`, kernel 6.18.40.1, includes
servers absent from the later field: zeemo, vanilla-epoll, may-minihttp, and Tina.
`bench/run.sh` used 1 and 4 workers, wrk with 8 threads, the same plaintext and JSON
connection counts as above, 3 runs of 15 s, and h2load latency measurements.
[2026-10-12 matrix](../bench/results/2026-10-12-matrix/summary.md).

Some competitor cells were copied with `REUSE` from compatible earlier runs. Their
source appears in the summaries. Session drift reached 5%, so small cross-session
differences do not establish a server improvement. vanilla-epoll's JSON cells were
not rerun because they leaked enough memory to exhaust the VM; those entries are
older measurements.

## Static files

`bench/files.sh` on 2026-10-12, server `fcfd80d`, Goose `5c83a5a`, desktop kernel
6.18.40.1: files on tmpfs, wrk 4.1.0 with 12 threads on CPUs 4-15 and 96 connections;
1 worker on CPU 0 or 4 on CPUs 0-3; 3 runs of 10 s after 3 s of warm-up, medians.
[Summary](../bench/results/2026-10-12-files/summary.md) includes rates, spread, and CPU.

nginx 1.28.3 uses `sendfile`, `tcp_nopush`, `open_file_cache`, and no access log.
Caddy 2.10.2 uses `file_server` and `GOMAXPROCS` equal to the worker count.
At 1 MB with 4 workers, wrk uses all its assigned CPU time: rate measures the client
limit, while server CPU per request still distinguishes the implementations.

Server CPU per request, in µs:

| Server | 4 KB, 1 worker | 4 KB, 4 | 64 KB, 1 | 64 KB, 4 | 1 MB, 1 | 1 MB, 4 |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | 12.3 | 18.5 | 31.6 | 41.1 | 96.3 | 122 |
| Goose epoll | 18.1 | 22.7 | 29.7 | 35.8 | 91.5 | 106 |
| Goose, emulated ring | 13.2 | 19.7 | 22.8 | 33.8 | 85.7 | 107 |
| nginx | 20.2 | 23.4 | 28.6 | 32.5 | 106.8 | 148 |
| Caddy | 77.7 | 81.0 | 79.9 | 84.1 | 155.9 | 197 |

The direct-file threshold and Windows `TransmitFile` comparison are recorded in
task 020. The unexplained 64 KB gap to nginx remains task 024. The same summary
records Goose's in-memory `/bytes` comparison, which separates file handling from
response transmission.

<a id="rest-apis"></a>
<a id="rest-apis-1"></a>
## Earlier REST comparisons

The 2026-10-13 desktop field at `23aa531`, Goose `6448f3f`, kernel 6.18.40.1,
used `bench/rest.sh run`: 4 workers, 8 client threads and 256 connections for
saturation, 3 rounds of 15 s after 5 s of warm-up.
[Summary](../bench/results/2026-10-13-rest/summary.md).
[Fixed-rate rerun](../bench/results/2026-10-13-rest-rates/summary.md).

dusty joined in a separate comparison with hyper and task 027's Goose variants:
[2026-10-13 REST variants](../bench/results/2026-10-13-rest-027/summary.md).
Session drift means its results should first be compared with hyper from that run.
Task 021 records the workloads, competitor exclusions, and the epoll fairness
decision. Tasks 025 and 027 retain the before/after evidence for their changes.

## Instructions per request

The earlier cross-server instruction comparison uses `bench/instructions.sh` on
2026-10-12, server `47876ad`, desktop kernel 6.18.40.1: one worker on CPU 0,
plaintext pipelined 16 deep at 256 connections, wrk with 8 threads on CPUs 4-15 for
20 s, and perf on CPU 0 for 10 s from 5 s into the run; 3 runs. Counts include
kernel network work on that CPU.
[Raw counts](../bench/results/2026-10-12-desktop-instructions/runs.tsv).

Tina's comparison and interpretation are retained in task 019. Fixed-count user
instruction comparisons for current API changes belong to task 027; their totals
are not interchangeable with these CPU-wide counts.

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

Task 018's two profiles, run the same way on 2026-10-12 with the Goose entry at
`4752493` and Goose `6448f3f`, after `bench/httparena.sh validate` passed all 32 of its
checks: async, `GET /delay/10` on 32,000 connections, and latency-10k, latency-1m's
endpoint offered at 10,000 requests per second by zrk 2.3.0 for 20 s. Results in
[bench/results/httparena-2026-10-12-async](../bench/results/httparena-2026-10-12-async).
Latency is the best run's.

| Profile | Goose | tokio | vanilla-epoll | dusty |
|---|---:|---:|---:|---:|
| async, req/s | **241K** | 228K | 196K | 226K |
| async, p50 / p99 | 56 / 99 ms | 61 / 87 ms | 90 / 116 ms | 13 / 216 ms |
| async, container memory | **159 MiB** | 1.1 GiB | 401 MiB | 662 MiB |
| latency-10k, CPU per request | 30.4 µs | 30.6 µs | **30.0 µs** | 42.8 µs |
| latency-10k, p99 / p99.9 | 172 µs / 8.3 ms | 158 µs / 10.8 ms | 166 µs / 16.4 ms | 158 µs / 1.2 ms |
| latency-10k, container memory | **15 MiB** | 42 MiB | 26 MiB | 46 MiB |

- async's 3 runs per server spread by 7-16%: Goose 221-241K, tokio 212-228K,
  vanilla-epoll 180-196K, dusty 193-226K. Each server used 320-343% of its 400% CPU.
- gcannon ran 64 threads in async, not `THREADS`, and counted 38,000-48,000 connect
  errors per run for every server, likely because `SKIP_TUNE` leaves out the
  harness's `system_tune`, which widens the ephemeral port range; not measured.
- dusty answers half its delays at 13 ms and the slowest at 216 ms; the others keep
  p50 and p99 within 2 times of each other.
- At 10,000 requests per second, the four spend 3 times latency-1m's CPU per request:
  each request wakes an idle loop. Goose, tokio, and vanilla-epoll are within 2%.


## M1 Pro, Linux in Docker

The host is a MacBook Pro `MacBookPro18,3`, Apple M1 Pro with 8 performance and
2 efficiency cores, macOS 26.3.1. Docker Desktop 29.8.2 supplies a 10-CPU, 8 GB VM,
kernel 7.0.14-linuxkit, running Ubuntu 26.04 with gcc 15.2.0, rustc 1.99.0,
wrk 4.1.0, and h2load 1.68.0.

The partial field at server `9623c6a`, Goose `efe3155`, used:

```sh
MACHINE=m1pro-docker SERVERS="goose goose-uring may-minihttp hyper tokio xitca-web" \
    WORKER_COUNTS=4 SERVER_CPUS=0-3 CLIENT_CPUS=4-9 CLIENT_THREADS=8 \
    RUNS=3 DURATION=10 WARMUP=3 TESTS="plaintext:256 plaintext:1024 json:256" bench/run.sh
```

[2026-10-11 summary](../bench/results/2026-10-11-m1pro-docker/summary.md).
wrk was near its CPU limit in the fastest cells. Transparent huge pages dominated
Goose's RSS, so it cannot be compared directly with desktop RSS.

The fuller arm64 field at `b2e0337`, Goose `efe3155`, used 3 workers on CPUs 0-2
and 8 client threads on CPUs 3-9, 3 runs of 10 s after 3 s of warm-up:
[plaintext](../bench/results/2026-10-11-m1pro-docker-3w-plaintext/summary.md) and
[JSON](../bench/results/2026-10-11-m1pro-docker-3w-json/summary.md).
JSON omitted vanilla-epoll because its memory growth exceeded the VM's capacity.
Copied competitor rows carry session drift; task 012 retains the open full-matrix
validation. These results are historical platform checks, not current-build rankings.

HttpArena `0720ee5` on the same VM used server `16528ea`, Goose `efe3155`, and the
epoll entry: `bench/httparena.sh run`, 3 workers on CPUs 0-2, gcannon `11c802b` with
4 threads on CPUs 3-9, best of 3 runs of 5 s; latency-1m offered 200,000 requests per
second. Every entry passed validation.
[Profile records](../bench/results/httparena-2026-10-11-m1pro-docker).
The clients also constrained these profiles. Memory includes socket buffers and
transparent huge pages, so it compares containers on this VM only.

## M1 Pro, macOS native

`bench/run-macos.sh` on 2026-10-11 used server `9623c6a` on the same M1 Pro host,
macOS 26.3.1, Darwin 25.3.0: 4 workers per server,
wrk 4.2.0 with 4 threads, 256 and 1,024 plaintext connections pipelined 16 deep,
256 JSON connections, 3 runs of 10 s after 3 s of warm-up. Nothing was pinned;
the machine was on AC power under `caffeinate -i`, with listen backlog cap 128.
[Raw runs](../bench/results/2026-10-11-m1pro-native/runs.tsv).

All servers were near the same loopback round-trip limit. Adding workers did not
raise JSON throughput; two independent server/client pairs shared the same total
capacity. These runs show native operation and memory use, not a reliable ranking
of server implementations. Task 012 records the profile and shared-listener work.

## Windows, IOCP

Task 017's baseline records `bench/oha.sh` on both Windows and WSL2 at `fcfd80d`,
Goose `5c83a5a`, desktop kernel 6.18.40.1: oha 1.16.0, 2 million plaintext requests,
256 connections, 1 and 4 workers, 3 runs, with no CPU pinning. The client shares CPUs
with the server, so the comparison does not isolate server capacity.
[IOCP runs](../bench/results/2026-10-12-iocp-plaintext) and
[io_uring runs](../bench/results/2026-10-12-uring-plaintext-oha).
The kernel trace analysis and candidate evaluation remain open in task 017.
