# 048: The packages spawn their own threads

Status: in progress; merged on Goose master `dcc2747`, pinned until a release has it.
On 2026-10-19 lanes moved into goose-http as `http::lane_open`, and `Config.worker`
and seats went with placement
([decision](../docs/decisions.md#placement-is-removed-until-it-is-measured-to-help)):
the criteria below that name them describe what was built then.

`thread_spawn` couldn't name a `thread_fn` passed into a generic from another module, so
neither package could start a thread of the program's: every program spawns its own
workers, and every goose-rest program spawns each lane's threads, one per box. Goose
`fb5698125` (aardappel/goose#37, on its `main` 2026-10-18) lifts that: a generic
`fn run<W>(...)` may `thread_spawn(W, ...)` with whatever `thread_fn` its caller binds
`W` to, in any namespace (Goose's `test/threads/thread_spawn_modules.goose`).

This task moves thread starting into the packages, where the count, the index, and the
seat of each thread are known. It follows task 046's placement and goose-rest's lanes
of N.

## Today

goose-http, in 11 examples and goose-rest's 26 programs:

```goose
let cfg = http::Config { port: 8080, place: http::place_ref(place), .. };
var ids: i64[>..] = [];
for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
for id in ids { thread_wait(id); }
```

A worker doesn't know its index, so `place_worker` takes the next one of its role from a
counter per placement and role in `shim/place.c` (task 046, "Workers' index"), global
state that the complexity review of 2026-10-18 named a cost.

goose-rest, for each lane:

```goose
let reports = rest::lane_open(place, rest::LaneConfig { role: "reports", max: 4, .. });
for b, i in reports.boxes { lanes.push(thread_spawn(reader, b, rest::lane_seat(place, reports, i))); }
// ...
rest::lane_stop(reports);
for id in lanes { thread_wait(id); }
```

## Proposed

goose-http:

```goose
// Spawns worker_count(cfg) workers, each with its own copy of cfg and its index,
// and returns once every one has returned.
http::run(cfg, worker);             // thread_fn worker(cfg: http::Config)
http::run(cfg, worker, app);        // thread_fn worker(cfg: http::Config, app: App)
http::run(cfg, worker, a, b);       // two values of the program's
```

`run` sets `Config.worker`, a new field, to each worker's index, and the loop takes the
seat `place_seat(place, cfg.role, cfg.worker)`. Goose has no variadic parameters, so
`run` has an overload per count of extra values: 0, 1, and 2 cover every program in
both repositories.

goose-rest:

```goose
// Opens the lane's boxes and spawns reader once per box, with its box and seat.
let reports = rest::lane_open(place, rest::LaneConfig { role: "reports", max: 4, .. }, reader);
// thread_fn reader(box: http::Box, at: http::Seat), or with one value of the program's
// ...
rest::lane_stop(reports);           // stops every box, then waits for its threads
```

`Lane` keeps its threads' ids beside its boxes. `rest::lane_seat` goes, since the
lane hands each thread its seat.

## Decided (2026-10-18)

Each open question below takes its proposal: no arrival counter, and a placed worker
spawned outside `run` warns once and floats; a program that chooses a loop per run
calls `run` once per choice, and only a program that must interleave spawning with
other work keeps its own loop and sets `Config.worker` (changed 2026-10-18);
`lane_stop` waits for the lane's threads; the names are `http::run` and `Config.worker`.

The API and the code are to be as simple as they can be without giving up speed or a
feature: what this change makes unneeded is removed, not kept beside the new way
(`lane_seat`, the arrival counter, `place_next`, `place_next_seat`, and anything else
`run` and `lane_open` make redundant).

## Open questions

- **Keep the program's own spawn loop for workers?** Retiring the arrival counter
  needs every placed worker to come through `run`. Options: keep the counter as the
  fallback when `Config.worker` is unset, which keeps today's code working but keeps the
  C state; or keep the counter out, and have a worker spawned outside `run` with a
  placement print one warning and float. Proposed: the second, since every example
  moves to `run` in this task.
- **Programs that choose a loop per worker,** as `bench/rest/goose/rest.goose` and
  `examples/device` do (`worker_epoll` or `worker`, chosen at run time): a `run` per
  choice, or such a program keeps its own loop and passes `Config.worker` itself.
  Proposed: it keeps its own loop and sets `Config.worker`, which `run`'s comment shows.
- **Does `lane_stop` wait?** Proposed: yes, as above, with `rest::lane_stop` called by
  the thread that opened the lane; `thread_wait` belongs to the spawner.
- **Names:** `http::run` or `http::serve_workers`; `Config.worker` or `Config.index`.

## Acceptance criteria

- [x] Agreed answers to the open questions, recorded here (2026-10-18)
- [x] The answers in each repository's `docs/decisions.md`, with the reason (goose-http
      `084f7fb`, goose-rest `c1d1e48`)
- [x] goose-http: `http::run` with 0, 1, and 2 extra values, `Config.worker`, and the
      loops taking their seat from it; the arrival counter and `place_next` removed
      from `shim/place.c`, or kept per the first question (`87cd198`). The worker comes
      last, `http::run(cfg, app, worker)`, not as proposed: Goose takes a function value
      only after a call's other arguments (spec §7.6)
- [x] goose-http: every example, `server/`, and `bench/pinning/pinning.goose` use
      `run`; programs that keep their own loop set `Config.worker`; tests for `run`
      (workers' indexes, each gets its own seat, `run` returns after the last worker)
      (`87cd198`, `test/server/run.goose`)
- [x] goose-rest: `rest::lane_open(place, cfg, W)` with 0 and 1 extra values,
      `Lane` keeping its thread ids, `lane_stop` waiting for them, and `lane_seat`
      removed; the tutorial's and best practices' programs, their pages' quoted blocks,
      and `test/lane/` moved to them (goose-rest `c1d1e48`, `446eae1`;
      `Lane.role` went too, as only `lane_seat` read it)
- [x] Docs: goose-http's `docs/api.md` ("Running a server") and `docs/tuning.md`;
      goose-rest's tutorial chapters that spawn threads,
      `docs/best-practices/lanes.md`, and `docs/reference.md` (`084f7fb`, goose-rest
      `c1d1e48` and `446eae1`)
- [ ] `README.md`'s quick start calls `http::run` once a goose-http tag has it: until
      then it imports `v0.3.7`, which builds with Goose `v2026.2`
- [x] Built and tested on Goose master `dcc2747`, which `scripts/goose.sh` pins until a
      release has #37 (2026-10-19): merged before that release, rather than waiting,
      so that the work on #38 and #39 builds on it
- [x] 2026-10-19: lanes in goose-http, `http::lane_open(cfg[, a], W)` and
      `http::lane_stop`, used by `examples/later`, `server/`, and every goose-rest
      program; `Config.worker` removed, and `test/server/run.goose` checks values and
      the wait only
- [ ] `scripts/test.sh` passes in both repositories on macOS, Linux (io_uring, epoll),
      and Windows (MSVC): both on macOS and in arm64 Linux Docker (io_uring, epoll, and
      the emulated ring) on 2026-10-19, at the `simplify` branches; Windows not yet run
