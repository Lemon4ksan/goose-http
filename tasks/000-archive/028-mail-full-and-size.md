# 028: Tell a full box from a long message, and give a sender the slot size

Status: done (2026-10-14)

Found by goose-rest's spike 06 (2026-10-13), which sends a reply larger than a slot back
to a waiting route in pieces. Two gaps in `mail.goose` make the sender guess:

- `mail_send` returns `FULL` both when no slot is free and when the message is longer
  than a slot (`shim/mail.c`, `mail_send`). The first passes, and a sender retries it;
  the second never passes, and a retry loops until something else gives up. The spike
  can only tell them apart by knowing the slot size beforehand.
- A `MailAddress` doesn't say its box's slot size, and `mail_size` answers only the
  box's owner (`mail_own`). So the spike's job carries the slot size from the worker
  to the backend thread, beside the address it already carries.

Additive: `FULL` keeps its meaning for a message that fits.

## Acceptance criteria

- [x] `mail_send` returns a result of its own, such as `TOO_LONG`, for a message longer
      than the box's slot, and `FULL` only when no slot is free: `http::TOO_LONG`
- [x] A sender can learn a box's slot size from its address, for example
      `mail_size(to: MailAddress)`, or the address carries it:
      `http::mail_slot_size(to)`, from any thread, -1 for a `STALE` address. The C
      checks the box's generation and holds off a close while it reads, as a send
      does. `mail_size` stays the owner's name in the shim.
- [x] Tests of each: a send one byte over the slot size, and a send to a box whose
      slots are all taken. In `test/test_mail.goose`, beside the full box's existing
      test; `scripts/test.sh` passes in WSL and Git Bash (2026-10-14).
- [x] `mail.goose`'s header and the README describe both: `examples/README.md`, the
      API reference, and `docs/architecture/README.md`
