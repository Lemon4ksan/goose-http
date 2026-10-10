# Tasks

Markdown-based task tracking. One file per task, or one folder for a task with
several subtasks or its own supporting files.

## Naming

`NNN-short-slug.md` — zero-padded, sequential number plus a kebab-case slug,
e.g. `003-epoll-server.md`.

A task with subtasks or supporting files is a folder with the same name,
`NNN-short-slug/`, holding the task itself as `README.md` and one file per
subtask as `NN-short-slug.md`, numbered within the folder. Subtasks use the same format
as tasks.

## Format

```markdown
# NNN: Title

Status: todo | in-progress | done | cancelled

Short description of what and why.

## Acceptance criteria

- [ ] Concrete, verifiable outcome
- [ ] ...
```

Update the status line as work progresses; tick criteria as they are met. A cancelled task
says who cancelled it, when, and why. A task that measures something records the numbers
in its own file, with how they were measured.

## Archive

When a task is done and nothing still builds on its file, move it to `000-archive/` with
`git mv`, keeping its name. The main folder then lists only open work. Numbers stay
unique across both folders: pick the next number after the highest in either. Refer to
tasks by number ("task 008"), not by path, so a move breaks no reference.

## Order

Tasks 001–004 build and measure the epoll server. Task 008 moves to clang and upstream
Goose's `simd` functions; task 005 then adds io_uring beside the epoll loop and compares
the two on that build. Task 006 ports the loops to macOS, the BSDs, and Windows, after
task 004. Task 007 gathers the tests into one command and can start at any point. Task
009 adds HttpArena's strongest epoll-era servers to the benchmark, and can start after
task 008.
