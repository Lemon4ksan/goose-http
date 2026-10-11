# 006: kqueue on macOS and BSD, IOCP on Windows

Status: todo (asked for 2026-10-10; after task 004)

Run the server on macOS and the BSDs through kqueue, and on Windows through I/O
completion ports. Linux stays the benchmark platform (`docs/architecture/README.md`), so
this task is about the server running correctly elsewhere, not about matching its Linux
numbers.

The two fit the two loop shapes the Linux server already has or plans. kqueue reports
readiness, as epoll does, so the epoll loop of task 003 can run on it behind a shim of the
same shape, `shim/kqueue.c`. IOCP reports completions, as io_uring does, so it follows
task 005's loop, through `shim/iocp.c` over Winsock.

Errors keep one set of codes on every platform, as libuv does. libuv's `UV_EAGAIN`
and the other codes are the negated errno on Unix, and its Windows layer
(`uv_translate_sys_error`) maps Winsock and Win32 errors onto the same codes. Here the
constants in `src/sys.goose` become the project's own codes, keeping their Linux values.
Each shim returns them: `shim/net.c` passes errno through (its `_Static_assert`s pin the
values), and `shim/kqueue.c` and `shim/iocp.c` translate (macOS's `EAGAIN` is 35, and
Winsock's is `WSAEWOULDBLOCK`). Goose code never sees a platform's own numbers.

The spec has no conditional compilation, so a root file's sidecar picks each platform's
shim (`c_sources_linux`, `_macos`, and `_windows`, task 010), and the build script picks
the root file. Conditional compilation in Goose
would let one root file serve every platform; that is a stretch goal, and an addition to
Goose, so it starts as a findings entry and a question to Kait.

Open question for the start of the task: whether the Windows build works through the
native `goose.exe` and MSVC, which `docs/development.md` so far uses only for `--check`.

## Subtasks

- [01-kqueue-macos.md](01-kqueue-macos.md): the epoll loop on macOS through kqueue.
- [02-iocp-windows.md](02-iocp-windows.md): a completion loop on Windows through IOCP.

## Acceptance criteria

- [ ] Subtasks 01 and 02 done
- [ ] Stretch: one root file for every platform, if Goose gains conditional compilation
