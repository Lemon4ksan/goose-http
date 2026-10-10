# 007: A lean test suite

Status: todo (asked for by Kait, 2026-10-10)

One command that runs every test this repository has, so a pin move or a change to the
server is checked the same way each time. Goose has no unit-test construct; the
compiler's own suite is programs that `assert` and print, compared against expected
output by a runner (`docs/testing.md` in the Goose checkout). This suite does the same,
at a smaller scale.

- Unit tests are Goose programs in `src/`, named `test_*.goose`, that import the modules
  they test and `assert`. They live in `src/` because imports resolve from the root
  file's directory.
- Integration tests are scripts that start the server and talk to it, as
  `scripts/test-echo.sh` does for the echo servers.

## Acceptance criteria

- [ ] `scripts/test.sh` builds the server, runs each `src/test_*.goose` through TinyCC,
      and runs the integration scripts against the gcc build; it fails on the first
      failure
- [ ] The Windows `--check` of every root file, so the Windows typecheck stays green
- [x] Unit tests for the parts of task 003 that work on bytes alone: the request parser,
      the `Date` header, and the response builder (`src/test_http.goose`, run by
      `scripts/test-unit.sh`; task 003 also added `scripts/test-http.sh`)
- [ ] How to run it, and what it covers, recorded in `docs/development.md`
- [ ] The "Move the pin" steps in `docs/development.md` run `scripts/test.sh`
