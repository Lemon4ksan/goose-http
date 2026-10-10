# Development

## Toolchain

- **Linux (WSL2 Ubuntu)** for building, testing, and benchmarking. The Goose compiler
  needs a build of its own there: the Windows `goose.exe` can't run in WSL.
- **The Goose compiler** at the pin in `README.md`, built with TinyCC so
  `goose file.goose` compiles and runs in process. Point `GOOSE` at the binary and
  `GOOSE_STDLIB` at the checkout's `stdlib/`. The compiler finds its stdlib by walking up
  from its own binary, so a copied binary needs `GOOSE_STDLIB`.
- **A C compiler**: clang or gcc. Release builds go through generated C
  (`goose -o out.c --standalone`), compiled with `-O2`.
- **Load generators**: `wrk` with a pipelining script for plaintext, as TechEmpower runs
  it, and `wrk` or `oha` for latency without pipelining.
- **Competitors** (task 004): Rust via `cargo`, and Odin via its compiler.

Task 001 turns this into scripts and replaces this section with the commands.
