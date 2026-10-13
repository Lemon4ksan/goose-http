# 027: A more idiomatic API

Status: in progress (asked for 2026-10-13). Next: the breaking proposals, then their
overnight batch. Breaking changes cost least before programs use the API, and
goose-rest will be the first.

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
   `server/` updated in the same commit.
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
      server changes with it.
- [ ] **Request helpers take `const Request&`**, not `Request` by value: `field_of`
      (`message.goose:225`), `cookie_of` (`cookie.goose:39`), `authorization`
      (`auth.goose:16`), `has_type` (`media.goose:124`), and `range_of`
      (`message.goose:1148`). `Event.req` became a reference to save the same copy,
      about 20 instructions per request. Unverified where gcc inlines them anyway.
      Check: `bench/rest.sh` tiers B and C.
- [ ] **`BodyReader.place` as an enum** (`message.goose:484-495`): `Length{left}`,
      `ChunkData{left}`, `ChunkSize`, and so on, so `read_body`'s cases are checked as
      complete and `left` exists only where it means something. Check: tier D's uploads.
- [ ] `PART_HEAD`, `PART_DATA`, and `PART_END` (`form.goose:31`) as an enum
      `Part { Head{fields}, Data{bytes}, End }`. Taste. Check: tier D.
- [ ] `Stream`'s `chunked`, `raw`, and `left` as one framing enum. Taste. Check: the
      streaming routes' tests and `bench/files.sh`.
- [ ] **Typed mail.** `mail_send_value<T>(to, tag, v)` over `to_bytes`, and a
      `from_bytes<T[>..]>` decode on take, checked by the language's verifier. Replaces
      `put`, `got`, `encode`, and `decode` in `server/backend.goose:22-48`. Additive,
      one framed copy per message on a cold path. Unverified: whether a limited
      array's image includes its unused capacity. Check: the `/later` and `/events`
      tests.
- [ ] Loop setup in `serve_epoll` and `serve` (`epoll.goose:41-72`) as a nested
      `fn setup()` caught by an `Error[]` handler, in the stdlib `exception` module's
      pattern: file descriptors start at -1, with one cleanup site. `Error.call` is
      always a literal, which a long-distance return may carry. About 15 lines fewer,
      on a cold path. Taste.

A proposal the work turns up later joins this list with its check before it lands.

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
