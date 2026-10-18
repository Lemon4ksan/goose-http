# 041: Move goose-http's tests to Goose's test convention

Status: done (asked for 2026-10-15; done on macOS 2026-10-15, run on Linux and Windows
2026-10-18)

Tests follow Goose's own convention in goose-http, goose-rest, and goose-compress
([decisions](../docs/decisions.md#tests-follow-gooses-convention), 2026-10-15): a
top-level `test/` by area, each test a small program checked by its printed output
against `test/expected/<name>.out`, `// error:` fixtures for code that must not
compile, and a runner that batches the builds with `goose --multi-test` and runs the
tests in parallel. goose-http's tests were `test/test_*.goose` programs and
`server/test_routes.goose`, which `scripts/test.sh` ran by name through
`scripts/test-unit.sh`, plus the examples' requests and expected answers, and the first
failed `assert` ended a program.

As in Goose's own repository, the runner is this repository's own: `test/run_tests.py`,
in Python, modeled on Goose's, with no package or script shared between repositories
(2026-10-15).

## Acceptance criteria

- [x] `test/run_tests.py`, modeled on Goose's: finds `test/**/*.goose`, compiles them
      in batches with `goose --multi-test`, runs each as a process of its own and in
      parallel, at `-O0` and `-O2` where they differ, compares output with
      `test/expected/`, checks `// error:` fixtures fail with their message, and
      reports every failure with a count per area; one way to run a single test or area
- [x] goose-http's tests split into small programs by area (`test/http/`,
      `test/mail/`, `test/store/`, `test/timers/`, `test/compression/`, ...), each
      printing what it checks, with its golden file; the shared helpers in one module
- [x] `// error:` fixtures for what must not compile, where the API refuses misuse at
      compile time
- [x] `scripts/test.sh` calls the runner in place of the programs it runs by name, and
      keeps its other steps (the examples, the client tests, each platform's loops)
- [x] The tests pass on Linux, macOS, and Windows, as `scripts/test.sh` does now
      (macOS: passed 2026-10-15; Linux in WSL2 at `2bf3134e`, and Windows in Git Bash
      with MSVC and clang-cl at `cb66ab09`, passed 2026-10-18)
- [x] `docs/development.md` says how to run the tests, one test, and one area, and how
      to bless a changed golden file

## What was done

The seven programs became 31 tests in seven areas, and four `// error:` fixtures:

| Before | After |
|---|---|
| `test/test_http.goose`, 22 functions | `test/http/`: 14 tests |
| `test/test_api.goose`, 12 functions | `test/api/`: 7 tests |
| `test/test_compression.goose`, 3 functions | `test/compression/`: 2 tests |
| `test/test_store.goose` | `test/store/shared_store.goose` |
| `test/test_timers.goose`, 5 functions | `test/timers/`: 3 tests |
| `test/test_mail.goose`, 6 calls | `test/mail/`: 3 tests, each with its sidecar |
| `server/test_routes.goose` | `test/server/server_routes.goose` |
| none | `test/errors/`: 4 fixtures |

Every check was kept: the new tests hold the same 419 `assert`s, 88 `expect`s, and 64
`same`s as the old (425, 89, and 66, less the helper definitions that moved to
`test/check.goose`), and each other helper call as often.

The runner typechecks in batches with `goose --multi-test --check`, and builds each test
with `goose build`, not through `--multi-test -o` and the C compiler: most tests link the
C that a sidecar names (`http.build`, or a mail test's own), which `goose build`
compiles. A test's `-O0` and `-O2` builds go one after the other, since `goose build`
writes the C of both to the same file under `~/.goose/build/prog/`; in parallel, one
read the other's half-written C (2026-10-15). `goose build` compiles the C at `-O2` at
either Goose level, so the two levels differ in Goose's optimizations alone.

The fixtures check what the API makes `const`: the request and body a handler gets, the
request an `Event` refers to, and a reply's common fields.

## Open

- Run `test/run_tests.py` and `scripts/test.sh` on Linux and on Windows in Git Bash.
  The runner converts a Git Bash `GOOSE` path with `cygpath`, and `.gitattributes` keeps
  the golden files LF.
