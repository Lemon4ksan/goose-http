// HPACK, HTTP/2's header compression (RFC 7541), on bytes alone: integers and
// strings, the static table, a dynamic table with its size updates, Huffman
// decoding and encoding, and a whole field block decoded or a field encoded.
// Nothing here makes a system call or needs another of the package's files. A
// program that imports it declares nothing more than http:
//
//   import http from "github.com/kaitk/goose-http@<tag>";
//   import http.hpack;
//
// One HpackTable per direction of a connection: the decoder's, which the
// peer's encoder fills, and the encoder's, which this side's fills.
//
//   var scratch: u8[>..] = [];
//   let ok = http::hpack_decode(dec, fb, scratch) { name, value => ... };
//   http::hpack_begin(enc, out);
//   http::hpack_encode(enc, out, ":status", "200");
namespace http;

import std;
import dictionary;

// The most a table holds (§4.1): SETTINGS_HEADER_TABLE_SIZE's initial value,
// and the most this side advertises or takes from a peer, so a table is a
// flat value of fixed size, 9 KB.
let HPACK_TABLE_SIZE = 4096;
// What each entry adds to its name and value (§4.1), and so the most entries
// a table of HPACK_TABLE_SIZE holds.
let HPACK_ENTRY_OVERHEAD = 32;
let HPACK_MAX_ENTRIES = 128;
// The entries' bytes take twice the table's size, so that the live ones move
// to the front at most once per HPACK_TABLE_SIZE bytes added.
let HPACK_TABLE_BYTES = 8192;
let HPACK_STATIC_COUNT = 61;
// The largest integer a block may carry (§5.1 sets none). A length or an
// index beyond it can't fit in a frame anyway.
let HPACK_MAX_INT = 0x7fffffff;

// How hpack_encode writes a field that isn't in a table whole (§6.2):
// with incremental indexing, so that a later block can name it by index;
// without; or never indexed, which an intermediary must keep, for values such
// as cookies and credentials.
let HPACK_INDEX = 0;
let HPACK_NO_INDEX = 1;
let HPACK_NEVER_INDEX = 2;

struct HpackEntry { at: u16, name: u16, value: u16 }

// A dynamic table (§2.3.2, §4). Entries' bytes lie in data in the order they
// were added, the oldest at start; ents is a ring of them, the oldest at first.
struct HpackTable {
    // The table's maximum size (§4.2), which a size update sets, and the most
    // an update may set: SETTINGS_HEADER_TABLE_SIZE, this side's for a
    // decoder, the peer's for an encoder.
    max: i64 = HPACK_TABLE_SIZE,
    limit: i64 = HPACK_TABLE_SIZE,
    size: i64 = 0,
    // An encoder's max changed since its last block, so hpack_begin writes a
    // size update; low is the smallest it went to in between (§4.2).
    update: bool = false,
    low: i64 = HPACK_TABLE_SIZE,
    first: i64 = 0,
    count: i64 = 0,
    start: i64 = 0,
    end: i64 = 0,
    ents: HpackEntry[HPACK_MAX_ENTRIES],
    data: u8[HPACK_TABLE_BYTES],
}

struct HpackStatic { name: const u8[:], value: const u8[:] }

// The static table (Appendix A), from index 1.
let HPACK_STATIC: HpackStatic[HPACK_STATIC_COUNT] = [
    HpackStatic { ":authority", "" },
    HpackStatic { ":method", "GET" },
    HpackStatic { ":method", "POST" },
    HpackStatic { ":path", "/" },
    HpackStatic { ":path", "/index.html" },
    HpackStatic { ":scheme", "http" },
    HpackStatic { ":scheme", "https" },
    HpackStatic { ":status", "200" },
    HpackStatic { ":status", "204" },
    HpackStatic { ":status", "206" },
    HpackStatic { ":status", "304" },
    HpackStatic { ":status", "400" },
    HpackStatic { ":status", "404" },
    HpackStatic { ":status", "500" },
    HpackStatic { "accept-charset", "" },
    HpackStatic { "accept-encoding", "gzip, deflate" },
    HpackStatic { "accept-language", "" },
    HpackStatic { "accept-ranges", "" },
    HpackStatic { "accept", "" },
    HpackStatic { "access-control-allow-origin", "" },
    HpackStatic { "age", "" },
    HpackStatic { "allow", "" },
    HpackStatic { "authorization", "" },
    HpackStatic { "cache-control", "" },
    HpackStatic { "content-disposition", "" },
    HpackStatic { "content-encoding", "" },
    HpackStatic { "content-language", "" },
    HpackStatic { "content-length", "" },
    HpackStatic { "content-location", "" },
    HpackStatic { "content-range", "" },
    HpackStatic { "content-type", "" },
    HpackStatic { "cookie", "" },
    HpackStatic { "date", "" },
    HpackStatic { "etag", "" },
    HpackStatic { "expect", "" },
    HpackStatic { "expires", "" },
    HpackStatic { "from", "" },
    HpackStatic { "host", "" },
    HpackStatic { "if-match", "" },
    HpackStatic { "if-modified-since", "" },
    HpackStatic { "if-none-match", "" },
    HpackStatic { "if-range", "" },
    HpackStatic { "if-unmodified-since", "" },
    HpackStatic { "last-modified", "" },
    HpackStatic { "link", "" },
    HpackStatic { "location", "" },
    HpackStatic { "max-forwards", "" },
    HpackStatic { "proxy-authenticate", "" },
    HpackStatic { "proxy-authorization", "" },
    HpackStatic { "range", "" },
    HpackStatic { "referer", "" },
    HpackStatic { "refresh", "" },
    HpackStatic { "retry-after", "" },
    HpackStatic { "server", "" },
    HpackStatic { "set-cookie", "" },
    HpackStatic { "strict-transport-security", "" },
    HpackStatic { "transfer-encoding", "" },
    HpackStatic { "user-agent", "" },
    HpackStatic { "vary", "" },
    HpackStatic { "via", "" },
    HpackStatic { "www-authenticate", "" },
];

// A table for a decoder that advertised SETTINGS_HEADER_TABLE_SIZE limit, or
// an encoder whose peer did, up to HPACK_TABLE_SIZE.
fn hpack_table(limit: i64 = HPACK_TABLE_SIZE) -> HpackTable {
    let l = clamp(limit, 0, HPACK_TABLE_SIZE);
    return HpackTable { max: l, limit: l, .. };
}

// The name and value of dynamic entry i, from 1, the newest (§2.3.3). They
// point into t, and stay only until t next changes.
fn hpack_entry(t: const HpackTable&, i: i64) -> const u8[:], const u8[:] {
    let e = t.ents[(t.first + t.count - i) % HPACK_MAX_ENTRIES];
    let at: i64 = e.at;
    let mid = at + e.name;
    return t.data[at..mid], t.data[mid..mid + e.value];
}

// Drops the oldest entry.
fn hpack_evict(t: HpackTable&) {
    let e = t.ents[t.first];
    t.size -= HPACK_ENTRY_OVERHEAD + e.name + e.value;
    t.first = (t.first + 1) % HPACK_MAX_ENTRIES;
    t.count--;
    if t.count == 0 {
        t.start = 0;
        t.end = 0;
    } else {
        t.start = t.ents[t.first].at;
    }
}

// Sets the table's maximum size, evicting the oldest entries that no longer
// fit (§4.3).
fn hpack_resize(t: HpackTable&, max: i64) {
    t.max = max;
    while t.size > t.max { hpack_evict(t); }
}

// Adds name and value as the newest entry, evicting what it needs room from
// (§4.4). An entry larger than the table empties it and isn't added. The
// name may be one of t's own entries' (named), which the eviction or the move
// to the front can overwrite, so it's copied first then.
fn hpack_add(t: HpackTable&, name: const u8[:], value: const u8[:], named: bool) {
    if named {
        var held: u8[..HPACK_TABLE_SIZE] = [];
        held.append(name);
        hpack_put(t, held, value);
    } else {
        hpack_put(t, name, value);
    }
}

fn hpack_put(t: HpackTable&, name: const u8[:], value: const u8[:]) {
    let need = HPACK_ENTRY_OVERHEAD + name.len + value.len;
    if need > t.max {
        while t.count > 0 { hpack_evict(t); }
        return;
    }
    while t.size + need > t.max { hpack_evict(t); }
    let bytes = name.len + value.len;
    if t.end + bytes > HPACK_TABLE_BYTES {
        let live = t.end - t.start;
        copy_into(t.data[0..live], t.data[t.start..t.end]);
        for k in t.count {
            let j = (t.first + k) % HPACK_MAX_ENTRIES;
            t.ents[j].at = (t.ents[j].at - t.start) as u16;
        }
        t.start = 0;
        t.end = live;
    }
    let at = t.end;
    copy_into(t.data[at..at + name.len], name);
    copy_into(t.data[at + name.len..at + bytes], value);
    t.end = at + bytes;
    t.ents[(t.first + t.count) % HPACK_MAX_ENTRIES] =
        HpackEntry { at: at as u16, name: name.len as u16, value: value.len as u16 };
    t.count++;
    t.size += need;
}

// Appends value as an integer with an n-bit prefix (§5.1), the bits above
// the prefix in the first byte taken from flags.
fn hpack_int(out: u8[>..]&, flags: u8, n: i64, value: i64) {
    let cap = (1 << n) - 1;
    if value < cap {
        out.push(flags | value as! u8);
        return;
    }
    out.push(flags | cap as! u8);
    var v = value - cap;
    while v >= 128 {
        out.push((v % 128 + 128) as! u8);
        v = v / 128;
    }
    out.push(v as! u8);
}

// The integer with an n-bit prefix at buf[pos], and the position after it;
// -1 for the position where it's truncated or exceeds HPACK_MAX_INT.
fn hpack_read_int(buf: const u8[:], pos: i64, n: i64) -> i64, i64 {
    guard pos < buf.len else { return 0, -1; }
    let cap = (1 << n) - 1;
    var v: i64 = buf[pos] & cap;
    var p = pos + 1;
    if v < cap { return v, p; }
    var shift = 0;
    loop {
        guard p < buf.len && shift <= 28 else { return 0, -1; }
        let b = buf[p];
        p++;
        v += ((b & 0x7f) as i64) << shift;
        guard v <= HPACK_MAX_INT else { return 0, -1; }
        if b < 128 { return v, p; }
        shift += 7;
    }
}

// The length of s Huffman-coded (§5.2), in bytes.
fn hpack_huffman_len(s: const u8[:]) -> i64 {
    var bits = 0;
    for c in s { bits += HPACK_HUFF_LENS[c]; }
    return (bits + 7) / 8;
}

// Appends s Huffman-coded, padded with the most significant bits of EOS.
fn hpack_huffman(out: u8[>..]&, s: const u8[:]) {
    var acc: u64 = 0;
    var bits = 0;
    for c in s {
        let len = HPACK_HUFF_LENS[c];
        acc = (acc << len) | HPACK_HUFF_CODES[c];
        bits += len;
        while bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as! u8);
        }
    }
    if bits > 0 {
        out.push(((acc << (8 - bits)) | (0xff >> bits)) as! u8);
    }
}

// Huffman decoding goes four bits at a time through a table built from the
// code (after nghttp2's): a state is a node of the code's tree, and each of
// its 16 steps says where four more bits lead, and the symbol they finish, if
// any. No code is shorter than 5 bits, so a step finishes at most one.
struct HpackStep { next: u8, sym: u8, flags: u8 }

// The step finishes sym; ends where the input may end, at the root or within
// at most 7 bits of EOS's leading ones (§5.2); or reaches EOS, an error.
let HPACK_EMIT: u8 = 1;
let HPACK_ACCEPT: u8 = 2;
let HPACK_FAIL: u8 = 4;

fn hpack_huffman_steps() -> HpackStep[4096] {
    // The tree: node k's children at kids[2k] and kids[2k + 1], a node's
    // index, or -1 - sym for a leaf. 257 leaves make 256 nodes.
    var kids = [0; 512];
    var accept = [false; 256];
    var nodes = 1;
    accept[0] = true;
    for sym in 257 {
        let len: i64 = HPACK_HUFF_LENS[sym];
        let code: i64 = HPACK_HUFF_CODES[sym];
        var node = 0;
        var ones = true;
        for d in len {
            let bit = (code >> (len - 1 - d)) & 1;
            ones = ones && bit == 1;
            let slot = node * 2 + bit;
            if d == len - 1 {
                kids[slot] = -1 - sym;
            } else {
                if kids[slot] == 0 {
                    kids[slot] = nodes;
                    accept[nodes] = ones && d < 7;
                    nodes++;
                }
                node = kids[slot];
            }
        }
    }
    assert(nodes == 256);
    var steps: HpackStep[4096] = [HpackStep { 0, 0, 0 }; 4096];
    for state in 256 {
        for nib in 16 {
            var node = state;
            var step = HpackStep { 0, 0, 0 };
            for b in 4 {
                let k = kids[node * 2 + ((nib >> (3 - b)) & 1)];
                if k >= 0 {
                    node = k;
                } else if k == -257 {
                    step.flags |= HPACK_FAIL;
                    node = 0;
                } else {
                    step.flags |= HPACK_EMIT;
                    step.sym = (-1 - k) as u8;
                    node = 0;
                }
            }
            step.next = node as u8;
            if accept[node] { step.flags |= HPACK_ACCEPT; }
            steps[state * 16 + nib] = step;
        }
    }
    return steps;
}

// Appends the Huffman-coded s decoded; false where it holds EOS or ends
// other than in at most 7 bits of padding.
fn hpack_unhuffman(out: u8[>..]&, s: const u8[:]) -> bool {
    var state = 0;
    var flags = HPACK_ACCEPT;
    for c in s {
        let hi = HPACK_HUFF_STEPS[state * 16 + (c >> 4)];
        if hi.flags & HPACK_EMIT != 0 { out.push(hi.sym); }
        let lo = HPACK_HUFF_STEPS[(hi.next as i64) * 16 + (c & 15)];
        if lo.flags & HPACK_EMIT != 0 { out.push(lo.sym); }
        guard (hi.flags | lo.flags) & HPACK_FAIL == 0 else { return false; }
        state = lo.next;
        flags = lo.flags;
    }
    return flags & HPACK_ACCEPT != 0;
}

// Appends s as a string literal (§5.2), Huffman-coded unless that's longer,
// as RFC 7541's examples are.
fn hpack_string(out: u8[>..]&, s: const u8[:]) {
    let h = hpack_huffman_len(s);
    if h <= s.len {
        hpack_int(out, 0x80, 7, h);
        hpack_huffman(out, s);
    } else {
        hpack_int(out, 0, 7, s.len);
        out.append(s);
    }
}

// Decodes a field block (RFC 9113 §4.3), the fragments of a HEADERS frame
// and its CONTINUATIONs joined, through t, calling F(name, value) for each
// field in order. Names and values point into fb, t, the static table, or
// scratch, which takes the Huffman-coded strings, and stay only until the call
// returns. Returns false for a COMPRESSION_ERROR, after which t is no longer
// in step with the peer's encoder, so the connection must end.
fn hpack_decode<F>(t: HpackTable&, fb: const u8[:], scratch: u8[>..]&) -> bool {
    var pos = 0;
    var fields = false;

    // The string literal at pos, or false.
    fn string() -> const u8[:], bool {
        guard pos < fb.len else { return "", false; }
        let huff = fb[pos] >= 0x80;
        let len, p = hpack_read_int(fb, pos, 7);
        guard p >= 0 && len <= fb.len - p else { return "", false; }
        pos = p + len;
        let raw = fb[p..pos];
        if !huff { return raw, true; }
        let mark = scratch.len;
        guard hpack_unhuffman(scratch, raw) else { return "", false; }
        return scratch[mark..], true;
    }

    // Entry i of the static and dynamic tables' index space (§2.3.3).
    fn entry(i: i64) -> const u8[:], const u8[:], bool {
        if i >= 1 && i <= HPACK_STATIC_COUNT {
            let s = HPACK_STATIC[i - 1];
            return s.name, s.value, true;
        }
        guard i > HPACK_STATIC_COUNT && i <= HPACK_STATIC_COUNT + t.count else { return "", "", false; }
        let n, v = hpack_entry(t, i - HPACK_STATIC_COUNT);
        return n, v, true;
    }

    // The value of a literal named name, and the field to t where add says.
    fn literal(name: const u8[:], add: bool, named: bool) -> bool {
        let value, ok = string();
        guard ok else { return false; }
        F(name, value);
        fields = true;
        if add { hpack_add(t, name, value, named); }
        return true;
    }

    while pos < fb.len {
        let b = fb[pos];
        if b >= 0x80 {
            // An indexed field (§6.1).
            let i, p = hpack_read_int(fb, pos, 7);
            guard p >= 0 else { return false; }
            pos = p;
            let n, v, ok = entry(i);
            guard ok else { return false; }
            F(n, v);
            fields = true;
        } else if b >= 0x40 || b < 0x20 {
            // A literal (§6.2): with incremental indexing under a 6-bit
            // index, else without or never indexed under a 4-bit one.
            let add = b >= 0x40;
            let i, p = hpack_read_int(fb, pos, if add { 6 } else { 4 });
            guard p >= 0 else { return false; }
            pos = p;
            if i > 0 {
                let n, v, ok = entry(i);
                guard ok && literal(n, add, i > HPACK_STATIC_COUNT) else { return false; }
            } else {
                let n, ok = string();
                guard ok && literal(n, add, false) else { return false; }
            }
        } else {
            // A dynamic table size update (§6.3), only before the block's
            // first field (§4.2), and no larger than the limit.
            guard !fields else { return false; }
            let max, p = hpack_read_int(fb, pos, 5);
            guard p >= 0 && max <= t.limit else { return false; }
            pos = p;
            hpack_resize(t, max);
        }
    }
    return true;
}

// Sets the most the peer lets an encoder's table take, from its
// SETTINGS_HEADER_TABLE_SIZE, up to HPACK_TABLE_SIZE, and sizes the table to
// it, which the next block's hpack_begin signals.
fn hpack_limit(t: HpackTable&, limit: i64) {
    t.limit = clamp(limit, 0, HPACK_TABLE_SIZE);
    guard t.limit != t.max;
    t.low = min(t.low, t.limit);
    hpack_resize(t, t.limit);
    t.update = true;
}

// Starts an encoder's header block: writes the size updates owed since the
// last one (§4.2), the smallest size first, then the current one.
fn hpack_begin(t: HpackTable&, out: u8[>..]&) {
    guard t.update;
    if t.low < t.max { hpack_int(out, 0x20, 5, t.low); }
    hpack_int(out, 0x20, 5, t.max);
    t.update = false;
    t.low = HPACK_TABLE_SIZE;
}

// Index of the entry with name and value, and of the first with name alone,
// in the static and dynamic tables' index space; 0 where there's none.
fn hpack_find(t: const HpackTable&, name: const u8[:], value: const u8[:]) -> i64, i64 {
    var named = 0;
    let first = HPACK_STATIC_NAMES.get(name);
    if first {
        named = first;
        // A name's entries in the static table are next to each other.
        for k in first - 1..HPACK_STATIC_COUNT {
            let s = HPACK_STATIC[k];
            guard s.name == name else { break; }
            if s.value == value { return k + 1, named; }
        }
    }
    for i in 1..t.count + 1 {
        let e = t.ents[(t.first + t.count - i) % HPACK_MAX_ENTRIES];
        guard e.name == name.len else { continue; }
        let n, v = hpack_entry(t, i);
        if n == name {
            if v == value { return HPACK_STATIC_COUNT + i, named; }
            if named == 0 { named = HPACK_STATIC_COUNT + i; }
        }
    }
    return 0, named;
}

// Each name of the static table, and its first index.
let HPACK_STATIC_NAMES = hpack_static_names();

fn hpack_static_names() -> dictionary<const u8[:], i64> {
    var d = dictionary<const u8[:], i64> {};
    for s, k in HPACK_STATIC {
        if !d.contains(s.name) { d.insert(s.name, k + 1); }
    }
    return d;
}

// Appends the field name: value through the encoder's table t: as an index
// where a table holds it whole, else as a literal written as how says (one
// of HPACK_INDEX, HPACK_NO_INDEX, HPACK_NEVER_INDEX), naming the name by index
// where a table holds it. A name must be lowercase (RFC 9113 §8.2.1).
fn hpack_encode(t: HpackTable&, out: u8[>..]&, name: const u8[:], value: const u8[:],
                how: i64 = HPACK_INDEX) {
    let whole, named = hpack_find(t, name, value);
    if whole > 0 && how != HPACK_NEVER_INDEX {
        hpack_int(out, 0x80, 7, whole);
        return;
    }
    let add = how == HPACK_INDEX;
    if add {
        hpack_int(out, 0x40, 6, named);
    } else {
        hpack_int(out, if how == HPACK_NEVER_INDEX { 0x10 } else { 0 }, 4, named);
    }
    if named == 0 { hpack_string(out, name); }
    hpack_string(out, value);
    if add { hpack_add(t, name, value, false); }
}

// Huffman code of each byte, and EOS at 256, right-aligned (Appendix B),
// and its length in bits.
let HPACK_HUFF_CODES: u32[257] = [
    0x1ff8, 0x7fffd8, 0xfffffe2, 0xfffffe3, 0xfffffe4, 0xfffffe5, 0xfffffe6, 0xfffffe7,
    0xfffffe8, 0xffffea, 0x3ffffffc, 0xfffffe9, 0xfffffea, 0x3ffffffd, 0xfffffeb, 0xfffffec,
    0xfffffed, 0xfffffee, 0xfffffef, 0xffffff0, 0xffffff1, 0xffffff2, 0x3ffffffe, 0xffffff3,
    0xffffff4, 0xffffff5, 0xffffff6, 0xffffff7, 0xffffff8, 0xffffff9, 0xffffffa, 0xffffffb,
    0x14, 0x3f8, 0x3f9, 0xffa, 0x1ff9, 0x15, 0xf8, 0x7fa,
    0x3fa, 0x3fb, 0xf9, 0x7fb, 0xfa, 0x16, 0x17, 0x18,
    0x0, 0x1, 0x2, 0x19, 0x1a, 0x1b, 0x1c, 0x1d,
    0x1e, 0x1f, 0x5c, 0xfb, 0x7ffc, 0x20, 0xffb, 0x3fc,
    0x1ffa, 0x21, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62,
    0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a,
    0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72,
    0xfc, 0x73, 0xfd, 0x1ffb, 0x7fff0, 0x1ffc, 0x3ffc, 0x22,
    0x7ffd, 0x3, 0x23, 0x4, 0x24, 0x5, 0x25, 0x26,
    0x27, 0x6, 0x74, 0x75, 0x28, 0x29, 0x2a, 0x7,
    0x2b, 0x76, 0x2c, 0x8, 0x9, 0x2d, 0x77, 0x78,
    0x79, 0x7a, 0x7b, 0x7ffe, 0x7fc, 0x3ffd, 0x1ffd, 0xffffffc,
    0xfffe6, 0x3fffd2, 0xfffe7, 0xfffe8, 0x3fffd3, 0x3fffd4, 0x3fffd5, 0x7fffd9,
    0x3fffd6, 0x7fffda, 0x7fffdb, 0x7fffdc, 0x7fffdd, 0x7fffde, 0xffffeb, 0x7fffdf,
    0xffffec, 0xffffed, 0x3fffd7, 0x7fffe0, 0xffffee, 0x7fffe1, 0x7fffe2, 0x7fffe3,
    0x7fffe4, 0x1fffdc, 0x3fffd8, 0x7fffe5, 0x3fffd9, 0x7fffe6, 0x7fffe7, 0xffffef,
    0x3fffda, 0x1fffdd, 0xfffe9, 0x3fffdb, 0x3fffdc, 0x7fffe8, 0x7fffe9, 0x1fffde,
    0x7fffea, 0x3fffdd, 0x3fffde, 0xfffff0, 0x1fffdf, 0x3fffdf, 0x7fffeb, 0x7fffec,
    0x1fffe0, 0x1fffe1, 0x3fffe0, 0x1fffe2, 0x7fffed, 0x3fffe1, 0x7fffee, 0x7fffef,
    0xfffea, 0x3fffe2, 0x3fffe3, 0x3fffe4, 0x7ffff0, 0x3fffe5, 0x3fffe6, 0x7ffff1,
    0x3ffffe0, 0x3ffffe1, 0xfffeb, 0x7fff1, 0x3fffe7, 0x7ffff2, 0x3fffe8, 0x1ffffec,
    0x3ffffe2, 0x3ffffe3, 0x3ffffe4, 0x7ffffde, 0x7ffffdf, 0x3ffffe5, 0xfffff1, 0x1ffffed,
    0x7fff2, 0x1fffe3, 0x3ffffe6, 0x7ffffe0, 0x7ffffe1, 0x3ffffe7, 0x7ffffe2, 0xfffff2,
    0x1fffe4, 0x1fffe5, 0x3ffffe8, 0x3ffffe9, 0xffffffd, 0x7ffffe3, 0x7ffffe4, 0x7ffffe5,
    0xfffec, 0xfffff3, 0xfffed, 0x1fffe6, 0x3fffe9, 0x1fffe7, 0x1fffe8, 0x7ffff3,
    0x3fffea, 0x3fffeb, 0x1ffffee, 0x1ffffef, 0xfffff4, 0xfffff5, 0x3ffffea, 0x7ffff4,
    0x3ffffeb, 0x7ffffe6, 0x3ffffec, 0x3ffffed, 0x7ffffe7, 0x7ffffe8, 0x7ffffe9, 0x7ffffea,
    0x7ffffeb, 0xffffffe, 0x7ffffec, 0x7ffffed, 0x7ffffee, 0x7ffffef, 0x7fffff0, 0x3ffffee,
    0x3fffffff,
];
let HPACK_HUFF_LENS: u8[257] = [
    13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28,
    28, 28, 28, 28, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    6, 10, 10, 12, 13, 6, 8, 11, 10, 10, 8, 11, 8, 6, 6, 6,
    5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 8, 15, 6, 12, 10,
    13, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 8, 7, 8, 13, 19, 13, 14, 6,
    15, 5, 6, 5, 6, 5, 6, 6, 6, 5, 7, 7, 6, 6, 6, 5,
    6, 7, 6, 5, 5, 6, 7, 7, 7, 7, 7, 15, 11, 14, 13, 28,
    20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23, 23, 23, 23, 24, 23,
    24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23, 24,
    22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23,
    21, 21, 22, 21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23,
    26, 26, 20, 19, 22, 23, 22, 25, 26, 26, 26, 27, 27, 26, 24, 25,
    19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26, 26, 28, 27, 27, 27,
    20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26, 23,
    26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26,
    30,
];

// After the code it's built from, as globals initialize in order.
let HPACK_HUFF_STEPS = hpack_huffman_steps();
