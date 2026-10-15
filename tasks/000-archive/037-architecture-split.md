# 037: Split the architecture doc into a user's page and a decision log

Status: done (2026-10-15)

`docs/architecture/README.md` describes the package by topic, but cites tasks 18 times
and carries dated notes, against AGENTS.md's rule that user-facing docs reference no
tasks and carry no history. goose-rest's task 026 makes the same split.

## Acceptance criteria

- [x] `docs/architecture.md`, for users: how the package works and why, as it is now,
      with no dates or tasks, linking the API and patterns rather than repeating them
- [x] `docs/decisions.md`, stated in its first line as the record for contributors and
      agents: each decision, dated, with its reason, what was rejected, and the task that
      measured it
- [x] AGENTS.md's "Architecture decisions" points at `docs/decisions.md`, and every link
      to the old file, goose-rest's included, points at the page that now holds its
      section
