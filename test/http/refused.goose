// Requests the parser refuses, and the status each gets: malformed lines and
// fields, Host, Content-Length, versions, transfer codings, targets, and the
// size limits.
import std;
import http from "../../";
import check from "../";

fn main() {
    // Malformed: a bare LF anywhere, no version, bad field syntax.
    check::expect("GET / HTTP/1.1\nHost: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\n\n", 400);
    check::expect("GET / HTTP/1.1\n", 400);
    check::expect("GET /\r\n\r\n", 400);
    check::expect("GET\r\n\r\n", 400);
    check::expect("GET  / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect(" GET / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET / http/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1 \r\nHost: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost : x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\n folded\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\n: x\r\nHost: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nX: a\x00b\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\rX: y\r\n\r\n", 400);
    check::expect("GET /a\x01b HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    // A tab as the request line's separator, whitespace before the first
    // field line, an invalid name, bytes before the request line, and a bare
    // CR starting a line; a value with obs-text is allowed (RFC 9110 §5.5).
    check::expect("GET\t/ HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\n Host: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nX-Invalid[]: y\r\n\r\n", 400);
    check::expect("Extra lineGET / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\n\rSome-Header: y\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nX: caf\xc3\xa9\r\n\r\n", 200);
    print("malformed: 400");
    // Host: required once in 1.1.
    check::expect("GET / HTTP/1.1\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", 400);
    // Content-Length: digits only, and one value.
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length:\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1, 1\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: +1\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1 2\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 12345678901234567890\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: -123456789012345678901234567\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nContent-Length: 3\r\n\r\n", 200);
    print("Host and Content-Length: 400");
    // Other versions, transfer codings, and the size limits.
    check::expect("GET / HTTP/2.0\r\nHost: x\r\n\r\n", 505);
    check::expect("GET / HTTP/0.9\r\nHost: x\r\n\r\n", 505);
    // Chunked must come last, once (RFC 9112 §6.3); other codings before it
    // aren't implemented.
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, gzip\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, chunked\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: \r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked;a=b\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: gzip\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, deflate , chunked\r\n\r\n", 501);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n", 501);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n", 400);
    check::expect("POST / HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n", 400);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1048577\r\n\r\n", 413);
    check::expect("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1048576\r\n\r\n", 200);
    check::expect("ABCDEFGHIJKLMNOPQ / HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    print("versions 505, codings 400 and 501, body 413");
    // A Host that isn't a uri-host and port; an empty one is allowed.
    check::expect("GET / HTTP/1.1\r\nHost: x:8080\r\n\r\n", 200);
    check::expect("GET / HTTP/1.1\r\nHost: [::1]:80\r\n\r\n", 200);
    check::expect("GET / HTTP/1.1\r\nHost: \r\n\r\n", 200);
    check::expect("GET / HTTP/1.1\r\nHost: u@x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x/a\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x, y\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: a b\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: [::1\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: [::1]x\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: x]\r\n\r\n", 400);
    check::expect("GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n", 200);
    // Targets other than origin-form: absolute-form, and * for OPTIONS only.
    check::expect("GET http://x/a HTTP/1.1\r\nHost: x\r\n\r\n", 200);
    check::expect("OPTIONS * HTTP/1.1\r\nHost: x\r\n\r\n", 200);
    check::expect("GET * HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("CONNECT x:443 HTTP/1.1\r\nHost: x:443\r\n\r\n", 400);
    check::expect("GET a/b HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET :// HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    assert(http::path_of("/a?b=1") == "/a");
    assert(http::path_of("http://x:80/a/b?c") == "/a/b");
    assert(http::path_of("http://x?c") == "/");
    assert(http::path_of("*") == "*");
    // The authority: an absolute-form target's over Host (RFC 9112 §3.2.2).
    let abs, sa = http::parse("GET http://a:81/x?y HTTP/1.1\r\nHost: b\r\n\r\n");
    assert(sa == 200 && http::authority(abs) == "a:81");
    let org, so = http::parse("GET /x HTTP/1.1\r\nHost: b:8080\r\n\r\n");
    assert(so == 200 && http::authority(org) == "b:8080");
    let star, ss = http::parse("OPTIONS * HTTP/1.1\r\nHost: c\r\n\r\n");
    assert(ss == 200 && http::authority(star) == "c");
    print("hosts, targets, path_of, authority: ", http::authority(abs), " ", http::authority(org));

    var line: u8[>..] = [];
    line.append("GET /");
    for i in http::MAX_LINE { line.push('a'); }
    check::expect(line, 414);       // before the line has ended
    line.append(" HTTP/1.1\r\nHost: x\r\n\r\n");
    check::expect(line, 414);
    // A request line of 8000 octets fits.
    var long: u8[>..] = [];
    long.append("GET /");
    while long.len < http::MAX_LINE - 9 { long.push('a'); }
    long.append(" HTTP/1.1\r\nHost: x\r\n\r\n");
    check::expect(long, 200);

    var many: u8[>..] = [];
    many.append("GET / HTTP/1.1\r\nHost: x\r\n");
    for i in http::MAX_FIELDS - 1 { many.append("A: b\r\n"); }
    var ok: u8[>..] = [];
    ok.append(many);
    ok.append("\r\n");
    check::expect(ok, 200);
    many.append("A: b\r\n\r\n");
    check::expect(many, 431);

    // A head that fills the buffer without ending can't fit.
    var big: u8[>..] = [];
    big.append("GET / HTTP/1.1\r\nHost: x\r\nX: ");
    while big.len < http::MAX_HEAD { big.push('y'); }
    check::expect(big[..http::MAX_HEAD - 1], http::INCOMPLETE);
    check::expect(big, 431);
    print("limits: line ", http::MAX_LINE, ", fields ", http::MAX_FIELDS, ", head ", http::MAX_HEAD);
}
