# Development

Benchmarking runs on Linux (WSL2 Ubuntu), and so do building and testing by default.
macOS builds both loops over kqueue ([below](#macos)), and Windows builds the
io_uring loop over I/O completion ports ([below](#windows)). Platform test coverage is
recorded in the tasks; performance comparisons use
Linux unless a measurement explicitly names another platform.

## Toolchain

| Tool | Where | Version used (2026-10-10) |
|---|---|---|
| Goose compiler | `../goose`, at the pin in `README.md` | `46356c2` (2026-10-13) |
| WSL2 Ubuntu | | 26.04.1 LTS, kernel 6.18.54.1-microsoft-standard-WSL2 (WSL 3.0.3, since 2026-10-13) |
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
| nginx | WSL, apt `nginx`, service disabled | 1.28.3, for `bench/files.sh` |
| Caddy | fetched by `bench/build.sh` | 2.10.2, for `bench/files.sh` |
| ARM cross compilers | `ubuntu:26.04` in Docker, apt (`scripts/test-arm.sh`) | `aarch64-linux-gnu-gcc` and `arm-linux-gnueabihf-gcc` 15.2.0 (`15.2.0-16ubuntu1`), with `liburing-dev` 2.14 for each (2026-10-14) |

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

The scripts run the compiler that `GOOSE` names, or `goose` on `PATH` without it, so the
checkout can live anywhere; this page puts it next to this repository, at `../goose`.
Leave it on the pinned commit and don't edit it (`AGENTS.md`). One checkout serves both
platforms: WSL builds into `build-linux/` and Windows into `build/`, and the checkout's
`.gitignore` covers both.

1. Clone the checkout at the pin. It has no submodules: TinyCC, which lets
   `goose file.goose` compile and run a program in process, is vendored, and graphics,
   audio, and physics are packages the compiler fetches only for a program that imports
   them.

   ```sh
   git clone -o upstream https://github.com/aardappel/goose.git ../goose
   git -C ../goose checkout 46356c2
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
`GOOSE_STDLIB` pointing at the checkout's `stdlib/`; the compiler reads it itself, and
says where it looked when it finds none.

### Move the pin

The Goose repository changes daily. Fetch it at the start of a session, and move the pin
in its own commit once the tests pass:

```sh
git -C ../goose fetch upstream
git -C ../goose log --oneline HEAD..upstream/master
git -C ../goose checkout upstream/master
```

Then rebuild both compilers (`cmake --build` with the same directories), run
`scripts/test.sh` ([below](#run-every-test)) in WSL and in Git Bash, and update the pin in
`README.md`, the table above, and `GOOSE_COMMIT` in `bench/httparena/goose/Dockerfile`,
which builds the HttpArena entry with Goose fetched at that commit.

A pin move doesn't wait for benchmarks. They're costly to run, so they run in batches,
overnight, after a stretch of work (2026-10-13). Until then the results
stand at the commits they name, and the README's Pins table says which ones.

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
file, so gcc can inline the runtime's functions into the server. The
server imports the package from `../`, whose sidecar, `http.build`, names the C in
`shim/` to compile and link for each platform (`shim/net.c` and `shim/uring.c` on Linux,
`shim/kqueue.c` on macOS), and liburing on Linux, for the io_uring loop, which needs
Linux 6.1 ([architecture](architecture/README.md#the-io_uring-loop-task-005)). `goose
build` keeps the generated C under `~/.goose/build/prog/`, and the package's compiled C
under `~/.goose/build/pkg/local/`; `goose build -v` prints the commands with their
paths.

TinyCC can't place thread-local storage, so it refuses to run any program that can reach
`thread_spawn`, even when the spawn isn't taken. Build the server with `goose build`,
as `scripts/build.sh` does. Unit tests without a reachable spawn can run through TinyCC;
the unit-test script builds those that need threads.

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
   each `test/test_*.goose` and `server/test_*.goose`, and the examples listed in
   `scripts/test.sh`.
2. `scripts/test-unit.sh`: each unit test through TinyCC, except one with a `thread_fn`,
   such as `test/test_mail.goose`, which TinyCC can't run: that one is built with
   `goose build` into `build/` and run from there.
3. For each loop, `scripts/build.sh` and then `scripts/test-http.sh`: uring and epoll on
   Linux and macOS, with `LOOP=uring-epoll` against the uring build on Linux too, and
   iocp on Windows.
4. `scripts/test-echo.sh`, against the last build.
5. `scripts/test-examples.sh`: builds the examples and requests their routes on port 8080,
   including the device example with simulated hardware. ARM builds are checked separately.

```sh
GOOSE=../goose/build-linux/goose scripts/test.sh
```

`GOOSE`, `CC`, `PORT`, and `WORKERS` pass through to the scripts it runs. On macOS it
waits for `TIME_WAIT` to drain before each run ([below](#macos)). On Windows, in Git
Bash, its first step is the Windows typecheck that [Edit on Windows](#edit-on-windows)
describes. Git Bash leaves out the load runs and the fd-limit check.

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

- Response bytes, keep-alive, pipelining, request framing, and hostile requests.
- Bodies and responses in pieces, upgrades, waiting answers, files, compression,
  client addresses, and the access log.
- Limits, timeouts, many connections, and graceful stop and restart.
- Load checks and fd exhaustion on platforms that support them.

The script and `scripts/http_client.py` define the individual modes and requests;
use them for the exact coverage. File checks verify that interrupted downloads leave
no file open, and streaming checks bound peak memory on Linux and Windows.

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

### Test on ARM

`scripts/test-aarch64.sh` cross-builds every example for aarch64 and runs
`scripts/test-examples.sh` on the builds in an arm64 container, with each one's peak RSS
([embedded Linux](embedded.md#without-the-board-emulated-arm64)).
`scripts/test-armhf.sh` does the same for 32-bit ARM in an arm/v7 container. Both run
`scripts/test-arm.sh`, which takes the architecture. They need Docker with ARM
emulation, which Docker Desktop has. `test-aarch64.sh` took 53 s in WSL2 and 63 s on the
Mac (2026-10-14). Neither is part of `scripts/test.sh`.

On macOS, the scripts still need a Linux build of the compiler that runs in
`ubuntu:26.04` on x86-64. Build one in Docker from the pinned checkout, mounted read-only,
into this repository's ignored `build/`:

```sh
docker build -q --platform linux/amd64 -t goose-http-goose-build - <<'EOF'
FROM ubuntu:26.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    --no-install-recommends cmake ninja-build g++ >/dev/null
EOF
mkdir -p build/goose-linux
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
    -v "$PWD/../goose:/goose:ro" -v "$PWD/build/goose-linux:/out" goose-http-goose-build \
    sh -c 'cmake -S /goose -B /out -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build /out'
GOOSE=$PWD/build/goose-linux/goose GOOSE_STDLIB=$PWD/../goose/stdlib scripts/test-armhf.sh
```

The build took 1 min 54 s under Docker Desktop's x86-64 emulation on the Mac
(2026-10-14). The compiler finds its stdlib only in the checkout it was built in, so
`GOOSE_STDLIB` names it. Rebuild after moving the pin.

- Docker Desktop on the Mac runs arm64 containers natively in its VM and arm/v7 ones
  under qemu-arm 10.2.3 (Docker Desktop 29.8.2), since the M1 has no 32-bit mode. Its
  arm64 RSS is no emulator's, and doesn't compare with task 029's WSL2 table.
- qemu delivers an alignment fault to the program as `SIGBUS`, where a 32-bit ARM
  kernel may fix up the access ([findings](goose-findings.md#thread_spawn-writes-its-packets-lengths-through-misaligned-int64_t-pointers)).
  `QEMU_STRACE=1` in the container's environment makes qemu print each system call and
  signal, with the fault's address; `QEMU_GDB=1234` makes it wait for `gdb` on that
  port, in the same container.
- Under Docker Desktop's file sharing, git in a container can see a mounted directory
  as another user's and refuse it ("detected dubious ownership"), which stopped the
  fetch of `examples/compress`'s package. `scripts/test-arm.sh` sets `safe.directory`
  through git's environment.

- `goose build --cc` takes the names `gcc`, `clang`, and `cc`, or a path, so a cross
  compiler goes by its path: `--cc /usr/bin/aarch64-linux-gnu-gcc`. A bare
  `aarch64-linux-gnu-gcc` fails with "unknown C compiler name".
- The script runs the Linux build of the compiler inside an `ubuntu:26.04` container,
  which works because WSL's Ubuntu is 26.04 too, with the same glibc (2.43).
- Every Linux program needs `liburing.so.2` at run time, the epoll-only ones included,
  since the package links liburing on Linux. The script's run image installs `liburing2`.
- Docker's seccomp profile blocks io_uring, so `LOOP=uring` runs over the emulation in
  both containers. Run `scripts/test-examples.sh` in WSL itself for real io_uring.
- `kill %1` in a `sh -c` script does nothing, because a non-interactive `sh` has no job
  control, and a `wait` after it waits forever. Kill by `$!`.

### Benchmark

[bench/README.md](../bench/README.md) owns the scripts, server configurations, and
measurement method. [benchmarks.md](benchmarks.md) owns the current comparisons;
[results.md](results.md) links their evidence. Script headers list the settings.
Set `GOOSE` and put `$HOME/.cargo/bin` on `PATH`. Run a benchmark with no competing
work on the machine, and compare only compatible machines, kernels, and settings.

`bench/codegen.sh REV...` compares generated code without serving traffic. It keeps
generated C under `~/goose-http-codegen/` and reports function-family sizes and hot
function instruction counts. Specialization numbers change between builds, so compare
families. Static counts include cold branches; `bench/count.sh` measures executed
user instructions over a fixed request count. Neither substitutes for rate and
memory measurements.

Operational constraints:

- Windows Update can stop WSL distributions and change the kernel. Check each run's
  `env.txt`; do not compare across a kernel change as if only the server changed.
  If Docker Desktop loses its WSL engine, restore WSL integration before running
  HttpArena.
- Run cargo and Zig dependency builds from a Linux filesystem cache. Cargo under
  `/mnt/c` can inherit Windows configuration; Zig package renames there can fail
  with `AccessDenied`. `bench/build.sh` uses its Linux cache.
- wrk rounds connections down to a multiple of its thread count. Give it a thread
  count dividing each cell's connection count. wrk 4.1.0 also needs a space after
  the colon in `-H "Host: tfb-server"`.
- wrk's wall clock can step backward in WSL. The benchmark preloads
  `wrk-monotonic.so`; HTTP load checks rely on monotonic-clock h2load and oha for
  timeouts. With oha, a request count avoids deadline-aborted requests from `-z`.
- Docker Desktop's host network is the Docker VM's, not WSL's loopback. HttpArena's
  readiness probes and cgroup reads use helper containers; published ports reach WSL.
- HttpArena validation can leave its watchdog holding output open until
  `VALIDATE_TIMEOUT` expires. Read output as it arrives instead of piping it to
  `tail`.
- vanilla-epoll's JSON build with `-gc none` leaks enough memory to exhaust the VM.
  Leave those cells out of unattended matrices or isolate them in their own run.
- perf uses the WSL kernel and needs elevated access to hardware counters. A warning
  about `/proc/schedstat` does not by itself mean the recording failed.

### From a Windows shell

Name the WSL distribution explicitly: `wsl.exe -d Ubuntu`. Docker Desktop can change
the default to a distribution with no bash. For commands containing shell variables,
put them in a script and run `wsl.exe -d Ubuntu -- bash /mnt/c/.../script.sh`; the
intermediate shell can otherwise expand variables before bash sees them.

- Git Bash rewrites POSIX-looking arguments. Set `MSYS_NO_PATHCONV=1` for a WSL call;
  PowerShell does not rewrite paths.
- A non-login script does not read the WSL profile. Export `GOOSE` and the oha path
  inside it.
- Run cargo with `cd ~` first, or use WSL's `--cd` option, to avoid inheriting
  configuration from parent directories on the Windows filesystem.
- Keep a long benchmark's foreground WSL call open. A detached run may end when the
  call returns; a background server may instead survive and retain its port.
- Keep a running script unchanged: Bash reads later commands from the file as it
  executes. Editing a benchmark script during its builds caused an unexpected EOF
  before measurement began (2026-10-14). Prepare a separate script for an extension.
- Kill by PID. `pkill -f` inside `bash -c` can match and kill that shell, and killing
  strace does not kill the server it started.
- Windows and WSL git record different file stats. The first WSL diff after Windows
  git can reread the whole checkout, delaying benchmark startup.
- Git for Windows 2.45 writes absolute Windows paths in worktree `.git` files that
  WSL git cannot follow. A relative `gitdir: ../goose-http/.git/worktrees/<name>`
  works for both.

Use the file editing tools for repository changes. Windows Python defaults can write
cp1252 and CRLF; shell heredocs add another escaping layer. See
[line endings on Windows](#line-endings-on-windows).

## macOS

`scripts/build.sh` defaults to the epoll loop over kqueue. `LOOP=uring` builds the
completion loop over its kqueue emulation; the benchmark server includes both loops.
The platform mapping is in [architecture](architecture/README.md#platform-shims-and-error-codes).

| Tool | Version used (2026-10-11) |
|---|---|
| macOS | 26.3.1, Darwin 25.3.0 |
| C compiler | Xcode Apple clang 21.0.0 (`clang-2100.0.123.102`) |
| CMake | Homebrew 4.4.4 |
| Python | Homebrew 3.14.8 |
| curl, nc | macOS curl 8.7.1, Apple's nc |
| wrk | Homebrew 4.2.0 |
| h2load | Homebrew nghttp2 1.70.0 |
| oha | Homebrew 1.16.0 |

```sh
brew install cmake wrk nghttp2 oha
cmake -S ../goose -B ../goose/build-macos -DCMAKE_BUILD_TYPE=Release
cmake --build ../goose/build-macos -j
export GOOSE=$PWD/../goose/build-macos/goose
```

TinyCC finds SDK headers through `xcrun --show-sdk-path`, requiring Xcode or the
Command Line Tools. `goose build --cc gcc` works because macOS's gcc is Apple clang.

- macOS holds closed client ports in `TIME_WAIT` for 30 s. Wait between large client
  runs; `scripts/test.sh` drains between stages. Count remaining sockets with
  `netstat -an -p tcp | grep -c TIME_WAIT`.
- `kern.ipc.somaxconn` defaults to 128, limiting the listen backlog. The tests pass
  there; `sudo sysctl kern.ipc.somaxconn=4096` raises it until reboot.
- `lsof` resolves `/var` and `/tmp` through `/private`. Match resolved paths when
  checking open files.
- The scripts' `ulimit -n 65536` fits the tested per-process fd limit.
- Apple's `nc -N` means keepalive probes, not OpenBSD's shutdown-after-input.
  The echo test checks nc's help and uses `-w 2` otherwise.
- Native loopback comparisons are kernel-limited; see
  [measurement limits](results.md#m1-pro-macos-native). Separate `SO_REUSEPORT`
  listeners can also leave a competing server using only one worker.
- `sample PID 5` profiles without sudo, but includes time blocked in `kevent`.
  `/usr/bin/time -l` reports retired instructions and elapsed cycles, including
  kernel work, after the process exits. It is less precise than fixed-count perf
  comparisons for changes of only a few instructions.

### Linux in Docker on macOS

Use an arm64 Linux image with the Linux toolchain and test tools. Build the Goose
compiler at the [current pin](../README.md#pins), rather than reusing a named image
from a previous session. Test tools include liburing, curl, wrk, nghttp2-client,
netcat-openbsd, python3, and oha. Benchmark builds additionally need the Rust, Zig,
Odin, and autotools versions above, plus util-linux and procps.

- Docker's default seccomp profile blocks native io_uring. Use
  `--security-opt seccomp=unconfined` to test native io_uring; without it, the server
  tests the emulated ring.
- Mount the working tree read-only for builds into a separate output directory, or
  run from an export. Mount results separately when recording benchmark output.
  An exported tree has no git metadata: record the source commit in the run.
- Export uncommitted tracked and untracked files as one archive:
  `git ls-files -co --exclude-standard -z | tar --null -T - -cf - | tar -xf - -C /tmp/work`.
  Passing file lists through xargs can produce several archives; extraction stops
  after the first.
- Transparent huge pages can inflate RSS relative to WSL. Record their setting;
  disabling them with `prctl(PR_SET_THP_DISABLE)` gives measurements with 4 KB pages.
- The VM can hide the CPU part number. `bench/build.sh` selects Zig's `apple_m1`
  rather than a generic arm64 target for this host.
- Tina can require `--security-opt seccomp=unconfined` to map its shard memory.
  Keep its `[FATAL]` lines when inspecting logs.

### Checking the Windows shims compile

With no Windows machine at hand, MinGW-w64 in a container checks that `shim/net_win.c`,
`shim/iocp.c`, and `shim/mail.c` compile, which a change to the Windows shims needs
before a run on Windows:

```sh
docker run --rm -v /tmp/work:/work -w /work ubuntu:26.04 sh -c '
  apt-get update -qq && apt-get install -y -qq gcc-mingw-w64-x86-64 >/dev/null
  for f in net_win iocp mail; do
    x86_64-w64-mingw32-gcc -std=c11 -Wall -Wextra -c shim/$f.c -o /tmp/$f.o
  done'
```

- Two warnings come from code that MSVC builds as intended: MinGW has no
  `SOMAXCONN_HINT` (`shim/net_win.c`), and a sign comparison in `shim/iocp.c`
  (2026-10-12, at `551ee19`).
- It doesn't check MSVC's paths. MinGW's headers lack `winnt.h`'s `ReadAcquire`,
  `ReadNoFence`, `WriteRelease`, and `ReadAcquire64`, which `shim/mail.c`'s atomics use
  under MSVC, so MinGW builds `mail.c`'s C11 atomics. To type-check the MSVC branch,
  compile a file that defines those four with the SDK's signatures, defines
  `_MSC_VER`, and includes `shim/mail.c`.

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
| oha | its `oha-windows-amd64.exe` release, as `%USERPROFILE%\.local\bin\oha.exe` | 1.16.0, for `bench/oha.sh` (`OHA` names it) |

Build the compiler as in [Set up the Goose compiler](#set-up-the-goose-compiler), step 3.
It needs the Visual Studio 2026 Build Tools (`winget install
Microsoft.VisualStudio.BuildTools` with the `Microsoft.VisualStudio.Workload.VCTools`
workload). With only Visual Studio 2022 17.6, MSBuild rejects Goose's C standard:
`Element <LanguageStandard_C> has an invalid value of "stdclatest"` (2026-10-12). Then,
in Git Bash:

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

- Back-to-back runs of `scripts/test.sh` leave thousands of connections to port 29080
  in `TIME_WAIT`, which Windows keeps for 240 s. A run started before they drain fails
  at random with client connect timeouts (`TimeoutError`, `WinError 121`, or
  `WinError 52`), anywhere from `keepalive` to `many` (2026-10-12). Wait until
  `(Get-NetTCPConnection -State TimeWait | Measure-Object).Count` is low again. Windows
  has 16,384 ephemeral ports; changing the server's `PORT` does not replenish them.

- <a id="line-endings-on-windows"></a>Line endings on Windows: with
  `core.autocrlf=true`, `.c`, `.goose`, and `.md` files are CRLF on disk and LF in git,
  while `.gitattributes` keeps `.sh` and `.py` LF. A scripted search and replace that
  assumes LF finds nothing in a CRLF file, and one that writes `\n` turns a whole CRLF
  file into a one-line-per-change diff. `\r`, `\n`, and `\` inside a heredoc pass
  through two rounds of escaping and come out as raw control bytes or literal text. The
  Edit tool keeps each file's endings and needs no escaping, so use it.
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
- The default listener is 127.0.0.1. Explicit IPv4 and IPv6 addresses are supported;
  listening elsewhere can raise a Windows Defender Firewall prompt.
- A connection to a port nothing listens on is refused only after Windows retries for
  about 2 s, so a client with a shorter timeout sees a timeout, not a refusal.
- Python's `os.kill(pid, signal.SIGTERM)` ends a process at once, as `TerminateProcess`
  does. For a graceful stop, start the server with `CREATE_NEW_PROCESS_GROUP` and send
  `signal.CTRL_BREAK_EVENT` to its PID; a path for `subprocess` must be absolute
  (`cygpath -m "$PWD/build/server.exe"`).
- Git Bash's `tar` reads an archive path that starts with a drive letter, such as
  `C:\Users\...\tree.tar` from `$TEMP`, as a remote host, fails with "Cannot connect
  to C: resolve failed", and extracts nothing. Pass `--force-local`, or a `/c/...`
  path.
- The Windows Performance Toolkit of the Windows 10 SDK, 10.0.20348, can't read a trace
  that `wpr` records on Windows 11 10.0.26200: `xperf -a profile` stops with
  `ISession::ProcessEvents [0x80070032]` (2026-10-12). Read it with the current Windows
  Performance Analyzer, from the Microsoft Store.
- `Get-Process`'s CPU times print with the locale's decimal separator, a comma in some
  locales; `bench/oha.sh` formats them with the invariant culture.
- `wpr -start CPU` and `wpr -stop file.etl` need an elevated shell. `wpr -stop` takes a
  minute or more to write the trace; Ctrl+C in that time cancels it with `0x800704c7`
  and discards the recording, and the next `wpr -stop` finds no profile running.
- `cd dir && build/server.exe ... &` puts the whole list in a background subshell, so
  `$!` and its `/proc/$!/winpid` name the subshell, and `taskkill` on that PID leaves the
  server running. Start the server alone with `&`, after the `cd`.

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
and stdlib in `../goose` and sets `server/server.goose` as the entry file, so a check of any
file covers the whole program.
