// Unit tests for the package's helpers for APIs: media types and Accept,
// and cookies.
// scripts/test-unit.sh runs them through TinyCC.
import std;
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

fn main() {
    test_media_type();
    test_accept();
    test_refusals();
    test_cookies();
    print("test_api: ok");
}
