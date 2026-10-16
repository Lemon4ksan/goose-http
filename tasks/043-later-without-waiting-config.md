# 043: Give `later` an answer when waiting isn't configured

Status: todo (found from goose-rest, 2026-10-16, by reading v0.3.3's source; no test has
shown it yet)

Without `Config.mail_slots` and `Config.max_waiting`, `http::later` on an exchange seems to
leave it with no event at all. The docs say a `later` past the limit gives `TIMEOUT` at
once, and 0 is a limit, so a handler would expect `TIMEOUT` here too.

What the source does:

- `open_waiting` (`http.goose`) opens no box unless both settings are above 0, so the loop
  has `waiting` false and a timer table of 0 cells.
- After the handler returns with `rearm` set, both loops (`epoll.goose` line 231 and
  `uring.goose` line 227) call `start_wait`. Its `arm` finds no cell, so it clears
  `waiting`, retires the stream, and returns true, and the loop pushes the key on
  `overdue`.
- Both loops drain `overdue` into `timed_out` only inside `if waiting`, which is false.
  The key is never delivered, and `overdue` grows by one key for each such exchange.
  Since epoll's wait takes a timeout of 0 while `overdue` isn't empty (line 393), and
  uring's likewise (line 388), the loop may also spin from then on. The source is the
  same at v0.3.4.
- The exchange isn't waiting and isn't answered, so the handler gets no `TIMEOUT` or
  `WAKE`. For an open response (`http::later` after `begin`, or at `MORE`), the stream
  stalls until the connection's deadline.

## Acceptance criteria

- [ ] A test confirms or refutes the reading above on both loops: a handler that calls
      `later` with `Config.mail_slots` and `Config.max_waiting` at 0, at `REQUEST` and on
      an open response, and what the client sees. Record the result here.
- [ ] If confirmed, the fix is one of these, chosen and recorded in
      `docs/decisions.md`:
  - give `TIMEOUT` at once, as the docs imply, by draining `overdue` whether or not
    waiting is configured; or
  - refuse `later` without the configuration, so the mistake shows at once rather than as
    a stall.
- [ ] `overdue` doesn't grow without bound in either case.
- [ ] `docs/api.md` says what `later` does when waiting isn't configured.
- [ ] The test covers both loops, as task 038's does.
