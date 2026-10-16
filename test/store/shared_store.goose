// The store (store.goose, shim/store.c): puts, reads of a range, of
// scalars, and of records, refused ranges and blobs, and no put after the
// freeze.
import std;
import http from "../../";
import http.store;

fn main() {
    let a, ea = http::store_put("hello, store");
    let e, ee = http::store_put("");
    assert(ea == 0 && ee == 0 && a.id != e.id);
    assert(http::store_len(a) == 12 && http::store_len(e) == 0);
    assert(http::store_len(http::Blob { .. }) == -1 && http::store_len(http::Blob { id: 99 }) == -1);
    print("put: lengths ", http::store_len(a), " and ", http::store_len(e));

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
    print("ranges: ", out);

    let s = scalars();
    let r = records();

    http::store_freeze();
    let f, ef = http::store_put("late");
    assert(ef < 0 && f.id == -1);
    assert(http::store_append(a, 0, 12, out) && out == ">hellostorehello, store");
    print("frozen: no put; reads go on");
    let last, lok = http::store_record<Item>(r, 2, item_read);
    assert(lok && last.id == 3);
    assert(http::store_u32(s, 8) == 0xdeadbeef);
}

struct Item { id: i64, price: f64, stock: u32, name: u8[4] }

// The test's own C for Item (shared_store.c), as docs/api.md shows.
extern "test_item_read" fn item_read(id: i64, i: i64, out: Item&) -> i32;

// Scalars at their offsets, little-endian, in one blob: an i64, a u32, a
// u8, an f64, as bytes_of writes them.
fn scalars() -> http::Blob {
    var bytes: u8[>..] = [];
    let i: i64[1] = [-5000000000];
    let u: u32[1] = [0xdeadbeef];
    let f: f64[1] = [2.5];
    bytes.append(bytes_of(i));
    bytes.append(bytes_of(u));
    bytes.push(200);
    bytes.append(bytes_of(f));
    let b, e = http::store_put(bytes);
    assert(e == 0 && http::store_len(b) == 21);

    let v64, ok64 = http::store_i64(b, 0);
    let v32, ok32 = http::store_u32(b, 8);
    let v8, ok8 = http::store_u8(b, 12);
    let vf, okf = http::store_f64(b, 13);
    assert(ok64 && ok32 && ok8 && okf);
    print("scalars: ", v64, " ", v32, " ", v8, " ", vf);
    // A value that starts inside the blob and ends past it, and every read
    // of a blob the store doesn't have, is 0 and false.
    let none = http::Blob { id: 99 };
    let x64, n64 = http::store_i64(b, 14);
    let x32, n32 = http::store_u32(b, 18);
    let x8, n8 = http::store_u8(b, 21);
    let xf, nf = http::store_f64(b, -1);
    assert(!n64 && !n32 && !n8 && !nf && x64 == 0 && x32 == 0 && x8 == 0 && xf == 0.0);
    let z64, m64 = http::store_i64(none, 0);
    let z32, m32 = http::store_u32(none, 0);
    let z8, m8 = http::store_u8(none, 0);
    let zf, mf = http::store_f64(none, 0);
    assert(!m64 && !m32 && !m8 && !mf && z64 == 0 && z32 == 0 && z8 == 0 && zf == 0.0);
    let y32, e32 = http::store_u32(b, 17);
    let y8, e8 = http::store_u8(b, 20);
    assert(e32 && e8);
    print("scalars at the end: ", y32 != 0, " ", y8 == 0x40, "; past it refused");
    return b;
}

// Records by value through the test's C read.
fn records() -> http::Blob {
    var items: Item[>..] = [];
    items.push(Item { id: 1, price: 9.5, stock: 3, name: [97, 120, 121, 122] });
    items.push(Item { id: 2, price: 0.25, stock: 0, name: [98, 0, 0, 0] });
    items.push(Item { id: 3, price: 100.0, stock: 70000, name: [99, 99, 99, 99] });
    let b, e = http::store_put(bytes_of(items));
    assert(e == 0 && http::store_len(b) == 3 * 24);
    for i in 3 {
        let it, ok = http::store_record<Item>(b, i, item_read);
        assert(ok && it == items[i]);
        print("record ", i, ": ", it.id, " ", it.price, " ", it.stock, " ", it.name[0..1]);
    }
    let it, ok = http::store_record<Item>(b, 3, item_read);
    assert(!ok && it == default<Item>());
    let neg, nok = http::store_record<Item>(b, -1, item_read);
    let big, bok = http::store_record<Item>(b, 0x7fffffffffffffff, item_read);
    let gone, gok = http::store_record<Item>(http::Blob { id: 99 }, 0, item_read);
    assert(!nok && !bok && !gok && gone == default<Item>());
    print("records past the end and of no blob refused");
    return b;
}
