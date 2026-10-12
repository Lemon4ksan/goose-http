# 015: What a REST and JSON API needs from the package

Status: in-progress (asked for 2026-10-12)

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
- [x] A field with CR, LF, or an invalid name never reaches the client (2026-10-12; see
      "Checked fields")
- [ ] Helpers for items 5 to 11, each with a check in `scripts/http_client.py` or
      `test/test_http.goose`.
- [ ] The benchmark routes keep their rate, measured as task 013's were.

## Checked fields (2026-10-12)

A field that `http::is_field` refuses is dropped, and the rest of the response goes out.
`is_field` takes a name of token characters (RFC 9110 §5.1) and a value that
`is_field_value` takes. `field` checks each field, and so do the writers that take a
name or value from the handler: `respond`'s and `serve_file`'s content type,
`upgrade`'s protocol, and each line of `end`'s trailers. A handler that would rather
answer 500 calls `is_field` before `start`. `finish`'s `fields` and the handler's own
appends to `out.buf` stay unchecked, for constant text; the benchmark routes write their
fields that way, so the check costs them nothing.

What the competitors in `bench/` do with a bad field:

- hyper and xitca-web take fields as the `http` crate's `HeaderName` and `HeaderValue`.
  Building one from bytes returns an error for CR, LF, or another control byte
  (`http` 1.4.2, `header/value.rs`, `is_valid`), so the program handles the error before
  the response exists, often with a 500; `from_static` panics.
- odin-http (`fac113f`) writes every field, escaping LF as the two bytes `\n` in names
  and values (`headers.odin`, `sanitize_key`; `response.odin`,
  `write_escaped_newlines`).
- may-minihttp 0.1.11 takes whole field lines as `&'static str` and checks nothing.

Dropping beats answering 500 here because the writers put the head into the write
buffer as the handler calls them. By the time a field is refused, the status line and
the fields before it are in the buffer, and a head begun in an earlier call may have
gone to the client; a 500 could replace it only in some cases. Dropping keeps each
response well formed in every case, and leaves the 500 to a handler that checks first,
as hyper's programs do.

Checks: `test/test_http.goose`, `test_reply` (bad names and values for `field` and
`respond`) and `test_stream` (trailers).

## Helpers (2026-10-12)

Each helper is Goose in the package, with its checks in `test/test_api.goose`.

The competitors mostly have nothing to compare: hyper 1.12.0, may-minihttp 0.1.11, and
xitca-http 0.8.2, the parts of them `bench/` builds, have none of these helpers. The
notes below cite odin-http (`fac113f`), and xitca-web 0.8.0, the framework over
xitca-http that `bench/` doesn't build.

- Media types (`media.goose`). odin-http only maps file extensions to types
  (`mimes.odin`), and xitca-web's `Json` and `Form` require a `Content-Type` without
  reading it (`handler/types/header.rs`); neither answers 415 or 406. Here,
  `media_type` parses a `Content-Type` into its type, subtype, and parameters, which
  `each_param` and `param_of` read, unquoting a quoted string. `has_type` compares a
  request's type and subtype ignoring case and parameters, and `require_type` answers
  415 with the wanted type in `Accept` otherwise. `negotiate` picks from the handler's
  offers by `Accept` (RFC 9110 §12.5.1): the most specific matching range sets an
  offer's weight, ties go to the first offer, and a range that can't be read is
  skipped. `accept_or_406` answers 406 when no offer is acceptable.
- Cookies (`cookie.goose`). odin-http splits `Cookie` on `"; "` exactly, keeps the
  quotes, and lets the last of a repeated name win (`cookie.odin`); xitca-web, through
  the `cookie` crate 0.18, splits on `;`, percent-decodes, and answers 400 for a pair
  without `=` (`handler/types/cookie.rs`). Here, `each_cookie` and `cookie_of` split on
  `;`, trim spaces and tabs, drop the quotes, and skip a pair without `=`, as RFC 6265
  §5.2 has a user agent do. `cookie_of` takes the first of a repeated name, because a
  user agent sends the cookie with the longest path first (§5.4). Values stay as sent:
  RFC 6265 encodes none. `set_cookie` writes a `Cookie` with its attributes, `Expires`
  as an HTTP date; one that `is_cookie` refuses (a name that isn't a token, a value
  outside RFC 6265's cookie octets, a `;` or control byte in `Path` or `Domain`, or a
  `SameSite` other than `Strict`, `Lax`, or `None`) is dropped, as `field` drops a field.
  odin-http writes any cookie, escaping LF only. `each_cookie` reads the fields with its
  own loops because of a checker limit
  ([findings](../docs/goose-findings.md#a-closure-that-keeps-a-slice-through-two-nested-blocks-doesnt-settle)).
