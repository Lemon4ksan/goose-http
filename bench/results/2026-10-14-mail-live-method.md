# Live mailbox keys (2026-10-14)

Paired request-path checks for task 027, item 12. Ryzen 7 5800X3D, WSL2 Ubuntu
26.04.1, kernel `6.18.54.1-microsoft-standard-WSL2`, Goose `46356c2`, gcc 15.2.0,
release builds through `LOOP=uring scripts/build.sh`. The baseline has the HTTP
source of `1e963ba`; the candidate adds live mailbox keys. Documentation commits
moved `main` during the run, so each `env.txt` records HEAD at measurement time;
the saved binaries were unchanged across the two sets of runs.

SHA-256:

| Binary | SHA-256 |
|---|---|
| `build/server-mail-base` | `04682da90fa137326d5ed84465ef31873770659dbaa7e57f3fa76dfbeec1a543` |
| `build/server-mail-live` | `46875ff73e9bfcbe8b04380378a48263bdf390481c7f78c7cc615aca277d99d9` |

oha 1.16.0, 4 workers, 256 connections, 500,000 requests per cell, 3 paired rounds,
no CPU affinity. Each round runs the baseline's plaintext and JSON cells, then the
candidate's. Every request returned 200. The `/json` route is the fixed JSON
response, not the REST workloads. Waiting is disabled for the first set and enabled
with `MAIL_SLOTS=64` for the second.

```sh
SERVERS='base=build/server-mail-base live=build/server-mail-live' \
WORKER_COUNTS=4 PATHS='/plaintext /json' REQUESTS=500000 CONNS=256 RUNS=3 \
MACHINE=ryzen5800x3d OHA=oha \
OUT=bench/results/2026-10-14-mail-live-off bench/oha.sh

MAIL_SLOTS=64 SERVERS='base=build/server-mail-base live=build/server-mail-live' \
WORKER_COUNTS=4 PATHS='/plaintext /json' REQUESTS=500000 CONNS=256 RUNS=3 \
MACHINE=ryzen5800x3d OHA=oha \
OUT=bench/results/2026-10-14-mail-live-on bench/oha.sh
```

The candidate's later test-only change gates the backend's stale-send assertions
behind `MAIL_CHECK_STALE`; it does not affect either measured request path.
Rates, spread, and the interpretation are in task 027, item 12.
