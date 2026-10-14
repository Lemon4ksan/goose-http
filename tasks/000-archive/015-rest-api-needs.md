# 015: What a REST and JSON API needs from the package

Status: done (asked for 2026-10-12, done 2026-10-12)

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

- [x] A handler hands a request to another thread and answers it from there, without
      blocking its worker, on every loop. The handle of a closed connection is refused,
      and an exchange can wait for a timer. (Done on kqueue and the ring over it, and in
      Docker on io_uring, the ring over epoll, and epoll, 2026-10-12; on IOCP in Git
      Bash on Windows, 2026-10-12. See "Answers that wait: a proposal".)
- [x] A handler reads the client's address on every loop, and a proxied request's,
      from trusted proxies only. (Done on kqueue and the ring over it, and in Docker on
      io_uring, the ring over epoll, and epoll, 2026-10-12; on IOCP in Git Bash on
      Windows, 2026-10-12. See "The client's address".)
- [x] The server listens on IPv6, dual-stack, and on a Unix socket on Linux and macOS.
      (2026-10-12, on kqueue and the ring over it, and in Docker on io_uring, the ring
      over epoll, and epoll; on IOCP in Git Bash on Windows, and on all three Linux
      loops in WSL2, at `30d4b34`. See "Where the server listens".)
- [x] A field with CR, LF, or an invalid name never reaches the client (2026-10-12; see
      "Checked fields")
- [x] Helpers for items 5 to 11, each with a check in `scripts/http_client.py` or
      `test/test_http.goose` (2026-10-12: items 5-8, 10, and 11 in
      `test/test_api.goose` and `scripts/http_client.py`; item 9 in
      `scripts/http_client.py`. See "Helpers" and "The access log")
- [x] The benchmark routes keep their rate (2026-10-12, on the Mac and in Docker on it,
      `288c868` against `26e073f`; see "The benchmark routes' rate"; and after answers
      that wait, `af23e84` against `1265886`, 2026-10-12, in the same section)

## Answers that wait: a proposal (2026-10-12)

Status: agreed as a proof of concept (2026-10-12); see "Decided". Built, in the phases
below, and its rate measured in "The benchmark routes' rate", "After answers that wait"
(2026-10-12):

- Phase 1: the timer table (`timers.goose`) and handles (`handle.goose`), with
  `test/test_timers.goose`, which declares the package by `timers.goose` alone, so it
  compiles only while the table reaches nothing of the HTTP side (2026-10-12).
- Phase 2: the mailbox, `shim/mail.c` and `mail.goose`, with the macOS waker in
  `shim/kqueue.c` and the ring emulation's `ur_waker`, and `test/test_mail.goose`,
  declared by `mail.goose` alone with a sidecar of its own (`test/test_mail.build`).
  It checks `FULL`, `STALE` after a close and after a reopen, 8 senders of 20,000
  messages each with every sender's messages in order, and two ping-pongs, of 20,000
  rounds and of 400 with a 1 ms pause before each reply, so that every wait sleeps in
  the kernel; no wait reaches its 2 s limit. `test-unit.sh` builds a test with a
  `thread_fn` with the C compiler, as TinyCC runs no threads (2026-10-12). The mailbox's
  address type is `MailAddress`, since `Address` is an IP address (`forwarded.goose`).
- Phase 3, on macOS, both loops: `http::later`, `WAKE`, `TIMEOUT`, paused streams,
  `Config.mail_slots`, `mail_size`, and `max_waiting` (0, 256, and 0 by default), and
  `/later` and `/events` in the benchmark server over `server/backend.goose`, a thread
  with a box and timer table of its own (2026-10-12). How it came out against the
  sketch:
  - A `Later`'s key is the connection's slot (20 bits, so a box needs `max_conns` of
    at most 2^20), 24 bits of the slot's generation, and 20 of `Exchange.served`; the
    loop sets the exchange's address at `REQUEST`, in `Stream.later`, and it stays the
    same for each `later` in the exchange, as `/events` needs.
  - A call that writes a whole response doesn't wait, so the sketch's 503 for a full
    worker box works as written.
  - With no timer free, or no box, the exchange gets `TIMEOUT` in the loop's next pass.
  - While an exchange waits, the loop goes on reading, holding what comes, until it holds
    the read buffer's worth; so a client that closes while it waits is seen, and its
    reply dropped.
  - The wakeup makes `http::stop` immediate (architecture, "Graceful shutdown"): the
    stop check now wants an idle connection closed within 0.5 s, not 2.5.
  - kqueue replaces a knote's `udata` at every change, a trigger's too, so
    `net_waker_wake` passes the tag again.
  - Checks: `scripts/http_client.py`'s `later`, against a server with `MAIL_SLOTS=64`:
    `/later`'s reply after its delay, 504 at its limit with the late reply dropped,
    requests pipelined behind a waiting one answered after it and in order, a reply to a
    connection that closed while waiting not reaching any of 8 connections that wait
    across it, `/events`' events, and their limit. With the key compared by slot only,
    the stale-reply check fails. `later-off`: 503 without `MAIL_SLOTS`.
  - `README.md` credits Tina for exactly the three ideas taken.
- Phase 4 (2026-10-12): on Linux, the waker is an `eventfd` (`shim/net.c`), in the epoll
  set edge-triggered, or polled by a multishot poll on io_uring (`shim/uring.c`), which
  empties it at each completion and queues the poll again when it ends. The loop closes
  its waker after `ring_destroy`, which ends the poll first. `scripts/test.sh` passed in
  Docker on the Mac, image `goose-http-dev3`, Goose `5c83a5a`, with `seccomp=unconfined`:
  `test_mail`, and `later` and the 0.5 s stop on io_uring, the ring over epoll, and
  epoll. On Windows, `shim/iocp.c`'s waker is a request of its own kind that each wake
  posts to the port with `PostQueuedCompletionStatus`, or an auto-reset event for a
  thread's `mail_wait`; a ring's waker is never freed, since a packet may still be
  queued, as the ring itself isn't. It compiles under MinGW-w64 (`docs/development.md`,
  "Checking the Windows shims compile"), with `mail.c`'s MSVC atomics type-checked
  there with stand-ins for `winnt.h`'s `ReadAcquire` family. On Windows 11 with MSVC
  19.51 and Goose `5c83a5a`, `test-unit.sh` (`test_mail`, `test_timers`),
  `test-http.sh` (`client`, `later`, `later-off`, and the Ctrl+Break stop), and
  `test-echo.sh` passed in Git Bash (2026-10-12).

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
- Tina (`a2e8d4d`, Apache 2.0), a thread-per-core framework in Odin, and its author's
  post on async/await (https://pmbanugo.me/blog/why-async-await-complect-concurrency).
  Every mailbox, pool, and channel is sized at boot, and a send returns `ok`,
  `mailbox_full`, `pool_exhausted`, or `stale_handle` at once
  (`docs/concepts/backpressure_and_drops.md`). Cross-core channels are rings with one
  writer and one reader, one per pair of shards, with no lock or compare-and-swap on the
  send path (`docs/concepts/thread_per_core.md`). Work goes to a shard chosen by key
  (`key_to_shard`), never to a shared queue. A call waits for its reply with a timeout
  it can't leave out (`ctx_call`), and timers are a fixed-capacity array with a bitmap
  of armed slots (`src/timer.odin`). Its HTTP extension parks a connection with
  `expect_reply(target, payload, timeout)` or `expect_notification(timeout, ...)`, and
  wakes it with a `Route_Event` (`src/extensions/http/server/route.odin`). Its wakeups
  are an `eventfd`, `EVFILT_USER`, and `PostQueuedCompletionStatus`
  (`src/io_backend_*.odin`).

- From memory, not checked: libuv keeps timers in a min-heap and wakes with
  `uv_async_send` over an eventfd or a pipe; h2o keeps a timer list per loop.

### The proposal (revised 2026-10-12, after Tina)

Three pieces know nothing about HTTP and use no HTTP type, so that they can move to a
package of their own later unchanged: a mailbox, a timer table, and generation-checked
handles. The HTTP loops are their first user. Tina's model as a whole (isolates for
everything, supervision) isn't adopted: a second user of these pieces, such as a
database client driven from the loop, would be the time to reconsider it
(2026-10-12). A request that doesn't wait costs nothing more: no allocation, no lock,
and no clock read beyond the loops' own.

1. **A mailbox (`mail.goose`, over the shims).** A thread opens a box with a fixed
   number of slots of a fixed size, allocated at open and never after. Any thread
   sends to it by address: `mail_send(to, tag, bytes)` copies the bytes into a free
   slot and returns `SENT`, `FULL` (no slot free, or no room in a slot), or `STALE`
   (the box is closed, or opened again since the address was taken), at once, and
   never grows or blocks. Adding to a box is lock-free, a ring with a sequence number
   per slot, since any thread may send and the senders aren't known at open. The owner
   takes what has come with `mail_take(box) { from, tag, bytes => }`. An address is
   the box's id and generation and a 64-bit key the mailbox doesn't read: the owner
   gives it its meaning. A box opened by a loop wakes the loop's wait: an `eventfd` in
   the epoll set or polled by the ring on Linux, `EVFILT_USER` on macOS (also under the
   ring's emulation), and `PostQueuedCompletionStatus` on the IOCP port. A thread with
   no loop waits on its box with `mail_wait(box, ms)`. The ring and the wakeup are C,
   since Goose has neither atomics nor a wait it can wake; what goes in a message, and
   everything above, is Goose.
2. **A timer table (`timers.goose`, Goose only).** A fixed-capacity min-heap of
   deadlines, each with a 64-bit key, allocated at open: `arm(key, at) -> Timer`,
   `cancel(t)`, `next()` for the loop's wait, and `expire(now) { key => }`. A timer is
   a slot and a generation, so cancelling one that has fired is a no-op. The loops
   size it to `Config.max_waiting` (below).
3. **Generation-checked handles.** A slot index and a generation, which a slot's reuse
   advances: the timers above use them, and so does the HTTP layer for its exchanges.
   A `Later` (below) is a mailbox address whose key holds the connection's slot, the
   slot's generation, and the exchange's number (`Exchange.served` in HTTP/1.1, the
   stream id in HTTP/2).

The HTTP layer, over them:

4. **`http::later(out, ms)`** makes the exchange wait, with a time limit it must give,
   and returns its `Later`, the address a reply goes to. At `MORE` it pauses an open
   response instead, for Server-Sent Events and long polling.
5. **Two events.** `WAKE` brings a message sent to the `Later`, in `ev.data`, with its
   tag; the handler answers, sends more, or calls `later` again. `TIMEOUT` comes when
   the limit passes first. A handler that answers neither gets 500 from the loop, as
   today. A message whose key names a closed or reused connection, or an exchange that
   has ended, is dropped.
6. **Work goes to an address, not a shared queue.** A worker is a thread with a box
   of its own; the program picks one, by key or in turn, and sends it the job with the
   `Later` to reply to. A full box is the handler's to deal with, with 503 or a retry
   at the next event. Goose's typed queues aren't used for this: any thread takes from
   them, they have no bound, and they can't wake a loop.
7. **HTTP/1.1 order, and stop.** While an exchange waits, the requests pipelined
   behind it stay in the read buffer, and reading stops once it's full. At stop, a
   waiting exchange gets `Config.grace_ms`, then `CLOSED`.

```goose
struct Job { reply: http::Later, user: i64 }

// The handler, at REQUEST: a full worker box answers 503.
let reply = http::later(out, 5000);
guard http::mail_send(workers[user % workers.len], JOB, Job { reply: reply, user: user }) == http::SENT
else { http::respond(out, 503, "text/plain", ""); return; }
// At WAKE: ev.data is the worker's reply. At TIMEOUT: answer 504.

thread_fn worker(box: http::Box) {
    loop {
        http::mail_wait(box, 1000);
        http::mail_take(box) { from, tag, bytes =>
            ... run the query; reply to the job's Later with mail_send ...
        };
    }
}
```

The names and the message's encoding are a sketch. The three pieces sit in the `http`
namespace until they move, in files that import nothing of the package's HTTP side.
`README.md` credits Tina for the bounded mailboxes with a result at the send, for
sending work to an address rather than a shared queue, and for the required time limit
on a wait.

### Decided (2026-10-12, for the proof of concept; refine later)

- The mailbox's ring and wakeup are C, in a shim file shared by every platform
  (`shim/mail.c`, with atomics behind a small macro layer: C11 `stdatomic.h` for gcc,
  clang, and TinyCC, `Interlocked*` for MSVC), plus each platform's wakeup in its own
  shim. Messages and everything above them are Goose.
- One lock-free ring per box that any thread adds to, not one per sender.
- The wakeup also makes `http::stop` immediate.

### The mailbox's mechanics

- **Send, lock-free.** A bounded queue with a sequence number per slot (Vyukov's): a
  sender claims a slot with one compare-and-swap on the enqueue position, retried only
  when another sender took it first, copies the message in, and publishes it with a
  release store of the slot's sequence. The owner takes with no read-modify-write per
  message.
- **Wakeup per batch.** A counter of pending messages: a sender wakes the owner only
  when it moves the counter from 0 to 1, so a burst costs one `eventfd` write,
  `kevent`, or `PostQueuedCompletionStatus`. The owner subtracts what it took, and takes
  again if more came meanwhile, so no wakeup is lost or doubled.
- **Waiting.** A loop never spins: it's awake anyway, and checking its box is one atomic
  load per pass. A worker thread on `mail_wait` spins briefly on the counter (a few
  microseconds, with the CPU's pause instruction), then sleeps in the kernel: `poll` on
  its `eventfd`, `kevent`, or `WaitForSingleObject`.
- **OS locks only to open and close.** A table of boxes, guarded by a `pthread_mutex` or
  an `SRWLOCK`, changes only when a box opens or closes. A send raises a count of sends
  in flight on its box while it copies, and a close advances the box's generation, then
  spin-yields until that count is 0 before freeing the slots, so no sender writes into
  freed memory.
- **Taking into Goose memory.** A shim can't append to a `u8[>..]&` (it can't reach the
  runtime: `docs/c-interop.md`), so `mail_take` writes whole messages into a `u8[:]`
  the owner gives, and returns the bytes written, as `net_strerror` does.
- **Memory.** A box is its slots times (slot size + a 24-byte header, rounded up to 8
  bytes), allocated at open, and nothing grows after: 256 slots of 512 bytes is about
  137 KB, 550 KB for 4 workers, against the epoll loop's 2.4 MB peak RSS with 4 workers today. Each box adds
  one `eventfd` on Linux, one `EVFILT_USER` registration on macOS, and nothing on
  Windows, where the completion port is there already. So the loops open no box unless
  `Config.mail_slots` is above 0, which is 0 by default, and the program sets the slot
  size: a program that never waits pays nothing. A reply longer than a slot is the
  program's to split, as Tina's cross-shard messages are.
- **The timer table's size** comes from `Config.max_waiting`, the exchanges that may
  wait at once, also 0 by default, not from `max_conns`: 16,384 cells of about 28 bytes
  would be 450 KB per worker.

### The timer table's shape

A struct may hold only one resizable field, which is its last, so the table is one
array of cells, `{ at, key, gen, pos, heap, next }`, pushed to its capacity at open:
`heap` is a column of its own, `cells[i].heap` being the cell at the heap's position `i`,
`pos` is a cell's place in the heap (-1 while free), and `next` links the free cells. A
`Timer` is a cell and its generation, which freeing a cell advances. `arm` returns no
timer (cell -1) when the table is full, and `expire(now) { key => }` takes each due timer
out of the heap before calling the block, so the block may arm more.

### Phases

1. The timer table and handles, with unit tests, and the mailbox in `shim/kqueue.c`
   and the ring's emulation, on the Mac.
2. `http::later`, `WAKE`, `TIMEOUT`, and paused streams, with `/later` and `/events`
   routes over a worker box, and their checks.
3. `shim/net.c` and `shim/uring.c` on Linux, in Docker and on WSL2; `shim/iocp.c` on
   Windows.
4. The benchmark routes' rate, as for the other items.

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
  ([historical finding](https://github.com/kaitk/goose-http/blob/9a6afc695ff5d6b6791a40771aa0ded7d5c00fe6/docs/goose-findings.md#a-closure-that-keeps-a-slice-through-two-nested-blocks-doesnt-settle)).
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
  ([historical finding](https://github.com/kaitk/goose-http/blob/97e61d2/docs/goose-findings.md#the-stdlibs-json-parser-and-reader-take-only-a-whole-text)).
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

### After answers that wait (2026-10-12)

No regression shows, with waiting off, the default: in every cell, `af23e84`'s runs
overlap `1265886`'s, the commit before phase 1 of "Answers that wait", on the Mac and
in Docker on it. What reaches the routes' path when nothing waits: a check of
`Stream.waiting` after each `REQUEST` call, and of `Stream.later`'s box before it, in
`answer`, and 34 more bytes in each connection's slot: 26 in `Stream` and 8 in
`Exchange`. The server binary grew from
242 KB to 415 KB, with the routes and the backend thread of `/later` and `/events`.

macOS, on the MacBook Pro M1 Pro of `docs/development.md`, macOS 26.3.1 (Darwin 25.3.0),
Goose `5c83a5a`, each build with `scripts/build.sh`, at a load average of 4.7-6.3 from
other work on the machine. wrk 4.2.0 on the same machine, `-t 4 -c 64 -d 5 -s
scripts/pipeline.lua -- 16`, against `WORKERS=4`, 5 rounds alternating the builds. In
thousands of requests per second, median and range:

| Loop, route | `1265886` | `af23e84` |
|---|---|---|
| epoll, plaintext | 571.2 (566.1-575.0) | 571.9 (569.4-576.3) |
| epoll, JSON | 573.2 (561.6-575.1) | 571.8 (567.0-578.7) |
| uring, plaintext | 572.1 (569.0-576.9) | 569.4 (566.0-577.9) |
| uring, JSON | 571.8 (564.5-575.8) | 570.2 (561.5-571.6) |

Instructions per request with `bench/count.sh`'s load on macOS, as above: `WORKERS=1`,
h2load 1.70.0 `--h1 -n 2000000 -c 256 -m 16 -t 8` on `/plaintext`, the server's
instructions retired from `/usr/bin/time -l`, kernel included, 3 rounds alternating the
builds. The third column is `af23e84` with `MAIL_SLOTS=64`, so with a box and a timer
table in the loop and nothing waiting:

| Loop | `1265886` | `af23e84` | `af23e84`, `MAIL_SLOTS=64` |
|---|---|---|---|
| epoll | 17,547-17,600 | 17,568-17,580 | 17,587-17,602 |
| uring | 17,807-17,823 | 17,825-17,828 | 17,819-17,830 |

The uring build's 5-20 more, about 0.1%, is within the 30 a run varies.

Docker Desktop 29.8.2 on the same Mac, kernel 7.0.14-linuxkit, 10 CPUs, image
`goose-http-dev3` (Goose `5c83a5a`, wrk 4.1.0), `--security-opt seccomp=unconfined`, so
`uring` is io_uring. The server with `WORKERS=3` on CPUs 0-2, wrk on CPUs 3-9, `-t 7 -c
256 -d 5 -s scripts/pipeline.lua -- 16`, 5 rounds alternating the builds. In thousands of
requests per second:

| Loop, route | `1265886` | `af23e84` |
|---|---|---|
| epoll, plaintext | 6,494 (6,452-6,542) | 6,447 (6,368-6,495) |
| epoll, JSON | 6,364 (6,315-6,446) | 6,449 (6,330-6,456) |
| uring, plaintext | 6,229 (6,180-6,311) | 6,181 (6,167-6,246) |
| uring, JSON | 6,130 (6,118-6,227) | 6,061 (6,047-6,235) |

The medians move by 0.7-1.3% either way, inside the ranges; these runs resolve a few
percent.

## Where the server listens (2026-10-12)

`Config.address` takes an IPv4 address, an IPv6 one, bare or in brackets, `::` for
every address, or `unix:PATH`; empty stays every IPv4 address (127.0.0.1 on Windows).
`listen_on` (`http.goose`) parses it with `forwarded.goose`'s `address` and gives
`net_listen` the 16 bytes of `Address.ip`, or the path with the `UNIX` flag. An
IPv4-mapped address listens on IPv4, and any other on IPv6, with `IPV6_V6ONLY` off, so
`::` is dual-stack, unless `Config.ipv6_only` sets `V6ONLY`: nginx's `listen [::]:80
ipv6only=off`, recalled, not checked in code.

- Unix sockets: Linux has no `SO_REUSEPORT` for them, so the workers share one per path,
  as on macOS, where the shared-listener table now takes any socket address. The
  listener removes a socket file left at the path before it binds, and leaves any other
  file, failing with `EADDRINUSE`; the last worker's `net_close` removes its own. A Unix
  socket's peer has no address, so `http::peer` finds none and the access log writes
  `-`.
- Windows: `net_win.c` listens on IPv6, and `iocp.c`'s `AcceptEx` makes its socket in
  the listener's family, from `getsockname`, with room for IPv6 addresses. A Unix socket
  is `EAFNOSUPPORT` there; the criterion asks for Linux and macOS.
- Checks: `scripts/http_client.py`'s `listen`, against servers started with
  `ADDRESS=::`, with `IPV6_ONLY` too, and with `ADDRESS=unix:PATH`: pipelined answers
  over IPv6, IPv4, and the Unix socket, `/client`'s peer for each, an IPv4 client refused
  with `IPV6_ONLY`, and the socket's file gone after the stop.
