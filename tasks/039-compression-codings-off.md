# 039: Let a program turn gzip and deflate off

Status: todo, later (found 2026-10-15)

`http::Compression` has a `zstd` flag, but gzip and deflate are always offered. A
program can't limit its answers to one coding, such as zstd alone for clients it
controls, or gzip alone to match a proxy's cache. goose-rest's `rest::compressed` takes
the same `http::Compression`, so it has the same limit.

## Acceptance criteria

- [ ] `http::Compression` can turn each of gzip, deflate, and zstd off, with every
      coding on by default
- [ ] Tests cover each coding turned off, and `docs/api.md` says so
