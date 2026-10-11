# 007: A lean test suite

Status: in-progress (asked for 2026-10-10)

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

## Http11Probe (2026-10-11)

Http11Probe `c5ee0b1` (215 tests), its CLI run in the `mcr.microsoft.com/dotnet/sdk:10.0`
container against `http::serve_epoll` on the Mac of `docs/development.md`, with 1 worker,
through `host.docker.internal`. The probe expects `GET /` to answer 200 and `POST /` to
echo its body, which the benchmark server's routes don't, so the target was a program
that imports the package and does only that:

```goose
http::serve_epoll(http::Config { port: 8080, workers: 1, .. }) { req, body, out =>
    if req.method == "POST" { http::respond(out, 200, "text/plain", body); }
    else { http::respond(out, 200, "text/plain", "OK"); }
}
```

```sh
docker run --rm -v "$PROBE:/src" -w /src mcr.microsoft.com/dotnet/sdk:10.0 \
    dotnet run -c Release --project src/Http11Probe.Cli -- --host host.docker.internal --port 8080
```

At `782bbb7`, 141 of 159 scored tests passed. At `6f367cb`, 155 of 157 did, with 17
warnings and 2 errors (below). Each failure:

- Fixed in `b73d527`: a `Host` with userinfo, a path, or a comma-separated second host
  is 400 (`COMP-HOST-WITH-USERINFO`, `COMP-HOST-WITH-PATH`, `SMUG-MULTIPLE-HOST-COMMA`);
  `GET *` and `CONNECT` are 400, and `OPTIONS *` reaches the handler
  (`COMP-ASTERISK-WITH-GET`, `COMP-METHOD-CONNECT`, `COMP-OPTIONS-STAR`); request lines
  of 8,000 octets are taken (`COMP-LONG-URL-OK`); a chunk extension that isn't a token
  with an optional value is 400 (`SMUG-CHUNK-BARE-SEMICOLON`,
  `SMUG-CHUNK-EXT-INVALID-TOKEN`); and `http::path_of` gives absolute-form's path
  (`COMP-ABSOLUTE-FORM`, unscored).
- Fixed in `6f367cb`: a `Transfer-Encoding` whose last coding isn't chunked, with chunked
  twice, or with an empty value or element is 400, as RFC 9112 §6.3 requires, where
  any coding but chunked was 501 (`SMUG-TE-DOUBLE-CHUNKED`, `SMUG-TE-NOT-FINAL-CHUNKED`,
  `SMUG-TE-EMPTY-VALUE`, `SMUG-TE-LEADING-COMMA`, `SMUG-TE-DUPLICATE-HEADERS`,
  `SMUG-TE-OBS-FOLD`, `SMUG-TE-TRAILING-COMMA`, and `SMUG-CHUNKED-WITH-PARAMS`,
  unscored). Other codings before chunked are still 501.
- Refused deliberately:
  - An empty `Host` gets 200 (`COMP-HOST-EMPTY-VALUE`): RFC 9112 §3.2 has a client
    send one for a URI without an authority, and task 013 keeps it.
  - A chunked body with a 64 KB extension gets 413 (`MAL-CHUNK-EXT-64K`): a chunked
    message must fit in the read buffer with its head (task 009).
  - The cookie tests (`COOK-ECHO`, `COOK-PARSED-BASIC`, `COOK-PARSED-MULTI`, unscored)
    need a handler that reads request fields, which `v0.1.0` doesn't have (task 013,
    item 6).

Two of four full runs had two connects time out after 5 s, each in different tests
(`COOK-NUL` and `WS-UPGRADE-HTTP10`, then `SMUG-CLTE-SMUGGLED-GET-CL-NON-NUMERIC` and
`SMUG-DUPLICATE-CL-SMUGGLED-GET`), which passed alone. On the Mac itself, 3,000
connections in a row to the same server, with 300 more held open mid-request, each
connected within 3 ms. The timeouts look like Docker Desktop's forwarding of
`host.docker.internal`, not the server; a run from a native .NET install would settle
it.

## Acceptance criteria

- [x] `scripts/test.sh` builds the server, runs each `src/test_*.goose` through TinyCC,
      and runs the integration scripts against the gcc build; it fails on the first
      failure (2026-10-11, run on macOS; not yet on Linux)
- [ ] The Windows `--check` of every root file, so the Windows typecheck stays green
      (`scripts/test.sh` runs it in Git Bash, 2026-10-11; not yet run on Windows)
- [x] Unit tests for the parts of task 003 that work on bytes alone: the request parser,
      the `Date` header, and the response builder (`src/test_http.goose`, run by
      `scripts/test-unit.sh`; task 003 also added `scripts/test-http.sh`)
- [ ] [Http11Probe](https://mda2av.github.io/Http11Probe/), HttpArena's RFC 9112
      compliance probe, run against the server, with each failure fixed or recorded as a
      deliberate refusal
- [x] How to run it, and what it covers, recorded in `docs/development.md`
- [x] The "Move the pin" steps in `docs/development.md` run `scripts/test.sh`
