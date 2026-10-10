// Unit tests for src/http.goose: the request parser, the Date header, and
// the responses. scripts/test-unit.sh runs them through TinyCC.
import std;
import http;

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

// A header value scanned eight bytes at a time: each kind of byte at every
// offset of a value longer than two words, from every alignment, so both the
// word loop and the byte loop meet it. Tab, space, visible bytes, and
// obs-text are allowed; other control bytes, a bare CR included, and DEL
// aren't.
fn test_values() {
    let kinds: u8[] = [0, 9, 13, 31, 32, 126, 127, 128, 255];
    for kind in kinds {
        let want: i32 = if kind == 9 || (kind >= 32 && kind != 127) { 200 } else { 400 };
        for shift in 8 {
            for at in 20 {
                var req: u8[>..] = [];
                req.append("GET / HTTP/1.1\r\nHost: x\r\nX");
                for i in shift { req.push('x'); }
                req.append(": ");
                for i in 20 { req.push(if i == at { kind } else { 'a' + (i % 26) as! u8 }); }
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
    expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n", 501);
    expect("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1048577\r\n\r\n", 413);
    expect("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1048576\r\n\r\n", 200);
    expect("ABCDEFGHIJKLMNOPQ / HTTP/1.1\r\nHost: x\r\n\r\n", 400);

    var line: u8[>..] = [];
    line.append("GET /");
    for i in http::MAX_LINE { line.push('a'); }
    expect(line, 414);       // before the line has ended
    line.append(" HTTP/1.1\r\nHost: x\r\n\r\n");
    expect(line, 414);

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

let DATE = "Sat, 10 Oct 2026 12:00:00 GMT";

// The response respond writes for a request.
fn response(text: const u8[:], out: u8[>..]&) -> bool {
    let r, s = http::parse(text);
    assert(s == 200);
    return http::respond(out, r, DATE);
}

fn same(got: const u8[:], want: const u8[:]) {
    if got != want {
        print("got:\n", got, "\nwant:\n", want);
        assert(false);
    }
}

fn test_respond() {
    var out: u8[>..] = [];
    assert(response(GET, out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!");

    out.clear();
    assert(response("GET /json?x=1 HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: application/json\r\nContent-Length: 27\r\n\r\n{\"message\":\"Hello, World!\"}");

    out.clear();
    assert(response("HEAD /plaintext HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\n");

    out.clear();
    assert(!response("GET /nope HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n", out));
    same(out, "HTTP/1.1 404 Not Found\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");

    out.clear();
    assert(response("POST /json HTTP/1.0\r\nConnection: keep-alive\r\nContent-Length: 2\r\n\r\n", out));
    same(out, "HTTP/1.1 405 Method Not Allowed\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: keep-alive\r\nAllow: GET, HEAD\r\nContent-Length: 0\r\n\r\n");

    // A limited array takes responses as the server's write buffer does.
    var wbuf: u8[..http::MAX_RESPONSE] = [];
    http::refuse(wbuf, 431, DATE);
    same(wbuf, "HTTP/1.1 431 Request Header Fields Too Large\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");

    var j: u8[>..] = [];
    http::json_string(j, "a\"b\\c\n\x01");
    same(j, "\"a\\\"b\\\\c\\u000a\\u0001\"");
}

fn main() {
    test_parse();
    test_values();
    test_keep_alive();
    test_refused();
    test_date();
    test_respond();
    print("test_http: ok");
}
