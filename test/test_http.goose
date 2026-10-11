// Unit tests for the package's message.goose: the request parser, the Date
// header, and the responses. scripts/test-unit.sh runs them through TinyCC.
import std;
import http from "../";

let GET = "GET /plaintext HTTP/1.1\r\nHost: x\r\n\r\n";

// The status parse gives text.
fn status(text: const u8[:]) -> i32 {
    let r, s = http::parse(text);
    return s;
}

fn expect(text: const u8[:], want: i32) {
    let got = status(text);
    if got != want {
        print("parse of '", text, "': got ", got, ", want ", want);
        assert(false);
    }
}

fn test_parse() {
    let r, s = http::parse(GET);
    assert(s == 200);
    assert(r.method == "GET" && r.target == "/plaintext" && r.minor == 1);
    assert(r.keep_alive && r.body == 0 && r.len == GET.len);

    // Every prefix of a request is incomplete, and a pipelined request
    // after it is left alone.
    for n in GET.len { expect(GET[..n], http::INCOMPLETE); }
    var two: u8[>..] = [];
    two.append(GET);
    two.append("GET /json HTTP/1.1\r\nHost: x\r\n\r\n");
    let r2, s2 = http::parse(two);
    assert(s2 == 200 && r2.len == GET.len);
    let r3, s3 = http::parse(two[r2.len..]);
    assert(s3 == 200 && r3.target == "/json" && r3.len == two.len - GET.len);

    // Empty lines before a request are part of it.
    let r5, s5 = http::parse("\r\n\r\nGET / HTTP/1.1\r\nHost: x\r\n\r\n");
    assert(s5 == 200 && r5.method == "GET" && r5.len == 31);
    expect("\r", http::INCOMPLETE);
    expect("\r\n", http::INCOMPLETE);
    expect("\r\r\n", 400);
    expect("\n", 400);

    // Header values lose surrounding whitespace, and names their case.
    let r4, s4 = http::parse("GET / HTTP/1.1\r\nHOST:x\r\ncontent-LENGTH: \t 12 \r\n\r\n");
    assert(s4 == 200 && r4.body == 12);
}

// The handler's view of the header fields: by name, ignoring case, the first
// of a repeated one, and all of them in order.
fn test_fields() {
    let text = "GET / HTTP/1.1\r\nHost: x\r\nCookie: a=1\r\nX-Empty:\r\ncookie:\t b=2 \r\nAccept: */*\r\n\r\n";
    let r, s = http::parse(text);
    assert(s == 200);
    let v, ok = http::field_of(r, "COOKIE");
    assert(ok && v == "a=1");
    let e, has = http::field_of(r, "x-empty");
    assert(has && e.len == 0);
    let m, found = http::field_of(r, "Missing");
    assert(!found && m.len == 0);
    let h, hok = http::field_of(r, "host");
    assert(hok && h == "x");
    var names: u8[>..] = [];
    var n = 0;
    http::each_field(r) { name, value =>
        names.append(name);
        names.append("=");
        names.append(value);
        names.append(";");
        n++;
    };
    assert(n == 5);
    assert(names == "Host=x;Cookie=a=1;X-Empty=;cookie=b=2;Accept=*/*;");

    // A request without fields, in HTTP/1.0.
    let r0, s0 = http::parse("GET / HTTP/1.0\r\n\r\n");
    assert(s0 == 200 && r0.fields.len == 0);
    let x, xok = http::field_of(r0, "host");
    assert(!xok);
    var none = 0;
    http::each_field(r0) { name, value => none++; };
    assert(none == 0);
}

// Percent-decoding, and the query's pairs.
fn decoded(s: const u8[:], plus: bool = false) -> u8[>..] {
    var out: u8[>..] = [];
    assert(http::decode(s, out, plus));
    return out;
}

fn test_decode() {
    assert(decoded("/a%20b%2Fc") == "/a b/c");
    assert(decoded("%e2%82%AC") == "\xe2\x82\xac");
    assert(decoded("a+b") == "a+b");
    assert(decoded("a+b%2B", true) == "a b+");
    assert(decoded("") == "");
    var out: u8[>..] = [];
    assert(!http::decode("ab%2", out) && out == "ab");
    assert(!http::decode("%g0", out));
    assert(!http::decode("%", out));

    expect("GET /a%20b HTTP/1.1\r\nHost: x\r\n\r\n", 200);
    expect("GET /a%2 HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    expect("GET /a?b=%zz HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    expect("GET /a% HTTP/1.1\r\nHost: x\r\n\r\n", 400);

    let t = "/s?q=a+b%26c&flag&n=12&q=second&&e=";
    let q, ok = http::query_of(t, "q");
    assert(ok && q == "a+b%26c" && decoded(q, true) == "a b&c");
    let f, fok = http::query_of(t, "flag");
    assert(fok && f.len == 0);
    let e, eok = http::query_of(t, "e");
    assert(eok && e.len == 0);
    let m, mok = http::query_of(t, "missing");
    assert(!mok);
    let z, zok = http::query_of("/no-query", "q");
    assert(!zok);
    assert(http::query_int(t, "n") == 12 && http::query_int(t, "q") == 0);
    var pairs: u8[>..] = [];
    http::each_query(t) { key, value =>
        pairs.append(key);
        pairs.append("=");
        pairs.append(value);
        pairs.append(";");
    };
    assert(pairs == "q=a+b%26c;flag=;n=12;q=second;e=;");
}

// A header value scanned by find_any: each kind of byte at every offset of a
// value longer than four of its 16-byte blocks, from every alignment, so both
// the search and the byte loop after it meet it. Tab, space, visible bytes,
// and obs-text are allowed; other control bytes, a bare CR included, and DEL
// aren't.
fn test_values() {
    let kinds: u8[] = [0, 9, 13, 31, 32, 126, 127, 128, 255];
    for kind in kinds {
        let want: i32 = if kind == 9 || (kind >= 32 && kind != 127) { 200 } else { 400 };
        for shift in 32 {
            for at in 80 {
                var req: u8[>..] = [];
                req.append("GET / HTTP/1.1\r\nHost: x\r\nX");
                for i in shift { req.push('x'); }
                req.append(": ");
                for i in 80 { req.push(if i == at { kind } else { 'a' + (i % 26) as! u8 }); }
                req.append("\r\n\r\n");
                let got = status(req);
                if got != want {
                    print("byte ", kind, " at ", at, " after ", shift, ": got ", got, ", want ", want);
                    assert(false);
                }
            }
        }
    }
}

fn test_keep_alive() {
    let a, sa = http::parse("GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n");
    assert(sa == 200 && !a.keep_alive);
    let b, sb = http::parse("GET / HTTP/1.1\r\nHost: x\r\nConnection: Keep-Alive, CLOSE\r\n\r\n");
    assert(sb == 200 && !b.keep_alive);
    let c, sc = http::parse("GET / HTTP/1.0\r\n\r\n");
    assert(sc == 200 && c.minor == 0 && !c.keep_alive);
    let d, sd = http::parse("GET / HTTP/1.0\r\nConnection:  keep-alive \r\n\r\n");
    assert(sd == 200 && d.keep_alive);
    // A later 1.x is answered as 1.1.
    let e, se = http::parse("GET / HTTP/1.7\r\nHost: x\r\n\r\n");
    assert(se == 200 && e.minor == 7 && e.keep_alive);
}

fn test_refused() {
    // Malformed: a bare LF anywhere, no version, bad field syntax.
    expect("GET / HTTP/1.1\nHost: x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\n\n", 400);
    expect("GET / HTTP/1.1\n", 400);
    expect("GET /\r\n\r\n", 400);
    expect("GET\r\n\r\n", 400);
    expect("GET  / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    expect(" GET / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    expect("GET / http/1.1\r\nHost: x\r\n\r\n", 400);
    expect("GET / HTTP/1.1 \r\nHost: x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost : x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\n folded\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\n: x\r\nHost: x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nX: a\x00b\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\rX: y\r\n\r\n", 400);
    expect("GET /a\x01b HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    // Host: required once in 1.1.
    expect("GET / HTTP/1.1\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", 400);
    // Content-Length: digits only, and one value.
    expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length:\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1, 1\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nContent-Length: 3\r\n\r\n", 200);
    // Other versions, transfer codings, and the size limits.
    expect("GET / HTTP/2.0\r\nHost: x\r\n\r\n", 505);
    expect("GET / HTTP/0.9\r\nHost: x\r\n\r\n", 505);
    // Chunked must come last, once (RFC 9112 §6.3); other codings before it
    // aren't implemented.
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, gzip\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, chunked\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: \r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked;a=b\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: gzip\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, deflate , chunked\r\n\r\n", 501);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n", 501);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n", 400);
    expect("POST / HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n", 400);
    expect("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1048577\r\n\r\n", 413);
    expect("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1048576\r\n\r\n", 200);
    expect("ABCDEFGHIJKLMNOPQ / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    // A Host that isn't a uri-host and port; an empty one is allowed.
    expect("GET / HTTP/1.1\r\nHost: x:8080\r\n\r\n", 200);
    expect("GET / HTTP/1.1\r\nHost: [::1]:80\r\n\r\n", 200);
    expect("GET / HTTP/1.1\r\nHost: \r\n\r\n", 200);
    expect("GET / HTTP/1.1\r\nHost: u@x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x/a\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x, y\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: a b\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: [::1\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: [::1]x\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: x]\r\n\r\n", 400);
    expect("GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n", 200);
    // Targets other than origin-form: absolute-form, and * for OPTIONS only.
    expect("GET http://x/a HTTP/1.1\r\nHost: x\r\n\r\n", 200);
    expect("OPTIONS * HTTP/1.1\r\nHost: x\r\n\r\n", 200);
    expect("GET * HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    expect("CONNECT x:443 HTTP/1.1\r\nHost: x:443\r\n\r\n", 400);
    expect("GET a/b HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    expect("GET :// HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    assert(http::path_of("/a?b=1") == "/a");
    assert(http::path_of("http://x:80/a/b?c") == "/a/b");
    assert(http::path_of("http://x?c") == "/");
    assert(http::path_of("*") == "*");

    var line: u8[>..] = [];
    line.append("GET /");
    for i in http::MAX_LINE { line.push('a'); }
    expect(line, 414);       // before the line has ended
    line.append(" HTTP/1.1\r\nHost: x\r\n\r\n");
    expect(line, 414);
    // A request line of 8000 octets fits.
    var long: u8[>..] = [];
    long.append("GET /");
    while long.len < http::MAX_LINE - 9 { long.push('a'); }
    long.append(" HTTP/1.1\r\nHost: x\r\n\r\n");
    expect(long, 200);

    var many: u8[>..] = [];
    many.append("GET / HTTP/1.1\r\nHost: x\r\n");
    for i in http::MAX_FIELDS - 1 { many.append("A: b\r\n"); }
    var ok: u8[>..] = [];
    ok.append(many);
    ok.append("\r\n");
    expect(ok, 200);
    many.append("A: b\r\n\r\n");
    expect(many, 431);

    // A head that fills the buffer without ending can't fit.
    var big: u8[>..] = [];
    big.append("GET / HTTP/1.1\r\nHost: x\r\nX: ");
    while big.len < http::MAX_HEAD { big.push('y'); }
    expect(big[..http::MAX_HEAD - 1], http::INCOMPLETE);
    expect(big, 431);
}

fn test_date() {
    let cases = [
        0, 951782400, 951868800, 1709251199, 1791633600, 4102444799, 4107542399,
        4107542400, 253402300799,
    ];
    let want = [
        "Thu, 01 Jan 1970 00:00:00 GMT",
        "Tue, 29 Feb 2000 00:00:00 GMT",
        "Wed, 01 Mar 2000 00:00:00 GMT",
        "Thu, 29 Feb 2024 23:59:59 GMT",
        "Sat, 10 Oct 2026 12:00:00 GMT",
        "Thu, 31 Dec 2099 23:59:59 GMT",
        "Sun, 28 Feb 2100 23:59:59 GMT",
        "Mon, 01 Mar 2100 00:00:00 GMT",
        "Fri, 31 Dec 9999 23:59:59 GMT",
    ];
    for t, i in cases {
        var d: u8[..32] = [];
        http::format_date(d, t);
        if d != want[i] {
            print("date of ", t, ": got '", d, "', want '", want[i], "'");
            assert(false);
        }
    }
}

// The chunked body at the start of text, decoded, or its status.
fn dechunked(text: const u8[:], out: u8[>..]&) -> i32 {
    let n, s = http::chunked_len(text);
    if s == 200 {
        var buf: u8[>..] = [];
        buf.append(text[..n]);
        let k = http::dechunk(buf);
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
    same(out, "hello");
    // Every prefix is incomplete, and what follows is left alone.
    for n in one.len { assert(dechunked(one[..n], out) == http::INCOMPLETE); }
    let n1, s1 = http::chunked_len("0\r\n\r\nGET");
    assert(s1 == 200 && n1 == 5);

    out.clear();
    assert(dechunked("3;x=y\r\nabc\r\nA\r\n0123456789\r\n0\r\nT: v\r\n\r\n", out) == 200);
    same(out, "abc0123456789");
    out.clear();
    assert(dechunked("1\r\n2\r\n1\r\n0\r\n0\r\n\r\n", out) == 200);
    same(out, "20");

    // A size that isn't hex or is too long, data longer than its size, bare
    // LFs, and control bytes in an extension.
    assert(dechunked("5x\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("\r\n", out) == 400);
    assert(dechunked("1000000000000000\r\n", out) == 400);
    assert(dechunked("2\r\nabc\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("2\nab\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("0;a\x01\r\n\r\n", out) == 400);
    // Extensions: a token, an optional value, a token or a quoted string.
    assert(dechunked("1;a=\"b;\\\"c\" ; d = e\r\nx\r\n0;z\r\n\r\n", out) == 200);
    assert(dechunked("5;\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("5;bad[=x\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("5;a=\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("5;a=\"b\r\nhello\r\n0\r\n\r\n", out) == 400);
    assert(dechunked("0;a \r\n\r\n", out) == 400);
    assert(dechunked("0\r\n\n", out) == 400);
}

// Reads the chunked body at the start of text as the loops do, with text
// arriving k bytes at a time, into out. Returns the status, and how many of
// text's bytes the body took.
fn read_in_pieces(text: const u8[:], k: i64, out: u8[>..]&) -> i32, i64 {
    var r = http::BodyReader { place: http::CHUNK_SIZE, left: 0 };
    var buf: u8[>..] = [];
    var pos = 0;
    while r.place != http::NO_BODY {
        let d0, d1, s = http::read_body(buf[pos..], r);
        if s == http::INCOMPLETE {
            guard buf.len < text.len else { return http::INCOMPLETE, pos; }
            buf.append(text[buf.len..min(buf.len + k, text.len)]);
            continue;
        }
        guard s == 200 else { return s, pos; }
        out.append(buf[pos + d0..pos + d1]);
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
            same(got, want);
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

    // A Content-Length body ends at its length.
    var r = http::BodyReader { place: http::LENGTH, left: 5 };
    let d0, d1, s = http::read_body("hel", r);
    assert(s == 200 && d0 == 0 && d1 == 3 && r.place == http::LENGTH && r.left == 2);
    let e0, e1, t = http::read_body("loGET", r);
    assert(t == 200 && e1 == 2 && r.place == http::NO_BODY);
}

// Limits set by the caller instead of the defaults.
fn test_limits() {
    let line = "GET /0123456789 HTTP/1.1\r\nHost: x\r\nA: b\r\n\r\n";
    let r1, s1 = http::parse(line, 8192, 100, 15, 100);
    assert(s1 == 200);
    let r2, s2 = http::parse(line, 8192, 100, 14, 100);
    assert(s2 == 414);
    let r3, s3 = http::parse(line, 8192, 100, 100, 2);
    assert(s3 == 200);
    let r4, s4 = http::parse(line, 8192, 100, 100, 1);
    assert(s4 == 431);
    // The head's, where a head that the read buffer can't hold doesn't fit,
    // and the body's.
    let r5, s5 = http::parse(line[..30], 30);
    assert(s5 == 431);
    let r6, s6 = http::parse("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 101\r\n\r\n", 8192, 100);
    assert(s6 == 413);
}

fn test_expect() {
    let r, s = http::parse("POST / HTTP/1.1\r\nHost: x\r\nExpect: 100-Continue\r\nContent-Length: 5\r\n\r\n");
    assert(s == 200 && r.expect);
    expect("POST / HTTP/1.1\r\nHost: x\r\nExpect: something\r\nContent-Length: 5\r\n\r\n", 417);
    // HTTP/1.0 has no expectations.
    let r0, s0 = http::parse("POST / HTTP/1.0\r\nExpect: something\r\nContent-Length: 5\r\n\r\n");
    assert(s0 == 200 && !r0.expect);
    let rg, sg = http::parse(GET);
    assert(!rg.expect);
}

// A response begun with begin, and sent in pieces.
fn test_stream() {
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: st };
    http::begin(c, 200, -1);
    http::field(c, "Content-Type", "text/plain");
    http::send(c, "hello");
    http::send(c, "");
    http::send(c, "0123456789abcdef!");
    http::end(c);
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nTransfer-Encoding: chunked\r\nContent-Type: text/plain\r\n\r\n5\r\nhello\r\n11\r\n0123456789abcdef!\r\n0\r\n\r\n");
    assert(keep && !st.open);
    // send and end after end write nothing.
    http::send(c, "late");
    http::end(c);
    assert(out[out.len - 5..] == "0\r\n\r\n");

    // A known length; a body past it is cut, and one short of it closes.
    let m1 = out.len;
    http::begin(c, 200, 7);
    http::send(c, "abc");
    assert(keep);
    http::send(c, "defgh");
    http::end(c);
    same(out[m1..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Length: 7\r\n\r\nabcdefg");
    assert(!keep);
    let m2 = out.len;
    keep = true;
    http::begin(c, 200, 5);
    http::end(c);
    assert(!keep && out[out.len - 21..] == "Content-Length: 5\r\n\r\n");

    // HEAD gets the head alone.
    let m3 = out.len;
    keep = true;
    let h = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: true, stream: st };
    http::begin(h, 200, -1);
    http::send(h, "hello");
    http::end(h);
    same(out[m3..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nTransfer-Encoding: chunked\r\n\r\n");
    assert(keep);

    // HTTP/1.0 has no chunks: the body ends at the close.
    let m4 = out.len;
    let old = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 0, head: false, stream: st };
    http::begin(old, 200, -1);
    http::send(old, "hello");
    http::end(old);
    same(out[m4..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\n\r\nhello");
    assert(!keep);

    // 204 has no body, and no framing.
    let m5 = out.len;
    keep = true;
    http::begin(c, 204, -1);
    http::send(c, "hello");
    http::end(c);
    same(out[m5..], "HTTP/1.1 204 No Content\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\n\r\n");
    assert(keep);
}

fn test_upgrade() {
    let r, s = http::parse("GET /chat HTTP/1.1\r\nHost: x\r\nConnection: keep-alive, Upgrade\r\nUpgrade: websocket\r\n\r\n");
    assert(s == 200 && http::upgrade_of(r) == "websocket");
    // Without Connection: upgrade, and in HTTP/1.0, there's none.
    let r2, s2 = http::parse("GET /chat HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n\r\n");
    assert(s2 == 200 && http::upgrade_of(r2) == "");
    let r3, s3 = http::parse("GET /chat HTTP/1.0\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n");
    assert(s3 == 200 && http::upgrade_of(r3) == "");

    // 101, then bytes as they are, until end closes the connection.
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: st };
    http::upgrade(c, "websocket");
    http::send(c, "\x81\x00");
    same(out, "HTTP/1.1 101 Switching Protocols\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n\x81\x00");
    assert(st.open && keep);
    http::end(c);
    assert(!st.open && !keep);
}

// A small app's routes on text's request: which route took it and its
// parameters, or the response the router gave.
fn app(text: const u8[:], out: u8[>..]&) {
    let req, s = http::parse(text);
    assert(s == 200);
    var keep = true;
    var stream = http::Stream { .. };
    let reply = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: req.method == "HEAD",
                              stream: stream };
    var r = http::router(req);
    if http::on(r, "GET", "/") { out.append("root"); }
    else if http::on(r, "GET", "/users/:id") { format(out, "user ", http::param(r, "id")); }
    else if http::on(r, "PUT", "/users/:id") { format(out, "put ", http::param(r, "id")); }
    else if http::on(r, "GET", "/users/:id/posts/:post") {
        format(out, "post ", http::param(r, "id"), " ", http::param(r, "post"));
    }
    else if http::on(r, "GET", "/files/*path") { format(out, "file ", http::param(r, "path")); }
    else if http::on(r, "POST", "/upload") { out.append("upload"); }
    else { http::otherwise(r, reply); }
}

fn routes_to(text: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    app(text, out);
    same(out, want);
}

fn test_router() {
    routes_to("GET / HTTP/1.1\r\nHost: x\r\n\r\n", "root");
    routes_to("GET /users/42 HTTP/1.1\r\nHost: x\r\n\r\n", "user 42");
    routes_to("GET /users/42?x=1 HTTP/1.1\r\nHost: x\r\n\r\n", "user 42");
    routes_to("HEAD /users/42 HTTP/1.1\r\nHost: x\r\n\r\n", "user 42");
    routes_to("PUT /users/7 HTTP/1.1\r\nHost: x\r\n\r\n", "put 7");
    routes_to("GET /users/7/posts/9 HTTP/1.1\r\nHost: x\r\n\r\n", "post 7 9");
    routes_to("GET http://x/users/5 HTTP/1.1\r\nHost: x\r\n\r\n", "user 5");
    routes_to("GET /files/a/b%20c HTTP/1.1\r\nHost: x\r\n\r\n", "file a/b%20c");
    routes_to("GET /files/ HTTP/1.1\r\nHost: x\r\n\r\n", "file ");
    // A method that the path's routes don't take, OPTIONS, and no route.
    routes_to("DELETE /users/42 HTTP/1.1\r\nHost: x\r\n\r\n",
              "HTTP/1.1 405 Method Not Allowed\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nAllow: GET, HEAD, PUT\r\nContent-Length: 0\r\n\r\n");
    routes_to("OPTIONS /users/42 HTTP/1.1\r\nHost: x\r\n\r\n",
              "HTTP/1.1 204 No Content\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nAllow: GET, HEAD, PUT\r\n\r\n");
    routes_to("GET /upload HTTP/1.1\r\nHost: x\r\n\r\n",
              "HTTP/1.1 405 Method Not Allowed\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nAllow: POST\r\nContent-Length: 0\r\n\r\n");
    let missing = "HTTP/1.1 404 Not Found\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Length: 0\r\n\r\n";
    routes_to("GET /nope HTTP/1.1\r\nHost: x\r\n\r\n", missing);
    routes_to("GET /users/ HTTP/1.1\r\nHost: x\r\n\r\n", missing);
    routes_to("GET /users/1/posts HTTP/1.1\r\nHost: x\r\n\r\n", missing);
    routes_to("GET /files HTTP/1.1\r\nHost: x\r\n\r\n", missing);
    routes_to("GET //users/1 HTTP/1.1\r\nHost: x\r\n\r\n", missing);
}

let DATE = "Sat, 10 Oct 2026 12:00:00 GMT";

fn same(got: const u8[:], want: const u8[:]) {
    if got != want {
        print("got:\n", got, "\nwant:\n", want);
        assert(false);
    }
}

// A handler's writers, into a reply as the loops make one.
fn test_reply() {
    var out: u8[>..] = [];
    var keep = true;
    var nobody = http::Stream { .. };
    http::respond(http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: nobody },
                  201, "text/plain", "made");
    same(out, "HTTP/1.1 201 Created\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 4\r\n\r\nmade");

    // A field of the handler's own, a status with no reason phrase, and a
    // handler that closes the connection.
    out.clear();
    keep = false;
    let r = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: nobody };
    http::start(r, 299);
    http::field(r, "X-Thing", "a b");
    http::finish(r, "Content-Length: ", "hi");
    same(out, "HTTP/1.1 299 \r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nX-Thing: a b\r\nContent-Length: 2\r\n\r\nhi");

    // HEAD gets the body's fields without the body, and HTTP/1.0 kept alive
    // says so.
    out.clear();
    keep = true;
    http::respond(http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 0, head: true, stream: nobody },
                  200, "a/b", "body");
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: keep-alive\r\nContent-Type: a/b\r\nContent-Length: 4\r\n\r\n");

    // 1xx, 204, and 304 get neither a Content-Length nor a body, whatever
    // the handler writes, and a HEAD for one gets the same.
    let bodyless: i32[] = [204, 304, 103];
    for status in bodyless {
        out.clear();
        keep = true;
        http::respond(http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: nobody },
                      status, "text/plain", "body");
        assert(nobody.bodyless);
        assert(find(out, "Content-Length") < 0 && out[out.len - 4..] == "\r\n\r\n");
        assert(find(out, "Content-Type: text/plain\r\n\r\n") > 0);
    }
    out.clear();
    let r304 = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: true, stream: nobody };
    http::start(r304, 304);
    http::field(r304, "ETag", "\"x\"");
    http::finish(r304, "", "ignored");
    same(out, "HTTP/1.1 304 Not Modified\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nETag: \"x\"\r\n\r\n");
    // A body status after them gets its length again.
    out.clear();
    http::respond(http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: nobody },
                  200, "text/plain", "ok");
    assert(!nobody.bodyless && find(out, "Content-Length: 2\r\n\r\nok") > 0);

    // A handler clears keep_alive through its copy of the reply.
    keep = true;
    out.clear();
    let close = http::Reply { buf: out, date: DATE, keep_alive: keep, minor: 1, head: false, stream: nobody };
    close.keep_alive = false;
    assert(!keep);

    // A limited array takes responses as the server's write buffer does.
    var wbuf: u8[..256] = [];
    http::refuse(wbuf, 431, DATE);
    same(wbuf, "HTTP/1.1 431 Request Header Fields Too Large\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");

    var j: u8[>..] = [];
    http::json_string(j, "a\"b\\c\n\x01");
    same(j, "\"a\\\"b\\\\c\\u000a\\u0001\"");
}

fn main() {
    test_parse();
    test_fields();
    test_decode();
    test_values();
    test_keep_alive();
    test_refused();
    test_chunked();
    test_read_body();
    test_expect();
    test_limits();
    test_date();
    test_reply();
    test_stream();
    test_router();
    test_upgrade();
    print("test_http: ok");
}
