# 044: A stop a full box can't refuse

Status: todo

A lane learns to stop from a message: goose-rest's best-practices `lanes/` program sends
each lane `STOP` with `http::mail_send` and ignores the result. When the box is full at
shutdown, the send returns `FULL` and the stop is lost. The lane then drains its box and
waits for mail forever, and `main`'s `thread_wait` never returns. Tina keeps a reserved
part of its message pool for shutdown, timers, and restarts, so that traffic can't
crowd them out (its `docs/concepts/backpressure_and_drops.md`, at `d129f67`).

A stop becomes a flag in the box, not a message in a slot: `http::mail_stop(box)` sets
it and wakes the thread that waits, and `http::mail_wait` returns `false` once the box
is stopped and empty. Jobs queued before the stop still run, and their replies go
`STALE` once the workers have stopped. goose-rest then wraps the loop every lane writes
by hand in `rest::lane(box) { tag, bytes => ... }`, which also closes the box.

## Acceptance criteria

- [ ] A test shows the hang today: a box filled to its slots, a `STOP` sent to it,
      and a lane that never returns
- [ ] `http::mail_stop` in `mail.goose` and the shim, on every loop and platform: it
      never fails for a full box, and wakes a thread blocked in `mail_wait`
- [ ] `http::mail_wait` returns `false` only once the box is stopped and empty, and
      the test above returns with every queued job taken
- [ ] `docs/api.md` ("Answers that wait") and `docs/architecture.md` ("Mail between
      threads") describe the stop; `docs/patterns.md` ("Slow work") shows a lane that
      stops
- [ ] `scripts/test.sh` passes on Linux (io_uring, epoll), macOS, and Windows
- [ ] goose-rest: `rest::lane`, and the tutorial's and best practices' lanes use it and
      `http::mail_stop` in place of a `STOP` tag
