# 025: The REST server's memory per worker

Status: todo (asked for 2026-10-13)

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
4. One data thread that workers mail, as task 023 plans for a shared cache: one copy,
   at the cost of a mailbox round trip per read, and on tier C every response's JSON
   built on that one thread. That measures Goose's concurrency model rather than its
   HTTP layer, so it belongs beside the main cells as a variant, with task 023, not in
   their place.

## Acceptance criteria

- [ ] Each worker's share split by source (records, templates, buffers, runtime), with
      task 016's per-worker baseline
- [ ] Main's copy released after spawn, or recorded why it can't be
- [ ] Records and templates compacted where it costs no requests per second, measured on
      tiers A to C before and after
- [ ] The sharing question asked, and the answer in `docs/goose-findings.md`
