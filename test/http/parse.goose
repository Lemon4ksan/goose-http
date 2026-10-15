// The request parser (message.goose): a request and its prefixes, pipelining,
// the fields a handler sees, keep-alive, Expect, and limits set by the caller.
import std;
import http from "../../";
import check from "../";

let GET = "GET /plaintext HTTP/1.1\r\nHost: x\r\n\r\n";

fn test_parse() {
    let r, s = http::parse(GET);
    assert(s == 200);
    assert(r.method == "GET" && r.target == "/plaintext" && r.minor == 1);
    assert(r.keep_alive && r.body == 0 && r.len == GET.len);

    // Every prefix of a request is incomplete, and a pipelined request
    // after it is left alone.
    for n in GET.len { check::expect(GET[..n], http::INCOMPLETE); }
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
    check::expect("\r", http::INCOMPLETE);
    check::expect("\r\n", http::INCOMPLETE);
    check::expect("\r\r\n", 400);
    check::expect("\n", 400);

    // Header values lose surrounding whitespace, and names their case.
    let r4, s4 = http::parse("GET / HTTP/1.1\r\nHOST:x\r\ncontent-LENGTH: \t 12 \r\n\r\n");
    assert(s4 == 200 && r4.body == 12);
    print("parse: a request, its ", GET.len, " prefixes, pipelining, empty lines before it, field case");
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
    print("fields: ", names);
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
    print("keep-alive: Connection close and keep-alive, HTTP/1.0, HTTP/1.7");
}

fn test_expect() {
    let r, s = http::parse("POST / HTTP/1.1\r\nHost: x\r\nExpect: 100-Continue\r\nContent-Length: 5\r\n\r\n");
    assert(s == 200 && r.expect);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nExpect: something\r\nContent-Length: 5\r\n\r\n", 417);
    // HTTP/1.0 has no expectations.
    let r0, s0 = http::parse("POST / HTTP/1.0\r\nExpect: something\r\nContent-Length: 5\r\n\r\n");
    assert(s0 == 200 && !r0.expect);
    let rg, sg = http::parse(GET);
    assert(!rg.expect);
    print("expect: 100-continue, 417 for another, none in HTTP/1.0");
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
    print("limits: line 414, fields 431, head 431, body 413");
}

fn main() {
    test_parse();
    test_fields();
    test_keep_alive();
    test_expect();
    test_limits();
}
