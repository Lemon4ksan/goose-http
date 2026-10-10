# 008: Clang and simd functions

Status: todo

Move the Goose pin to upstream (`aardappel/goose`), which adds `simd fn` (spec §7.12) and
`stdlib/base64.goose` as a model of its use, and build the server with clang. The C
backend honors `simd` only under clang on x86-64, and the Goose README reports clang's
code as faster. The Rust servers in `bench/` build with `-C target-cpu=native`; `simd`
lets the Goose server use AVX2 where the CPU has it, without tying the binary to one CPU.

`simd` versions a whole function and keeps it out of line, with a CPU test per call, so
it goes on `parse`, which runs once per request and holds the header loops, not on the
helpers called inside them. The C compiler vectorizes loops without early exits, as in
`base64.goose`; the header value scan stops at the first byte that ends a value, so it
needs a fixed-size inner block that flags such bytes, with the break in the outer loop.

## Acceptance criteria

- [ ] `../goose` follows upstream, the pin is moved ("Move the pin" in
      `docs/development.md`), and `scripts/test-http.sh` and the unit tests pass at it
- [ ] `scripts/build.sh` builds with clang, its version is in `docs/development.md`, and
      the gcc build stays possible for comparison
- [ ] The header value scan is shaped so the C compiler vectorizes it, with every access
      still proven in bounds (`--bce-lines`), and `parse` is a `simd fn`
- [ ] Instructions per request (`perf stat`) and requests per second at 1 and 4 workers
      are recorded for gcc, clang, and clang with `simd`, with how they were measured
- [ ] Anything the compiler rejects or miscompiles is in `docs/goose-findings.md`
