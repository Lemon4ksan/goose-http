# 021: A REST benchmark

Status: todo (asked for 2026-10-12; design below, two choices open)

Plaintext and JSON measure the loop and the parser. A REST benchmark measures what an
API request costs on top: a larger request head with a bearer token or session cookie,
routing among patterns with parameters, an auth check per request, JSON bodies on
writes, and JSON responses from a few hundred bytes to about a megabyte. Every server
answers from the same generated in-memory data, so no database is in the comparison.

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

## How it runs

- Each tier at saturation (requests per second) and at a fixed offered rate (p50 and p99
  latency, CPU per request), as snowtime's own targets measure it.
- wrk with Lua scripts for the mix, and HttpArena's zrk for the fixed rate; each client
  checks its responses, as HttpArena's `validate.sh` does.
- Auth the same in every server: decode the token's claims, check `exp` and `sub`, and
  cache the result by a hash of the token, as the clinic app does after its first
  verification. Goose's stdlib has no base64url, which a JWT needs.

## Open

- Competitors. Proposed: axum (snowtime-native's own stack) and Bun with Elysia, with
  Goose and axum on all three tiers first.
- Auth: claims and a hash cache, as above, or HS256 on every request, which needs
  SHA-256 and HMAC written in Goose.

## Acceptance criteria

- [ ] The data generator, and each tier's routes in the benchmark server, from memory
- [ ] Each tier's wrk script and response checks, passing against Goose
- [ ] The chosen competitors implementing the same tiers, built in release mode
- [ ] Each tier at saturation and at a fixed rate on the desktop, in `docs/results.md`
      with how it was measured
