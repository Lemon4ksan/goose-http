// Chunked bodies: dechunk on a whole body, and read_body on one arriving in
// pieces of every size, with extensions, trailers, and the bodies refused.
import std;
import http from "../../";
import check from "../";

// The chunked body at the start of text, decoded, or its status.
fn dechunked(text: const u8[:], out: u8[>..]&) -> i32 {
    let n, s = http::chunked_len(text);
    if s == 200 {
        var buf: u8[>..] = [];
        buf.append(text[..n]);
        let k, t = http::dechunk(buf);
        out.append(buf[..k]);
    }
    return s;
}

fn test_chunked() {
    let r, s = http::parse("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: Chunked\r\n\r\n");
    assert(s == 200 && r.chunked && r.body == 0);

    var out: u8[>..] = [];
    let one = "5\r\nhello\r\n0\r\n\r\n";
    assert(dechunked(one, out) == 200);
    check::same(out, "hello");
    // Every prefix is incomplete, and what follows is left alone.
    for n in one.len { assert(dechunked(one[..n], out) == http::INCOMPLETE); }
    let n1, s1 = http::chunked_len("0\r\n\r\nGET");
    assert(s1 == 200 && n1 == 5);

    out.clear();
    assert(dechunked("3;x=y\r\nabc\r\nA\r\n0123456789\r\n0\r\nT: v\r\n\r\n", out) == 200);
    check::same(out, "abc0123456789");
    out.clear();
    assert(dechunked("1\r\n2\r\n1\r\n0\r\n0\r\n\r\n", out) == 200);
    check::same(out, "20");

    // A size that isn't hex or is too long, data longer than its size, bare
    // LFs, and control bytes in an extension.
    assert(dechunked("5x\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("\r\n", out) == 400);
    assert(dechunked("1000000000000000\r\n", out) == 400);
    assert(dechunked("2\r\nabc\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("2\nab\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("0;a\x01\r\n\r\n", out) == 400);
    // Whitespace before an extension's ';' (BWS, RFC 9112 §7.1.1), but not
    // after the size alone.
    out.clear();
    assert(dechunked("5 ;a=b\r\nhello\r\n0\r\n\r\n", out) == 200);
    check::same(out, "hello");
    assert(dechunked("5\t;a\r\nhello\r\n0 ;z\r\n\r\n", out) == 200);
    assert(dechunked("5 \r\nhello\r\n0\r\n\r\n", out) == 400);
    // Extensions: a token, an optional value, a token or a quoted string.
    assert(dechunked("1;a=\"b;\\\"c\" ; d = e\r\nx\r\n0;z\r\n\r\n", out) == 200);
    assert(dechunked("5;\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("5;bad[=x\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("5;a=\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("5;a=\"b\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("0;a \r\n\r\n", out) == 400);
    assert(dechunked("0\r\n\n", out) == 400);
    print("dechunk: whole bodies, prefixes, extensions, and 400s");
}

// Reads the chunked body at the start of text as the loops do, with text
// arriving k bytes at a time, into out. Returns the status, and how many of
// text's bytes the body took.
fn read_in_pieces(text: const u8[:], k: i64, out: u8[>..]&) -> i32, i64 {
    var r: http::BodyReader = http::BodyReader.ChunkSize;
    var buf: u8[>..] = [];
    var pos = 0;
    while r != http::BodyReader.None {
        let d0, d1, s = http::read_body(buf[pos..], r);
        if s == http::INCOMPLETE {
            guard buf.len < text.len else { return http::INCOMPLETE, pos; }
            buf.append(text[buf.len..min(buf.len + k, text.len)]);
            continue;
        }
        guard s == 200 else { return s, pos; }
        // The last run is the trailer section, not data.
        if r != http::BodyReader.None { out.append(buf[pos + d0..pos + d1]); }
        pos += d1;
    }
    return 200, pos;
}

fn test_read_body() {
    // Each body, arriving in pieces of every size, decodes as dechunk does.
    let bodies = ["5\r\nhello\r\n0\r\n\r\n", "3;x=y\r\nabc\r\nA\r\n0123456789\r\n0\r\nT: v\r\n\r\n",
                  "1\r\n2\r\n1\r\n0\r\n0\r\n\r\n", "0\r\n\r\n"];
    for b in bodies {
        var want: u8[>..] = [];
        assert(dechunked(b, want) == 200);
        for k in 1..b.len + 1 {
            var got: u8[>..] = [];
            var text: u8[>..] = [];
            text.append(b);
            text.append("GET");
            let s, n = read_in_pieces(text, k, got);
            assert(s == 200 && n == b.len);
            check::same(got, want);
        }
    }
    var got: u8[>..] = [];
    let s1, n1 = read_in_pieces("5\r\nhel", 2, got);
    assert(s1 == http::INCOMPLETE && got == "hel");
    let bad = ["5x\r\nhello\r\n0\r\n\r\n", "\r\n", "1000000000000000\r\n", "2\r\nabc\r\n0\r\n\r\n",
               "2\nab\r\n0\r\n\r\n", "0;a\x01\r\n\r\n", "5;\r\nhello\r\n0\r\n\r\n", "0\r\n\n"];
    for b in bad {
        for k in 1..b.len + 1 {
            got.clear();
            let s, n = read_in_pieces(b, k, got);
            assert(s == 400);
        }
    }
    print("read_body: ", bodies.len, " bodies and ", bad.len, " refused, in pieces of every size");

    // The trailer section comes whole, after the data, and so do a whole
    // body's trailers from dechunk.
    var rt: http::BodyReader = http::BodyReader.ChunkSize;
    let tb = "1\r\nx\r\n0\r\nT: v\r\nU: w\r\n\r\nGET";
    let a0, a1, sa = http::read_body(tb, rt);
    assert(sa == 200 && tb[a0..a1] == "x");
    let b0, b1, sb = http::read_body(tb[a1..], rt);
    assert(sb == 200 && rt == http::BodyReader.None && tb[a1 + b0..a1 + b1] == "T: v\r\nU: w\r\n\r\n");
    let tv, found = http::field_in(tb[a1 + b0..a1 + b1 - 2], "u");
    assert(found && tv == "w");
    var whole: u8[>..] = [];
    whole.append(tb[..tb.len - 3]);
    let wn, wt = http::dechunk(whole);
    assert(wn == 1 && whole[wt..whole.len - 2] == "T: v\r\nU: w\r\n");
    for b in ["0\r\nbad\r\n\r\n", "0\r\n: v\r\n\r\n", "0\r\nT: \x01\r\n\r\n"] {
        var none: u8[>..] = [];
        let s, n = read_in_pieces(b, b.len, none);
        assert(s == 400);
        assert(dechunked(b, none) == 400);
    }
    print("trailers: U is ", tv);

    // A Content-Length body ends at its length.
    var r: http::BodyReader = http::BodyReader.Length { left: 5 };
    let d0, d1, s = http::read_body("hel", r);
    let left = match r { Length l => l.left, _ => -1 };
    assert(s == 200 && d0 == 0 && d1 == 3 && left == 2);
    let e0, e1, t = http::read_body("loGET", r);
    assert(t == 200 && e1 == 2 && r == http::BodyReader.None);
    print("Content-Length body: ", left, " left after 3 of 5");
}

fn main() {
    test_chunked();
    test_read_body();
}
