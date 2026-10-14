# 033: Investigate REST throughput regressions

Status: todo (requested 2026-10-14).

Identify why `bc75f2a` loses serialized REST throughput and mixed-upload throughput
against `e4f7b55`, and assess whether the responsible API changes justify their cost.
The [measurement record](../docs/results.md#2026-10-14-main-against-the-readme-benchmark-build)
records both revisions rebuilt with Goose `46356c2`, the raw runs, gains, losses,
and memory reductions. No benchmark-driven code fixes are part of that record.

The baseline already contains task 027's p2 to p6. This comparison does not isolate
the whole API rewrite, nor distinguish later API changes from compiler-workaround
removals and the REST worker-load/shared-store changes. Attribute the cost before
deciding what to keep or revert. Memory savings are a separate benefit to preserve
or quantify when evaluating an alternative.

## Acceptance criteria

- [ ] Reproduce the losses on a quiet desktop with both revisions built from
      archives at the same compiler pin, three interleaved runs, and both loops.
      Record the machine, kernel, command, worker and connection counts, run ranges,
      request errors, CPU cost, and peak RSS.
- [ ] Identify the first responsible commits between `e4f7b55` and `bc75f2a` for
      serialized B/C and uploads beside fixed-rate reads. Separate package changes
      from benchmark application/data-loading changes; do not infer causation from
      aggregate rates alone.
- [ ] Use instruction/cycle counts and profiles of the affected REST routes to
      distinguish JSON serialization cost, copies, allocation, and code layout.
      Check epoll and io_uring separately.
- [ ] For an implicated API change, record the concrete caller benefit, measured
      cost, and the result of a compatible alternative or inverse change. Decide
      whether to keep, revise, or revert it; record that decision and its trade-off.
- [ ] Drop a change made only for speed if it has no gain beyond run spread, and
      record what it cost and why it was dropped, as AGENTS.md requires.
- [ ] Run the relevant correctness tests, record the final benchmark comparison,
      and update the current benchmark tables if the accepted result changes.
