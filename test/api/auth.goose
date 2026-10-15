// Authorization: the scheme and credentials, Basic, Bearer, and challenge's
// 401.
import std;
import http from "../../";
import check from "../";

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
