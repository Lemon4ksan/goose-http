# 051: Jobs through a limited queue

Status: in-progress; built, and the benchmark before and after waits for a batch

With [aardappel/goose#39](https://github.com/aardappel/goose/pull/39), in the pinned
`dcc2747`, Goose's typed queues take a limit (`qlimit<T>(n)`), `qput` returns false at
once when a queue is full, and `qget<T>(ms)` waits with a time limit. That covers one
half of what `shim/mail.c` does: jobs that a thread takes from no particular sender.

The benchmark server's backend, which answers `/later`, `/events`, and an upgraded
`/upgrade` after a delay, is that case:

- `server/routes.goose` puts a `Job` with `qput` instead of sending it to the backend's
  box, and answers 503 when `qput` returns false; `server/app.goose` gives the queue a
  limit of 256, the box's slots.
- `server/backend.goose` waits with `qget<Job>(ms)` until a job or its next timer.
  The job's kind went: no code read it, and the backend never stops, so the stop it
  stood for went with it. Its box went too, and with it the job's size limit.

Replies stay on mail: a reply goes to the one worker whose exchange waits for it, and a
queue chosen by type can't reach one particular thread. The worker loops also wait in
epoll, io_uring, or IOCP, which only an fd wakes. A lane keeps its box too: `rest::ask_by`
keeps one key's jobs in order on one thread, a send picks the least busy box, and a stop
is a flag a full box can't refuse; a queue shared by type has none of that.
`http::run`'s supervision uses the queues as well (task 050).

## Acceptance criteria

- [x] The pin has #39 (`dcc2747`)
- [x] The backend takes jobs from a limited queue, with 503 when it's full, and the
      `/later`, `/events`, and `/upgrade` tests pass unchanged (macOS, and Linux in
      arm64 Docker on each loop, 2026-10-19)
- [ ] The tiers that wait (`/later`, `/events`) measured before and after, on the same
      machine, recorded here with how they were measured; dropped if slower beyond the
      runs' spread
- [x] `docs/decisions.md` says what of mail stays in C, and why
- [x] `docs/patterns.md` ("slow work") shows a limited queue for a pool, and mail for
      replies and for a lane of its own
- [ ] goose-rest's task 045: a pool of identical lanes on a limited queue through
      `rest::ask`, or left to the program, decided there
- [ ] `scripts/test.sh` passes on Windows
