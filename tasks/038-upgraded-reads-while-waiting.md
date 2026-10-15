# 038: Read an upgraded connection while its exchange waits

Status: todo (found in goose-rest's task 023, 2026-10-15)

While an exchange waits with `http::later`, the loop doesn't read its connection. For a
request that's right: the next request waits its turn. An upgraded connection is a
stream both ways, though, and one that asks another thread for something gets none of
the client's bytes until the reply comes. A WebSocket that looks something up for one
message can't take the next meanwhile, nor see a close or a ping. goose-rest's reference
records the limit.

## Acceptance criteria

- [ ] On an upgraded connection, `BODY` events keep coming while the exchange waits
      with `http::later`, and `WAKE` or `TIMEOUT` comes when the reply does
- [ ] A connection that isn't upgraded still isn't read while it waits
- [ ] Both loops, with a test that sends bytes while a reply is pending
- [ ] `docs/api.md` says what an upgraded exchange gets while it waits
