# 022.02: gzip in `goose-compress`

Status: in progress, as [goose-compress](https://github.com/kaitk/goose-compress)'s task
001 (moved there 2026-10-12)

A DEFLATE encoder in Goose with the gzip and zlib wrappers, in a package of its own
([task 022](README.md)). Its steps, acceptance criteria, and measurements are tracked in
goose-compress's `tasks/001-gzip.md`. Step 1 is done: stored blocks in gzip and zlib, a
one-shot `compress`, and a streaming encoder with `flush` and `finish`. That's enough to
build subtask 03 against; the output gets smaller from step 2 on, with the same API.

## Acceptance criteria

- [ ] goose-compress's task 001 done
