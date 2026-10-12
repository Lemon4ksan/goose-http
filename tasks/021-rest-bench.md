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

**D. writes** (decided 2026-10-12, after B and C): tiers A to C are almost all reads,
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
Decided for tier D (2026-10-12):

- The mix: the JSON batch 40%, the form 30%, the attachment 20%, and the CSV import
  10%. The import still carries most of the bytes.
- Body sizes: the CSV 2-8 MB, the attachment's file 100 KB to 1 MB, the JSON batch
  200-500 KB, and the form 2-8 KB. The servers allow bodies of up to 16 MB, past
  `max_body`'s default of 1 MB.
- The uploads come from a fixed eighth of the connections, as tier A's writes do, and
  the other connections send the rest of the mix: uploads come from a few clients, such
  as an import tool, beside many that browse.
- Each server reads a body the way its HTTP layer offers: streamed where it can be, as
  Goose's bodies in pieces and hyper's body stream are, and buffered whole otherwise.
  The results say which way each server read. Buffering everywhere would be simpler,
  but would hide the cost streaming saves.
- The data doesn't change, as in tier B: each answer is computed from the body (counts,
  sums, checksums, field errors), so the checker verifies the server read every byte. A
  shared store would measure the store, not the HTTP layer.
- A mixed run sends tier C's reads at a fixed rate, about half of C's saturation, with
  and without tier D's uploads on the same server, and compares the reads' p50 and p99
  latency. A worker runs one handler at a time, so a handler parsing a multi-megabyte
  CSV holds up its worker's other connections. A connection whose response is still
  queued (`max_queued`) isn't read until the client takes it, so a client that sends
  while it reads can stall. The run shows how much of either reaches the reads.

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

Tier B (2026-10-12): the generator writes `snow-orgs.json` (20 organizations of 20
projects), `snow-users.json` (200 users, each a member of 2 to 5 organizations, with the
session's settings and fill), `snow-entries.json` (36,763 entries over the 60 days up to
2026-10-12T09:00Z, 12 MB), and `snow-load.txt`, the cookie and ids for each user that
`bench/rest/tier-b.lua` sends. Shapes, member order, checks, and error bodies follow
snowtime's Hono routes; a 14-day window averages 41 entries and 13.4 KB. Where the
benchmark differs from snowtime:

- The data doesn't change, since each Goose worker holds its own copy. PATCH answers
  the entry with the description it was sent; timer start answers the dataset's running
  timer as `stopped`; timer stop takes an id the dataset lacks for a timer started at
  the uuidv7's time, as tier-b.lua starts them, and answers 404 for one older than a day.
- A 400 for a query or body that doesn't validate has one message, `Invalid input.`,
  where snowtime gives valibot's.
- `fill` is the dataset's, and only the active organization has entries.
- tier-b.lua sends Origin on every request, as k6's scenario does, with its
  `Sec-Fetch-Site`, `User-Agent`, `CF-Connecting-IP`, and `X-Bench-*` fields.

Tier C (2026-10-12): the generator writes 10 staff, 24 services, 1,000 clients (about
480 bytes each), 2,698 bookings and 297 shifts over the 4 weeks from 2026-09-07, and 5,111
encounters: 2,413 past visits of clients 1 to 100 over 2 years, in cases of 2 to 12, and
one per booking. A week of 10 staff's bookings is 668-681 bookings and 715-728 KB; a
month of one staff member about 270 and 288 KB; an encounter with its case's notes 3-46
KB; a client's last 20 visits 59-77 KB. The bearer token is an ES512-shaped JWT of
about 557 characters with a 176-character signature segment, in a head of about 1.28 KB.
Its claims are the ones listed above, in a structure of the benchmark's own. Days in the
queries are UTC's, and the version counts minutes since 2026-09-01.

`check.py` passes against Goose, on both loops in both JSON ways, on macOS and in Docker,
and against hyper in both JSON ways in Docker, for tiers A to C. hyper's tiers B and C
(`bench/rest/hyper/src/snow.rs`, `heavy.rs`) answered 104 requests byte for byte as Goose
does, error paths included.

A quick comparison, set up as tier A's above: Goose and hyper at `e588a65`, Goose
`5c83a5a`, `--ulimit nofile=1048576:1048576`, 3 rounds alternating the 6 servers, `-d 5`
with `tier-b.lua` or `tier-c.lua`. No run counted a socket error or a status other than
2xx. All 3 rounds, in thousands of requests per second:

| Tier | JSON | Goose io_uring | Goose epoll | hyper |
|---|---|---|---|---|
| B | serialize | 244-246 | 229-231 | 142-142 |
| B | template | 295-297 | 293-297 | 173-178 |
| C | serialize | 26.7-28.3 | 33.3-35.0 | 22.5-23.9 |
| C | template | 41.4-43.1 | 59.1-60.9 | 58.1-59.7 |

- Goose answers tier B at 1.6-1.7 times hyper's rate both ways. Templates gain Goose
  20% and hyper 22-25%.
- On tier C, Goose's epoll loop serializes at 1.5 times hyper's rate, and with templates
  the two tie at about 4.1 GB/s, copying prebuilt bytes.
- io_uring loses to epoll on tier C by 20-30%, where tier B shows no such loss. The
  responses of up to a megabyte are the difference; the cause isn't measured yet.
  Round 3's io_uring template run had a 198 ms maximum latency, where the others stayed
  under 60 ms.
- Goose uses 4 to 5 times hyper's memory. Peak RSS, startup's included: tier B 123-152
  MB serialized and 248-276 MB templated, against hyper's 31-34 and 54-55; tier C 158-188
  and 402-412 MB, against 36-38 and 77-79. Each of Goose's 3 workers holds its own copy
  of the records, and templates add a copy of their JSON. hyper's threads share one.

Tier D (2026-10-12), Goose's side: the generator writes 6 CSV imports of 2.4-7.8 MB, half
with CRLF line ends, whose descriptions are sometimes quoted around a comma, a doubled
quote, or a line break; 12 multipart bodies of three text fields and a PDF-named file of
100 KB to 1 MB, whose random bytes hold the start of the delimiter now and then; 24
batches of 210-490 KB, every fourth with 1 to 5 invalid bookings; and 48 forms of 50-100
fields and 3-7 KB. `rest.goose` serves them with `TIER=d`, which also loads and serves
tier C, for the mixed run:

- The CSV and the multipart body are read as they arrive, the CSV by a reader of its
  own and the multipart body by `http::each_part`. The batch and the form are joined
  first, as `json::reader` takes only a whole text (`docs/goose-findings.md`).
- A request's state is its route and an index into the worker's spools, which hold each
  reader's state, and runs of a `reusable[]` spill for what a request joins.
- The limits are 16 MB for the CSV and the attachment (`max_body`), 1 MB for the batch,
  and 64 KB for the form, with `http::body_within`. It counted a `Content-Length` body
  that came in pieces twice, the declared length and then each piece, so a body over
  half the limit got 413; fixed, with a test in `test/test_api.goose`.

`check.py d` sends each body whole, in 64 KB chunks, and in chunks of 1 to 9,000 bytes,
and compares each answer with what it computes from the body with Python's `csv`,
`zlib.adler32`, `json`, and `urllib.parse`. It also checks CSVs, multipart bodies,
batches, and forms that don't validate (400 with the bad record, 422 with each field
error), and 401, 404, 413, and 415. It passes on macOS and in Docker, on both loops,
with tier C's checker passing against the same server. `tier-d.lua` runs as two wrk
processes, one per role, since wrk's script can't tell its connections apart: uploads
(attachments and chunked CSVs, 2:1) on an eighth of the connections, and batches and
forms (4:3) on the rest. wrk counts the invalid batches' 422s, about a seventh of the
second role's responses, as errors.

hyper's tier D (`bench/rest/hyper/src/writes.rs`, 2026-10-12) passes the same checks in
Docker, beside tier C. It reads the CSV from hyper's body stream frame by frame, with a
port of Goose's reader: the `csv` and `csv-core` crates accept a quote inside an
unquoted field and a lone CR, which the checker refuses. The multipart body goes
through multer 3.1.0, the streaming parser that axum's `Multipart` uses. The batch is
collected whole and read by serde_json into borrowed `RawValue` members, which are then
checked by hand to list each field error. The form is collected whole and decoded by
hand. multer stops reading at the close delimiter, and hyper closes a connection whose
request body wasn't read to its end, as a chunked body's last chunk often isn't by
then. The handler therefore lends multer the body and drains the rest after.

A quick comparison of tier D (2026-10-12): Docker Desktop 4.94.0 (engine 29.8.2) on the
MacBook Pro M1 Pro of `docs/development.md`, kernel 7.0.14-linuxkit, image
`goose-http-dev3` with wrk 4.1.0, `--security-opt seccomp=unconfined --ulimit
nofile=1048576:1048576`; Goose and hyper at `9d47fba`, Goose `5c83a5a`. Each server ran
`TIER=d` with 3 workers on CPUs 0-2. On CPUs 3-9, two wrk processes ran at once with
`-d 10 --timeout 10s -s bench/rest/tier-d.lua`: the uploads role with `-t 1 -c 32`
and the forms role with `-t 6 -c 224`. There were 3 rounds alternating the servers.
Peak RSS comes from `VmHWM`. Both servers read the CSV and the multipart body as they
arrive, and join the batch and the form. Rates are in requests per second, with the
body bytes they imply (1.96 MB per upload and 210 KB per request of the forms role, on
average):

| Server | Uploads | Uploads p50 | Forms role | Forms p99 | Peak RSS |
|---|---|---|---|---|---|
| Goose io_uring | 91-95 (180 MB/s) | 169-193 ms | 4,214-4,262 (890 MB/s) | 109-115 ms | 243-254 MB |
| Goose epoll | 240-289 (470-565 MB/s) | 75-78 ms | 3,570-3,832 (750-805 MB/s) | 111-389 ms | 212-227 MB |
| hyper | 25-62 (48-121 MB/s) | 116-128 ms | 2,600-2,783 (546-585 MB/s) | 272-293 ms | 151-186 MB |

- Goose takes 1.3-1.6 times hyper's batches and forms, and 1.5 to 12 times its uploads.
- hyper's uploads starve beside the forms role. Alone, on `-c 4` without it, hyper took
  720 uploads per second to Goose epoll's 598, and each upload took as long on both. A
  first run with wrk's default 2 s timeout counted 11 of hyper's uploads as timeouts in
  5 s; the cause isn't measured. Tokio polling each connection's task in turn, an
  upload's task taking one read per turn, would fit.
- Goose's io_uring loop takes uploads at a third of its epoll loop's rate, alone too:
  80 against 229 per second with 2 workers. Its receives come in the ring's 4 KB
  provided buffers, against epoll's reads into the 8 KB read buffer; whether that is
  the cause isn't measured yet.
- Goose holds 1.1-1.7 times hyper's memory. Each of its workers loads its own copy of
  tier C's records.

The mixed run (2026-10-12), set up as above: tier C's reads at a fixed 11,000 requests
per second, about half of hyper's tier C saturation and the lowest of the three
(`tier-c.lua` with `-t 7 -c 256 -d 5`: Goose io_uring 27.9K, Goose epoll 34.4-34.6K,
hyper 22.6-22.9K, each as with `TIER=c`). The fixed rate comes from HttpArena's zrk
2.3.0 (its aarch64 release, as `bench/httparena.sh` pins it), which corrects for
coordinated omission. zrk sends one URL per process, so 6 processes ran, one per
route at its share of `tier-c.lua`'s mix, on 224 connections:

- version poll: 55%, 64 connections
- a week of 10 staff's bookings (715 KB): 9%
- the same week's shifts: 9%
- encounter 1200: 12%
- client 42's last 20 visits: 12%
- client 7: 3%

Every route other than the poll had 32 connections. wrk 4.1.0 has no fixed rate, and
wrk2 bundles LuaJIT 2.0, which has no arm64 port. Each server ran 15 s alone and 15 s
beside `tier-d.lua`'s uploads role (`-t 1 -c 32`, closed loop), in 2 rounds alternating
the servers. Read latency, in ms, as p50 / p99 over both rounds:

| Server | Alone: poll | Alone: bookings | Beside uploads: poll | Beside: bookings | Uploads |
|---|---|---|---|---|---|
| Goose io_uring | 0.12 / 1.5-1.6 | 1.01 / 1.3-1.5 | 9.8-10.1 / 23-26 | 10.5-11.0 / 15 | 395-398/s |
| Goose epoll | 0.11 / 0.8 | 0.86 / 1.0-1.2 | 5,585-5,749 / 11,858-11,964 | 1,897-2,196 / 6,404-6,670 | 606-613/s |
| hyper | 0.11 / 1.0 | 1.33-1.36 / 1.7-1.8 | 8.4-8.7 / 22-28 | 8.6 / 17-18 | 394-398/s |

- Alone, every server holds the rate with every route's p99 under 2 ms. Goose's epoll
  loop is the fastest, and hyper's bookings take 0.3-0.5 ms longer at the median.
- Beside uploads, hyper and Goose's io_uring loop hold the reads' rate. Every route's
  median rises to 8-11 ms and its p99 to 14-28 ms, hyper's a little lower at the median.
- Goose's epoll loop doesn't hold it. The reads fell to 637-711 per second on most
  routes and 1,272-1,364 for the poll, with medians of 2-6 s; only the client route,
  the smallest rate, kept to 48-50 ms. Meanwhile the loop took 606-613 uploads per
  second, half again as many as the others. A worker that reads a connection's body for
  as long as data keeps arriving would starve its other connections this way, and
  io_uring's one 4 KB buffer per completion would interleave them; neither is measured
  yet. It is the stall the design above expected, on the epoll loop alone.

io_uring against epoll (2026-10-12), the three losses above. Set up as tier D's
comparison: Docker Desktop 4.94.0 (engine 29.8.2) on the MacBook Pro M1 Pro, kernel
7.0.14-linuxkit, image `goose-http-dev3` with wrk 4.1.0, `--security-opt
seccomp=unconfined --ulimit nofile=1048576:1048576`, 3 workers on CPUs 0-2, the load on
CPUs 3-9. The experiments ran on `f2fba78`, with the changes under test and temporary
counters in both loops (completions, receives, ENOBUFS, stalls, sends, and bytes read
per epoll turn), printed when a worker stopped, and the server's user and system CPU
time from `/proc/PID/stat` over each run, 2 rounds each:

- Tier C's loss isn't `max_queued`. With it at 64 KB, 1 MB, and 16 MB, io_uring served
  28.1-28.4K requests per second serialized and 43.4-43.9K templated, and no
  connection ever stalled: `pump` checks `blocked()` before its last `flush`, so a
  client that doesn't pipeline never reaches it. Both loops used all 3 CPUs, and
  io_uring spent about 1.6 µs more user time per request. The epoll loop sent each
  response, up to 728 KB, in one `send`, with no `EAGAIN`; `ur_send` copied each one,
  74 KB on average, into its own buffer first.
- Sending a response inline in `ur_send` (`62e1d45`, `docs/architecture/README.md`)
  took io_uring to 34.7-34.9K serialized and 59.6-60.4K templated, epoll's 34.9K and
  59.9-61.2K. Sent inline at every size, tier B fell from 232-234K to 209-211K
  serialized and from 275-279K to 261-262K templated, epoll's rate; at 64 KB and up
  it stayed at 231-232K and 279-280K.
- Uploads alone (`tier-d.lua`'s uploads role, `-t 1 -c 32 -d 10`) didn't show
  io_uring at a third of epoll's rate: 660 per second against epoll's 429 in the
  first round, and 755-763 for epoll later with the same loop. The first round's
  epoll runs may have shared the VM with another load; the cause isn't known. Ring
  buffers of 16 KB and 64 KB cut io_uring's completions per upload by up to 16 times
  and its ENOBUFS from 36-45K per worker to under 700, yet took 629-642 uploads a
  second against 660: the per-buffer completions aren't what limits it.
- The epoll loop read a whole upload, up to 8.15 MB, in one turn, 457-477 times per
  worker in 10 s. Bounding a turn at 16 KB (`Config.max_read`, `5ca934f`) kept the
  mixed run's reads beside uploads at p50 0.42-1.18 ms and p99 1.4-4.0 ms, and 64 KB
  at p50 1.7-2.5 ms and p99 4.2-5.6 ms. Uploads alone fell 2-3%, to 737-744 per second
  at either bound.

The committed loops at `5ca934f`, Goose `c38dc0f` (the image's compiler is `5c83a5a`'s;
the commits between change only docs), hyper at `9d47fba`, with no counters. Tiers A to
C ran `-t 7 -c 256 -d 5` with each tier's script, 3 rounds alternating the loops; the
other runs as above. In thousands of requests per second:

| Tier | JSON | Goose io_uring | Goose epoll |
|---|---|---|---|
| A | serialize | 616-671 | 608-636 |
| A | template | 662-672 | 631-654 |
| B | serialize | 231-233 | 213-219 |
| B | template | 274-282 | 264-268 |
| C | serialize | 33.3-33.7 | 35.1-35.2 |
| C | template | 58.6-59.9 | 58.7-61.4 |

wrk counted 239 and 177 timeouts in two of io_uring's tier A runs, and no other socket
error. io_uring's loss on tier C fell from 20-30% to 4-5% serialized and 0-3% templated.

Uploads alone, 3 rounds: io_uring 663-667 per second with a p50 of 31-36 ms, epoll
737-740 with 29-35 ms. io_uring is 10% behind, with the CPUs saturated in both; why
isn't measured.

Tier D's two roles at once, 3 rounds, in requests per second:

| Server | Uploads | Uploads p50 | Forms role | Forms p99 | Peak RSS |
|---|---|---|---|---|---|
| Goose io_uring | 92-95 | 169-192 ms | 4,305-4,317 | 108-112 ms | 239-247 MB |
| Goose epoll | 76-78 | 193-222 ms | 4,675-4,706 | 120-123 ms | 249-251 MB |
| hyper | 20-24 | 122-172 ms | 2,832-2,839 | 224-227 ms | 154-175 MB |

The epoll loop no longer favors the uploads: it took 240-289 a second before, beside
3,570-3,832 forms. Each Goose loop now gives a connection about the same share of the
worker, and the uploads hold an eighth of the connections. io_uring's uploads at a
third of epoll's rate beside the forms role came from this difference, not from
io_uring's receives.

The mixed run, 2 rounds, read latency in ms as p50 / p99:

| Server | Alone: poll | Alone: bookings | Beside uploads: poll | Beside: bookings | Beside: other routes | Uploads |
|---|---|---|---|---|---|---|
| Goose io_uring | 0.11-0.13 / 1.0-1.2 | 0.86-0.88 / 1.2-1.3 | 3.9-4.6 / 10.8-42.8 | 3.7-3.9 / 9.5-10.4 | 3.1-4.6 / 9.4-13.0 | 442-448/s |
| Goose epoll | 0.12 / 0.8-0.9 | 0.88 / 1.1-1.2 | 0.44-0.47 / 1.5-1.7 | 1.15-1.18 / 1.9-2.3 | 0.52-0.79 / 1.6-2.1 | 503-505/s |
| hyper | 0.12-0.13 / 1.2 | 1.35 / 1.8 | 8.4 / 22.7-23.8 | 8.5-8.6 / 17.5-17.8 | 7.7-8.1 / 16.9-17.4 | 402-406/s |

Every server held the 11,000 reads a second in every run. Beside uploads, the epoll
loop now keeps every route's p99 under 2.3 ms, and io_uring's medians fell from 8-11 ms
to 3-5 ms, with one round's poll p99 at 42.8 ms. io_uring hands the worker 256
completions per wait, each 4 KB of some upload, before it answers the next read; that
fits its remaining 4 ms, and isn't measured.

The other competitors (2026-10-12). tokio's entry, may-minihttp, and xitca-web serve the
tiers from one crate, `bench/rest/rust`, a port of hyper's routes behind a request head
and a response of its own; each server only frames requests and responses around it.
hyper keeps its own copy, so its measured binary doesn't change. odin-http and Tina
share `bench/rest/odin`, which reads each dataset file with `core:encoding/json` into
structs of the answers' shapes and serializes them per request with the same library;
the files already hold each record in the shape the routes answer it. Odin has no
multipart library, so `bench/rest/odin/writes.odin` has a streaming reader of its own,
which accepts and refuses what multer does for the checker's bodies. Each server keeps
its configuration in `bench/`: its crate versions in `Cargo.lock`, started from its
`bench/` entry's, its release profile, and its build flags. The Rust routes write JSON
with serde_json, as hyper's do, where xitca-web's `/json` entry uses sonic-rs.

How each server reads tier D's CSV and multipart body, and what it changes:

| Server | Reads | Changes and gaps |
|---|---|---|
| tokio | whole: the entry's read loop answers a request once its body is buffered | The entry closes a connection whose buffer passes 1 MB; here 17 MB. A chunked body is walked chunk by chunk and copied out once, where the entry copied it again on each read. A body over its route's limit is refused with 413 as soon as its length or its chunks show it. |
| may-minihttp | as it arrives, through `BodyReader`'s `fill_buf` | Tier D is a gap: the crate frames a body by `Content-Length` alone, and leaves a chunked body's bytes to be parsed as the next request. The server answers a chunked body with 411, and the checker fails on its first chunked import. The forms role, all `Content-Length`, works. |
| xitca-web | as it arrives, from the h1 dispatcher's body stream | One service in place of the entry's router. multer takes a `Send` stream and xitca's isn't, so multer is polled with a no-op waker as each piece is pushed into its queue. |
| odin-http | whole: `http.body` hands the handler the whole body, a chunked one decoded | `http.body` on a request without a body marks the body failed, which closes the connection, so only POST and PATCH bodies are read. |
| Tina | as it arrives, in `Body_Chunk` events of up to 10 KB | Tier D is a gap; see below. |

Tina needed more than its defaults, each in a comment in `bench/rest/tina/main.odin`:

- Tina answers an unmatched path with a 404 and an unregistered method with a 405 of its
  own, so one event handler takes every path of one to eight segments, for GET, POST,
  PATCH, PUT, and DELETE, and the app routes from there.
- `respond_bytes` takes only a body that fits the connection's egress buffer, 4 KB by
  default. Responses go out as fixed-length streams through a buffer of 62 KB
  (`-define:HTTP_EGRESS_BUFFER_SIZE=63488`); the documented maximum, 65535, fails a
  compile-time assertion, since the buffer is part of a connection that must fit in 64 KB.
- Tina's scratch arena lasts one handler call. Each request takes an arena from its
  shard's pool and gives it back once its response is written.
- A streamed body's bytes that a receive leaves over are kept in the pipeline tail, 8 KB
  by default, and the connection is closed when they and the next receive don't fit.
  Receives are up to 10 KB, so any body over about 8 KB failed. The tail holds two
  receives here (`pipeline_size_max`).
- After a few bodies sent in chunks of 1 to 3 bytes, with pauses of 3 s between
  requests, on one kept-alive connection, reading a `Body_Chunk`'s data faults with
  SIGSEGV and Tina quarantines the shard. A handler that only sums each piece's bytes
  faults the same way; one that never reads them doesn't. The checker sends such bodies,
  and pauses while it computes each answer, so Tina fails tier D's checker, on the
  defaults as well. Buffered bodies would avoid the stream, but Tina reserves a buffered
  route's whole limit for every connection slot: 16 MB times 1,024 slots per shard.

`check.py` passes against tokio, xitca-web, and odin-http on tiers A to D, and against
may-minihttp and Tina on tiers A to C, both JSON ways each, in Docker (`goose-http-dev3`,
`--security-opt seccomp=unconfined`). A 3 s wrk run of each tier's script counted no
socket error and no status but tier D's 422s, except may-minihttp's uploads role: 224
read errors, its chunked imports.

## Acceptance criteria

- [x] Tier D built as A to C are, and its mixed run with tier C
- [x] The generator, writing each tier's dataset files from a fixed seed
- [x] Each tier's routes in Goose, loading the files, in both JSON ways
- [x] Each tier's wrk script and checker, passing against Goose
- [ ] The competitors serving the same tiers, built in release mode, passing the checker
- [ ] Each tier at saturation and at a fixed rate on the desktop, in `docs/results.md`
      with how it was measured
