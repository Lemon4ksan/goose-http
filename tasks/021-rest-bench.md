# 021: A REST benchmark

Status: in-progress (asked for 2026-10-12; designed 2026-10-12)

Plaintext and JSON measure the loop and the parser. This measures what REST traffic
costs an HTTP layer on top: request heads of 0.3-1.2 KB with a bearer token or session
cookie, many distinct URLs over a few routes, small JSON bodies on writes, and JSON
responses from a few hundred bytes to about a megabyte, mixed on one connection.

## Decided (2026-10-12)

- The competitors are the low-level servers of `bench/` that can serve these routes
  without a framework: hyper, tokio's hand-written entry, may-minihttp, xitca-http,
  odin-http, and Tina. Frameworks such as axum or Elysia belong in the framework that
  will sit on this package, in a repository of its own, against a Goose framework.
- Handlers are thin and the same in each server: route, take the id or query, look the
  records up, and write the response. No business rules and no auth: a token or cookie
  is header bytes the server parses and carries.
- One generator, a Goose program with a fixed seed, writes each tier's dataset as JSON
  files at build time (`bench/build.sh`); they aren't committed. Each server loads them
  at startup into its own records, unmeasured. The load scripts' response checks read
  the same files.
- Responses aren't static: they hold the records a request selects, and a few values
  computed per request in fixed places: from the request (a total from a query
  parameter, a range's count, its bounds echoed back) and from the moment
  (`generatedAt`). The checks verify them, so a server that replays cached bytes fails.
- Two ways to write the JSON, each server doing both alike: serialize, walking the
  records with the language's usual JSON library, the default; and template, each
  record's fixed part prebuilt as bytes with the per-request values spliced in. The
  difference splits the HTTP layer's cost from the JSON writer's, most of all for the
  heavy tier's megabyte.

## Sources (2026-10-12)

Three workloads, each read from its source by a subagent, shapes only: no token, name,
or record was copied, and the bodies below are synthetic.

- HttpArena `0720ee5` has no plain REST profile left: its `json` and CRUD profiles were
  removed, and `production-stack` needs HTTP/2, TLS, nginx, an auth service, Redis, and
  Postgres. Its application layer runs from memory on HTTP/1.1.
- snowtime's k6 load test (`perf/stress/scenario.js`): an open-model arrival rate of
  16.76 actions per user-hour, about 75 requests per user-hour, 93% reads, with server
  p95 targets of 300 ms for API calls.
- A clinic booking app in production, not named here: JWTs of about 500 characters
  with an ECDSA signature, verified once and then cached by a hash of the token, and the
  heaviest responses such an app serves, a week of a 10-person schedule and a client's
  visit history. Tier C keeps its sizes, depth, and request mix, but its paths, field
  names, grouping, and token claims are the benchmark's own.

## The tiers

**A. arena**: `production-stack`'s application layer. Requests carry `Authorization:
Bearer` with a 147-byte token.

| Request | Share | Response |
|---|---|---|
| `GET /api/items/{id}`, ids 1-10,000 | 5/6 of reads | the item's JSON |
| `GET /api/me` | 1/6 of reads | `{id, name, email, plan}` |
| `POST /api/items/{1..20}` with `{"name":..., "price":..., "quantity":...}` (51 B) | writes, on 1/8 of the connections | 204; a later read of the id sees it |

**B. snowtime**: the k6 hot path. A session cookie of about 115 characters; writes carry
`Origin`.

| Request | Share | Response |
|---|---|---|
| `GET /api/v1/session` | 25% | about 2 KB object, nested `organizations[]`, `settings` |
| `GET /api/v1/timer` | 25% | `null` 85% of the time, else a 350 B entry |
| `GET /api/v1/organizations/{org}/entries?from=&to=&userId=` (14 days) | 25% | bare array of about 45 entries, about 13 KB |
| `GET /api/v1/organizations/{org}/projects?includeArchived=true` | 15% | about 20 projects, about 3 KB |
| `PATCH /api/v1/organizations/{org}/entries/{id}`, `{"description":...}` | 6% | the entry, about 290 B |
| `POST .../timer/start` and `POST /api/v1/timer/stop` | 4% | `{started, stopped}` about 600 B, or the stopped entry |

**C. heavy**: a clinic's schedule and records, synthetic. Requests carry a bearer token
of about 530 bytes, a JWT whose claims are `sub`, `uid`, `name`, `org`, `auth`, `scope`,
`env`, `tid`, and `exp`, with a signature segment as long as an ECDSA P-521 signature's,
in a head of about 1.2 KB with a browser's other fields.

| Request | Share | Response |
|---|---|---|
| `GET /api/v2/schedule/version?since=`, the schedule's poll | high | `{version, changedAt}` |
| `GET /api/v2/schedule/bookings?start=&end=&staff=1,...,10`, a week of 10 people, 85% full | on a change | `{bookings: [...], count}`, about 700 bookings of depth 4 (slot, client, staff, encounter, items, reminders), 0.7-1 MB |
| `GET /api/v2/schedule/shifts?start=&end=&staff=`, the same week | with each refetch | about 75 shifts, 15 KB |
| `GET /api/v2/encounters/{id}` | medium | one visit, its notes grouped by kind, and the notes of its whole case, 6-50 KB |
| `GET /api/v2/clients/{id}/encounters?limit=20` | medium | `{items: [...], total}`, 20 past visits with free-text notes, 50-90 KB |
| `GET /api/v2/clients/{id}` | low | about 0.5 KB |

A month of the whole team is no request a schedule view makes; a month of one person,
about 300 bookings, can be the rare case.

**D. writes** (proposed 2026-10-12, after B and C): tiers A to C are almost all reads,
and only B sends small JSON bodies, so none of them measures what the HTTP layer does
with a request body. Tier D sends large and structured bodies, and each answer is
computed from the body, so the checker can verify that the server read all of it.

| Request | Body | Response |
|---|---|---|
| `POST /api/v3/imports` | a CSV of several MB, `Transfer-Encoding: chunked` | 201, per-column counts and sums, and the row count |
| `POST /api/v3/attachments` | `multipart/form-data`: a few text fields and a file part of 100 KB to 1 MB | 201, the fields echoed, and the file's size and checksum |
| `POST /api/v3/bookings/batch` | JSON of a few hundred KB, an array of bookings | 201 with each booking's new id, or 422 with a list of field errors |
| `POST /api/v3/forms` | `application/x-www-form-urlencoded`, 50 to 100 fields | 200, the decoded fields as JSON |

The parsing, the CSV and multipart included, is Goose's, as the rest of the server is.
Still open: the mix and its shares, the body sizes, whether uploads come in one
connection's pipeline or spread across all of them, and which competitors stream a body
rather than buffer it whole.

## How it runs

- Each tier at saturation (requests per second) and at a fixed offered rate (p50 and p99
  latency, CPU per request), as snowtime's own targets measure it.
- wrk with Lua scripts for the mix, and HttpArena's zrk for the fixed rate; a checker
  verifies each tier's responses against the dataset files first, as HttpArena's
  `validate.sh` does.
- Goose and one competitor on tier A first, then the other tiers, then the rest of the
  competitors.

## Progress

Tier A (2026-10-12): `bench/rest/gen.goose` writes `arena-items.json` (10,000 items,
1.57 MB) and `arena-users.json` (1,000 users) from a fixed seed. Goose's server
(`bench/rest/goose/rest.goose`) and hyper's (`bench/rest/hyper`, bench/hyper's pinned
versions) answer both JSON ways, and `bench/rest/check.py` passes against both on every
loop: each item and user field against the files, `servedAt` within 2 s, 404 and 401,
and writes answered 204 or 422. `bench/rest/tier-a.lua` sends the mix.

A first quick comparison: Docker Desktop 29.8.2 on the MacBook Pro M1 Pro of
`docs/development.md`, kernel 7.0.14-linuxkit, image `goose-http-dev3` with wrk 4.1.0,
`--security-opt seccomp=unconfined`; Goose `5d1d329` with Goose `5c83a5a`, hyper built
in `goose-http-bench2` with `-C target-cpu=native`. Each server with 3 workers on CPUs
0-2, wrk on CPUs 3-9, `-t 7 -c 256 -d 5 -s bench/rest/tier-a.lua`, 3 rounds alternating
the servers; the first round ran 30-40% lower for every server and is left out. In
thousands of requests per second, rounds 2 and 3:

| JSON | Goose io_uring | Goose epoll | hyper |
|---|---|---|---|
| serialize | 590-634 | 625-629 | 350-392 |
| template | 581-629 | 605-619 | 388-420 |

Tier A's records are small (about 200 bytes), so the two ways cost the same in Goose,
and template gains hyper 7-11% over serde_json. One Goose epoll run in round 1 counted
224 wrk timeouts. The Docker VM isn't the benchmark machine.

## Acceptance criteria

- [ ] Tier D's open questions settled, and the tier built as A to C are
- [ ] The generator, writing each tier's dataset files from a fixed seed
- [ ] Each tier's routes in Goose, loading the files, in both JSON ways
- [ ] Each tier's wrk script and checker, passing against Goose
- [ ] The competitors serving the same tiers, built in release mode, passing the checker
- [ ] Each tier at saturation and at a fixed rate on the desktop, in `docs/results.md`
      with how it was measured
