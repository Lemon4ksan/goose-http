// Unit tests for the package's helpers for APIs: media types and Accept,
// cookies, Authorization, form bodies, and JSON responses.
// scripts/test-unit.sh runs them through TinyCC.
import std;
import json;
import http from "../";

// The request text's head, parsed: text holds its field lines.
fn request(fields: const u8[:], buf: u8[>..]&) -> http::Request {
    buf.clear();
    buf.append("POST /x HTTP/1.1\r\nHost: x\r\n");
    buf.append(fields);
    buf.append("\r\n");
    let r, s = http::parse(buf);
    assert(s == 200);
    return r;
}

fn same(got: const u8[:], want: const u8[:]) {
    if got != want {
        print("got:\n", got, "\nwant:\n", want);
        assert(false);
    }
}

fn test_media_type() {
    let m, ok = http::media_type("Application/JSON ; charset=\"utf-8\";;  q=x ");
    assert(ok && m.top == "Application" && m.sub == "JSON");
    assert(http::is_media(m, "application/json") && !http::is_media(m, "application/xml"));
    let cs, has = http::param_of(m, "CHARSET");
    assert(has && cs == "utf-8");
    let q, hq = http::param_of(m, "q");
    assert(hq && q == "x");
    let none, missing = http::param_of(m, "boundary");
    assert(!missing);

    let b, okb = http::media_type("multipart/form-data; boundary=\"a b\\\"c\"");
    let bv, hb = http::param_of(b, "boundary");
    assert(okb && hb && bv == "a b\\\"c");

    for bad in ["", "json", "a/", "/b", "a/b c", "a/b; c", "a/b; c=", "a/b; c=\"x", "a b/c", "a/b;c=d e"] {
        let x, okx = http::media_type(bad);
        if okx { print("media_type took '", bad, "'"); }
        assert(!okx);
    }

    var buf: u8[>..] = [];
    assert(http::has_type(request("Content-Type: application/json; charset=utf-8\r\n", buf), "application/json"));
    assert(!http::has_type(request("Content-Type: text/plain\r\n", buf), "application/json"));
    assert(!http::has_type(request("", buf), "application/json"));
}

// Which of offers req's Accept picks.
fn picks(accept: const u8[:], offers: const u8[:][:]) -> i64 {
    var buf: u8[>..] = [];
    let req = request(accept, buf);
    return http::negotiate(req, offers);
}

fn test_accept() {
    let offers = ["application/json", "text/html", "text/plain; charset=utf-8"];
    assert(picks("", offers) == 0);
    assert(picks("Accept: text/html\r\n", offers) == 1);
    assert(picks("Accept: */*\r\n", offers) == 0);
    assert(picks("Accept: text/*, application/json;q=0.5\r\n", offers) == 1);
    // The most specific range wins: text/* takes text/plain, and text/html
    // is refused.
    assert(picks("Accept: text/*;q=0.3, text/html;q=0, application/json;q=0.2\r\n", offers) == 2);
    // A range's parameters must be the offer's.
    assert(picks("Accept: text/plain;charset=utf-8, */*;q=0.1\r\n", offers) == 2);
    assert(picks("Accept: text/plain;charset=latin1, application/json;q=0.1\r\n", offers) == 0);
    // Repeated fields add up, and an equal weight keeps the server's order.
    assert(picks("Accept: image/png\r\nAccept: text/html, application/json\r\n", offers) == 0);
    assert(picks("Accept: image/png\r\n", offers) == -1);
    assert(picks("Accept: */*;q=0\r\n", offers) == -1);
    // Case doesn't matter, and quoted commas don't split.
    assert(picks("Accept: TEXT/HTML;a=\"x,y\";q=0.9, application/json;q=0.8\r\n", offers) == 0);
    // Ranges that can't be read are skipped, and the rest still count.
    assert(picks("Accept: text, text/html;q=2, text/plain;q=0.1234, application/json;q=0.001\r\n", offers) == 0);
    assert(picks("Accept: bad junk, text/html\r\n", offers) == 1);
    assert(picks("Accept: \r\n", offers) == -1);

    let one, ok1 = http::qvalue("1");
    let half, ok5 = http::qvalue("0.5");
    let eighth, ok8 = http::qvalue("0.125");
    assert(ok1 && one == 1000 && ok5 && half == 500 && ok8 && eighth == 125);
    let a, oka = http::qvalue("1.0");
    let b, okb = http::qvalue("1.001");
    let c, okc = http::qvalue("0.");
    assert(oka && a == 1000 && !okb && okc && c == 0);
}

// require_type's 415 and accept_or_406's 406.
fn test_refusals() {
    var buf: u8[>..] = [];
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let req = request("Content-Type: text/plain\r\nAccept: text/html\r\n", buf);
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    assert(!http::require_type(req, reply, "application/json"));
    same(out, "HTTP/1.1 415 Unsupported Media Type\r\nAccept: application/json\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    assert(http::require_type(req, http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                              "text/plain"));
    assert(out.len == 0);
    assert(http::accept_or_406(req, http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                               ["application/json"]) == -1);
    same(out, "HTTP/1.1 406 Not Acceptable\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    assert(http::accept_or_406(req, http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                               ["application/json", "text/html"]) == 1);
    assert(out.len == 0 && keep);
}

fn test_cookies() {
    var buf: u8[>..] = [];
    let req = request("Cookie: a=1; b=\"two\";c=3 ;bad; =x; d=\r\nCookie: a=9; e = 5\r\n", buf);
    var got: u8[>..] = [];
    http::each_cookie(req) { n, v =>
        got.append(n);
        got.push('=');
        got.append(v);
        got.push('|');
    };
    same(got, "a=1|b=two|c=3|d=|a=9|e=5|");
    let a, ha = http::cookie_of(req, "a");
    let b, hb = http::cookie_of(req, "b");
    let d, hd = http::cookie_of(req, "d");
    let z, hz = http::cookie_of(req, "A");
    assert(ha && a == "1" && hb && b == "two" && hd && d == "" && !hz);

    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    http::set_cookie(reply, http::Cookie { name: "sid", value: "abc", max_age: 3600, expires: 1791633600,
                                           path: "/", domain: "example.com", secure: true, http_only: true,
                                           same_site: "Lax" });
    http::set_cookie(reply, http::Cookie { name: "q", value: "\"x y\"", .. });
    http::set_cookie(reply, http::Cookie { name: "gone", value: "", max_age: -5, .. });
    http::set_cookie(reply, http::Cookie { name: "q", value: "\"x\"", .. });
    same(out, "Set-Cookie: sid=abc; Max-Age=3600; Expires=Sat, 10 Oct 2026 12:00:00 GMT; Path=/; Domain=example.com; Secure; HttpOnly; SameSite=Lax\r\nSet-Cookie: gone=; Max-Age=0\r\nSet-Cookie: q=\"x\"\r\n");
    // A cookie set_cookie can't write is dropped.
    out.clear();
    let bad = [http::Cookie { name: "", value: "x", .. }, http::Cookie { name: "a b", value: "x", .. },
               http::Cookie { name: "a", value: "x;y", .. }, http::Cookie { name: "a", value: "x\r\nB: c", .. },
               http::Cookie { name: "a", value: "x,y", .. }, http::Cookie { name: "a", value: "\"x", .. },
               http::Cookie { name: "a", value: "x", path: "/;Secure", .. },
               http::Cookie { name: "a", value: "x", domain: "a\nb", .. },
               http::Cookie { name: "a", value: "x", same_site: "lax", .. }];
    for c in bad {
        assert(!http::is_cookie(c));
        http::set_cookie(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st }, c);
    }
    assert(out.len == 0);
}

// Whether basic_auth takes the request with fields. A function of its own: a
// call that shrinks an array declared in a for loop over a literal is refused
// (docs/goose-findings.md).
fn basic_ok(fields: const u8[:]) -> bool {
    var buf: u8[>..] = [];
    var decoded: u8[>..] = [];
    let u, p, ok = http::basic_auth(request(fields, buf), decoded);
    return ok;
}

fn test_auth() {
    var buf: u8[>..] = [];
    var decoded: u8[>..] = [];
    let r = request("Authorization: bAsIc  QWxhZGRpbjpvcGVuIHNlc2FtZQ==\r\n", buf);
    let scheme, cred, ok = http::authorization(r);
    assert(ok && scheme == "bAsIc" && cred == "QWxhZGRpbjpvcGVuIHNlc2FtZQ==");
    let user, pass, okb = http::basic_auth(r, decoded);
    assert(okb && user == "Aladdin" && pass == "open sesame");
    // The password may hold ':', and either may be empty.
    var decoded2: u8[>..] = [];
    let u2, p2, ok2 = http::basic_auth(request("Authorization: Basic OmE6Yg==\r\n", buf), decoded2);
    assert(ok2 && u2 == "" && p2 == "a:b");
    let bearer, token, okt = http::authorization(request("Authorization: Bearer abc.def-_~+/=\r\n", buf));
    assert(okt && bearer == "Bearer" && token == "abc.def-_~+/=");
    let alone, none, oka = http::authorization(request("Authorization: Negotiate\r\n", buf));
    assert(oka && alone == "Negotiate" && none == "");
    for bad in ["", "Authorization: Basic\r\n", "Authorization: Bearer abc\r\n",
                "Authorization: Basic QWxhZGRpbg==\r\n", "Authorization: Basic QWxhZGRpbjpvcGVu!\r\n",
                "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ\r\n", "Authorization: B@sic x\r\n"] {
        if basic_ok(bad) {
            print("basic_auth took '", bad, "'");
            assert(false);
        }
    }
    let s1, c1, ok1 = http::authorization(request("Authorization: B@sic x\r\n", buf));
    assert(!ok1);

    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    http::challenge(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                    "Basic realm=\"api\", charset=\"UTF-8\"");
    same(out, "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"api\", charset=\"UTF-8\"\r\nContent-Length: 0\r\n\r\n");
}

fn test_form() {
    var got: u8[>..] = [];
    http::each_form("a=1&&b=x+y%21&c&=z") { k, v =>
        got.append(k);
        got.push('=');
        got.append(v);
        got.push('|');
    };
    same(got, "a=1|b=x+y%21|c=|=z|");
    var v: u8[>..] = [];
    assert(http::form_value("a=1&b=x+y%21&b=2", "b", v) && v == "x y!");
    assert(http::form_value("k%20ey=1&k+ey=2", "k ey", v) && v == "1");
    assert(http::form_value("a=%zz&a=ok", "a", v) && v == "ok");
    assert(!http::form_value("a=1", "b", v) && v == "ok");
    assert(!http::form_value("a=%zz", "a", v));
}

// A multipart body: two fields, a file with CRLF and boundary-like bytes in
// it, a preamble, and an epilogue.
let MULTIPART = "preamble\r\n--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\none\r\n--XyZ \t\r\nContent-Disposition: form-data; name=\"f\"; filename=\"x \\\"y\\\".txt\"\r\nContent-Type: text/plain\r\n\r\nline\r\n--XyY\r\n-\r\n--Xy\r\n--XyZ\r\n\r\n\r\n--XyZ--\r\nepilogue";

// The parts of body read k bytes at a time, as "head|data|" with an END
// mark, or "fail".
fn parts_in_pieces(req: http::Request, body: const u8[:], k: i64) -> u8[>..] {
    var m = http::Multipart { .. };
    var log: u8[>..] = [];
    assert(http::start_multipart(req, m));
    var at = 0;
    while at < body.len {
        let piece = body[at..min(at + k, body.len)];
        at += piece.len;
        let ok = http::each_part(m, piece) { kind, data =>
            if kind == http::PART_HEAD {
                let name, filename, okd = http::disposition(data);
                log.append("[");
                log.append(name);
                log.append(",");
                log.append(filename);
                log.append("]");
            } else if kind == http::PART_DATA {
                log.append(data);
            } else {
                log.append("<end>");
            }
        };
        if !ok { log.append("<fail>"); }
    }
    if http::multipart_done(m) { log.append("<done>"); }
    return log;
}

// Whether start_multipart takes a request with fields.
fn takes(fields: const u8[:]) -> bool {
    var buf: u8[>..] = [];
    var m = http::Multipart { .. };
    let req = request(fields, buf);
    return http::start_multipart(req, m);
}

fn test_multipart() {
    var buf: u8[>..] = [];
    let req = request("Content-Type: multipart/form-data; boundary=XyZ\r\n", buf);
    let want = "[a,]one<end>[f,x \\\"y\\\".txt]line\r\n--XyY\r\n-\r\n--Xy<end>[,]<end><done>";
    for k in MULTIPART.len {
        let got = parts_in_pieces(req, MULTIPART, k + 1);
        if got != want {
            print("in pieces of ", k + 1, ":");
            same(got, want);
        }
    }

    // A boundary must be there, be at most 70 characters, and be quoted to
    // hold a space.
    assert(!takes("Content-Type: multipart/form-data\r\n"));
    assert(!takes("Content-Type: multipart/mixed; boundary=a\r\n"));
    assert(takes("Content-Type: Multipart/Form-Data; boundary=\"a b\"\r\n"));
    assert(!takes("Content-Type: multipart/form-data; boundary=\"a@b\"\r\n"));
    var long: u8[>..] = [];
    long.append("Content-Type: multipart/form-data; boundary=");
    for i in 70 { long.push('x'); }
    long.append("\r\n");
    assert(takes(long));
    long.resize(long.len - 2);
    long.append("x\r\n");
    assert(!takes(long));

    // A delimiter followed by neither CRLF nor "--", and a part head that
    // isn't field lines, fail the body.
    assert(parts_in_pieces(req, "--XyZx\r\n", 100) == "<fail>");
    assert(parts_in_pieces(req, "--XyZ\r\nno colon\r\n\r\n", 100) == "<fail>");
    assert(parts_in_pieces(req, "--XyZ\r\nA: b\nc\r\n\r\n", 100) == "<fail>");
    // A part's head may be MAX_PART_HEAD bytes, its blank line aside, in
    // pieces or not, and no longer.
    for extra in [0, 1] {
        var long: u8[>..] = [];
        long.append("--XyZ\r\nX: ");
        for i in http::MAX_PART_HEAD - 5 + extra { long.push('v'); }
        long.append("\r\n\r\nab\r\n--XyZ--");
        let whole = parts_in_pieces(req, long, long.len);
        let pieces = parts_in_pieces(req, long, 100);
        let want = if extra == 0 { "[,]ab<end><done>" } else { "<fail>" };
        assert(whole == pieces && pieces == want);
    }
    // A body cut short isn't done.
    assert(parts_in_pieces(req, "--XyZ\r\n\r\nab", 100) == "[,]ab");
}

fn test_json() {
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let name = "a \"b\"";
    http::respond_json(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st }, 201) { b =>
        b.push('{');
        json::format_key(b, "name");
        json::format_string(b, name);
        b.push(',');
        json::format_key(b, "n");
        json::format_int(b, 7);
        b.push('}');
    };
    same(out, "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 24\r\n\r\n{\"name\":\"a \\\"b\\\"\",\"n\":7}");
}

fn main() {
    test_media_type();
    test_accept();
    test_refusals();
    test_cookies();
    test_auth();
    test_form();
    test_multipart();
    test_json();
    print("test_api: ok");
}
