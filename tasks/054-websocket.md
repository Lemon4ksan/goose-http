# 054: WebSocket

Status: done on the branch `websocket` (asked for 2026-10-19); HttpArena's benchmark
runs of the three echo profiles are still to run.

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
   (`github.com/kaitk/goose-hash`, `v0.0.2`), which tests this example.
2. Frames: a reader for masked client frames, with fragmentation and a size limit, and
   a writer for unmasked server frames. Text, binary, ping, pong, and close, with
   close codes. Frames that arrive together are read in one pass, for the pipelined
   profile.
3. The program's side: messages in, messages out, and close, with a pong sent for
   each ping without the program.
4. Tests: the handshake's accept value against RFC 6455's example, each frame kind,
   fragmented and pipelined messages, a frame over the limit, and Autobahn's test suite
   on the server.

## What was built

- `websocket.goose`, the optional module `http.websocket`: `ws_upgrade`, `ws_read`,
  `ws_send`, `ws_close`, and the state `http::WebSocket`
  ([api](../docs/api.md#websocket),
  [decision](../docs/decisions.md#websocket-is-an-optional-module-over-upgrade)). It
  declares goose-hash `v0.0.2` as `compression.goose` declares goose-compress, so only a
  program that imports it declares goose-hash. `upgrade`'s switch of the stream became
  `switched`, which `ws_upgrade` shares.
- The benchmark server's `/ws` echoes each message, with a 32 MiB limit for Autobahn's
  16 MiB messages. `bench/httparena/goose/meta.json` subscribes to the three echo
  profiles.
- Tests: `test/websocket/ws_handshake.goose` (RFC 6455's accept example, the 101, and
  the 426, 400, and 501 answers) and `test/websocket/ws_frames.goose` (each frame kind,
  fragments across reads, 16 pipelined frames, a frame a byte per read, the limit, the
  protocol errors, and UTF-8); `http_client.py websocket` against the server in
  `scripts/test-http.sh`; and `scripts/test-autobahn.sh`, run by `scripts/test.sh` with
  `AUTOBAHN=1`.

## Results

Autobahn testsuite 25.10.1 (`crossbario/autobahn-testsuite`, digest `519915fb568b`),
fuzzing client, against `build/server`'s `/ws` with 2 workers, on an M1 Pro, macOS 26.3,
Docker Desktop, 2026-10-19: 301 cases, every case but sections 12 and 13. On the epoll
loop and the uring loop (the ring emulated on kqueue) alike, 296 OK, 2 NON-STRICT, and 3
INFORMATIONAL, with no failure:

- NON-STRICT: 6.4.3 and 6.4.4, invalid UTF-8 inside one text frame sent in pieces. The
  check runs once the frame is whole, so the connection fails then rather than at the
  bad byte. Fragments are checked as they come.
- INFORMATIONAL: 7.1.6, 7.13.1, and 7.13.2, which only report what the server does.
- Excluded: 12.* and 13.*, permessage-deflate, which the module doesn't negotiate.

The same 301 cases gave the same results on Linux, Ubuntu 26.04 arm64 in Docker
Desktop's VM on the same Mac, with the server in a container and Autobahn in its network:
the epoll loop twice and native io_uring once. There, no connection was lost; on macOS,
`host.docker.internal` lost one in about one full run in four
([known issues](../docs/known-issues.md#docker-on-macos)), and the script runs the
cases it didn't reach again.

`scripts/test.sh` passed on that Linux container, with seccomp unconfined so io_uring
ran natively, and on macOS with `AUTOBAHN=1`.

The API was confirmed on 2026-10-19: the `ws_` names, `ws_upgrade` taking no state,
and its optional subprotocol parameter.

Remaining: a ping the server sends on its own, such as for keep-alive, which isn't in
the API yet.

Still to measure: the `/ws` state adds an `http::WebSocket`, about 80 bytes, to the
benchmark server's `Transfer`, which each request starts from fresh; plaintext's
instructions per request with it, at the next batch of benchmark runs.

HttpArena's `scripts/validate-ws.py` (at `0720ee57`, the commit `bench/httparena.sh`
pins) against `build/server http` on macOS: 7 passed, 0 failed. The three echo profiles
share that validation.

## Acceptance criteria

- [x] The API in `docs/api.md`, and the decision that WebSocket is in scope in
      `docs/decisions.md` and `README.md`
- [x] Autobahn's server tests pass, except those for extensions
- [x] An echo server passes HttpArena's three echo validations
