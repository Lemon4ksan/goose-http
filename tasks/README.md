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
benchmark, in three tiers taken from HttpArena, snowtime, and a clinic booking app, and
one of uploads; done, measured against six competitors (2026-10-13), and kept here because
goose-rest, a framework on this package planned in its own repository, is measured on
its tiers. Task 024 looks for why nginx beats Goose at 64 KB files, where Goose's emulated
ring doesn't lose, and can start at any point. Task 025 shrinks the REST server's
memory, a copy of the records per worker. Task 026 brings the io_uring loop's reads
beside uploads to the epoll loop's latency. Task 027 makes the API more idiomatic Goose
where the benchmarks show speed holds, then rewrites the examples and the API reference.
It comes next, since breaking changes cost least before programs such as goose-rest use
the API. Task 028 tells a full mailbox from a message longer than a slot, and gives a
sender the slot size, for goose-rest's replies in pieces; it can start at any point.
Task 029 builds for embedded Linux on aarch64, with a device example, and waits on a
board to finish. Task 030 ports to 32-bit ARM, after task 029's guide. Task 031 moves the
REST server's records, loaders, and writers into a module that goose-rest imports, after
task 025's branches merge, since both change the same server. Task 032 gives the bench
scripts one shared harness that goose-rest can reuse.

Next, in this order (asked for 2026-10-14): task 027's remaining API work, each step
committed and pushed; the overnight benchmarks that the branches in task 027's "Pending"
wait on, then their merges into `main`; task 032; and goose-rest's first benchmark run
on the benchmark desktop, once the HTTP changes are on `main`.
