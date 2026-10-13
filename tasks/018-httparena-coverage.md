# 018: HttpArena's profiles beyond the four we run

Status: in-progress

HttpArena (`MDA2AV/HttpArena`, at `0720ee5`, the commit `bench/httparena.sh` pins) has
27 profiles. This task records which of them HTTP/1.1 without TLS covers, what the
package lacks for the rest, and enters the ones it already serves (2026-10-12).

## The profiles

| Profile | Needs | Goose |
|---|---|---|
| baseline, pipelined, limited-conn, latency-1m | `GET`/`POST` with a query | entered (task 009) |
| latency-10k | latency-1m's endpoint at 10,000 requests per second | entered here |
| latency-500k-8cpu | latency-1m's endpoint on 8 CPUs | left out: `bench/httparena.sh` puts every profile on `SERVER_CPUS`, so it would repeat latency-1m |
| async | `GET /delay/{ms}`, 32,000 connections each waiting 10 ms | entered here |
| json-comp | gzip responses by `Accept-Encoding` | missing: compression |
| static-tls, static-h2, static-h3 | files, with precompressed gzip variants | missing: TLS, HTTP/2 and 3; compression for the variants |
| json-tls, 8gbit | TLS | task 014 |
| baseline-h2, baseline-h2c, json-h2c, baseline-h3 | HTTP/2, HTTP/3 | task 014; HTTP/3 out of scope |
| fortunes, async-db, production-stack | a database | out of scope |
| gateway-64, gateway-h3 | a proxy in front | out of scope |
| unary-grpc, unary-grpc-tls | gRPC over HTTP/2 | out of scope |
| echo-ws, echo-ws-pipeline, echo-ws-limited | WebSocket | out of scope for now; `Upgrade` hands the connection over |

Its request set also has malformed requests (`noise-*.raw`: bare CR, obs-fold, NUL,
a bad `Content-Length`, a huge header, binary), which `validate.sh` sends. The parser
refuses each kind in `scripts/http_client.py hostile`; HttpArena's own validation of
them hasn't run yet.

So for HTTP/1.1 without TLS, compression is the one feature missing, and it is the
next HTTP/1.1 work, in task 022. Serving a precompressed `.gz` next to a static
file, chosen by `Accept-Encoding`, is the cheap half of it.

## async

`validate.sh` asks `GET /delay/{ms}` for 200, `text/plain`, and `{ms}` as the body,
after at least 90% of the delay; `/delay/0` too, and 32 overlapping requests with 32
delays. The benchmark server answers it from the worker's timer table
(`http::later` with no other thread): `server/routes.goose`, `delay`. The entry's
Dockerfile turns waiting on (`MAIL_SLOTS=256 MAX_WAITING=16384`).

Checked by hand on the Windows laptop of task 013, WSL2, with `validate.sh`'s
requests and 4 workers: every check passed on epoll and io_uring. wrk with 4,000
connections on `/delay/10` for 5 s: 144K requests per second and 27 ms mean latency
on epoll, 129K and 30 ms on io_uring, with the server unpinned and sharing CPUs with
wrk. `bench/instructions.sh`, 2 runs, epoll: 1,491-1,523 user instructions per
plaintext request with waiting on, 1,499-1,521 off; peak RSS 3.7 MB against 2.4 MB.

`bench/httparena.sh validate` passed on the Mac (2026-10-12): Docker Desktop 29.8.2 on
the MacBook Pro M1 Pro of `docs/development.md`, the `goose-http-arena` image of
"HttpArena under Docker on macOS", HttpArena `0720ee5`, Goose at `701b6ad` with Goose
`5c83a5a`, `SERVER_CPUS=0-2`. Subscribed: baseline, pipelined, limited-conn, latency-1m,
latency-10k, and async; 32 checks passed and none failed, among them the 9 shapes of
exhaustive fragmentation (1,047 split offsets), `/delay/{ms}` with its timing checks,
and 32 overlapping delays in 0.52 s.

On the desktop (2026-10-12), Goose `4752493` with Goose `6448f3f`, `validate` passed the
same 32 checks, with the 32 overlapping delays in 0.51 s. In `run`, Goose served async at
241K requests per second against tokio's 228K, and spent 30.4 µs of CPU per latency-10k
request against tokio's 30.6 µs and vanilla-epoll's 30.0 µs.

## Acceptance criteria

- [x] The profiles mapped to what they need, and the gap for HTTP/1.1 named
- [x] `/delay/{ms}` in the benchmark server, passing `validate.sh`'s checks by hand
- [x] async and latency-10k in the entry's `meta.json` and `bench/httparena.sh`
- [x] `bench/httparena.sh validate` and `run` with them on the desktop (2026-10-12,
      [results](../docs/results.md#httparenas-profiles))
- [x] Compression (task 022), then json-comp: in the entry, `validate` passing and
      `run` on the desktop (2026-10-14,
      [022.03](022-compression/03-http-compress.md#httparenas-json-comp))
