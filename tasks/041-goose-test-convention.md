# 041: Move goose-http's tests to Goose's test convention

Status: todo (asked for 2026-10-15)

Tests follow Goose's own convention in goose-http, goose-rest, and goose-compress
([decisions](../docs/decisions.md#tests-follow-gooses-convention), 2026-10-15): a
top-level `test/` by area, each test a small program checked by its printed output
against `test/expected/<name>.out`, `// error:` fixtures for code that must not
compile, and a runner that batches the builds with `goose --multi-test` and runs the
tests in parallel. goose-http's tests today are `test/test_*.goose` programs that
`scripts/test.sh` runs by name, plus the examples' requests and expected answers, and
the first failed `assert` ends a program.

As in Goose's own repository, the runner is this repository's own: `test/run_tests.py`,
in Python, modeled on Goose's, with no package or script shared between repositories
(2026-10-15).

## Acceptance criteria

- [ ] `test/run_tests.py`, modeled on Goose's: finds `test/**/*.goose`, compiles them
      in batches with `goose --multi-test`, runs each as a process of its own and in
      parallel, at `-O0` and `-O2` where they differ, compares output with
      `test/expected/`, checks `// error:` fixtures fail with their message, and
      reports every failure with a count per area; one way to run a single test or area
- [ ] goose-http's tests split into small programs by area (`test/http/`,
      `test/mail/`, `test/store/`, `test/timers/`, `test/compression/`, ...), each
      printing what it checks, with its golden file; the shared helpers in one module
- [ ] `// error:` fixtures for what must not compile, where the API refuses misuse at
      compile time
- [ ] `scripts/test.sh` calls the runner in place of the programs it runs by name, and
      keeps its other steps (the examples, the client tests, each platform's loops)
- [ ] The tests pass on Linux, macOS, and Windows, as `scripts/test.sh` does now
- [ ] `docs/development.md` says how to run the tests, one test, and one area, and how
      to bless a changed golden file
