# 002: The C shim for sockets and epoll

Status: done

The thin C layer in `shim/net.h` that the server reaches the kernel through, passed to
goose with `--include`, and a blocking echo server that proves each call works from
Goose before the event loop depends on them.

The shim exposes plain functions over integers, flat structs, and slices (spec §7.10). It
returns `-errno` on failure instead of `-1`, so Goose code needs no `errno` accessor. It
owns every kernel structure whose layout differs by architecture: `sockaddr_in`, and
`epoll_event`, which is packed on x86-64 but not on ARM, so Goose sees a flat struct of
its own.

## Acceptance criteria

- [x] `shim/net.h` with listen (socket, `SO_REUSEADDR`, `SO_REUSEPORT`, `TCP_NODELAY`,
      bind, listen, non-blocking), `accept4`, `read`, `write`, `writev` or a batched
      write, `close`, `epoll_create1`, `epoll_ctl`, `epoll_wait` into a Goose array of
      events, and a monotonic and a wall clock
- [x] Each `extern fn` declared in one Goose module, `src/sys.goose`, with the C
      obligations §7.10 leaves to the programmer noted where they apply
- [x] A blocking echo server in Goose that answers `nc` and survives a client that
      disconnects mid-write (`SIGPIPE` ignored or `MSG_NOSIGNAL` used)
- [x] An epoll echo server with one worker, tested with many concurrent clients
- [x] Anything Goose couldn't express directly recorded in `docs/goose-findings.md`

## What was built

- `shim/net.h`: `net_listen`, `net_accept` (`accept4`), `net_recv`, `net_send`,
  `net_close`, `net_epoll_create`, `net_epoll_ctl`, `net_epoll_wait`, `net_clock_ms`,
  `net_time_s`, and `net_strerror`. Read and write are `recv` and `send`, so `send` can
  pass `MSG_NOSIGNAL`. The batched write is a single `send` of one buffer: `writev` would
  need a list of slices, which can't cross to C (`docs/c-interop.md`). The clocks are
  the coarse ones; `std` already has the precise `clock_ns` and `time_ns`.
- `src/sys.goose`: the `extern fn`s in namespace `sys`, with the errno values, epoll
  bits, and `epoll_ctl` ops the server compares against. `shim/net.h` checks each of
  those numbers with `_Static_assert`, and checks that `sys::Event` is 12 bytes.
- `src/echo.goose`: the two echo servers, run as `build/server echo-blocking PORT` and
  `build/server echo-epoll PORT`.
- `scripts/test-echo.sh` and `scripts/echo_client.py`: the tests below.

`SO_REUSEPORT` is in `net_listen` behind `sys::REUSEPORT`, but neither echo server sets
it. Task 003's workers are its first use.

## How it was tested

On WSL2 Ubuntu 26.04.1, kernel 6.18.40.1-microsoft-standard-WSL2, 16 logical CPUs, Goose
`3536810`, gcc 15.2.0, Python 3.14.4, 2026-10-10. `scripts/test-echo.sh` passed against
the gcc build (`scripts/build.sh`) and the TinyCC build (`scripts/test-echo.sh
scripts/run.sh`), then five more times in a row against the gcc build. Against each
server it runs:

- `printf 'hello\n' | nc -N`, which must come back unchanged.
- 10 clients that hang up while the server writes. Five send without reading until both
  directions' buffers are full (5.3 to 7.5 MB) and close with data unread, so the
  server's `send` fails with `ECONNRESET`. Five send 24 KB and close before the echo
  arrives; the reset then lands in `CLOSE_WAIT` and a later `send` fails with `EPIPE`.
  The script requires at least one `EPIPE` in the server's log, and a working echo
  afterwards. Over the five repeated runs, 49 of the 50 `EPIPE` rounds got one.
- Many clients at once, each sending random bytes and comparing the echo: 20 clients of
  64 KB against the blocking server, and against the epoll server 2,000 clients of 64 KB
  and then 10,000 of 100 bytes, with 10,000 connections open at once.

The control: the same `build/server.c` compiled against a copy of `shim/net.h` with
`MSG_NOSIGNAL` replaced by `0`. Both servers died at the first 24 KB round with exit
status 141 (128 + `SIGPIPE`), so the cut test does reach the signal.

Accepted sockets inherit `TCP_NODELAY` from the listener on this kernel: a C test that
set it on a listener read it back as 1 with `getsockopt` on the accepted socket.
`net_listen` relies on that.
