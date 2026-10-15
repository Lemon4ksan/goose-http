# Changelog

What each tag adds. Each release names the Goose compiler it was built and tested with.

## v0.3.1 (2026-10-14)

A send to an exchange that no longer waits says so at once, so a service can stop
working for a client that has gone. Goose `46356c2`.
[Release notes](https://github.com/kaitk/goose-http/releases/tag/v0.3.1).

- `http::mail_send` returns `STALE` for a reply to an exchange whose client closed or
  whose wait timed out, where it returned `SENT` and the loop dropped the message.
- `http::mail_live(address)` checks, from any thread and without sending, whether an
  exchange still waits.
- A reply sent in pieces is never refused between pieces.
- Boxes of a program's own can track keys: `http::mail_open(slots, size, waker,
  live_keys, key_shift)` and `http::mail_mark`. The new parameters are optional.
- REST strings' JSON escapes are found 16 bytes at a time.

## v0.3.0 (2026-10-14)

A revised API, compression, files sent without copying on every loop, and a shared
store for immutable data. Goose `46356c2`.
[Release notes](https://github.com/kaitk/goose-http/releases/tag/v0.3.0), with the
migration from `v0.2.0`.

- Precompressed Brotli, Zstandard, and gzip files, and gzip, deflate, and Zstandard on
  the fly through `http.compression`.
- Large files sent without copying on io_uring, its epoll emulation, and IOCP.
- `http.store`: immutable byte blobs shared by every worker.
- `insert_field`, `file_path`, `fail_multipart`, typed mail helpers, and
  `exit_on_error`.
- API changes: request helpers take `const Request&`; `BodyReader`, multipart `Part`,
  and `Stream` framing are enums; `query_int` returns `(value, found)`;
  `stop_on_signals` returns `http::Error` and `mail_open` returns `(Box, Error)`.

## v0.2.0 (2026-10-12)

The HTTP/1.1 essentials: a strict parser, the router, bodies and responses of any size,
conditional and range requests, static files, cookies and `Basic` authorization, forms
and multipart, limits and timeouts, answers that wait, the client's address, IPv6, and
Unix sockets, on io_uring, epoll, kqueue, and IOCP.

## v0.1.0 (2026-10-11)

The first tag: an event loop per worker, `http::serve` (io_uring, IOCP, or a ring over
kqueue) and `http::serve_epoll`, with keep-alive. Requests and responses
are fixed in size: no header lookup, bodies read in pieces, or streamed responses.
