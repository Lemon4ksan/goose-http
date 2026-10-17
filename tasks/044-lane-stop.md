# 044: A stop a full box can't refuse

Status: built on `tina-alignment`; the docs wait for review (2026-10-17), and the
Windows run is pending

A lane learns to stop from a message: goose-rest's best-practices `lanes/` program sends
each lane `STOP` with `http::mail_send` and ignores the result. When the box is full at
shutdown, the send returns `FULL` and the stop is lost. The lane then drains its box and
waits for mail forever, and `main`'s `thread_wait` never returns. Tina keeps a reserved
part of its message pool for shutdown, timers, and restarts, so that traffic can't
crowd them out (its `docs/concepts/backpressure_and_drops.md`, at `d129f67`).

A stop becomes a flag in the box, not a message in a slot: `http::mail_stop(box)` sets
it and wakes the thread that waits, and `http::mail_stopped(box)` is true once the box
is stopped and empty. `mail_wait` keeps its meaning, since its `false` already means the
time limit passed, so a lane can wait with no limit (`-1`) and still wake for the stop.
Jobs queued before the stop still run, and their replies go
`STALE` once the workers have stopped. goose-rest then wraps the loop every lane writes
by hand in `rest::lane(box) { tag, bytes => ... }`, which also closes the box.

As built (2026-10-17): a send to a stopped box returns `STALE`, so that a lane that
finds its box stopped and empty can close it without dropping a job sent after the stop.
`mail_stopped` also waits out a send in flight across the stop: it reads the table's
senders count, as a close does. `test/mail/mail_stop.goose` shows the lost `STOP` (its
lane gives up after three empty waits, where a real one waits forever), then a stop of
the same full box, a `STALE` send after it, and a stop that wakes a lane asleep in
`mail_wait(box, -1)`.

## Acceptance criteria

- [x] A test shows the hang today: a box filled to its slots, a `STOP` sent to it,
      and a lane that never returns
- [ ] `http::mail_stop` in `mail.goose` and the shim, on every loop and platform: it
      never fails for a full box, and wakes a thread blocked in `mail_wait`. Done in
      `shim/mail.c`, which every platform shares, and tested on macOS and on Linux
      (io_uring, the ring over epoll, epoll, in Docker); Windows pending
- [x] `http::mail_stopped` is true only once the box is stopped and empty, and the test
      above returns with every queued job taken
- [ ] `docs/api.md` ("Answers that wait") and `docs/architecture.md` ("Mail between
      threads") describe the stop; `docs/patterns.md` ("Slow work") shows a lane that
      stops. Postponed until the code is reviewed (2026-10-17); `examples/later` stops
      its lane
- [ ] `scripts/test.sh` passes on Linux (io_uring, epoll), macOS, and Windows: passes on
      macOS and on Linux in Docker on macOS (arm64); Windows pending
- [x] goose-rest: `rest::lane`, and the tutorial's and best practices' lanes use it and
      `http::mail_stop` in place of a `STOP` tag (its branch `tina-alignment`).
      Chapter 13's reports thread works between messages with a time limit, so it
      writes the loop itself, ending on `mail_stopped`
