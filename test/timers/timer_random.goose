// The timer table against a list scanned in full: random arms, cancels, and
// expiries, with equal deadlines among them. The package is declared by
// timers.goose alone.
import std;
import timers from "../../";

fn main() {
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
    var fired = 0;
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
                fired++;
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
    print("20000 steps: ", fired, " fired, as the model has it");
}
