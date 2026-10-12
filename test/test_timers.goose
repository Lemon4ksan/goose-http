// Unit tests for the timer table (timers.goose) and its handles
// (handle.goose). The package is declared by timers.goose alone, so this
// compiles only if the timer table reaches nothing of the HTTP side.
// scripts/test-unit.sh runs them through TinyCC.
import std;
import timers from "../";

fn same(got: const u64[:], want: const i64[:]) -> bool {
    guard got.len == want.len else { return false; }
    for k, i in got { guard k == want[i] as u64 else { return false; } }
    return true;
}

fn test_handles() {
    let h = http::Handle { slot: 7, gen: 0xFFFFFFFF };
    let back = http::handle_of(http::key_of(h));
    assert(back.slot == 7 && back.gen == 0xFFFFFFFF);
    assert(http::next_gen(0xFFFFFFFF) == 1 && http::next_gen(1) == 2);
    let none = http::Handle { .. };
    assert(none.slot == -1);
}

fn test_order() {
    var t = http::timer_table(8);
    let _, any = http::next_due(t);
    assert(!any);
    for at in [50, 10, 40, 30, 20] { http::arm(t, (at * 2) as u64, at); }
    let at, some = http::next_due(t);
    assert(some && at == 10);
    var got: u64[>..] = [];
    http::expire(t, 35) { key => got.push(key); };
    assert(same(got, [20, 40, 60]));
    http::expire(t, 1000) { key => got.push(key); };
    assert(same(got, [20, 40, 60, 80, 100]));
    assert(t.count == 0);
}

fn test_full_and_stale() {
    var t = http::timer_table(3);
    let a = http::arm(t, 1, 100);
    let b = http::arm(t, 2, 200);
    let c = http::arm(t, 3, 300);
    let d = http::arm(t, 4, 400);
    assert(a.slot >= 0 && b.slot >= 0 && c.slot >= 0 && d.slot == -1);
    assert(http::cancel(t, b) && !http::cancel(t, b) && !http::armed(t, b));
    // b's cell goes to the next timer, under a new generation: b stays dead.
    let e = http::arm(t, 5, 50);
    assert(e.slot == b.slot && e.gen != b.gen);
    assert(!http::cancel(t, b) && http::armed(t, e));
    var got: u64[>..] = [];
    http::expire(t, 100) { key => got.push(key); };
    assert(same(got, [5, 1]));
    // A fired timer can't be cancelled, nor can a handle from no table.
    assert(!http::cancel(t, a) && !http::cancel(t, e) && !http::cancel(t, http::Handle { .. }));
    assert(!http::cancel(t, http::Handle { slot: 9, gen: 1 }));
    let empty = http::timer_table(0);
    assert(!http::armed(empty, a));
}

// A block that arms a timer already due doesn't keep expire from returning,
// and the new timer fires at the next call.
fn test_rearm() {
    var t = http::timer_table(4);
    http::arm(t, 1, 10);
    var fired = 0;
    http::expire(t, 10) { key =>
        fired++;
        http::arm(t, key + 1, 10);
    };
    assert(fired == 1 && t.count == 1);
    http::expire(t, 10) { key => assert(key == 2); fired++; };
    assert(fired == 2 && t.count == 0);
}

// Against a list scanned in full: random arms, cancels, and expiries, with
// equal deadlines among them.
fn test_random() {
    let n = 64;
    var t = http::timer_table(n);
    var model_at: i64[>..] = [];
    var model_handle: http::Handle[>..] = [];
    for i in n {
        model_at.push(-1);
        model_handle.push(http::Handle { .. });
    }
    var seed: u64 = 12345;
    fn rand(k: i64) -> i64 {
        seed = seed * 6364136223846793005 + 1442695040888963407;
        return ((seed >> 33) % (k as u64)) as i64;
    }
    var now = 0;
    for step in 20000 {
        let op = rand(10);
        if op < 5 {
            let key = rand(n);
            if model_at[key] < 0 {
                let at = now + rand(50);
                let h = http::arm(t, key as u64, at);
                assert(h.slot >= 0);
                model_at[key] = at;
                model_handle[key] = h;
            }
        } else if op < 7 {
            let key = rand(n);
            let was = model_at[key] >= 0;
            assert(http::cancel(t, model_handle[key]) == was);
            model_at[key] = -1;
        } else {
            now += rand(20);
            var last = -1;
            http::expire(t, now) { key =>
                let k = key as i64;
                assert(model_at[k] >= 0 && model_at[k] <= now && model_at[k] >= last);
                last = model_at[k];
                model_at[k] = -1;
            };
            for at in model_at { assert(at < 0 || at > now); }
        }
        var count = 0;
        var earliest = -1;
        for at in model_at {
            if at >= 0 {
                count++;
                if earliest < 0 || at < earliest { earliest = at; }
            }
        }
        assert(t.count == count);
        let due, any = http::next_due(t);
        assert(any == (count > 0) && (!any || due == earliest));
    }
}

fn main() {
    test_handles();
    test_order();
    test_full_and_stale();
    test_rearm();
    test_random();
    print("test_timers: ok");
}
