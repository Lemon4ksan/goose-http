# 028: Tell a full box from a long message, and give a sender the slot size

Status: todo

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

- [ ] `mail_send` returns a result of its own, such as `TOO_LONG`, for a message longer
      than the box's slot, and `FULL` only when no slot is free
- [ ] A sender can learn a box's slot size from its address, for example
      `mail_size(to: MailAddress)`, or the address carries it
- [ ] Tests of each: a send one byte over the slot size, and a send to a box whose
      slots are all taken
- [ ] `mail.goose`'s header and the README describe both
