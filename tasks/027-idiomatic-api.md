# 027: A more idiomatic API

Status: in progress (asked for 2026-10-13). The maintainer decided what stays
(2026-10-13, "Decisions" below). p1 is reverted, and p7 dropped. p2, p4, p5, and p6
are on `main`, cherry-picked without p1 and p3 and checked by neither tests nor
benchmarks since, which waited on another session's runs (asked for 2026-10-13: merge
what is kept, and keep what needs deciding on a branch until it can be benchmarked).
p3 waits on `task-027-p3`. Next: `scripts/test.sh` on `main`, then steps 2, 5, 6, and
7 below, then the examples and docs. Breaking changes cost least before programs use
the API, and goose-rest will be the first.

## Decisions

The maintainer's answers to the open questions (2026-10-13). An idiom that costs
speed doesn't land, however idiomatic: record it in `docs/goose-findings.md` as one
this package would use if Goose made it free.

1. Revert p1 on `main` with an inverse commit (`git revert a9783c8`), not by rewriting
   history. Keep its `docs/goose-findings.md` entry on the `null` branch, which the
   revert would otherwise remove. After it, `git diff 2afc12f HEAD -- '*.goose'` shows
   only dusty's changes. p2 doesn't win p1's cost back: the two are independent, so p1
   costs its 39.5 instructions per request on epoll and 45.0 on uring with or without
   p2.
2. Add a finding for p1, from a minimal program at `a6249a4` that tells which costs
   the instructions: matching the enum's tag, or the loops passing `const Event?` as
   both the constant `null` and an event, which makes Goose specialize `go`, `drive`,
   `advance`, `pump`, and `answer` twice (`.text` 267 to 424 KB). The growth points at
   the second. The finding names the idiom and what it would replace.
3. Rebase `task-027` onto the new `main`, keeping p2, p4, p5, and p6. Cherry-picking
   onto a fresh branch is simpler than a rebase, since the branch holds a merge
   (`0bedc15`) and a copy of `main`'s `04791ac` (`e886805`).
4. Drop p7 (`927a268`): its reason was 15 lines fewer, and it came out 16 longer.
5. Drop p3 (`dfc4a00`) unless a quick tier D run without p1 shows its upload loss
   gone: uploads beside tier C took 670-737 a second against the baseline's 781-786.
   p5 (`a3b8744`) builds on p3's `BodyReader.Raw`, so its conflicts are resolved by
   hand. Record each dropped proposal under its bullet with its cost (step 4 below).
6. Check p2's 3-6% on uploads again without p1. If it holds, `perf stat` the
   instruction-cache and iTLB misses, p2 against the baseline, before calling it
   layout.
7. Benchmark the rebased series against `2afc12f`: the numbers below for p2 on were
   measured on top of p1.

Done: step 1 (`c16cca6`), step 3 for what is kept, and step 4. p3 waits on
`task-027-p3`, cut from `main` after p6, with p5's `Framing.Raw` test carried onto
`BodyReader.Raw`.

### Pending

What `main` holds unchecked, or what waits on a branch. Remove an item once its check
passes.

- [ ] `scripts/test.sh` in WSL and Git Bash on `main`, where p2, p4, p5, and p6 were
      cherry-picked without p1 and p3 and their conflicts resolved by hand.
- [ ] Step 2: the finding for p1's cost, from a minimal program at `a6249a4`.
- [ ] Step 5: a tier D run of `task-027-p3` without p1, which merges p3 or drops it.
- [ ] Step 6: p2's upload cost without p1, and `perf stat` of its cache misses if it
      holds.
- [ ] Step 7: the series on `main` against `2afc12f`.

Baseline: `2afc12f`, the Goose pin moved to `a6249a4` (2026-10-13), with
`scripts/test.sh` passing in WSL and Git Bash. The proposals' benchmarks compare
against it.

goose-http was written for correctness and speed, partly before Goose had features
that fit it better. A review against the Goose docs and code at `a6249a4` (2026-10-13,
for goose-rest's plan) proposed the changes below. Each lands only if its benchmark
shows speed and memory hold (`docs/architecture/README.md`, "The API isn't frozen").
The task then rewrites the examples and the API reference for the API that results.

## How a change is validated

1. Before the first change, record a baseline on the benchmark desktop, at the Goose
   pin the comparisons use (a pin move between baseline and comparison means a new
   baseline): `scripts/test.sh`, `bench/instructions.sh`,
   plaintext and JSON from `bench/run.sh`, and the tiers of `bench/rest.sh` that the
   proposals below name.
2. Each proposal is its own commit, with its tests, the README, `examples/`, and
   `server/` updated in the same commit, on the `task-027` branch until its benchmarks
   hold (asked for 2026-10-13). Before the commit, `bench/codegen.sh` against the
   baseline and the commit before, looking for new specializations and growth in the
   loops' hot functions (asked for 2026-10-13).
3. After each, run `scripts/test.sh` on Linux and macOS. The proposals' checks run in
   an overnight batch, each at its own commit, compared with the baseline, using
   `bench/count.sh` for instructions (`docs/development.md`, "Move the pin"). Record the numbers
   here, with how they were measured (`AGENTS.md`, "Benchmarks").
4. A proposal that costs speed or memory beyond the runs' noise is reverted. Record what
   it cost here and why it was dropped, so it isn't proposed again.

## Proposals

Breaking changes first, so the API breaks in one stretch. Costs and gains are the
review's estimates; "unverified" marks what no program has checked yet.

- [ ] **`Event` as a fixed-mode enum**, each variant carrying only what applies
      (`Request{req, data, whole, trailers}`, `Body{data}`, `Wake{data, tag}`,
      `Done{status, sent, ms}`, and so on). Removes the placeholder requests `gone`,
      `none`, and `nothing` (`http.goose:340`, `373`; `epoll.goose:77-78`) and
      `NO_EVENT`, and a handler can no longer read `req` at `BODY`. Breaks the API
      across `http.goose`, the loops, the routes, the tests, and the README.
      Unverified: that tag dispatch costs what the `u8` compare does now. Check:
      `bench/instructions.sh` against the recorded ~1,460 per request, and plaintext and
      JSON in `bench/run.sh`.
      Done (2026-10-13), not yet benchmarked; `scripts/test.sh` passes in WSL and Git
      Bash. `Done` keeps `req`, as `const Request?`, null where the response wasn't
      whole at `Request`: the access log prints its target (asked for 2026-10-13). The
      loops pass the wake as `const Event?` and keep a flag for whether it's still owed:
      a `var` reference rebound to `null` counts under spec §5.1 as one that may point
      into the write buffer they shrink. A typed local works around a `null` branch
      that doesn't take the optional's type (`docs/goose-findings.md`). `bench/rest`'s
      server changes with it. Commit `a9783c8`, pushed to `main` before its codegen
      check; `main` keeps it (2026-10-13), and later proposals go to `task-027`.
      Codegen (`bench/codegen.sh`, against `2afc12f`): the Request path's C builds the
      event's four fields where it built nine, and the handler's `match` on a tag that's
      constant there folds away. But `.text` grew from 267 to 424 KB: Goose now
      specializes `go`, `drive`, `advance`, `pump`, and `answer` once with `wake` the
      constant `null` and once with an event, and `answer`'s nested `call`, which holds
      the whole inlined handler (about 17 KB), three times where it did twice. In
      machine code, `answer` grew from 4,821 to 4,994 instructions on epoll and from
      4,862 to 5,145 on uring, cold branches included. Whether a request pays for it
      is for `bench/count.sh` to say.
      Dropped (2026-10-13): it costs 39.5 user instructions per request on epoll and
      45.0 on uring (`bench/count.sh`, below), with or without p2, and no rate shows a
      gain for it. Reverted on `main` by `c16cca6`.
- [ ] **Request helpers take `const Request&`**, not `Request` by value: `field_of`
      (`message.goose:225`), `cookie_of` (`cookie.goose:39`), `authorization`
      (`auth.goose:16`), `has_type` (`media.goose:124`), and `range_of`
      (`message.goose:1148`). `Event.req` became a reference to save the same copy,
      about 20 instructions per request. Unverified where gcc inlines them anyway.
      Check: `bench/rest.sh` tiers B and C.
      Done (2026-10-13), not yet benchmarked; `scripts/test.sh` passes in WSL and Git
      Bash. Every package function that reads a request takes it so, 21 in all, as
      `router` and `upgrade_of` already did; the servers' own functions are unchanged,
      so the check measures the package alone. A call's result can't be passed
      straight to one (the struct-literal finding), so the tests bind it to a local
      first. Codegen against `a9783c8`: `answer` drops to 4,447 instructions on epoll
      and 4,568 on uring, below the baseline, and `.text` to 381 KB; in `bench/rest`'s
      server, `cookie_of` inlines away, `has_bearer`, which still takes a copy, goes
      from one 300-byte copy to four, and the `answer`s grow by 12 KB. Commit `070e830`.
- [ ] **`BodyReader.place` as an enum** (`message.goose:484-495`): `Length{left}`,
      `ChunkData{left}`, `ChunkSize`, and so on, so `read_body`'s cases are checked as
      complete and `left` exists only where it means something. Check: tier D's uploads.
      Done (2026-10-13), not yet benchmarked; `scripts/test.sh` passes in WSL and Git
      Bash. `BodyReader` is the enum itself, with `None` for no body, since a struct
      around one field added nothing. `read_body` matches it and writes the next
      variant whole, as fixed mode requires. The loops test `x.body ==
      BodyReader.None`, whose generic equality gcc folds to a tag compare: no call to
      it is left in either binary. A variant with a payload has a type of its own and
      doesn't compare with `==` against the enum, so tests `match` it. Codegen against
      `070e830`: `answer` grows by 175 instructions on epoll and shrinks by 81 on
      uring; `.text` grows by 1 KB. Commit `dfc4a00`. Waits on `task-027-p3` for a
      tier D run without p1 ("Decisions", step 5).
- [ ] `PART_HEAD`, `PART_DATA`, and `PART_END` (`form.goose:31`) as an enum
      `Part { Head{fields}, Data{bytes}, End }`. Taste. Check: tier D.
      Done (2026-10-13), not yet benchmarked; `scripts/test.sh` passes in WSL and Git
      Bash, and `bench/rest/check.py` every tier on both loops. `each_part` calls its
      function with one `Part`, typed as the enum before the call, so the function
      isn't instantiated per variant. Codegen against `dfc4a00`: the benchmark
      server's code doesn't change; in `bench/rest`'s, gcc inlines one `read_parts`
      into `attach_piece`, 3 KB more in all.
- [ ] `Stream`'s `chunked`, `raw`, and `left` as one framing enum. Taste. Check: the
      streaming routes' tests and `bench/files.sh`.
      Done (2026-10-13), not breaking: `Stream.framing` is `Framing { Length{left},
      Chunked, Close, Raw }`, `Close` for a body that ends with the connection (HTTP/1.0
      without a length). `scripts/test.sh` passes in WSL and Git Bash. Codegen against
      `0962213`: `send` 370 bytes smaller, `end` 128 larger, the loops' hot functions
      within 3 instructions. `bench/count.sh`, 2 runs: 1,824.6 and 1,873.1 user
      instructions per request, p3's to the tenth. `bench/files.sh`, one worker, 64
      connections, 3 runs of 10 s, p3 against p5
      ([summary](../bench/results/2026-10-13-desktop-027-files/summary.md)): every
      cell within the runs' spread; the lowest, bytes:1048576 on uring, 2.62 GB/s
      against 2.70 (2.52-2.73). On `main` it comes before p3, so `answer` sets the
      `BodyReader` struct's `RAW` place from `Framing.Raw`.
- [ ] **Typed mail.** `mail_send_value<T>(to, tag, v)` over `to_bytes`, and a
      `from_bytes<T[>..]>` decode on take, checked by the language's verifier. Replaces
      `put`, `got`, `encode`, and `decode` in `server/backend.goose:22-48`. Additive,
      one framed copy per message on a cold path. Unverified: whether a limited
      array's image includes its unused capacity. Check: the `/later` and `/events`
      tests.
      Done (2026-10-13), additive: `http::mail_send_value(to, tag, v)` sends a
      one-element array's `to_bytes` image, and `http::mail_value(bytes, out)` reads it
      back into the caller's variable, since a generic function can't build a `T` to
      return on failure. A limited array's image does take its whole capacity: the
      backend's job is 74 bytes where its hand encoding took 35 with a 3-byte id, so
      `JOB_SIZE` grows from 64 to 80, and the workers' boxes, which hold replies, keep
      64 as `REPLY_SIZE`. The backend clamps delay and count after decoding, as
      `decode` did. `scripts/test.sh` passes in WSL and Git Bash, whose `later` mode
      runs `/later` and `/events` with `MAIL_SLOTS` set.
- [ ] Loop setup in `serve_epoll` and `serve` (`epoll.goose:41-72`) as a nested
      `fn setup()` caught by an `Error[]` handler, in the stdlib `exception` module's
      pattern: file descriptors start at -1, with one cleanup site. `Error.call` is
      always a literal, which a long-distance return may carry. About 15 lines fewer,
      on a cold path. Taste.
      Dropped (2026-10-13): built as `927a268`, a nested `setup()` that throws to
      `exception::try<Error>` and a nested `release()`, it came out 16 lines longer,
      not 15 shorter, because the descriptors are declared before `setup` and
      `release` adds its own lines. Its reason was the line count.

A proposal the work turns up later joins this list with its check before it lands.

## The breaking proposals' benchmarks

Run on the desktop on 2026-10-13, once the four breaking proposals were in (asked for
2026-10-13: fast checks first, and only what's needed). Each revision is built into a
name of its own, both loops, with the Goose pin at `a6249a4`:

| Build | Commit | Benchmark server | REST server |
|---|---|---|---|
| base | `2afc12f` | `build/bench/goose-27base[-uring]` | `build/rest/rest-goose-base` |
| p1 | `a9783c8` | `goose-27p1[-uring]` | not built: no tier named |
| p2 | `070e830` | `goose-27p2[-uring]` | `rest-goose-p2` |
| p3 | `dfc4a00` | `goose-27p3[-uring]` | `rest-goose-p3` |
| p4 | `0962213` | the same code as p3 | `rest-goose-p4` |

The commands, run as root in WSL, each build made from `git archive` of its commit with
`scripts/build.sh` (`LOOP=epoll`, then `uring`) and `goose build --cc gcc --standalone`
for `bench/rest/goose/rest.goose`:

```sh
RUNS=3 bench/count.sh goose-27{base,p1,p2,p3} goose-27{base,p1,p2,p3}-uring
RUNS=3 bench/instructions.sh goose-27{base,p1,p2,p3} goose-27{base,p1,p2,p3}-uring
SERVERS="goose-27base goose-27p1 goose-27p3 goose-27base-uring goose-27p1-uring goose-27p3-uring" \
    TESTS="plaintext:256 json:256" LATENCY=0 bench/run.sh
SERVERS="goose-uring-base goose-uring-p2 goose-uring-p3 goose-uring-p4 hyper dusty" \
    RATE_A=140000 RATE_B=74000 RATE_C=16000 bench/rest.sh run
```

`bench/rest.sh` runs a `goose-uring-TAG` server from `build/rest/rest-goose-TAG`. The
REST run's fixed rates are the 2026-10-13 rerun's, so dusty's cells, which task 021
asked for, sit beside the existing tables, with hyper as the anchor.

### Instructions and memory

Ryzen 7 5800X3D, WSL2 kernel 6.18.40.1, gcc 15.2.0, one worker on CPU 0. `bench/count.sh`:
10 million plaintext requests from h2load 1.68.0 (CPUs 4-15, 8 threads, 256
connections, 16 in flight each), 3 runs, which repeat to 0.1 instruction
([runs](../bench/results/2026-10-13-desktop-027-count/runs.tsv)). `bench/instructions.sh`:
wrk 4.1.0 pipelining 16 deep at 256 connections for 20 s, perf on CPU 0 for 10 s, 3 runs
([runs](../bench/results/2026-10-13-desktop-027-instructions/runs.tsv)).

| Build | epoll, user insns/req (count.sh) | uring | epoll, peak RSS KB | uring |
|---|---|---|---|---|
| base | 1,826.9 | 1,875.2 | 2,448 | 4,896-4,992 |
| p1 | 1,866.4 (+39.5) | 1,920.2 (+45.0) | 2,512-2,544 | 4,928-4,996 |
| p2 | 1,822.4 (-4.5) | 1,874.1 (-1.1) | 2,448-2,484 | 4,768-4,980 |
| p3 | 1,824.6 (-2.3) | 1,873.1 (-2.1) | 2,476-2,540 | 4,632-4,876 |

`bench/count.sh`'s user cycles per request: base 476-478 on epoll and 445-454 on uring;
p1 486-494 and 438-442; p2 461-465 and 426-428; p3 459-482 and 423-442.

p1 alone costs about 40 instructions per request on each loop, beyond any noise of
these counts, which step 4 above would revert. p2 more than wins it back, and the
series from p2 on is at or under the baseline in instructions and cycles, with memory
within 100 KB. A sampled profile (`perf record`, instructions) puts p1's extra in
`answer`; where in it isn't found yet. p1 must hold on its own, and p2's gain doesn't
depend on it, so p1 was reverted ("Decisions", step 1).

### Plaintext and JSON

`bench/run.sh`, same machine, wrk 4.1.0 for 15 s after 5 s of warm-up, server on CPUs
0-3 and wrk on 4-15 with 8 threads, 3 runs, latency left out, medians
([summary](../bench/results/2026-10-13-desktop-027-run/summary.md)), in millions of
requests per second:

| Test, workers | base | p1 | p3 | base, uring | p1, uring | p3, uring |
|---|---|---|---|---|---|---|
| plaintext:256, 1 | 1.853 | 1.869 | 1.888 | 2.058 | 2.090 | 2.074 |
| plaintext:256, 4 | 5.553 | 5.479 | 5.663 | 6.811 | 6.849 | 6.984 |
| json:256, 1 | 0.144 | 0.147 | 0.146 | 0.167 | 0.168 | 0.173 |
| json:256, 4 | 0.419 | 0.420 | 0.426 | 0.506 | 0.501 | 0.511 |

Every cell is within the runs' spread of the baseline. p3 is at or above it in all
eight, by 0.8-2.6%; p1 is from 1.3% under to 1.8% over, so its 40 instructions don't
show in a rate. Peak RSS is the same to 0.1 MB.

### REST

`bench/rest.sh run` with `SERVERS="goose-uring-base goose-uring-p2 goose-uring-p3
goose-uring-p4 hyper dusty"` at the fixed rates above, 4 workers on CPUs 0-3, the load
on 4-15, 3 rounds of 15 s, the uring loop
([summary](../bench/results/2026-10-13-rest-027/summary.md)). Medians at saturation,
and tier D's uploads:

| Cell | base | p2 | p3 | p4 |
|---|---:|---:|---:|---:|
| A serialize | 598.6K | 592.7K | 591.3K | 590.2K |
| A template | 609.8K | 602.9K | 608.0K | 603.4K |
| B serialize | 272.2K | 276.7K | 272.0K | 278.8K |
| B template | 386.8K | 385.8K | 380.9K | 385.4K |
| C serialize | 53.1K, 75.4 µs | 54.1K, 73.9 µs | 51.7K, 77.3 µs | 54.2K, 73.7 µs |
| C template | 149.2K | 149.9K | 147.4K | 149.0K |
| Uploads alone, p50 | 15.8-16.6 ms | 16.3-16.9 ms | 16.5-17.8 ms | 16.4-17.3 ms |
| Uploads beside forms | 162-164/s | 155-159/s | 154-160/s | 161-163/s |
| Uploads beside tier C | 781-786/s | 733-750/s | 670-737/s | 722-748/s |

Peak RSS is the same in every cell. Tiers A to C hold for every proposal: within 1.5%
of the baseline but p3's C, 2.6% under on serialize and 1.2% on templates, which p4,
whose change no tier C request runs, doesn't share, so code layout is the likelier
cause. p2 gains 1.7-1.9% on B and C serialized, which it was meant to check.

Uploads cost 3-6% from p2 on. A second tier D run with the order reversed
(`STEPS=2`, p2 first, and p1's REST server added,
[summary](../bench/results/2026-10-13-rest-027-uploads/summary.md)) repeated it: p50
alone base 15.8-16.2 ms, p1 16.0-16.8, p2 16.7-17.7. perf stat on the server, uploads
alone for 10 s, twice each: p1 and p2 spend the same user instructions per upload,
39.6-39.9 M, but p2 1-3% more cycles. p2 changes no code an upload's body runs
through, and an upload spends its 40 M instructions in the body, so this too looks like
code layout; it isn't pinned down. p2 stays, and its upload cost is measured again
without p1 ("Decisions", step 6).

## Examples and docs

Once the proposals are settled:

- [ ] `examples/README.md` describes the API as it now is, and its snippets compile.
- [ ] New examples beside `hello` and `routes`, each a short program a reader can copy:
      a JSON API with path parameters, a body, cookies, and bearer auth; an upload read
      as a stream and as multipart; an answer that waits on a backend thread over mail;
      and files with ranges and conditional requests.
- [ ] `scripts/test.sh` builds every example and requests each route once, so an API
      change can't leave an example broken.
- [ ] The README's quick start and concepts match the examples.

## Kept as they are

The review looked at these and found reasons to keep them:

- The `exception` module on hot paths. `parse`'s early returns have no frames between
  to unwind, `handler<E>` would build an `E[]` per request, and `try` passes its body on
  by name, which keeps it and its callers out of line (found in goose-rest's spike 04).
  `each_part` and `read_body` already use `json::Reader`'s sticky-failure idiom.
- `Exchange<S>`'s flags and the connection slot in a `reusable` pool. The loops hold
  references into slots, which a fixed-mode enum forbids (spec §3.5).
- The C mailbox over `qput` and `qget`, for the reasons in the architecture doc.
- The status-line `match`, the byte loops around `find_any`, and `parse` without
  `simd`, each backed by measurements in the findings.
- `Config` as one flat struct with limited-array strings, as `thread_spawn` needs.
- `Reply` as a struct of references: the spec's one-context pattern (Appendix A.6).
