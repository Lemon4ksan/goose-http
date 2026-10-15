# 035: One tutorial across goose-http and goose-rest

Status: todo (asked for 2026-10-15)

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

| Page | Focus | Links to goose-http |
|---|---|---|
| **Part one: the basics** | | |
| 1. Running something | Workers, the loop, one route | README, "Concepts" (the workers diagram) |
| 2. Routes, path, query, headers | Matching and reading a request | |
| 3. Answers and errors | Responses, and one error shape | |
| 4. JSON bodies | A body that fits the read buffer, read whole | `patterns.md`, "Request bodies" |
| 5. The API from a schema | Generated routes beside hand-written ones | |
| 6. Middleware and scopes | | |
| 7. State | The worker's and the request's; workers share no memory | `patterns.md`, "State that workers share" |
| 8. Testing without sockets | | |
| **Part two: the sample application grows** | | |
| 9. Large bodies | A CSV import gathered whole up to a limit, then an attachment of any size read in pieces | `patterns.md`, "Request bodies" |
| 10. Long responses | An export sent in pieces, and files | `patterns.md`, "Long responses" (the backpressure diagram) |
| 11. Work that waits | A database behind a service: one job per route | `patterns.md`, "Slow work" (the `later` diagram) |
| 12. Two services, or a reply in pieces | When a service can't do it alone | |
| 13. Limits | 503 for a full box, 504 for a late reply, a slow client, a client that has gone, and minutes-long work as a job the client polls | `patterns.md`, "Slow work" |
| **Part three: elsewhere** | | |
| 14. The schema in TypeScript, Python, or Rust | | |
| 15. On a board | | `docs/embedded.md` |

Pages 9 to 13 are goose-rest task 016's approaches 7 and 9 to 12, in its order.

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

## Open questions

- Is `docs/patterns.md` the right name and scope for goose-http's side, or should it
  become "How the loop works", with no recommendations of its own?
- Does part two keep the projects API, or take a sample whose bodies and waits are more
  natural, such as a clinic's records and bookings, from task 015's review?
- Does a goose-http user without goose-rest need more than `patterns.md` and the
  examples?
- Can Goose express the fake library's chained calls (`.bind(...).fetch_all<T>()`), or
  does it read as plain calls, `db::fetch_all<Project>(conn, sql, [owner])`? Check the
  pinned release's spec before the page is written.

## Acceptance criteria

- [ ] The split, the pages, and the open questions are agreed, with the date
- [ ] goose-rest task 016 names the pages and the goose-http sections each links to
- [ ] `docs/patterns.md` has a section for each goose-http link the pages need, and
      names the page that builds on it
- [ ] No page in either project explains what the other holds, past a sentence and a
      link
