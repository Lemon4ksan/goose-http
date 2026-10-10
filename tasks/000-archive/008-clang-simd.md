# 008: Clang and simd functions

Status: done

Move the Goose pin to upstream (`aardappel/goose`), which adds `simd fn` (spec §7.12) and
`stdlib/base64.goose` as a model of its use, and build the server with clang. The C
backend honors `simd` only under clang on x86-64. The Rust servers in `bench/` build with
`-C target-cpu=native`; `simd` lets the Goose server use AVX2 where the CPU has it,
without tying the binary to one CPU.

The plan assumed clang builds faster code than gcc. Goose's own benchmarks compare clang
with MSVC, not gcc (`bench/results.md` in the Goose checkout), and here gcc won. Neither
clang nor `simd` made the server faster, so the server stays on gcc, and `parse` scans
header values with `std`'s `find_any` instead of a vectorized block.

## Acceptance criteria

- [x] `../goose` follows upstream, the pin is moved ("Move the pin" in
      `docs/development.md`), and `scripts/test-http.sh` and the unit tests pass at it
- [x] clang's version is in `docs/development.md`, and gcc and clang builds were compared;
      `scripts/build.sh` stays on gcc, which won (below), and `CC=clang` builds with clang
- [x] The header value scan is faster, with every per-byte access still proven in bounds
      (`--bce-lines`); `parse` isn't a `simd fn`, which made it slower (below)
- [x] Instructions per request (`perf stat`) and requests per second at 1 and 4 workers
      are recorded for gcc and clang, with and without `simd`, with how they were
      measured
- [x] What the compiler handles badly is in `docs/goose-findings.md`

## Results

Measured on 2026-10-10 on task 004's machine: AMD Ryzen 7 5800X3D, WSL2 kernel
6.18.40.1-microsoft-standard-WSL2, Ubuntu 26.04.1 LTS. Goose `bab8b6f`, gcc 15.2.0,
clang 21.1.8.

### The pin

`aardappel/goose` and the fork `kaitk/goose` were both at `bab8b6f`, 96 commits past the
old pin `3536810`. The unit tests, `scripts/test-http.sh`, and `scripts/test-echo.sh`
passed there, and `scripts/test-http.sh` also against a clang build. One case of the bounds-check finding is fixed at
`bab8b6f`: a call inlined into a loop condition no longer costs the loop's checks.

### The benchmark's request

wrk dropped `-H Host:tfb-server` and `-H Connection:keep-alive`, written without a space
after the colon, in every run since task 004 (`docs/development.md`). Its requests had
`Host: 127.0.0.1:29280` and `Accept` only. `bench/run.sh` and `bench/instructions.sh` now
send all three fields, which a trace of the server's `recvfrom` confirmed. A first run of
this task's matrix with the short request ranked the builds the same way; it was
discarded. wrk's request counts are right: over 5 s they were within 0.8% of the
responses the server sent (counted from its `sendto` calls under strace).

### The parser alone

`bench/parse.sh` parses one request 10 M times with `src/http.goose`: wrk's (170 bytes),
the same without its `Connection` field, and a Chrome navigation request with a 1 KB
cookie (1.9 KB). Each value scan below was tried as a variant of `parse`; all passed
`src/test_http.goose`. Instructions per parse in user code, under gcc `-O2` unless
noted:

| Value scan | wrk's | without `Connection` | Chrome's |
|---|---:|---:|---:|
| Eight bytes as a word, SWAR test (task 004) | 1,521 | 953 | 8,566 |
| A 16-byte block reduced to its first end byte | 1,382 | 841 | 7,573 |
| The same, 32 bytes | 1,356 | 810 | 6,977 |
| The same, 64 bytes | 2,103 | 1,371 | 12,905 |
| A 32-byte bit mask and `ctz`, as httparse does | 2,462 | 1,698 | 18,964 |
| `find_any` | **1,270** | **749** | **6,143** |
| `find_any`, gcc `-march=native` | 1,242 | 728 | 5,938 |
| `find_any`, clang `-O2` | 1,383 | 860 | 7,590 |
| The 32-byte block, clang `-O2` | 1,321 | 826 | 8,032 |
| The 32-byte block, clang with `simd` (AVX2) | 1,532 | 850 | 7,035 |

gcc didn't vectorize the 64-byte block at `-O2`; clang's 16-byte block took 2,561 and
23,125. In time, best of 5 runs on one CPU, one variant at a time:

| Value scan, build | wrk's | without `Connection` | Chrome's |
|---|---:|---:|---:|
| Word scan, gcc | 69.6 ns | 42.9 ns | 409 ns |
| 32-byte block, gcc | 63.0 ns | 36.0 ns | 336 ns |
| 32-byte block, clang | 76.4 ns | 52.7 ns | 620 ns |
| `find_any`, gcc | **59.5 ns** | **33.7 ns** | **278 ns** |
| `find_any`, gcc `-march=native` | 57.4 ns | 32.1 ns | 265 ns |
| `find_any`, clang | 56.8 ns | 35.3 ns | 315 ns |
| `find_any`, clang with `simd` | 70.6 ns | 38.3 ns | 317 ns |

`find_any` searches 16 bytes at a time with SSE2 and stops at the first match, as
picohttpparser's SSE4.2 path and httparse's AVX2 path do, so short values cost one
block. The reduced block always reduces all 32 bytes, and Goose has no way to write
httparse's movemask (`docs/goose-findings.md`).

### The server

Instructions per request: `bench/instructions.sh`, one worker on CPU 0, plaintext
pipelined 16 deep at 256 connections, `perf stat -C 0` for 10 s from 5 s in, divided by
wrk's rate times 10 s; median of 3 runs. Requests per second: `bench/run.sh` with
`TESTS=plaintext:256 LATENCY=0`, wrk medians of 3 runs of 15 s, servers on CPUs 0–3 and
wrk on 4–15, the spread in brackets. The word-scan builds are of `d4a9f8a`, the others of
the tree committed with this file. `bench/compilers.sh` built them.

| Build | Instructions/req | In user code | 1 worker | 4 workers | Peak RSS | Binary |
|---|---:|---:|---:|---:|---:|---:|
| Word scan, gcc | 2,686 | 1,681 | 1.711 M (1.687–1.715) | 4.879 M (4.823–4.944) | 6.1 MB | 50.8 KB |
| Word scan, clang | 2,963 | 1,964 | | | | 58.7 KB |
| Word scan, gcc `-march=native` | 2,731 | 1,724 | | | | 50.8 KB |
| `find_any`, gcc | **2,505** | **1,506** | **1.781 M (1.749–1.782)** | **5.079 M (4.861–5.095)** | 6.1 MB | 55.1 KB |
| `find_any`, clang | 2,713 | 1,706 | | | | 62.9 KB |
| `find_any`, gcc `-march=native` | 2,488 | 1,485 | 1.743 M (1.737–1.765) | 5.034 M (4.927–5.052) | 6.1 MB | 55.1 KB |

```sh
bench/compilers.sh                                      # and SUFFIX=-swar on d4a9f8a
bench/instructions.sh goose-gcc-swar goose-clang-swar goose-gcc-native-swar \
    goose-gcc goose-clang goose-gcc-native
SERVERS="goose-gcc-swar goose-gcc goose-gcc-native" TESTS=plaintext:256 LATENCY=0 \
    OUT=bench/results/2026-10-10-compilers bench/run.sh
```

The raw results are in `bench/results/2026-10-10-compilers/`; its `env.txt` says
`d4a9f8a (modified)`, the tree of this file's commit. `find_any` under gcc serves 4% more
requests than the word scan at both worker counts, with 175 fewer user instructions per
request (10%). At 1 worker the spreads don't overlap; at 4 they do. clang spends about
200 more user instructions per request with either scan. `-march=native` saves 17
instructions per request and showed no difference in requests per second, so the build
stays portable. Memory is the same; the binary grows by the runtime's search.

In an earlier, unfinished run with the full request, may-minihttp spent 3,015 to 3,028
instructions per request, against 2,494 to 2,534 for the 32-byte block under gcc.

### Where `parse` spends now

`perf annotate` of `find_any` under gcc on wrk's request: `find_any` and its set-up about
18%, the method, target, and name loops about 14%, `eq_fold` about 10%, the comma scan
of `Connection`'s value 3%, and the rest spread thin. The `Connection: keep-alive` field
costs about 520 instructions of the 1,270 (the second column above): its name passes
three `eq_fold`s, and its value is split on commas, trimmed, and folded twice, a byte at
a time. That is the next target in the parser.
