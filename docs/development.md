# Development

Building, testing, and benchmarking run on Linux (WSL2 Ubuntu). Windows is for editing:
the native compiler typechecks the program there, but the server only runs on Linux.

## Toolchain

| Tool | Where | Version used (2026-10-10) |
|---|---|---|
| Goose compiler | `../goose`, at the pin in `README.md` | `f084e52` |
| WSL2 Ubuntu | | 26.04.1 LTS, kernel 6.18.40.1-microsoft-standard-WSL2 |
| C compilers | WSL | gcc 15.2.0, clang 21.1.8 |
| CMake, Ninja | WSL, apt | 4.2.3, 1.13.2 |
| Visual Studio Build Tools | Windows | 2026 (18), MSVC 19.51 |
| VS Code | Windows | 1.85 or later, for the Goose extension |
| Python | WSL | 3.14.4, for the test clients |
| curl | WSL, apt | 8.18.0 |
| wrk | WSL, apt | 4.1.0 (`4.1.0-4build3`) |
| h2load | WSL, apt `nghttp2-client` | 1.68.0 |
| oha | WSL, `cargo install oha --locked` | 1.16.0, with cargo 1.99.0 |
| Rust | WSL, rustup | rustc 1.99.0, cargo 1.99.0, for the Rust servers in `bench/` |
| Odin | WSL, `/opt/odin-dev-2026-10` | `dev-2026-10` (`dev-2026-10-nightly:84bc3fc`, LLVM 20.1.8), for odin-http |
| Zig | WSL, `/opt/zig-0.16.0` | 0.16.0, for dusty |
| V | WSL, built by `bench/build.sh` in its cache | 0.5.2 `b99970b`, for vanilla-epoll; needs apt `liburing-dev` (2.14) |
| Docker | WSL, Docker Desktop | 29.8.2, for HttpArena's harness |
| perf | WSL, apt `linux-perf` | 7.0.14 (package `7.0.0-38.38`) |

Install the test tools in WSL. Run `cargo` from a Linux directory
([below](#from-a-windows-shell)); oha lands in `~/.cargo/bin`.

```sh
sudo apt-get install -y curl wrk nghttp2-client netcat-openbsd strace linux-perf
cd ~ && cargo install oha --locked
```

Odin comes from its GitHub release; `bench/build.sh` refuses any other version, because
odin-http follows Odin's master branch:

```sh
curl -sSLf -o /tmp/odin.tgz \
    https://github.com/odin-lang/Odin/releases/download/dev-2026-10/odin-linux-amd64-dev-2026-10.tar.gz
mkdir -p /tmp/odin && tar -xzf /tmp/odin.tgz -C /tmp/odin
sudo mv /tmp/odin/odin-linux-amd64-nightly+2026-10-06 /opt/odin-dev-2026-10
sudo ln -sf /opt/odin-dev-2026-10/odin /usr/local/bin/odin
```

Odin links with clang, which is already installed.

Zig comes from ziglang.org; `bench/build.sh` refuses any other version, because dusty
pins `minimum_zig_version = "0.16.0"` and Zig's standard library changes between
releases. The tarball's SHA-256 is
`70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00`, as
`https://ziglang.org/download/index.json` lists it:

```sh
curl -sSLf -o /tmp/zig.tar.xz https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz
mkdir -p /tmp/zig && tar -xJf /tmp/zig.tar.xz -C /tmp/zig
sudo mv /tmp/zig/zig-x86_64-linux-0.16.0 /opt/zig-0.16.0
sudo ln -sf /opt/zig-0.16.0/zig /usr/local/bin/zig
```

`bench/build.sh` builds V itself, at the commits HttpArena's vanilla-epoll image pins.
vanilla's io_uring module needs liburing's header even in an epoll build:

```sh
sudo apt-get install -y liburing-dev
```

When V fails to compile the C it generated, it downloads a V release and retries with
it, unpinned. A missing `liburing.h` did that once; a build whose output mentions
`v1-fallback` didn't use the pinned V, so fix the cause and rebuild.

## Set up the Goose compiler

The scripts expect a plain Goose checkout next to this repository, at `../goose`. Leave it
on the pinned commit and don't edit it (`AGENTS.md`). On Kait's machine, `../goose-fix`
and `../goose-ngpu` are other Goose checkouts on feature branches: leave them alone. One checkout serves both platforms:
WSL builds into `build-linux/` and Windows into `build/`, and the checkout's `.gitignore`
covers both.

1. Clone the checkout at the pin, with the TinyCC submodule only. TinyCC is what lets
   `goose file.goose` compile and run a program in process; the other submodules are for
   graphics, audio, and physics, which this server doesn't use. The clone calls
   `aardappel/goose` `upstream`, as Kait's checkout does, where `origin` is the fork
   `kaitk/goose`.

   ```sh
   git clone -o upstream https://github.com/aardappel/goose.git ../goose
   git -C ../goose checkout f084e52
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
git -C ../goose fetch upstream
git -C ../goose log --oneline HEAD..upstream/master
git -C ../goose checkout upstream/master
git -C ../goose submodule update third_party/tinycc
```

Then rebuild both compilers (`cmake --build` with the same directories), rerun the
scripts below, and update the pin in `README.md` and the table above.

## Build and run

Run these in WSL. They work from any directory.

| Command | What it does |
|---|---|
| `scripts/build.sh` | Compiles `src/main.goose` to `build/server.c` at `-O2`, then to `build/server` with `cc -O2`. |
| `scripts/test-unit.sh` | Runs each `src/test_*.goose` through TinyCC ([below](#test-the-http-server)). |
| `scripts/test-http.sh` | Tests the HTTP server of `build/server` ([below](#test-the-http-server)). |
| `scripts/test-echo.sh [server]` | Tests the echo servers of `build/server`, or of another command ([below](#test-the-echo-servers)). |
| `bench/build.sh` | Builds the Goose server and the competing servers into `build/bench/` ([below](#benchmark)). |
| `bench/run.sh` | Runs the benchmark matrix against `build/bench/` and writes `bench/results/<date>/` ([below](#benchmark)). |

`build.sh` passes `-D_GNU_SOURCE --include shim/net.h` to goose
([c-interop.md](c-interop.md#where-the-header-goes)). It takes the C compiler from `CC`
(default `cc`, gcc here) and its flags from `CFLAGS` (default `-O2`). The generated C
stays in `build/server.c` for reading. gcc builds a faster server than clang
(task 008).

TinyCC can't place thread-local storage, so it refuses to run any program that can reach
`thread_spawn`, even when the spawn isn't taken. `src/main.goose` is one, so the server
runs only through `build.sh`. The unit tests are root files of their own, which TinyCC
runs.

The program takes a mode and a port (default 8080):

```sh
build/server http 8080            # the HTTP server, one worker per hardware thread
WORKERS=4 build/server http 8080  # with 4 workers
build/server echo-blocking 8080   # the echo servers of task 002: one client at a time
build/server echo-epoll 8080      # one edge-triggered epoll loop
```

### Test the HTTP server

`scripts/test-unit.sh` runs `src/test_http.goose`, which asserts what `src/http.goose`
does with bytes alone: the parser on good, partial, pipelined, and refused requests, the
`Date` header against dates from Python's `email.utils`, and the exact bytes of each
kind of response.

`scripts/test-http.sh` starts `build/server http` with 4 workers (`WORKERS`) and fails on
the first error. It needs curl, wrk, h2load, oha, `nc`, and `python3`
([toolchain](#toolchain)). Against the server it runs:

- curl on `/plaintext`, `/json`, and a 404, and two requests on one connection.
- `scripts/http_client.py`, in these modes:
  - `tfb`: the checks TechEmpower's verifier makes of both tests, with its request
    headers: status, `Server`, `Date` as an IMF-fixdate within 2 s of the clock,
    `Content-Type`, `Content-Length` against the body, the body, and a `Date` that moves
    on after a second.
  - `pipeline`: 16 requests in one write, answered in order; a request sent a byte at a
    time; 5-byte and 512 KB bodies dropped between pipelined requests; and 500
    pipelined requests, more than the write buffer holds.
  - `chunked`: chunked bodies, with an extension and a trailer field, dropped between
    pipelined requests and sent a byte at a time, and HttpArena's `/baseline11` with no
    body, a `Content-Length` body, and a chunked one.
  - `keepalive`: HTTP/1.0 with and without `Connection: keep-alive`, `Connection: close`
    in a pipeline, and `HEAD`.
  - `hostile`: 22 malformed or oversized requests, each refused with its status (400,
    413, 414, 431, 501, or 505) and the connection closed, and a refusal after a good
    request in a pipeline.
  - `many 10000`: 10,000 connections open at once, each pipelining 4 requests.
  - `slow`: at once, a client that trickles a request head (408 after the 10 s request
    timeout), one that sends nothing (closed after 10 s), one that finishes a request
    every 3 s (never cut off), and one that pipelines without reading (closed 10 s after
    the server's buffers fill), while another client is served.
- wrk for 3 s on `/plaintext` with 16-deep pipelining (`scripts/pipeline.lua`) and on
  `/json`, h2load `--h1` for 200,000 requests 16 deep, and oha for 500,000 requests. Each
  must see only 200s and no errors.
- Then one worker under `ulimit -n 40` and 60 clients (`emfile`): the clients past the fd
  limit wait in the listen backlog, and are served once earlier ones close.

The load runs check correctness, not speed; their numbers aren't measurements (task 004).
wrk 4.1.0 times requests with the wall clock, `gettimeofday`, and WSL2 steps its wall clock
back by about a millisecond every 30 s or so. wrk then counts each request in flight
across the step as a timeout, one per connection (64 for `-c 64`), with no slow
response behind them. `test-http.sh` ignores wrk's timeouts for that reason and relies on
h2load and oha, which use a monotonic clock; `bench/run.sh` gives wrk a monotonic clock
instead ([below](#benchmark)). And oha with `-z`
aborts the requests in flight at the deadline and lists them as errors, so the test gives
it a request count instead.

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

### Benchmark

`bench/build.sh` builds the seven servers into `build/bench/`, and `bench/run.sh` runs
the matrix of task 004 against them. [`bench/README.md`](../bench/README.md) has the
method, the pins, and each server's configuration. Both scripts need `GOOSE` and
`$HOME/.cargo/bin` on `PATH`, as above. A full run takes about 20 minutes per server,
140 minutes for all seven, and nothing else should run on the machine meanwhile.

`bench/httparena.sh` runs [HttpArena](https://github.com/MDA2AV/HttpArena)'s own
harness, in Docker, with the Goose server as an entry: `validate` runs its
`scripts/validate.sh`, and `run` its `baseline`, `limited-conn`, `latency-1m`, and
`pipelined` profiles for Goose and HttpArena's tokio, dusty, and vanilla-epoll entries
(task 009). The comment at its top lists what it changes in the checkout.

`bench/compilers.sh` adds Goose builds to `build/bench/`: `goose-gcc`, `goose-clang`,
and `goose-gcc-native` (`-march=native`). `bench/run.sh` runs any server whose name
starts with `goose` as a Goose build, so `SERVERS="goose-gcc goose-clang"` compares
them. `bench/instructions.sh`, as root, counts instructions per request with
`perf stat`, and `bench/parse.sh` times `http::parse` alone on the requests in
`bench/parse/` (task 008).

What the benchmark has to work around on this machine:

- WSL2 steps the wall clock back by 0.4 to 2.6 ms every 30 s (measured with
  `bench/clockstep.py`, 2026-10-10). wrk 4.1.0 counts each request in flight across a
  step as a timeout: 106 and 154 in two 100 s runs at 64 connections. Preloaded with
  `bench/wrk-monotonic.so`, which answers `gettimeofday` from `CLOCK_MONOTONIC`, it
  counted none over the same kind of steps, at the same rate.
- wrk's latency percentiles are wrong under pipelining. wrk 4.1.0 always corrects for
  coordinated omission against each connection's mean request interval, about 13 µs at
  16 deep, and adds synthetic samples below the histogram's minimum, where
  `stats_percentile` doesn't look. p99 then reads `0.00us` whenever a run has an
  outlier. `bench/run.sh` takes latency from h2load's per-request log instead, which it
  times on a monotonic clock, summarized by `bench/latency.c` through a FIFO.
- `mkfifo` fails on `/mnt/c` ("File exists"), so the FIFO goes in a Linux temporary
  directory.
- The load generator needs more CPU than the server. wrk spends about 1.4 times the
  server's CPU time per pipelined request, and h2load more: 6.4 CPUs of system time and
  2.4 of user time at 3.1 million requests per second. With 8 CPUs each, wrk was the bottleneck at 8 workers,
  so `bench/run.sh` gives the server CPUs 0 to 3 and the clients CPUs 4 to 15.
- wrk gives each thread `connections / threads` connections, rounded down, so the thread
  count must divide every connection count. `bench/run.sh` uses 8 threads.
- wrk 4.1.0 drops a `-H` header without a space after its colon: `-H Host:tfb-server`
  sends wrk's own `Host: 127.0.0.1:PORT`, and `-H Connection:keep-alive` sends nothing.
  h2load accepts both spellings and adds `user-agent: h2load nghttp2/1.68.0`. Task 004's
  runs sent only `Host` and `Accept` this way (found in task 008, by tracing the
  server's `recvfrom`); write `-H "Host: tfb-server"`.
- Cargo under `/mnt/c/Users/kait` reads the Windows `~/.cargo/config`, which sets
  `-C target-cpu=native` for every build (see [below](#from-a-windows-shell)).
  `bench/build.sh` runs cargo from its cache directory on the Linux file system, and sets
  the flags it wants itself.
- Docker here is Docker Desktop, whose containers run in its own VM namespace. A
  `--network host` container shares that VM's network with other such containers, but
  WSL can't reach it on `localhost`, and its cgroup isn't under WSL's `/sys/fs/cgroup`.
  `bench/httparena.sh` runs HttpArena's readiness probe and cgroup CPU reads in helper
  containers for that (`bench/httparena/docker-desktop.sh`). `-p 8080:8080` publishing,
  which `validate.sh` uses, does reach WSL.
- gcannon, HttpArena's load generator, peaks at 4 threads on CPUs 4-15 against a
  4-worker server: 466K requests per second on `baseline` for Goose, 248K at 2 threads,
  386K at 6, and 267K at 12 (2026-10-10). More threads lose throughput, one per core
  included, so a thread count from another machine doesn't carry over.
- Zig 0.16 fetches a package's dependencies into `zig-pkg/` beside its `build.zig.zon`,
  and renaming into a `.zig-cache` on `/mnt/c` fails with `AccessDenied`.
  `bench/build.sh` copies `bench/dusty` into the Linux cache and builds it there.
- perf runs on the WSL2 kernel, hardware counters included (`cycles`, `instructions`),
  as root. It can't read `/proc/schedstat`, which `perf record` mentions and survives.
- vanilla-epoll leaks in JSON (`-gc none`): 6-15 GB of RSS per 15 s cell, in a WSL VM
  of 16 GB. A full `bench/run.sh` survived it once, and once (2026-10-11) the host ran
  short of memory in vanilla-epoll's last JSON cell of round 2, and Claude Code stopped
  its background tasks, the run among them. Start a full matrix from a terminal, or
  leave vanilla-epoll's JSON cells out of an unattended one.

### From a Windows shell

The repository lives on the Windows drive, so WSL sees it at
`/mnt/c/Users/kait/projects/goose/goose-http`. These things break commands passed to WSL
from Windows:

- `wsl.exe` hands its arguments to a shell that expands `$VARS` before `bash -c` sees
  them, so a variable set inside the command is empty. Put any command that uses
  variables in a script file and run `wsl.exe -d Ubuntu -- bash /mnt/c/.../script.sh`.
- Git Bash rewrites arguments that look like POSIX paths, so `/mnt/c/...` turns into
  `C:/Program Files/Git/mnt/c/...`. Set `MSYS_NO_PATHCONV=1` for the `wsl.exe` call.
  PowerShell doesn't rewrite paths.
- `GOOSE` isn't set in Kait's WSL profile, and `bash script.sh` wouldn't read the profile
  anyway. A script that calls `scripts/build.sh` or `scripts/test-unit.sh` exports it
  first: `export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose`. The
  same goes for `PATH`, which needs `$HOME/.cargo/bin` for oha.
- A server started in the background survives when its `wsl.exe` call ends early, for
  example when the output is piped into `head`. It keeps its port, and the next run fails
  to bind. Check with `ps aux | grep build/server` before rerunning.
- `wsl.exe` starts in the Windows working directory, under `/mnt/c/Users/kait`, and cargo
  reads the config files of every directory above its own. It then picks up the Windows
  `C:\Users\kait\.cargo\config`. Run cargo with `wsl.exe --cd /root`, or `cd ~` first.
- `pkill -f PATTERN` inside `wsl.exe -- bash -c '...'` matches that `bash -c` too, whose
  command line holds the pattern, and kills it. Kill by PID instead.
- Killing `strace` doesn't stop the server it started; kill the server's PID.

The agent's Bash tool turns `\\` into `\` before the shell sees it, even inside a quoted
heredoc, so `'\\n'` written through it reaches the file as a line break. Edit files with
the file tools, or check the result, when the text has backslashes.

Windows `python`, called from Git Bash, writes text files with CRLF line endings and in
cp1252, so a `§` it writes becomes the byte `0xA7`, which isn't UTF-8. A script that
rewrites files here opens them with `encoding="utf-8", newline="\n"`.
`.gitattributes` keeps `*.sh` and `*.py` at LF in the index, but WSL runs the working
copy, so a CRLF script fails there before Git would fix it.

## Edit on Windows

The Windows compiler typechecks the whole program without running it:

```powershell
..\goose\build\Release\goose.exe --check src\main.goose
..\goose\build\Release\goose.exe --check src\test_http.goose
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
