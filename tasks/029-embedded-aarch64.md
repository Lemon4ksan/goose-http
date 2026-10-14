# 029: Embedded Linux on aarch64

Status: in-progress

Make the package usable on 64-bit ARM embedded Linux boards, such as NXP i.MX 8, so a
team with one can try it (2026-10-14): a guide to cross-building and running, an
example of a device's HTTP API, and a script that cross-builds the examples and runs
them on emulated arm64. Benchmarks wait until there is a board to run them on. 32-bit
ARM is task 030.

## Acceptance criteria

- [x] `goose build --cc /usr/bin/aarch64-linux-gnu-gcc` builds `examples/hello` and
      `examples/c` for aarch64, and both answer their routes on emulated arm64
- [x] `examples/device/`: temperature and an LED from sysfs in Goose, a GPIO line
      through `board.c`, temperature as Server-Sent Events, and either loop by `LOOP`;
      in `scripts/test-examples.sh`
- [x] `scripts/test-aarch64.sh`: cross-builds the examples in Docker, runs them on
      emulated arm64, and prints each one's peak RSS
- [x] `docs/embedded.md`: cross-building with a distribution's cross compiler and with
      a Yocto SDK, what the board needs, which loop, memory and address space, and a
      check to run on the board
- [ ] Yocto SDK wrapper tried with a real SDK
- [ ] Tried on an i.MX 8 board, with its numbers recorded here

## Emulated arm64 (2026-10-14)

`scripts/test-aarch64.sh` at Goose `46356c2`: aarch64-linux-gnu-gcc 15.2.0 in
`ubuntu:26.04`, run in `ubuntu:26.04` for arm64 under Docker Desktop 29.8.2's qemu, in
WSL2 Ubuntu 26.04 (kernel 6.18.54.1) on the benchmark desktop (Ryzen 7 5800X3D, 16
logical CPUs), so 16 workers each. One run. `test-examples.sh` passed for every
example. Peak RSS is VmHWM at the end of each example's checks, in `/proc`'s kB. It
includes about 13,000 kB of qemu's own: the same `hello` built for x86-64 and run
natively peaks at 3,084 kB.

| Example | Peak RSS |
|---|---|
| `hello` | 16,080 kB |
| `routes` | 15,980 kB |
| `api` | 16,100 kB |
| `upload` | 16,680 kB |
| `later` | 18,100 kB |
| `files` | 16,156 kB |
| `c` | 32,368 kB, of which 16 MB is its 1 MB response buffer per worker |
| `device`, `LOOP=uring` (emulated ring: Docker blocks io_uring) | 16,556 kB |
| `device`, `LOOP=epoll` | 16,040 kB |
