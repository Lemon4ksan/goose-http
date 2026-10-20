# 027: A more idiomatic API

Status: in-progress (asked for 2026-10-13). The maintainer decided what stays
(2026-10-13, "Decisions" below). p1 is reverted, and p7 dropped. p2 to p6 are on
`main`, tested and benchmarked at Goose `0bdbd18` (2026-10-14, "The series at Goose
`0bdbd18`" below). The four new examples are on `main`, built and run by
`scripts/test.sh` (2026-10-14), and the README matches them. Of the follow-up review's
eleven items ("Examples and docs" below), 1, 2, 4, and 6 to 11 are on `main`, and 5 was
kept as it is, with tests (2026-10-14). Items 7 to 11 hold on a recheck (2026-10-14).
Item 3 is dropped: it cost the epoll loop 13.8 instructions a request and showed no
gain of its own. Breaking changes cost least before programs use the API, and
goose-rest will be the first.

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

Steps 1 to 7 were resolved on 2026-10-14; p3 was kept and merged. The numbered
instructions above record the original decisions, not branches still waiting to merge.

### Pending

The implementation and examples are on `main`. The tier C templated rate, 3.3% below
the baseline in the recorded comparison, still needs the next REST run's recheck.
Keep this task open until that result is recorded; completed merges do not settle it.

The main-against-README comparison (2026-10-14) is recorded in
[results](../docs/results.md#2026-10-14-main-against-the-readme-benchmark-build).
Its C templated ranges overlap on both loops, but its baseline is `e4f7b55`, not
`2afc12f`, so it does not settle the original series' recheck. Task 033 will
attribute the newer serialized B/C and mixed-upload regressions before judging
the responsible API changes.

The last branches merged into `main` as `1818526`, in this order, each once its
benchmarks held, and were deleted here and on GitHub:

- `findings-46356c2-hot`: the workarounds on a request's path that Goose `46356c2`
  made unneeded (`http::whole` taking the handler, `INTERIM`, `pos += k` in `parse`,
  `each_cookie` over `each_field`, `bench/rest`'s string constants), and `respond`
  with no `Content-Type` for an empty one. Multipart keeps `find_bytes` ("f's tier D,
  again" below).
- `task-025-worker-load` and `task-025-shared-templates` (task 025): REST workers take
  their records over the typed queues, and the templated tiers' JSON sits in the
  package's shared store, `store.goose` over `shim/store.c` (merged at the
  maintainer's call, 2026-10-14).
- `api-hot`, review item 3, was dropped instead.

`scripts/test.sh` passes on `1818526` in WSL and Git Bash.

Before these, `main` at `48f8e37` spent 8 user instructions per request more
than the baseline ("The series at Goose `0bdbd18`"); at `e4f7b55`, with 022.03's routes
in the benchmark server, it spends 1,833.1 on epoll and 1,888.5 on uring against the
baseline's 1,838.9 and 1,887.2 (`RUNS=3 bench/count.sh`, 2026-10-14,
[results](../docs/results.md#2026-10-14-main-after-tasks-02203-025-and-027)), so where
the 8 went wasn't pinned down: a sampled profile's addresses didn't resolve to symbols.

Done on 2026-10-14, at Goose `0bdbd18` on kernel 6.18.54.1: `scripts/test.sh` on
`main` in WSL and Git Bash; step 2, the finding
([An optional passed as `null` at one call and a value at another specializes twice](../docs/goose-findings.md#an-optional-passed-as-null-at-one-call-and-a-value-at-another-specializes-twice));
step 5, p3 kept and merged; step 6, p2's upload cost gone; and step 7, the series on
`main` against `2afc12f`, whose rates overlap the baseline's ranges but tier C
templated's, 3.3% under, which the next REST run checks again.

Baseline: `2afc12f`, rebuilt at each Goose pin the comparisons use, `0bdbd18` since
2026-10-14.

goose-http was written for correctness and speed, partly before Goose had features
that fit it better. A review against the Goose docs and code at `a6249a4` (2026-10-13,
for goose-rest's plan) proposed the changes below. Each lands only if its benchmark
shows speed and memory hold (`docs/decisions.md`, "The API isn't frozen").
The task then rewrites the examples and the API reference for the API that results.

## How a change is validated

1. Before the first change, record a baseline on the benchmark desktop, at the Goose
   pin the comparisons use (a pin move between baseline and comparison means a new
   baseline): `scripts/test.sh`, `bench/instructions.sh`,
   plaintext and JSON from `bench/run.sh`, and the tiers of `bench/rest.sh` that the
   proposals below name.
2. Each proposal is its own commit, with its tests, the README, `examples/`, and
   `server/` updated in the same commit, on the `task-027` branch until its benchmarks
   hold (asked for 2026-10-13). Since 2026-10-14 it goes to `main` once its tests pass,
   with its benchmarks recorded when they come (`AGENTS.md`, "Commits"). Before the commit, `bench/codegen.sh` against the
   baseline and the commit before, looking for new specializations and growth in the
   loops' hot functions (asked for 2026-10-13).
3. After each, run `scripts/test.sh` on Linux and macOS. The proposals' checks run in
   an overnight batch, each at its own commit, compared with the baseline, using
   `bench/count.sh` for instructions (`agents/pins.md`). Record the numbers
   here, with how they were measured (`agents/benchmarks.md`).
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
      that doesn't take the optional's type. `bench/rest`'s
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
      uring; `.text` grows by 1 KB. Commit `dfc4a00`, rebased onto `48f8e37` as
      `0e1f564`. Kept (2026-10-14): without p1 its upload loss is gone, uploads beside
      tier C at 649-711 a second against main's 674-736, and its instructions per
      request are main's to the tenth ("The series at Goose `0bdbd18`", below). Its
      JSON on one epoll worker read 8% under main's in the first run, 0.122 M against
      0.133 M; run again, both were 0.131 M (`bench/run.sh`, `TESTS="json:256
      plaintext:256" WORKER_COUNTS=1`, 3 runs,
      [summary](../bench/results/2026-10-14-027-json-recheck/summary.md)). Merged into
      `main`.
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

- [ ] **A `Router` built once, not per request.** `router(req)` returns `Router {
      .., params: [], allow: [] }`, whose nested fixed arrays (`params: Param[..8]`, 264
      bytes, and `allow: u8[..96]`) the literal zeroes and copies whole, as
      goose-compress found for its encoder
      ([its findings](https://github.com/kaitk/goose-compress/blob/main/docs/goose-findings.md#a-struct-literal-copies-each-nested-fixed-array-whole)):
      `bench/codegen.sh work` at `48f8e37` shows three `rep stos` (about 728 bytes) and
      two `rep movsq` (256 bytes, then about 387 for the return) in `http_router` of
      `bench/rest`'s server, which calls it once per request. The benchmark server has
      no router and no such literal on its path (2026-10-14). The fix: a
      `reset(r: Router&, req)` that sets the fields and clears `params` and `allow` in
      place, with one `Router` per worker, not in the state `S`, which `answer` copies
      per request. Breaking. Estimated 20-40 instructions and 100-250 cycles per routed
      request, unverified. Check: `bench/count.sh` against `bench/rest`'s server on a
      tier A route, then tiers A-C.
      Blocked (2026-10-14, Goose `46356c2`): a `Router` that outlives the request
      can't hold its slices. `reset` storing `req.method` into a worker's `Router` is
      refused: "storing a reference rooted at req, which does not outlive the
      destination (§9.2)". Keeping offsets instead of slices would make `on` and
      `param` take `req` as well, at every call. `inline fn router` instead, built
      with `bench/codegen.sh` against `findings-46356c2-hot`, moves the zeroing into
      each caller: `bench/rest`'s server goes from 40 `rep stos` to 77 and from 122
      `rep movs` to 120, with 22 KB more `.text`, so it was reverted. What costs is
      two open findings: a limited array's `..` default writes its whole capacity,
      and a struct literal is built in temporaries and copied. A fix for either makes
      `router(req)` cheap as it is, with no API change. Nothing was benchmarked.

A proposal the work turns up later joins this list with its check before it lands.

## The pending branches at Goose `46356c2`

Run on the desktop on 2026-10-14, daytime, with the machine not kept quiet: Ryzen 7
5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose `46356c2`. Each build is made from
`git archive` of its commit, the benchmark server with `scripts/build.sh` for both loops
and the REST server with `goose build --cc gcc --standalone`
([batch.sh](../bench/results/2026-10-14-rest-027-025/batch.sh) has every build and
command):

| Tag | Commit | Built from |
|---|---|---|
| e | `e67d92d` | `main` before review items 7 to 11 |
| n | `cb57a0b` | `main` |
| h | `4292f87` | `api-hot`: item 3 on `main` (REST only) |
| f | `e047040` | `findings-46356c2-hot`, with `main` merged |
| w | `b10cf60` | `task-025-worker-load`, with f merged (REST only, task 025) |
| s | `effcd47` | `task-025-shared-templates`, with w merged (REST only, task 025) |

```sh
RUNS=3 bench/count.sh goose-27{e,n,f} goose-27{e,n,f}-uring
SERVERS="goose-27e goose-27n goose-27f goose-27e-uring goose-27n-uring goose-27f-uring" \
    TESTS="plaintext:256 json:256" LATENCY=0 bench/run.sh
SERVERS="goose-uring-27n goose-uring-27h goose-uring-27f goose-uring-27w goose-uring-27s" \
    STEPS="1 2 4" RATE_C=16000 bench/rest.sh run
```

### Instructions

`bench/count.sh`: one worker on CPU 0, 10 million plaintext requests from h2load 1.68.0
(CPUs 4-15, 8 threads, 256 connections, 16 in flight each), 3 runs, which repeat to 0.1
instruction ([runs](../bench/results/2026-10-14-desktop-027-recount/runs.tsv)):

| Build | epoll, user insns/req | user cycles/req | uring, user insns/req | user cycles/req |
|---|---:|---:|---:|---:|
| e | 1,833.1 | 479-481 | 1,888.5 | 427-442 |
| n | 1,835.0 (+1.9) | 513-524 | 1,885.5 (-3.0) | 422-428 |
| f | 1,836.0 (+2.9) | 507-509 | 1,885.4 (-3.1) | 431-441 |

n repeats the first count to the tenth: items 7 to 11 cost no instructions, and their
epoll build again spends 7-9% more user cycles a request than e, where uring's spends
fewer. f spends 1.0 instruction more than n on epoll and 0.1 fewer on uring.

### Plaintext and JSON

`bench/run.sh`: wrk 4.1.0, the server on CPUs 0-3 and wrk on 4-15 with 8 threads, 256
connections pipelining 16 deep, 3 runs of 15 s after 5 s of warm-up, latency left out,
medians and the runs' range in millions of requests per second
([summary](../bench/results/2026-10-14-desktop-027-recheck-run/summary.md)):

| Test, workers | e | n | f | e, uring | n, uring | f, uring |
|---|---|---|---|---|---|---|
| plaintext, 1 | 1.447 (1.442-1.624) | 1.538 (1.518-1.586) | 1.564 (1.469-1.617) | 1.850 (1.841-1.851) | 1.865 (1.864-1.915) | 1.885 (1.808-1.927) |
| plaintext, 4 | 5.090 (4.875-5.265) | 5.181 (4.714-5.280) | 5.245 (4.702-5.260) | 6.784 (5.992-6.831) | 6.786 (6.739-6.919) | 6.820 (6.291-6.840) |
| json, 1 | 0.119 (0.117-0.126) | 0.123 (0.122-0.123) | 0.125 (0.122-0.127) | 0.152 (0.152-0.153) | 0.152 (0.151-0.152) | 0.151 (0.148-0.152) |
| json, 4 | 0.397 (0.373-0.402) | 0.398 (0.368-0.405) | 0.403 (0.372-0.405) | 0.503 (0.469-0.507) | 0.507 (0.476-0.512) | 0.504 (0.450-0.515) |

With 4 workers, one round of nearly every cell fell 6-12% under the other two, the
third on epoll for all three builds: the machine's load, not a build's. Peak RSS is the
same for all three, 3.4 MB with 1 worker and 3.8-3.9 MB with 4 on epoll. n's median is
at or above e's in all eight cells, so items 7 to 11 stay: their epoll cycles don't
show in a rate. f's medians are within the runs' spread of n's in every cell.

### REST

`bench/rest.sh run`, steps 1, 2, and 4, uring, 4 workers on CPUs 0-3 and the load on
4-15, 3 rounds of 15 s, tier C's reads at 16,000 a second in step 4
([summary](../bench/results/2026-10-14-rest-027-025/summary.md)). Medians at
saturation and their range, and tier D; w and s are in task 025:

| Cell | n | h | f |
|---|---:|---:|---:|
| A serialize | 569.8K (558.1-584.9) | 578.1K (551.4-581.8) | 580.5K (576.6-584.7) |
| A template | 585.9K (575.5-589.5) | 580.7K (559.2-593.3) | 593.0K (591.7-597.4) |
| B serialize | 269.9K (259.2-271.8) | 272.7K (254.0-275.6) | 274.2K (268.9-274.9) |
| B template | 371.6K (340.7-378.8) | 373.0K (336.9-387.6) | 380.4K (369.9-385.4) |
| C serialize | 49.0K (46.8-50.0) | 49.8K (44.7-50.1) | 49.9K (49.8-50.5) |
| C template | 141.9K (133.2-142.1) | 144.0K (143.3-144.2) | 143.5K (142.6-144.7) |
| Uploads alone, p50 | 16.3-18.6 ms | 16.0-17.3 ms | 16.4-16.9 ms |
| Uploads beside forms | 159-164/s | 163-168/s | 145-151/s |
| Uploads beside tier C | 726-727/s | 716-720/s | 705-715/s |

Peak RSS is the same for the three in every cell. h gains beyond the rounds' spread
only on tier C templated, 1.5% over n, and f, which lacks item 3's check, gains as much
there, 143.5K; so item 3 shows no gain of its own. f's ranges are above n's on A and C
templated and overlap it elsewhere, but its uploads beside forms are 5-10% under n's,
with uploads alone the same.

### f's tier D, again

f's loss beside forms repeats. `bench/rest.sh run` with
`STEPS=2`, f first, the same servers, 3 rounds
([summary](../bench/results/2026-10-14-rest-027-uploads/summary.md)): uploads beside
forms 141-155/s (median 146) against n's 150-159 (155), forms beside them 6.4-7.1K/s
against 7.0-7.1K, and uploads alone 1.03-1.10K/s against 1.08-1.10K.

`perf stat` on the server, each role alone, two rounds of 10 s, n then f
([perf](../bench/results/2026-10-14-rest-027-uploads-perf/)):

| Role | Build | Rate | User insns/req | User cycles/req | IPC |
|---|---|---:|---:|---:|---:|
| uploads | n | 1,086-1,124/s | 39.7-39.8 M | 13.2-13.6 M | 2.92-3.01 |
| uploads | f | 1,107-1,121/s | 39.9-40.0 M | 13.3-13.4 M | 2.99-3.01 |
| forms | n | 8,573-8,676/s | 6.13-6.17 M | 1.72-1.75 M | 3.54-3.56 |
| forms | f | 8,325-8,370/s | 6.07-6.12 M | 1.79-1.80 M | 3.39-3.40 |

An upload costs f 0.5% more instructions, std's `find` in multipart where
`find_bytes` was, at the same cycles and rate. A form request costs it 1% fewer
instructions but 3-5% more cycles, its IPC 4% lower, and the forms role alone runs
2.4-4.0% slower in both rounds. The uploads beside forms share the workers with it.

f's code changes, each group taken back from `main` in turn on `40ce2a6` (f with
`main` merged), the forms role alone measured the same way, 4 rounds for n, f, and the
`find` group, 2 for the others
([bisect](../bench/results/2026-10-14-rest-027-forms-bisect/)):

| Build | Forms role, req/s |
|---|---|
| n | 8,571, 8,220, 8,466, 8,388 |
| f | 8,342, 7,598, 8,218, 8,154 |
| f, `find_bytes` in `form.goose` | 8,654, 8,355, 8,268, 8,278 |
| f, `each_cookie`'s loop | 8,385, 8,025 |
| f, `parse` and `respond` as before | 7,751, 8,113 |
| f, `whole_only` and string functions | 7,890, 8,204 |

f is 2.7-7.6% under n in every round. With `find_bytes` back it is 1.0-1.6% over n in
the first two rounds and 1.3-2.3% under in the last two, within their spread; no other
group comes back. So std's `find` still costs multipart, in cycles more than in
instructions. `d1f4ffc` keeps `find_bytes` on the branch and the rest of f's changes.
Tier D at `d1f4ffc` (g) against n, `STEPS=2`, g first
([summary](../bench/results/2026-10-14-rest-027-uploads-g/summary.md)): uploads beside
forms 148-155/s against 147-153, forms 6.7-6.9K/s against 6.3-6.9K, and uploads alone
the same. Merged into `main` with that (2026-10-14).

## The review items at Goose `46356c2`

Run on the desktop on 2026-10-14, daytime: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc
15.2.0, Goose `46356c2`. Three builds, each from `git archive` of its branch with
`scripts/build.sh`, both loops: main `e67d92d`, items 2, 4, and 6 on top of
`e4f7b55`; cold `1f00143`, items 7 to 11 on main; and hot `cf03468`, item 3 on main.
The commits after `1f00143` on `api-cold` add tests and a finding only.

```sh
RUNS=3 bench/count.sh goose-27{main,cold,hot} goose-27{main,cold,hot}-uring
SERVERS="goose-27main goose-27cold goose-27hot" TESTS="plaintext:256" LATENCY=0 \
    bench/run.sh
```

`bench/count.sh`: one worker on CPU 0, 10 million plaintext requests from h2load
1.68.0 (CPUs 4-15, 8 threads, 256 connections, 16 in flight each), 3 runs, which
repeat to 0.1 instruction. Epoll's main and cold were counted three more times, 3
runs each, in other orders, and their cycles repeat; the ranges below take in every
run ([runs](../bench/results/2026-10-14-desktop-027-api-count/)):

| Build | epoll, user insns/req | user cycles/req | uring, user insns/req | user cycles/req |
|---|---:|---:|---:|---:|
| main | 1,833.1 | 474-486 | 1,888.5 | 439-455 |
| cold | 1,835.0 (+1.9) | 513-532 | 1,885.5 (-3.0) | 428-431 |
| hot | 1,846.9 (+13.8) | 495-502 | 1,886.2 (-2.3) | 443-448 |

Main spends what `e4f7b55` did to the tenth on both loops, so items 2, 4, and 6 cost
nothing. Cold's instructions hold, but its epoll cycles are 8-9% above main's in every
run, where uring's are lower. Each commit of `api-cold`, built for epoll and counted
3 times: item 7 1,833.1 instructions and 490-498 cycles; item 8 1,832.1 and 527-545;
items 9 and 10 the same as 8, within 526-549. Item 8 changes only the benchmark
server's `/baseline` and `/bytes` routes, which plaintext doesn't run, for
`query_int`'s new result. By `bench/codegen.sh main api-cold`, gcc now inlines
`query_int`, which it had kept out of line, and both loops' `answer` change with it:
4,906 and 4,966 instructions to 4,821 and 4,914. The same routes through the server's own `query_or` bring the
cycles back to 476-489 but cost 21.3 instructions, 1,854.4. Both are the layout of
`answer`, not the work a request does.

`bench/run.sh`: wrk 4.1.0, epoll builds, the server on CPUs 0-3 and wrk on 4-15 with 8
threads, 256 connections pipelining 16 deep, 3 runs of 15 s after 5 s of warm-up,
latency left out, medians and the runs' range in millions of requests per second
([summary](../bench/results/2026-10-14-desktop-027-api-run/summary.md)):

| Workers | main | cold | hot |
|---|---|---|---|
| 1 | 1.597 (1.597-1.622) | 1.614 (1.590-1.657) | 1.620 (1.585-1.638) |
| 4 | 5.178 (5.174-5.204) | 5.119 (4.887-5.122) | 5.135 (5.116-5.139) |

Peak RSS is the same, 3.4 MB with 1 worker and 3.8-3.9 MB with 4. With 1 worker the
three overlap. With 4, cold's and hot's medians are 1.1% and 0.8% under main's, their
ranges just below it. The machine wasn't kept quiet for these runs. Items 7 to 11 were
merged on these numbers at the maintainer's call, and held when measured again ("The
pending branches at Goose `46356c2`").

## The series at Goose `0bdbd18`

Steps 5 to 7, run on the desktop overnight on 2026-10-14: Ryzen 7 5800X3D, WSL2 kernel
6.18.54.1, gcc 15.2.0, with the Goose pin moved to `0bdbd18`. The tables in "The
breaking proposals' benchmarks" below are from kernel 6.18.40.1 and Goose `a6249a4`, so
nothing here compares with them; each run has its baseline beside it. Each build is
made from `git archive` of its commit, both loops, as before:

| Build | Commit | Benchmark server | REST server |
|---|---|---|---|
| base | `2afc12f` | `build/bench/goose-27b[-uring]` | `build/rest/rest-goose-27b` |
| main | `48f8e37`: p2, p4, p5, p6 | `goose-27m[-uring]` | `rest-goose-27m` |
| p3 | `0e1f564`: `task-027-p3`, rebased onto `48f8e37` | `goose-27q[-uring]` | `rest-goose-27q` |

```sh
RUNS=3 bench/count.sh goose-27{b,m,q} goose-27{b,m,q}-uring
SERVERS="goose-uring-27b goose-uring-27m goose-uring-27q" STEPS="1 2 4" RATE_C=16000 \
    bench/rest.sh run
SERVERS="goose-27b goose-27m goose-27q goose-27b-uring goose-27m-uring goose-27q-uring" \
    TESTS="plaintext:256 json:256" LATENCY=0 bench/run.sh
```

### Instructions

`bench/count.sh`: one worker on CPU 0, exactly 10 million plaintext requests from
h2load 1.68.0 (CPUs 4-15, 8 threads, 256 connections, 16 in flight each), 3 runs,
which repeat to 0.1 instruction
([runs](../bench/results/2026-10-14-desktop-027-count/runs.tsv)):

| Build | epoll, user insns/req | user cycles/req | uring, user insns/req | user cycles/req |
|---|---:|---:|---:|---:|
| base | 1,838.9 | 495-531 | 1,887.2 | 468-485 |
| main | 1,846.9 (+8.0) | 495-521 | 1,895.0 (+7.8) | 448-457 |
| p3 | 1,846.1 (+7.2) | 473-579 | 1,895.2 (+8.0) | 475-504 |

Main spends 8 instructions a request more than the baseline on each loop, where at
`a6249a4` p2 to p5 spent 1-5 fewer. Its cycles are the same or fewer. `bench/codegen.sh
2afc12f 48f8e37` finds the loops' hot functions smaller on main (`answer` 4,785 and
4,761 instructions against 4,821 and 4,862), so the 8 are on the path a request takes,
not in the code's size.

### Plaintext and JSON

`bench/run.sh`: wrk 4.1.0 for 15 s after 5 s of warm-up, server on CPUs 0-3 and wrk on
4-15 with 8 threads, 256 connections, 3 runs, latency left out, medians and the runs'
range ([summary](../bench/results/2026-10-14-027-run/summary.md)), in millions of
requests per second:

| Test, workers | base | main | p3 | base, uring | main, uring | p3, uring |
|---|---|---|---|---|---|---|
| plaintext, 1 | 1.752 (1.621-1.772) | 1.751 (1.603-1.776) | 1.732 (1.599-1.740) | 1.976 (1.872-2.022) | 2.030 (1.912-2.033) | 2.009 (1.964-2.016) |
| plaintext, 4 | 5.467 (5.243-5.509) | 5.329 (5.326-5.459) | 5.317 (5.302-5.424) | 6.815 (6.668-6.939) | 7.006 (6.721-7.019) | 6.781 (6.721-6.809) |
| json, 1 | 0.134 (0.125-0.134) | 0.133 (0.125-0.134) | 0.122 (0.117-0.123) | 0.165 (0.153-0.169) | 0.157 (0.150-0.163) | 0.162 (0.152-0.166) |
| json, 4 | 0.402 (0.400-0.411) | 0.408 (0.399-0.409) | 0.408 (0.408-0.411) | 0.514 (0.506-0.517) | 0.508 (0.481-0.516) | 0.512 (0.511-0.512) |

Peak RSS is the same for all three, to 0.1 MB.

### REST

`bench/rest.sh run`, steps 1, 2, and 4, uring, 4 workers on CPUs 0-3 and the load on
4-15, 3 rounds of 15 s, tier C's reads at 16,000 a second in step 4
([summary](../bench/results/2026-10-14-rest-027/summary.md)). Medians at saturation,
and tier D:

| Cell | base | main | p3 |
|---|---:|---:|---:|
| A serialize | 556.4K | 569.6K | 539.9K |
| A template | 579.4K | 580.5K | 567.3K |
| B serialize | 266.0K | 263.7K | 257.2K |
| B template | 372.1K | 368.1K | 367.0K |
| C serialize | 52.3K (51.9-53.0) | 51.2K (47.5-51.9) | 49.2K (45.1-51.1) |
| C template | 145.1K (144.8-145.9) | 140.3K (130.7-144.0) | 143.5K (133.3-148.8) |
| Uploads alone, p50 | 15.9-18.0 ms | 16.1-16.6 ms | 16.0-17.5 ms |
| Uploads beside forms | 147-155/s | 151-162/s | 149-158/s |
| Uploads beside tier C | 423-672/s | 674-736/s | 649-711/s |

Peak RSS is the same in every cell. The ranges of A and B overlap for all three, and
so do C serialized's. C templated is the one cell where main's range, 130.7-144.0K,
stays under the baseline's, 144.8-145.9K: its median is 3.3% under, and p3's, on top
of main, 1.1%. The baseline's uploads beside tier C spread from 423 to 672 a second,
one round far under the others, so main's and p3's 649-736 aren't a gain over it.

### Step 6: p2's upload cost

Gone without p1: main's uploads alone, beside forms, and beside tier C are at or above
the baseline's. `perf stat` on the server, uploads alone for 10 s, two rounds each
([perf](../bench/results/2026-10-14-desktop-027-uploads-perf/perf.txt)): base and main
miss the instruction cache 7.2-7.8 M times and the iTLB 5.6-6.1 M times, the same to
within the rounds' spread, at 1,080-1,124 uploads a second. The 3-6% at `a6249a4` came
with p1 or with that kernel, and no layout cost is left to pin down.

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

- [x] `examples/README.md` describes the API as it now is, and its snippets compile.
      Its table lists the new examples, and it says not to `return` from a handler
      block (below). Each name it uses is the package's, and its code blocks, with a
      call of each helper as its text gives the arguments, typecheck in one program at
      Goose `46356c2` (2026-10-14).
- [x] New examples beside `hello` and `routes`, each a short program a reader can copy:
      a JSON API with path parameters, a body, cookies, and bearer auth; an upload read
      as a stream and as multipart; an answer that waits on a backend thread over mail;
      and files with ranges and conditional requests. `examples/api/`, `upload/`,
      `later/`, and `files/` (2026-10-14).
- [x] `scripts/test.sh` builds every example and requests each route once, so an API
      change can't leave an example broken: `scripts/test-examples.sh`, its last step,
      passing in WSL and Git Bash (2026-10-14).
- [x] The README's quick start and concepts match the examples: the quick start is
      `hello/` with the package imported from GitHub, and the concepts gain the rule
      against `return` in a handler block (2026-10-14).

Writing them turned up rough edges in the API, each a candidate for this task's list:

- A `return` in a handler block returns from the function the block is written in
  (the tutorial, "a block may also `return` from the lexically enclosing function"),
  so a handler written as a block that returns early ends its worker's loop, and the
  request waits unanswered. `api/`, `upload/`, and `later/` did, and hung on the
  first such request in `scripts/test-examples.sh`; they now call a function. A
  handler passed by name avoids it.
  Neither the loop nor the compiler can catch it (2026-10-14): the block returns
  through the loop's frames with none of the loop's code run (spec §7.6), Goose has no
  `finally` or `defer`, and a function can't refuse a block that returns past it. A
  finding records it
  ([A function can't keep its block from returning past it](../docs/goose-findings.md#a-function-cant-keep-its-block-from-returning-past-it)),
  and the README's concepts and `examples/README.md` state the rule.
- No bearer helper: `http::authorization`, then `http::eq_fold(scheme, "bearer")`,
  whose second argument must be lowercase.
  Done (2026-10-14): `http::bearer(req)` gives the token of `Bearer` credentials, the
  scheme in any case and the token a token68, tested in `test/test_api.goose` and used
  by `api/`.
- A 204 takes `start` and `finish(out, "", "")`, since `respond` always writes
  `Content-Type`.
  Done on `findings-46356c2-hot` (2026-10-14): `respond` writes no `Content-Type` for an
  empty one, so a 204 is `respond(out, 204, "", "")`. `respond` is on every request's
  path, so it waits for `bench/count.sh` with that branch's other changes.
- A handler takes state only to get `WAKE` and `TIMEOUT` (`serve(cfg, false)` in
  `later/`).
  Kept (2026-10-14): a loop entry without state would add two to the package, for
  `serve` and `serve_epoll`, to save one argument, and a `bool` costs a byte a slot.
  `examples/README.md` names the idiom.
- A box's slot size is guessed from `to_bytes` image sizes (task 028).

A review of the API against the examples and goose-rest at goose-http `e27ab21`
(2026-10-14) found more, most valuable first. "Hot" marks one on every request's
path, which `bench/count.sh` checks before it lands. All but 12 are settled
(2026-10-14): 1, 2, 4, and 6 to 11 are on `main`, 5 stays as it is, and 3 is dropped.
Item 12, found later the same day, is completed below.

1. A body larger than the read buffer: goose-rest copies the head out of `Request`,
   keeps it and the body in a buffer of its own, and parses again at the end
   (`runtime.goose`, `gather_head`, about 70 lines). A package helper, such as
   `http::gather(g, ev, out, spill, limit)` and then `http::gathered(g, spill)`, would
   replace that code. Additive.
   Done (2026-10-14): `http::gather(ev, g, out, limit) { req, body, o =>
   }`, with `g` an `http::Gather` in the request's state. The runs are in a per-worker
   global slice pool (spec §11.2), as `compression.goose` keeps its encoders, so the
   program passes no buffer. At `END` it parses the copied head again. Tested in
   `test/test_api.goose`, and by `upload/`'s `/words` in `scripts/test-examples.sh`.
2. `finish`'s `fields` must end in `"Content-Length: "`. Without it, the digits run
   into the line before, with no error. The examples, `server/routes.goose`, and
   goose-rest all write the raw string. Constants such as `http::JSON` and
   `http::TEXT` would remove the raw string, at no cost. Additive; hot, but a constant
   is the same append.
   Done on `api-246` (2026-10-14): `http::NO_TYPE`, `http::TEXT`, and `http::JSON`, in
   the package, `server/`, the examples, and `examples/README.md`; `test/` keeps its
   exact bytes. They're `const` fixed arrays: a global `let` slice is read at run time,
   so its append has a length gcc doesn't know, where a fixed array's sits in static
   data with a constant length, as a literal's does in the generated C. On `main`, with
   4 and 6. `bench/count.sh` at `e67d92d` holds: 1,833.1 user
   instructions a request on epoll and 1,888.5 on uring, what `e4f7b55` spent before
   them ("The review items at Goose `46356c2`").
3. `respond` checks its content type through `field` and `is_field` on each call, a
   `find_any` over the constant name included. Check only the value instead. Measure
   it first: gcc may already fold it. Hot.
   Done on `api-hot` (2026-10-14): gcc didn't fold it, since each `respond` called
   `gs_scan_any` over `"Content-Type"`. `respond` now checks the value with
   `is_field_value`, appends `"Content-Type: "` as a constant, and writes no
   `Content-Type` for an empty one. In `bench/rest`'s server, `.text` shrinks from
   612,111 to 605,199 bytes and both `answer` and `call` shrink. But in the benchmark
   server gcc now inlines the cold `client` and `wait_for_backend` routes into
   `answer`, which grows from 4,906 to 6,023 instructions on epoll, and a plaintext
   request, which never calls `respond`, costs 13.8 user instructions more there: 1,846.9
   against 1,833.1, with uring 2.3 under ("The review items at Goose `46356c2`").
   Dropped (2026-10-14): it changes no API, only what `respond` checks, and REST tiers
   A-C show no gain of its own: its one gain beyond the rounds' spread, tier C
   templated, `findings-46356c2-hot` has without it ("The pending branches at Goose
   `46356c2`"). The part a program sees, no `Content-Type` for an empty one, is on
   that branch. `api-hot` (`4292f87`) is deleted.
4. No supported way to add fields to every response: goose-rest swaps `out.common` for
   CORS and moves bytes in the written head for `Server-Timing`. Either document
   `Reply.common` as a handler's to set, or add `http::insert_field`. Additive.
   Done (2026-10-14), both: `Reply`'s declaration and
   `examples/README.md` state `common`'s contract, and
   `http::insert_field(out, mark, name, value)` adds a field at the end of the head of
   the response begun at `mark`, checked as `field` checks one, tested in
   `test/test_http.goose`. A value known only once the response is written, as
   `Server-Timing`'s, can't go in `common`.
5. `respond_json` builds a new array on each call (`media.goose`). A form that reuses
   a caller's buffer would avoid it. Additive; hot for JSON APIs.
   Kept (2026-10-14): the array costs a header and a stack top restored, and the one
   cost worth saving is the `memcpy` into `out.buf`. Writing the body straight into
   `out.buf` and moving it up past its length replaces that `memcpy` with a byte loop
   of about 7 instructions a byte, since Goose has no `memmove` within an array.
   `out.buf` can't shrink under the loop's `Reply` either (spec §5.1), so HEAD and a
   204 would need the array anyway, and W would be built twice: `examples/api`'s
   `.text` grew by 2,560 bytes. A caller's scratch buffer saves only the header.
   `test/test_api.goose` now pins its bytes for HEAD, a 204, and lengths of 1 to 4
   digits.
6. The examples' own functions take `http::Request` by value, a copy of about 300
   bytes per call. They should take `const http::Request&`. Docs and examples only.
   Done (2026-10-14): `api/` and `files/`; no README snippet takes one.
   `server/`'s functions still take it by value, on the benchmark's path.
7. `stop_on_signals` returns an `i32` and `mail_open` a code, so each `main` builds its
   `http::Error` by hand. Return an `Error` instead, and add an `exit_on_error`.
   Breaking; cold.
   Done (2026-10-14): `http::stop_on_signals()` and `http::mail_open`
   return an `http::Error`, and `http::exit_on_error(e)` reports one and exits with
   status 1 unless its code is 0. mail.goose stays free of HTTP: its opener is
   `http::mail_open_code`, which still returns a code, and http.goose's `mail_open`
   wraps it. Every `main` in `examples/`, `server/`, and `bench/rest` uses it, and
   `device/` and `server/` drop their own `stopped`. Tested in `test/test_http.goose`.
8. `query_int` returns 0 for a missing value, a malformed one, and a real 0. Return
   `i64, bool` instead. Breaking; cold.
   Done (2026-10-14): `http::query_int(target, key) -> i64, bool`, false
   with 0 for a value missing or not an integer. `server/routes.goose` ignores the
   `bool`, as it read a missing value as 0 before; `examples/README.md` lists it, and
   `test/test_http.goose` tests a real 0 against both failures.
9. A program's own check can't fail a `Multipart`, so `upload/` keeps a flag beside
   the one `each_part` keeps. Add `http::fail_multipart`. Additive; cold.
   Done (2026-10-14): `http::fail_multipart(m)` fails `m` as a body that
   isn't multipart does. Called from `each_part`'s function, it ends that `each_part`,
   which calls the function no more and returns false. `upload/` drops its flag.
   `test/test_api.goose` fails the body at each call, in pieces of 1, 7, and the whole
   body.
10. `field` and `set_cookie` drop invalid input without a word. Return a `bool`.
    Additive.
    Done (2026-10-14): `http::field`, `http::set_cookie`, and
    `http::insert_field`, which drops a field as `field` does, return whether they
    wrote it. A call that ignores the result is unchanged, so no caller changes.
    `test/test_http.goose` and `test/test_api.goose` assert each result.
11. A file from an encoded path takes `decode`, `is_safe_path`, and a join. Add an
    `http::file_path(dir, encoded, out)`. Additive; cold.
    Done (2026-10-14): `http::file_path(dir, encoded, out)` appends
    `dir`, a `/` unless `dir` is empty or ends in one, and the decoded path, and
    returns false, with `out` as it was, for a bad escape or a path `is_safe_path`
    refuses. `files/` and `server/`'s `/files/` use it, and `examples/README.md`
    lists it. `test/test_http.goose` tests escaped `..`, `/`, NUL, `\`, and `:`. A
    `for` over a literal array of strings there is refused when its body shrinks an
    array, so the test binds the literal to a `let` first.
12. A reply to an exchange whose client closed or whose wait timed out returned `SENT`,
    then the loop dropped it silently. A database thread answering `rest::ask` could
    do the whole job and send every piece of a long reply for a client that had gone.
    Found by goose-rest's task 017 (2026-10-14), at goose-http `bc75f2a`: only closing
    or reopening the whole box made a send return `STALE`.
    Implemented (2026-10-14): `mail_live(to)` and an optional generic table of keys
    the owner marks live with `mail_mark`. The mailbox owns the atomic table and
    knows no HTTP state. The HTTP worker sizes it by `max_conns` and selects entries
    with the key's top 20 bits. The lifecycle and the race with a send already in
    flight are recorded in
    [the waiting design](../docs/architecture.md#mail-between-threads).
    Publishing in `later` itself lets another thread reply before the handler
    returns; timer exhaustion or an immediate whole response clears the key again.
    `mail_slot_size` now returns -1 for a stale tracked key too.

    Validation on Goose `46356c2`: `scripts/test.sh` passes on Linux (io_uring,
    epoll, and the ring over epoll) and Windows (IOCP). Final unit checks include
    tracked concurrent sends, entry replacement, queued mail after clearing,
    immediate replies, timer exhaustion, `CLOSED`, and answering instead of waiting.
    The HTTP suite checks `STALE` and `mail_live == false` in the backend after a
    client disconnects mid-wait and after a timeout, then checks connection reuse
    and repeated SSE waits. Both kqueue paths use the same updated Goose loops and
    tests. On macOS (kqueue), `scripts/test.sh` passes at the fix below.
    Request-path benchmark: Ryzen 7 5800X3D, WSL2 Ubuntu 26.04.1, kernel
    `6.18.54.1-microsoft-standard-WSL2`, Goose `46356c2`, gcc 15.2.0 release
    builds. The baseline's HTTP source is `1e963ba`; the candidate adds this item.
    oha 1.16.0, 4 workers, 256 connections, 500,000 requests per cell, 3 paired
    rounds, no CPU affinity, on the io_uring loop. Each cell runs
    `oha -n 500000 -c 256 --no-tui --json http://127.0.0.1:29380/PATH` through
    `bench/oha.sh`, on `/plaintext` and `/json`, with waiting disabled and with
    `MAIL_SLOTS=64`. Rates below are the three runs' ranges, in K requests/s;
    the difference is between medians. Neither gain nor loss separates from
    the runs' spread.

    | Waiting | Path | Baseline | Live keys | Median difference |
    |---|---|---:|---:|---:|
    | Off | Plaintext | 511.3-523.0 | 506.5-529.0 | +2.9% |
    | Off | JSON | 508.8-525.6 | 502.7-516.9 | +1.0% |
    | On | Plaintext | 538.5-565.0 | 531.5-551.5 | -2.7% |
    | On | JSON | 545.9-558.4 | 522.2-573.7 | +0.3% |

    Raw runs and CPU time:
    [waiting disabled](../bench/results/2026-10-14-mail-live-off/runs.tsv),
    [waiting enabled](../bench/results/2026-10-14-mail-live-on/runs.tsv).
    [The measurement settings and binary hashes](../bench/results/2026-10-14-mail-live-method.md)
    identify the saved builds independently of the metadata's runtime HEAD.

    goose-rest can add `rest::wanted(a) = http::mail_live(a.reply)` so a service
    skips a job or stops sending pieces for a client that has gone. Its
    `rest::answer` already stops on `STALE`; that repository is outside this change.

    Fixed (2026-10-14): the loops first cleared the key before `WAKE`, so a piece sent
    while the handler had yet to call `later` again returned `STALE`, and
    `rest::answer` cut a reply in pieces short. The key now stays live through `WAKE`
    and is cleared after any handler call that leaves the exchange not waiting, which
    also catches a handler that resets `Stream.waiting` itself, as goose-rest's
    `rest::ask` does when its job can't be sent. `Stream.live` records the mark, so
    `later` on a live key and requests that never wait make no atomic write. The HTTP
    suite sends 5 bursts of 500 `/events` pieces back to back, retrying `FULL`, and
    the backend asserts every send is `SENT`; the old code failed it on macOS. Passes
    `scripts/test.sh` on macOS (kqueue).

    Confirmed (2026-10-14, `faead67`, Goose `46356c2`): `scripts/test-unit.sh`
    passes on Linux (gcc 15.2.0) and Windows in Git Bash (MSVC 19.51), including
    `test_http`'s piece-by-piece `WAKE` liveness checks. Rebuilt servers also pass
    `scripts/http_client.py PORT later`, with `WORKERS=4`, `MAIL_SLOTS=64`, and
    `MAIL_CHECK_STALE=1`, on io_uring, epoll, the ring over epoll, and Windows IOCP.
    This includes the five bursts of 500 pieces and the backend's stale-send
    assertions after a disconnect and timeout. The Goose pin stays unchanged;
    upstream's only newer commit is a logo change.

    Completed (2026-10-14, `d29ac5f`, Goose `46356c2`): the full `scripts/test.sh`
    suites pass on Linux (native io_uring, epoll, and the ring over epoll) and
    Windows in Git Bash (IOCP, MSVC 19.51), including the examples. Linux used
    `PORT=29180`, Windows `PORT=29280`, both `WORKERS=4`; no further fix or release
    was needed. `CLAUDE.local.md` was absent, so the documented adjacent Goose
    checkout supplied both compilers.

    Paired benchmark of the fix: Ryzen 7 5800X3D, WSL2 Ubuntu 26.04.1, kernel
    `6.18.54.1-microsoft-standard-WSL2`, Goose `46356c2`, gcc 15.2.0 release
    builds through `LOOP=uring scripts/build.sh`. The baseline is `0c7b0e4` and
    the fixed binary is `8ab362c`. oha 1.16.0 through `bench/oha.sh`, 4 workers,
    256 connections, 500,000 requests per cell, 3 paired rounds, no CPU affinity,
    port 29380. Rates are the three runs' ranges in K requests/s; the difference
    is between medians. Waiting on means `MAIL_SLOTS=64`.

    | Waiting | Path | Baseline | Fixed | Median difference |
    |---|---|---:|---:|---:|
    | Off | Plaintext | 481.7-550.3 | 503.3-552.5 | +1.5% |
    | Off | JSON | 516.0-536.8 | 514.3-553.8 | +0.3% |
    | On | Plaintext | 540.0-559.9 | 521.4-555.0 | -3.2% |
    | On | JSON | 539.4-551.4 | 521.3-545.6 | -2.5% |
    | On | `/later?id=b&delay=0` | 85.9-94.5 | 87.5-98.0 | +4.1% |

    Every pair's ranges overlap: no gain or loss separates from the runs' spread.
    The plaintext and JSON cells return only 200s. The waiting-path rates include
    8-24 HTTP 504s per baseline run and 6-18 per fixed run, with no transport errors.
    The benchmark backend drops a reply on `FULL`; uneven connection distribution
    can fill a worker's 64-slot mailbox and leave a wait to time out after 5 seconds.
    Thus the waiting-path rates do not isolate this fix's cost. `oha.sh` passes the
    query string correctly, verified in a separate probe; no route substitution
    was needed. This correctness fix stays; the observed median costs with waiting
    on are recorded, and do not invoke the rule for speed-only changes.

    [Method, commands, saved binary hashes, and the query probe](../bench/results/2026-10-14-mail-wake-method.md);
    raw runs and CPU time: [waiting off](../bench/results/2026-10-14-mail-wake-off/runs.tsv),
    [waiting on](../bench/results/2026-10-14-mail-wake-on/runs.tsv), and
    [the waiting path](../bench/results/2026-10-14-mail-wake-later/runs.tsv).

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
