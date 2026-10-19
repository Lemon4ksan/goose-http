// HPACK against RFC 7541's examples (Appendix C): integers, each kind of field,
// and the three requests and three responses decoded, with and without
// Huffman coding, and encoded back to the same bytes.
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

// The decoded fields of fb, one "name: value" a line, through t.
fn decode(t: http::HpackTable&, fb: const u8[:]) -> u8[>..] {
    var scratch: u8[>..] = [];
    var lines: u8[>..] = [];
    let ok = http::hpack_decode(t, fb, scratch) { n, v => format(lines, n, ": ", v, "\n"); };
    assert(ok);
    return lines;
}

// The dynamic table, newest first, as Appendix C prints it.
fn table(t: const http::HpackTable&) -> u8[>..] {
    var out: u8[>..] = [];
    for i in 1..t.count + 1 {
        let n, v = http::hpack_entry(t, i);
        format(out, "  [", i, "] (s = ", n.len + v.len + 32, ") ", n, ": ", v, "\n");
    }
    format(out, "  size: ", t.size);
    return out;
}

fn integers() {
    var out: u8[>..] = [];
    http::hpack_int(out, 0, 5, 10);
    check::same(to_hex(out), "0a");
    out.clear();
    http::hpack_int(out, 0, 5, 1337);
    check::same(to_hex(out), "1f9a0a");
    out.clear();
    http::hpack_int(out, 0, 8, 42);
    check::same(to_hex(out), "2a");
    let v, p = http::hpack_read_int(hex("1f9a0a"), 0, 5);
    assert(v == 1337 && p == 3);
    let w, q = http::hpack_read_int(hex("2a"), 0, 8);
    assert(w == 42 && q == 1);
    // Truncated, and past HPACK_MAX_INT.
    let a, pa = http::hpack_read_int(hex("1f9a"), 0, 5);
    assert(pa == -1);
    let b, pb = http::hpack_read_int(hex("1fffffffff0f"), 0, 5);
    assert(pb == -1);
    out.clear();
    http::hpack_int(out, 0, 5, http::HPACK_MAX_INT);
    let c, pc = http::hpack_read_int(out, 0, 5);
    assert(c == http::HPACK_MAX_INT && pc == out.len);
    print("C.1 integers: 10, 1337 in 5-bit prefixes, 42 in 8 bits; truncated and too large refused");
}

fn fields() {
    let cases = [
        "400a637573746f6d2d6b65790d637573746f6d2d686561646572",
        "040c2f73616d706c652f70617468",
        "100870617373776f726406736563726574",
        "82",
    ];
    for c, i in cases {
        var t = http::hpack_table();
        print("C.2.", i + 1, ":\n", decode(t, hex(c)), table(t));
    }
}

// Decodes each block in turn through one table, which must then have the
// example's size, and where encode says, encodes the same fields through
// another, which must give the same bytes: the examples with Huffman coding
// code every literal it doesn't lengthen, as hpack_encode does.
fn connection(name: const u8[:], blocks: const u8[:][:], sizes: i64[:], limit: i64,
              encode: bool) {
    var dec = http::hpack_table(limit);
    var enc = http::hpack_table(limit);
    for b, i in blocks {
        let lines = decode(dec, hex(b));
        print(name, ".", i + 1, ":\n", lines, table(dec));
        assert(dec.size == sizes[i]);
        guard encode else { continue; }
        var out: u8[>..] = [];
        http::hpack_begin(enc, out);
        each_split(lines[..lines.len - 1], '\n') {
            let colon = find(it[1..], ":") + 1;
            http::hpack_encode(enc, out, it[..colon], it[colon + 2..]);
        };
        check::same(to_hex(out), b);
        assert(enc.size == dec.size && enc.count == dec.count);
    }
    if encode { print(name, ": encoded to the same bytes"); }
}

fn main() {
    integers();
    fields();
    connection("C.3", [
        "828684410f7777772e6578616d706c652e636f6d",
        "828684be58086e6f2d6361636865",
        "828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565",
    ], [57, 110, 164], 4096, false);
    connection("C.4", [
        "828684418cf1e3c2e5f23a6ba0ab90f4ff",
        "828684be5886a8eb10649cbf",
        "828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf",
    ], [57, 110, 164], 4096, true);
    connection("C.5", [
        "4803333032580770726976617465611d4d6f6e2c203231204f637420323031332032303a31333a323120474d546e1768747470733a2f2f7777772e6578616d706c652e636f6d",
        "4803333037c1c0bf",
        "88c1611d4d6f6e2c203231204f637420323031332032303a31333a323220474d54c05a04677a69707738666f6f3d4153444a4b48514b425a584f5157454f50495541585157454f49553b206d61782d6167653d333630303b2076657273696f6e3d31",
    ], [222, 222, 215], 256, false);
    connection("C.6", [
        "488264025885aec3771a4b6196d07abe941054d444a8200595040b8166e082a62d1bff6e919d29ad171863c78f0b97c8e9ae82ae43d3",
        "4883640effc1c0bf",
        "88c16196d07abe941054d444a8200595040b8166e084a62d1bffc05a839bd9ab77ad94e7821dd7f2e6c7b335dfdfcd5b3960d5af27087f3672c1ab270fb5291f9587316065c003ed4ee5b1063d5007",
    ], [222, 222, 215], 256, true);
}
