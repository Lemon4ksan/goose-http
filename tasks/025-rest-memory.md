# 025: The REST server's memory per worker

Status: in progress (asked for 2026-10-13)

On the REST tiers, Goose holds 2 to 5 times hyper's peak RSS, more than its 1.2 to 2.1
times the speed: tier C 129-140 MB serialized and 376-387 MB templated with 4 workers,
against hyper's 36 and 75 ([results](../docs/results.md#rest-apis)). A real program with
an in-memory cache would pay the same, so the cost belongs to Goose's model, not only to
the benchmark.

## What's known (2026-10-13)

Each worker holds its own copy of the records. `rest.goose` loads them into globals in
`main`, and `thread_spawn` copies every global a worker uses: nothing is shared between
threads but `const` globals with compile-time initializers (spec §11.2). With 4 workers
that is 5 copies, main's included. hyper's threads share one.

Idle after startup, epoll loop, the desktop, `build/rest` binaries of
`2026-10-13-rest`, VmRSS (VmHWM was the same for Goose):

| Tier, JSON | Goose, 1 / 2 / 4 workers | Per worker | hyper, 1-4 workers |
|---|---|---:|---:|
| A, serialize | 13 / 17 / 26 MB | 4.3 MB | 7 MB |
| A, template | 19 / 27 / 42 MB | 7.7 MB | 10 MB |
| C, serialize | 58 / 79 / 122 MB | 21 MB | 23 MB (29 at peak) |
| C, template | 156 / 227 / 370 MB | 71 MB | 61 MB |

- Memory grows linearly with workers, by about one dataset per worker, and the 1-worker
  intercept holds main's copy too.
- A copy is larger than its JSON: tier A's items are 1.5 MB of JSON and 4.3 MB per
  worker. Records keep strings in fixed-capacity fields (`name: u8[..48]`,
  `tags: u8[..24][..4]`), each the full capacity whatever its length.
- Templates add each record's prebuilt JSON per worker, on top of the records the
  serialize path uses: 71 MB a worker on tier C, from about 15 MB of dataset JSON.
- The load is no spike: VmHWM equals VmRSS at idle. A benchmark run adds 15-20 MB to
  the idle figure on tier C (response buffers, connections).

## What to try

1. Release main's copy once the last worker is spawned, if clearing a global array gives
   its data-stack memory back; one copy of five.
2. Smaller records: strings as ranges into one byte array per table, not fixed-capacity
   fields, and in template mode only what the prebuilt JSON doesn't already hold.
3. Sharing one copy. Goose has no way to share data built at run time between threads,
   and no recorded plan for one (checked 2026-10-13 at `6448f3f`): only static data is
   shared (spec §11.2), every other global a worker names is copied whole at spawn, with
   no copy-on-write, and queues copy too. Static initializers take literals only, up to
   256 array elements. `const` globals are shared because they're read-only; data built
   by `main` before the first spawn and never written after could be shared on the same
   grounds. Ask the maintainer whether that's planned, and record the limit in
   `docs/goose-findings.md` with tier C's numbers.
   - Today's one route is `embed_file(path)`: a file's bytes compiled into the binary as
     static data, which every thread shares. A worker must call it through a function
     (a slice global isn't flat, so a worker can't name one), and must read the bytes in
     place, with offsets into them: parsing them into structs makes a copy per worker
     again. It changes the benchmark's rule that servers load their records at startup,
     and 15 MB of JSON makes about 60 MB of generated C, so it stays out unless every
     server may do the same.
4. One data thread that workers mail, as goose-rest plans for a shared cache: one copy,
   at the cost of a mailbox round trip per read, and on tier C every response's JSON
   built on that one thread. That measures Goose's concurrency model rather than its
   HTTP layer, so it belongs beside the main cells as a variant, with goose-rest, not in
   their place.

## What was done (2026-10-14)

Three changes to `bench/rest/goose/rest.goose`, each its own commit:

1. `c9d9d9f`: main can't give its copy back. A data stack keeps its pages while its
   thread runs, and `clear()` only lowers its top
   ([findings](../docs/goose-findings.md#a-worker-holds-its-globals-twice-and-its-spawner-keeps-a-third-copy)).
   So a `loader` thread loads the records, spawns the workers, which copy its globals as
   before, hands main their ids through a queue, and returns, and the runtime unmaps
   its stacks: its copy, the spawn image, and the parsed file.
2. `a81b3f0`: strings live in one pool and records hold ranges into it, repeated short
   values are `u8` indexes into a word list, and in template mode the loader drops the
   records the prebuilt JSON already holds, on every tier but B, whose routes compare
   ids.
3. `9408035`: tier C's visit templates are built from slices of their notes' JSON, so
   each note's text is held once.

Measured on the desktop: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose
`0bdbd18`, against `main` at `dd68f22`. Idle memory, each build, tier, JSON way, and 1,
2, and 4 workers on the epoll loop, VmRSS 3 s after listening, one run each
([idle](../bench/results/2026-10-14-rest-025-idle/idle.tsv)). With 4 workers, in MB:

| Build | A serialize | A template | B serialize | B template | C serialize | C template |
|---|---:|---:|---:|---:|---:|---:|
| main | 26.9 | 43.8 | 88.5 | 217.7 | 125.9 | 379.0 |
| 1, loader thread | 21.1 | 34.5 | 62.2 | 165.5 | 91.7 | 294.2 |
| 2, string pool | 8.9 | 16.7 | 35.7 | 139.1 | 83.9 | 214.7 |
| 3, notes once | 8.9 | 16.7 | 35.8 | 139.1 | 83.8 | 142.8 |

A tier C worker now costs 20 MB serialized and 35 MB templated (from 1 to 4 workers),
where it cost 22 and 73. hyper holds 23 and 61 MB at any worker count, so Goose's
templated tier C is at 2.3 times it, from 6.2.

`bench/rest.sh run`, `STEPS=1` (with its checks, which passed for every tier, each
response matching the other servers'), uring, 4 workers on CPUs 0-3 and the load on
4-15, 3 rounds of 15 s
([summary](../bench/results/2026-10-14-rest-025/summary.md)):

| Cell | main, req/s | peak RSS | 3, req/s | peak RSS |
|---|---:|---:|---:|---:|
| A serialize | 589.2K (585.7-591.9K) | 33 MB | 584.7K (576.9-590.7K) | 15 MB |
| A template | 599.7K (597.3-600.6K) | 49 MB | 599.3K (596.0-603.8K) | 23 MB |
| B serialize | 268.7K (263.7-270.5K) | 95 MB | 277.0K (275.9-282.8K) | 47 MB |
| B template | 372.2K (371.6-376.0K) | 221 MB | 379.3K (376.6-380.3K) | 152 MB |
| C serialize | 50.7K (49.9-51.1K) | 140 MB | 52.0K (51.4-52.6K) | 104 MB |
| C template | 145.6K (144.5-146.2K) | 387 MB | 145.6K (142.9-146.0K) | 176 MB |

Every rate holds within the rounds' spread or gains, by up to 3.1% on B serialized.
Step 2 alone (`goose-uring-25b` in the summary) ran tier C templated at 142.9K, 1.9%
under; step 3 wins it back.

## Workers take their records over queues (2026-10-14, not yet measured)

On `task-025-worker-load`, cut from `findings-46356c2-hot`. Built and typechecked only;
nothing was run, since another session was benchmarking.

A worker holds what `thread_spawn` copies twice for its life: in the `malloc`ed packet
the runtime copies the globals through, which it frees only when the worker returns, and
on the worker's own data stacks
([findings](../docs/goose-findings.md#a-worker-holds-its-globals-twice-and-its-spawner-keeps-a-third-copy)).
So `rest.goose`'s loader now hands each worker its arrays over the typed queues instead:

- `hand_over` `qput`s each of the 45 global arrays once per worker and clears the
  loader's own, so each spawn copies empty arrays and its packet is a few hundred
  bytes.
- Each worker's `take_all` `qget`s them into its globals. The generated C copies each
  queued image straight onto the global's data stack and frees the queue's node.
  `qput` `malloc`s each node; a node over glibc's mmap threshold (128 KB until the
  first such free) is `mmap`ed, so its free gives the pages back. Every node is
  allocated before any is freed, so the threshold doesn't move between them.
- Arrays of one element type share a queue, so workers take theirs one at a time: the
  loader spawns a worker, waits for its `Taken`, and only then spawns the next.
- An array left out of `hand_over` and `take_all` still reaches the workers, copied
  through `thread_spawn` as before, so a miss costs memory, not correctness.

Expected: each worker holds one copy of its arrays where it held two, about half of
each added worker's memory (tier C templated +35 MB a worker to about +18 MB,
serialized +20 MB to about +10 MB, tier B templated +34 MB to about +17 MB). The
loader's peak rises during the hand-off, by one copy of the arrays per worker, and it
all goes when the loader returns. Startup adds one copy of the arrays per worker, in
turn, a few milliseconds on tier C. No request runs any changed code: the handlers and
the loops are as they were.

Not done: dropping the record arrays a templated worker never reads. Tier C's templated
routes still select by the records (bookings, shifts, visits, clients, and
`staffers.len`); only `notes` would go, read for its `kind` alone, and the dataset has
at most about 5,100 notes, about 0.2 MB a worker.

To check, at `findings-46356c2-hot` and at this branch: `bench/rest-memory.sh`, which
should move each worker's share out of the "large malloc" column; then tiers A to C of
`bench/rest.sh run` for the rates.

## Acceptance criteria

- [ ] Each worker's share split by source (records, templates, buffers, runtime), with
      task 016's per-worker baseline
- [x] Main's copy released after spawn, or recorded why it can't be: it can't, so the
      records load on a thread that returns once the workers start
- [x] Records and templates compacted where it costs no requests per second, measured on
      tiers A to C before and after
- [ ] The sharing question asked, and the answer in `docs/goose-findings.md`: not
      asked yet (asked for 2026-10-14: nothing goes to the maintainer until allowed)
