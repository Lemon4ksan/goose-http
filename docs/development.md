# Development

Building, testing, and benchmarking run on Linux (WSL2 Ubuntu). Windows is for editing:
the native compiler typechecks the program there, but the server only runs on Linux.

## Toolchain

| Tool | Where | Version used (2026-10-10) |
|---|---|---|
| Goose compiler | `../goose`, at the pin in `README.md` | `3536810` |
| WSL2 Ubuntu | | 26.04.1 LTS, kernel 6.18.40.1-microsoft-standard-WSL2 |
| C compilers | WSL | gcc 15.2.0, clang 21.1.8 |
| CMake, Ninja | WSL, apt | 4.2.3, 1.13.2 |
| Visual Studio Build Tools | Windows | 2026 (18), MSVC 19.51 |
| VS Code | Windows | 1.85 or later, for the Goose extension |

Load generators (`wrk`, `oha`) and the competing servers (Rust through `cargo`, Odin)
come with tasks 003 and 004.

## Set up the Goose compiler

The scripts expect a plain Goose checkout next to this repository, at `../goose`. Leave it
on the pinned commit and don't edit it (`AGENTS.md`). One checkout serves both platforms:
WSL builds into `build-linux/` and Windows into `build/`, and the checkout's `.gitignore`
covers both.

1. Clone the checkout at the pin, with the TinyCC submodule only. TinyCC is what lets
   `goose file.goose` compile and run a program in process; the other submodules are for
   graphics, audio, and physics, which this server doesn't use.

   ```sh
   git clone https://github.com/kaitk/goose.git ../goose
   git -C ../goose checkout 3536810
   git -C ../goose submodule update --init third_party/tinycc
   ```

2. Build the Linux compiler, in WSL:

   ```sh
   sudo apt-get install -y cmake ninja-build
   cd ../goose
   cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release \
       -DGOOSE_GFX=OFF -DGOOSE_AUDIO=OFF -DGOOSE_PHYSICS=OFF -DGOOSE_UI=OFF
   cmake --build build-linux
   ```

   The compiler is `../goose/build-linux/goose`. Point `GOOSE` at it, for example in
   `~/.profile`:

   ```sh
   export GOOSE=$HOME/path/to/goose/build-linux/goose
   ```

3. Build the Windows compiler, in PowerShell. CMake comes with the Visual Studio Build
   Tools, at `Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`.

   ```powershell
   cmake -S ..\goose -B ..\goose\build -G "Visual Studio 18 2026" `
       -DGOOSE_GFX=OFF -DGOOSE_AUDIO=OFF -DGOOSE_PHYSICS=OFF -DGOOSE_UI=OFF
   cmake --build ..\goose\build --config Release
   ```

   The compiler is `..\goose\build\Release\goose.exe`.

The compiler finds the stdlib by walking up to four directories from its own binary, so
both builds find `../goose/stdlib` with no setting. A compiler copied anywhere else needs
`GOOSE_STDLIB` pointing at the checkout's `stdlib/`; the compiler reads it itself. The
error when the stdlib is missing names the wrong path
([findings](goose-findings.md#a-missing-stdlib-is-reported-as-a-missing-file-next-to-the-program)).

### Move the pin

The Goose repository changes daily. Fetch it at the start of a session, and move the pin
in its own commit with the builds and results that still hold (`README.md`):

```sh
git -C ../goose fetch
git -C ../goose log --oneline HEAD..origin/master
git -C ../goose checkout origin/master
git -C ../goose submodule update third_party/tinycc
```

Then rebuild both compilers (`cmake --build` with the same directories), rerun the
scripts below, and update the pin in `README.md` and the table above.

## Build and run

Run these in WSL. Both work from any directory.

| Command | What it does |
|---|---|
| `scripts/run.sh [args]` | Compiles and runs `src/main.goose` in process through TinyCC, passing `args` to the program. For quick iteration. |
| `scripts/build.sh` | Compiles `src/main.goose` to `build/server.c` at `-O2`, then to `build/server` with `cc -O2`. For anything measured. |
| `scripts/test-echo.sh [server]` | Tests the echo servers of `build/server`, or of another command such as `scripts/run.sh` (below). |

Both build scripts pass `-D_GNU_SOURCE --include shim/net.h` to goose
([c-interop.md](c-interop.md#where-the-header-goes)). `build.sh` takes the C compiler from
`CC` and its flags from `CFLAGS` (default `-O2`). The generated C stays in
`build/server.c` for reading.

TinyCC can't place thread-local storage, so a program that spawns workers runs only
through `build.sh`.

The program takes a mode and a port (default 8080). Until task 003 adds the HTTP server,
the modes are the two echo servers of `src/echo.goose`:

```sh
build/server echo-blocking 8080   # one client at a time
build/server echo-epoll 8080      # one edge-triggered epoll loop
```

### Test the echo servers

`scripts/test-echo.sh` starts each echo server in turn and fails on the first error.
It needs `nc` (`netcat-openbsd`) and `python3`. Against each server it runs:

- `nc` and a one-line echo.
- 10 clients that hang up while the server writes (`scripts/echo_client.py cut`). Half
  fill both directions' buffers and close with data unread, so the server's `send` fails
  with `ECONNRESET`. The other half send 24 KB and close before the echo arrives, so a
  later `send` fails with `EPIPE`, the error that raises `SIGPIPE`. The script checks
  that the server logged an `EPIPE` and is still running.
- Many clients at once, each sending random bytes and checking the echo: 20 clients of
  64 KB for the blocking server, and 2,000 of 64 KB, then 10,000 of 100 bytes, for the
  epoll server.

`PORT` picks the port (default 29080). Keep it below 32768: the many-client runs leave
thousands of client sockets in `TIME_WAIT` on ports in the kernel's ephemeral range,
and a server port among them fails to bind with `EADDRINUSE`.

### From a Windows shell

The repository lives on the Windows drive, so WSL sees it at
`/mnt/c/Users/kait/projects/goose/goose-http`. Two things break commands passed to WSL
from Windows:

- `wsl.exe` hands its arguments to a shell that expands `$VARS` before `bash -c` sees
  them, so a variable set inside the command is empty. Put any command that uses
  variables in a script file and run `wsl.exe -d Ubuntu -- bash /mnt/c/.../script.sh`.
- Git Bash rewrites arguments that look like POSIX paths, so `/mnt/c/...` turns into
  `C:/Program Files/Git/mnt/c/...`. Set `MSYS_NO_PATHCONV=1` for the `wsl.exe` call.
  PowerShell doesn't rewrite paths.

## Edit on Windows

The Windows compiler typechecks the whole program without running it:

```powershell
..\goose\build\Release\goose.exe --check src\main.goose
```

`--check` and `-o out.c` don't compile the generated C, so the Linux-only C in `shim/` is
no obstacle on Windows.

The Goose VS Code extension checks on save and underlines errors. Its run commands go
through TinyCC without `--include`, so they can't run the program, which calls into
`shim/`. Install it from the checkout:

```powershell
code --install-extension ..\goose\vscode\goose-language.vsix
```

It needs VS Code 1.85 or later. If `code` on PATH belongs to an older install, call the
newer install's `bin\code.cmd` directly. `.vscode/settings.json` points it at the Windows compiler
and stdlib in `../goose` and sets `src/main.goose` as the entry file, so a check of any
file covers the whole program.
