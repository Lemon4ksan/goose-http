# 030: 32-bit ARM

Status: in-progress, blocked on two Goose bugs (2026-10-14)

Run the package on 32-bit ARM Linux (armhf: i.MX 6 and 7, Cortex-A7, STM32MP1), which
many embedded boards still are (2026-10-14). Goose itself runs there: a program of
slices, growing arrays, limited arrays, and threads, built with
`arm-linux-gnueabihf-gcc` 15.2 at Goose `46356c2`, runs correctly on emulated armv7.
Every example cross-builds without a C warning, but none runs:

- The shims declared the slices they share with Goose unpacked, 16 bytes on armhf
  against Goose's packed 12, so a slice passed to the shim arrived garbled. Fixed: every
  shared struct is packed, with a `_Static_assert` on its size.
- Every example aborts at start with "a value on main's data stacks grew past the 512
  MB reserved for it". That is an alignment fault, not an overflow: `thread_spawn`
  writes its packet's lengths through misaligned `int64_t` pointers. Past it, the
  compiler lays out slices and references as 64-bit on every target. Both are in
  `docs/goose-findings.md`, neither has a clean workaround here, and neither is
  reported yet: the maintainer decides when.

## Acceptance criteria

- [x] The shims declare every struct they share with Goose packed, with a
      `_Static_assert` on its size for both word sizes
- [ ] The start-up overflow reduced to a minimal program, recorded in
      `docs/goose-findings.md`, and worked around here or reported. Reduced and
      recorded, with the second bug it hides; no clean workaround, and not reported
- [ ] `scripts/test-examples.sh` passes on emulated armv7, from an armhf variant of
      `scripts/test-aarch64.sh`. `scripts/test-armhf.sh` exists and cross-builds every
      example; every example then exits at start, blocked by the two bugs
- [x] `docs/embedded.md` updated for 32-bit

## Shims (2026-10-14)

`shim/*.c`, `examples/c/goose_http.h`, and `examples/device/board.c` declare every
struct they share with Goose under `#pragma pack(push, 1)`, the form MSVC takes too, and
assert each slice's size as `sizeof(void *) + 8`. Each builds with `-O2 -Wall` and no
warning for x86-64 (`gcc`), aarch64, and armhf (`aarch64-linux-gnu-gcc` and
`arm-linux-gnueabihf-gcc`, all 15.2.0 in `ubuntu:26.04`), for macOS (`kqueue.c`,
`ring_epoll.c`, `mail.c`, Apple clang 21.0.0), and for Windows with MinGW-w64's
`x86_64-w64-mingw32-gcc` and `i686-w64-mingw32-gcc` (13-win32). The i686 build checks
the 12-byte slice on a 32-bit Windows target. MSVC itself wasn't run; MinGW reads the
same `#pragma pack`. `scripts/test.sh` passed on macOS after the change.

## Emulated armv7 (2026-10-14)

`scripts/test-armhf.sh` at Goose `46356c2`, with the Linux compiler built in
`ubuntu:26.04` for x86-64 (`docs/development.md`, "ARM under Docker"):
`arm-linux-gnueabihf-gcc` 15.2.0 (`15.2.0-16ubuntu1`) and `liburing-dev:armhf` 2.14 in
`ubuntu:26.04` for amd64, run in `ubuntu:26.04` for arm/v7 under qemu-arm 10.2.3, in
Docker Desktop 29.8.2 (VM kernel 7.0.14-linuxkit, 10 CPUs, 8 GB) on a MacBook Pro
(`MacBookPro18,3`, Apple M1 Pro, macOS 26.3.1). Default worker count, one per CPU: 10.
One run. Every example cross-built. Each was then started on its own, since
`test-examples.sh` stops at the first failure, and each exited at start with the
fault reported as an overflow, before any RSS could be read:

| Example | Peak RSS |
|---|---|
| `hello` | blocked: exits at start, 512 MB per stack of main's |
| `routes` | blocked, as `hello` |
| `api` | blocked, as `hello` |
| `upload` | blocked, as `hello` |
| `later` | blocked, as `hello` |
| `files` | blocked, as `hello` |
| `compress` | blocked, as `hello` |
| `c` | blocked, as `hello` |
| `device`, `LOOP=uring` | blocked: exits at start, 128 MB per stack of main's |
| `device`, `LOOP=epoll` | blocked, as `device` on uring |

How the fault was found: `QEMU_STRACE=1` showed `SIGBUS` with `si_code=1`
(`BUS_ADRALN`) at an odd address in a data stack, and `gdb` through qemu's stub
(`QEMU_GDB`) stopped `hello`, rebuilt from its generated C with `-g`, at `strd r6, r7,
[r3]` on `thread_spawn`'s packet.

`scripts/test-aarch64.sh`, which now runs the same `scripts/test-arm.sh`, passed for
every example on the same Mac, where arm64 runs natively in the VM, so RSS has no
emulator's in it: `hello` 22,512 kB, `routes` 22,540, `api` 22,712, `upload` 22,872,
`later` 25,032, `files` 22,716, `compress` 33,520, `c` 32,784, `device` on uring
22,788 and on epoll 22,696. One run, 10 workers.

Benchmark numbers wait for a board.
