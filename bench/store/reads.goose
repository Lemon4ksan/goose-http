// The cost of a read from the store: each way reads a value 10 M times
// from a blob of 8192 i64s or of 1024 25-byte records, round by round, and
// prints the best, median, and worst ns per read of the rounds.
//
//   append i64     store_append of 8 bytes into a cleared buffer, decoded
//   store_i64      one C call that returns the value
//   append record  store_append of a record into a cleared buffer, one field
//                  decoded
//   from_bytes     the record rebuilt in Goose: store_append's image, then
//                  from_bytes, as goose_record below
//   store_record   the record by value through its per-type C (reads.c)
import std;
import http from "../../";
import http.store;

struct Item { id: i64, price: i64, stock: i32, rating: f32, flags: u8 }

extern "bench_item" fn bench_item(id: i64, i: i64, out: Item&) -> i32;

let READS = 10000000;
let ROUNDS = 7;

fn le64(b: const u8[:]) -> i64 {
    var v: i64 = 0;
    for k in 8 { v |= (b[k] as i64) << (k * 8); }
    return v;
}

// Record i of b rebuilt by from_bytes, which any flat T allows without C.
fn goose_record<T>(b: http::Blob, i: i64) -> T, bool {
    let one: T[1] = [default<T>()];
    let size = bytes_of(one).len;
    guard i >= 0 && i < 0x7fffffffffffffff / size else { return default<T>(), false; }
    var image: u8[>..] = [];
    format_uleb(image, size);
    guard http::store_append(b, i * size, i * size + size, image) else {
        return default<T>(), false;
    }
    let a, ok = from_bytes<T[>..]>(image);
    guard ok && a.len == 1 else { return default<T>(), false; }
    return a[0], true;
}

fn append_i64(b: http::Blob) -> i64 {
    var buf: u8[>..] = [];
    var sum: i64 = 0;
    for k in READS {
        let at = (k & 8191) * 8;
        buf.clear();
        guard http::store_append(b, at, at + 8, buf) else { abort("append"); }
        sum += le64(buf);
    }
    return sum;
}

fn store_i64(b: http::Blob) -> i64 {
    var sum: i64 = 0;
    for k in READS {
        let v, ok = http::store_i64(b, (k & 8191) * 8);
        guard ok else { abort("store_i64"); }
        sum += v;
    }
    return sum;
}

fn append_record(b: http::Blob) -> i64 {
    var buf: u8[>..] = [];
    var sum: i64 = 0;
    for k in READS {
        let at = (k & 1023) * 25;
        buf.clear();
        guard http::store_append(b, at, at + 25, buf) else { abort("append"); }
        sum += le64(buf[8..16]);
    }
    return sum;
}

fn from_bytes_record(b: http::Blob) -> i64 {
    var sum: i64 = 0;
    for k in READS {
        let it, ok = goose_record<Item>(b, k & 1023);
        guard ok else { abort("goose_record"); }
        sum += it.price;
    }
    return sum;
}

fn store_record(b: http::Blob) -> i64 {
    var sum: i64 = 0;
    for k in READS {
        let it, ok = http::store_record<Item>(b, k & 1023, bench_item);
        guard ok else { abort("store_record"); }
        sum += it.price;
    }
    return sum;
}

// Runs F ROUNDS times and prints its ns per read: best, median, worst.
fn time_way<F>(name: const u8[:], b: http::Blob, want: i64) {
    var ns: i64[>..] = [];
    for r in ROUNDS {
        let t0 = clock_ns();
        let sum = F(b);
        let t1 = clock_ns();
        guard sum == want else { abort("wrong sum"); }
        ns.push(t1 - t0);
    }
    ns.sort();
    print(name, "\t", per_read(ns[0]), "\t", per_read(ns[ROUNDS / 2]), "\t", per_read(ns[ROUNDS - 1]));
}

// ns per read, to two decimals, as text.
fn per_read(total: i64) -> u8[>..] {
    let hundredths = total * 100 / READS;
    var s: u8[>..] = [];
    format(s, hundredths / 100, ".");
    if hundredths % 100 < 10 { s.append("0"); }
    format(s, hundredths % 100);
    return s;
}

fn main() {
    var values: i64[>..] = [];
    for k in 8192 { values.push(k * 3 + 1); }
    var items: Item[>..] = [];
    for k in 1024 {
        items.push(Item { id: k, price: k * 7, stock: k as i32, rating: 0.5, flags: 1 });
    }
    let vb, ve = http::store_put(bytes_of(values));
    let ib, ie = http::store_put(bytes_of(items));
    guard ve == 0 && ie == 0 && http::store_len(ib) == 1024 * 25 else { abort("put"); }
    http::store_freeze();

    // The sums each way must reach: every value, and every price, in turn.
    var want_v: i64 = 0;
    var want_p: i64 = 0;
    for k in READS {
        want_v += values[k & 8191];
        want_p += items[k & 1023].price;
    }
    print("way\tbest\tmedian\tworst (ns per read, ", ROUNDS, " rounds of ", READS, ")");
    time_way("append i64", vb, want_v, append_i64);
    time_way("store_i64", vb, want_v, store_i64);
    time_way("append record", ib, want_p, append_record);
    time_way("from_bytes", ib, want_p, from_bytes_record);
    time_way("store_record", ib, want_p, store_record);
}
