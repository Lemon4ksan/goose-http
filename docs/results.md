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

### The full field

`bench/run.sh` on 2026-10-12, in the evening, with the 12 servers of tasks 005, 009, and
019, odin-http left out and Tina for Odin: Goose at `73dd28c` with Goose `6448f3f`, the
settings below. `REUSE` copied the cells whose binary and settings were unchanged:
tokio's, may-minihttp's, and hyper's, and vanilla-epoll's plaintext, from the morning's
run below, and xitca-web's, zix's, zeemo's, libreactorng's, and vanilla-io_uring's
plaintext at 256 and 1,024 connections and JSON at 256, from
[2026-10-11-uring-matrix](../bench/results/2026-10-11-uring-matrix/summary.md). The rest
ran in this session. Sessions drift by up to 5%: the morning's Goose build served 4%
less in this session than in the morning's ([below](#goose-since-the-morning)). Results,
with latency, CPU, and memory per cell, in
[2026-10-12-matrix](../bench/results/2026-10-12-matrix/summary.md); the tables come from
`bench/table.py`. Requests per second from wrk, medians of 3 runs, and peak RSS over
the row's cells; bold is the column's best.

4 workers on CPUs 0-3:

| Server | plaintext 256 | plaintext 1,024 | plaintext 4,096 | json 256 | json 1,024 | peak RSS |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | 6.74 M | 6.52 M | 6.02 M | 498 K | 487 K | 8.9-15 MB |
| Goose epoll | 5.37 M | 5.31 M | 5.24 M | 416 K | 408 K | **2.7-3.6 MB** |
| vanilla-io_uring (V) | **8.14 M** | **8.25 M** | **7.60 M** | 456 K | 453 K | 37-154 MB |
| libreactorng (C) | 6.96 M | 7.38 M | 7.03 M | 545 K | 609 K | 6.1-80 MB |
| zix (Zig) | 5.13 M | 5.44 M | 4.97 M | **552 K** | **614 K** | 6.7-39 MB |
| vanilla-epoll (V) | 6.10 M | 5.85 M | 5.46 M | (216 K) | (218 K) | 6.0-57 MB, 15 GB in JSON |
| tokio (Rust) | 3.89 M | 3.83 M | 3.65 M | 394 K | 386 K | 12-183 MB |
| may-minihttp (Rust) | 2.39 M | 4.31 M | 3.95 M | 375 K | 364 K | 40-621 MB |
| xitca-web (Rust) | 3.30 M | 3.52 M | 3.21 M | 419 K | 442 K | 25-69 MB |
| hyper (Rust) | 2.69 M | 2.67 M | 2.54 M | 303 K | 295 K | 8.0-88 MB |
| zeemo (Zig) | 2.39 M | 2.69 M | 2.21 M | 540 K | 606 K | 6.6-37 MB |
| Tina (Odin) | 0.73 M | 0.74 M | 0.47 M | 504 K | 446 K | 755 MB |

1 worker on CPU 0:

| Server | plaintext 256 | plaintext 1,024 | plaintext 4,096 | json 256 | json 1,024 | peak RSS |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | 2.10 M | 2.06 M | 1.89 M | **173 K** | **152 K** | 4.0-6.2 MB |
| Goose epoll | 1.84 M | 1.83 M | 1.52 M | 148 K | 121 K | **2.4-3.3 MB** |
| vanilla-io_uring (V) | **2.67 M** | **2.54 M** | **1.89 M** | 148 K | 90 K | 14-75 MB |
| libreactorng (C) | 2.35 M | 2.44 M | 1.31 M | 129 K | 92 K | 5.1-82 MB |
| zix (Zig) | 1.77 M | 1.51 M | 0.99 M | 152 K | 99 K | 3.8-34 MB |
| vanilla-epoll (V) | 1.90 M | 1.91 M | 1.53 M | (71 K) | (61 K) | 5.6-56 MB, 6 GB in JSON |
| tokio (Rust) | 1.38 M | 1.35 M | 1.19 M | 134 K | 116 K | 12-183 MB |
| may-minihttp (Rust) | 1.22 M | 1.30 M | 1.07 M | 123 K | 113 K | 39-619 MB |
| xitca-web (Rust) | 1.10 M | 1.05 M | 0.82 M | 98 K | 83 K | 13-59 MB |
| hyper (Rust) | 0.86 M | 0.69 M | 0.71 M | 85 K | 72 K | 7.5-78 MB |
| zeemo (Zig) | 0.84 M | 0.76 M | 0.55 M | 140 K | 107 K | 3.4-33 MB |
| Tina (Odin) | 0.21 M | 0.20 M | 0.10 M | 128 K | 98 K | 190 MB |

vanilla-epoll's JSON didn't run: it leaks 6-15 GB a cell. Its JSON cells, in
parentheses, are the ones the morning's tables give, with 1 worker from that morning
and with 4 from 2026-10-11 ([below](#the-mornings-seven-servers)).

- vanilla-io_uring leads plaintext in every cell: by 21-27% over Goose's io_uring loop
  with 4 workers, and by 23-27% with 1 worker at 256 and 1,024 connections. At 4,096
  connections with 1 worker the two tie, and vanilla-io_uring counted 1,990 socket
  errors. libreactorng leads Goose's io_uring loop in plaintext with 4 workers, by
  3-17%, and with 1 worker at 256 and 1,024 connections.
- In JSON with 4 workers, zix, zeemo, and libreactorng lead Goose's io_uring loop by
  8-11% at 256 connections and 24-26% at 1,024. With 1 worker, Goose's io_uring loop
  leads JSON at both connection counts.
- Goose's epoll loop trails vanilla-epoll in plaintext with 4 workers by 4-12%, across
  sessions (vanilla-epoll's cells are the morning's); in the morning's session the gap
  was 0-5%.
- Goose's io_uring loop leads every Rust server in every cell, and Tina in every cell
  but JSON at 256 connections with 4 workers: 498K against 504K. Goose's epoll loop has
  the lowest peak RSS in every cell.
- Tina's pipelined plaintext runs at 5-11% of Goose's io_uring rate, and its JSON at
  0.64 to 1.01 times, with 30 to 85 times its memory (task 019).

### Goose since the morning

The evening's Goose builds served 8% less plaintext than the morning's on the epoll loop
and 4.5% less on io_uring. Run side by side on 2026-10-13
([2026-10-13-regress](../bench/results/2026-10-13-regress/summary.md), 4 workers,
plaintext and JSON at 256 connections, 3 runs of 15 s), the morning's `ef09c0f` and the
evening's `73dd28c`:

| Build | plaintext, epoll | plaintext, io_uring | JSON, epoll | JSON, io_uring |
|---|---:|---:|---:|---:|
| `ef09c0f` | 5.61 M | 6.87 M | 420 K | 499 K |
| `73dd28c` | 5.43 M | 6.67 M | 414 K | 504 K |

So about 4% was the session and 3% the code. `bench/count.sh` counts 1,826.9 user
instructions per plaintext request on the evening's epoll build against 1,786.7 on the
morning's, and 1,875.2 against 1,832.1 on io_uring; JSON is unchanged. Counted at each
commit between the two that changed the package or the server, on the epoll loop, the
40 instructions came from:

| Commit | Change | Instructions per request |
|---|---|---:|
| `f306c6f` | Response fields checked for CR, LF, and invalid names | +2.1 |
| `d617b2b` | A cap on a connection's requests, a per-route body limit | +7.2 |
| `7c31b13` | The `DONE` event, for an access log | +7.0 |
| `ea6192d` to `af23e84` | Timers, mailboxes, answers that wait, the eventfd waker | +18.1 |
| `30d4b34` | Files with `sendfile` on the epoll loop | +5.4 |
| `5ca934f` | `Config.max_read` | +1.2 |

`64fec0d` and `551ee19` don't build on their own, so the waiting feature's share isn't
split further. User cycles per request rose from 438-448 to 470-473.

### The morning's seven servers

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

## Static files

`bench/files.sh` on 2026-10-12, Goose at `fcfd80d`: wrk downloads one file over and over
from tmpfs, 96 connections, wrk 4.1.0 on CPUs 4-15 with 12 threads; 1 worker on CPU 0 or
4 on CPUs 0-3; 3 runs of 10 s after 3 s of warm-up, medians
([2026-10-12-files](../bench/results/2026-10-12-files/summary.md), which also has each
cell's spread and CPU). nginx 1.28.3 is Ubuntu's, with `sendfile`, `tcp_nopush`,
`open_file_cache`, and no access log; Caddy 2.10.2 is its release binary with
`file_server`, `GOMAXPROCS` set to the worker count. The rate counts body bytes only. Bold
is the column's best; the emulated ring is Goose's fallback where io_uring is blocked.

| Server | 4 KB, 1 w | 4 KB, 4 w | 64 KB, 1 w | 64 KB, 4 w | 1 MB, 1 w | 1 MB, 4 w |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | **81.6 K/s** | **219 K/s** | 2.08 GB/s | 6.42 GB/s | 10.98 GB/s | 30.39 GB/s |
| Goose epoll | 56.0 K/s | 179 K/s | 2.23 GB/s | 7.41 GB/s | 11.59 GB/s | **31.28 GB/s** |
| Goose, emulated ring | 76.8 K/s | 206 K/s | **2.90 GB/s** | 7.85 GB/s | **12.38 GB/s** | 31.11 GB/s |
| nginx | 50.2 K/s | 173 K/s | 2.31 GB/s | **8.15 GB/s** | 9.93 GB/s | 28.52 GB/s |
| Caddy | 13.0 K/s | 47 K/s | 0.83 GB/s | 2.99 GB/s | 6.80 GB/s | 20.08 GB/s |

Server CPU per request, in µs:

| Server | 4 KB, 1 w | 4 KB, 4 w | 64 KB, 1 w | 64 KB, 4 w | 1 MB, 1 w | 1 MB, 4 w |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | **12.3** | **18.5** | 31.6 | 41.1 | 96.3 | 122 |
| Goose epoll | 18.1 | 22.7 | 29.7 | 35.8 | 91.5 | **106** |
| Goose, emulated ring | 13.2 | 19.7 | **22.8** | 33.8 | **85.7** | 107 |
| nginx | 20.2 | 23.4 | 28.6 | **32.5** | 106.8 | 148 |
| Caddy | 77.7 | 81.0 | 79.9 | 84.1 | 155.9 | 197 |

- Goose copies a file under 64 KB, and sends a larger one with `sendfile` (epoll and the
  emulation) or two splices through a pipe (io_uring). At 4 KB, copying serves 1.3 to
  1.8 times what zero-copy does (task 020).
- nginx wins 64 KB with 4 workers, and with 1 worker against both real loops. The
  splices cost io_uring more than `sendfile` from 32 KB up.
- With 4 workers at 1 MB, wrk used all 120 of its CPU-seconds in Goose's cells, so
  the rates there measure wrk; CPU per request still separates the servers.
- WSL2's kernel costs most of a small file: 12-20 µs a request at 4 KB for Goose and
  nginx, against 5.8 µs for an unpipelined JSON response.

## REST APIs

Task 021's four tiers, run by `bench/rest.sh run` on 2026-10-12: Goose at `73dd28c` with
Goose `6448f3f`, on each loop, against hyper 1.12.0 on Tokio 1.53.2 (`bench/rest/hyper`,
`-C target-cpu=native`). Each server with 4 workers on CPUs 0-3, the load on CPUs 4-15, a
fresh server per cell warmed up for 5 s, 3 rounds of 15 s interleaved.
`bench/rest/check.py` passed against every server on every tier first. Results in
[2026-10-12-rest](../bench/results/2026-10-12-rest/summary.md), which also has every
cell's range, each route's latency, and peak RSS. No run counted a socket error or an
unexpected status.

Tiers A to C at saturation: wrk 4.1.0 with each tier's script, 8 threads, 256
connections. Requests per second, the median of 3 runs, and the server's CPU time per
request:

| Tier, JSON | Goose io_uring | Goose epoll | hyper |
|---|---:|---:|---:|
| A (items, 0.2 KB), serialize | **572K**, 6.9 µs | 441K, 9.1 µs | 271K, 14.8 µs |
| A, template | **588K**, 6.8 µs | 459K, 8.7 µs | 290K, 13.8 µs |
| B (snowtime, 0.3-13 KB), serialize | **269K**, 14.8 µs | 220K, 18.3 µs | 149K, 27.0 µs |
| B, template | **372K**, 10.7 µs | 283K, 14.1 µs | 194K, 20.6 µs |
| C (clinic, up to 728 KB), serialize | **52.5K**, 76 µs | 51.1K, 79 µs | 32.2K, 125 µs |
| C, template | **146K**, 27 µs | 139K, 29 µs | 119K, 33 µs |

- Every run fell within 4% of its cell's median.
- Goose's io_uring loop serves 2.0-2.1 times hyper's rate on tier A, 1.8-1.9 times on
  B, and 1.6 times on C serialized. With templates, which copy prebuilt bytes, C's lead
  shrinks to 1.2 times.
- io_uring leads epoll on every tier: by 28-30% on A, 22-31% on B, and 3-5% on C. Tier
  C's 4-5% loss to epoll in Docker on the Mac (task 021) doesn't appear here.
- Goose uses 2 to 5 times hyper's memory: peak RSS 26-49 MB on A, 87-221 MB on B, and
  129-387 MB on C, against hyper's 13-17, 29-46, and 37-75 MB. Each Goose worker loads
  its own copy of the records, and templates add a copy of their JSON.

Tier D, request bodies of 2 KB to 8 MB (`tier-d.lua`): the uploads role, chunked CSV
imports and multipart attachments, on 1 thread and 32 connections, alone and beside
the forms role, JSON batches and forms, on 7 threads and 224. Requests per second, the
range of 3 runs:

| Server | Uploads alone | p50 | Uploads beside forms | p50 | Forms role | p99 |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | 968-977 | 21-23 ms | **151-152** | 136-137 ms | 6.9-7.1K | **78-79 ms** |
| Goose epoll | 983-998 | 20-24 ms | 115-116 | 157-244 ms | **7.3K** | 87-92 ms |
| hyper | **1,056-1,072** | **15 ms** | 42-73 | 132-148 ms | 4.8-5.0K | 135-172 ms |

- hyper took uploads alone 6-11% faster than either Goose loop, at a lower median
  latency. perf put 19% of Goose's time in the multipart reader's delimiter search,
  the stdlib's `find`, which compares the delimiter at every byte
  ([finding](goose-findings.md#the-stdlibs-find-compares-the-whole-subsequence-at-every-offset)).
  With `http::find_bytes`, which compares only where the delimiter's first byte is, run
  on 2026-10-13 with `STEPS=2`, 3 rounds, before and after in one session
  ([before](../bench/results/2026-10-13-uploads-before/summary.md),
  [after](../bench/results/2026-10-13-uploads-after/summary.md)):

  | Uploads alone, per second | Before | After |
  |---|---:|---:|
  | Goose epoll | 1,003-1,015 | **1,127-1,153** |
  | Goose io_uring | 978-995 | 1,108-1,141 |
  | hyper | 1,107-1,116 | 1,084-1,095 |

  Goose now takes uploads alone 1-6% faster than hyper. Beside the forms role, nothing
  changed beyond the runs' spread. Per upload before the change, Goose ran 43.3 M user
  instructions to hyper's 33.4 M.
- Beside the forms role, Goose takes 1.6 to 3.6 times hyper's uploads and 1.4-1.5 times
  its forms, at 0.5-0.7 times its forms p99.

Tiers A to C at a fixed rate, half the lowest median above: 140K requests per second on
A, 74K on B, and 16K on C, from zrk 2.3.0, one process per route at its share of the
tier's mix (`bench/rest/rate.py`), corrected for coordinated omission. Every server
held every rate. The server's CPU time per request, and each tier's highest route p99
over the 3 runs:

| Tier, JSON | Goose io_uring | Goose epoll | hyper |
|---|---:|---:|---:|
| A, serialize | 17.9-18.3 µs, 0.91 ms | **17.5-18.0 µs, 0.19 ms** | 22.6-23.0 µs, 0.80 ms |
| A, template | 17.9-18.5 µs, 0.71 ms | **17.3-17.9 µs, 0.26 ms** | 22.4 µs, 9.6 ms |
| B, serialize | **28.4-29.3 µs, 0.20 ms** | 29.0-29.8 µs, 0.38 ms | 38.9-39.5 µs, 2.1 ms |
| B, template | 26.7-27.0 µs, 0.19 ms | **26.1-26.9 µs, 0.17 ms** | 35.6-35.7 µs, 0.24 ms |
| C, serialize | 86.8-89.2 µs, 1.6 ms | **86.7-87.1 µs, 0.93 ms** | 141-144 µs, 2.1 ms |
| C, template | 43.3-43.7 µs, 0.39 ms | **42.7-43.2 µs, 0.35 ms** | 54.0-54.4 µs, 0.42 ms |

- At a fixed rate the two Goose loops spend the same CPU per request, 0.6 to 0.8 times
  hyper's. Each request wakes an idle loop: on tier A that costs 1.9 times the epoll
  loop's saturated figure and 2.6 times io_uring's.
- Every route's median stays at 0.09-0.18 ms on every server, except C's 715 KB
  bookings: 0.67 ms on Goose serialized, 1.15 ms on hyper, and 0.25-0.26 ms with
  templates.

The mixed run: a server with `TIER=d` takes tier C's reads at 16K requests per second,
alone and beside the uploads role. Read latency in ms, p50 / p99, the range over the
6 routes and 3 runs:

| Server | Reads alone | Reads beside uploads | Uploads |
|---|---:|---:|---:|
| Goose io_uring | 0.10-0.67 / 0.65-1.0 | 2.6-3.6 / 8.9-17 | 636-650/s |
| Goose epoll | 0.10-0.68 / 0.36-0.94 | **0.32-0.94 / 1.6-2.7** | 627-651/s |
| hyper | 0.12-1.17 / 0.50-38 | 5.9-7.0 / 17-21 | 555-567/s |

- The epoll loop keeps reads beside uploads under 2.7 ms at p99, since it reads at most
  `Config.max_read` (16 KB) from a connection per turn. io_uring's p99 there is 9-17 ms
  and hyper's 17-21 ms.
- hyper's reads alone had p99s of 19-38 ms in one of the 3 rounds, and under 1.5 ms in
  the other two.

## Instructions per request

`bench/instructions.sh`, on 2026-10-12 in the evening, Goose at `47876ad`: one worker on
CPU 0, plaintext pipelined 16 deep at 256 connections, wrk on CPUs 4-15 with 8 threads for
20 s, and `perf stat` on CPU 0 for 10 s from 5 s in, so the counts include the kernel's
network work on that CPU. Three runs per server
([2026-10-12-desktop-instructions](../bench/results/2026-10-12-desktop-instructions/runs.tsv)),
the range of the three, ordered by cycles; bold is the column's best. dusty's row is
from the morning's run
([2026-10-12-full-instructions](../bench/results/2026-10-12-full-instructions/instructions.tsv)),
with the same binary.

| Server | Instructions per request | In user code | Cycles per request | Peak RSS |
|---|---:|---:|---:|---:|
| vanilla-io_uring | **1,702-1,731** | **745-759** | **1,541-1,560** | 14.2 MB |
| libreactorng | 2,266-2,308 | 1,307-1,328 | 1,719-1,746 | 5.3 MB |
| Goose io_uring | 2,533-2,580 | 1,576-1,601 | 1,808-1,819 | 4.9 MB |
| vanilla-epoll | 1,744-1,768 | 756-766 | 1,980-2,010 | 5.5 MB |
| Goose epoll | 2,475-2,530 | 1,535-1,574 | 1,995-2,036 | **2.4 MB** |
| zix | 4,675-4,720 | 3,703-3,736 | 2,331-2,359 | 3.8 MB |
| tokio | 4,353-4,415 | 3,408-3,453 | 2,724-2,736 | 10.0 MB |
| may-minihttp | 2,983-3,005 | 1,945-1,953 | 2,731-2,776 | 65 MB |
| xitca-web | 7,166-7,259 | 6,090-6,168 | 3,881-3,943 | 15.4 MB |
| hyper | 6,136-6,291 | 5,177-5,318 | 4,117-4,326 | 7.2 MB |
| zeemo | 10,111-10,203 | 7,791-7,870 | 4,949-4,970 | 3.4 MB |
| Tina | 19,983-20,260 | 8,230-8,334 | 18,566-18,751 | 190 MB |
| dusty | 20,264-20,293 | 7,990-7,992 | 26,811-27,263 | 8.8 MB |

- Goose's io_uring loop is third by cycles, behind vanilla-io_uring and libreactorng.
  Both answer without parsing the request as Goose does: vanilla runs half of Goose's user
  instructions.
- The io_uring loop runs 40-60 more user instructions per request than the epoll loop,
  and about 200 fewer cycles, as in the morning. The day's work (answers that wait,
  queued sends, files without copying) left the epoll loop's user instructions within
  50 of the morning's 1,494-1,527.
- Tina pipelines poorly: 216-221 K requests per second here, and 20,000 instructions a
  request, about 8 times Goose's (task 019). It holds 190 MB, for 4,096 connection
  slots.

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

From the runs of 2026-10-12 above. Against the full field, the io_uring servers in C,
V, and Zig beat Goose's io_uring loop; against the morning's seven servers, the losses
are the epoll loop's, which is also the HttpArena entry, and memory.

- **Plaintext, to vanilla-io_uring, by 21-27%** in every cell but 4,096 connections with
  1 worker, a tie, and **to libreactorng, by 3-17%**, with 4 workers and with 1 worker
  at 256 and 1,024 connections ([the full field](#the-full-field)). Both answer without
  parsing the request as Goose does, and spend fewer cycles per request
  ([instructions](#instructions-per-request)).
- **JSON with 4 workers, to zix, zeemo, and libreactorng**, by 8-11% at 256 connections
  and 24-26% at 1,024; and to Tina by 1% at 256.
- **3% since the morning's build**, about 40 user instructions per plaintext request
  ([Goose since the morning](#goose-since-the-morning)).

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
- **REST memory**: 2 to 5 times hyper's peak RSS on every tier, since each worker loads
  its own copy of the records.
- **REST reads beside uploads on the io_uring loop**: p99 9-17 ms against the epoll
  loop's 1.6-2.7 ms. The epoll loop bounds its reads per connection turn. The io_uring
  loop takes up to 256 completions per wait, each up to 4 KB of an upload, which would
  fit; not measured yet.

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
