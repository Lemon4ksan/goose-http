// Authorization: the scheme and credentials, Basic, Bearer, and challenge's
// 401.
import std;
import http from "../../";
import check from "../";

// A token68 of len bytes, of every kind of byte it takes.
fn token_of(len: i64) -> u8[>..] {
    let kinds = "aZ09-._~+/";
    var t: u8[>..] = [];
    for i in len { t.push(kinds[i % kinds.len]); }
    return t;
}

fn main() {
    var buf: u8[>..] = [];
    var decoded: u8[>..] = [];
    let r = check::request("POST", "Authorization: bAsIc  QWxhZGRpbjpvcGVuIHNlc2FtZQ==\r\n", buf);
    let scheme, cred, ok = http::authorization(r);
    assert(ok && scheme == "bAsIc" && cred == "QWxhZGRpbjpvcGVuIHNlc2FtZQ==");
    let user, pass, okb = http::basic_auth(r, decoded);
    assert(okb && user == "Aladdin" && pass == "open sesame");
    print("basic: ", user, ", ", pass);
    // The password may hold ':', and either may be empty.
    var decoded2: u8[>..] = [];
    let r2 = check::request("POST", "Authorization: Basic OmE6Yg==\r\n", buf);
    let u2, p2, ok2 = http::basic_auth(r2, decoded2);
    assert(ok2 && u2 == "" && p2 == "a:b");
    let r3 = check::request("POST", "Authorization: Bearer abc.def-_~+/=\r\n", buf);
    let bearer, token, okt = http::authorization(r3);
    assert(okt && bearer == "Bearer" && token == "abc.def-_~+/=");
    let t3, okt3 = http::bearer(r3);
    assert(okt3 && t3 == "abc.def-_~+/=");
    let r6 = check::request("POST", "Authorization: bEaReR  x==\r\n", buf);
    let t6, okt6 = http::bearer(r6);
    assert(okt6 && t6 == "x==");
    print("bearer: ", t6, ", in any case of the scheme");
    for no in ["", "Authorization: Bearer\r\n", "Authorization: Basic QWxh\r\n",
               "Authorization: Bearer a=b\r\n", "Authorization: Bearer =\r\n", "Authorization: Bearer a b\r\n"] {
        var held: u8[>..] = [];
        let rn = check::request("POST", no, held);
        let tn, okn = http::bearer(rn);
        assert(!okn && tn.len == 0);
    }
    // is_token68 and field_at scan 16 bytes at a time: a token of every length
    // up to 48 is taken whole, with '='s after it, from a request whose field
    // it ends; a bad byte at any position refuses it, and so does an '=' but at
    // its end.
    var cases = 0;
    for len in 1..49 {
        let t = token_of(len);
        var head: u8[>..] = [];
        format(head, "Authorization: Bearer ", t, "==\r\nX-After: 1\r\n");
        var held: u8[>..] = [];
        let rl = check::request("POST", head, held);
        let tl, okl = http::bearer(rl);
        assert(okl && tl.len == len + 2 && tl[..len] == t);
        for at in len {
            for bad in [' ', '!', ',', '"', 0x7f, 0x80, 0xff] {
                var b = token_of(len);
                b[at] = bad as u8;
                assert(!http::is_token68(b));
                cases += 1;
            }
            var e = token_of(len);
            e[at] = '=';
            assert(http::is_token68(e) == (at > 0 && at == len - 1));
            cases += 1;
        }
    }
    print("token68: ", cases, " cases of 48 lengths");

    let r4 = check::request("POST", "Authorization: Negotiate\r\n", buf);
    let alone, none, oka = http::authorization(r4);
    assert(oka && alone == "Negotiate" && none == "");
    for bad in ["", "Authorization: Basic\r\n", "Authorization: Bearer abc\r\n",
                "Authorization: Basic QWxhZGRpbg==\r\n", "Authorization: Basic QWxhZGRpbjpvcGVu!\r\n",
                "Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ\r\n", "Authorization: B@sic x\r\n"] {
        var held: u8[>..] = [];
        var decoded_bad: u8[>..] = [];
        let rb = check::request("POST", bad, held);
        let ub, pb, took = http::basic_auth(rb, decoded_bad);
        if took {
            print("basic_auth took '", bad, "'");
            assert(false);
        }
    }
    let r5 = check::request("POST", "Authorization: B@sic x\r\n", buf);
    let s1, c1, ok1 = http::authorization(r5);
    assert(!ok1);
    print("refused: 6 Bearer, 7 Basic, a bad scheme");

    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    http::challenge(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st },
                    "Basic realm=\"api\", charset=\"UTF-8\"");
    check::same(out, "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"api\", charset=\"UTF-8\"\r\nContent-Length: 0\r\n\r\n");
    print("challenge: 401");
}
