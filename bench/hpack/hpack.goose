// HPACK's cost alone: an h2load request's field block decoded, first on a
// connection and then as a later one names it by index; a JSON response's
// fields encoded, the same two ways; and Huffman coding of a 1 KB cookie.
// Each runs N times, best of 5, and prints nanoseconds per operation.
import std;
import os;
import http;

let N = 1000000;

// The best of 5 runs of N calls of F, or as many as make N * 16 units of
// per each, in ns per unit; F returns a number that the total keeps live.
fn best<F>(name: const u8[:], unit: const u8[:], per: i64) {
    let calls = if per == 1 { N } else { N * 16 / per };
    var best_ns = 0;
    var keep = 0;
    for run in 5 {
        let t0 = clock_ns();
        for i in calls { keep += F(); }
        let ns = clock_ns() - t0;
        if run == 0 || ns < best_ns { best_ns = ns; }
    }
    let x100 = best_ns * 100 / (calls * per);
    var line: u8[>..] = [];
    format(line, name, "\t");
    format_int(line, x100 / 100, 10, 1, ' ');
    line.push('.');
    format_int(line, x100 % 100, 10, 2, '0');
    format(line, "\t", unit, "\t(", keep % 10, ")");
    print(line);
}

// Empties t, as a new connection's table is, without writing its 9 KB.
fn fresh(t: http::HpackTable&) {
    http::hpack_resize(t, 0);
    http::hpack_resize(t, http::HPACK_TABLE_SIZE);
}

fn main() {
    // What h2load sends for a GET of /, as nghttp2 codes it: each literal
    // with incremental indexing, Huffman-coded.
    var enc = http::hpack_table();
    var first: u8[>..] = [];
    var later: u8[>..] = [];
    fn request(out: u8[>..]&) {
        http::hpack_encode(enc, out, ":method", "GET");
        http::hpack_encode(enc, out, ":path", "/");
        http::hpack_encode(enc, out, ":scheme", "http");
        http::hpack_encode(enc, out, ":authority", "127.0.0.1:8082");
        http::hpack_encode(enc, out, "accept", "*/*");
        http::hpack_encode(enc, out, "accept-encoding", "gzip, deflate");
        http::hpack_encode(enc, out, "user-agent", "h2load nghttp2/1.64.0");
    }
    request(first);
    request(later);
    print("request blocks: ", first.len, " bytes first, ", later.len, " bytes later");
    print("case\tns\tper\t(check)");

    var dec = http::hpack_table();
    var scratch: u8[>..] = [];
    best("decode request, first", "block", 1) {
        fresh(dec);
        scratch.clear();
        var n = 0;
        let ok = http::hpack_decode(dec, first, scratch) { name, value => n += value.len; };
        n
    };
    fresh(dec);
    scratch.clear();
    let ok = http::hpack_decode(dec, first, scratch) { name, value => };
    best("decode request, later", "block", 1) {
        scratch.clear();
        var n = 0;
        let ok = http::hpack_decode(dec, later, scratch) { name, value => n += value.len; };
        n
    };

    var renc = http::hpack_table();
    var out: u8[>..] = [];
    fn response() -> i64 {
        out.clear();
        http::hpack_encode(renc, out, ":status", "200");
        http::hpack_encode(renc, out, "content-type", "application/json");
        http::hpack_encode(renc, out, "content-length", "27");
        http::hpack_encode(renc, out, "date", "Mon, 19 Oct 2026 12:00:00 GMT");
        http::hpack_encode(renc, out, "server", "goose");
        return out.len;
    }
    best("encode response, first", "block", 1) {
        fresh(renc);
        response()
    };
    best("encode response, later", "block", 1) { response() };

    var cookie: u8[>..] = [];
    var r = rng { 3 };
    let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789=;%-_ ";
    for i in 1024 { cookie.push(alphabet[r.rand_int(alphabet.len)]); }
    var coded: u8[>..] = [];
    http::hpack_huffman(coded, cookie);
    var back: u8[>..] = [];
    best("Huffman decode, 1 KB", "byte", cookie.len) {
        back.clear();
        let ok = http::hpack_unhuffman(back, coded);
        back.len
    };
    best("Huffman encode, 1 KB", "byte", cookie.len) {
        back.clear();
        http::hpack_huffman(back, cookie);
        back.len
    };
}
