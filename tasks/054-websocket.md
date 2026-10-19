# 054: WebSocket

Status: todo (asked for 2026-10-19)

WebSocket (RFC 6455) in goose-http, over the upgrade that already hands an upgraded
connection's bytes to the program (`http::upgrade`, `docs/api.md`). HttpArena's three
echo profiles score on a board of their own (goose-rest's task 047).

## What HttpArena asks

At HttpArena `2d85137` (2026-10-18), `echo-ws`, `echo-ws-pipeline`, and
`echo-ws-limited` upgrade `GET /ws` on port 8080 and send 5-byte text frames
(`"hello"`) to be echoed: one at a time, 16 back to back, or 10 per connection before it
closes and a new one upgrades. The rules require the framework's own handshake on every
connection, with no 101 response cached across connections.

## Steps

1. The handshake: check `Sec-WebSocket-Key` and `Sec-WebSocket-Version`, and answer
   101 with `Sec-WebSocket-Accept`, base64 of the key's SHA-1, from goose-hash
   (`github.com/kaitk/goose-hash`, `v0.0.1`), which tests this example.
2. Frames: a reader for masked client frames, with fragmentation and a size limit, and
   a writer for unmasked server frames. Text, binary, ping, pong, and close, with
   close codes. Frames that arrive together are read in one pass, for the pipelined
   profile.
3. The program's side: messages in, messages out, and close, with a pong sent for
   each ping without the program.
4. Tests: the handshake's accept value against RFC 6455's example, each frame kind,
   fragmented and pipelined messages, a frame over the limit, and Autobahn's test suite
   on the server.

## Acceptance criteria

- [ ] The API in `docs/api.md`, and the decision that WebSocket is in scope in
      `docs/decisions.md` and `README.md`
- [ ] Autobahn's server tests pass, except those for extensions
- [ ] An echo server passes HttpArena's three echo validations
