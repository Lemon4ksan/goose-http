import std;
import http;

// wrk's plaintext request without its Connection field, parsed 10 M times:
// the difference from wrk.goose is what that field costs.
fn main() {
    let req = "GET /plaintext HTTP/1.1\r\nHost: tfb-server\r\nAccept: text/plain,text/html;q=0.9,application/xhtml+xml;q=0.9,application/xml;q=0.8,*/*;q=0.7\r\n\r\n";
    var buf: u8[>..] = [];
    for i in 16 { buf.append(req); }
    var total = 0;
    for i in 10000000 {
        let r, s = http::parse(buf[(i % 16) * req.len..]);
        assert(s == 200);
        total += r.len + s;
    }
    print(total);
}
