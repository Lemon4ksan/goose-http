# 003: The epoll HTTP server

Status: done

The HTTP/1.1 server, one edge-triggered epoll loop per core, as
`docs/decisions.md` records. It serves the two TechEmpower-style endpoints the
benchmarks in task 004 call:

- `GET /plaintext` answers `Hello, World!` as `text/plain`.
- `GET /json` answers `{"message":"Hello, World!"}` as `application/json`, built per
  request by Goose code, not from a constant.

Anything else answers 404. Responses carry `Server`, `Date`, `Content-Type`, and
`Content-Length`, as TechEmpower requires.

## Acceptance criteria

- [x] One worker per `hardware_threads()`, or `WORKERS`, each with its own
      `SO_REUSEPORT` listener and epoll loop, and no state shared between them
- [x] Connection state in fixed-size flat structs, with no growth per request; the
      buffer sizes and the connection limit per worker recorded with why
- [x] A request parser in Goose that works on slices of the read buffer, with no copy of
      the request line or headers
- [x] Pipelining: every complete request in the buffer handled, and their responses sent
      in one write; a partial request kept for the next read
- [x] Keep-alive by default, `Connection: close` honored, and HTTP/1.0 answered without
      keep-alive unless asked
- [x] `Content-Length` request bodies read and discarded; chunked requests refused with
      501; oversized request line, headers, and body refused with 414, 431, and 413
- [x] Malformed requests answered 400 and the connection closed, tested with a set of
      hostile inputs (bare `\n`, missing version, huge header count, slow clients)
- [x] The `Date` header rendered once a second per worker
- [x] `curl`, `wrk`, and `h2load --h1` (or `oha`) run against it without errors, and the
      responses match TechEmpower's plaintext and JSON requirements
- [x] The server's line count, Goose and C separately, recorded

## What was built

- `src/http.goose` (namespace `http`): the request parser, routing, the responses, the
  JSON serializer, and the `Date` rendering. It makes no system call, so its unit tests
  run through TinyCC. `parse` returns a `Request` of slices into the buffer it was given,
  and 200, `INCOMPLETE`, or the status to refuse the request with.
- `src/server.goose`: `serve_http` spawns the workers; each `serve` owns a listener, an
  epoll instance, a `reusable` pool of `Conn` slots, and its `Date` string. The
  connection logic is nested inside `serve`, as the samples' parsers are.
- `shim/net.h` and `src/sys.goose`: `net_shutdown` and `sys::shutdown`, `ENFILE`, and
  `SHUT_WR`, with the same `_Static_assert`s. `sys::report` and `sys::check` moved here
  from `src/echo.goose`, for both servers.
- `src/main.goose`: the `http` mode. The echo modes stay; they cost nothing and keep
  `scripts/test-echo.sh` exercising the shim alone. The echo server's `Conn` became
  `EchoConn`.
- Tests: `src/test_http.goose` with `scripts/test-unit.sh`, and `scripts/test-http.sh`
  with `scripts/http_client.py` and `scripts/pipeline.lua`. `scripts/run.sh` is gone:
  TinyCC refuses `src/main.goose` now that it can spawn a thread.

The decisions this task settled, with their reasons, are in
`docs/decisions.md`: the per-worker `reusable` pool, 8 KB read and write
buffers, 16,384 connections per worker, pausing `accept` at that limit and at `EMFILE`,
the HTTP limits, the timeouts, and the lingering close after a refusal.

## How it was tested

On WSL2 Ubuntu 26.04.1, kernel 6.18.40.1-microsoft-standard-WSL2, 16 logical CPUs, Goose
`3536810`, gcc 15.2.0, Python 3.14.4, curl 8.18.0, wrk 4.1.0, h2load 1.68.0, and oha
1.16.0, 2026-10-10:

- `scripts/test-unit.sh`: `src/test_http.goose` passes.
- `scripts/test-http.sh`, which `docs/development.md` describes case by case, passed four
  times in a row against the gcc build with 4 workers, and its fd-limit run with one.
- `scripts/test-echo.sh` still passes.
- The Windows compiler's `--check` passes for `src/main.goose` and `src/test_http.goose`.

Two properties were checked once by hand with strace (`strace -f -e trace=accept4,sendto`)
under `wrk -t 2 -c 64 -s scripts/pipeline.lua ... -- 16` against 4 workers: all four
worker threads accepted connections, and every completed `sendto` was 2,080 bytes, 16
plaintext responses of 130 bytes in one send.

The first wrk runs reported timeouts. They were wrk's: it times requests with the wall
clock, and WSL2 steps that back about every 30 s. A monitor saw the steps at the same
seconds as the two runs out of twelve that reported 64 timeouts, while wrk's own maximum
latency in those runs stayed under 2 ms (`docs/development.md`).

## Line counts

Lines of code, without blank lines and comments:

| File | Lines |
|---|---:|
| `src/http.goose` | 247 |
| `src/server.goose` | 204 |
| `src/sys.goose` | 49 |
| `src/main.goose` | 22 |
| HTTP server, Goose | 522 |
| `shim/net.h`, C | 99 |

Besides these: the echo servers, `src/echo.goose`, 106 lines, and the unit tests,
`src/test_http.goose`, 168.

## Findings

One new entry in `docs/goose-findings.md`: a `return … from` can't carry a struct that
holds a slice of a parameter, though it can carry the slice alone. Nothing blocked the
task. The two task 002 findings are still open; `origin/master` hadn't moved past the pin.
