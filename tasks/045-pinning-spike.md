# 045: Pin threads to cores, as an option

Status: the spike is built (`bench/pinning.sh`) and smoke-tested in Docker; the
measurement on bare metal is pending

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

## Acceptance criteria

- [x] `http::pin_thread(core)` in the shim: `sched_setaffinity` on Linux,
      `SetThreadAffinityMask` on Windows, and a result that says it did nothing on macOS;
      `Config.pin` pins each worker to its own core. Built as placement instead
      (`http::take_seat`, `Config.place`). On Windows, `shim/place.c` builds with MSVC
      and clang-cl, `test/place/place_seat.goose` reads each pinned seat back, and
      `bench/pinning/pinning.goose` runs with a placement file, at `cb66ab09` (task 047)
- [x] The spike's server and script under `bench/`, with the five layouts above
- [ ] Results on the benchmark desktop in this task: `/fast` p50, p99, and p99.9 (median
      of 5 and range), the primes route's completed rate, and its 503 and 504 counts, with
      machine, kernel, cores, connections, and run count
- [ ] The decision, recorded in `docs/decisions.md`: pinning workers, pinning a lane, or
      `nice` stays as an option only where it beats `over` and `fewer` on `/fast` p99 by
      more than the runs' spread, and what doesn't is dropped and recorded here
- [ ] Whatever stays: in `docs/api.md` and `docs/patterns.md` ("Slow work"), with when to
      use it and when not to (few cores, CPU quotas)
