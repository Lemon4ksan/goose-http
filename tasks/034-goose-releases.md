# 034: Build from Goose releases, then release our own

Status: in-progress (asked for 2026-10-15)

Goose publishes official releases for Windows, Linux, and macOS since `v2026.0`
(2026-10-14). Asked for 2026-10-15: the three repositories build from the pinned release
by default, and pin a Goose commit only when they really need one. goose-http goes first,
then goose-compress and goose-rest. Later, the repositories offer their own packages in
the same way.

goose-http's part (2026-10-15): `scripts/goose.sh` names the release (`v2026.1`) and its
archives' SHA-256 sums. It downloads the archive into `build/`, or uses `GOOSE` or
`GOOSE_COMMIT` when set ([setup](../docs/development.md#get-goose)).
Every script that runs the compiler, `env.txt`, and the HttpArena Dockerfile use it.
`v2026.1` is `46356c2` plus the release packaging and the compiler's lookup of its
stdlib, so benchmark results at `46356c2` still stand. `http.build` excludes `build/`:
without that, the JIT library's symbol table picks up the unpacked release's stdlib
`extern fn`s, and `goose file.goose` fails to link the package on macOS.

## Acceptance criteria

- [x] goose-http builds and tests with the release by default, with `GOOSE` and
      `GOOSE_COMMIT` as overrides: `scripts/test.sh` passed on macOS arm64 with
      `v2026.1`, and with `GOOSE_COMMIT=46356c2…` the compiler built and checked an
      example (2026-10-15).
- [x] The HttpArena image builds from the release; on arm64 Docker, which has no
      release archive, from the release's tag (2026-10-15, Docker Desktop on the Mac).
- [x] `scripts/test.sh` passes with the release in WSL and in Git Bash on Windows:
      `v2026.2`, in WSL2 at `2bf3134e` and in Git Bash with MSVC and clang-cl at
      `cb66ab09` (2026-10-18).
- [ ] goose-compress builds from the pinned release the same way.
- [x] goose-rest builds from the pinned release the same way: its `scripts/goose.sh`
      pins `v2026.2`, and its `scripts/test.sh` passes with it in WSL2 and in Git Bash
      at goose-rest `5e1a4e3` (2026-10-18).
- [ ] Decide what "our own packages" means and record it: release archives built by a
      workflow, as Goose's, or tags that `import ... from "github.com/kaitk/...@vX"`
      already resolves. Then implement it.
