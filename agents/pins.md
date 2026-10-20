# Moving the Goose pin

The pin is an official Goose release, which builds the same on every platform. At the
start of a session, check for a newer one:

```sh
gh release list -R aardappel/goose --limit 3
```

To move to a new release, update `goose_release` and the four archives' SHA-256 sums in
`scripts/goose.sh`. GitHub lists each asset's digest:

```sh
gh api repos/aardappel/goose/releases/tags/<tag> -q '.assets[] | "\(.name) \(.digest)"'
```

Then run `scripts/test.sh` on Linux, on Windows in Git Bash, and on macOS, and update
the release and its commit in `README.md`'s quick start, `docs/development.md` ("Get
Goose" and the release paths), and `.vscode/settings.json`, in its own commit.

Pin a commit only when a Goose fix that this repository needs isn't in a release yet,
and return to a release once one has it (2026-10-15). Set `goose_commit` in
`scripts/goose.sh` to the full hash, which every script and
`bench/httparena/goose/Dockerfile` then build, and empty it to return to the release.
Record the commit and the reason in `docs/development.md`, "Get Goose". Goose releases
often, so work that needs a merged fix lands on `main` on a pinned commit rather than
wait for the release (2026-10-19).

A pin move doesn't wait for benchmarks. They're costly to run, so they run in batches,
overnight, after a stretch of work (2026-10-13). Until then the results stand at the
compilers they name, which `docs/benchmarks.md`'s pins table lists.
