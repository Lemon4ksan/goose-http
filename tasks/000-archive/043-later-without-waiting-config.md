# 043: Give `later` an answer when waiting isn't configured

Status: done (found from goose-rest, 2026-10-16, by reading v0.3.3's source; confirmed
and fixed 2026-10-19)

Without `Config.mail_slots` and `Config.max_waiting`, `http::later` on an exchange seemed
to leave it with no event at all. The docs say a `later` past the limit gives `TIMEOUT`
at once, and 0 is a limit, so a handler would expect `TIMEOUT` here too.

What the source did:

- `open_waiting` (`http.goose`) opens no box unless both settings are above 0, so the loop
  has `waiting` false and a timer table of 0 cells.
- After the handler returns with `rearm` set, both loops call `start_wait`. Its `arm`
  finds no cell, so it clears `waiting`, retires the stream, and returns true, and the
  loop pushes the key on `overdue`.
- Both loops drained `overdue` into `timed_out` only inside `if waiting`, which is false.
  The key was never delivered, `overdue` grew by one key for each such exchange, and
  the loop's wait took a timeout of 0 from then on.
- The exchange wasn't waiting and wasn't answered, so the handler got no `TIMEOUT` or
  `WAKE`, and the client waited until the connection's deadline.

## Acceptance criteria

- [x] A test confirms or refutes the reading above on both loops: a handler that calls
      `later` with `Config.mail_slots` and `Config.max_waiting` at 0, at `REQUEST` and on
      an open response, and what the client sees. Record the result here.
- [x] If confirmed, the fix is one of these, chosen and recorded in
      `docs/decisions.md`:
  - give `TIMEOUT` at once, as the docs imply, by draining `overdue` whether or not
    waiting is configured; or
  - refuse `later` without the configuration, so the mistake shows at once rather than as
    a stall.
- [x] `overdue` doesn't grow without bound in either case.
- [x] `docs/api.md` says what `later` does when waiting isn't configured.
- [x] The test covers both loops, as task 038's does.

## Result

Confirmed on macOS at `ff18ecc7`, for the epoll loop over kqueue and the ring loop over
its kqueue emulation: no connection got its `TIMEOUT`, at `REQUEST` or on an open
response, and after the requests the server used about half a core while idle, the
loop spinning on the undrained `overdue`.

A second fault sat behind the first. Without a box, the loops gave no connection a key
of its own, so every exchange's address had key 0; draining `overdue` alone would have
sent each `TIMEOUT` to whatever connection held slot 0, which could be one that never
asked, and left the exchange that did ask waiting. The h2c branch fixed the same fault
for its streams.

## What changed

The fix gives `TIMEOUT` at once ([decisions](../../docs/decisions.md#without-waiting-configured-later-gets-timeout-at-once)).

- Both loops (`epoll.goose`: epoll and kqueue; `uring.goose`: io_uring, IOCP, and the
  emulation over epoll or kqueue) drain `overdue` on every pass, with or without a box;
  only the timer table's `expire` stays behind `waiting`. Each pass empties `overdue`,
  so it holds at most the keys one pass adds.
- Both loops give each connection its slot and generation in its key whether or not
  they have a box, and `answer` (`http.goose`) adds the exchange's number to it either
  way, so `timed_out` finds the exchange that asked.

Tests: `/delay/MS?open=1` (`server/routes.goose`) begins a chunked response before it
waits, and sends MS as its body at `TIMEOUT`. `http_client.py later-off`, against a
server without `MAIL_SLOTS`, opens 8 idle connections and 24 that ask for `/delay`, half
of them with `open`, more than the 4 workers, so a worker holds several. Each asking
connection must get its own answer within 2 s, and each connection, idle or not, must
answer `/plaintext` afterwards with nothing unasked before it.

`scripts/test.sh` passes on macOS for both loops, and on Linux in Docker on macOS (arm64,
kernel 7.0.14-linuxkit, with `seccomp=unconfined`) for io_uring, the emulation over
epoll, and epoll (2026-10-19). IOCP shares
`uring.goose`'s Goose and wasn't run on Windows.
