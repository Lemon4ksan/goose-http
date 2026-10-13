# Agent rules

## Project context

- What this is and its pins: `README.md`
- Architecture decisions: `docs/architecture/README.md`
- Toolchain and local setup: `docs/development.md`
- What `extern fn` looks like from C, for the shim: `docs/c-interop.md`
- Goose compiler and stdlib gaps found here: `docs/goose-findings.md`
- Task tracking: `tasks/` (see `tasks/README.md`)
- Writing docs: `.claude/skills/google-style/SKILL.md`
- The language: the pinned Goose checkout's `docs/tutorial.md`, `docs/goose_spec.md`,
  and `docs/stdlib.md`. Read the tutorial before writing Goose; check the spec before
  assuming a feature exists.

Follow the recorded decisions; if a change contradicts one, update the doc in the same
change or ask first. Record setup facts and environment traps you find (paths, shell
quirks, ports, encodings) in `docs/development.md`, not in agent memory, so the next
agent finds them. Docs and commits name no people: date a decision or a request
(`(2026-10-11)`), and describe the setup without anyone's machine, checkouts, or home
directory. What only one machine needs, such as where its Goose checkout is, goes in
`CLAUDE.local.md`, which git ignores. Benchmark results still name their machine.

## Goose, not an addition to Goose

- The Goose repository changes daily. Fetch the Goose checkout `GOOSE` is built from
  (`../goose` unless `CLAUDE.local.md` says otherwise) at the start of a session and
  move the pin when it lags, unless `docs/development.md` ("Move the pin") holds it.
- Don't edit the Goose checkout. When the compiler rejects something it should accept,
  miscompiles, or the stdlib lacks something, reduce it to a minimal program, record it
  in `docs/goose-findings.md`, and work around it here. Report blockers to the maintainer.
- Every finding names the Goose commit it was found on, the pin at the time. When one
  lacks it, recover it from this repository's history: the pin in the commit that added
  the entry.
- Write Goose the way the pinned checkout's `samples/` and `stdlib/` do: flat data,
  references into growing arrays, `return ... from` for errors, untyped parameters for
  generics.
- C is for what Goose can't reach: syscalls and kernel structures, behind thin functions
  in `shim/`. HTTP parsing, routing, response building, and JSON are Goose, since
  measuring Goose is the point.

## Benchmarks

- Every number comes with how it was measured: machine, kernel, command, worker and
  connection counts, and run count. A result without them doesn't go in a doc.
- The competing servers run in their fastest documented configuration, built in release
  mode, with the same worker count as the Goose server. Losses are recorded as plainly as
  wins.

## Code conventions

- Comment only where the code is hard to follow without it, and say only what a reader
  of that code needs: why, a constraint, or a contract the code can't show. Don't restate
  the next line, and don't describe earlier versions or the task that added the code;
  history belongs in git.
- Edit files with the Edit tool, not with `sed` or a Python or PowerShell script. On
  Windows, line endings differ by file type and a shell adds a layer of escaping, and
  scripted edits break on both (`docs/development.md`, "Line endings on Windows").
- An `extern fn` whose C side keeps or writes more than the spec's default (§7.10) says
  so in a comment.

## Commits

- One lean sentence in imperative mood, at most 72 characters.
- No body, no `Co-Authored-By` or any other trailers.
