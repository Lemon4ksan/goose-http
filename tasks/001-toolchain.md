# 001: Toolchain and build

Status: todo

Build the pinned Goose compiler on WSL2 Ubuntu with TinyCC, and script building and
running a Goose program from this repository, so later tasks start from one command.

Goose programs already compile from outside the Goose tree: imports resolve from the root
file's directory, then the stdlib, and `--stdlib` or `GOOSE_STDLIB` names the stdlib for
a compiler binary that isn't inside its checkout. There's no install target or package
manager, so the scripts point at a checkout.

## Acceptance criteria

- [ ] The Goose compiler built on WSL2 Ubuntu at the pinned commit, with TinyCC, and the
      steps recorded in `docs/development.md`
- [ ] `scripts/build.sh` compiles `src/main.goose` to `build/server` through generated C
      at `-O2`, taking the compiler from `GOOSE` and the stdlib from `GOOSE_STDLIB`
- [ ] `scripts/run.sh` runs `src/main.goose` through TinyCC, for quick iteration
- [ ] A hello-world `src/main.goose` that imports a module of its own and one from the
      stdlib, built and run both ways
- [ ] The same program compiles to C on Windows with the native `goose.exe`, so editing
      on Windows catches type errors
- [ ] The VS Code extension in the Goose checkout (`vscode/goose-language.vsix`) set up
      for this repository: `goose.compilerPath` and `goose.stdlibPath` in
      `.vscode/settings.json`
