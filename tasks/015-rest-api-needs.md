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
   - A way for another thread to wake a worker's loop. None exists: `http::stop` is a
     counter each loop reads after a wait of at most a second (task 013, item 11).
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
      from trusted proxies only. (Done on kqueue and the ring over it, and in Docker on
      io_uring, the ring over epoll, and epoll, 2026-10-12; the IOCP loop's `net_peer`
      compiles but waits for a Windows run. See "The client's address".)
- [ ] The server listens on IPv6, dual-stack, and on a Unix socket on Linux and macOS.
- [x] A field with CR, LF, or an invalid name never reaches the client (2026-10-12; see
      "Checked fields")
- [x] Helpers for items 5 to 11, each with a check in `scripts/http_client.py` or
      `test/test_http.goose` (2026-10-12: items 5-8, 10, and 11 in
      `test/test_api.goose` and `scripts/http_client.py`; item 9 in
      `scripts/http_client.py`. See "Helpers" and "The access log")
- [x] The benchmark routes keep their rate (2026-10-12, on the Mac and in Docker on it,
      `288c868` against `26e073f`; see "The benchmark routes' rate")

## Answers that wait: a proposal (2026-10-12)

Status: proposed, for review before any code. Nothing below is decided.

### What constrains it

- Goose threads share no memory (spec §11.2). They talk through typed queues, one
  queue per element type, which any thread may take from. A pool thread can't address
  a queue to one loop, and a queue can't wake a loop blocked in `epoll_wait`,
  `kevent`, `io_uring_enter`, or `GetQueuedCompletionStatusEx`.
- The loops have no wakeup today; `http::stop` is a counter they poll each second.
- An HTTP/1.1 connection answers in order, so a waiting exchange holds back the
  requests pipelined behind it. Under HTTP/2 (task 014) one connection has many
  exchanges, and any of them may wait while the others go on.

### What the competitors do (verified in code unless marked)

- hyper 1.12.0 keeps the pending exchange as the service's future
  (`proto/h1/dispatch.rs`, `in_flight`), and `poll_ready` reads no next head while
  one is in flight, so pipelined bytes wait in the read buffer. Dropping the
  connection drops the future: there's no handle to invalidate. Wakeups come from
  tokio 1.53.2, through mio 1.2.4's `Waker`: an `eventfd` on Linux
  (`sys/unix/waker/eventfd.rs`), `EVFILT_USER` with `NOTE_TRIGGER` on macOS
  (`sys/unix/selector/kqueue.rs`), and `PostQueuedCompletionStatus` on Windows
  (`sys/windows/waker.rs`). tokio's timers are a hierarchical wheel of 6 levels of 64
  slots (`runtime/time/wheel/`).
- odin-http (`fac113f`) answers through `^Response`, which points at its
  connection. `respond` asserts it runs on a server thread, and the connection is
  freed on close with no generation or count, so a late answer would use freed
  memory. One request at a time per connection: pipelined bytes wait in its scanner.
  Its vendored older nbio keeps timeouts in an array scanned each tick, with kevent
  capped at 10 ms.
- may-minihttp 0.1.11 runs each connection in a coroutine that a blocking call parks;
  may 0.3.51 wakes a selector with an `eventfd` (`io/sys/unix/epoll.rs`). There is no
  handle to answer later with.
- From memory, not checked: libuv keeps timers in a min-heap and wakes with
  `uv_async_send` over an eventfd or a pipe; h2o keeps a timer list per loop.

### The proposal

1. **A mailbox per loop, in the shim.** A loop opens one at its start
   (`net_mailbox_open`), which registers a wakeup with its wait: an `eventfd` in the
   epoll set or polled by the ring on Linux, `EVFILT_USER` on macOS (also under the
   ring's emulation, which waits through `net_epoll_wait`), and
   `PostQueuedCompletionStatus` on the IOCP port. `net_post(box, bytes)` copies a
   message into the box under a lock and wakes the loop; the loop drains the box
   after each wait, appending the messages to a Goose buffer (spec §7.10's builder
   append). A box has an id and a generation, so a post to a box whose loop has
   returned fails (`ESRCH`), and a byte cap, past which `net_post` fails with
   `EAGAIN` for the caller to retry or give up. This is data moving through C, against
   `AGENTS.md`'s "C is for what Goose can't reach": the case for it is that Goose can
   neither address a queue to a thread nor wake a kernel wait, and the box is a list
   of byte runs, with no HTTP in it.
2. **A handle that a closed connection invalidates.** `http::later(out, ms)` makes
   the exchange wait, and returns a flat `http::Later`: the box's id and generation,
   the connection's slot and a generation per slot (the io_uring loop's tag has one
   already; the epoll loop gains one), and the exchange's number (`Exchange.served` in
   HTTP/1.1, the stream id in HTTP/2). Any thread may call `http::wake(h, bytes)`,
   which posts to the box. The loop checks the slot, its generation, and the exchange
   number when the message arrives, and drops it if any differs. The connection that
   took over the slot never sees it.
3. **Two new events.** `WAKE` brings the posted bytes in `ev.data`, with the state as
   `later` left it; the handler answers, begins a stream, or calls `later` again.
   `TIMEOUT` comes when the time given to `later` runs out with no wake. Without
   either answer, the loop answers 500 as it does today for a handler that doesn't.
   The bytes are the program's own encoding (an id, JSON, a row): the response is
   built on the loop thread, where `Date`, keep-alive, and the write buffer are.
4. **Streams that wait.** At `MORE`, `later` pauses an open response, for
   Server-Sent Events and long polling: no `MORE` comes until a `WAKE` or a
   `TIMEOUT`. Today a `MORE` that neither sends nor ends closes the connection.
5. **Timers in a heap per loop.** Each waiting exchange has an entry, keyed by its
   deadline, in a min-heap of the loop's own, and the loop waits no longer than its
   earliest deadline. The per-connection deadline and the sweep stay for the other
   timeouts. A heap rather than the sweep, because the sweep runs about once a second
   and HTTP/2 needs a timer per stream rather than per connection; rather than a
   wheel, because the waits are far fewer than the connections.
6. **HTTP/1.1 order.** While an exchange waits, `answer` parses nothing after it.
   Pipelined bytes stay held, and reading stops once the read buffer is full, as it
   does for a response the client doesn't take. Requests not waiting cost nothing:
   the check is one flag, read where `settle` already reads the exchange.
7. **Stop.** A waiting exchange counts as in progress: it gets `Config.grace_ms`, then
   `CLOSED`. The wakeup could also make stop immediate rather than within a second,
   but that is optional.

Work is the program's: it spawns its own pool of `thread_fn` workers that take jobs
from a typed queue, any worker taking any job, and wake the handle each job carries.
The package spawns no threads.

```goose
struct Job { at: http::Later, user: i64 }

// The handler, at REQUEST:
let at = http::later(out, 5000);
qput(Job { at: at, user: id });
// At WAKE: ev.data is what the worker posted. At TIMEOUT: answer 504.

thread_fn pool() {
    loop {
        let job = qget<Job>();
        var row: u8[>..] = [];
        query(job.user, row);
        http::wake(job.at, row);   // false if the loop has returned or its box is full
    }
}
```

### Open questions for review

- Is a mailbox of bytes in the shim acceptable, as the one exception to keeping data
  in Goose, or should it wait for a Goose facility (a queue a thread can address and
  a loop can wait on)? That facility would be a request to Goose's maintainer.
- Should the posted bytes be the program's to read at `WAKE`, as above, or should the
  worker build the whole response? The first keeps the package's response writers on
  the loop thread; the second saves a step but splits `Date` and keep-alive between
  threads.
- Should the wakeup also make `http::stop` immediate?

### Phases, once agreed

1. The mailbox and wakeup in `shim/kqueue.c` and the ring's emulation, with
   `/later` and `/events` (Server-Sent Events) routes and their checks, on the Mac.
2. `shim/net.c` and `shim/uring.c` on Linux, in Docker and on WSL2.
3. `shim/iocp.c` on Windows.
4. The rate of the benchmark routes, as for the other items.

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
- `Authorization` (`auth.goose`). No competitor in `bench/` reads `Authorization` or
  answers 401: odin-http names the field only to keep it out of trailers
  (`http.odin`), and xitca-web and its dependencies have no base64. Here,
  `authorization` splits the scheme, a token, from its credentials at the spaces after
  it. `basic_auth` takes the `Basic` scheme ignoring case (RFC 9110 §11.1), decodes the
  credentials with the stdlib's `base64::decode`, which takes only the standard
  alphabet with its padding, and splits them at the first `:`, as RFC 7617 §2 requires
  of a user-id. It decodes into a buffer of its own and appends that to the caller's,
  because the checker won't let `base64::decode` shrink the caller's buffer while the
  request is live. `challenge` answers 401 with a `WWW-Authenticate` value, dropped as
  `field` drops one if it's bad.
- Form bodies (`form.goose`, and `each_form` in `message.goose`). odin-http splits a
  urlencoded body on `&`, doesn't take `+` as a space, fails the whole body on one bad
  escape, and lets the last of a repeated key win (`body.odin`, `body_url_encoded`);
  xitca-web's `Form` hands the whole body to `serde_urlencoded`, and its `Multipart`
  streams parts through the `http-multipart` crate, with a blank 400 for a bad boundary
  (`handler/types/multipart.rs`). odin-http has no multipart. Here, `each_form` splits
  pairs as `each_query` does, which now calls it, and `form_value` decodes the first
  pair whose key decodes to the one asked for, with `plus` set, skipping a pair with a
  bad escape. A urlencoded body that doesn't fit the read buffer comes in pieces, which
  the handler joins. `start_multipart` takes the boundary from `Content-Type`, and
  `each_part` reads the body as it comes, at `REQUEST` and each `BODY`, calling the
  handler for each part's head, the pieces of its content, and its end; `disposition`
  reads a head's name and filename. A delimiter split between pieces is found: the
  reader holds back only the end of a piece that could start one. `Multipart` is flat,
  because the loops keep a handler's state in each connection's slot, which can't hold
  a growable array: it holds at most `MAX_PART_HEAD`, 2,048 bytes, between pieces, and a
  part's head longer than that fails the body. That cap is the reader's only limit;
  `Config.max_body` bounds the whole.
- JSON responses (`respond_json`, `media.goose`). odin-http's `respond_json` marshals
  through a 128-byte writer and closes with 500 on a marshal error (`responses.odin`);
  xitca-web's `Json` serializes with `serde_json::to_vec` (`handler/types/json.rs`).
  Both, and every benchmark route in `bench/`, send `application/json` with no
  charset, which RFC 8259 §11 doesn't define. Here, `respond_json` calls its block with
  a buffer for the stdlib's `json::format_*` writers, then answers with that body and
  `application/json`. The stdlib's parser and reader take only a whole text, so a body
  that comes in `BODY` pieces must be joined first
  ([findings](../docs/goose-findings.md#the-stdlibs-json-parser-and-reader-take-only-a-whole-text)).
- Limits (`Config.max_requests` and `body_within`, `http.goose`). None of hyper 1.12.0,
  xitca-http 0.8.2, may-minihttp, or odin-http caps a connection's requests. For a
  route's body, odin-http's `body` takes a maximum from the handler, checks
  `Content-Length` before reading and each chunk's size as it comes, and answers 413
  (`body.odin`); xitca-web's `Limit<N>` checks as the body streams but answers 400
  (`error/body.rs`). Here, `Config.max_requests`, 0 by default for no cap, makes the
  response to a connection's last request carry `Connection: close`, in `answer`, which
  every loop shares. `body_within` is odin-http's check for a handler that reads the
  body in pieces: called at `REQUEST` and each `BODY`, it checks `Content-Length`
  first and then what has come, and past the route's limit answers 413 and closes the
  connection, rather than drop the rest. The cap's check is in
  `scripts/http_client.py` (`requests`), and `body_within`'s in `test/test_api.goose`.


## The client's address (2026-10-12)

A handler asks for the address; nothing is read per request or per connection
otherwise. `Reply.fd` carries the connection's socket from every loop, and
`http::peer(out)` calls the shim's `net_peer`, a `getpeername` that returns an IPv4
address as IPv4-mapped IPv6 and the port. The io_uring loop's multishot accept passes no
address, and on Windows `SO_UPDATE_ACCEPT_CONTEXT`, which the IOCP shim already sets,
makes `getpeername` work on an `AcceptEx` socket, so one call serves every loop.

`http::client(req, out, trusted)` takes the client from `Forwarded`, or without one
from `X-Forwarded-For`, only when the peer is in `trusted`, a list of networks that
`http::network` parses (`"10.0.0.0/8"`, `"::1"`). It walks the hops from the nearest
and returns the first that isn't trusted, or the farthest if all are: nginx's
`real_ip_recursive on`, recalled, not checked in code. A hop that isn't an address, as
`unknown`, an obfuscated name (RFC 7239 §6), or a bad element, ends the walk at the
trusted hop before it, so a client can't forge the hops a trusted proxy appended.
`http::format_address` writes an address as RFC 5952 has it.

What the competitors do (verified in code):

- hyper 1.12.0 and hyper-util 0.1.21 have no peer address and no `Forwarded`: the
  program owns accept, and `bench/hyper/src/main.rs` drops the accept's address.
- may-minihttp 0.1.11 never gives the handler the address, and parses no `Forwarded`.
- odin-http (`fac113f`) keeps the accept's endpoint, binary with its port, on every
  request (`server.odin`, `req.client`), and parses no `Forwarded`.
- actix-web 4.15.0, outside `bench/`, takes the first `for=` of `Forwarded`, then the
  first `X-Forwarded-For` (`src/info.rs`), with no list of trusted proxies, so any
  client can set its own address. Its `peer_addr` is text.

xitca-http's source isn't in this checkout, so it isn't compared.

Checks: `test/test_api.goose` (`test_addresses`, `test_forwarded`), and
`scripts/http_client.py`'s `client`, which compares `/client`'s peer with the client
socket's own address and port. The rate holds: on the Mac, `bench/count.sh`'s load
(`h2load --h1 -n 2000000 -c 256 -m 16 -t 8`, one worker, instructions from
`/usr/bin/time -l`, kernel included, 3 rounds alternating) gave 17,547-17,557
instructions per request against 17,541-17,547 on epoll, and 17,763-17,777 against
17,777-17,787 on the ring, within the 30 a run varies.

## The access log (2026-10-12)

With `Config.log`, each loop calls the handler given state with `DONE` once a response
is whole in the write buffer: `Event.status`, as `start` or a refusal of the loop's gave
it; `Event.sent`, the response's bytes, head included; and `Event.ms`, the loop's clock
from the read that brought the head's first byte. `Reply.fd` gives the peer through
`http::peer` or `http::client`. `Event.req` is the request when its response was whole
at `REQUEST`; after a body in pieces or a streamed response, the read buffer no longer
holds it, so the handler keeps in its state what it wants to log. `answer` sends `DONE`
from the three places a response becomes whole: after `REQUEST`, after the call that
ends it, and after a refusal of the loop's (500 for a handler that didn't answer, 400
or 413 for a body). A response cut short by a close gets `CLOSED` instead, an upgraded
connection gets only `CLOSED`, and a request refused before `REQUEST` (400, 414, 431)
isn't logged.

The time ends at the write buffer, not at the client's last byte: the loops batch
responses into one send and don't track where each ends. It is the loop's clock,
milliseconds and up to a scheduler tick old, as nginx's `$request_time` reads the time
it caches per event loop pass (recalled, not checked in code). Each read that finds the
read buffer empty sets `Exchange.since`; a pipelined request whose head began in an
earlier read than the one before it gets that earlier read's time.

A `DONE` event, not a second function: `serve` takes one handler, and the handler's
state still holds the request's at `DONE`. odin-http (`fac113f`) writes no line per
response: its `core:log` calls are diagnostics, such as "no route matched"
(`routing.odin`) and connection events (`server.odin`), and `middleware_proc`
(`handlers.odin`) lets a program wrap a handler. The other competitors weren't checked
for a hook.

Check: `scripts/http_client.py`'s `log`, against a server started with `ACCESS_LOG`,
whose handler prints each `DONE` (`server/routes.goose`, `logged`). It checks a whole
response, a 404, a streamed response, a body in pieces, and a head whose first byte
came 0.3 s before the rest, for the status, the bytes as the client got them, the
target, and the time.

The rate: on the Mac, with `bench/count.sh`'s load as in "The client's address",
alternating with `52e7fc8`, the build with the log off took 17,561-17,587 instructions
per request against 17,533-17,556 on epoll (15 rounds), and 17,783-17,808 against
17,767-17,771 on the ring (3 rounds): about 25 more on epoll and 12-40 on the ring,
0.1-0.2%, kernel included. Neither the status
store in `start`, the arrival time in the loop, nor `Event`'s three new fields accounts
for it: a build without each measured the same, and one without the `DONE` calls on the
whole-request path took 130 more, so it follows gcc's layout of `answer` rather than
the work added.

## The benchmark routes' rate (2026-10-12)

No regression shows on the Mac or in Docker on it: in every cell, `288c868`'s runs
overlap `26e073f`'s, the commit before this task's changes, and the medians differ by
less than the spread of either. These runs resolve a few percent, not a few
instructions; task 013 counted changes of this size at 5-15 user instructions per
request. Two changes reach the routes' path: `answer` counts each connection's
requests against `Config.max_requests` (item 11), which adds 8 bytes to each slot, and
`field` checks its name and value (item 4), which `/bytes`, `/stream`, `/echo`, and
`/upgrade` call; plaintext and JSON write their fields through `finish`. No benchmark
route calls the helpers of items 5 to 11.

macOS, on the MacBook Pro M1 Pro of `docs/development.md`, Darwin 25.3.0, Goose
`5c83a5a`, each build with `scripts/build.sh`, at a load average of 6-12: another
project's benchmark ran on the machine meanwhile, so these runs are noisy. wrk 4.2.0 on the same machine, `-t 4 -c 64 -d 5 -s scripts/pipeline.lua -- 16`,
against `WORKERS=4`, 5 rounds alternating the builds. In thousands of requests per
second, median and range:

| Loop, route | `26e073f` | `288c868` |
|---|---|---|
| epoll, plaintext | 565.6 (549.0-575.5) | 551.0 (550.0-574.1) |
| epoll, JSON | 566.9 (551.7-577.7) | 556.7 (540.1-573.2) |
| uring, plaintext | 549.9 (546.4-565.7) | 561.7 (544.8-569.7) |
| uring, JSON | 560.4 (546.5-571.4) | 560.4 (554.7-573.4) |

Plaintext and JSON run at the same rate there, which the loopback limits
(`docs/development.md`, "macOS"), so the counts below say more. `bench/count.sh`'s load
on macOS: `WORKERS=1`, h2load 1.70.0 `--h1 -n 2000000 -c 256 -m 16 -t 8` on
`/plaintext`, and the server's instructions retired from `/usr/bin/time -l`, which
counts the kernel's too, divided by the requests; 3 rounds alternating the builds.
Instructions per request: epoll 17,531-17,560 (`26e073f`) and 17,548-17,558
(`288c868`); uring 17,787-17,801 and 17,780-17,790.

Docker Desktop 29.8.2 on the same Mac, kernel 7.0.14-linuxkit, 10 CPUs, the
`ubuntu:26.04` image of `docs/development.md` with wrk 4.1.0, `--security-opt
seccomp=unconfined`, so `uring` is io_uring. The server with `WORKERS=3` on CPUs 0-2,
wrk on CPUs 3-9, `-t 7 -c 256 -d 5 -s scripts/pipeline.lua -- 16`, 5 rounds alternating
the builds. In thousands of requests per second:

| Loop, route | `26e073f` | `288c868` |
|---|---|---|
| epoll, plaintext | 6,074 (5,744-6,726) | 6,383 (5,927-6,804) |
| epoll, JSON | 6,296 (5,739-6,378) | 6,223 (5,819-6,443) |
| uring, plaintext | 6,250 (5,619-6,451) | 5,775 (5,211-6,477) |
| uring, JSON | 5,744 (5,612-6,385) | 6,043 (5,523-6,350) |

Docker Desktop's VM exposes no hardware counters (`perf stat` finds no supported
events), so `bench/count.sh` can't run there. On WSL2, `bench/count.sh` against
`26e073f` would put a number on the few instructions these runs can't see.
