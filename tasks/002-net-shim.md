# 002: The C shim for sockets and epoll

Status: todo

The thin C layer in `shim/net.h` that the server reaches the kernel through, passed to
goose with `--include`, and a blocking echo server that proves each call works from
Goose before the event loop depends on them.

The shim exposes plain functions over integers, flat structs, and slices (spec §7.10). It
returns `-errno` on failure instead of `-1`, so Goose code needs no `errno` accessor. It
owns every kernel structure whose layout differs by architecture: `sockaddr_in`, and
`epoll_event`, which is packed on x86-64 but not on ARM, so Goose sees a flat struct of
its own.

## Acceptance criteria

- [ ] `shim/net.h` with listen (socket, `SO_REUSEADDR`, `SO_REUSEPORT`, `TCP_NODELAY`,
      bind, listen, non-blocking), `accept4`, `read`, `write`, `writev` or a batched
      write, `close`, `epoll_create1`, `epoll_ctl`, `epoll_wait` into a Goose array of
      events, and a monotonic and a wall clock
- [ ] Each `extern fn` declared in one Goose module, `src/sys.goose`, with the C
      obligations §7.10 leaves to the programmer noted where they apply
- [ ] A blocking echo server in Goose that answers `nc` and survives a client that
      disconnects mid-write (`SIGPIPE` ignored or `MSG_NOSIGNAL` used)
- [ ] An epoll echo server with one worker, tested with many concurrent clients
- [ ] Anything Goose couldn't express directly recorded in `docs/goose-findings.md`
