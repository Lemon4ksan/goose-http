// Unit tests for the REST server's shared store (store.goose, store.c):
// puts, reads of a range, refused ranges and blobs, and no put after the
// freeze. Run it with `goose bench/rest/goose/test_store.goose`.
import std;
import store;

fn main() {
    let a, ea = store::put("hello, store");
    let e, ee = store::put("");
    assert(ea == 0 && ee == 0 && a.id != e.id);
    assert(store::len(a) == 12 && store::len(e) == 0);
    assert(store::len(store::Blob { .. }) == -1 && store::len(store::Blob { id: 99 }) == -1);

    var out: u8[>..] = [];
    out.append(">");
    assert(store::append(a, 0, 5, out) && out == ">hello");
    assert(store::append(a, 7, 12, out) && out == ">hellostore");
    assert(store::append(e, 0, 0, out) && out == ">hellostore");
    // Ranges outside the blob, and blobs the store doesn't have, append
    // nothing.
    assert(!store::append(a, 0, 13, out) && !store::append(a, -1, 2, out));
    assert(!store::append(a, 5, 4, out) && !store::append(store::Blob { id: 99 }, 0, 0, out));
    assert(out == ">hellostore");

    store::freeze();
    let f, ef = store::put("late");
    assert(ef < 0 && f.id == -1);
    assert(store::append(a, 0, 12, out) && out == ">hellostorehello, store");
    print("test_store: ok");
}
