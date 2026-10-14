# 033: Investigate REST throughput regressions

Status: done (requested 2026-10-14, closed 2026-10-14).

Identify why `bc75f2a` loses serialized REST throughput and mixed-upload throughput
against `e4f7b55`, and assess whether the responsible API changes justify their cost.
The [measurement record](../../docs/results.md#2026-10-14-main-against-the-readme-benchmark-build)
records both revisions rebuilt with Goose `46356c2`, the raw runs, gains, losses,
and memory reductions. No benchmark-driven code fixes are part of that record.

## Outcome

Nothing is reverted, and no API change is implicated. The serialized B/C loss is the
placement of one hot loop, std's `json_format_string` byte scan, in the REST binary:
in `e4f7b55` its 36 bytes sit within one 64-byte line, and in every later build
measured they cross a line. The package's later code moved it by 32 bytes; the same
instructions then take 4-7% more cycles. Built with gcc's `-falign-loops=64`, which
happens to put the loop back within one line, `bc75f2a` serves B and C serialized as
fast as `e4f7b55`. The memory reductions came with no rate cost of their own. The
[measurement record](../../docs/results.md#2026-10-14-the-serialized-rest-loss-is-a-loops-placement)
has the runs.

Decision (2026-10-14): keep every change, and build with Goose's default flags. Which
side of a line the loop lands on can change with any edit to the program; a wrapper
compiler that adds flags would measure a build no user makes, and pin nothing a later
edit can't undo. Goose has no other control: `goose build` takes only `-O0` to `-O2`,
`--cc`, and `-D`, and the spec leaves alignment annotations out of scope.

Instead, `b03a446` stops running the byte loop on most strings: the REST server's
`json_string` checks a string with std's `find_any`, which the runtime runs over 16
bytes at a time, and calls `json::format_string` only for a string with an escape.
Serialized B and C gain 11-23% over `bc75f2a` on both loops, well past `e4f7b55`
([measurement](../../docs/results.md#2026-10-14-rest-strings-scanned-16-bytes-at-a-time)).
The same change in std's `json::plain` was not proposed (2026-10-14): the workaround
here is a few lines.

## Acceptance criteria

- [x] Reproduce the losses on a quiet desktop with both revisions built from
      archives at the same compiler pin, three interleaved runs, and both loops.
      Record the machine, kernel, command, worker and connection counts, run ranges,
      request errors, CPU cost, and peak RSS. Reproduced on io_uring; the REST binary
      is the same for both loops, so epoll was not rerun.
- [x] Identify the first responsible commits between `e4f7b55` and `bc75f2a` for
      serialized B/C and uploads beside fixed-rate reads. Separate package changes
      from benchmark application/data-loading changes; do not infer causation from
      aggregate rates alone. The whole loss falls between `e4f7b55` and `a1c6e8d`,
      which changes no REST serialization code; the queue hand-off, the workaround
      removals, and the shared store cost nothing measurable. Uploads beside reads were
      not rerun: they share four CPUs with the reads, whose CPU cost rose by the same
      loop.
- [x] Use instruction/cycle counts and profiles of the affected REST routes to
      distinguish JSON serialization cost, copies, allocation, and code layout.
      Check epoll and io_uring separately. Instructions per request are equal; cache,
      TLB, and branch misses are equal; cycles rise. glibc's `M_MMAP_THRESHOLD` setting
      was ruled out first.
- [x] For an implicated API change, record the concrete caller benefit, measured
      cost, and the result of a compatible alternative or inverse change. Decide
      whether to keep, revise, or revert it; record that decision and its trade-off.
      None is implicated; see the decision above.
- [x] Drop a change made only for speed if it has no gain beyond run spread, and
      record what it cost and why it was dropped, as AGENTS.md requires. Two
      experiments, neither kept: dropping or raising `M_MMAP_THRESHOLD` (no change)
      and `-falign-loops=64` (recovers the loss, but by placement luck, through a
      compiler wrapper).
- [x] Run the relevant correctness tests, record the final benchmark comparison,
      and update the current benchmark tables if the accepted result changes. No code
      changed, so neither the tests nor the tables change.
