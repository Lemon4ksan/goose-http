# 011: goose-http as a Goose package

Status: todo (after task 010; asked for by Kait, 2026-10-11)

Goose `efe3155` has packages: a program declares one in its root file,
`import http from "github.com/kaitk/goose-http@<ref>";`, and the compiler fetches the
repository, compiles the C its sidecar names, and links it (the pinned checkout's
`docs/packages.md`). This repository becomes such a package, so a program can serve HTTP
with its own routes; the benchmark server becomes one program that uses it.
`../goose-ngfx` is the reference for the layout (`docs/development.md`).

The design, proposed:

- The package is `http`, with its entry `http.goose` at the repository root and every
  module in `namespace http`: a package has one namespace, and namespaces don't nest
  (`namespace http::sys;` is a parse error at `efe3155`). `sys::` and `ring::` become
  part of `http::`.
- `http.build` names the shim, `c_sources_linux = ["shim/net.c"];`, and `_macos` and
  `_windows` sources as task 006 adds them.
- A program passes its routes to the loop as a function value, which Goose compiles into
  the loop, with no runtime function pointers (spec §7.6). `thread_spawn` copies only
  flat arguments (§11.2), so the program owns the `thread_fn` and calls the loop from it:

  ```goose
  import http from "github.com/kaitk/goose-http@<ref>";

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
- The io_uring loop stays in the server program until task 005 decides between the
  loops: as a package module it would make every program link liburing.

## Acceptance criteria

- [ ] `http.goose` and `http.build` at the root, every module in `namespace http`
- [ ] `http::serve` takes the program's handler; the benchmark server in `server/`
      serves TechEmpower's and HttpArena's routes through it
- [ ] A program outside the repository imports the package from git at a commit, and
      `goose build` and `goose run` both work with it
- [ ] The tests pass, and the server's rate in `bench/run.sh`'s closest cells matches
      task 010's build within the runs' spread
- [ ] `README.md` says how to use the package, as goose-ngfx's does
