# goose-http

A proof of concept: a small, fast HTTP/1.1 server written in
[Goose](https://github.com/kaitk/goose), benchmarked against the fastest Rust and Odin
servers. It starts with an epoll event loop per core and may move to io_uring.

This repository is a Goose program, not an addition to Goose (Kait, 2026-10-10). Gaps found
in the compiler or the standard library are recorded in
[docs/goose-findings.md](docs/goose-findings.md), not patched here. It may later grow
into the HTTP layer of a Goose port of snowtime-native; nothing here depends on that.

## The question

Can a Goose HTTP server match the fastest Rust and Odin servers on plaintext and JSON
benchmarks, in a small amount of code? Task 004 answers it for epoll, and task 005 for
io_uring.

## Scope

In scope: HTTP/1.1 with keep-alive and pipelining, `Content-Length` request bodies, a
plaintext and a JSON endpoint, and the C shim the server needs for syscalls. Out of
scope: TLS, HTTP/2, chunked request bodies, routing beyond a few fixed paths, and Windows
as a benchmark platform.

## Layout

```text
src/           the Goose program
shim/          C headers passed to goose with --include: sockets, epoll, later io_uring
bench/         the competing servers, the load scripts, and the recorded results
scripts/       build and run scripts
docs/          architecture, development setup, and the Goose findings log
tasks/         task tracking (tasks/README.md)
```

`shim/` arrives with task 002 and `bench/` with task 004. Setup and the build commands are
in [docs/development.md](docs/development.md).

## Pins

| What | Pin | Why |
|---|---|---|
| Goose compiler | `kaitk/goose` `3536810` (`master`, 2026-10-10) | The language and stdlib change often |

Move the pin in its own commit, with the build and benchmark results that still hold.
