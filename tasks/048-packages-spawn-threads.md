# 048: The packages spawn their own threads

Status: in progress; merges after a Goose release with `fb5698125`

`thread_spawn` couldn't name a `thread_fn` passed into a generic from another module, so
neither package could start a thread of the program's: every program spawns its own
workers, and every goose-rest program spawns each lane's threads, one per box. Goose
`fb5698125` (aardappel/goose#37, on its `main` 2026-10-18) lifts that: a generic
`fn run<W>(...)` may `thread_spawn(W, ...)` with whatever `thread_fn` its caller binds
`W` to, in any namespace (Goose's `test/threads/thread_spawn_modules.goose`).

This task moves thread starting into the packages, where the count, the index, and the
seat of each thread are known. It follows task 046's placement and goose-rest's lanes
of N (both on `tina-alignment`), and is built on a branch stacked on it.

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
spawned outside `run` warns once and floats; a program that chooses a loop per worker
keeps its own spawn loop and sets `Config.worker`; `lane_stop` waits for the lane's
threads; the names are `http::run` and `Config.worker`.

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
- [ ] The answers in each repository's `docs/decisions.md`, with the reason
- [ ] goose-http: `http::run` with 0, 1, and 2 extra values, `Config.worker`, and the
      loops taking their seat from it; the arrival counter and `place_next` removed
      from `shim/place.c`, or kept per the first question
- [ ] goose-http: every example, `server/`, and `bench/pinning/pinning.goose` use
      `run`; programs that keep their own loop set `Config.worker`; tests for `run`
      (workers' indexes, each gets its own seat, `run` returns after the last worker)
- [ ] goose-rest: `rest::lane_open(place, cfg, W)` with 0 and 1 extra values,
      `Lane` keeping its thread ids, `lane_stop` waiting for them, and `lane_seat`
      removed; the tutorial's and best practices' programs, their pages' quoted blocks,
      and `test/lane/` moved to them
- [ ] Docs: goose-http's `docs/api.md` ("Running a server"), `docs/tuning.md`, and
      `README.md`'s quick start; goose-rest's tutorial chapters that spawn threads,
      `docs/best-practices/lanes.md`, and `docs/reference.md`
- [ ] Built and tested with `GOOSE_COMMIT=fb5698125d6b366cff3b7aebc877fe0148c698a2` on a
      branch stacked on `tina-alignment`; merged only after a Goose release has the
      commit, with the pin moved to that release first
- [ ] `scripts/test.sh` passes in both repositories on macOS, Linux (io_uring, epoll),
      and Windows (MSVC)
