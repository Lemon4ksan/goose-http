# 045: Pin threads to cores, as an option

Status: done, with nothing taken (2026-10-21). On bare-metal Linux no layout beat
floating on /fast's p99 beyond the runs' spread, so placement stays off `main`, on the
branch `placement`
([decision](../docs/decisions.md#placement-stays-off-main-after-bare-metal-linux)).

Tina pins each shard to a core of its own (its `docs/concepts/thread_per_core.md`, at
`d129f67`). goose-http pins nothing. A worker runs on every hardware thread by default,
and lanes run on top of them, so the OS decides whether a short request waits behind a
lane's CPU work. Pinning may help workers, and some lanes, such as one that hashes
passwords, but likely not all. A lane that mostly waits on a database needs no core of
its own. Pinning is to be an option, never the default: a machine with 1 or 2 cores has
no core to spare, and in a container with a CPU quota the hardware thread count says
nothing about the cores the program may use.

A spike measures it against goose-http, not goose-rest, so that no framework code is
between the layouts. `examples/later` already sends CPU work, counting primes, to a
lane.

## The spike

A copy of `examples/later` under `bench/`, with a short route (`GET /fast`) answered in
the handler, and the primes route on a CPU lane. `LAYOUT` picks one of five:

| Layout | Workers | Lane |
|---|---|---|
| `over` | one per hardware thread, unpinned (today's default) | unpinned |
| `fewer` | one fewer, unpinned | unpinned |
| `workers` | one fewer, each pinned | unpinned |
| `pinned` | one fewer, each pinned | pinned to the core left free |
| `nice` | one per hardware thread, unpinned | unpinned, at low priority (`nice`, `SCHED_BATCH`) |

`fewer` separates the gain from leaving a core free from the gain from pinning itself.
`nice` is the option that also works on 1 or 2 cores.

Two load generators run at fixed rates at once, so the client slowing down can't hide
latency: `/fast` at about 70% of what `over` serves alone, and the primes route at a
rate that keeps the lane about 80% busy. Each layout runs 5 times, alternating, 30 s
each after a 5 s warm-up, on Linux, which has CPU affinity (macOS has none).

Task 046 designs the placement API this spike measures, and may add layouts to the five
above: a lane on a worker's SMT sibling, and a lane kept within a set of cores.

## As built (2026-10-17)

Placement (task 046) replaced `http::pin_thread` and `Config.pin`: the spike gives each
layout as a placement file, so that it measures the API that ships.
`bench/pinning/pinning.goose` is the server, and `bench/pinning.sh` writes each layout's
file from the cores the server may use, calibrates the two rates as above unless
`FAST_RATE` and `PRIMES_RATE` are given, and writes `runs.tsv` and `summary.tsv` under
`build/bench/pinning/`. Beyond the five layouts above, it runs task 046's: `sibling` (a
worker on the first hardware thread of each core, the lane on worker 0's SMT sibling),
`within` (the lane within the two cores the workers leave), and `incoming` (`pinned`, with
`SO_INCOMING_CPU` on each worker's listener). `SERVER_CPUS` and `CLIENT_CPUS` keep the
server and the clients apart with `taskset`.

It ran once, for 3 s a layout, in Docker on macOS (arm64, 10 virtual CPUs, no SMT, so no
`sibling`): every layout started, and the placement printed no warning. Docker's virtual
CPUs are host threads that macOS moves between cores, so pinning in it pins nothing
real, and no number from it is a result. macOS itself can't pin: there, the script runs
`over`, `fewer`, and `nice`, which on Apple silicon puts the lane on the efficiency cores
(the background QoS class).

## On macOS (2026-10-17)

On an M1 Pro (8 performance and 2 efficiency cores), macOS 26.3.1 (Darwin 25.3.0), Goose
`v2026.2`, at `e73ccb82`: `bench/pinning.sh` with `RUNS=5 SECONDS_EACH=30 WARMUP=5`,
the layouts alternating. `over` and `nice` run 10 workers, `fewer` 9; the lane is one
thread. /fast has 64 connections and /primes/200000 16, both from oha 1.16.0 with
`--latency-correction`, on the same cores as the server: macOS can't keep them apart.
Other programs ran (a terminal at about half a core, idle containers). Median of 5, with
the range:

| /fast rate | Layout | /fast p50 | p99 | p99.9 | Primes done/s (of 1,771.5 asked) |
|---|---|---|---|---|---|
| 24,331/s (70% of `over` alone) | `over` | 0.911 ms | 4.49 (4.14–4.65) | 10.8 (9.6–11.1) | 1,771 |
| | `fewer` | 0.906 ms | 5.17 (4.91–6.95) | 10.8 (10.0–35.2) | 1,771 |
| | `nice` | 0.887 ms | 6.39 (6.35–6.47) | 10.2 (9.2–16.4) | 1,060 (966–1,068) |
| 12,165/s (35%) | `over` | 0.428 ms | 4.01 (3.99–4.02) | 6.5 (5.3–6.7) | 1,771 |
| | `fewer` | 0.427 ms | 4.00 (3.95–4.04) | 6.2 (4.7–10.3) | 1,771 |
| | `nice` | 0.492 ms | 3.96 (3.91–3.99) | 6.0 (5.0–9.4) | 998 (968–1,014) |

No 503 or 504 in any run. Neither `fewer` nor `nice` beats `over` on /fast's p99 by more
than the runs' spread on this machine: at 70%, both are worse; at 35%, `nice` is 1% lower
with ranges that touch. `nice` costs the lane about 40% of its rate, since the
background QoS class runs it on the efficiency cores only; the client, held to 16
connections, then asks less than its rate rather than meeting 503s. So on macOS, `low`
is for work that may run slower, not a latency gain for the workers. The decision below
waits for bare-metal Linux, where the pinned layouts can run.

## On bare-metal Linux (2026-10-21)

On a Ryzen 5 9600X (6 cores, 12 hardware threads; CPU n and n+6 are SMT siblings),
Bazzite 43, kernel `6.17.7-ba29.fc43.x86_64`, amd-pstate-epp with the `powersave`
governor, EPP `balance_performance`, and tuned's `balanced-bazzite`; built and run in a
Fedora 43 distrobox, which shares the host's kernel. The `placement` branch at
`a5e2d37c`, Goose `dcc2747`, oha 1.16.0 with `--latency-correction`. Bazzite's firewall
filters loopback (`docs/known-issues.md`, "Benchmarks") and was left on.

```sh
SERVER_CPUS=0-3,6-9 CLIENT_CPUS=4,5,10,11 RUNS=5 SECONDS_EACH=30 WARMUP=5 \
    PRIMES_RATE=3454.3 FAST_RATE=200000 bench/pinning.sh    # then FAST_RATE=100000
```

The server has 4 cores, both threads of each, and the clients the other 2. The layouts
hold as the script defines them on hardware threads, unchanged: `over` and `nice` run 8
workers, `fewer` and `workers` 7, and `within` 6; `pinned` and `incoming` put the lane
on CPU 9, worker 3's SMT sibling, since no core is left whole; `sibling` runs 4 workers
on 0-3 and the lane on 6. The placement files, `env.txt`, `runs.tsv`, and `summary.tsv`
for each rate are in `bench/results/2026-10-21-pinning-bazzite/`.

The /fast rates differ from the design's. Calibrated, `over` alone served 718,000
requests a second with its 8 workers using 1.8 CPUs: oha on 4 threads is the limit, not
the server, so 70% of that measures oha. Against the unloaded server, oha's own p99 rose
with its rate: 0.45 ms at 100,000/s, 0.98 ms at 200,000/s, and 6.2 ms at 300,000/s. The
runs use 200,000/s and 100,000/s, which oha holds, so the workers are lightly loaded:
this measures the lane's interference at those loads, not near saturation. The primes
rate is the script's calibration, 3,454.3/s over 16 connections, the lane 80% busy.

Median of 5, with the range, in ms; /fast had 64 connections:

| /fast rate | Layout | p50 | p99 | p99.9 | Primes done/s |
|---|---|---|---|---|---|
| 200,000/s | `over` | 0.281 | 2.78 (2.25–3.61) | 26.4 (20.6–27.3) | 3,454.2 |
| | `fewer` | 0.284 | 4.31 (3.15–4.42) | 29.6 (24.3–34.8) | 3,454.2 |
| | `workers` | 0.291 | 3.36 (2.78–5.71) | 28.8 (24.8–50.1) | 3,454.2 |
| | `pinned` | 0.284 | 3.48 (3.19–4.33) | 27.8 (26.8–32.6) | 3,454.2 |
| | `nice` | 0.286 | 3.21 (2.55–3.79) | 27.8 (25.7–29.1) | 3,454.2 |
| | `sibling` | 0.283 | 3.06 (2.23–3.43) | 24.6 (20.9–27.2) | 3,454.2 |
| | `within` | 0.275 | 3.32 (2.52–4.25) | 30.4 (24.8–35.7) | 3,454.3 |
| | `incoming` | 0.282 | 3.26 (2.84–3.51) | 28.9 (21.4–31.3) | 3,454.2 |
| 100,000/s | `over` | 0.142 | 0.566 (0.547–0.580) | 4.23 (3.69–6.01) | 3,454.2 |
| | `fewer` | 0.142 | 0.565 (0.531–0.591) | 3.87 (2.65–4.72) | 3,454.2 |
| | `workers` | 0.141 | 0.587 (0.568–0.594) | 3.66 (3.17–8.09) | 3,454.2 |
| | `pinned` | 0.140 | 0.571 (0.557–0.583) | 4.60 (3.83–5.51) | 3,454.2 |
| | `nice` | 0.142 | 0.565 (0.549–0.572) | 3.75 (3.21–5.61) | 3,454.2 |
| | `sibling` | 0.140 | 0.567 (0.555–0.583) | 3.30 (3.07–4.73) | 3,454.2 |
| | `within` | 0.141 | 0.574 (0.555–0.589) | 4.98 (4.20–5.74) | 3,454.2 |
| | `incoming` | 0.141 | 0.556 (0.545–0.595) | 3.94 (2.90–5.01) | 3,454.2 |

Every run held its /fast rate to within 0.02%, and no run had a 503 or a 504.

- No layout beats `over` on /fast's p99 at either rate. At 200,000/s `over` has the
  lowest median, and every other layout's range overlaps it; `fewer` is worse, its
  median 55% higher. At 100,000/s every median is within 0.556–0.587 ms and every range
  overlaps.
- `nice` cost the lane nothing here, unlike on macOS: the lane met its rate in every
  layout.
- The p99.9 at 200,000/s, 25-30 ms in every layout and ten times the p99, is likely
  oha's pacing at that rate rather than the server's.

So every layout goes: pinned workers (`workers`), a pinned lane (`pinned`), a lane on a
worker's SMT sibling (`sibling`), a lane kept within a set (`within`),
`SO_INCOMING_CPU` (`incoming`), and a low-priority lane (`nice`). A server near
saturation wasn't measured, since oha can't load one on this machine; a case for
placement would need a client that can, and a gain there.

## Acceptance criteria

- [x] `http::pin_thread(core)` in the shim: `sched_setaffinity` on Linux,
      `SetThreadAffinityMask` on Windows, and a result that says it did nothing on macOS;
      `Config.pin` pins each worker to its own core. Built as placement instead
      (`http::take_seat`, `Config.place`). On Windows, `shim/place.c` builds with MSVC
      and clang-cl, `test/place/place_seat.goose` reads each pinned seat back, and
      `bench/pinning/pinning.goose` runs with a placement file, at `cb66ab09` (task 047)
- [x] The spike's server and script under `bench/`, with the five layouts above
- [x] Results on a bare-metal Linux machine in this task: `/fast` p50, p99, and p99.9 (median
      of 5 and range), the primes route's completed rate, and its 503 and 504 counts, with
      machine, kernel, cores, connections, and run count ("On bare-metal Linux")
- [x] The decision, recorded in `docs/decisions.md`: pinning workers, pinning a lane, or
      `nice` stays as an option only where it beats `over` and `fewer` on `/fast` p99 by
      more than the runs' spread, and what doesn't is dropped and recorded here: none
      did, so every layout went (2026-10-21)
- [x] Whatever stays: in `docs/api.md` and `docs/patterns.md` ("Slow work"), with when to
      use it and when not to (few cores, CPU quotas): nothing stayed
