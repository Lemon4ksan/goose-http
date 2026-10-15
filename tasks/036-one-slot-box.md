# 036: A box of one slot never reports FULL

Status: todo (found 2026-10-15)

Found by goose-rest's tutorial (its page 15, limits) at `v0.3.1`. `http::mail_open(1,
size)` succeeds, but every `mail_send` to it returns `SENT`, overwriting the message not
yet taken. The ring in `shim/mail.c` tells a free slot from a full one by its sequence
number, which needs at least two slots: with one, a filled slot's sequence equals the
next send's position.

```rust
import std;
import http from "github.com/kaitk/goose-http@v0.3.1";
fn main() {
    for slots in [1, 2, 4] {
        let box, e = http::mail_open(slots as i32, 64);
        let to = http::address(box, 0);
        var line: u8[>..] = [];
        format(line, slots, " slots:");
        for i in 6 { format(line, " ", http::mail_send(to, 1, "x")); }
        print(line);
    }
}
```

```text
1 slots: 0 0 0 0 0 0
2 slots: 0 0 1 1 1 1
4 slots: 0 0 0 0 1 1
```

goose-rest's tutorial opens its box with two slots meanwhile.

## Acceptance criteria

- [ ] `mail_open` refuses fewer than two slots, or a box of one reports `FULL` while its
      slot is taken
- [ ] `docs/api.md` says which, and a unit test covers it
