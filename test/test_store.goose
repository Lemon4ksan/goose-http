// Unit tests for the shared store (store.goose, shim/store.c): puts, reads
// of a range, refused ranges and blobs, and no put after the freeze.
// scripts/test-unit.sh runs them through TinyCC.
import std;
import http from "../";
import http.store;

fn main() {
    let a, ea = http::store_put("hello, store");
    let e, ee = http::store_put("");
    assert(ea == 0 && ee == 0 && a.id != e.id);
    assert(http::store_len(a) == 12 && http::store_len(e) == 0);
    assert(http::store_len(http::Blob { .. }) == -1 && http::store_len(http::Blob { id: 99 }) == -1);

    var out: u8[>..] = [];
    out.append(">");
    assert(http::store_append(a, 0, 5, out) && out == ">hello");
    assert(http::store_append(a, 7, 12, out) && out == ">hellostore");
    assert(http::store_append(e, 0, 0, out) && out == ">hellostore");
    // Ranges outside the blob, and blobs the store doesn't have, append
    // nothing.
    assert(!http::store_append(a, 0, 13, out) && !http::store_append(a, -1, 2, out));
    assert(!http::store_append(a, 5, 4, out) && !http::store_append(http::Blob { id: 99 }, 0, 0, out));
    assert(out == ">hellostore");

    http::store_freeze();
    let f, ef = http::store_put("late");
    assert(ef < 0 && f.id == -1);
    assert(http::store_append(a, 0, 12, out) && out == ">hellostorehello, store");
    print("test_store: ok");
}
