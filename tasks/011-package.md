# 011: goose-http as a Goose package

Status: in-progress (asked for 2026-10-11)

Goose `efe3155` has packages: a program declares one in its root file,
`import http from "github.com/kaitk/goose-http@v0.1.0";`, and the compiler fetches the
repository, compiles the C its sidecar names, and links it (the pinned checkout's
`docs/packages.md`). This repository becomes such a package, so a program can serve HTTP
with its own routes; the benchmark server becomes one program that uses it.
`../goose-ngfx` is the reference for the layout (`docs/development.md`).

The design, proposed:

- The package is `http`, with its entry `http.goose` at the repository root and every
  module in `namespace http`: a package has one namespace, and namespaces don't nest
  (`namespace http::sys;` is a parse error at `efe3155`). `sys::` and `ring::` become
  part of `http::`.
- `http.build` names each platform's shim, which picks the backend at compile time, as
  libuv's build and Go's build tags do: `shim/net.c` and `shim/uring.c` with liburing on
  Linux, `shim/kqueue.c` on macOS, and `shim/net_win.c` and `shim/iocp.c` on Windows.
- A program passes its routes to the loop as a function value, which Goose compiles into
  the loop, with no runtime function pointers (spec §7.6). `thread_spawn` copies only
  flat arguments (§11.2), so the program owns the `thread_fn` and calls the loop from it:

  ```goose
  import http from "github.com/kaitk/goose-http@v0.1.0";

  thread_fn worker(port: i32) {
      http::serve(port) { req, body, out => http::text(out, req, "Hello, World!") }
  }

  fn main() { http::spawn_workers(worker, 8080); }
  ```

  A prototype at `efe3155` ran this shape: a package from a directory, with sidecar C,
  whose generic loop a program's `thread_fn` called with a block.
  `http::spawn_workers` taking a `thread_fn` as a function value doesn't compile at
  `efe3155`: `thread_spawn` rejects a function value bound to a `thread_fn`
  (`docs/goose-findings.md`). So the program spawns its workers itself, with
  `http::worker_count(cfg)` (2026-10-11), and the loops take a `Config`, not a port.
- The routes in `http::respond` today, TechEmpower's and HttpArena's, move into the
  benchmark server's handler, a program in `server/` that imports the package from
  `"../"`. The parser, the response helpers, and the date stay in the package.
- Two entry points, and the program picks one by calling it (decided 2026-10-11). Goose
  compiles a generic function only where it's called, so the one a program doesn't call
  never reaches its binary, and the choice needs no flag:
  - `http::serve` is the portable loop, today's `src/uring.goose`, over the ring API of
    `src/ring.goose`, as Boost.Asio and libxev put one completion API over every
    platform. Linux runs it on io_uring, Windows on IOCP (`shim/iocp.c`), and macOS on a
    ring emulated over kqueue in C, as `shim/iocp.c` emulates multishot requests. On
    Linux, `ur_create` falls back to the same emulation over epoll when
    `io_uring_setup` fails, as in a container whose seccomp profile blocks io_uring.
  - `http::serve_epoll` is today's readiness loop, `src/server.goose`, on Linux (epoll)
    and macOS (kqueue). On Linux it uses a quarter of the io_uring loop's memory and runs
    where io_uring is blocked, and on macOS it skips the emulation's copies. On Windows it fails at startup with `ENOSYS`.
  The benchmark server reads `LOOP=epoll|uring` at startup and calls one of them,
  uring by default on Linux, as task 005 decided. A runtime pick inside the package was
  rejected: no event-loop library we looked at does it, except as a fallback from
  io_uring to epoll. The cost of one sidecar: every Linux program that imports `http`
  links liburing, even one that calls only `serve_epoll`.
- Before the handler can go in, the loops' request handling becomes one function both
  call: `answer` was nearly the same in `src/server.goose` and `src/uring.goose`, with
  routes wired into it (`http::respond`, and `http::reads_body`'s `/baseline11`).
  A handler's response must not abort the process. Done (2026-10-11): `answer` in
  `src/app.goose` serves both loops, and the write buffer grows to take a response of
  any size whole.
- A library can't end the process: `http::serve` returns errors that `sys::check`
  and the shims turned into exits, and takes its settings (address, limits,
  timeouts, buffer sizes, workers) as one flat struct instead of constants and
  `WORKERS`. Done (2026-10-11): `Config` and `Error` in `src/app.goose`. The loops
  still write two notes to stderr, `accept` at the fd limit and an `epoll_ctl` that
  failed for one connection, as they go on serving.

## The handler (decided 2026-10-11)

Task 013's items 6, 7, and 8 decide the handler's shape: a handler called once per
request can't read a body in pieces or stream a response. `v0.1.0` serves requests and
responses of a fixed size, the second of task 013's options, and the handler is:

```goose
http::serve(cfg) { req, body, out => ... }
```

- `req` is `http::Request`, the parsed head, with slices into the read buffer: method,
  target, version, keep-alive, the announced body length, and chunked framing.
- `body` is the whole request body when it fits in the read buffer (`max_head`) with its
  head, chunked bodies decoded. A longer `Content-Length` body is dropped as it arrives,
  and `body` is empty while `req.body` gives its length, so the handler can refuse it.
  This replaces the routes' `reads_body`: the loop needs no second function value to
  ask whether to keep a body. Implemented in this step.
- `out` is a reply: the worker's growable write buffer, with what the response's
  framing needs from the request (keep-alive, version, `HEAD`) and the cached `Date`.
  The handler writes one whole response of any size through helpers that write the
  status line and the fields every response has, the handler's own fields, and the
  body with its `Content-Length`. Status codes are a table the helpers look up, any
  code the handler names.
- Why not more now: header lookup (013 item 6) adds functions over `req`, and a
  `Request` field for the whole head, without changing the handler. Bodies read in
  pieces (item 7) and streamed responses (item 8) need a handler that resumes, which
  spec §7.6 rules out as a stored function value; they would come as another entry
  point, with per-connection state for the body or the stream, after `v0.1.0`.

## Acceptance criteria

- [x] `http.goose` and `http.build` at the root, every module in `namespace http`
- [x] `http::serve` and `http::serve_epoll` take the program's handler; the benchmark
      server in `server/` serves TechEmpower's and HttpArena's routes through either,
      picked by `LOOP`
- [ ] `http::serve` runs on Linux, macOS, and Windows, and on Linux without io_uring
- [ ] A program outside the repository imports the package from git at a commit, and
      `goose build` and `goose run` both work with it
- [ ] The tests pass, and the server's rate in `bench/run.sh`'s closest cells matches
      task 010's build within the runs' spread
- [ ] `README.md` says how to use the package, as goose-ngfx's does, and which entry
      point to call: `serve` everywhere, `serve_epoll` for the fastest loop on Linux
      and macOS
- [ ] Tagged `v0.1.0`, the ref the README's example imports
