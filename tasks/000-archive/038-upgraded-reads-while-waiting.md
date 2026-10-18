# 038: Read an upgraded connection while its exchange waits

Status: done (found in goose-rest's task 023, 2026-10-15; run on every loop
2026-10-18)

While an exchange waits with `http::later`, the loop doesn't read its connection. For a
request that's right: the next request waits its turn. An upgraded connection is a
stream both ways, though, and one that asks another thread for something gets none of
the client's bytes until the reply comes. A WebSocket that looks something up for one
message can't take the next meanwhile, nor see a close or a ping. goose-rest's reference
records the limit.

## Acceptance criteria

- [x] On an upgraded connection, `BODY` events keep coming while the exchange waits
      with `http::later`, and `WAKE` or `TIMEOUT` comes when the reply does
- [x] A connection that isn't upgraded still isn't read while it waits
- [x] Both loops, with a test that sends bytes while a reply is pending: passes on
      macOS for the epoll loop over kqueue and the ring loop over its kqueue emulation;
      on Linux in WSL2 for io_uring, the emulation over epoll, and epoll, at
      `2bf3134e`; and on Windows for IOCP, with MSVC and clang-cl, at `cb66ab09`
      (`test-http.sh`'s `later`, 2026-10-18)
- [x] `docs/api.md` says what an upgraded exchange gets while it waits

## What changed

The change was contained: one predicate, `holds_input` (`http.goose`), true for a
waiting exchange that isn't upgraded (`BodyReader.Raw`), takes the place of
`stream.waiting` where the shared code and the ring loop decide whether to hold input.

- `answer` (`http.goose`), which every loop shares, goes on handing an upgraded
  exchange's bytes to the handler as `BODY` while it waits, and `settle` stops only for
  `holds_input`. A call that ends an open response, which after an upgrade writes
  nothing, now stops the wait as one that writes a whole response does; without that,
  an `end` at `BODY` during a wait left the connection closing with its wait set, which
  the sweep skips.
- The epoll loop (epoll and kqueue) already read a waiting connection until the read
  buffer was full; with `answer` taking the bytes, it reads on. Only a comment changed.
- The ring loop (`uring.goose`: io_uring, IOCP, and the emulation over epoll or kqueue)
  held a waiting connection's bytes in `received` and `pump`, and after a file's send;
  those three checks use `holds_input`. IOCP has no Goose of its own, so this covers it.
- Unchanged and still right: a client that closes during the wait closes the
  connection, its handler gets `CLOSED`, and `abandon` makes the address `STALE`; the
  sweep skips a waiting connection, whose own time limit stands; a `later` at `BODY`
  starts the limit again (`start_wait` cancels the old timer).

Tests: `test_upgraded_wait` (`test/test_http.goose`) checks `answer` directly: a
waiting request holds the next one back, and an upgraded exchange gets `BODY` while it
waits, `WAKE` after, and `end` stops its wait. `/upgrade?id=ID&delay=D&ms=M`
(`server/routes.goose`) waits for the backend once upgraded, and `http_client.py later`
checks that bytes sent meanwhile are echoed before the reply, that `TIMEOUT` comes at
the limit, that echoing goes on after either, and that a client that closes while it
waits leaves the backend's reply `STALE`.
