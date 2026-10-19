# 053: Outbound connections

Status: in-progress (asked for 2026-10-19). The blocking socket and the epoll and kqueue
loop's half are built, on the branch `outbound`; see "Handover" at the end for what
remains.

The loop opens TCP connections to other servers, not only accepts them. goose-postgres
needs them (its task 001), and so do the ACME package's requests to its directory over
goose-tls's client TLS (goose-rest's task 049) and any HTTP client. goose-rest's HttpArena plan (its task 047) puts them before Postgres:
api-4, api-16, gateway-64, gateway-h3, and production-stack all query Postgres.

HttpArena's `async-db` rules ask for an async driver with a pool sized from
`DATABASE_MAX_CONN` (256 at HttpArena `2d85137`, 2026-10-18), so a thread blocking on
each connection won't do. The protocol packages take bytes in and give bytes out, and
the loop owns the socket, as it does for accepted connections.

A second half came with goose-rest's task 052 (2026-10-19): database work with several
queries runs as one job on a lane, which runs no loop, and blocks on its socket.
goose-postgres's blocking facade (its task 002) takes that socket as its transport.

## Steps

1. The API: open a connection to an address and port, learn when it's connected or
   failed, then read and write as on an accepted connection, with its own timeouts.
   Decide which thread owns an outbound connection: the worker that asked, or a lane
   that holds a pool for every worker.
2. A non-blocking connect on each loop: epoll, io_uring (`IORING_OP_CONNECT`), kqueue,
   and IOCP (`ConnectEx`).
3. Name resolution. `getaddrinfo` blocks, so the first version takes `localhost` and
   IP addresses only, and a later one resolves names off the loop.
4. Tests: connect to a test server on each loop, a refused connection, a connect
   timeout, and a peer that closes.
5. A blocking socket, with time limits, for a thread that runs no loop.

## Acceptance criteria

- [x] The API and the owning thread recorded in `docs/decisions.md` and `docs/api.md`
- [ ] Connect, read, write, and close work on epoll, io_uring, kqueue, and IOCP, each
      with a test (epoll and kqueue done; io_uring and IOCP fail with `ENOSYS`)
- [x] A refused connection and a connect timeout reach the program as errors
- [ ] A blocking socket for lanes, with a test, on Linux, macOS, and Windows (Linux and
      macOS pass; Windows's shim compiles, with Zig's MinGW target, but hasn't run)
- [ ] goose-postgres's task 001 can open its pool on it
- [x] The API's names agreed (2026-10-19)

## Handover

Written 2026-10-19, at the branch's first commit.

### Built

- `socket.goose` (`http::Socket`), imported by `http.goose`:
  - Blocking, for a lane: `connect(host, port, ms)`, `send_all(s, data, ms)`,
    `recv(s, buf, ms)`, `hangup(s)`.
  - On the loop: `connect_start(host, port)`, `connected(s)`, `wait_socket(out, s, events, ms)`
    with `READABLE` and `WRITABLE`, then `WAKE` with tag `SOCKET_READY` or `TIMEOUT`,
    and `recv(s, buf)` and `send(s, data)`, which never block.
  - A host is `localhost`, an IPv4 or IPv6 literal, or `unix:PATH`; other names fail
    with `resolve`'s `ENOSYS`.
- The shim, per platform: `net_connect`, `net_connected`, `net_poll`, `net_port`,
  `net_loop_bind`, and `net_arm` in `shim/net.c`, `shim/kqueue.c`, and
  `shim/net_win.c` (where `net_arm` is `ENOSYS`). `sys.goose` declares them, with
  `ENOTCONN`, `ETIMEDOUT`, `ECONNREFUSED`, and `EINPROGRESS`.
- `epoll.goose`: the loop binds its poller for `net_arm` while it runs, and hands an
  event whose tag is a key (at least `SOCKET_KEYS`) to `delivered`, as mail.
- Tests: `test/outbound/outbound_blocking.goose` (round trip through `localhost`, an 8 MiB send,
  a server that closes, refused, a connect timeout against a full backlog, a name, port
  0) and `test/outbound/outbound_loop.goose` (the same through `serve_epoll`'s handler, a 4 MiB
  send, and `ENOSYS` on `serve`). The loops listen on Unix sockets in the test's own
  directory, so parallel runs share no port.
- Docs: decisions ("Outbound connections: blocking on a lane, readiness on the worker's
  loop"), architecture, API ("Outbound connections"), patterns (slow work), README's
  status.

### What passes

On 2026-10-19, at Goose `dcc2747`, the pin:

- `scripts/test.sh` on macOS (M1 Pro, kqueue) and in an arm64 `ubuntu:26.04` container
  on it (Docker Desktop, `--security-opt seccomp=unconfined`, epoll and native
  io_uring): all passed, `test/outbound/` included, both before and after the branch
  was rebased onto `main` with h2c on io_uring merged (`37aa7030`). `wait_socket` on
  `serve` still fails with `ENOSYS` there: only `epoll_loop` binds a poller for it.
- `shim/net_win.c` compiles with `zig cc -target x86_64-windows-gnu`; nothing ran on
  Windows.
- goose-postgres's protocol over the blocking calls against `postgres:18` in Docker
  (host port 55510, SCRAM-SHA-256): it logged in, ran a query with parameters whose
  row held 100,000 bytes, and terminated, and a wrong password failed the login
  cleanly. The program was a scratch file outside both repositories, importing each
  from its checkout, as the facade's would; it isn't kept. goose-postgres's
  `scripts/live.sh` is the place for such a run once the facade exists.

### What remains, in order

1. goose-postgres's task 002 builds its facade on the blocking calls (below), and task
   005 its pool on `wait_socket`.
2. io_uring, on the Windows desktop next: `IORING_OP_CONNECT`, and readiness through
   `IORING_OP_POLL_ADD` with the key as its tag, which `uring.goose` would deliver as
   the epoll loop does.
3. The emulated ring and IOCP: the emulation can arm its own epoll instance or kqueue
   as `net_arm` does; IOCP needs `ConnectEx` and a zero-byte `WSARecv` for readability.
4. Name resolution off the loop: `getaddrinfo` on a lane, or in the blocking `connect`
   only, where blocking is allowed.
5. Run `test/outbound/outbound_blocking.goose` on Windows. `test/run_tests.py` skips
   `test/outbound/` there for now: `outbound_loop.goose` needs `serve_epoll` and a Unix
   socket, and Windows may refuse a connect to a full backlog with `ECONNREFUSED` where
   the blocking test expects `ETIMEDOUT`.
6. An h2 stream waiting on a socket: `delivered` finds it by its key, but no test covers
   it yet.

### What goose-postgres's facade calls

```rust
import http from "github.com/kaitk/goose-http@<tag with task 053>";

let s, e = http::connect(cfg.host, cfg.port, connect_ms);   // e.code: ECONNREFUSED, ETIMEDOUT, ...
http::send_all(s, out, ms);          // an http::Error; code 0 when all went
let n = http::recv(s, buf, ms);      // bytes into buf; 0: the server closed; -ETIMEDOUT; -code
http::hangup(s);
```

`pg::Config.host` passes straight in: `localhost`, an address, or `unix:` and a
directory's socket path for a Unix socket (`/var/run/postgresql/.s.PGSQL.5432`), which
the facade builds from a host that starts with `/`, as libpq does. A run against a live
Postgres 18 is recorded under "What passes".

### Traps

- `net_connected` reports a failed connect once: `SO_ERROR` is cleared by the read, and
  a second call gives `ENOTCONN`.
- A refused connect to loopback can fail inside `connect_start` on some platforms, or later in
  `connected`; a handler checks both.
- `wait_socket` arms the socket once (`EPOLLONESHOT`, `EV_ONESHOT`). An armed socket
  whose exchange stopped waiting, by `TIMEOUT` or mail, can still raise its event
  later, while the same exchange waits for something else: it gets a `WAKE` with
  `SOCKET_READY` that means nothing. Hang up the socket at `TIMEOUT`, or treat it as
  "try again".
- The connect-timeout tests fill a listener's backlog of 1 with eight connects that are
  never accepted; Linux and macOS then drop the next SYN.

### Answers

- The names (2026-10-19): `dial` became `connect_start`; `http::Socket`, `connected`,
  `wait_socket`, `READABLE`, `WRITABLE`, `SOCKET_READY`, `recv` and `send` on a socket
  (overloads beside the reply's `send`), `connect`, `send_all`, and `hangup` stay.
- `wait_socket` on io_uring, the emulated ring, and IOCP keeps failing with `ENOSYS`
  when it's called (2026-10-19): `serve` can't know at startup whether a handler will
  call it, unlike an h2c or TLS listener. io_uring and IOCP support is to be done on
  the Windows desktop next.
