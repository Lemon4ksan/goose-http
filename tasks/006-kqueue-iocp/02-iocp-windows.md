# 006.02: IOCP on Windows

Status: done

A completion loop on Windows through I/O completion ports, following task 005's loop,
behind `shim/iocp.c` over Winsock ([task 006](README.md)). Windows is for running the
server correctly, not for benchmarks.

Built and tested on Windows 11 Pro 25H2 (10.0.26200), Ryzen 7 5800X3D, with Git Bash
5.2.26, Python 3.14.6, mingw curl 8.7.1, MSVC 19.51, and Goose `efe3155`, 2026-10-11.

## Acceptance criteria

- [x] `shim/iocp.c` and a completion loop running on Windows, passing the same tests
- [x] How Windows is built and tested recorded in `docs/development.md`

## Design

### The loop doesn't change

`shim/iocp.c` implements `src/ring.goose`'s `ur_*` calls over a completion port and
Winsock, so `src/uring.goose` and `src/main_uring.goose` run unchanged.
`shim/net_win.c` gives `src/sys.goose`'s calls over Winsock, with the epoll calls
returning `ENOSYS`. `src/main_uring.build` lists both under `c_sources_windows`, with
`c_libs_windows = ["ws2_32", "mswsock"]`. No Goose file changed for Windows.

IOCP completes one operation per request, so the shim emulates what io_uring has and
IOCP lacks:

- **Accept.** The workers share one listener: `net_listen` with `REUSEPORT` returns the
  same socket to every worker, from a table under a mutex. A socket belongs to at most
  one completion port, so the listener belongs to none. Each ring keeps one `AcceptEx`
  posted, with an event in its `OVERLAPPED`, and a `RegisterWaitForSingleObject`
  callback posts the completion to that ring's port, as libuv does. The ring posts the
  `AcceptEx` again after each accept.
- **Receive.** A zero-byte `WSARecv` stays posted on each connection. When it completes,
  the shim makes one non-blocking `recv` into a free 4 KB buffer of the ring's, reports
  it with `more=1`, and posts the receive again. An idle connection holds no buffer, as
  with io_uring's provided buffers; a real buffer posted per connection deadlocked
  `many 10000`. With no free buffer, the receive ends with `ENOBUFS` and `more=0`.
  `recv` returning 0 is EOF, and `WSAEWOULDBLOCK` posts the receive again and reports
  nothing.
- **Send.** The shim copies a send into a record of its own, with a free list for
  records of 8 KB or less. A short send is posted again for the rest, unless the socket
  was closed meanwhile, and reported once.
- **Cancel and close.** `ur_cancel` sets a flag and calls `CancelIoEx`; the next
  completion reports `ECANCELED` with `more=0`, and its data stays in the socket.
  `ur_close` calls `closesocket` and marks the socket's record closed. Each pending
  request holds a reference to the record, so a late completion never touches a reused
  handle. Two open-addressing maps find the records, by socket and by tag. A post that
  fails at once goes on a ready list, which `ur_wait` drains first.

### Errors

`net_win_err` maps Winsock and Win32 errors to Linux's errno values, as libuv's
`uv_translate_sys_error` does: `WSAESHUTDOWN` to `EPIPE`, `ERROR_NETNAME_DELETED` to
`ECONNRESET`, `ERROR_OPERATION_ABORTED` to `ECANCELED`. An unmapped code becomes 1000
plus its Windows code. `net_strerror` gives glibc's text for mapped codes, and
`FormatMessageW`'s, in UTF-8, otherwise.

A client that hangs up gives `ECONNRESET` on a send and `ECONNABORTED` on a receive,
never `EPIPE`, and Windows has no `SIGPIPE`.

### Listening

- On 127.0.0.1 only. Windows Defender Firewall has `NotifyOnListen` on, so listening on
  any other address raises a prompt.
- `SO_EXCLUSIVEADDRUSE`, so a second server on the port gets `EADDRINUSE`, as on Linux.
- `listen(SOMAXCONN_HINT(backlog))`, because a plain backlog is capped at 200.
- `WSAStartup` runs once, on first use. The clocks are `GetTickCount64` and
  `GetSystemTimeAsFileTime`.

### Build

`scripts/build.sh` under Git Bash (MINGW or MSYS) defaults to `LOOP=iocp`, which builds
`src/main_uring.goose`, and to `CC=msvc`. It refuses `iocp` off Windows and `epoll` on
Windows. `goose build` works natively: `goose toolchain` finds MSVC and clang-cl, and
both `--cc msvc` and `--cc clang-cl` build the server. cl needs `/std:c11` for
`_Static_assert`, which the sidecar passes as `c_flags_msvc`.

## Tests

On the machine above, at idle priority:

- `scripts/test-unit.sh` passes, through TinyCC.
- `scripts/test-http.sh` passes with 4 workers: curl, tfb, pipeline, chunked, keepalive,
  all 22 hostile cases, `many 10000`, and slow. It leaves out the load runs (wrk has no
  Windows build, and Windows isn't a benchmark platform) and `emfile` (`ulimit -n`
  doesn't reach a native program, and Windows has no per-process socket limit).
  `CC=clang-cl` passed it too.
- `scripts/test-echo.sh` passes echo-blocking. echo-epoll has no epoll to run on, and the
  nc check is left out, because Windows has no nc; `ping` still runs.
- The Linux tests pass on both loops with the Windows changes to `scripts/` and
  `src/main_uring.build`.

`slow` failed 1 run in 10 at first: the slowloris client got WinError 10054 (connection
reset) instead of its 408. The sweep queued the 408 and closed the socket at once, and
`closesocket` aborts an overlapped send that is still pending. The client thread died
without adding to the check's errors, so the run printed ok. Two fixes followed: the
sweep sends its 408 through the same shutdown and drain as any refusal
([architecture](../../docs/architecture.md#the-handler-and-its-events)), and `http_client.py`
counts a client thread that raises as a failure. After them, 10 runs of 10 passed.

## Open

- Windows serves pending `AcceptEx` requests last-posted-first, so one worker took every
  connection in bursts of 1, 16, and 64, and in `many 400` and `many 2000`. That costs
  throughput, not correctness. Round-robin dispatch from the wait callback would spread
  them, if Windows ever matters for speed. With one worker taking nearly every
  connection, the 16,384-connection limit acts almost per process.
- No test reaches the path where a worker at its connection limit cancels its accept.
