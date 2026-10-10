# 005: io_uring

Status: todo (starts after task 008)

Add an event loop on io_uring's completion model beside the epoll loop, which stays
either way: it is the baseline io_uring is measured against, and the loop on kernels
without io_uring. The HTTP parser and response code from task 003 stay as they
are; only the event loop and the shim change.

liburing's helpers are mostly `static inline` functions, which `extern fn` can't bind, so
`shim/uring.h` wraps the ones the loop uses as plain functions. Each worker owns its own
ring, which matches Goose's shared-nothing workers.

Task 004's profile favors trying it: after the parser fix, 73% of a worker's cycles are in
the kernel, serving plaintext with 256 connections, and 27% in user code. Add
`xitca-web` in its io_uring configuration to `bench/` as the io_uring competitor; the
others in task 004 use epoll, except odin-http, whose cap there comes from one `send` per
response, not from io_uring. HttpArena's fastest io_uring servers are competitors too:
zix and zeemo (Zig), first and fifth in its pipelined test, and libreactorng (C), ninth
(task 009 has the source of these figures).

## Acceptance criteria

- [ ] `shim/uring.h` over liburing, with the liburing version and minimum kernel
      recorded
- [ ] An io_uring loop per worker with multishot accept, multishot receive into a
      provided buffer ring, and sends batched per loop iteration
- [ ] The same behavior as task 003's server: its tests pass against both loops,
      selected at build time
- [ ] xitca-web, zix, zeemo, and libreactorng in `bench/`, pinned and in their fastest
      documented configuration
- [ ] Task 004's matrix rerun with both loops, and the results recorded here
- [ ] A decision recorded in `docs/architecture/README.md`: which loop is the default,
      and why; the epoll loop stays buildable and tested
