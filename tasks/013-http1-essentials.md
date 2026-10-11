# 013: HTTP/1.1 essentials

Status: todo (asked for 2026-10-11; design with task 011)

The server parses and frames HTTP/1.1 well enough to pass the smuggling, limit, and
keep-alive checks the competitors fail (`bench/README.md`), but it only serves its own
fixed routes. A program that imports it (task 011) also needs the parts listed below:
header access, bodies and responses of any size, and shutdown. They are ordered by
priority within each group. Line numbers are at `9623c6a`.

Already in place, and kept: tchar methods, 414, 431 (8 KB head, 100 fields), 505 for a
major version other than 1, 501 for a `Transfer-Encoding` other than `chunked`, 400 for
`Content-Length` and `Transfer-Encoding` together or for differing `Content-Length`s,
exactly one `Host` in HTTP/1.1, HTTP/1.0 keep-alive, pipelining, `HEAD`, a cached `Date`,
write backpressure, 10 s head and body timeouts that trickled bytes don't extend, 60 s
idle close, and a cap of 16,384 connections per worker.

Items 6, 7, and 8 decide the shape of task 011's handler: a handler called once with
`(req, body, out)` can't stream. Settle that shape before tagging `v0.1.0`, or tag
`v0.1.0` as serving fixed-size requests and responses only. Items 3, 7, 8, 11, and 13
change the per-connection state, in both loops until task 005 picks one.

## Correctness (RFC 9110, RFC 9112)

1. Absolute-form targets. A server must accept `GET http://host/path` (RFC 9112 §3.2.2);
   `path_of` (`src/http.goose:328`) takes it for a path, so it gets 404.
2. `Host` value. A `Host` with an invalid value must get 400 (RFC 9112 §3.2); only the
   count is checked (`src/http.goose:185-190`).
3. `Expect: 100-continue` (RFC 9110 §10.1.1). curl sends it with large bodies and waits
   up to 1 s for an answer before sending the body anyway. Answer `100 Continue` before reading the body, or
   the final status at once (413, 405); any other expectation gets 417.
4. Response framing a handler can't break: no body or `Content-Length` on 1xx, 204, and
   304; `HEAD` gets `GET`'s fields; no `Transfer-Encoding` to an HTTP/1.0 client, whose
   streamed body ends at close (RFC 9110 §8.6, RFC 9112 §6). The fixed routes are right
   by construction; a program's handler won't be.
5. `OPTIONS *` gets 404 today (RFC 9110 §9.3.7), and an unknown method on an unknown path
   gets 404 where 501 is expected.

## A library a program can use (task 011)

6. Header access. `Request` (`src/http.goose:50-58`) drops every field the parser doesn't
   interpret. The handler looks a field up by case-insensitive name and iterates them,
   as slices into the read buffer, repeated fields included.
7. Bodies larger than the read buffer. A body must fit in the 8 KB buffer with the head
   (`src/http.goose:209-228`) or gets 413. The handler reads `Content-Length` and chunked
   bodies in buffer-sized pieces, up to a configurable limit; a body it ignores is still
   drained. This is the largest change to the io_uring loop.
8. Large and streamed responses. A response is at most 512 bytes (`MAX_RESPONSE`,
   `src/http.goose:23`). The handler can send a body of any size, and stream one with
   chunked encoding, while backpressure pauses the handler instead of buffering
   without bound. Check what shape spec §7.6's compile-time function values allow for a
   handler that resumes.
9. Path and query decoding. Only `query_int` exists (`src/http.goose:378`), without
   percent-decoding.
10. Limits and timeouts as configuration, not constants (`src/http.goose:11-23`,
    `src/app.goose`), with a body and a write timeout apart from the head's.
11. Graceful shutdown. The loop never returns. On `SIGTERM` or a call, workers close
    their listeners, answer the next request on each connection with `Connection: close`,
    finish what's in flight within a grace period, and return. Needs a wakeup in the shim
    for both the epoll and the io_uring wait.
12. Error responses from the handler that keep the connection open when the request was
    read whole; `refuse` always closes.

## Later

13. `Upgrade`, so a handler can answer 101 and take over the connection (WebSocket;
    task 014's `h2c` upgrade, if it's ever wanted).
14. Request trailers (skipped at `src/http.goose:246-257`), and response trailers on
    chunked responses.
15. A router: method and path patterns with parameters, 405 with `Allow` from the routes.
16. Response helpers: a configurable or absent `Server` (hard-coded in `status_line`),
    conditional `GET` (304), `Range`, static files through `sendfile`.

## Acceptance criteria

- [ ] `GET http://tfb-server/plaintext` answers as `GET /plaintext`
- [ ] `Host: a b` and `Host: [::1` get 400; `Host: x:8080`, `Host: [::1]:80`, and an
      empty `Host` get 200
- [ ] A `POST` with `Expect: 100-continue` gets `100 Continue` before its body is read, or
      its final status without one; `Expect: other` gets 417
- [ ] Unit tests show 204, 304, and `HEAD` without a body, and a streamed body to an
      HTTP/1.0 client ending at close, whatever the handler writes
- [ ] `OPTIONS *` gets 200 with `Allow`; an unknown method gets 501
- [ ] The handler reads any request field by name, and iterates them
- [ ] A handler reads a 100 MB `Content-Length` body and a 100 MB chunked body in pieces;
      a handler that ignores them leaves the connection usable for the next request
- [ ] A handler sends a 10 MB body, and streams a chunked one, with each connection's
      memory bounded
- [ ] Decoded path and query, with 400 for an invalid `%` escape
- [ ] Limits and timeouts set by the program, with tests at non-default values
- [ ] `SIGTERM` drains and stops every worker within the grace period, in both loops
- [ ] Every item above has a check in `scripts/http_client.py` or `src/test_http.goose`
- [ ] The benchmark routes, served through the handler, keep their rate in
      `bench/run.sh`'s closest cells within the runs' spread
