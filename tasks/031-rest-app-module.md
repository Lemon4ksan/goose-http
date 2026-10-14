# 031: Split the REST server's application out of its routes

Status: todo (asked for 2026-10-14)

goose-rest's benchmark server (its task 010) is a copy of `bench/rest/goose/rest.goose` at
`e27ab21` with its own routes: about 2,450 of its 2,883 lines are the same. The copy
missed task 025's memory work, so its peak RSS would be compared against a server that
has it. goose-rest can import a module from this package at its pin (spec §11.1:
`import http.bench.rest.goose.app;` is this repository's `bench/rest/goose/app.goose`),
so the shared part can live here once and both servers can serve it through their own
routers.

The split puts in `app.goose` everything a framework doesn't do: the record structs,
the dataset loaders, the JSON writers and templates, and tier D's work on a body. It
keeps in `rest.goose` what the benchmark compares: routes, parsing a request's
parameters and headers, the bearer check, error answers, the `thread_fn`s, and `main`.
Loading stays on a loader thread (task 025), which the server writes, since it spawns
the server's own workers.

## Acceptance criteria

- [ ] `bench/rest/goose/app.goose` holds the records, loaders, writers, templates, and
      tier D's body work, with no `main`, no routes, and nothing from `http` but types
      its functions need; `rest.goose` imports it with `import .app;`
- [ ] No behavior change: `bench/rest/check.py` passes on every tier, both loops, and
      both JSON ways
- [ ] Idle VmRSS per worker on tiers A and C matches task 025's last table, so the
      globals behind a module copy no more on `thread_spawn` than before; if they do,
      the reduction goes in `docs/goose-findings.md`
- [ ] `app.goose`'s header says goose-rest imports it, so a rename there is a breaking
      change for goose-rest's next pin move
