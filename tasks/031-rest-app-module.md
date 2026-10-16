# 031: Split the REST server's application out of its routes

Status: in-progress (asked for 2026-10-14). The split is on `main`, checked on Linux in
Docker on a Mac; the desktop's idle memory recheck remains (below).

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

- [x] `bench/rest/goose/app.goose` holds the records, loaders, writers, templates, and
      tier D's body work, with no `main`, no routes, and nothing from `http` but types
      its functions need; `rest.goose` imports it with `import .app;`
- [x] No behavior change: `bench/rest/check.py` passes on every tier, both loops, and
      both JSON ways
- [x] Idle VmRSS per worker on tiers A and C matches task 025's last table, so the
      globals behind a module copy no more on `thread_spawn` than before; if they do,
      the reduction goes in `docs/goose-findings.md` (matched against the build before
      the split on the same machine; the desktop's figures are pending, below)
- [x] `app.goose`'s header says goose-rest imports it, so a rename there is a breaking
      change for goose-rest's next pin move

## What was done (2026-10-16)

The 3,107 lines of `rest.goose` at `13b9aa33` are now `app.goose` (2,279 lines) and
`rest.goose` (863). Every line moved as it was, but for these changes:

- `app.goose` has the records and their indexes, the loaders, the JSON writers,
  `JSON=template`'s prebuilding and `share_templates`, the date and lookup helpers they
  use, snowtime's `is_admin` and `sees`, tier D's CSV, multipart, batch, and form
  readers, the spools, and the lists of every global array: `hand_over`, `take_all`,
  `Flags`, and `print_lens`, which a new global array must join.
- `rest.goose` keeps the routes, `served`, `index_of`, the query, cookie, Origin, and
  bearer checks, the bodies of tiers A and B, every error answer, `Upload` and tier D's
  limits, the distributor and its `Ready` and `Taken`, `mallopt`, the `thread_fn`s, and
  `main`.
- Tier D's four answers (`import_answer`, `attach_answer`, `bookings_batch`,
  `form_answer`) write their JSON and return the status, or 0 for a body that isn't
  one. `rest.goose`'s `answer` sends that, or `heavy_error`'s 400. Before, they called
  `http::respond` and `heavy_error` themselves. The bytes sent are the same.
- From `http`, `app.goose` uses `Blob` and `Multipart`, and the functions that build
  JSON (`json_string`), read multipart and form bodies, and use the store. It names no
  `Request`, `Reply`, or `Event`.

`app.goose` can't import `http.store` itself. Imported from a package, as goose-rest
imports it, a module looks for `import http.store;` at `<package>/http/store.goose`
and in the stdlib, not among the root's declared packages, which spec §11.1 and
`docs/design/packages.md` §4.4 list as the second place to look (Goose v2026.2,
`3ee3871`). Under `rest.goose` it resolves, since there `app.goose` is the program's own
file. So the importer imports `http.store`, as its header says. Minimal:

    // app/main.goose
    import mylib2 from "../../mylib2";
    import mylib2.sub.user;
    fn main() { print(used()); }

    // mylib2/mylib2.goose: fn entry() -> i64 { 1 }
    // mylib2/extra.goose: fn helper() -> i64 { 2 }
    // mylib2/sub/user.goose
    import mylib2.extra;
    fn used() -> i64 { helper() }

`goose run app/main.goose` fails with "cannot find the module mylib2.extra". It isn't in
`docs/goose-findings.md`: one import in the importer works around it.

### Checks

- `goose check bench/rest/goose/rest.goose` on macOS. A program that imports
  `http.bench.rest.goose.app` and `http.store` with no routes, as goose-rest will,
  builds and runs on macOS, calling every loader, writer, and tier D answer.
- `scripts/test.sh` passes on macOS (M1 Pro, macOS 26.3.1, kqueue), Goose v2026.2.
- The REST server doesn't link natively on macOS (`mallopt` is glibc's), so it ran in
  Docker Desktop 29.8.2's arm64 VM on the same Mac: `ubuntu:26.04`, kernel
  7.0.14-linuxkit, gcc, Goose v2026.2 built from source by `scripts/goose.sh`,
  `--security-opt seccomp=unconfined` so `LOOP=uring` runs on io_uring, the dataset
  from `bench/rest/gen.goose`. Each binary built with
  `goose build --cc gcc --standalone`: before, from `git archive 13b9aa33`, and after,
  from the working tree. `bench/rest/check.py` passed for both, on tiers A to D, both
  loops, both JSON ways, 2 workers: 32 of 32.
- Idle memory: epoll, no request sent, VmRSS 3 s after listening, 1, 2, and 4 workers,
  3 rounds, before and after each cell in turn. Medians, in KB:

| Tier, JSON | Before, 1 / 2 / 4 workers | After, 1 / 2 / 4 workers | Per worker, both |
|---|---|---|---:|
| A, serialize | 7,216 / 10,036 / 15,656 | 7,228 / 10,024 / 15,656 | 2.8 MB |
| A, template | 6,608 / 8,796 / 13,168 | 6,608 / 8,796 / 13,164 | 2.2 MB |
| C, serialize | 18,404 / 32,260 / 60,024 | 18,416 / 32,272 / 60,024 | 13.9 MB |
| C, template | 25,616 / 29,568 / 37,472 | 25,616 / 29,568 / 37,476 | 4.0 MB |

Per worker is (4 workers less 1) / 3. Every median is within 0.2% of its before; two
single rounds read 2 MB over (C serialized 2 workers, C templated 1 worker), and their
other rounds didn't. The module's globals copy as they did. These are the VM's figures,
with its default huge pages, not the desktop's, so they compare the two builds, not
task 025's table.

### Pending on Linux

On the desktop (WSL2), at the commit after the split and at `13b9aa33`: `bench/rest.sh
build`, then `bench/rest-memory.sh` with `TIERS="a c"`, and the idle VmRSS with 4
workers, epoll, 3 s after listening, to compare with task 025's last tables. No rate run
is needed: the request path's functions are the same, but for tier D's answers
returning their status (`bench/codegen.sh 13b9aa33 <commit>` shows it, if wanted).