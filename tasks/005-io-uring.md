# 005: io_uring

Status: todo (starts after task 004)

Replace the epoll loop's readiness model with io_uring's completion model, and keep it
only if it measures faster. The HTTP parser and response code from task 003 stay as they
are; only the event loop and the shim change.

liburing's helpers are mostly `static inline` functions, which `extern fn` can't bind, so
`shim/uring.h` wraps the ones the loop uses as plain functions. Each worker owns its own
ring, which matches Goose's shared-nothing workers.

Revisit this plan with task 004's profile: if the epoll server's time goes to syscalls,
io_uring helps; if it goes to parsing or response building, it won't.

## Acceptance criteria

- [ ] `shim/uring.h` over liburing, with the liburing version and minimum kernel
      recorded
- [ ] An io_uring loop per worker with multishot accept, multishot receive into a
      provided buffer ring, and sends batched per loop iteration
- [ ] The same behavior as task 003's server: its tests pass against both loops,
      selected at build time
- [ ] Task 004's matrix rerun with both loops, and the results recorded here
- [ ] A decision recorded in `docs/architecture/README.md`: which loop is the default,
      and why
