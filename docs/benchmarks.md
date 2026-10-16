# Benchmarks

Where Goose stands now, one section per workload. Each section holds the latest
accepted run and is replaced, not appended to, when a newer one supersedes it. The
[measurement records](results.md) link to the raw runs and retain limitations needed
to interpret them. Superseded analysis can be recovered from git.

## How these are measured

On the benchmark desktop: AMD Ryzen 7 5800X3D, 8 cores, 16 logical CPUs, Windows 11,
WSL2 Ubuntu 26.04.1, gcc 15.2.0 at `-O2`. Every server runs on CPUs 0-3 with the same
worker count as Goose, 4, and the load generators run on CPUs 4-15. Each competitor runs
in its fastest documented configuration, built in release mode. WSL2 carries loopback
through a VM, so the kernel's share of each request is larger than on bare metal.

The method, each load generator, and the servers' pins and builds:
[bench/README.md](../bench/README.md#method).

## Pins

| Workload | Goose server | Goose compiler | Kernel | Date | Command |
|---|---|---|---|---|---|
| Plaintext and JSON, every connection count | `3785950e`, `v0.3.6` | `v2026.2` (`3ee3871`) | 6.18.54.1 | 2026-10-16 | `bench/run.sh` |
| REST saturation rates, uploads, and peak memory, both loops | `3785950e`, `v0.3.6` | `v2026.2` (`3ee3871`) | 6.18.54.1 | 2026-10-16 | goose-rest's `bench/rest.sh run`, steps 1 and 2 |
| REST reads beside uploads at 16,000/s, both loops | `bc75f2a` | `46356c2` | 6.18.54.1 | 2026-10-14 | `bench/rest.sh run`, step 4 |
| REST memory, idle | `1818526` | `46356c2` | 6.18.54.1 | 2026-10-14 | VmRSS 3 s after listening; task 025 |
| Static files | `fcfd80d` | `5c83a5a` | 6.18.40.1 | 2026-10-12 | `bench/files.sh` |
| Compression | `6f584e2`, goose-compress `4bed2d2` | `0bdbd18` | 6.18.54.1 | 2026-10-14 | `bench/httparena.sh run` |

Benchmarks run in overnight batches, so they lag the
[Goose pin](development.md#get-goose).

## Plaintext and JSON

TechEmpower's tiny fixed responses. They measure the loop and the parser, nothing else.
wrk 4.1.0 with 8 threads, plaintext pipelined 16 deep, by connection count, 3 runs of
15 s after 5 s of warm-up, medians. Bold is the column's best. Rows go by average rank
over the columns; peak RSS is the highest of a server's cells.

| Server | plaintext 256 | plaintext 1,024 | plaintext 4,096 | JSON 256 | JSON 1,024 | peak RSS |
|---|---:|---:|---:|---:|---:|---:|
| libreactorng (C)\* | 7.02 M | 7.46 M | 7.01 M | 540 K | 610 K | 72 MB |
| vanilla-io_uring (V)\* | **8.12 M** | **8.26 M** | **7.58 M** | 453 K | 462 K | 155 MB |
| Goose io_uring | 6.73 M | 6.62 M | 6.20 M | 495 K | 491 K | 13 MB |
| zix (Zig) | 5.19 M | 5.37 M | 4.83 M | **561 K** | **614 K** | 39 MB |
| Goose epoll | 5.22 M | 5.18 M | 5.06 M | 402 K | 397 K | **4.9 MB** |
| xitca-web (Rust) | 3.37 M | 3.60 M | 3.22 M | 419 K | 445 K | 69 MB |
| tokio (Rust) | 3.83 M | 3.79 M | 3.63 M | 381 K | 373 K | 163 MB |
| hyper (Rust) | 2.66 M | 2.64 M | 2.53 M | 294 K | 287 K | 81 MB |

\* Answers plaintext without parsing the request.

Goose is `3785950e`, `v0.3.6`, with compiler `v2026.2`, measured on 2026-10-16 in a
session without competitors
([record](results.md#2026-10-16-v036-at-goose-v20262-goose-builds-only)). Competitors
remain the earlier field run on the same machine and kernel, so their gaps to Goose
include session drift of up to 5%. Against the `f875101a` cells this table had before,
whose loops run the same code at compiler `v2026.1`, every Goose cell moved by -2.6% to
+0.6%; io_uring's plaintext fell 2.1-2.6% at every connection count, below or at the
bottom of the earlier runs' ranges.

`bench/count.sh` on `bc75f2a`: 1,836.0 user instructions per plaintext request on
epoll and 1,885.4 on io_uring, one worker, 10 million requests, 3 runs. Against
`e4f7b55` rebuilt at the same compiler pin, epoll costs 2.9 instructions and 3.55%
more user cycles; io_uring saves 3.2 instructions, with overlapping cycle ranges.
`bench/instructions.sh` on `3785950e` at `v2026.2` counts 1,553-1,580 user
instructions per plaintext request on epoll and 1,633-1,650 on io_uring, 1.5% fewer and
1.5% more than `f875101a` at `v2026.1` at the medians with the same loop code, and
1.8% and 3.1% more cycles ([record](results.md#instruction-counts-at-v20262)).

The [main comparison](results.md#2026-10-14-main-against-the-readme-benchmark-build)
records the `bc75f2a` runs and ranges. The
[earlier field run](results.md#2026-10-14-main-after-tasks-02203-025-and-027)
supplies the competitors. zeemo,
vanilla-epoll, may-minihttp, and Tina, the 1-worker table, latency, and CPU per request
are from 2026-10-12, on kernel 6.18.40.1 ([the full field](results.md#the-full-field)).

## REST APIs

Three API workloads and one of uploads, against servers that serve the same routes
without a framework. Responses are computed per request from records loaded at startup,
and checked before each run. At saturation, wrk 4.1.0 uses 8 threads and 256
connections; uploads alone use 1 thread and 32 connections. Each cell has a fresh
server, 5 s of warm-up, and 3 runs of 15 s, medians.

- **A**: HttpArena's `production-stack` API, items of 0.2 KB.
- **B**: a time tracker's hot path, 0.3-13 KB of JSON.
- **C**: a clinic's schedule and records, up to 728 KB.
- **Uploads**: chunked CSVs of 2-8 MB and multipart files up to 1 MB.

### The tiers

The requests, their shares, and the decisions behind them are in task 021
(`tasks/000-archive/021-rest-bench.md`); the scripts are `bench/rest/tier-*.lua`.

<a id="tier-a"></a>
**A**, [HttpArena](https://github.com/MDA2AV/HttpArena)'s `production-stack` API. Every
request carries a bearer token. Reads get one of 10,000 items or the caller's profile;
an eighth of the connections write items with a 51-byte JSON body.

<a id="tier-b"></a>
**B**, a time tracker's hot path, behind a session cookie. The session (about 2 KB of
nested JSON), the running timer, two weeks of entries (about 13 KB), the projects, and
small `PATCH` and `POST` writes.

<a id="tier-c"></a>
**C**, a clinic's schedule and records, behind a 530-byte JWT in a browser-sized head.
Mostly a cheap version poll, then a week's bookings for ten people (700 bookings nested
four deep, up to 728 KB), shifts, one visit with its case's notes
(6-50 KB), and a client's past visits (50-90 KB). "Templates" builds each record's JSON
once at startup and splices in the per-request values.

<a id="uploads"></a>
**Uploads** (tier D): chunked CSV imports of 2-8 MB, multipart attachments up to 1 MB,
JSON batches of a few hundred KB, and form posts, from an eighth of the connections.
Each answer is computed from the whole body, so the checker sees every byte read.
"Reads p99" sends C's reads at a fixed 16,000 a second on the same server while the
uploads run.

"Uploads" is uploads alone. "Reads p99" is tier C's reads at a fixed 16,000 a second
while uploads stream in, the range over the routes and runs. Bold is the column's best;
rows go by average rank.

| Server | A | B | C | C, templates\* | Uploads | Reads p99 |
|---|---:|---:|---:|---:|---:|---:|
| Goose io_uring | **588 K/s** | **311 K/s** | **62.1 K/s** | **147 K/s** | 1,152/s | 8.5-18.0 ms |
| Goose epoll | 429 K/s | 240 K/s | 61.4 K/s | 136 K/s | **1,180/s** | **1.8-2.6 ms** |
| xitca-web (Rust)‡ | 407 K/s | 235 K/s | 38.2 K/s | 113 K/s | 1,016/s | 2.4-4.6 ms |
| dusty (Zig)§ | 353 K/s | 164 K/s | 25.4 K/s | 130 K/s | 1,131/s | 6.7-42 ms |
| hyper (Rust) | 278 K/s | 154 K/s | 33.2 K/s | 124 K/s | 1,128/s | 11-29 ms |
| tokio (Rust)‡ | 393 K/s | 183 K/s | 31.6 K/s | 100 K/s | 1,034/s | 1.1-5.8 s† |

Goose's A to C rates and uploads come from a session on 2026-10-16
([record](results.md#rest-tiers-a-to-d-at-v20262)), Goose at `3785950e`, `v0.3.6`,
with compiler `v2026.2`. dusty's and hyper's come from the
[morning's session](results.md#rest-tiers-a-to-d) on the same machine and kernel,
beside Goose at `v0.3.4`. "Reads p99" is from the earlier runs at 16,000 a second,
Goose's at `bc75f2a`; the 2026-10-16 sessions offered the reads at 1,700 a second.  
‡ From the earlier field run on the same machine and kernel; sessions have drifted by up
to 5%.

\* Each record's JSON is prebuilt at startup, with the per-request values spliced in.  
† The server fell behind the fixed rate, so the reads queued.  
§ A framework, not a direct competitor: its peer is
[goose-rest](https://github.com/kaitk/goose-rest), the REST framework built on this
package.

Peak RSS at saturation, in MB, the highest peak over each cell's three runs.
Both Goose loops, dusty, and hyper are from the 2026-10-16 sessions above, on the
machine and with the load settings above. xitca-web and tokio retain the earlier field
run on the same machine and kernel. Bold is the column's lowest among these recorded
runs.

| Server | A | B | C | C, templates | Uploads |
|---|---:|---:|---:|---:|---:|
| Goose io_uring | 12.5 MB | 30.2 MB | 70.5 MB | **57.6 MB** | 70.7 MB |
| Goose epoll | **7.5 MB** | **28.8 MB** | 69.0 MB | 57.7 MB | 69.1 MB |
| xitca-web (Rust) | 32 MB | 68 MB | 490 MB | 512 MB | 56 MB |
| dusty (Zig)§ | 16 MB | 42 MB | 216 MB | 242 MB | **31 MB** |
| hyper (Rust) | 13 MB | 29 MB | **37 MB** | 74 MB | 76 MB |
| tokio (Rust) | 16 MB | 30 MB | 307 MB | 365 MB | 412 MB |

Workers receive their records over queues, and prebuilt JSON is held once per
process in the store. Every saturation cell's peak is lower beyond the
baseline's ranges. The
[measurement record](results.md#2026-10-14-main-against-the-readme-benchmark-build)
contains both loops' rates, memory, uploads, and latency. `bc75f2a` lost 2.7-5.8% of
its serialized B and C rates to the
[placement of std's JSON string scan](results.md#2026-10-14-the-serialized-rest-loss-is-a-loops-placement);
`b03a446` [scans with `find_any`](results.md#2026-10-14-rest-strings-scanned-16-bytes-at-a-time)
instead, 11-23% faster than `bc75f2a`.

Idle with the records loaded, by worker count: Goose on the epoll loop at `1818526`
(2026-10-14, VmRSS 3 s after it listened,
[idle.tsv](../bench/results/2026-10-14-rest-idle-main/idle.tsv)), and hyper with 4
workers on 2026-10-13 ([idle-rss.txt](../bench/results/2026-10-13-rest/idle-rss.txt)),
whose memory stays flat with workers: 23 MB on tier C at 1, 2, and 4.

| Tier | Goose, 1 worker | Goose, 4 workers | Each added worker | hyper, 4 workers |
|---|---:|---:|---:|---:|
| A | 4.1 MB | 6.4 MB | +0.8 MB | 7.5 MB |
| B | 7.7 MB | 20 MB | +4.1 MB | 17 MB |
| C | 14 MB | 44 MB | +10 MB | 24 MB |
| C, templates | 21 MB | 27 MB | +1.9 MB | 62 MB |

Goose copies the records into each worker, where the other servers share one copy;
the templates' JSON is shared through the store. With
one worker Goose holds less than hyper on every tier; each added worker adds a copy of
the records.

The [main comparison](results.md#2026-10-14-main-against-the-readme-benchmark-build)
records both loops' rates and ranges, uploads beside forms, and every route's
latency in the linked summaries. Competitors come from the earlier field run
([measurement record](results.md#2026-10-14-main-after-tasks-02203-025-and-027) and
[summary](../bench/results/2026-10-14-rest-field/summary.md)). may-minihttp, Tina, and
odin-http are from 2026-10-13, on kernel 6.18.40.1 ([REST APIs](results.md#rest-apis-1)).

## Static files

One file downloaded over and over, against nginx and Caddy, the usual static file
servers. Files on tmpfs. 1 worker on CPU 0 or 4 on CPUs 0-3, wrk on 4-15 with 12 threads
and 96 connections, 3 runs of 10 s, medians. Bold is the column's best.

| Server | 4 KB, 1 worker | 4 KB, 4 | 64 KB, 1 | 64 KB, 4 | 1 MB, 1 | 1 MB, 4 |
|---|---:|---:|---:|---:|---:|---:|
| Goose epoll | 56.0 K/s | 179 K/s | 2.23 GB/s | 7.41 GB/s | **11.6 GB/s** | **31.3 GB/s** |
| Goose io_uring | **81.6 K/s** | **219 K/s** | 2.08 GB/s | 6.42 GB/s | 11.0 GB/s | 30.4 GB/s |
| nginx 1.28.3 | 50.2 K/s | 173 K/s | **2.31 GB/s** | **8.15 GB/s** | 9.9 GB/s | 28.5 GB/s |
| Caddy 2.10.2 (Go) | 13.0 K/s | 47 K/s | 0.83 GB/s | 2.99 GB/s | 6.8 GB/s | 20.1 GB/s |

1 MB with 4 workers is wrk's limit, not the servers'. CPU per request, in-memory
responses, and Windows: [results](results.md#static-files). A Goose-only run at
`3785950e` with compiler `v2026.2` on 2026-10-16 had wrk on 8 threads and 64
connections, and stopped at the client's limit of 21.9-22.3 GB/s at 1 MB with 4
workers; it doesn't replace this table. In that run the emulated ring, the loop Goose
falls back to where io_uring isn't available, leads epoll with 1 worker by 30% at 64 KB
and 18% at 1 MB ([record](results.md#static-files-at-v20262)).

## Compression

HttpArena's json-comp profile: JSON responses gzipped per request when the client asks.
HttpArena `0720ee5`, gcannon `11c802b` with 4 threads on CPUs 4-15, each server in its
HttpArena entry's Docker image on CPUs 0-3, 3 runs of 5 s at each connection count. The
harness keeps each cell's best run. Goose compresses at gzip level 1, nginx's default.

| Server | 4,096 connections | Bytes per response | Memory | 16,384 connections | Memory |
|---|---:|---:|---:|---:|---:|
| goose | 66.1 K/s | 1,477 | 51-52 MiB | 64.2 K/s | 147 MiB |
| actix | 62.6 K/s | 1,733 | 129-141 MiB | 61.0 K/s | 368-441 MiB |
| dusty | 43.0 K/s | 1,303 | 28-200 MiB | 42.0 K/s | 235 MiB-1.1 GiB |
| vanilla-epoll\* | 404.8 K/s | 1,635 | 111-115 MiB | 204.4 K/s | 250-293 MiB |

\* Caches each response's gzipped bytes, so its cell measures a cache, not compression.

Goose is the fastest of the servers that compress each response. HttpArena scores
json-comp by rate times the square of the smallest bytes per response over a server's
own; dusty's gzip writes 12% fewer bytes, which scores Goose at 51.5 K, still above
actix's 35.4 K and dusty's 43.0 K. Compressing costs Goose about 24 µs of CPU per
response. The measurements, the gzip levels compared, and the logs:
[task 022.03](../tasks/022-compression/03-http-compress.md).

## Other platforms

- **Linux in Docker, M1 Pro** (2026-10-11, Goose `9623c6a`): Goose leads every cell
  against tokio, may-minihttp, hyper, and xitca-web; plaintext 6.96 M/s at 256
  connections against tokio's 6.10 M ([results](results.md#m1-pro-linux-in-docker)).
- **macOS native, M1 Pro** (2026-10-11): every server within 5% of Goose, because macOS's
  loopback limits the round trips; Goose holds 1.9 MB against 7-194 MB
  ([results](results.md#m1-pro-macos-native)).
- **Windows, IOCP** (2026-10-12): 2 to 2.7 times slower than io_uring on WSL2 on the
  same machine, with oha on plaintext (task 017); not benchmarked further.

## Where Goose loses

From the runs in this file:

- **Plaintext**, to vanilla-io_uring by 17-20% and to libreactorng by 4-12%. Both answer
  without parsing the request.
- **JSON**, to zix by 12-20% and to libreactorng by 8-20%, on the io_uring loop. The
  epoll loop also trails xitca-web, by 4-11%. These gaps span sessions.
- **Goose `v2026.2` against `v2026.1`**, the same loop code: io_uring's plaintext fell
  2.1-2.6%, below or at the bottom of the earlier ranges, and its user instructions per
  plaintext request rose 1.5% and cycles 3.1% at the medians; epoll's cycles rose 1.8%
  ([record](results.md#plaintext-and-json-at-v20262)). The same epoll code has counted
  1,538-1,586 user instructions per request across runs, a spread whose cause isn't
  measured ([record](results.md#instruction-counts-at-v20262)).
- **REST memory**: the Goose io_uring loop holds 70.5 MB on tier C serialized against
  hyper's 37 MB in the same session. The templated path holds 57.6 MB, below hyper's
  74 MB. Records still cost a copy per worker (task 025).
- **REST reads beside uploads on the io_uring loop**: p99 8.5-18.0 ms against the epoll
  loop's 1.8-2.6 ms and xitca-web's earlier 2.4-4.6 ms.
- **Uploads beside the forms role** (tier D), to tokio: 252-279 uploads a second in the
  field run against the io_uring loop's 175-178 at `3785950e` (2026-10-16), though Goose
  served the forms at 7.7-7.8 K/s against tokio's 3.7-3.9 K/s
  ([summary](../bench/results/2026-10-14-rest-field/summary.md#tier-d)).
- **REST reads beside uploads at 1,700 a second**, at `3785950e`: the io_uring loop's
  p99 is 4.95-7.92 ms against epoll's 0.39-1.34 ms, so the gap above isn't only the
  16,000/s rate's ([record](results.md#rest-tiers-a-to-d-at-v20262)).
- **Since `e4f7b55`**, at `bc75f2a`: io_uring uploads beside fixed-rate reads lose
  5.80%, and read-only CPU cost rises on both loops; neither was rerun at `b03a446`,
  whose faster serialization should cut the reads' cost. Epoll adds 2.9 user
  instructions and 3.55% user cycles per plaintext request; one-worker io_uring
  plaintext RSS rises by 0.10 MB. Epoll's history reads alone add 0.026 ms median p99.
  The [record](results.md#2026-10-14-main-against-the-readme-benchmark-build) includes
  every loss and range. The serialized B/C loss it records is gone at `b03a446`.
- **Static files of 64 KB**, to nginx: by 3-9% on the epoll loop and 10-21% on io_uring.
- **Windows**, where IOCP serves well under io_uring's rate (above).

Other HttpArena profiles and their measurement limits:
[measurement records](results.md#httparenas-profiles).
