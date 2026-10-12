# 015: What a REST and JSON API needs from the package

Status: todo (asked for 2026-10-12)

A REST and JSON API, such as a Goose port of snowtime-native's, needs more from the
package than task 013 gave it. TLS, HTTP/2, and compression are task 014's or later.
This task covers the HTTP-level parts that remain below a framework: CORS, sessions,
middleware, and an outgoing client stay out of it. The items are ordered by priority
within each group. Each item looks at two or three competitors' code before its design,
as task 013's did.

## Blocks an API

1. **Answers that wait.** A handler answers before it returns, or later at `MORE`.
   Nothing lets a connection wait for work done elsewhere, such as a database query on
   another thread or a timer, and be woken to answer. A blocking call in the handler
   stalls every connection of its worker. Long polling and Server-Sent Events that wait
   for an event need the same thing. The design needs:
   - A way for another thread to wake a worker's loop. Each shim's wait already has a
     wakeup for `http::stop` (task 013, item 11).
   - A handle to an exchange that outlives the call, and that a closed or reused
     connection invalidates, as `shim/uring.c`'s generations do for fds.
   - A per-exchange timer.

   Task 014's HTTP/2 needs this too, because one connection carries many streams and
   any of them can wait. Design the two together.
2. **The client's address.** Neither `Event` nor `Request` carries it, and rate limits,
   logs, and audits need it. The io_uring loop's multishot accept passes no address
   (`shim/uring.c`, `ur_accept`), and `AcceptEx` gets one on Windows. A `getpeername`
   only when the handler asks costs nothing per request. Add a helper that takes the
   client's address from `Forwarded` or `X-Forwarded-For`, but only when the connection
   comes from a proxy the program trusts.
3. **IPv6 and Unix sockets.** `Config.address` holds an IPv4 address (`http.goose`,
   `ipv4`). Listen on IPv6 and dual-stack too, and on a Unix socket, the usual way to
   run behind nginx or Caddy.
4. **Checked fields.** `http::field` writes its name and value as they are. A value
   with CR or LF from a request, such as a `Location` or a file name in
   `Content-Disposition`, splits the response. Check them with `is_field_value` and the
   tchar set, and decide what a bad one does: drop the field, or answer 500.

## Helpers

5. **Media types.** Parse `Content-Type` into its type and parameters, so that
   `application/json; charset=utf-8` matches `application/json`. A helper that answers
   415 for the wrong type, and one that picks a type from `Accept` or answers 406.
6. **Cookies.** Read `Cookie` pairs, and write `Set-Cookie` with `Max-Age`, `Expires`,
   `Path`, `Domain`, `Secure`, `HttpOnly`, and `SameSite` (RFC 6265).
7. **`Authorization`.** Split the scheme from its credentials, and decode `Basic` with
   the stdlib's base64.
8. **Form bodies.** Read `application/x-www-form-urlencoded` pairs with `each_query`'s
   parser and `decode`, with `plus` set. Read `multipart/form-data` from `BODY` pieces,
   so an upload doesn't sit whole in memory.
9. **A log after each response.** A call after the exchange ends, with its status, the
   bytes sent, the time from the head's first byte to the response's last, and the
   client's address. Today a handler knows none of these at the end.
10. **JSON responses.** `respond_json`, which writes a body the stdlib's `json.goose`
    formats, with its content type. Check that the stdlib's parser takes a body that
    comes in `BODY` pieces, or record that it can't in `docs/goose-findings.md`.
11. **Limits.** A cap on requests per connection, and a body limit per route below
    `Config.max_body`. A streaming handler can already refuse at `REQUEST`; this is a
    helper for it.

## Acceptance criteria

- [ ] A handler hands a request to another thread and answers it from there, without
      blocking its worker, on every loop. The handle of a closed connection is refused,
      and an exchange can wait for a timer.
- [ ] A handler reads the client's address on every loop, and a proxied request's,
      from trusted proxies only.
- [ ] The server listens on IPv6, dual-stack, and on a Unix socket on Linux and macOS.
- [ ] A field with CR, LF, or an invalid name never reaches the client.
- [ ] Helpers for items 5 to 11, each with a check in `scripts/http_client.py` or
      `test/test_http.goose`.
- [ ] The benchmark routes keep their rate, measured as task 013's were.
