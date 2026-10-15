// Percent-decoding, targets that don't decode, and the query's pairs.
import std;
import http from "../../";
import check from "../";

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

    check::expect("GET /a%20b HTTP/1.1\r\nHost: x\r\n\r\n", 200);
    check::expect("GET /a%2 HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET /a?b=%zz HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    check::expect("GET /a% HTTP/1.1\r\nHost: x\r\n\r\n", 400);
    print("decode: ", decoded("/a%20b%2Fc"), " ", decoded("a+b%2B", true), ", and 400 for a bad escape");

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
    let n, nok = http::query_int(t, "n");
    assert(nok && n == 12);
    let bad, bok = http::query_int(t, "q");
    assert(!bok && bad == 0);
    let gone, gok = http::query_int(t, "missing");
    assert(!gok && gone == 0);
    let zero, zok = http::query_int("/s?z=0&m=-7", "z");
    assert(zok && zero == 0);
    let minus, mok = http::query_int("/s?z=0&m=-7", "m");
    assert(mok && minus == -7);
    var pairs: u8[>..] = [];
    http::each_query(t) { key, value =>
        pairs.append(key);
        pairs.append("=");
        pairs.append(value);
        pairs.append(";");
    };
    assert(pairs == "q=a+b%26c;flag=;n=12;q=second;e=;");
    print("query: ", pairs);
}

fn main() {
    test_decode();
}
