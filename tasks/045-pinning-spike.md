# 045: Pin threads to cores, as an option

Status: todo

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

## Acceptance criteria

- [ ] `http::pin_thread(core)` in the shim: `sched_setaffinity` on Linux,
      `SetThreadAffinityMask` on Windows, and a result that says it did nothing on macOS;
      `Config.pin` pins each worker to its own core
- [ ] The spike's server and script under `bench/`, with the five layouts above
- [ ] Results on the benchmark desktop in this task: `/fast` p50, p99, and p99.9 (median
      of 5 and range), the primes route's completed rate, and its 503 and 504 counts, with
      machine, kernel, cores, connections, and run count
- [ ] The decision, recorded in `docs/decisions.md`: pinning workers, pinning a lane, or
      `nice` stays as an option only where it beats `over` and `fewer` on `/fast` p99 by
      more than the runs' spread, and what doesn't is dropped and recorded here
- [ ] Whatever stays: in `docs/api.md` and `docs/patterns.md` ("Slow work"), with when to
      use it and when not to (few cores, CPU quotas)
