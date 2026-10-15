// Media types, Accept negotiation, qvalues, and require_type's 415 and
// accept_or_406's 406.
import std;
import http from "../../";
import check from "../";

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

    let bad = ["", "json", "a/", "/b", "a/b c", "a/b; c", "a/b; c=", "a/b; c=\"x", "a b/c", "a/b;c=d e"];
    for t in bad {
        let x, okx = http::media_type(t);
        if okx { print("media_type took '", t, "'"); }
        assert(!okx);
    }

    var buf: u8[>..] = [];
    let json = check::request("POST", "Content-Type: application/json; charset=utf-8\r\n", buf);
    assert(http::has_type(json, "application/json"));
    let text = check::request("POST", "Content-Type: text/plain\r\n", buf);
    assert(!http::has_type(text, "application/json"));
    let untyped = check::request("POST", "", buf);
    assert(!http::has_type(untyped, "application/json"));
    print("media_type: ", m.top, "/", m.sub, " charset ", cs, "; boundary ", bv, "; ", bad.len, " refused");
}

// Which of offers req's Accept picks.
fn picks(accept: const u8[:], offers: const u8[:][:]) -> i64 {
    var buf: u8[>..] = [];
    let req = check::request("POST", accept, buf);
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
    print("negotiate: specific ranges, parameters, repeats, case, unreadable ranges");

    let one, ok1 = http::qvalue("1");
    let half, ok5 = http::qvalue("0.5");
    let eighth, ok8 = http::qvalue("0.125");
    assert(ok1 && one == 1000 && ok5 && half == 500 && ok8 && eighth == 125);
    let a, oka = http::qvalue("1.0");
    let b, okb = http::qvalue("1.001");
    let c, okc = http::qvalue("0.");
    assert(oka && a == 1000 && !okb && okc && c == 0);
    print("qvalue: ", one, " ", half, " ", eighth, " ", a, " ", c, ", 1.001 refused");
}

// require_type's 415 and accept_or_406's 406.
fn test_refusals() {
    var buf: u8[>..] = [];
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let req = check::request("POST", "Content-Type: text/plain\r\nAccept: text/html\r\n", buf);
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    assert(!http::require_type(req, reply, "application/json"));
    check::same(out, "HTTP/1.1 415 Unsupported Media Type\r\nAccept: application/json\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    assert(http::require_type(req, http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                              "text/plain"));
    assert(out.len == 0);
    assert(http::accept_or_406(req, http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                               ["application/json"]) == -1);
    check::same(out, "HTTP/1.1 406 Not Acceptable\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    assert(http::accept_or_406(req, http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                               ["application/json", "text/html"]) == 1);
    assert(out.len == 0 && keep);
    print("refusals: 415, 406");
}

fn main() {
    test_media_type();
    test_accept();
    test_refusals();
}
