# 011: goose-http as a Goose package

Status: todo (asked for 2026-10-11)

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
  `http::spawn_workers` taking a `thread_fn` as a function value is untested.
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
  call: `answer` is nearly the same in `src/server.goose` and `src/uring.goose`, and
  routes are wired into it (`http::respond`, and `http::reads_body`'s `/baseline11`).
  A handler's response must not abort the process: today each must fit in
  `MAX_RESPONSE`, 512 bytes, in a fixed 8 KB write buffer.
- A library can't end the process: `http::serve` returns errors that `sys::check`
  and the shims turn into exits today, and takes its settings (address, limits,
  timeouts, buffer sizes) as one flat struct instead of constants and `WORKERS`.

## Acceptance criteria

- [ ] `http.goose` and `http.build` at the root, every module in `namespace http`
- [ ] `http::serve` and `http::serve_epoll` take the program's handler; the benchmark
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
