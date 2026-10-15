// Handles (handle.goose): a key and back, and generations. The package is
// declared by timers.goose alone, so this compiles only if the timer table
// reaches nothing of the HTTP side.
import std;
import timers from "../../";

fn main() {
    let h = http::Handle { slot: 7, gen: 0xFFFFFFFF };
    let back = http::handle_of(http::key_of(h));
    assert(back.slot == 7 && back.gen == 0xFFFFFFFF);
    assert(http::next_gen(0xFFFFFFFF) == 1 && http::next_gen(1) == 2);
    let none = http::Handle { .. };
    assert(none.slot == -1);
    print("handle: slot ", back.slot, ", gen ", back.gen, "; next_gen wraps to ", http::next_gen(0xFFFFFFFF));
}
