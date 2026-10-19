# 014.02: HTTP/1.1 over TLS

Status: in-progress (started 2026-10-19). HTTP/1.1 over TLS 1.3 serves from the epoll
loop on the branch `tls`; see "Handover" at the end for what remains.

Task 014's phase 2: HTTPS through [goose-tls](https://github.com/kaitk/goose-tls)
(OpenSSL 3 over memory BIOs) from the module `http.tls`, for HttpArena's json-tls and
8gbit profiles on port 8081: TLS 1.3 with the mounted RSA-2048 certificate, ALPN
`http/1.1` (goose-rest's task 047). Phase 3, kTLS, comes after.

## Acceptance criteria

- [x] The TLS split recorded in `docs/decisions.md`, with what it rejects (2026-10-19)
- [x] A program importing `http` without `http.tls` builds without declaring goose-tls,
      tested (`test/http/no_tls.goose`, 2026-10-19)
- [x] HTTP/1.1 over TLS in the epoll and kqueue loop, as a listener's mode: the
      handshake, keep-alive, close_notify, the handshake's timeout, and the limits
      (2026-10-19)
- [x] The benchmark server serves TLS on its port + 1 given a certificate and key, with
      `/json` and `POST /echo` (2026-10-19)
- [x] Tests with curl, `openssl s_client`, Python's TLS client, and h2load in
      `scripts/test-http.sh`, run by `scripts/test.sh` on macOS and on Linux (2026-10-19)
- [ ] The API's names agreed (question 1 below)
- [ ] HttpArena's TLS validation passed, and json-tls and 8gbit measured on Linux
- [ ] TLS in the io_uring loop, which fails with `ENOSYS` on a TLS listener for now

## Handover

Written 2026-10-19 at the end of the first run.

### Built

On the branch `tls`, from `main` at `c5d3cd67`:

- `tls.goose`, the module `http.tls`: `TlsServer` (a worker's reference to the
  context, a 16 KB read buffer, and a slot per connection), `tls_server(ctx)`,
  `release(server)`, the two `serve_epoll`s that take a `TlsServer`, and the loop's
  calls: `tls_open`, `tls_recv`, `tls_seal`, `tls_notify`, `tls_ready`, `tls_close`.
- `epoll.goose`: the loop is now `epoll_loop<S, H>(cfg, fresh, tls)`, whose untyped
  `tls` is a `NoTls` (stubs, never called) from the `serve_epoll`s without TLS, or a
  `TlsServer`. `EpollConn.tls` (an `i32`, in the padding before `deadline`), `tls_at`
  per listener, `sealed` (the write buffer's prefix already encrypted), and TLS in
  accept, `close_conn`, `drive`, `advance`, `wait`, and `sweep`.
  [Architecture](../../docs/architecture.md#tls) describes the paths.
- `http.goose`: `Listener.tls` and `Config.tls`. `uring.goose`: `ENOSYS` for
  `Config.tls` (a TLS `Listener` already fails as any extra listener does).
- `server/https.goose` and `server/server_epoll.goose`: the epoll build serves TLS on
  `TLS_PORT` (the port + 1) when `TLS_CERT` and `TLS_KEY` are set. `server/app.goose`'s
  `run` takes the root file's TLS setup and epoll runner as function values, so
  `server/server.goose` (uring, and Windows' IOCP) doesn't declare goose-tls.
- `bench/httparena/goose/Dockerfile`: libssl in both stages, port 8081, and
  `TLS_CERT`/`TLS_KEY` from `/certs` when HttpArena mounts it. Not built yet;
  `meta.json`'s tests are unchanged until the validation passes.
- `examples/tls`: HTTP on 8080 and HTTPS on 8443, with a certificate from the command
  line; `scripts/test-examples.sh` runs it (not on Windows, nor in
  `scripts/test-arm.sh`'s cross builds, which leave it out).
- Tests: `test/http/no_tls.goose`, `test/tls/undeclared.goose` (`// error:` fixture),
  `test/tls/tls_config.goose`; `scripts/http_client.py`'s `tls` and `tls-slow` modes,
  and an idle TLS connection in the graceful stop, which must get close_notify;
  `test/run_tests.py` leaves out `test/tls/` on Windows.
- Docs: `docs/decisions.md` (two entries), `docs/architecture.md` ("TLS"),
  `docs/api.md` ("HTTPS"), `docs/development.md` (OpenSSL and CMake), `README.md`'s
  status.

### What passes

Goose `dcc2747`, goose-tls `v0.0.1`.

- macOS (M1 Pro, macOS 26.3.1, Homebrew OpenSSL 3 through goose-tls's CMake):
  `scripts/test-http.sh` on the epoll build, with the TLS block: `s_client` TLS 1.3
  and ALPN http/1.1; curl `/plaintext`, `/json`, a reused connection, a 3,000,000-byte
  body echoed through `/echo`, the same as a file through `/files/`, 1,000,000 bytes of
  `/bytes`; `http_client.py tls` (tfb, pipeline, large, and keepalive over TLS, each
  close with close_notify; a TLS 1.2-only client refused with `protocol_version`;
  plaintext to the port closed unanswered); h2load `--h1 -c 64 -n 50000`, every
  request 2xx, ALPN http/1.1; `tls-slow` (a ClientHello cut short, and a whole one
  with no Finished, each closed at `REQUEST_MS`, 4 s, while another client is served);
  and the stop with an idle TLS connection, which gets close_notify.
- `scripts/test.sh` with `PORT=29780` on 2026-10-19, on the working tree that became
  this branch's commit:
  - macOS, as above: every step passes, 46 tests at -O0 and -O2 (`test/tls/`'s two
    included), the TLS block and `tls-slow` on the epoll build ("tls: not served by
    this loop" on uring), h2spec 146 of 146, and `examples/tls` in
    `test-examples.sh`.
  - Linux, arm64 in Docker Desktop on the same Mac (`ubuntu:26.04`, kernel
    7.0.14-linuxkit, `--security-opt seccomp=unconfined`, OpenSSL 3.5.5 from
    `libssl-dev`): every step passes, the same TLS checks on the epoll build; h2spec
    skipped, as on any arm64 Linux.

No measurement yet: the macOS runs are smoke tests, and the comparison that counts is
HttpArena's json-tls and 8gbit on Linux.

### What remains, in order

1. Question 1 below: the names.
2. HttpArena: build `bench/httparena/goose/Dockerfile` (`libssl3t64` is Ubuntu 26.04's
   runtime package, 3.5.5; the image itself not yet built), run `bench/httparena.sh validate` for
   json-tls and 8gbit, then add them to `meta.json`'s tests and measure on Linux
   against the Rust entries (task 014's phase 2 criterion).
3. kTLS (phase 3): not started. Docker Desktop's kernel (`7.0.14-linuxkit`) has no
   `tls` module (`/proc/sys/net/ipv4/tcp_available_ulp` is missing, checked
   2026-10-19), so it needs a Linux machine or VM whose kernel has `CONFIG_TLS`.
   goose-tls's `tasks/002-ktls.md`, "What goose-http's loops will need", lists the
   loop's side: `tls::to_kernel` after the handshake (with everything drained and
   sent first, and `kernel_wants` bytes read exactly while it returns `WANT_INPUT`),
   then plain `recv`/`send`/`sendfile` on the socket, `recvmsg` with a control
   buffer on `EIO`, and `sendmsg` with `TLS_SET_RECORD_TYPE` for close_notify and
   KeyUpdate. `recvmsg`/`sendmsg` with control messages are goose-http shim work.
4. io_uring: TLS listeners in `uring.goose`, then the benchmark server's TLS with
   `LOOP=uring` (`server/app.goose` adds it only for epoll).
5. Windows: goose-tls hasn't been built there; `test/tls/` and `examples/tls` are
   skipped, and `server/server_epoll.goose`'s typecheck in `scripts/test.sh` now
   fetches goose-tls there too (untried).
6. Smaller points:
   - A TLS connection's file responses go through `pread` in pieces at any size;
     with kTLS they could go back to `sendfile`.
   - `tls_close` sends close_notify or an alert with one nonblocking `send`, and
     drops it if the socket doesn't take it.
   - OpenSSL's `SSL_new` failing at accept closes the socket without a report: the
     shim's error codes have no `ENOMEM`.

### Traps

- A struct may have one resizable field, and it must be last: `TlsServer`'s read
  buffer is a fixed `u8[16384]`, and its free slots a list threaded through the slots.
- A program's own subdirectory named like a package (`lib/` beside a root that
  declares `lib`) makes `import lib.tls` an error ("both a file of this package and the
  declared package's module"); keep test libraries outside the program's directory.
- `tls::shutdown` before `tls::write` fails the write: seal the response first, then
  queue close_notify (`tls_seal`'s `last`).
- `tls::read` returns one record at most; `tls_recv` reads until `WANT_INPUT` before
  calling the socket empty, or edge-triggered epoll never reports the records
  OpenSSL already holds.
- Python's `ssl` sockets can't send and receive on one connection from two threads,
  so `http_client.py`'s `stream` doesn't run over TLS; curl echoes the large body.
- `openssl s_client -brief` doesn't print the ALPN protocol; `test-http.sh` reads the
  full output.
- The scratchpad of a session may be shared by several agents: keep logs and exported
  trees in a directory of one's own.

### Commands

```sh
python3 test/run_tests.py no_tls tls
LOOP=epoll scripts/build.sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 2 -subj /CN=localhost
TLS_CERT=c.pem TLS_KEY=k.pem build/server http 8080      # TLS on 8081
curl -k https://127.0.0.1:8081/json
openssl s_client -connect 127.0.0.1:8081 -alpn http/1.1 </dev/null
python3 scripts/http_client.py 8081 tls
PORT=29780 scripts/test.sh
```

### Questions for the user

1. The names, proposed and not yet agreed: `Config.tls` and `Listener.tls`;
   `http::TlsServer`, `http::tls_server(ctx)`, and `http::release(server)`; and
   `http::serve_epoll(cfg, server)` and `http::serve_epoll(cfg, fresh, server)`, the
   `TlsServer` last. The other shape considered was a `serve_tls` of its own, which
   would need another name again for io_uring.
2. The benchmark server's `TLS_PORT` defaults to the port + 1 (8081), as `H2C_PORT`
   does to the port + 2, but only when `TLS_CERT` and `TLS_KEY` are set.
