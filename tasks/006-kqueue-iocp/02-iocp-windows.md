# 006.02: IOCP on Windows

Status: todo

A completion loop on Windows through I/O completion ports, following task 005's loop,
behind `shim/iocp.h` over Winsock ([task 006](README.md)).

## Acceptance criteria

- [ ] `shim/iocp.h` and a completion loop running on Windows, passing the same tests
- [ ] How Windows is built and tested recorded in `docs/development.md`
