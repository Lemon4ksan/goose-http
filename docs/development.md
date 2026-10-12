# Development

Benchmarking runs on Linux (WSL2 Ubuntu), and so do building and testing by default.
macOS builds both loops over kqueue ([below](#macos)), and Windows builds the
io_uring loop over I/O completion ports ([below](#windows)). Both pass the tests, and
neither is for benchmarks.

## Toolchain

| Tool | Where | Version used (2026-10-10) |
|---|---|---|
| Goose compiler | `../goose`, at the pin in `README.md` | `5c83a5a` (2026-10-12) |
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
| Zig | WSL, `/opt/zig-0.16.0` | 0.16.0, for dusty, zix, and zeemo |
| V | WSL, built by `bench/build.sh` in its cache | 0.5.2 `b99970b`, for vanilla-epoll; needs apt `liburing-dev` (2.14) |
| liburing | WSL, apt `liburing-dev` | 2.14, for the io_uring loop (`LOOP=uring`) |
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

libreactorng builds with autotools:

```sh
sudo apt-get install -y autoconf automake libtool libltdl-dev
```

When V fails to compile the C it generated, it downloads a V release and retries with
it, unpinned. A missing `liburing.h` did that once; a build whose output mentions
`v1-fallback` didn't use the pinned V, so fix the cause and rebuild.

## Set up the Goose compiler

The scripts expect a plain Goose checkout next to this repository, at `../goose`. Leave it
on the pinned commit and don't edit it (`AGENTS.md`). Other Goose checkouts beside it,
such as `../goose-fix` and `../goose-ngpu`, are on feature branches: leave them alone.
`../goose-ngfx` (`kaitk/goose-ngfx`) is a graphics library for Goose, already a package
that programs import from git; it is the reference for how this repository
becomes one (task 011). Its `docs/development.md`, `docs/goose-findings.md`, and
`scripts/run_tests.py` record how its package builds, what Goose's package system got
wrong, and how its tests run. One checkout serves both platforms:
WSL builds into `build-linux/` and Windows into `build/`, and the checkout's `.gitignore`
covers both.

1. Clone the checkout at the pin. It has no submodules: TinyCC, which lets
   `goose file.goose` compile and run a program in process, is vendored, and graphics,
   audio, and physics are packages the compiler fetches only for a program that imports
   them. The clone calls `aardappel/goose` `upstream`, which leaves `origin` for a fork
   such as `kaitk/goose`.

   ```sh
   git clone -o upstream https://github.com/aardappel/goose.git ../goose
   git -C ../goose checkout 5c83a5a
   ```

2. Build the Linux compiler, in WSL:

   ```sh
   sudo apt-get install -y cmake ninja-build
   cd ../goose
   cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release
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
   cmake -S ..\goose -B ..\goose\build -G "Visual Studio 18 2026"
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
```

Then rebuild both compilers (`cmake --build` with the same directories), run
`scripts/test.sh` ([below](#run-every-test)) in WSL and in Git Bash, and update the pin in
`README.md` and the table above.

A checkout from before `6fcb753`, where TinyCC was a submodule, can't check out a later
commit over the submodule's directory. Release it first:
`git -C ../goose submodule deinit -f third_party/tinycc` and
`rm -rf ../goose/third_party/tinycc`. The old configure options `GOOSE_GFX`,
`GOOSE_AUDIO`, `GOOSE_PHYSICS`, and `GOOSE_UI` are gone; CMake warns about them in an old
build directory and ignores them.

## Build and run

Run these in WSL, or on macOS ([below](#macos)). They work from any directory.

| Command | What it does |
|---|---|
| `scripts/build.sh` | Builds the benchmark server into `build/server` with `goose build`, at `-O2` for Goose and gcc: on Linux `server/server.goose`, which serves with the io_uring loop, or with `LOOP=epoll` `server/server_epoll.goose`, which serves with the epoll loop. |
| `scripts/test.sh` | Runs every test, and stops at the first failure ([below](#run-every-test)). |
| `scripts/test-unit.sh` | Runs each `test/test_*.goose` and `server/test_*.goose` through TinyCC ([below](#test-the-http-server)). |
| `scripts/test-http.sh` | Tests the HTTP server of `build/server` ([below](#test-the-http-server)). |
| `scripts/test-echo.sh [server]` | Tests the echo servers of `build/server`, or of another command ([below](#test-the-echo-servers)). |
| `bench/build.sh` | Builds the Goose server and the competing servers into `build/bench/` ([below](#benchmark)). |
| `bench/run.sh` | Runs the benchmark matrix against `build/bench/` and writes `bench/results/<date>/` ([below](#benchmark)). |

`build.sh` runs `goose build --cc gcc --standalone`. gcc builds a faster server than
clang (task 008); `CC` picks another. `--standalone` puts the runtime in the program's C
file, so gcc can inline the runtime's functions into the server, as before task 010. The
server imports the package from `../`, whose sidecar, `http.build`, names the C in
`shim/` to compile and link for each platform (`shim/net.c` and `shim/uring.c` on Linux,
`shim/kqueue.c` on macOS), and liburing on Linux, for the io_uring loop, which needs
Linux 6.1 ([architecture](architecture/README.md#the-io_uring-loop-task-005)). `goose
build` keeps the generated C under `~/.goose/build/prog/`, and the package's compiled C
under `~/.goose/build/pkg/local/`; `goose build -v` prints the commands with their
paths. Before each build, `build.sh` deletes the stamp that marks the package's C as
built: on Linux, `goose build` doesn't see a change to it
([findings](goose-findings.md#goose-build-on-linux-never-sees-a-sidecars-c-change)).

TinyCC can't place thread-local storage, so it refuses to run any program that can reach
`thread_spawn`, even when the spawn isn't taken. The server's root files are such
programs, so the server runs only through `build.sh`. The unit tests are root files of their own, which TinyCC
runs.

The program takes a mode and a port (default 8080):

```sh
build/server http 8080            # the HTTP server, one worker per hardware thread
WORKERS=4 build/server http 8080  # with 4 workers
LOOP=epoll build/server http 8080 # with the epoll loop, whichever root file was built
build/server echo-blocking 8080   # the echo servers of task 002: one client at a time
build/server echo-epoll 8080      # one edge-triggered epoll loop
```

### Run every test

`scripts/test.sh` runs the whole suite, and stops at the first failure:

1. `goose --check` of each root file: `server/server.goose`, `server/server_epoll.goose`,
   and each `test/test_*.goose` and `server/test_*.goose`.
2. `scripts/test-unit.sh`.
3. For each loop, `scripts/build.sh` and then `scripts/test-http.sh`: uring and epoll on
   Linux and macOS, with `LOOP=uring-epoll` against the uring build on Linux too, and
   iocp on Windows.
4. `scripts/test-echo.sh`, against the last build.

```sh
GOOSE=../goose/build-linux/goose scripts/test.sh
```

`GOOSE`, `CC`, `PORT`, and `WORKERS` pass through to the scripts it runs. On macOS it
waits for `TIME_WAIT` to drain before each run ([below](#macos)). On Windows, in Git
Bash, its first step is the Windows typecheck that [Edit on Windows](#edit-on-windows)
describes. It took 2 min 48 s on the Mac of [macOS](#macos), 1 min 37 s in WSL2, and 34 s
in Git Bash, where the load runs are left out (2026-10-11).

### Test the HTTP server

`scripts/test-unit.sh` runs `test/test_http.goose`, which asserts what the package's
`message.goose` does with bytes alone, and `server/test_routes.goose`, the server's
routes: the parser on good, partial, pipelined, and refused requests, the
`Date` header against dates from Python's `email.utils`, and the exact bytes of each
kind of response.

`scripts/test-http.sh` starts `build/server http` with 4 workers (`WORKERS`) and fails on
the first error. It tests whichever loop `build/server` has, so build each loop and run it
once per loop. It needs curl, wrk, h2load, oha, `nc`, and `python3`
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
  - `large`: responses of 5 KB to 300 KB from `/bytes`, alone and pipelined between
    small ones, and 4 MB to a client that reads only after the server's send has
    blocked.
  - `stream`: bodies and responses in pieces (task 013): 100 MB uploads with a
    `Content-Length` and chunked, bodies the handler doesn't read below and past
    `max_drain`, `Expect: 100-continue`, 10 MB echoed with each framing, 10 MB and
    100 MB downloads, a body to HTTP/1.0 that ends at the close, and an `Upgrade` to
    an echo. After it, on Linux, the server's peak RSS must be under 64 MB.
  - `chunked`: chunked bodies, with an extension and a trailer field, dropped between
    pipelined requests and sent a byte at a time, and HttpArena's `/baseline11` with no
    body, a `Content-Length` body, and a chunked one.
  - `keepalive`: HTTP/1.0 with and without `Connection: keep-alive`, `Connection: close`
    in a pipeline, and `HEAD`.
  - `hostile`: 23 malformed or oversized requests, each refused with its status (400,
    413, 414, 431, 501, or 505) and the connection closed, and a refusal after a good
    request in a pipeline.
  - `many 10000`: 10,000 connections open at once, each pipelining 4 requests.
  - `slow`: against a server started again with a 4 s request timeout, 3 s body
    timeout, and 5 s write timeout (`REQUEST_MS`, `BODY_MS`, and `WRITE_MS`, which the
    client reads too), at once: a client that trickles a request head (408 after the
    request timeout), one that sends nothing (closed after it), one whose body stops
    (408 after the body timeout), one that finishes a request every 3 s (never cut
    off), and one that pipelines without reading (closed after the write timeout,
    once the server's buffers fill), while another client is served.
- wrk for 3 s on `/plaintext` with 16-deep pipelining (`scripts/pipeline.lua`) and on
  `/json`, h2load `--h1` for 200,000 requests 16 deep, and oha for 500,000 requests. Each
  must see only 200s and no errors.
- A graceful stop (`stop`): `SIGTERM` with an idle connection, one partway through a
  request head, and one partway through a 20 MB response; and then, with `SERVER_RUNS=2`, a
  stop after which the server's loops start again and serve. On Windows, the same
  checks by Ctrl+Break (`stop-break`), of a server the client starts in a process group
  of its own, since Ctrl+Break reaches only a console process group.
- Then one worker under `ulimit -n 40` and 60 clients (`emfile`): the clients past the fd
  limit wait in the listen backlog, and are served once earlier ones close.

`LOOP=uring-epoll scripts/test-http.sh`, against the `LOOP=uring` build, tests the
io_uring loop over its emulation on epoll, which it falls back to where io_uring is
blocked ([architecture](architecture/README.md#the-io_uring-loop-task-005)). The
fallback itself was tested (2026-10-11) by running the uring build under Docker's
default seccomp profile, with WSL's liburing mounted, and `http_client.py`'s modes from
WSL against it:

```sh
docker run -d --name ghttp -p 29097:29097 -v "$PWD/build/server:/server:ro" \
    -v /usr/lib/x86_64-linux-gnu/liburing.so.2.14:/usr/lib/x86_64-linux-gnu/liburing.so.2:ro \
    -e WORKERS=2 ubuntu:26.04 /server http 29097
python3 scripts/http_client.py 29097 pipeline
```

The io_uring loop's listener outlives its process by a moment: the kernel tears a ring
down after the process exits, and the queued multishot accept holds the listener until
then. `test-http.sh` waits up to 5 s for the port to free before each start.

The load runs check correctness, not speed; their numbers aren't measurements (task 004).
wrk 4.1.0 times requests with the wall clock, `gettimeofday`, and WSL2 steps its wall clock
back by about a millisecond every 30 s or so. wrk then counts each request in flight
across the step as a timeout, one per connection (64 for `-c 64`), with no slow
response behind them. `test-http.sh` ignores wrk's timeouts for that reason and relies on
h2load and oha, which use a monotonic clock; `bench/run.sh` gives wrk a monotonic clock
instead ([below](#benchmark)). And oha with `-z`
aborts the requests in flight at the deadline and lists them as errors, so the test gives
it a request count instead.

### Use the package from git

A program outside the repository imports the package as a user's does, at a pushed
commit, by its full hash: `import http from
"github.com/kaitk/goose-http@<40-hex hash>";`. Git can't fetch an abbreviated hash.
The compiler fetches it into `~/.goose/pkg/github.com/kaitk/goose-http/<12-hex
hash>/`. Check both `goose build` and `goose run`, the second with a program that calls
`http::serve` from `main`: TinyCC can't run one that reaches `thread_spawn`.

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
- `bench/run.sh` writes the host name into `env.txt` unless `MACHINE` is set, and
  results name no machines, so a run on WSL sets `MACHINE=wsl2-5800x3d`.
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
- Cargo under `/mnt/c/Users/<user>` reads the Windows `~/.cargo/config`, which sets
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

The repository lives on the Windows drive, so WSL sees it under `/mnt/c`, for example
at `/mnt/c/Users/<user>/projects/goose/goose-http`. These things break commands passed to WSL
from Windows:

- `wsl.exe` hands its arguments to a shell that expands `$VARS` before `bash -c` sees
  them, so a variable set inside the command is empty. Put any command that uses
  variables in a script file and run `wsl.exe -d Ubuntu -- bash /mnt/c/.../script.sh`.
- Git Bash rewrites arguments that look like POSIX paths, so `/mnt/c/...` turns into
  `C:/Program Files/Git/mnt/c/...`. Set `MSYS_NO_PATHCONV=1` for the `wsl.exe` call.
  PowerShell doesn't rewrite paths.
- `bash script.sh` doesn't read the WSL profile, so a `GOOSE` set there doesn't reach
  it. A script that calls `scripts/build.sh` or `scripts/test-unit.sh` exports it first:
  `export GOOSE=/mnt/c/Users/<user>/projects/goose/goose/build-linux/goose`. The
  same goes for `PATH`, which needs `$HOME/.cargo/bin` for oha.
- A server started in the background survives when its `wsl.exe` call ends early, for
  example when the output is piped into `head`. It keeps its port, and the next run fails
  to bind. Check with `ps aux | grep build/server` before rerunning.
- `wsl.exe` starts in the Windows working directory, under `/mnt/c/Users/<user>`, and
  cargo reads the config files of every directory above its own. It then picks up the
  Windows `C:\Users\<user>\.cargo\config`. Run cargo with `wsl.exe --cd /root`, or `cd ~` first.
- `pkill -f PATTERN` inside `wsl.exe -- bash -c '...'` matches that `bash -c` too, whose
  command line holds the pattern, and kills it. Kill by PID instead.
- Killing `strace` doesn't stop the server it started; kill the server's PID.
- Git for Windows 2.45 writes a worktree's `.git` file with a Windows path, which WSL's
  git can't follow, so `bench/run.sh` can't record the commit there. It has no
  `--relative-paths`; write the file by hand, for example
  `gitdir: ../goose-http/.git/worktrees/goose-http-uring`. Both gits read that.

The agent's Bash tool turns `\\` into `\` before the shell sees it, even inside a quoted
heredoc, so `'\\n'` written through it reaches the file as a line break. Edit files with
the file tools, or check the result, when the text has backslashes.

Windows `python`, called from Git Bash, writes text files with CRLF line endings and in
cp1252, so a `§` it writes becomes the byte `0xA7`, which isn't UTF-8. A script that
rewrites files here opens them with `encoding="utf-8", newline="\n"`.
`.gitattributes` keeps `*.sh` and `*.py` at LF in the index, but WSL runs the working
copy, so a CRLF script fails there before Git would fix it.

## macOS

The epoll loop runs on macOS through `shim/kqueue.c`, which `http.build` lists under
`c_sources_macos`
([architecture](architecture/README.md#the-platform-and-its-error-codes-task-006)), and
`scripts/test-unit.sh`, `scripts/test-http.sh`, and `scripts/test-echo.sh` pass there.
`LOOP=uring scripts/build.sh` builds `http::serve` over `shim/ring_epoll.c`, the
io_uring loop's emulation, on kqueue; both builds hold both loops, and `LOOP` at run
time picks one. Both loops pass the three scripts there, and the emulation holds at the fd
limit without spinning (task 011, 2026-10-11).

| Tool | Where | Version used (2026-10-11) |
|---|---|---|
| macOS | MacBook Pro `MacBookPro18,3`, Apple M1 Pro (8 performance and 2 efficiency cores) | 26.3.1, Darwin 25.3.0 |
| C compiler | Xcode | Apple clang 21.0.0 (`clang-2100.0.123.102`) |
| CMake | Homebrew | 4.4.4 |
| Python | Homebrew | 3.14.8 |
| curl, nc | macOS | curl 8.7.1, Apple's nc |
| wrk | Homebrew | 4.2.0, built on kqueue |
| h2load | Homebrew `nghttp2` | 1.70.0 |
| oha | Homebrew | 1.16.0 |

```sh
brew install cmake wrk nghttp2 oha
```

Build the compiler as on Linux, with the Makefile generator CMake picks by default. The
TinyCC backend finds the SDK's headers through `xcrun --show-sdk-path`, which needs Xcode
or the Command Line Tools. `goose build --cc gcc` works unchanged, because macOS's `gcc`
is Apple clang:

```sh
cmake -S ../goose -B ../goose/build-macos -DCMAKE_BUILD_TYPE=Release
cmake --build ../goose/build-macos -j
export GOOSE=$PWD/../goose/build-macos/goose
```

Then `scripts/build.sh` and the test scripts run as on Linux. On the Mac task 006 used,
`../goose` is a fork on a feature branch, with `../goose-tcc-fix` a worktree of it:
leave both alone. The plain checkout at the pin is `../goose-upstream`, so there
`GOOSE=../goose-upstream/build-macos/goose`.

What differs from Linux:

- macOS has 16,384 ephemeral ports (`net.inet.ip.portrange.first` 49152 to `last`
  65535), against Linux's 28,232, and a closed client socket holds its port in
  `TIME_WAIT` for 30 s (twice `net.inet.tcp.msl`, 15,000 ms). `test-echo.sh` leaves
  12,000 such sockets, and `test-http.sh` started within 30 s of it fails its
  10,000-connection run with `EADDRNOTAVAIL` ("Can't assign requested address"). Wait
  30 s between them; `netstat -an -p tcp | grep -c TIME_WAIT` counts what's left.
- `kern.ipc.somaxconn` is 128, and `listen` cuts the server's backlog of 4,096 to it
  without an error. The tests pass at 128: clients past the backlog retry their `SYN`.
  `sudo sysctl kern.ipc.somaxconn=4096` raises it until the next boot.
- The fd limit's hard maximum is unlimited and `kern.maxfilesperproc` is 122,880, so the
  scripts' `ulimit -n 65536` works without changing a setting.
- Apple's `nc -N` sets a count of keepalive probes, where OpenBSD's shuts down the socket
  after the input ends. `test-echo.sh` passes `-N` only to an `nc` whose help describes
  the shutdown, and relies on `-w 2` otherwise, which makes each echo check 2 s longer.
- Without `WORKERS`, `build/server http` starts one worker per performance core
  (`hw.perflevel0.logicalcpu`, 8 on an M1 Pro), where `hardware_threads()` would count
  the efficiency cores too.

One wrk run of the kqueue build, at commit `ac64ce9`, 2026-10-11, on the machine above:
563,173 requests per second on `/plaintext`, 0.97 ms mean latency, and no errors.

```sh
WORKERS=4 build/server http 29084
wrk -t 4 -c 64 -d 10 -s scripts/pipeline.lua http://127.0.0.1:29084/plaintext -- 16
```

That's 4 server workers and 4 wrk threads, 64 connections pipelining 16 deep, and one
10 s run, with wrk on the same machine and no CPU pinning, at a load average of 2.7.
The number shows that the build carries load, and nothing more: macOS isn't a benchmark
platform (`AGENTS.md`).

`bench/run-macos.sh` runs a short native matrix against the Rust servers that build on
macOS (task 012). Traps found running it, 2026-10-11:

- macOS's loopback carries about 35,000-40,000 request-response exchanges a second in
  all, whatever the server and the client: two independent server and wrk pairs ran at
  36 K alone and 18 K each together, while the machine sat 70% idle and `kernel_task`
  took one core. Every server measures the same there.
- `SO_REUSEPORT` listeners don't spread on macOS, so a competitor that binds one per
  worker, such as the tokio entry, runs on one thread: under load, one of its 4 threads
  used CPU.
- xitca-web enables `io-uring` in `bench/xitca-web/Cargo.toml` and doesn't build on
  macOS; Odin and V aren't installed on the Mac, and Homebrew's Zig is 0.17.0, not the
  0.16.0 `bench/build.sh` requires.
- Other projects' benchmarks and macOS's own indexing (`mediaanalysisd`, `mdworker`)
  share the machine: the load average was 4-10 through the session. `env.txt` records
  it before and after.
- `sample PID 5` profiles a running server without `sudo`. Its counts include time
  blocked in `kevent`; read the rest for where a request's time goes.

### Linux in Docker on macOS

Docker Desktop on macOS runs the Linux build and its tests in an arm64 Linux VM, and both
loops pass there as on WSL. Measured 2026-10-11 on the Mac above, Docker Desktop 29.8.2,
kernel 7.0.14-linuxkit, 10 CPUs and 8 GB for the VM, in `ubuntu:26.04` with gcc 15.2.0,
wrk 4.1.0, h2load 1.68.0, and oha 1.16.0 (its `oha-linux-arm64` release binary). The
image installs what the toolchain table lists for WSL and builds the compiler at the pin:

```dockerfile
FROM ubuntu:26.04
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    ca-certificates git cmake ninja-build gcc g++ liburing-dev curl wrk nghttp2-client \
    netcat-openbsd python3
RUN curl -sSLf -o /usr/local/bin/oha \
        https://github.com/hatoo/oha/releases/download/v1.16.0/oha-linux-arm64 && \
    chmod +x /usr/local/bin/oha
RUN git init -q /goose && cd /goose && \
    git fetch -q --depth 1 https://github.com/aardappel/goose.git efe31554dcce698c0749daec36cd5318d28135fb && \
    git checkout -q FETCH_HEAD && \
    cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-linux
ENV GOOSE=/goose/build-linux/goose
```

Run it on an export of the commit, so the container's `build/` doesn't land in the
working tree:

```sh
git archive HEAD | tar -x -C /tmp/work
docker run --rm --security-opt seccomp=unconfined --ulimit nofile=1048576:1048576 \
    -v /tmp/work:/work -w /work goose-http-linux \
    sh -c 'LOOP=uring scripts/build.sh && scripts/test-http.sh'
```

- Docker's default seccomp profile blocks io_uring: the uring server exited with
  "io_uring: Operation not permitted" before task 011, and runs over an emulation on
  epoll since. `--security-opt seccomp=unconfined` lets it use io_uring.
- `scripts/test-unit.sh`, and `scripts/test-echo.sh` and `scripts/test-http.sh` against
  each loop, passed at commit `090b2e2`, in one full run.
- Before that commit, `test-echo.sh` failed 2 of 10 runs there with "echo-blocking never
  saw EPIPE": the loopback is fast enough that the echo often reaches a cut client
  before its close, which then resets the connection, and the server's send fails with
  `ECONNRESET` instead. The script now repeats the cut rounds until an `EPIPE`, and passed
  10 of 10, 3 of them needing a second or third round.
- `test-http.sh` and `test-unit.sh` weren't executable in Git, which WSL's `/mnt/c`
  hides by showing every file as executable. Commit `e22a9b8` made them executable,
  with `bench/build.sh` and `bench/run.sh`.
- The VM is no benchmark machine: its CPUs are shared with macOS, and the load runs share
  them with the server.

To run `bench/run.sh` there (task 012), the image also needs Rust, Zig 0.16.0, and Odin
`dev-2026-10` for the servers, the tools libreactorng's build uses, `util-linux` and
`procps` for `taskset`, `lscpu`, and `/proc`, and oha for `test-http.sh`. On 2026-10-11:

```dockerfile
FROM ubuntu:26.04
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    ca-certificates git cmake ninja-build gcc g++ liburing-dev curl wrk nghttp2-client \
    netcat-openbsd python3 util-linux procps pkg-config make xz-utils \
    autoconf automake libtool libltdl-dev clang lld llvm
RUN curl -sSLf -o /usr/local/bin/oha \
        https://github.com/hatoo/oha/releases/download/v1.16.0/oha-linux-arm64 && \
    chmod +x /usr/local/bin/oha
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal --default-toolchain 1.99.0
ENV PATH=/root/.cargo/bin:/opt/zig:/opt/odin:$PATH
RUN mkdir -p /opt/zig && curl -sSLf https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz | \
    tar -xJ -C /opt/zig --strip-components 1
RUN mkdir -p /opt/odin && \
    curl -sSLf https://github.com/odin-lang/Odin/releases/download/dev-2026-10/odin-linux-arm64-dev-2026-10.tar.gz | \
    tar -xz -C /opt/odin --strip-components 1
RUN git init -q /goose && cd /goose && \
    git fetch -q --depth 1 https://github.com/aardappel/goose.git efe31554dcce698c0749daec36cd5318d28135fb && \
    git checkout -q FETCH_HEAD && \
    cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-linux
ENV GOOSE=/goose/build-linux/goose
```

Odin's linux-arm64 release links with clang. In the container, `CACHE=/cache
bench/build.sh` builds the whole field for arm64, with a Docker volume at `/cache` so the
next container reuses cargo's target directories, V, and the checkouts; `bench/README.md`
lists what differs from the x86-64 builds. Then, with the layout of task 012's runs:

```sh
MACHINE=m1pro-docker SERVERS="goose goose-uring tokio vanilla-epoll vanilla-io_uring \
    may-minihttp hyper xitca-web odin-http dusty zix zeemo libreactorng" \
    WORKER_COUNTS=3 SERVER_CPUS=0-2 CLIENT_CPUS=3-9 CLIENT_THREADS=8 CACHE=/cache bench/run.sh
```

- Mount the working tree to write results into `bench/results/`, and run from a copy of
  its tracked files in the container. `env.txt` then shows the commit as "(modified)":
  record it by hand.
- The VM runs transparent huge pages set to `always`. An idle Goose server with 4 workers
  holds 22 MB, 20 MB of it in `AnonHugePages`, so peak RSS there doesn't compare with
  WSL2's.
- With 4 workers and wrk on 6 of the 10 CPUs, wrk used 51-58 of its 60 CPU seconds per
  10 s run in the fastest servers' cells. With 3 workers and wrk on 7 CPUs, wrk used
  60-65 of 70 in plaintext and 49-53 in JSON, where the servers used all of theirs.
- The VM hides the CPU's part number (`CPU part : 0x000` in `/proc/cpuinfo`), so Zig's
  `-Dcpu=native` builds for generic arm64; `bench/build.sh` names `apple_m1` instead.
- vanilla-epoll's JSON cells grow its memory by 6-15 GB each, past the VM's 8 GB: run
  JSON without it, in its own result directory.
- `goose build` on Linux reuses a program's compiled shim after the first build
  (`docs/goose-findings.md`). `scripts/build.sh` works around it; a hand-run `goose
  build` needs the shim's `stamp` under `~/.goose/build/pkg/local/` deleted first.

### HttpArena under Docker on macOS

`bench/httparena.sh` drives HttpArena's harness, which needs bash 4, GNU `stat` and
`timeout`, and `nproc`; macOS has bash 3.2 and none of the rest. Run it in a Linux
container that talks to Docker Desktop through its socket, with the cache and the working
tree mounted at the same paths as on the Mac, so the paths the harness passes to `docker
run -v` resolve on the Mac. `--network host` puts the container on the VM's host network,
where the servers listen, and its `nproc` is the VM's 10 CPUs, which the harness reads
for its CPU limits. The image, 2026-10-11:

```dockerfile
FROM docker:29.8.2-cli AS cli
FROM ubuntu:26.04
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    bash ca-certificates curl git jq python3 openssl util-linux procps bc
COPY --from=cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
```

```sh
docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME/.cache/goose-http-bench:$HOME/.cache/goose-http-bench" -v "$PWD:$PWD" \
    -e HOME="$HOME" -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
    -e GIT_CONFIG_VALUE_0='*' -e SERVER_CPUS=0-2 -e LOAD_CPUS=3-9 -e MACHINE=m1pro-docker \
    -w "$PWD" goose-http-arena bench/httparena.sh run
```

- The buildx plugin is needed: without it, `docker build` doesn't set `TARGETARCH`,
  and dusty's Dockerfile then builds for x86-64.
- The safe.directory setting lets the container's git read a working tree owned by
  another user.
- HttpArena's zrk image downloads an x86-64 binary, and its vanilla-epoll image pins
  tccbin's x86-64 branch, whose `libgc.a` V's bootstrap links. On an arm64 Docker host,
  `bench/httparena.sh` swaps in zrk's aarch64 release and tccbin's arm64 branch.

## Windows

The io_uring loop runs natively on Windows through `shim/iocp.c` and `shim/net_win.c`,
which `http.build` lists under `c_sources_windows`
([architecture](architecture/README.md#the-platform-and-its-error-codes-task-006)), and
`scripts/test-unit.sh`, `scripts/test-http.sh`, and `scripts/test-echo.sh` pass there,
in Git Bash. The epoll loop doesn't build on Windows. Windows isn't for benchmarks.

| Tool | Where | Version used (2026-10-11) |
|---|---|---|
| Windows | Windows 11 Pro 25H2, Ryzen 7 5800X3D | 10.0.26200 |
| C compiler | Visual Studio Build Tools | MSVC 19.51; clang-cl works too |
| Shell, curl | Git for Windows | Git Bash 5.2.26, mingw curl 8.7.1 |
| Python | on `PATH` as `python3` | 3.14.6 |

Build the compiler as in [Set up the Goose compiler](#set-up-the-goose-compiler), step 3.
Then, in Git Bash:

```sh
export GOOSE=$PWD/../goose/build/Release/goose.exe
scripts/build.sh                 # LOOP=iocp, CC=msvc: build/server.exe
nice -n 19 scripts/test-unit.sh
nice -n 19 scripts/test-http.sh
nice -n 19 scripts/test-echo.sh
```

`goose toolchain` shows the C compilers `goose build` finds; `CC=clang-cl` picks
clang-cl. `test-http.sh` leaves out the load runs and `emfile` on Windows, and
`test-echo.sh` runs only echo-blocking, without nc ([task
006.02](../tasks/006-kqueue-iocp/02-iocp-windows.md#tests)).

Traps in Git Bash:

- `nice -n 19` starts a native program in the Idle priority class, which keeps a test
  run from slowing other work on the machine.
- A Linux build in the same tree leaves an ELF `build/server` beside `build/server.exe`,
  and Git Bash runs `build/server` first, which fails with "Exec format error". The test
  scripts name `build/server.exe` on Windows; do the same by hand.
- `ulimit -n` fails, and wouldn't reach a native program anyway.
- Git Bash's `kill` doesn't always end a native program. The test scripts end the server
  with `taskkill //F //PID` and the Windows process ID from `/proc/$pid/winpid`.
- MSYS rewrites arguments that look like paths, so `cmd /c` becomes `cmd C:/`. Run it
  with `MSYS2_ARG_CONV_EXCL='*'`. Writing `//c` with path conversion turned off
  (`MSYS_NO_PATHCONV=1`) passes `//c` through, and leaves `cmd` waiting for input.
- The server listens on 127.0.0.1 only. Any other address raises a Windows Defender
  Firewall prompt.
- A connection to a port nothing listens on is refused only after Windows retries for
  about 2 s, so a client with a shorter timeout sees a timeout, not a refusal.
- Python's `os.kill(pid, signal.SIGTERM)` ends a process at once, as `TerminateProcess`
  does. For a graceful stop, start the server with `CREATE_NEW_PROCESS_GROUP` and send
  `signal.CTRL_BREAK_EVENT` to its PID; a path for `subprocess` must be absolute
  (`cygpath -m "$PWD/build/server.exe"`).
- Windows has 16,384 ephemeral ports (49152 to 65535), and `test-http.sh` leaves about
  11,000 client sockets in `TIME_WAIT`. A second run started within a couple of minutes
  fails in `many 10000` with `OSError: [WinError 52] You were not connected because a
  duplicate name exists on the network`, which is running out of ports (2026-10-11).
  Wait until `netstat -an | grep -c TIME_WAIT` is down to a few thousand.
- Git Bash's `tar` reads an archive path that starts with a drive letter, such as
  `C:\Users\...\tree.tar` from `$TEMP`, as a remote host, fails with "Cannot connect
  to C: resolve failed", and extracts nothing. Pass `--force-local`, or a `/c/...`
  path.
- `cd dir && build/server.exe ... &` puts the whole list in a background subshell, so
  `$!` and its `/proc/$!/winpid` name the subshell, and `taskkill` on that PID leaves the
  server running. Start the server alone with `&`, after the `cd`.

### Against WSL

A speed check, not a benchmark (2026-10-11): is the IOCP build in the ballpark of the
same loop on io_uring in WSL2, on the same machine? It is, about 2.2 to 2.8 times
slower, not an order of magnitude.

- Both sides ran the code of `2d61b55`: the Windows build by MSVC 19.51
  (`scripts/build.sh`), and the WSL2 build `goose-uring` by gcc 15.2.0
  (`bench/build.sh`), WSL2 kernel 6.18.40.1.
- The load generator was oha 1.16.0 on both: its `oha-windows-amd64.exe` release on
  Windows, and `cargo install oha` in WSL2. `oha -n 2000000 -c 256 --no-tui
  http://127.0.0.1:29380/plaintext`: 256 connections, 2,000,000 requests, not pipelined,
  since oha can't pipeline. Nothing was pinned to CPUs, and nothing else ran.
- `WORKERS=4 build/server.exe http 29380` on Windows, and `LOOP=uring WORKERS=4
  build/bench/goose-uring http 29380` in WSL2.

| Server | Workers | Runs | Requests per second |
|---|---:|---:|---:|
| Windows, IOCP | 4 | 3 | 217,526-231,707 |
| WSL2, io_uring | 4 | 3 | 629,992-646,977 |
| WSL2, epoll (`LOOP=epoll`) | 4 | 3 | 543,578-550,226 |
| Windows, IOCP | 1 | 2 | 78,065-78,079 |
| WSL2, io_uring | 1 | 2 | 174,910-176,395 |

Every request succeeded. Windows trails by 2.2 times with 1 worker and 2.8 times with
4. The client shares the CPUs with the server on both sides, so the numbers bound the
server only loosely.

#### After the IOCP changes

`82d2939` (2026-10-11) skips the completion port when a request completes at once, and
receives into the ring's buffers while more than half are free
([architecture](architecture/README.md#the-platform-and-its-error-codes-task-006)).
Both sides at `82d2939`, as above, except that the WSL2 build is `LOOP=uring
scripts/build.sh`'s. The CPU columns are the server's busy threads, from
`Get-Process`'s `UserProcessorTime` and `PrivilegedProcessorTime` read as oha ends:

| Server | Workers | Runs | Requests per second | CPU per request, user/kernel |
|---|---:|---:|---:|---|
| Windows, IOCP, `5778aaa` | 1 | 4 | 78,071-78,348 | 0.8/12.0 µs |
| Windows, IOCP | 1 | 2 | 83,106-84,435 | 0.8-0.9/11.0-11.2 µs |
| WSL2, io_uring | 1 | 2 | 171,837-172,415 | |
| Windows, IOCP, `5778aaa` | 4 | 3 | 229,124-234,017 | |
| Windows, IOCP | 4 | 3 | 247,647-253,850 | |
| Windows, IOCP, pinned | 4 | 3 | 255,762-263,177 | |
| WSL2, io_uring | 4 | 3 | 614,953-634,554 | |
| WSL2, epoll | 4 | 3 | 537,191-546,550 | |
| Windows, tokio | 1 | 2 | 61,292-62,362 | 1.6-1.7/14.3-14.5 µs |

- Windows now trails by 2.0 times with 1 worker and 2.5 times with 4, from 2.2 and 2.8.
  The changes gained 7% and 9% over `5778aaa`, the commit before them; skipping the
  port was most of it (7% and 5% alone).
- Nearly all of a request's time on Windows is the kernel's. Receiving into a buffer
  saves a `recv` per request and gained 0-2%, so the system calls aren't the cost: the
  loopback TCP path is. A kernel profile, which takes an elevated shell for WPR, would
  say where it goes.
- HttpArena's tokio entry, built with Rust 1.90.0 for Windows and bound to 127.0.0.1
  without `SO_REUSEPORT`, which Windows lacks, serves 26% less than Goose with 1 worker,
  at more kernel time per request. It can't run 4 workers there: its second bind fails.
- With 4 workers, every worker was busy for the whole run, at 7.1-7.5 s of kernel time
  each, so connections spread; the 4 workers serve 3.0 times what 1 does, against 3.6
  times in WSL2. Pinning the server to CPUs 0, 2, 4, and 6 and oha to 8-15
  (`ProcessorAffinity` 0x55 and 0xFF00) gained 3%.

## Edit on Windows

The Windows compiler typechecks the whole program without running it:

```powershell
..\goose\build\Release\goose.exe --check server\server.goose
..\goose\build\Release\goose.exe --check test\test_http.goose
```

`--check` and `-o out.c` don't compile the generated C, so the Linux-only C in `shim/` is
no obstacle on Windows.

The Goose VS Code extension checks on save and underlines errors. Its run commands go
through TinyCC, which can't run the server ([above](#build-and-run)). Install it from the checkout:

```powershell
code --install-extension ..\goose\vscode\goose-language.vsix
```

It needs VS Code 1.85 or later. If `code` on PATH belongs to an older install, call the
newer install's `bin\code.cmd` directly. `.vscode/settings.json` points it at the Windows compiler
and stdlib in `../goose` and sets `src/main.goose` as the entry file, so a check of any
file covers the whole program.
