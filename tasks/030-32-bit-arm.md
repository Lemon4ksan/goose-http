# 030: 32-bit ARM

Status: todo

Run the package on 32-bit ARM Linux (armhf: i.MX 6 and 7, Cortex-A7, STM32MP1), which
many embedded boards still are (2026-10-14). Goose itself runs there: a program of
slices, growing arrays, limited arrays, and threads, built with
`arm-linux-gnueabihf-gcc` 15.2 at Goose `46356c2`, runs correctly on emulated armv7.
Every example cross-builds without a C warning, but none runs:

- The shims declare the slices they share with Goose as `{ uint8_t *data; int64_t len;
  }` unpacked, and the generated C packs the same struct (`sl_u8` under `#pragma
  pack(push, 1)`). Both are 16 bytes on 64-bit targets. On armhf the shim's is 16 and
  Goose's 12, so a slice passed to the shim arrives garbled: `serve_epoll` called from
  `main` fails at `listen` with no error text.
- `examples/hello`, which serves from worker threads, aborts at start with "a value on
  main's data stacks grew past the 512 MB reserved for it", and with `--stack-reserve
  32M` past 32 MB. Not reduced yet. `src/codegen_types.h` lays out references as 8 bytes
  and slices as 16 whatever the target, which may be the cause.

## Acceptance criteria

- [ ] The shims declare every struct they share with Goose packed, with a
      `_Static_assert` on its size for both word sizes
- [ ] The start-up overflow reduced to a minimal program, recorded in
      `docs/goose-findings.md`, and worked around here or reported
- [ ] `scripts/test-examples.sh` passes on emulated armv7, from an armhf variant of
      `scripts/test-aarch64.sh`
- [ ] `docs/embedded.md` updated for 32-bit
