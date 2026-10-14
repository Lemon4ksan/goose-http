# 025: The REST server's memory per worker

Status: in-progress (asked for 2026-10-13)

The memory reductions are implemented and measured. Remaining work is the per-worker
source accounting and the sharing question's report and answer. Reporting still waits
for authorization, as the acceptance criteria state. The initial diagnosis below
describes the earlier build.

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

## Workers take their records over queues (2026-10-14)

Built on `task-025-worker-load`, cut from `findings-46356c2-hot`; on `main` with the
shared store below since `1818526` (2026-10-14). A worker held what
`thread_spawn` copies twice for its life: in the `malloc`ed packet the runtime copies
the globals through, freed only when the worker returns, and on the worker's own data
stacks
([findings](../docs/goose-findings.md#a-worker-holds-its-globals-twice-and-its-spawner-keeps-a-third-copy)).
`rest.goose` now hands the records over the typed queues instead:

- The loader loads the records, puts one set of the 45 global arrays on the queues
  (`hand_over`), and returns, which unmaps the files it read and parsed.
- A distributor thread takes that set and puts one copy of it per worker, the next only
  after the worker's `Taken`: arrays of one element type share a queue, so one thread
  takes at a time, a whole set. `Flags` carries the two scalar globals with each set.
- `main` spawns the distributor and each worker on its `Ready`. `main`'s record globals
  are empty, so each spawn's packet is a few hundred bytes. Each worker takes its set
  into its globals (`take_set`); the generated C copies each queued image onto the
  global's data stack and frees the queue's node.
- `main` sets glibc's `M_MMAP_THRESHOLD` to 128 KB. Left to adjust itself, glibc raises
  the threshold to the first `mmap`ed block freed, so later sets came from an arena
  that kept their pages: on tier C templated, 1, 2, and 4 workers held 20.8, 54.5, and
  88.6 MB, against 20.7, 37.9, and 72.1 with the threshold fixed.

The first version (`ce68db1`) put each array `count` times in a row, so a worker taking
`text` and then `item_json`, both `u8[>..]`, got `text`'s second copy: the checker
failed every cell. `2c2cb67` hands over one whole set per worker.

Measured on the desktop: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose
`46356c2`, the data of `bench/rest.sh build`, epoll loop, CPUs 0-3, no request sent,
one run each. `bench/rest/check.py` passes every cell at `c6058cb`: tiers A to D,
serialized and templated, on the epoll and io_uring loops, with 4 workers.

Each added worker's VmRSS, from `bench/rest-memory.sh` (2 workers less 1, 3 s after
listening; [before](../bench/results/2026-10-14-rest-memory-hot/memory.tsv),
[after](../bench/results/2026-10-14-rest-memory-queues/memory.tsv)), beside what a
worker's globals hold (the loader's `REST_LENS` lengths times the record sizes in the
generated C):

| Tier | `findings-46356c2-hot` | Queues | A worker's globals |
|---|---:|---:|---:|
| A, serialize | 1.5 MB | 0.7 MB | 0.7 MB |
| A, template | 3.3 MB | 1.8 MB | 1.6 MB |
| B, serialize | 8.1 MB | 4.2 MB | 4.0 MB |
| B, template | 34.3 MB | 17.1 MB | 16.5 MB |
| C, serialize | 20.1 MB | 10.2 MB | 9.8 MB |
| C, template | 35.0 MB | 17.6 MB | 17.0 MB |

A worker now costs one copy of its globals, where it cost two.

With 4 workers, VmRSS and VmHWM 3 s after listening, each build from `git archive`:

| Tier | VmRSS before | after | VmHWM before | after |
|---|---:|---:|---:|---:|
| B, serialize | 35.1 MB | 19.5 MB | 50.2 MB | 28.6 MB |
| B, template | 136.0 MB | 70.0 MB | 163.6 MB | 109.0 MB |
| C, serialize | 81.9 MB | 42.9 MB | 102.5 MB | 68.9 MB |
| C, template | 139.6 MB | 71.8 MB | 176.2 MB | 107.5 MB |

The peak sits above idle by the distributor's set and one queued copy, during startup.
Before the distributor, with the loader handing out the sets while it still held its
parse buffers, tier C templated peaked at 127.6 MB.

No request runs changed code: the handlers and loops are as before, and
`bench/codegen.sh findings-46356c2-hot task-025-worker-load` (at `9d4d36c`) found the
request path's functions within 32 bytes.

Rates, against `findings-46356c2-hot` with `main` merged (`e047040`, f) at `b10cf60`
(w): `bench/rest.sh run` with `STEPS="1 2 4" RATE_C=16000`, uring, 4 workers on CPUs 0-3
and the load on 4-15, 3 rounds of 15 s, on 2026-10-14 in the daytime with the machine
not kept quiet, each server built from `git archive` of its commit
([summary](../bench/results/2026-10-14-rest-027-025/summary.md); the batch is task
027's "The pending branches at Goose `46356c2`"). Medians and the rounds' range:

| Cell | f, req/s | peak RSS | w, req/s | peak RSS |
|---|---:|---:|---:|---:|
| A serialize | 580.5K (576.6-584.7K) | 15 MB | 579.2K (551.0-580.6K) | 12 MB |
| A template | 593.0K (591.7-597.4K) | 23 MB | 576.8K (567.8-590.2K) | 16 MB |
| B serialize | 274.2K (268.9-274.9K) | 51 MB | 269.3K (266.0-270.5K) | 30 MB |
| B template | 380.4K (369.9-385.4K) | 165 MB | 374.8K (357.4-377.0K) | 111 MB |
| C serialize | 49.9K (49.8-50.5K) | 104 MB | 49.5K (49.3-50.1K) | 70 MB |
| C template | 143.5K (142.6-144.7K) | 177 MB | 143.0K (142.3-146.3K) | 112 MB |
| Uploads alone, p50 | 16.4-16.9 ms | 103 MB | 16.2-16.7 ms | 70 MB |
| Uploads beside forms | 145-151/s | 164 MB | 156-162/s | 125 MB |
| Uploads beside tier C | 705-715/s | | 718-732/s | |

Every range overlaps f's but A templated's, 2.7% under, where w's highest round,
590.2K, is just below f's lowest, 591.7K. `main` read 585.9K (575.5-589.5K) there in
the same batch, and w's range overlaps it; no request runs code w changes, so this
reads as the rounds' spread. Peak RSS falls by 20-41% in every cell: on tier C
templated from 177 to 112 MB.

Not done: dropping the record arrays a templated worker never reads. Tier C's templated
routes still select by the records (bookings, shifts, visits, clients, and
`staffers.len`); only `notes` would go, read for its `kind` alone, and the dataset has
at most about 5,100 notes, about 0.2 MB a worker.

## The templates in a shared store (2026-10-14)

Goose shares only static data between threads (spec §11.2), so the queue hand-off above
is as low as Goose alone goes: one copy of a worker's globals each. Asked for
2026-10-14: the server keeps its prebuilt JSON in a store in C that every worker reads,
one copy for the process. The store is the package's, `store.goose` and `shim/store.c`
(decided 2026-10-14), so goose-rest and task 031's shared module get its C with the
import. The loader builds the JSON in
Goose as before, puts each `*_json` array in the store, empties its own, and freezes
the store; the blobs' ids go to the workers in `Flags`, through the queues, which
order the store's writes before the reads. Each template read copies its range into
the response through `store_append`, a bounds check and a `memcpy` in C. Building the
responses stays Goose. Loading the data from disk per request was rejected: it moves
the memory into the page cache, out of RSS, and adds a syscall per response.
`test/test_store.goose` tests the store, run by `scripts/test-unit.sh`.

`bench/` is now out of the package (`exclude` in `http.build`): the package's library
links the `extern fn`s of every file under its root, and the server's `mallopt`, which
Windows lacks, broke every in-process test there (found 2026-10-14).

Measured on the desktop: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose
`46356c2`, at `d7c9b91`, with the store in the server's directory, the same way as the
section above: `bench/rest-memory.sh`
([split](../bench/results/2026-10-14-rest-memory-store/memory.tsv)), 1 and 2 workers,
epoll, idle, one run each, and VmRSS and VmHWM with 4 workers 3 s after listening.
`bench/rest/check.py` passes every tier, both JSON ways, both loops, 4 workers.

Each added worker, idle (2 workers less 1):

| Tier | Queues | Shared store |
|---|---:|---:|
| A, template | 1.8 MB | 0.1 MB |
| B, template | 17.1 MB | 4.7 MB |
| C, template | 17.6 MB | 1.7 MB |

Serialized tiers don't change: they have no templates. In the store, once for the
process: 11.8 MB on tier B and 15.2 MB on tier C.

4 workers, 3 s after listening:

| Tier | VmRSS, queues | VmRSS, store | VmHWM, queues | VmHWM, store |
|---|---:|---:|---:|---:|
| B, template | 70.0 MB | 34.6 MB | 109.0 MB | 50.2 MB |
| C, template | 71.8 MB | 26.4 MB | 107.5 MB | 57.6 MB |

Tier C templated now holds less than hyper's 62 MB idle up to about 24 workers: 21.4 MB
with one, and 1.7 MB more for each added. `bench/codegen.sh 3ee50dd d7c9b91`: the benchmark server's code is the
same; in this server, each template read is one of 43 calls to `store_append`, which
gcc can't inline from its own file, and the template routes' functions shrink slightly
(`.text` 13 KB smaller in all).

Rates, in the batch of the section above, at `effcd47` (s, with w merged) against
`b10cf60` (w), as a variant labeled `goose-uring-27s`
([summary](../bench/results/2026-10-14-rest-027-025/summary.md)):

| Cell | w, req/s | peak RSS | s, req/s | peak RSS |
|---|---:|---:|---:|---:|
| A serialize | 579.2K (551.0-580.6K) | 12 MB | 580.6K (573.8-580.9K) | 12 MB |
| A template | 576.8K (567.8-590.2K) | 16 MB | 588.7K (583.9-593.4K) | 12 MB |
| B serialize | 269.3K (266.0-270.5K) | 30 MB | 271.7K (269.9-277.5K) | 30 MB |
| B template | 374.8K (357.4-377.0K) | 111 MB | 380.7K (375.5-392.3K) | 50 MB |
| C serialize | 49.5K (49.3-50.1K) | 70 MB | 49.7K (49.1-50.3K) | 71 MB |
| C template | 143.0K (142.3-146.3K) | 112 MB | 144.8K (142.7-146.4K) | 58 MB |
| Uploads alone, p50 | 16.2-16.7 ms | 70 MB | 16.4-17.1 ms | 70 MB |
| Uploads beside forms | 156-162/s | 125 MB | 151-160/s | 125 MB |
| Uploads beside tier C | 718-732/s | | 697-712/s | |

s's medians are at or above w's at saturation, every range overlapping, so the copy
through `store_append` costs no rate. Templated peaks fall from 111 to 50 MB on tier B
and from 112 to 58 MB on tier C, under hyper's 74 MB serving. Uploads beside tier C read
2-4% under w's, ranges apart; tier D's server serializes, so it runs none of the store's
code, and f read 705-715 there in the same batch.

On `main` at `1818526`, idle on the epoll loop, VmRSS 3 s after listening, one run each
([idle.tsv](../bench/results/2026-10-14-rest-idle-main/idle.tsv)), in MB:

| Tier, JSON | 1 worker | 2 workers | 4 workers |
|---|---:|---:|---:|
| A, serialize | 4.1 | 4.8 | 6.4 |
| A, template | 5.2 | 5.3 | 5.6 |
| B, serialize | 7.7 | 11.7 | 19.9 |
| B, template | 20.5 | 25.5 | 35.4 |
| C, serialize | 13.5 | 23.6 | 43.9 |
| C, template | 21.4 | 23.2 | 27.0 |

With 4 workers, tier C templated holds 27 MB where `main` held 379 MB before this task.

## Acceptance criteria

- [ ] Each worker's share split by source (records, templates, buffers, runtime), with
      task 016's per-worker baseline
- [x] Main's copy released after spawn, or recorded why it can't be: it can't, so the
      records load on a thread that returns once the workers start
- [x] Records and templates compacted where it costs no requests per second, measured on
      tiers A to C before and after
- [ ] The sharing question asked, and the answer in `docs/goose-findings.md`: not
      asked yet (asked for 2026-10-14: nothing goes to the maintainer until allowed)
