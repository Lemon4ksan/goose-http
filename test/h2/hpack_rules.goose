// HPACK beyond RFC 7541's examples: Huffman coding of every byte and its
// padding rules, the blocks a decoder must refuse, eviction and the table's
// bytes moving to the front against a model of the table, and an encoder's
// size updates.
import std;
import http from "../../";
import http.hpack;
import check from "../";

fn hex(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for i in 0..s.len / 2 {
        let v, ok = parse_int(s[2 * i..2 * i + 2], 16);
        assert(ok);
        out.push(v as u8);
    }
    return out;
}

fn to_hex(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for c in s { format_int(out, c, 16, 2, '0'); }
    return out;
}

fn round_trip(s: const u8[:]) {
    var coded: u8[>..] = [];
    http::hpack_huffman(coded, s);
    assert(coded.len == http::hpack_huffman_len(s));
    var back: u8[>..] = [];
    assert(http::hpack_unhuffman(back, coded));
    check::same(back, s);
}

fn unhuffman(coded: const u8[:]) -> bool {
    var out: u8[>..] = [];
    return http::hpack_unhuffman(out, coded);
}

fn huffman() {
    var all: u8[>..] = [];
    for i in 256 {
        all.push(i as u8);
        round_trip(all[i..]);
    }
    round_trip(all);
    round_trip("");
    var r = rng { 7 };
    for k in 1000 {
        var s: u8[>..] = [];
        for j in r.rand_int(40) { s.push(r.rand_int(256) as u8); }
        round_trip(s);
    }
    print("Huffman: each byte alone, all 256 together, and 1000 random strings round trip");

    // 'a' is 00011: three bits of padding, which must be ones.
    assert(unhuffman(hex("1f")));
    assert(!unhuffman(hex("1b")));
    // Eight bits or more of padding.
    assert(!unhuffman(hex("1fff")));
    assert(!unhuffman(hex("ff")));
    // EOS, 30 ones, then two of padding.
    assert(!unhuffman(hex("ffffffff")));
    print("Huffman: padding of zeros, padding over 7 bits, and EOS refused");
}

fn decodes(t: http::HpackTable&, fb: const u8[:]) -> bool {
    var scratch: u8[>..] = [];
    return http::hpack_decode(t, fb, scratch) { n, v => };
}

fn refusals() {
    let bad = [
        "80",                       // index 0
        "be",                       // index 62, in an empty dynamic table
        "ff80808080808001",         // an index past HPACK_MAX_INT
        "400a6375",                 // a name shorter than its length
        "407f",                     // a truncated length
        "0f",                       // a 4-bit index, truncated
        "4003616263ff",             // a value's length cut off
        "4081ff0161",               // a Huffman name of 8 bits of padding
        "3fe21f",                   // a size update to 4097, over the limit
        "8220",                     // a size update after a field
    ];
    for b in bad {
        var t = http::hpack_table();
        if decodes(t, hex(b)) {
            print("decoded ", b);
            assert(false);
        }
    }
    var t = http::hpack_table();
    assert(decodes(t, hex("202082")) && t.max == 0 && t.count == 0);
    assert(decodes(t, hex("3fe11f82")) && t.max == 4096);
    print("decode: ", bad.len, " malformed blocks refused; size updates before the first field taken");
}

// Many fields, of names the table may already hold and values of every
// length, through an encoder and a decoder, each checked after each block
// against a model of the table: every entry added, as "name=value", oldest
// first, and the first one the table still holds. The entries' bytes move to
// the front many times over.
fn churn() {
    var enc = http::hpack_table();
    var dec = http::hpack_table();
    var model: u8[..4200][>..] = [];
    var first = 0;
    var size = 0;

    fn same_table(t: const http::HpackTable&) {
        assert(t.size == size && t.count == model.len - first);
        for i in 1..t.count + 1 {
            let n, v = http::hpack_entry(t, i);
            check::same(str(n, "=", v), model[model.len - i]);
        }
    }

    var r = rng { 11 };
    var named = 0;
    for k in 3000 {
        var name: u8[>..] = [];
        format(name, "x-", r.rand_int(9));
        var value: u8[>..] = [];
        let len = if k % 97 == 0 { 4100 } else { r.rand_int(300) };
        for j in len { value.push(('a' + r.rand_int(26)) as u8); }
        let whole, idx = http::hpack_find(enc, name, value);
        if idx > http::HPACK_STATIC_COUNT { named++; }
        var out: u8[>..] = [];
        http::hpack_begin(enc, out);
        http::hpack_encode(enc, out, name, value);
        model.push(str(name, "=", value));
        size += name.len + value.len + 32;
        while size > 4096 && first < model.len {
            size -= model[first].len - 1 + 32;
            first++;
        }
        same_table(enc);
        var got: u8[>..] = [];
        var scratch: u8[>..] = [];
        assert(http::hpack_decode(dec, out, scratch) { n, v => format(got, n, "=", v); });
        check::same(got, str(name, "=", value));
        same_table(dec);
    }
    assert(named > 1000);
    print("churn: 3000 fields agree with the model in encoder and decoder, ",
          "most named from the dynamic table");
}

fn size_updates() {
    var enc = http::hpack_table();
    var out: u8[>..] = [];
    http::hpack_begin(enc, out);
    assert(out.len == 0);
    http::hpack_encode(enc, out, "x-a", "1");
    assert(enc.count == 1);
    // The peer lowers its limit to 0 and raises it to 1000 between blocks:
    // the next block says 0 then 1000, and the entry is gone.
    http::hpack_limit(enc, 0);
    http::hpack_limit(enc, 1000);
    out.clear();
    http::hpack_begin(enc, out);
    check::same(to_hex(out), "203fc907");
    assert(enc.count == 0 && enc.max == 1000);
    out.clear();
    http::hpack_begin(enc, out);
    assert(out.len == 0);
    // A limit above HPACK_TABLE_SIZE takes HPACK_TABLE_SIZE.
    http::hpack_limit(enc, 65536);
    http::hpack_begin(enc, out);
    check::same(to_hex(out), "3fe11f");
    // A decoder follows each.
    var dec = http::hpack_table();
    assert(decodes(dec, hex("203fc907")) && dec.max == 1000);
    // Never-indexed and unindexed fields stay out of the table, and an
    // indexed one comes back as its index.
    out.clear();
    http::hpack_encode(enc, out, "authorization", "secret", http::HPACK_NEVER_INDEX);
    http::hpack_encode(enc, out, "x-b", "2", http::HPACK_NO_INDEX);
    http::hpack_encode(enc, out, "x-c", "3");
    http::hpack_encode(enc, out, "x-c", "3");
    http::hpack_encode(enc, out, ":status", "200");
    assert(enc.count == 1);
    // Never indexed, with name 23 in a 4-bit prefix; then x-c's and
    // :status 200's indexes, 62 and 8.
    check::same(to_hex(out[..2]), "1f08");
    check::same(to_hex(out[^2..]), "be88");
    var dec2 = http::hpack_table();
    var got: u8[>..] = [];
    var scratch: u8[>..] = [];
    assert(http::hpack_decode(dec2, out, scratch) { n, v => format(got, n, ": ", v, "; "); });
    check::same(got, "authorization: secret; x-b: 2; x-c: 3; x-c: 3; :status: 200; ");
    assert(dec2.count == 1);
    print("encoder: size updates for a lower then higher limit, and each kind of literal");
}

fn main() {
    huffman();
    refusals();
    churn();
    size_updates();
}
