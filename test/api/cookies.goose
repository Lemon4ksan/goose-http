// Cookies: each_cookie and cookie_of on a request, and set_cookie with the
// cookies is_cookie refuses.
import std;
import http from "../../";
import check from "../";

fn main() {
    var buf: u8[>..] = [];
    let req = check::request("POST", "Cookie: a=1; b=\"two\";c=3 ;bad; =x; d=\r\nCookie: a=9; e = 5\r\n", buf);
    var got: u8[>..] = [];
    http::each_cookie(req) { n, v =>
        got.append(n);
        got.push('=');
        got.append(v);
        got.push('|');
    };
    check::same(got, "a=1|b=two|c=3|d=|a=9|e=5|");
    let a, ha = http::cookie_of(req, "a");
    let b, hb = http::cookie_of(req, "b");
    let d, hd = http::cookie_of(req, "d");
    let z, hz = http::cookie_of(req, "A");
    assert(ha && a == "1" && hb && b == "two" && hd && d == "" && !hz);
    print("cookies: ", got);

    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    assert(http::set_cookie(reply, http::Cookie { name: "sid", value: "abc", max_age: 3600, expires: 1791633600,
                                                  path: "/", domain: "example.com", secure: true, http_only: true,
                                                  same_site: "Lax" }));
    assert(!http::set_cookie(reply, http::Cookie { name: "q", value: "\"x y\"", .. }));
    assert(http::set_cookie(reply, http::Cookie { name: "gone", value: "", max_age: -5, .. }));
    assert(http::set_cookie(reply, http::Cookie { name: "q", value: "\"x\"", .. }));
    check::same(out, "Set-Cookie: sid=abc; Max-Age=3600; Expires=Sat, 10 Oct 2026 12:00:00 GMT; Path=/; Domain=example.com; Secure; HttpOnly; SameSite=Lax\r\nSet-Cookie: gone=; Max-Age=0\r\nSet-Cookie: q=\"x\"\r\n");
    print("set_cookie: every attribute, Max-Age=0, a quoted value");
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
        assert(!http::set_cookie(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st }, c));
    }
    assert(out.len == 0);
    print("dropped: ", bad.len, " cookies");
}
