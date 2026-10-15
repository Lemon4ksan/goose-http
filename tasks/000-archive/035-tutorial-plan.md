# 035: One tutorial across goose-http and goose-rest

Status: done (2026-10-15)

A developer coming from another stack, such as TypeScript, needs to see bodies past the
read buffer, long responses, and slow work solved on a sample problem, one step at a
time. goose-rest's task 016 already plans that tutorial, on its projects API: large
bodies, a service for work that waits, streaming, and limits. Writing it again here, at
goose-http's level, would tell the same story twice. This task agrees which project
holds what, then shapes goose-http's side to match.

It waits on goose-rest's documentation taking goose-http's shape first (asked for
2026-10-15): a README for people who use the package, with process, pins, layout, and
agent rules in `docs/` or `AGENTS.md`, setup and known issues apart, a changelog, and no
task list in the README. That work leaves the examples and the tutorial to this task.

## Proposal

One tutorial, in goose-rest, paged. goose-http has no tutorial: it explains how its
loop works, in `docs/patterns.md`, and goose-rest's pages link there instead of
explaining it again.

| Project | Holds | Doesn't hold |
|---|---|---|
| goose-rest | The tutorial: one sample application that grows a step per page, with code `scripts/test.sh` checks | How the loop reads, sends, and waits, past a sentence and a link |
| goose-http | What the loop does and why: buffers, limits, backpressure, mail, with diagrams (`docs/patterns.md`); the reference (`docs/api.md`); small standalone programs (`examples/`) | A sample application's story |

### The tutorial's pages

Part one exists in goose-rest's `docs/tutorial.md` today, as one page; this splits it.

Agreed 2026-10-15 (see [Decisions](#decisions-2026-10-15)).

| Page | Focus | Links to goose-http |
|---|---|---|
| **Part one: the basics** | | |
| 1. Running something | Workers, the loop, one route | README, "Concepts" (the workers diagram) |
| 2. Routes, path, query, and headers | Matching and reading a request | |
| 3. Answers and errors | Responses, and one error shape | |
| 4. JSON bodies | A body that fits the read buffer, read whole | `patterns.md`, "Request bodies" |
| 5. The API from a schema | Generated routes beside hand-written ones | |
| 6. The schema in TypeScript, Python, or Rust | `api.json` from code | |
| 7. Middleware and scopes | | |
| 8. State | The worker's and the request's; workers share no memory | `patterns.md`, "State that workers share" |
| 9. Testing without sockets | | |
| **Part two: bodies, waits, and limits** | | |
| 10. Large bodies | A CSV import gathered whole up to a limit | `patterns.md`, "Request bodies" |
| 11. Bodies read as they arrive | TBD: no page until goose-rest reads a body in pieces | `patterns.md`, "Request bodies" |
| 12. Long responses and files | TBD: no page until goose-rest sends a response in pieces | `patterns.md`, "Long responses" |
| 13. Work that waits | The database in the route, then behind a service: one job per route | `patterns.md`, "Mail between threads" and "Slow work" |
| 14. Two services, or a reply in pieces | When a service can't do it alone | `patterns.md`, "Mail between threads" |
| 15. Limits | 503 for a full box, 504 for a late reply, a slow client, a client that has gone, and minutes-long work as a job the client polls | `patterns.md`, "Limits" |
| 16. Embedded Linux | One worker and small limits on a board | `docs/embedded.md` |

Pages 10 to 15 are goose-rest task 016's approaches 7 and 9 to 12, in its order. The
index lists a TBD page by number and title, without a link.

### A database for part two

Pages 11 to 13 call an external database, through a small fictional library whose API
reads like a Rust one, such as sqlx's (proposed 2026-10-15): a pool, a query with bound
parameters, and a row read into a struct, all blocking.

```goose
let rows = db::query(conn, "SELECT id, name FROM projects WHERE owner = $1")
    .bind(owner)
    .fetch_all<Project>();
```

A reader coming from Rust or TypeScript knows the shape, so the page can spend its words
on what's new: the calls block, so they run on a service thread that owns the pool, and
the route waits for one reply. The tutorial's programs are built and requested by
`scripts/test.sh`, so the library is a small fake in the tutorial's own code, rows in
memory with a set delay per query, and the page says so. A real driver, such as SQLite
through C, can replace it later without changing the pages.

## Decisions (2026-10-15)

The open questions, settled:

- **`docs/patterns.md` keeps its name and its advice**, such as which body handler to
  pick by size: a goose-http user without goose-rest needs it, and links already point
  there. It gains a "Limits" section for page 15 (the bounds in `Config`,
  `max_waiting`, 503 and 504, a slow client, a client that has gone), drops its
  reference to a `server/` example that doesn't exist, and its "Minutes" row links
  page 15.
- **The sample stays the projects API**, on every page. One application grows through
  the tutorial, and part one's eight programs already build it; a clinic's records
  would bring health data into every example.
- **A goose-http user needs no more** than `patterns.md` and the examples, as long as
  each section links an example that shows it end to end.
- **The fake database reads as plain calls**: `db::fetch_all<Project>(conn, sql,
  owner)`. With Goose v2026.1, `x.f(a)` finds `f` only in the calling code's
  namespace, so `db::query(..).bind(owner)` fails with "unknown function or member:
  bind", and `.fetch_all<Project>()` doesn't parse: a call written `x.f()` takes no
  type arguments.

And the rest of the plan:

- The pages live under goose-rest's `docs/tutorial/`, each page `NN-name.md` with its
  program in `NN-name/`, or in subfolders of it for a page with several. The index is
  `docs/tutorial/README.md`, and `docs/tutorial.md` goes.
- Parts are "the basics" and "bodies, waits, and limits". There is no part three: the
  schema in TypeScript, Python, or Rust follows the schema page, and embedded Linux
  closes part two, after limits. The index lists each page with the calls it
  introduces, not a description.
- goose-rest can't read a body in pieces, or send a response in pieces or from a file,
  so pages 11 and 12 are TBD: the index lists them by number and title, without a
  link, and the README's status table names what's missing.
- Quick, synchronous work in the handler (task 016's approach 9) opens page 13: the
  fake database called in the route stalls the worker, and moves behind a service.
- Examples: goose-rest's `waiting/` goes, since pages 13 to 15 tell its story, and its
  links move there. `plain/` and `schema/` stay, the two complete programs to start
  from. The two `device/` examples overlap: goose-http's keeps the events and the GPIO
  line through C, and goose-rest's keeps what the schema adds and links goose-http's.
  goose-http's other examples stay, one mechanism each.
- Code blocks in both repositories are labelled `rust`, which GitHub highlights closest
  to Goose; a block Rust's highlighting gets wrong, such as one with a `"""` raw
  string, is left without a label.

## Acceptance criteria

- [x] The split, the pages, and the open questions are agreed, with the date
- [x] goose-rest task 016 names the pages and the goose-http sections each links to
- [x] `docs/patterns.md` has a section for each goose-http link the pages need, and
      names the page that builds on it ("Limits" is new)
- [x] No page in either project explains what the other holds, past a sentence and a
      link
