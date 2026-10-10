# 006: kqueue on macOS and BSD, IOCP on Windows

Status: todo (asked for by Kait, 2026-10-10; after task 004)

Run the server on macOS and the BSDs through kqueue, and on Windows through I/O
completion ports. Linux stays the benchmark platform (`docs/architecture/README.md`), so
this task is about the server running correctly elsewhere, not about matching its Linux
numbers.

The two fit the two loop shapes the Linux server already has or plans. kqueue reports
readiness, as epoll does, so the epoll loop of task 003 can run on it behind a shim of the
same shape, `shim/kqueue.h`. IOCP reports completions, as io_uring does, so it follows
task 005's loop, through `shim/iocp.h` over Winsock.

Open questions for the start of the task:

- How the program picks a shim and a loop per platform. The spec has no conditional
  compilation, so the choice likely sits in the build scripts: which header to
  `--include`, and which root file to compile.
- The errno values in `src/sys.goose` are Linux's, and macOS's differ (`EAGAIN` is 35,
  not 11). `shim/net.h` asserts them at compile time; the other shims need either their
  own constants or a translation to the Linux values.
- Whether the Windows build works through the native `goose.exe` and MSVC, which
  `docs/development.md` so far uses only for `--check`.

## Acceptance criteria

- [ ] `shim/kqueue.h` and the epoll loop running on macOS through it, passing the same
      tests as on Linux
- [ ] `shim/iocp.h` and a completion loop running on Windows, passing the same tests
- [ ] How each platform is built and tested recorded in `docs/development.md`
- [ ] The way the platform is chosen recorded in `docs/architecture/README.md`
