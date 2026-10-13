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

Tasks 001–004 build and measure the epoll server, and task 008 moved the pin upstream and
kept gcc over clang and `simd`. Task 005 adds io_uring beside the epoll loop and compares
the two. Task 006 ports the loops to macOS, the BSDs, and Windows, after
task 004. Task 007 gathers the tests into one command and can start at any point. Task
009 adds HttpArena's strongest epoll-era servers to the benchmark, and can start after
task 008. Task 010 moves the build to `goose build` and the shim to C files of their own,
before task 006 adds a platform's shim. Task 011 makes the repository a Goose package that
programs import, after task 010. Task 012 benchmarks the Mac, natively and
in Docker. Task 013 lists the HTTP/1.1 features a program needs from the package, and is
designed with task 011. Task 014 plans HTTP/2 and TLS, after tasks 011 and 013. Task
015 lists what a REST and JSON API still needs. It starts once task 013's macOS tests
and streaming cost are done (2026-10-12); task 013's large-response items can wait, as an
API's responses are small. Task 015's answers that wait are designed with task 014's
HTTP/2. Task 016 accounts for each worker's committed memory, and can start at any
point. Task 017 narrows the IOCP loop's gap to io_uring, on the benchmark desktop. Task
019 adds Tina to the benchmark, and can start at any point. Task 020 sends files on
io_uring and IOCP without copying them, as the epoll loop does. Task 021 is the REST
benchmark, in three tiers taken from HttpArena, snowtime, and a clinic booking app.
Task 023 plans goose-rest, a framework on this package, as a proof of concept for
later, measured on task 021's tiers; it moves to a repository of its own once it has
code.
