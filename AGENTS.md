# Agent rules

## Project context

- What this is: `README.md`; what each tag adds: `CHANGELOG.md`; the API by topic:
  `docs/api.md`; which approach fits bodies, responses, and slow work:
  `docs/patterns.md`; and the examples: `examples/README.md`
- Architecture decisions, dated, with their reasons: `docs/decisions.md`; how the
  package works, and what isn't Goose: `docs/architecture.md`
- Layout, the Goose release, toolchain, and local setup: `docs/development.md`
- Environment traps and incidents, by platform: `docs/known-issues.md`
- What `extern fn` looks like from C, for the shim: `docs/c-interop.md`
- Goose compiler and stdlib gaps found here: `docs/goose-findings.md`
- Task tracking: `tasks/` (see `tasks/README.md`)
- Substantial doc drafts and requested prose reviews:
  `.claude/skills/google-style/SKILL.md`; other writing follows "Writing" below
- The language: the pinned Goose release's `docs/tutorial.md`, `docs/goose_spec.md`,
  and `docs/stdlib.md`. Read the tutorial before writing Goose; check the spec before
  assuming a feature exists.

Follow the recorded decisions; if a change contradicts one, update the doc in the same
change or ask first. Record setup facts you find (paths, versions, install steps) in
`docs/development.md`, and environment traps (shell quirks, ports, encodings, dated
incidents) in `docs/known-issues.md`, not in agent memory, so the next agent finds
them. Docs and commits name no people: date a decision or a request
(`(2026-10-11)`), and describe the setup without anyone's machine, checkouts, or home
directory. What only one machine needs, such as where its Goose checkout is, goes in
`CLAUDE.local.md`, which git ignores. Benchmark results still name their machine. The
docs and scripts must work for a developer on a clean machine without LLM tools:
`CLAUDE.local.md` holds conveniences, never a step the setup needs, and a script fetches
what it needs or says how to get it, rather than assume a sibling checkout (2026-10-15).

## Writing

- `README.md` is for people who use the package: what it provides, a quick start,
  concepts, benchmark highlights, and links. Process, pins, layout, internals, and
  rules for agents go in `docs/` or here (2026-10-15).
- Lead with the decision, behavior, or action, then explain why. Name the responsible
  component and use concrete facts. Cut filler and repeated summaries.
- Preserve technical meaning when editing: actors, negations, conditions, numbers,
  versions, commands, paths, and identifiers. Keep decided/proposed/open,
  implemented/planned, and must/should/can distinct. Flag contradictions instead of
  silently resolving them while copyediting.
- Record a decision with its reason and the trade-off that matters. Keep each fact in
  one place and link to it elsewhere. Use absolute dates for dated events.
- Match the document's format. Tasks follow `tasks/README.md`, with concrete acceptance
  criteria. Use sentence-case headings, backticks for code identifiers and commands,
  and descriptive links. Wrap prose at about 90 characters.
- Use prose for connected ideas, lists for steps or separate items, and tables for
  comparisons. Keep structure proportional to the content.

## Goose, not an addition to Goose

- Build with the official Goose release that `scripts/goose.sh` pins, and move the pin
  to each new release ("Move the Goose pin" below).
- Don't edit a Goose checkout. When the compiler rejects something it should accept,
  miscompiles, or the stdlib lacks something, work around it here, and reduce it to a
  minimal program for `docs/goose-findings.md` only if it meets the bar that file's
  introduction sets. Report blockers to the maintainer.
- Every finding names the Goose commit it was found on, the pin at the time (for a
  release, its commit). When one lacks it, recover it from this repository's history:
  the pin in the commit that added the entry.
- `docs/goose-findings.md` lists bugs first and feature requests after, each part from
  the least work a fix is expected to take to the most. Place a new entry by that
  order, and delete an entry once the pin has its fix (2026-10-14).
- Write Goose the way the pinned release's `samples/` and `stdlib/` do: flat data,
  references into growing arrays, `return ... from` for errors, untyped parameters for
  generics.
- C is for what Goose can't reach: syscalls and kernel structures, behind thin functions
  in `shim/`. HTTP parsing, routing, response building, and JSON are Goose, since
  measuring Goose is the point.

## Move the Goose pin

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
and return to a release once one has it (2026-10-15). Set `GOOSE_COMMIT` in the
scripts' environment (`docs/development.md`, "Use another compiler"), and
`--build-arg GOOSE_COMMIT=<hash>` for `bench/httparena/goose/Dockerfile`. Record the
commit and the reason in `docs/development.md`, "Get Goose".

A pin move doesn't wait for benchmarks. They're costly to run, so they run in batches,
overnight, after a stretch of work (2026-10-13). Until then the results stand at the
compilers they name, which `docs/benchmarks.md`'s pins table lists.

## Benchmarks

- Every number comes with how it was measured: machine, kernel, command, worker and
  connection counts, and run count. A result without them doesn't go in a doc.
- The competing servers run in their fastest documented configuration, built in release
  mode, with the same worker count as the Goose server. Losses are recorded as plainly as
  wins.
- A change made only for speed that shows no gain beyond the runs' spread is dropped, and
  its task records what it was, what it cost, and why it went, so it isn't proposed again
  (2026-10-14).

## Code conventions

- Comment only where the code is hard to follow without it, and say only what a reader
  of that code needs: why, a constraint, or a contract the code can't show. Don't restate
  the next line, and don't describe earlier versions or the task that added the code;
  history belongs in git.
- Edit files with the Edit tool, not with `sed` or a Python or PowerShell script. On
  Windows, line endings differ by file type, Python defaults can write cp1252 and CRLF,
  and a shell adds a layer of escaping, and scripted edits break on all three. The Edit
  tool keeps each file's endings and needs no escaping (`docs/known-issues.md`, "Line
  endings on Windows").
- An `extern fn` whose C side keeps or writes more than the spec's default (§7.10) says
  so in a comment.

## Running commands

- Never edit a script while it runs: Bash reads later commands from the file as it
  executes, and an edit to a benchmark script during its builds ended the run with an
  unexpected EOF before measurement began (2026-10-14). Write a separate script for an
  extension.
- Kill a process by its PID, never by pattern: `pkill -f` inside `bash -c` can match
  and kill that shell, and killing strace doesn't kill the server it started
  (`docs/known-issues.md`, "WSL from a Windows shell").

## Commits

- Push finished work to `main` once its tests pass, even when its benchmarks are still
  to run: record the pending check in its task, and add the results when they come. A
  change whose benchmarks then show a cost is reverted on `main` with an inverse commit
  (2026-10-14). Work branches are for work that isn't finished.
- One lean sentence in imperative mood, at most 72 characters.
- No body, no `Co-Authored-By` or any other trailers.
