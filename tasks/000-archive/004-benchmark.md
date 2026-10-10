# 004: Benchmark against Rust and Odin

Status: done

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

- [x] The competitors' sources and build commands in `bench/`, pinned to exact versions
- [x] `bench/run.sh` runs the whole matrix and writes raw results to `bench/results/`
- [x] A results table in this file, with the machine, kernel, compiler versions, and
      commands
- [x] Where Goose loses, a profile (`perf`) saying where its time goes
- [x] Fixes from that profile applied to the server, the matrix rerun, and before and
      after recorded
- [x] Goose findings from this task in `docs/goose-findings.md`

## Results

Measured on 2026-10-10 under WSL2. Bare-metal Linux wasn't available, so there is no
bare-metal run, and no number here estimates one.

| | |
|---|---|
| Machine | AMD Ryzen 7 5800X3D, 8 cores, 16 logical CPUs; 15 GB for WSL2; Windows 11 Pro 10.0.26200 |
| Kernel | 6.18.40.1-microsoft-standard-WSL2, Ubuntu 26.04.1 LTS |
| Compilers | gcc 15.2.0 (`goose -O2`, then `cc -O2`), rustc 1.99.0, Odin dev-2026-10-nightly:84bc3fc |
| Goose | `3536810` |
| Load generators | wrk 4.1.0 (Ubuntu's `4.1.0-4build3`), h2load 1.68.0 |
| CPUs | servers on 0–3 (1 worker: CPU 0; 4 workers: cores 0 and 1 with both SMT threads); wrk and h2load on 4–15, 8 threads |
| Counts | 4 servers × 2 worker counts × 5 tests × 3 runs: 120 cells per matrix; per cell a 5 s wrk warm-up, 15 s of wrk, and 15 s of h2load after a 2 s warm-up |

Both matrices ran in WSL with `GOOSE` and `~/.cargo/bin` on `PATH`:

```sh
bench/build.sh
OUT=bench/results/2026-10-10-before bench/run.sh   # server at a144f5e
OUT=bench/results/2026-10-10-after bench/run.sh    # server at 6f9b6e1
```

The `after` run's `env.txt` says `6f9b6e1 (modified)`: the uncommitted changes were this
file and `docs/goose-findings.md`. Each measured wrk run is, for plaintext:

```sh
LD_PRELOAD=build/bench/wrk-monotonic.so taskset -c 4-15 wrk -t 8 -c CONNS --timeout 8 \
    -H Host:tfb-server -H Connection:keep-alive -H "Accept: ..." -d 15 --latency \
    -s scripts/pipeline.lua http://127.0.0.1:29280/plaintext -- 16
```

and for JSON the same without the script, at `/json`. `bench/README.md` has the h2load
command's role, where each column comes from, and the deviations each competitor needed.

wrk dropped the `Host` and `Connection` headers written this way, without a space after
the colon (found in task 008). Every request in these runs was `GET`, wrk's
`Host: 127.0.0.1:29280`, and the `Accept` field, the same for every server; TechEmpower's
`Connection: keep-alive` was missing. Task 008's runs send all three.

### After the fix

Medians of 3 runs, from `bench/results/2026-10-10-after/summary.md`. Requests per second
are wrk's; the spread is the lowest and highest run; "vs Goose" is the server's median
divided by Goose's. Latency is h2load's, at h2load's own rate (in `summary.md`); at 4
workers h2load tops out near 3.5 million requests per second, below wrk, so the plaintext
latencies there are at a lower load than wrk's numbers. Peak RSS is the highest of the 3
runs; server CPU is the median over the 15 s wrk run.

| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs Goose | p50 (h2load) | p99 (h2load) | Peak RSS | Server CPU | wrk errors |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| plaintext | 256 | 1 | goose | 1.531 M | 1.485–1.568 M | 1.00 | 3.12 ms | 4.22 ms | 6.2 MB | 15.1 s | 0 |
| plaintext | 256 | 1 | may-minihttp | 1.435 M | 1.385–1.447 M | 0.94 | 3.32 ms | 4.40 ms | 76.6 MB | 15.2 s | 0 |
| plaintext | 256 | 1 | hyper | 0.906 M | 0.881–0.914 M | 0.59 | 4.96 ms | 6.19 ms | 7.9 MB | 15.2 s | 0 |
| plaintext | 256 | 1 | odin-http | 0.114 M | 0.113–0.115 M | 0.07 | 39.39 ms | 50.46 ms | 5.6 MB | 14.8 s | 0 |
| plaintext | 256 | 4 | goose | 4.588 M | 4.533–4.631 M | 1.00 | 1.20 ms | 1.48 ms | 7.2 MB | 60.5 s | 0 |
| plaintext | 256 | 4 | may-minihttp | 4.346 M | 4.309–4.389 M | 0.95 | 1.21 ms | 1.49 ms | 78.7 MB | 60.5 s | 0 |
| plaintext | 256 | 4 | hyper | 2.850 M | 2.831–2.851 M | 0.62 | 1.29 ms | 2.94 ms | 9.6 MB | 60.5 s | 0 |
| plaintext | 256 | 4 | odin-http | 0.334 M | 0.332–0.347 M | 0.07 | 12.39 ms | 16.26 ms | 6.2 MB | 60.2 s | 0 |
| plaintext | 1,024 | 1 | goose | 1.560 M | 1.548–1.566 M | 1.00 | 12.54 ms | 16.34 ms | 18.2 MB | 15.1 s | 0 |
| plaintext | 1,024 | 1 | may-minihttp | 1.408 M | 1.393–1.425 M | 0.90 | 13.42 ms | 16.30 ms | 178.9 MB | 15.1 s | 0 |
| plaintext | 1,024 | 1 | hyper | 0.741 M | 0.728–0.748 M | 0.48 | 4.69 ms | 175.00 ms | 22.0 MB | 15.1 s | 0 |
| plaintext | 1,024 | 1 | odin-http | 0.108 M | 0.106–0.109 M | 0.07 | 173.10 ms | 221.30 ms | 13.1 MB | 14.1 s | 0 |
| plaintext | 1,024 | 4 | goose | 4.542 M | 4.484–4.561 M | 1.00 | 4.78 ms | 5.47 ms | 19.7 MB | 60.5 s | 0 |
| plaintext | 1,024 | 4 | may-minihttp | 4.300 M | 4.294–4.305 M | 0.95 | 4.86 ms | 5.37 ms | 178.7 MB | 60.5 s | 0 |
| plaintext | 1,024 | 4 | hyper | 2.810 M | 2.770–2.816 M | 0.62 | 4.61 ms | 17.12 ms | 26.3 MB | 60.5 s | 0 |
| plaintext | 1,024 | 4 | odin-http | 0.367 M | 0.336–0.367 M | 0.08 | 47.67 ms | 62.34 ms | 15.5 MB | 59.2 s | 1 |
| plaintext | 4,096 | 1 | goose | 1.424 M | 1.413–1.436 M | 1.00 | 47.51 ms | 57.09 ms | 66.4 MB | 15.0 s | 0 |
| plaintext | 4,096 | 1 | may-minihttp | 1.220 M | 1.201–1.237 M | 0.86 | 53.47 ms | 62.49 ms | 590.9 MB | 15.1 s | 0 |
| plaintext | 4,096 | 1 | hyper | 0.758 M | 0.733–0.767 M | 0.53 | 4.60 ms | 777.30 ms | 77.8 MB | 15.1 s | 0 |
| plaintext | 4,096 | 1 | odin-http | 0.068 M | 0.067–0.069 M | 0.05 | 639.90 ms | 6497.10 ms | 43.7 MB | 13.5 s | 1575 |
| plaintext | 4,096 | 4 | goose | 4.349 M | 4.129–4.367 M | 1.00 | 18.93 ms | 20.49 ms | 68.4 MB | 60.1 s | 0 |
| plaintext | 4,096 | 4 | may-minihttp | 3.941 M | 3.798–3.980 M | 0.91 | 19.11 ms | 23.85 ms | 576.0 MB | 60.2 s | 0 |
| plaintext | 4,096 | 4 | hyper | 2.690 M | 2.627–2.702 M | 0.62 | 5.14 ms | 97.73 ms | 87.9 MB | 60.1 s | 0 |
| plaintext | 4,096 | 4 | odin-http | 0.297 M | 0.285–0.303 M | 0.07 | 197.10 ms | 258.30 ms | 44.8 MB | 53.7 s | 1 |
| json | 256 | 1 | goose | 0.125 M | 0.125–0.129 M | 1.00 | 2.19 ms | 2.66 ms | 6.2 MB | 15.0 s | 0 |
| json | 256 | 1 | may-minihttp | 0.121 M | 0.120–0.127 M | 0.97 | 2.28 ms | 3.07 ms | 38.6 MB | 15.1 s | 0 |
| json | 256 | 1 | hyper | 0.086 M | 0.085–0.087 M | 0.68 | 2.85 ms | 3.48 ms | 7.5 MB | 15.0 s | 0 |
| json | 256 | 1 | odin-http | 0.084 M | 0.079–0.087 M | 0.67 | 2.06 ms | 4.95 ms | 5.6 MB | 14.9 s | 0 |
| json | 256 | 4 | goose | 0.383 M | 0.373–0.389 M | 1.00 | 0.59 ms | 0.88 ms | 7.1 MB | 60.1 s | 0 |
| json | 256 | 4 | may-minihttp | 0.365 M | 0.354–0.374 M | 0.95 | 0.64 ms | 0.82 ms | 41.4 MB | 60.1 s | 0 |
| json | 256 | 4 | hyper | 0.304 M | 0.303–0.305 M | 0.79 | 0.76 ms | 1.64 ms | 8.2 MB | 60.0 s | 0 |
| json | 256 | 4 | odin-http | 0.291 M | 0.268–0.298 M | 0.76 | 0.87 ms | 2.26 ms | 6.2 MB | 59.9 s | 0 |
| json | 1,024 | 1 | goose | 0.111 M | 0.105–0.111 M | 1.00 | 8.62 ms | 10.12 ms | 18.2 MB | 15.0 s | 0 |
| json | 1,024 | 1 | may-minihttp | 0.115 M | 0.098–0.118 M | 1.04 | 9.13 ms | 10.87 ms | 120.9 MB | 15.0 s | 0 |
| json | 1,024 | 1 | hyper | 0.072 M | 0.072–0.072 M | 0.65 | 2.79 ms | 171.50 ms | 20.8 MB | 15.0 s | 0 |
| json | 1,024 | 1 | odin-http | 0.072 M | 0.071–0.074 M | 0.65 | 9.71 ms | 22.61 ms | 13.3 MB | 13.6 s | 0 |
| json | 1,024 | 4 | goose | 0.380 M | 0.380–0.381 M | 1.00 | 2.49 ms | 3.20 ms | 19.6 MB | 60.0 s | 0 |
| json | 1,024 | 4 | may-minihttp | 0.359 M | 0.358–0.363 M | 0.94 | 2.65 ms | 3.18 ms | 122.8 MB | 60.0 s | 0 |
| json | 1,024 | 4 | hyper | 0.297 M | 0.275–0.302 M | 0.78 | 2.12 ms | 12.06 ms | 22.7 MB | 60.0 s | 0 |
| json | 1,024 | 4 | odin-http | 0.300 M | 0.279–0.309 M | 0.79 | 2.91 ms | 7.67 ms | 15.5 MB | 59.2 s | 1 |

Goose has the highest median in 19 of 20 cells. It loses JSON at 1,024 connections and 1
worker to may-minihttp, 0.111 M to 0.115 M, with overlapping spreads (0.105–0.111 M and
0.098–0.118 M); in the `before` run, with the same JSON path, Goose had 0.115 M there.
Goose leads may-minihttp by 6 to 17% in plaintext and by 3 to 6% elsewhere in JSON, and
holds 6 to 12 times less memory: may-minihttp gives every coroutine its own stack.

hyper's p50 is lower than Goose's at 1,024 connections and above, because it serves some
connections much less often than others: its p99 is 175 ms at 1,024 connections and 777
ms at 4,096, with 1 worker. odin-http sends each pipelined response with its own `send`
and reaches 5 to 8% of Goose's plaintext rate; with 4,096 connections and 1 worker,
1,575 of its requests timed out in wrk over the 3 runs, and its p99 was 6.5 s.

Between the two matrices the competitors' medians moved by up to 4% (may-minihttp,
plaintext, 256 connections, 1 worker: 1.378 M, then 1.435 M), which bounds what a
difference between the two sessions can show.

### Before and after

Both from the matrices above, wrk medians of 3 runs.

| Test | Conns | Workers | Goose before | Goose after | Change | may-minihttp before | may-minihttp after | Goose ÷ may-minihttp before | after |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| plaintext | 256 | 1 | 1.343 M | 1.531 M | +14% | 1.378 M | 1.435 M | 0.97 | 1.07 |
| plaintext | 256 | 4 | 4.066 M | 4.588 M | +13% | 4.329 M | 4.346 M | 0.94 | 1.06 |
| plaintext | 1,024 | 1 | 1.421 M | 1.560 M | +10% | 1.402 M | 1.408 M | 1.01 | 1.11 |
| plaintext | 1,024 | 4 | 4.036 M | 4.542 M | +13% | 4.279 M | 4.300 M | 0.94 | 1.06 |
| plaintext | 4,096 | 1 | 1.320 M | 1.424 M | +8% | 1.213 M | 1.220 M | 1.09 | 1.17 |
| plaintext | 4,096 | 4 | 3.937 M | 4.349 M | +10% | 3.878 M | 3.941 M | 1.02 | 1.10 |
| json | 256 | 1 | 0.122 M | 0.125 M | +2% | 0.117 M | 0.121 M | 1.04 | 1.03 |
| json | 256 | 4 | 0.377 M | 0.383 M | +2% | 0.364 M | 0.365 M | 1.04 | 1.05 |
| json | 1,024 | 1 | 0.115 M | 0.111 M | −3% | 0.114 M | 0.115 M | 1.01 | 0.97 |
| json | 1,024 | 4 | 0.373 M | 0.380 M | +2% | 0.361 M | 0.359 M | 1.03 | 1.06 |

Before the fix, Goose lost plaintext to may-minihttp by 3 to 6% at 256 connections and at
1,024 with 4 workers, and led by 1 to 9% in the other plaintext cells. JSON doesn't change much: its cost is the system calls of
one request per read.

### Profile

`perf` 7.0.14 works under WSL2 with hardware counters (`docs/development.md`). One worker on
CPU 0, plaintext with 256 connections and TechEmpower's headers under the same wrk command
for 25 s; `perf record -e cycles -F 4999 -g` for 10 s, then `perf stat` for 5 s, from 5 s
in. Instructions per request are `perf stat`'s instructions over wrk's rate times 5 s.

| | Instructions per request | Cycles in user code | Of which the server's own | Kernel |
|---|---:|---:|---:|---:|
| Goose before | 3,608 | 32.3% | 24.4% | 67.7% |
| may-minihttp | 2,885 | 31.5% | 19.0% | 68.5% |
| Goose after | 2,894 | 26.8% | 18.3% | 73.2% |

"Cycles in user code" includes libc. With 4 workers, `perf stat -C 0-3` over 10 s of the
same load gave 3,568 instructions per request for Goose before (3.86 M requests per
second), 2,827 for may-minihttp (4.09 M), and 2,947 for Goose after (4.17 M), counting
everything on those CPUs.

The two servers made the same system calls per request (two `recvfrom` and one `sendto`
per 16 pipelined requests, about one `epoll_wait` per 250 batches), so Goose lost on the
about 720 extra instructions per request in user code. Almost all of them were in `serve`
(17.6% of cycles), into which the parser is inlined: header values were scanned a byte at
a time, `is_tchar` was a chain of comparisons, and the checks on `buf[pos]` in the method
and name loops stayed, because their loop condition called `is_tchar`.

### Fix

In `src/http.goose`, commit `6f9b6e1`:

- Header values are scanned 8 bytes at a time: the 8 bytes are assembled into a `u64`,
  which gcc compiles to one load, and a SWAR test finds a control byte or DEL in it.
- `is_tchar` tests a 128-bit mask, and is called from the loop body, not the condition,
  so the analysis keeps `buf[pos]` proven.
- The loop guard is spelled `pos < buf.len - 7` rather than `pos + 8 <= buf.len`, the form
  the analysis reads.

Index checks elided in the server build went from 35 of 50 to 43 of 58 (`goose -O2`'s
`bce:` line; the new code adds 8).

`scripts/test-http.sh` and the unit tests passed after each change; `test_values` in
`src/test_http.goose` checks the 8-byte scan at every alignment and position for the bytes
on either side of each boundary.

What's left in Goose's user code is mostly response building (`http_start` and
`http_finish`, about 5% of cycles together). Writing the whole plaintext response once a
second would cut it, but changes the decision that responses are literals around the date
and the length, so it isn't done here.

### Findings

In `docs/goose-findings.md`:

- One unproven change to an index costs every bounds check on it: the range analysis is
  flow-insensitive over the function, a loop condition holding an inlined call adds no
  facts, and `pos + 8 <= len` isn't read where `pos < len - 7` is.
- The stdlib has no fast byte search and no word loads.
