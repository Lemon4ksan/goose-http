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

## 2026-10-14: v0.3.1, Goose builds only

goose-rest's `bench/all.sh` measured the Goose servers alone on the desktop, machine
name Tiamat, in session `2026-10-14T2039`. The server is `de19e3b`, whose code is
that of `v0.3.1` (`faead67`). The compiler is built from Goose `bc3c1f1`, which
`env.txt` records as `46356c2`: the two commits differ only by a logo image. Kernel
6.18.54.1-microsoft-standard-WSL2, gcc 15.2.0 at `-O2`. No competitor ran, so every
comparison with one below uses the
[2026-10-14 field run](#2026-10-14-main-after-tasks-02203-025-and-027) on the same
machine and kernel, and sessions have drifted by up to 5%. The session failed before
goose-rest's tiers F, R, and M on a checker bug; those ran on 2026-10-15 from the
same binaries. The session's [steps](../bench/results/2026-10-14T2039-Tiamat/session-steps.txt),
[environment](../bench/results/2026-10-14T2039-Tiamat/session-env.txt), and
[last log lines](../bench/results/2026-10-14T2039-Tiamat/session-tail.txt) are kept.

### Plaintext and JSON at every connection count

```sh
SERVERS="goose goose-uring" bench/run.sh
```

1 worker on CPU 0 or 4 on CPUs 0-3; wrk 4.1.0 with 8 threads on CPUs 4-15; plaintext
pipelined 16 deep at 256, 1,024, and 4,096 connections, JSON at 256 and 1,024; 3
interleaved runs of 15 s after 5 s of warm-up, medians. 4 workers, from the
[summary](../bench/results/2026-10-14T2039-Tiamat/summary.md), against the Goose cells
in [benchmarks.md](benchmarks.md#plaintext-and-json) before this run (`bc75f2a` at
256 connections, `e4f7b55` at the others):

| Loop | Test | Conns | Before | `de19e3b` | Change |
|---|---|---:|---:|---:|---:|
| io_uring | plaintext | 256 | 6.37 M | 6.84 M (6.76-6.90) | +7.4% |
| io_uring | plaintext | 1,024 | 6.81 M | 6.64 M (6.54-6.85) | -2.4% |
| io_uring | plaintext | 4,096 | 6.38 M | 6.30 M (6.25-6.40) | -1.2% |
| io_uring | JSON | 256 | 481 K | 512 K (504-517) | +6.4% |
| io_uring | JSON | 1,024 | 489 K | 508 K (500-512) | +3.9% |
| epoll | plaintext | 256 | 4.87 M | 5.41 M (5.34-5.47) | +11.1% |
| epoll | plaintext | 1,024 | 5.36 M | 5.39 M (5.35-5.39) | +0.5% |
| epoll | plaintext | 4,096 | 5.26 M | 5.19 M (5.18-5.20) | -1.3% |
| epoll | JSON | 256 | 375 K | 402 K (397-407) | +7.2% |
| epoll | JSON | 1,024 | 401 K | 395 K (395-397) | -1.5% |

The losses are within the 5% drift between sessions. The gains at 256 connections
are larger than that drift, but this run has no same-session baseline, so it doesn't
show whether the code or the session caused them. Peak RSS is 3.9-4.8 MB on epoll
and 10.1-16.1 MB on io_uring with 4 workers; 16.1 MB, at 4,096 connections, is the
new highest Goose peak, where the earlier matrix had 13 MB. Every cell had zero
errors.

### Instruction counts

```sh
bench/instructions.sh goose goose-uring
```

As in [Instructions per request](#instructions-per-request): one worker on CPU 0,
plaintext pipelined 16 deep at 256 connections, wrk with 8 threads on CPUs 4-15 for
20 s, perf on CPU 0 for 10 s from 5 s in, 3 runs, kernel work included
([counts](../bench/results/2026-10-14T2039-rest-Tiamat-frm/instructions.txt)). Against
2026-10-12's `47876ad` on kernel 6.18.40.1:

| Loop | Instructions/req | User instructions/req | Cycles/req | Peak RSS |
|---|---:|---:|---:|---:|
| epoll, `47876ad` | 2,475-2,530 | 1,535-1,574 | 1,995-2,036 | 2.4 MB |
| epoll, `de19e3b` | 2,460-2,474 | 1,529-1,538 | 2,100-2,124 | 3.3-3.4 MB |
| io_uring, `47876ad` | 2,533-2,580 | 1,576-1,601 | 1,808-1,819 | 4.8-4.9 MB |
| io_uring, `de19e3b` | 2,545-2,571 | 1,582-1,600 | 1,819-1,834 | 5.7-5.8 MB |

Instructions are unchanged. Epoll spends about 4% more cycles per request, and both
loops hold about 1 MB more at their peak; the kernels differ, so neither is pinned on
the code.

### Static files without nginx and Caddy

```sh
SERVERS="goose goose-uring goose-uring-epoll" bench/files.sh
```

`bench/files.sh`'s defaults have changed since the 2026-10-12 run in
[benchmarks.md](benchmarks.md#static-files): wrk ran with 8 threads and 64
connections, not 12 and 96, on CPUs 4-15; 3 runs of 10 s after 3 s of warm-up,
medians; nginx and Caddy didn't run
([summary](../bench/results/2026-10-14T2039-Tiamat-files/summary.md)).

| Server | 4 KB, 1 worker | 4 KB, 4 | 64 KB, 1 | 64 KB, 4 | 1 MB, 1 | 1 MB, 4 |
|---|---:|---:|---:|---:|---:|---:|
| Goose epoll | 52.6 K/s | 190 K/s | 2.11 GB/s | 7.92 GB/s | 10.6 GB/s | 21.9 GB/s |
| Goose io_uring | 82.2 K/s | 233 K/s | 2.02 GB/s | 6.84 GB/s | 10.4 GB/s | 21.5 GB/s |
| Goose, emulated ring | 72.7 K/s | 213 K/s | 2.71 GB/s | 8.35 GB/s | 11.2 GB/s | 21.8 GB/s |

At 1 MB with 4 workers wrk used 80.2 s of CPU in each 10 s run, all of its 8
threads, so the three servers' 21.5-21.9 GB/s is the client's limit, against 31.3
GB/s with 12 threads on 2026-10-12. Below that the numbers stand on their own: io_uring
leads at 4 KB and loses to epoll at 64 KB and 1 MB, and the emulated ring leads at
64 KB and 1 MB. These cells don't replace the table in benchmarks.md, whose run
had nginx and Caddy beside Goose under the same load.

### REST tiers A to D

```sh
SERVERS="goose-uring goose-epoll goose-uring-rest goose-epoll-rest" \
    RATE_A=100000 RATE_B=24000 RATE_C=1700 bench/rest.sh run   # from goose-rest
```

goose-rest's `bench/rest.sh run` wraps this repository's: 4 workers on CPUs 0-3,
saturation with wrk 4.1.0, 8 threads and 256 connections on CPUs 4-15, uploads
alone with 1 thread and 32 connections, 3 interleaved runs of 15 s after 5 s of
warm-up with a fresh server per cell, each server checked first
([summary](../bench/results/2026-10-14T2039-rest-Tiamat/summary.md)). Goose's medians,
serialized, against `b03a446`'s in [benchmarks.md](benchmarks.md#rest-apis):

| Loop | A | B | C | C, templates | Uploads alone |
|---|---:|---:|---:|---:|---:|
| io_uring, `b03a446` / `bc75f2a` | 577 K/s | 308 K/s | 60.3 K/s | 144 K/s | 1,080/s |
| io_uring, `de19e3b` | 598 K/s | 315 K/s | 62.4 K/s | 147 K/s | 1,120/s |
| epoll, `b03a446` / `bc75f2a` | 427 K/s | 238 K/s | 58.9 K/s | 135 K/s | 1,076/s |
| epoll, `de19e3b` | 444 K/s | 244 K/s | 60.9 K/s | 137 K/s | 1,128/s |

Every rate is 1.4-4.8% higher, within session drift. Peak RSS matches the earlier
run's to within 1 MB in every saturation cell. Tier D beside forms: io_uring 153-182
uploads a second against 149-159 before, with forms at 7.1-7.2 K/s; epoll 117-120
uploads a second.

Step 4 offered tier C's reads at 1,700 a second, not at the 16,000 of the "Reads p99"
column in benchmarks.md, so its p99 doesn't replace that column. At 1,700 a second
the io_uring loop's reads still suffer beside uploads: p99 4.8-7.5 ms against epoll's
0.40-1.35 ms, and 0.14-0.96 ms on both loops alone. Every fixed-rate cell reached its
rate with zero errors.

goose-rest's results from the same sessions are in its task 010.

## 2026-10-14: REST strings scanned 16 bytes at a time

`b03a446` has the REST server look for a string's JSON escapes with std's `find_any`,
which the runtime runs over 16 bytes at a time, and call `json::format_string` only
for a string that has one. Serialized B and C gain 11-23%, beyond the ranges, on both
loops; A, the templated tiers, and peak RSS don't change. It replaces the byte loop
whose placement cost `bc75f2a` its serialized rates
([below](#2026-10-14-the-serialized-rest-loss-is-a-loops-placement)).

Same machine and kernel as below; both builds `goose build --cc gcc --standalone` at
Goose `46356c2`, `cm` from `git archive bc75f2a` and `cs` from the working tree that
became `b03a446` (env.txt's "8f0308e (modified)"); the checker passed on every tier,
both JSON modes, and both loops.

```sh
OUT=... SERVERS="goose-uring-cm goose-uring-cs" STEPS=1 bench/rest.sh run
OUT=... SERVERS="goose-epoll-cm goose-epoll-cs" STEPS=1 bench/rest.sh run
```

4 workers on CPUs 0-3, wrk 4.1.0 with 8 threads and 256 connections on CPUs 4-15,
three interleaved runs of 15 s after 5 s of warm-up, medians and ranges, req/s, from
the [io_uring](../bench/results/2026-10-14-rest-scan/uring/summary.md) and
[epoll](../bench/results/2026-10-14-rest-scan/epoll/summary.md) summaries:

| Loop | Tier | `bc75f2a` | `b03a446` | Change | CPU µs/req |
|---|---|---:|---:|---:|---:|
| io_uring | B serialize | 268.9 K (258.8-271.3) | 308.3 K (306.2-310.2) | +14.7% | 14.9 → 13.0 |
| io_uring | C serialize | 48.9 K (45.7-49.2) | 60.3 K (60.1-60.5) | +23.3% | 81.7 → 66.3 |
| epoll | B serialize | 214.1 K (199.3-215.0) | 237.8 K (231.8-237.9) | +11.1% | 18.7 → 16.9 |
| epoll | C serialize | 48.3 K (44.6-48.6) | 58.9 K (58.7-59.3) | +21.9% | 83.0 → 68.1 |

p99 at saturation falls from 1.47 to 1.22 ms on io_uring B, 11.7 to 9.03 ms on C,
1.80 to 1.52 ms on epoll B, and 10.5 to 8.57 ms on C. Every other cell's range
overlaps. Counted as in the section below, user instructions per request fall from
57.1-57.2 K to 40.2-40.8 K on B and from 751-763 K to 522-525 K on C, against
`e4f7b55`'s 56.8-57.0 K and 752-754 K
([counts](../bench/results/2026-10-14-rest-033/counts.tsv), build `cs`). Uploads and
reads beside them were not rerun; they keep `bc75f2a`'s numbers.

## 2026-10-14: the serialized REST loss is a loop's placement

The serialized B/C loss of `bc75f2a` against `e4f7b55`
([below](#2026-10-14-main-against-the-readme-benchmark-build)) is the placement of
std's `json_format_string` byte scan, about a third of tier C's user cycles. In
`e4f7b55` the loop's 36 bytes lie within one 64-byte line; the package's later code
moves it 32 bytes, across a line, in every later build measured. The same
instructions then take 4-7% more cycles. No API change, data-loading change, or
`mallopt` setting costs a measurable rate. [Task 033](../tasks/000-archive/033-rest-regressions.md)
records the decision; scripts and raw output are in
[2026-10-14-rest-033](../bench/results/2026-10-14-rest-033/).

Same machine and kernel as below; every REST build is `goose build --cc gcc
--standalone` at Goose `46356c2` from `git archive` of its revision, 4 workers on
CPUs 0-3, io_uring, wrk 4.1.0 with 8 threads and 256 connections on CPUs 4-15.
The REST binary is the same on both loops, so epoll was not rerun.

**Bisect.** `STEPS=1 bench/rest.sh run`, three interleaved runs of 15 s after 5 s of
warm-up, along main's first parents ([summary](../bench/results/2026-10-14-rest-033/bisect-summary.md)).
Medians and ranges, req/s, and peak RSS:

| Build | B serialize | C serialize | Peak RSS B / C, MB |
|---|---:|---:|---:|
| `e4f7b55` | 275.6 K (275.4-275.9) | 51.1 K (50.7-51.4) | 47 / 105 |
| `a1c6e8d`, API work merged | 271.9 K (270.7-276.6) | 49.7 K (48.9-49.8) | 50 / 104 |
| `afb4a40`, workarounds dropped | 270.7 K (268.6-271.0) | 49.6 K (49.5-49.8) | 51 / 104 |
| `71ef2c0`, queue hand-off | 270.4 K (270.0-272.1) | 49.7 K (48.7-49.8) | 30 / 70 |
| `bc75f2a`, shared store | 271.3 K (268.7-272.7) | 49.2 K (48.9-49.5) | 30 / 70 |

The whole loss falls on the first step, and the memory reductions on the later ones.
Templated cells and tier A overlap across all five builds. A separate run of
`bc75f2a` without its `mallopt(M_MMAP_THRESHOLD, 131072)`, or with the threshold
raised to 32 MB after loading, served B at 265.9 K and 265.7 K against 265.9 K and C
at 48.0 K and 48.4 K against 48.5 K ([summary](../bench/results/2026-10-14-rest-033/mallopt-summary.md)).

**Counts.** `count.sh` runs each server, warms it for 5 s, and counts its user
instructions and cycles with `perf stat` over 10 s of a 14 s wrk run, three
interleaved runs ([counts](../bench/results/2026-10-14-rest-033/counts.tsv)).
Against `e4f7b55`, `a1c6e8d` runs 56.7-56.9 K against 56.7-56.9 K instructions per
B request and 749-754 K against 749-753 K per C request, but 25.2-25.4 K against
24.3-24.5 K cycles on B and 259-266 K against 248-249 K on C. Branch, L1, and TLB
misses per request match ([events](../bench/results/2026-10-14-rest-033/events.txt)).
`perf record` puts about 32% of tier C's user cycles in the scan loop; the
[disassembly](../bench/results/2026-10-14-rest-033/loops.txt) shows it at offset 0 of
a 64-byte line in `e4f7b55` and offset 32 in `a1c6e8d`, `71ef2c0`, and `bc75f2a`.

**Check.** `bc75f2a` built through a `gcc` wrapper that adds `-falign-loops=64`
places the loop at offset 16, within one line. Counted as above, later in the
session, when every rate ran lower: B 264.8-268.8 K req/s against `e4f7b55`'s
261.6-273.0 K and `bc75f2a`'s 254.5-264.4 K; C 48.0-48.5 K against 48.0-48.5 K and
46.2-46.6 K, at 257-259 K cycles against 258-260 K and 273-276 K. It is not adopted:
task 033 says why.

## 2026-10-14: main against the README benchmark build

Main at `bc75f2a` has overlapping plaintext and JSON throughput ranges with the
baseline, but costs more user cycles on epoll and loses serialized REST throughput.
REST memory is substantially lower. Both `bc75f2a` (`m`) and the README's previous
benchmark build, `e4f7b55` (`x`), were rebuilt with Goose `46356c2`; this compares the
server revisions at one compiler pin, rather than comparing two compiler versions.
The later documentation commit `02f28c9` changes no measured code.

AMD Ryzen 7 5800X3D, Windows 11, WSL2 Ubuntu 26.04.1, kernel
6.18.54.1-microsoft-standard-WSL2, gcc 15.2.0 at `-O2`. The machine was kept quiet:
only README/documentation editing continued, with no other benchmarks or taxing
work. The initial process check found no `wrk`, `zrk`, `h2load`, or `rest-goose`.

Each build came from `git archive <rev> | tar -x -C /root/bconf/<tag>`, not the
working tree. `LOOP=epoll scripts/build.sh` and `LOOP=uring scripts/build.sh` built
the small-response servers; `$GOOSE build --cc gcc --standalone -o
build/rest/rest-goose-c<tag> <dir>/bench/rest/goose/rest.goose` built REST. The
existing REST datasets and competitors were retained; `bench/rest.sh build` was
not rerun. The batch removed `/root/bconf` when it ended. Commands and full revision
IDs are in the [batch](../bench/results/2026-10-14-rest-main/batch.sh) and
[revision record](../bench/results/2026-10-14-rest-main/revs.txt).

### Instructions and cycles

```sh
RUNS=3 bench/count.sh goose-c{x,m} goose-c{x,m}-uring
```

One worker on CPU 0; h2load 1.68.0 on CPUs 4-15, 8 threads, 256 connections,
16 requests in flight per connection, exactly 10 million plaintext requests per
sample. `perf stat` counts the server process's user instructions and user cycles.
Medians of three runs, with minimum and maximum in parentheses, from
[counts](../bench/results/2026-10-14-desktop-main-count/runs.tsv) and
[environment](../bench/results/2026-10-14-desktop-main-count/env.txt):

| Loop | x instructions/req | m instructions/req | x cycles/req | m cycles/req |
|---|---:|---:|---:|---:|
| epoll | 1,833.1 (1,833.1-1,833.1) | 1,836.0 (1,836.0-1,836.0) | 492.6 (489.4-498.1) | 510.1 (503.3-515.7) |
| io_uring | 1,888.6 (1,888.5-1,888.6) | 1,885.4 (1,885.4-1,885.4) | 454.8 (434.8-461.8) | 445.0 (436.5-453.0) |

Epoll loses 2.9 instructions per request and 3.55% median user cycles, beyond
both ranges. io_uring saves 3.2 instructions; its cycle ranges overlap.

### Plaintext and JSON

```sh
OUT=bench/results/2026-10-14-desktop-main-run \
    SERVERS="goose-cx goose-cm goose-cx-uring goose-cm-uring" \
    TESTS="plaintext:256 json:256" LATENCY=0 bench/run.sh
```

One worker on CPU 0 or four on CPUs 0-3; wrk 4.1.0 with 8 threads on CPUs 4-15,
256 connections, TechEmpower headers, plaintext pipelined 16 deep and JSON without
pipelining. Three interleaved runs of 15 s per cell after 5 s of warm-up; a fresh
server per cell. Latency was not measured. Medians and ranges, requests per second,
from the [summary](../bench/results/2026-10-14-desktop-main-run/summary.md):

| Loop | Workers | Test | x req/s | m req/s | Median change |
|---|---:|---|---:|---:|---:|
| epoll | 1 | plaintext | 1.521 M (1.513-1.527 M) | 1.500 M (1.489-1.550 M) | -1.37% |
| epoll | 1 | JSON | 120.9 K (119.5-123.9 K) | 118.8 K (116.6-121.2 K) | -1.74% |
| io_uring | 1 | plaintext | 1.803 M (1.800-1.809 M) | 1.821 M (1.761-1.841 M) | +1.04% |
| io_uring | 1 | JSON | 145.2 K (144.1-145.9 K) | 144.2 K (143.0-149.3 K) | -0.64% |
| epoll | 4 | plaintext | 4.862 M (4.343-4.992 M) | 4.873 M (4.788-4.894 M) | +0.21% |
| epoll | 4 | JSON | 383.0 K (382.1-387.6 K) | 374.8 K (368.1-385.4 K) | -2.14% |
| io_uring | 4 | plaintext | 6.427 M (6.346-6.451 M) | 6.370 M (6.327-6.402 M) | -0.89% |
| io_uring | 4 | JSON | 472.2 K (471.2-476.5 K) | 481.0 K (480.8-481.6 K) | +1.87% |

Every throughput loss has overlapping ranges. Four-worker io_uring JSON improves
beyond the ranges. All 48 samples have zero socket errors and non-2xx responses.
The harness logged wall-clock steps in 25 samples; wrk uses the monotonic-clock
preload, and [clock logs](../bench/results/2026-10-14-desktop-main-run/) are retained.
One-worker io_uring plaintext peak RSS rises from 5.74 MB (5.66-5.75) to 5.84 MB
(5.77-5.85), a 1.77% median increase with separate ranges. Other small-response RSS
ranges overlap. MB follows the harness's convention, KiB divided by 1,024.

### REST APIs

```sh
OUT=bench/results/2026-10-14-rest-main \
    SERVERS="goose-uring-cx goose-uring-cm" \
    STEPS="1 2 4" RATE_C=16000 bench/rest.sh run
OUT=bench/results/2026-10-14-rest-main-epoll \
    SERVERS="goose-epoll-cx goose-epoll-cm" \
    STEPS="1 2 4" RATE_C=16000 bench/rest.sh run
```

Four workers on CPUs 0-3; the load on CPUs 4-15. Saturation uses wrk 4.1.0,
8 threads and 256 connections. Uploads alone use 1 thread and 32 connections;
beside forms, forms use 7 threads and 224 connections. Three interleaved runs of
15 s after 5 s of warm-up, with a fresh server per cell. Both revisions passed
the checker on A to D and both JSON modes, on both loops. The io_uring batch ran
first, then the [epoll extension](../bench/results/2026-10-14-rest-main-epoll/batch.sh)
used the same archived REST binaries. Each directory's `revs.txt` names the builds;
the working tree's concurrent documentation edits do not enter those binaries.

Requests per second at saturation, medians with run ranges in parentheses, from
the [io_uring summary](../bench/results/2026-10-14-rest-main/summary.md) and
[epoll summary](../bench/results/2026-10-14-rest-main-epoll/summary.md). Serialized
responses are built per request; templates prebuild each record's JSON at startup
and splice in request-specific values.

| Loop | Tier | JSON | x req/s | m req/s | Median change |
|---|---|---|---:|---:|---:|
| io_uring | A | serialize | 564.0 K (556.2-568.8 K) | 562.4 K (556.6-562.4 K) | -0.30% |
| io_uring | A | template | 576.8 K (561.9-579.9 K) | 577.6 K (573.3-579.7 K) | +0.13% |
| io_uring | B | serialize | 271.2 K (271.1-273.1 K) | 264.0 K (262.9-264.5 K) | -2.68% |
| io_uring | B | template | 356.4 K (355.1-357.5 K) | 365.6 K (359.7-366.4 K) | +2.58% |
| io_uring | C | serialize | 49.8 K (49.2-49.9 K) | 48.1 K (47.5-48.3 K) | -3.29% |
| io_uring | C | template | 140.3 K (139.9-140.4 K) | 140.1 K (138.9-140.6 K) | -0.13% |
| epoll | A | serialize | 412.1 K (407.0-421.0 K) | 415.9 K (413.8-416.5 K) | +0.91% |
| epoll | A | template | 430.5 K (425.0-436.5 K) | 432.8 K (428.0-432.9 K) | +0.53% |
| epoll | B | serialize | 212.5 K (212.1-214.3 K) | 200.1 K (196.5-208.8 K) | -5.84% |
| epoll | B | template | 270.8 K (268.9-275.5 K) | 274.6 K (273.1-277.0 K) | +1.42% |
| epoll | C | serialize | 47.7 K (47.3-49.1 K) | 45.6 K (44.7-47.1 K) | -4.40% |
| epoll | C | template | 128.2 K (128.0-131.4 K) | 129.0 K (124.5-131.2 K) | +0.66% |

Serialized B and C lose beyond the run ranges on both loops. B templated gains
beyond the ranges on io_uring; every other saturation rate has overlapping ranges.
There are no saturation errors. These are server-revision comparisons: the
earlier competitor measurements are retained, not rerun. Even the baseline runs
slower than its earlier field-run medians, so gaps to those competitors include
session drift.

Peak RSS per run at saturation, MB, medians with ranges. The current benchmark
table uses each cell's highest peak instead of its median.

| Loop | Tier | JSON | x peak RSS MB | m peak RSS MB |
|---|---|---|---:|---:|
| io_uring | A | serialize | 14.99 (14.98-15.04) | 12.38 (12.37-12.39) |
| io_uring | A | template | 22.57 (22.57-22.66) | 11.50 (11.45-11.52) |
| io_uring | B | serialize | 46.74 (46.63-51.90) | 30.12 (30.04-30.18) |
| io_uring | B | template | 152.76 (152.61-153.53) | 50.05 (50.03-50.21) |
| io_uring | C | serialize | 103.53 (102.40-104.79) | 70.41 (70.31-70.50) |
| io_uring | C | template | 175.95 (175.18-176.12) | 57.59 (57.53-57.62) |
| epoll | A | serialize | 9.25 (8.90-9.88) | 7.41 (7.29-7.46) |
| epoll | A | template | 18.15 (16.38-18.28) | 8.29 (8.11-8.29) |
| epoll | B | serialize | 45.93 (45.42-46.34) | 28.55 (28.53-28.57) |
| epoll | B | template | 151.75 (151.68-151.91) | 50.02 (50.02-50.11) |
| epoll | C | serialize | 102.53 (101.29-102.90) | 68.97 (68.67-68.98) |
| epoll | C | template | 175.80 (174.70-175.93) | 57.69 (57.53-57.73) |

Every REST saturation cell has lower peak RSS beyond the ranges. Workers receive
their loaded records over queues, and prebuilt JSON is held once per process in
the shared store. The rate losses come from neither: the
[follow-up](#2026-10-14-the-serialized-rest-loss-is-a-loops-placement) traces them to
the placement of one hot loop.

The serialized B/C losses also appear in CPU time and latency at saturation.
CPU is the server's total user and kernel time per request; latency is wrk's,
measured at saturation, not the fixed-rate read test. Medians and run ranges:

| Loop | Tier | x CPU us/req | m CPU us/req | x p50 ms | m p50 ms | x p99 ms | m p99 ms |
|---|---|---:|---:|---:|---:|---:|---:|
| io_uring | B | 14.74 (14.64-14.75) | 15.15 (15.12-15.21) | 0.92 (0.91-0.92) | 0.94 (0.94-0.94) | 1.43 (1.43-1.44) | 1.52 (1.48-1.56) |
| io_uring | C | 80.39 (80.09-81.27) | 83.11 (82.83-84.15) | 4.99 (4.97-5.03) | 5.18 (5.16-5.21) | 10.89 (10.85-11.19) | 11.42 (11.33-11.44) |
| epoll | B | 18.86 (18.70-18.90) | 20.04 (19.21-20.41) | 1.21 (1.20-1.21) | 1.26 (1.21-1.27) | 1.71 (1.69-1.73) | 1.96 (1.79-2.16) |
| epoll | C | 84.17 (81.67-84.72) | 88.07 (85.11-89.80) | 5.18 (4.97-5.22) | 5.32 (5.23-5.51) | 10.29 (10.06-10.64) | 11.25 (10.65-11.85) |

CPU per request rises beyond the ranges by 2.82%/3.38% on io_uring B/C and
6.24%/4.63% on epoll B/C. Their p99 rises beyond the ranges by 6.29%/4.87% and
14.62%/9.33%, respectively. p50 also rises beyond the ranges except on epoll B.
No other saturation CPU or latency metric loses beyond the ranges.

### Uploads and reads beside uploads

The REST commands above include step 2's uploads alone and beside forms. Medians
with ranges; RSS is the peak per run, in MB:

| Loop | Load | x uploads/s | m uploads/s | x forms req/s | m forms req/s | x peak RSS MB | m peak RSS MB |
|---|---|---:|---:|---:|---:|---:|---:|
| io_uring | uploads alone | 1,095 (1,086-1,114) | 1,080 (1,065-1,089) | | | 103.77 (103.59-103.94) | 70.34 (70.24-70.46) |
| io_uring | beside forms | 154 (150-157) | 154 (149-159) | 6,851 (6,808-6,903) | 6,957 (6,808-7,008) | 162.93 (162.31-163.56) | 124.52 (124.44-125.84) |
| epoll | uploads alone | 1,088 (1,064-1,089) | 1,076 (1,059-1,085) | | | 102.18 (102.01-102.71) | 68.92 (68.80-68.99) |
| epoll | beside forms | 111 (109-114) | 112 (110-114) | 6,987 (6,912-7,124) | 7,147 (7,035-7,166) | 172.14 (171.08-173.09) | 131.73 (130.69-132.44) |

Uploads alone lose 1.40% on io_uring and 1.06% on epoll, within overlapping
ranges. Upload and forms rates beside each other overlap, as do their latency
ranges except epoll forms p99, which improves. Peak RSS is lower beyond the ranges
for both upload roles on both loops.

Step 4 offers tier C's reads at 16,000/s through zrk 2.3.0, split over six routes,
alone and beside uploads. Each route has one zrk process, pinned to CPUs 4-15;
the tier-C allocation uses 254 connections and 11 threads across those processes
(integer shares of the harness's 256-connection and 12-thread budgets, with a
minimum of 8 connections and 1 thread per route). Beside reads, wrk uses 1 thread
and 32 upload connections. Both builds reach the offered rate with zero errors.
Medians with ranges, from three 15 s runs after 5 s of warm-up:

| Loop | Reads | x CPU us/req | m CPU us/req | x uploads/s | m uploads/s | x peak RSS MB | m peak RSS MB |
|---|---|---:|---:|---:|---:|---:|---:|
| io_uring | alone | 93.47 (92.78-94.40) | 95.94 (95.50-96.19) | | | 103.95 (103.73-103.98) | 70.26 (70.10-70.51) |
| io_uring | beside uploads | 250.39 (250.31-251.07) | 251.13 (251.12-251.52) | 681 (670-704) | 642 (625-663) | 103.89 (103.32-104.12) | 70.42 (70.38-70.53) |
| epoll | alone | 92.15 (91.94-92.84) | 95.09 (94.88-95.29) | | | 102.55 (101.94-102.61) | 68.80 (68.79-69.09) |
| epoll | beside uploads | 252.47 (251.39-252.82) | 252.85 (252.62-253.24) | 668 (626-676) | 654 (649-680) | 102.63 (102.41-102.72) | 68.80 (68.66-68.88) |

Read-only CPU cost rises beyond the ranges by 2.65% on io_uring and 3.19% on
epoll. io_uring uploads beside reads lose 5.80% beyond the ranges; epoll loses
2.02%, within overlapping ranges. Mixed CPU cost includes both reads and uploads,
divided by read requests, so it is not the CPU cost of a read alone. Its increase
is 0.30% on io_uring, beyond narrowly separate ranges, and 0.15% on epoll, within
the ranges.

Read p99 beside uploads ranges over all routes and runs from 9.22-16.44 ms at x
to 8.47-17.96 ms at m on io_uring, and from 1.60-4.11 ms to 1.80-2.62 ms on
epoll. Every route's individual ranges overlap. Reads alone also overlap except
epoll's history route: median p99 rises from 0.790 ms (0.786-0.811) to 0.816 ms
(0.815-0.914), 3.29%, with narrowly separate ranges. Its 0.026 ms median loss is
recorded rather than treated as a broad latency regression. Epoll's shifts route
improves beyond the ranges. All route-level results remain in the two summaries.

The results do not meet the original expectation that every REST rate remain
within run spread. The measured losses are accepted for the current summary
(2026-10-14); no code was fixed or reverted. Task 033 attributed them to a hot
loop's placement, not to an API change.

Release validation after measurement (2026-10-14): `GOOSE=<Linux compiler>
scripts/test.sh` passes in WSL Ubuntu, including io_uring, its epoll fallback,
epoll, echo, and the examples. `GOOSE=<Windows compiler> nice -n 19
scripts/test.sh` passes in Git Bash, including IOCP, echo, and the examples.
Both compilers are built from Goose `46356c2`; no measured code changed between
the archived main build and validation. The full logs are retained as
[Linux validation](../bench/results/2026-10-14-rest-main/validation-linux.log) and
[Windows validation](../bench/results/2026-10-14-rest-main/validation-windows.log).

## 2026-10-14: main after tasks 022.03, 025, and 027

The field run uses server `e4f7b55` and Goose `0bdbd18`, before the final worker-load
and shared-store merges. Its raw throughput tables remain in the linked summaries;
the current [benchmarks](benchmarks.md) name the later Goose builds separately.

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
