# 003: The epoll HTTP server

Status: todo

The HTTP/1.1 server, one edge-triggered epoll loop per core, as
`docs/architecture/README.md` proposes. It serves the two TechEmpower-style endpoints the
benchmarks in task 004 call:

- `GET /plaintext` answers `Hello, World!` as `text/plain`.
- `GET /json` answers `{"message":"Hello, World!"}` as `application/json`, built per
  request by Goose code, not from a constant.

Anything else answers 404. Responses carry `Server`, `Date`, `Content-Type`, and
`Content-Length`, as TechEmpower requires.

## Acceptance criteria

- [ ] One worker per `hardware_threads()`, or `WORKERS`, each with its own
      `SO_REUSEPORT` listener and epoll loop, and no state shared between them
- [ ] Connection state in fixed-size flat structs, with no growth per request; the
      buffer sizes and the connection limit per worker recorded with why
- [ ] A request parser in Goose that works on slices of the read buffer, with no copy of
      the request line or headers
- [ ] Pipelining: every complete request in the buffer handled, and their responses sent
      in one write; a partial request kept for the next read
- [ ] Keep-alive by default, `Connection: close` honored, and HTTP/1.0 answered without
      keep-alive unless asked
- [ ] `Content-Length` request bodies read and discarded; chunked requests refused with
      501; oversized request line, headers, and body refused with 414, 431, and 413
- [ ] Malformed requests answered 400 and the connection closed, tested with a set of
      hostile inputs (bare `\n`, missing version, huge header count, slow clients)
- [ ] The `Date` header rendered once a second per worker
- [ ] `curl`, `wrk`, and `h2load --h1` (or `oha`) run against it without errors, and the
      responses match TechEmpower's plaintext and JSON requirements
- [ ] The server's line count, Goose and C separately, recorded
