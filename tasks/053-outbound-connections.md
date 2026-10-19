# 053: Outbound connections

Status: todo (asked for 2026-10-19)

The loop opens TCP connections to other servers, not only accepts them. goose-postgres
needs them (its task 001), and so do the ACME package's requests to its directory over
goose-tls's client TLS (goose-rest's task 049) and any HTTP client. goose-rest's HttpArena plan (its task 047) puts them before Postgres:
api-4, api-16, gateway-64, gateway-h3, and production-stack all query Postgres.

HttpArena's `async-db` rules ask for an async driver with a pool sized from
`DATABASE_MAX_CONN` (256 at HttpArena `2d85137`, 2026-10-18), so a thread blocking on
each connection won't do. The protocol packages take bytes in and give bytes out, and
the loop owns the socket, as it does for accepted connections.

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

## Acceptance criteria

- [ ] The API and the owning thread recorded in `docs/decisions.md` and `docs/api.md`
- [ ] Connect, read, write, and close work on epoll, io_uring, kqueue, and IOCP, each
      with a test
- [ ] A refused connection and a connect timeout reach the program as errors
- [ ] goose-postgres's task 001 can open its pool on it
