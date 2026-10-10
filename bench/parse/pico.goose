import std;
import http;

// picohttpparser's benchmark request (bench.c at h2o/picohttpparser 465a7ff),
// parsed 10 M times.
fn main() {
    var req: u8[>..] = [];
    req.append("GET /wp-content/uploads/2010/03/hello-kitty-darth-vader-pink.jpg HTTP/1.1\r\n");
    req.append("Host: www.kittyhell.com\r\n");
    req.append("User-Agent: Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; ja-JP-mac; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3 Pathtraq/0.9\r\n");
    req.append("Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n");
    req.append("Accept-Language: ja,en-us;q=0.7,en;q=0.3\r\n");
    req.append("Accept-Encoding: gzip,deflate\r\n");
    req.append("Accept-Charset: Shift_JIS,utf-8;q=0.7,*;q=0.7\r\n");
    req.append("Keep-Alive: 115\r\n");
    req.append("Connection: keep-alive\r\n");
    req.append("Cookie: wp_ozh_wsa_visits=2; wp_ozh_wsa_visit_lasttime=xxxxxxxxxx; ");
    req.append("__utma=xxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.x; ");
    req.append("__utmz=xxxxxxxxx.xxxxxxxxxx.x.x.utmccn=(referral)|utmcsr=reader.livedoor.com|utmcct=/reader/|utmcmd=referral\r\n");
    req.append("\r\n");
    let one = req.len;
    var buf: u8[>..] = [];
    for i in 4 { buf.append(req); }
    var total = 0;
    for i in 10000000 {
        let r, s = http::parse(buf[(i % 4) * one..]);
        assert(s == 200);
        total += r.len + s;
    }
    print(total);
}
