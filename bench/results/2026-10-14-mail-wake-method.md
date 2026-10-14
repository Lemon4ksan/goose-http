# Mailbox keys through WAKE (2026-10-14)

Task 027, item 12: validate the correctness fix that keeps a waiting exchange's
mailbox key live through `WAKE`, and measure its request-path cost against the live-key
implementation before that fix. The full Linux and Windows suites pass at
`d29ac5fcb68bbdf2dcddc613dea1bc955da9bc1e`, whose implementation is the fix in
`8ab362c`. No further fix or release is needed.

## Machine and builds

Ryzen 7 5800X3D, 8 cores and 16 hardware threads, machine `Tiamat`
(`MACHINE=ryzen5800x3d`), WSL2 Ubuntu 26.04.1 LTS, kernel
`6.18.54.1-microsoft-standard-WSL2`. gcc is Ubuntu 15.2.0-16ubuntu1, liburing is
2.14, and oha is 1.16.0. Native io_uring is enabled; the server logs report the
uring loop without a fallback. Transparent huge pages are set to `madvise`.

Both binaries use Goose `46356c26a94f0e1723b3b61ad56b93a7da70878f`, built in
release mode. The Linux compiler's SHA-256 is
`448390d9b273f5818cbc22b8425bbbe85f006219f800aa567b5ac2df69e0e8d7`.
The fetched Goose upstream adds only a logo and a Discord link; this comparison
retains the compiler pin used by the original measurement.

| Build | HTTP source commit | Saved binary |
|---|---|---|
| Baseline | `0c7b0e4501e0c19268390d1825faeca3e9db127d` | `build/server-mail-wake-base` |
| Fixed | `8ab362c2afd589e572bfc64d545933f2195d4aff` | `build/server-mail-wake-fixed` |

The sources are separate `git archive` exports under ignored `build/`, so neither
build changes the checkout on `main`. Both use `LOOP=uring scripts/build.sh`:
`goose build --cc gcc --standalone`, with Goose and gcc at `-O2`. The package sidecar
builds and links the Linux shims and liburing. The saved binaries are kept locally;
the raw benchmark output is committed beside this file.

```sh
export GOOSE=$(realpath ../goose/build-linux/goose)
mkdir -p build/mail-wake-validation/base build/mail-wake-validation/wake
git archive 0c7b0e4 | tar -xf - -C build/mail-wake-validation/base
git archive 8ab362c | tar -xf - -C build/mail-wake-validation/wake
LOOP=uring bash build/mail-wake-validation/base/scripts/build.sh
cp build/mail-wake-validation/base/build/server build/server-mail-wake-base
LOOP=uring bash build/mail-wake-validation/wake/scripts/build.sh
cp build/mail-wake-validation/wake/build/server build/server-mail-wake-fixed
sha256sum build/server-mail-wake-base build/server-mail-wake-fixed
```

| Binary | SHA-256 |
|---|---|
| `build/server-mail-wake-base` | `a98c21454b5d0d4e59cb6ed5c1cb1397e471749300c0549df67b8eead7fe66a5` |
| `build/server-mail-wake-fixed` | `01d72aad0f49d20fa976089d4a404e342b3e1afe75e9c53fccd004d55a64ee9a` |

## Tests

`main` was fetched and pulled before testing. The suites ran concurrently with
different ports, avoiding WSL's localhost forwarding between their HTTP listeners.
The example stages, which use port 8080, did not overlap.

```sh
# WSL2 Ubuntu, gcc 15.2.0
GOOSE=../goose/build-linux/goose PORT=29180 WORKERS=4 scripts/test.sh

# Windows 11 10.0.26200, Git Bash, MSVC 19.51
GOOSE=../goose/build/Release/goose.exe PORT=29280 WORKERS=4 \
    nice -n 19 scripts/test.sh
```

| Platform | Loop | Result |
|---|---|---|
| Linux | Native io_uring | Pass |
| Linux | Ring over epoll | Pass |
| Linux | epoll | Pass |
| Windows | IOCP | Pass |

Both suites finish with `test.sh: all passed`: typechecks, unit tests, HTTP tests,
echo tests, and examples. Linux includes the load and fd-limit checks; Windows
omits them as documented. The HTTP waiting checks include five bursts of 500 SSE
pieces, stale sends after disconnect and timeout, and connection reuse. Full logs
are saved in `build/mail-wake-validation/linux-test.log` and `windows-test.log`.

## Measurement commands

The method follows [the live-key measurement](2026-10-14-mail-live-method.md):
oha, 4 HTTP workers, 256 connections, 500,000 requests per cell, 3 paired rounds,
no CPU affinity and no concurrent test or build work. A waiting-enabled server also
has the benchmark backend thread. Each cell starts a fresh server. Each round runs
the baseline's paths, then the fixed binary's paths. Waiting is disabled for the
first set and enabled with `MAIL_SLOTS=64` for the other two.

`bench/oha.sh` quotes the full URL, so `PATHS` accepts a query string. A separate
1,000-request probe of `/later?id=b&delay=0`, with 256 connections and waiting on,
checks both binaries before measurement. No alternate route is used. The probe
returns 995 HTTP 200s and 5 HTTP 504s on the baseline, and 994 HTTP 200s and 6 HTTP
504s on the fixed binary, with no transport errors
([raw probe](2026-10-14-mail-wake-probe/runs.tsv)). The benchmark backend
deliberately drops a reply when a worker's mailbox is `FULL`
(`server/backend.goose`, `answer`). With 256 connections unevenly distributed
across four workers and 64 mailbox slots per worker, this can leave an exchange
waiting until its 5-second timeout. A 504 is not a failure to pass the query string.

The waiting-path rates therefore include mailbox saturation and timeouts, and
cannot by themselves isolate the cost of keeping the key live through `WAKE`.
This route waits for one reply from the backend; it does not reproduce the
multi-piece race, which the HTTP suite tests with `/events`. The requested
settings and source commits are retained so the comparison remains reproducible.

```sh
export PATH=$HOME/.cargo/bin:$PATH
unset MAIL_SLOTS MAIL_CHECK_STALE LOOP PIN
export SERVERS='base=build/server-mail-wake-base fixed=build/server-mail-wake-fixed'
export WORKER_COUNTS=4 CONNS=256 MACHINE=ryzen5800x3d OHA=oha PORT=29380
MAIL_SLOTS=64 PATHS='/later?id=b&delay=0' REQUESTS=1000 RUNS=1 \
    OUT=build/mail-wake-validation/query-probe bench/oha.sh
export REQUESTS=500000 RUNS=3
PATHS='/plaintext /json' OUT=bench/results/2026-10-14-mail-wake-off bench/oha.sh
MAIL_SLOTS=64 PATHS='/plaintext /json' \
    OUT=bench/results/2026-10-14-mail-wake-on bench/oha.sh
MAIL_SLOTS=64 PATHS='/later?id=b&delay=0' \
    OUT=bench/results/2026-10-14-mail-wake-later bench/oha.sh
```

Each cell invokes
`oha -n 500000 -c 256 --no-tui --output-format json http://127.0.0.1:29380/PATH`.
`runs.tsv` records response counts, rates, and server user and kernel CPU time;
each cell's JSON and server log remain beside it. `env.txt` records the runtime
checkout HEAD; the source commits and hashes above identify the saved binaries.

## Results and limits

All 30 measured cells finish, accounting for all 500,000 requests in each, with
no transport errors. The 24 plaintext and JSON cells return only 200s. The waiting
path returns the following 504 counts alongside its 200s:

| Binary | Round 1 | Round 2 | Round 3 |
|---|---:|---:|---:|
| Baseline | 24 | 8 | 18 |
| Fixed | 6 | 18 | 7 |

The three-run ranges overlap for every comparison. The waiting-path difference
includes the 5-second timeout tail, so it is not evidence of a gain from the fix.
The costs with waiting on do not separate from the runs' spread; the fix is retained
for correctness.

[Task 027, item 12](../../tasks/027-idiomatic-api.md) records the rate table and
interpretation. Raw runs and CPU time are in
[waiting off](2026-10-14-mail-wake-off/runs.tsv),
[waiting on](2026-10-14-mail-wake-on/runs.tsv), and
[the waiting path](2026-10-14-mail-wake-later/runs.tsv).
The README and benchmark summary cite other builds and keep their existing pins.
