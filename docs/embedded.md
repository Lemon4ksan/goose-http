# Embedded Linux

The package runs on 64-bit ARM Linux boards (aarch64), such as NXP i.MX 8 and i.MX 9.
Every example cross-builds with an aarch64 gcc and passes `scripts/test-examples.sh` on
emulated arm64 (2026-10-14). None has run on a board yet (task 029). 32-bit ARM doesn't
work yet ([below](#32-bit-arm)).

Goose compiles to C, so building for a board means having `goose build` run the board's
C cross compiler. The compiler runs on the build machine, and only the executable goes to
the board.

## Goose or C

A board's program can be written two ways, and both cross-build the same way:

| | [`examples/device`](../examples/device/device.goose) | [`examples/c`](../examples/c/) |
|---|---|---|
| Written in | Goose, with C only for what Goose can't reach | C: one function, `gh_handle`, answers every request |
| The board's hardware | sysfs from Goose (`read_file`, `write_file`); a GPIO `ioctl` in `board.c`, called through `extern fn` | Any C the team already has, called from `gh_handle` |
| What the package gives it | The router, JSON, cookies, forms, files, streaming, Server-Sent Events, and timers | Method, target, header fields, and a body that fits in 8 KB; a status, content type, and body of up to 1 MB back |

Choose Goose for a new program, or when the API needs streaming or Server-Sent Events.
Choose C to put an HTTP API in front of device code that is C already, without writing
Goose. The C handler can't call the package's Goose functions, and runs on every worker
at once, so what it shares must be atomic or locked
([a handler in C](../examples/README.md#a-handler-in-c)). Either way, C's part goes in a
sidecar, `device.build` or `app.build`, which `goose build` compiles with the same cross
compiler as the program.

## What the board needs

- Linux on aarch64 with glibc. musl is untested.
- `liburing.so.2`. The package compiles its io_uring shim on every Linux build, so a
  program links liburing even when it serves with the epoll loop only. On Yocto, add
  liburing to the image (`IMAGE_INSTALL:append = " liburing"`) and to the SDK, from a
  layer that has its recipe.
- Any kernel the board runs. The io_uring loop needs 6.1. On an older kernel,
  `io_uring_setup` refuses the loop's flags, and `http::serve` runs the same loop over an
  emulation on epoll ([Which loop](#which-loop)).
- The GPIO character device (Linux 5.10+), for `examples/device`'s GPIO line only.

## Cross-build

`goose build --cc` takes the names `gcc`, `clang`, and `cc`, or a path, so give a cross
compiler by its path. The runtime and the package's C are built and cached per compiler,
so host and board builds share `GOOSE_HOME` without mixing objects.

### With a distribution's cross compiler

On Debian or Ubuntu, install the cross compiler and arm64 liburing (on Ubuntu, the arm64
packages come from the ports archive; `scripts/test-aarch64.sh` shows the sources), then
build:

```sh
sudo apt-get install gcc-aarch64-linux-gnu liburing-dev:arm64
goose build --cc /usr/bin/aarch64-linux-gnu-gcc -o build/device examples/device/device.goose
file build/device   # ELF 64-bit LSB pie executable, ARM aarch64
```

The result links against the distribution's glibc. A board whose glibc is older than the
build machine's may refuse it; build with the board's own SDK, below.

### With a Yocto SDK

A Yocto SDK's `$CC` is a command with flags, such as `aarch64-poky-linux-gcc
-mcpu=cortex-a53 --sysroot=...`, and `goose build` takes no extra C flags. Put the
command in a wrapper script and give its path:

```sh
. /opt/poky/5.0/environment-setup-cortexa53-crypto-poky-linux
cat > aarch64-cc <<EOF
#!/bin/sh
exec $CC "\$@"
EOF
chmod +x aarch64-cc
goose build --cc "$PWD/aarch64-cc" -o build/device examples/device/device.goose
```

`goose build` runs the wrapper with `--version` and finds gcc in its output, so it
passes gcc's flags. It caches the runtime and the package's C under `GOOSE_HOME` by the
compiler's path and version, so a wrapper rewritten for another SDK with the same gcc
version would reuse the first SDK's objects. Give each SDK a `GOOSE_HOME` of its own,
such as `GOOSE_HOME=$PWD/build/goose-home-imx8 goose build ...`.

### Without the board: emulated arm64

On an x86-64 Linux host with Docker, `scripts/test-aarch64.sh` cross-builds every example
in a container, runs `scripts/test-examples.sh` on the builds in an arm64 container under
emulation, and prints each one's peak RSS. Run it after a change, to catch a break before
a board does:

```sh
GOOSE=../goose/build-linux/goose scripts/test-aarch64.sh
```

The executables stay in `build/aarch64/examples/`. Under emulation, RSS includes about
13,000 kB of the emulator's own per process (task 029), and Docker blocks io_uring, so the io_uring loop runs over its emulation there.

## Which loop

Both loops run on a board, and `examples/device` takes either through `LOOP`:

| `LOOP` | Loop | Use it when |
|---|---|---|
| `uring` (default) | `http::serve`: io_uring on 6.1+, else the same loop over epoll | The kernel is 6.1 or later and throughput matters most |
| `epoll` | `http::serve_epoll` | Memory matters most, or on a kernel before 6.1 |

At start, `examples/device` prints which loop it runs, and when `http::serve` is on the
emulation, why: for example `io_uring_setup: Operation not permitted` where a seccomp
profile blocks it, as Docker's does. On Linux, io_uring serves 12% to 22% faster than
epoll, at 2 to 5 times the peak RSS
([event loops](../examples/README.md#event-loops)).

## Memory and address space

- Run one worker per core, the default. An i.MX 8M has up to four Cortex-A53 cores.
- Idle, `examples/device` with 4 workers peaks at 4,480 kB of RSS on io_uring and
  2,392 kB on epoll. Measured on the benchmark desktop (Ryzen 7 5800X3D), in WSL2 Ubuntu
  26.04 on kernel 6.18.54.1, with the x86-64 build at Goose `46356c2`: one run per loop,
  VmHWM a second after start, before any request. Measure on the board for its own
  numbers ([below](#check-on-the-board)).
- Each data stack reserves 2 GB of address space and commits pages only as they're
  touched. `examples/device` reserves about 14 GiB plus 28 GiB per worker: 126 GiB with 4
  workers. A kernel with 39-bit virtual addresses (512 GiB per process) holds up to 17
  workers. Where the kernel refuses a reservation, the runtime halves it and tries again.
- Strict overcommit (`vm.overcommit_memory=2`) counts reservations as committed memory,
  so the program may not start. Build with a smaller reservation per stack, such as
  `--stack-reserve 64M`, which also caps the largest value a stack holds.
- `examples/c` holds a 1 MB response buffer per worker (`MAX_RESPONSE` in `app.goose`).
  Lower it for a board with little memory.

## Run it on the board

Copy the executable over and start it. Port 8080 needs no root:

```sh
scp build/device root@board:/usr/local/bin/
ssh root@board 'LED=/sys/class/leds/user-led GPIO=/dev/gpiochip0:17 /usr/local/bin/device'
```

`ls /sys/class/leds/` lists the board's LEDs, and `gpioinfo`, from libgpiod, lists the
lines of each chip. Opening a GPIO chip needs root, or a udev rule that gives a group
access to `/dev/gpiochip*`.

To keep it running, a systemd unit:

```ini
# /etc/systemd/system/device.service
[Unit]
Description=Device HTTP API
After=network-online.target

[Service]
ExecStart=/usr/local/bin/device
Environment=LED=/sys/class/leds/user-led GPIO=/dev/gpiochip0:17
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

The server stops gracefully on `SIGTERM`, which `systemctl stop` sends.

## Check on the board

`scripts/test-examples.sh` runs prebuilt examples, so a board with curl can run the same
checks as the emulated run. Cross-build the examples with the board's compiler, copy them
and the script over, and run it there:

```sh
# On the build machine: the examples into build/board/examples.
for dir in examples/*/; do
    name=$(basename "$dir"); src=$dir$name.goose; [ -f "$src" ] || src=${dir}app.goose
    goose build --cc "$PWD/aarch64-cc" --standalone -o "build/board/examples/$name" "$src"
done
mkdir -p build/board/scripts && cp scripts/test-examples.sh build/board/scripts/
scp -r build/board root@board:/tmp/

# On the board: port 8080 must be free.
cd /tmp/board && PREBUILT=1 RSS=1 BIN=/tmp/board/examples sh scripts/test-examples.sh
```

Record the results in task 029 with the board, its kernel (`uname -a`), its
`vm.overcommit_memory`, each example's peak RSS, and the loop line `examples/device`
prints.

## 32-bit ARM

32-bit ARM boards (i.MX 6 and 7, Cortex-A7, STM32MP1) don't run the package yet (task
030). A Goose program without it runs on emulated armv7, but the package's shims declare
the slices they share with Goose unpacked, and Goose packs them: 16 bytes against 12 on
32-bit ARM, so every slice that crosses to the shim arrives garbled.
