import std;
import http;

// A browser's navigation request, as Chrome sends one, with a 1 KB cookie of
// made-up values, parsed 10 M times.
fn main() {
    var req: u8[>..] = [];
    req.append("GET /account/orders?page=2&sort=date HTTP/1.1\r\n");
    req.append("Host: shop.example.com\r\n");
    req.append("Connection: keep-alive\r\n");
    req.append("sec-ch-ua: \"Chromium\";v=\"130\", \"Google Chrome\";v=\"130\", \"Not?A_Brand\";v=\"99\"\r\n");
    req.append("sec-ch-ua-mobile: ?0\r\n");
    req.append("sec-ch-ua-platform: \"Windows\"\r\n");
    req.append("Upgrade-Insecure-Requests: 1\r\n");
    req.append("User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36\r\n");
    req.append("Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7\r\n");
    req.append("Sec-Fetch-Site: same-origin\r\n");
    req.append("Sec-Fetch-Mode: navigate\r\n");
    req.append("Sec-Fetch-User: ?1\r\n");
    req.append("Sec-Fetch-Dest: document\r\n");
    req.append("Referer: https://shop.example.com/account/orders?page=1&sort=date\r\n");
    req.append("Accept-Encoding: gzip, deflate, br, zstd\r\n");
    req.append("Accept-Language: en-GB,en-US;q=0.9,en;q=0.8,et;q=0.7\r\n");
    req.append("Cookie: session=7f3a9c1e5b2d4f6a8c0e2b4d6f8a0c2e4b6d8f0a2c4e6b8d0f2a4c6e8b0d2f4a; csrftoken=Q2xhdWRlIGlzIG5vdCBhIHJlYWwgdG9rZW4gaGVyZSwganVzdCBwYWRkaW5n; ");
    req.append("_ga=GA1.1.1234567890.1700000000; _ga_ABCDEF1234=GS1.1.1700000000.42.1.1700003600.0.0.0; _gid=GA1.2.987654321.1700000000; ");
    req.append("_fbp=fb.1.1700000000000.1234567890; cart=%7B%22items%22%3A%5B%7B%22id%22%3A1042%2C%22qty%22%3A2%7D%2C%7B%22id%22%3A2210%2C%22qty%22%3A1%7D%5D%7D; ");
    req.append("prefs=theme%3Ddark%26lang%3Den%26currency%3DEUR%26tz%3DEurope%252FTallinn; consent=analytics%3Atrue%2Cmarketing%3Afalse%2Cfunctional%3Atrue; ");
    req.append("recently_viewed=1042%2C2210%2C3381%2C4407%2C5519%2C6623%2C7730%2C8841%2C9952%2C1063; ");
    req.append("ab_test=checkout_v2%3Db%3Bsearch_ranking%3Dcontrol%3Bbanner%3Dvariant3; ");
    req.append("remember_token=b64.ZXhhbXBsZSByZW1lbWJlciB0b2tlbiB2YWx1ZSB0aGF0IGlzIGxvbmcgZW5vdWdoIHRvIG1hdHRlcg; ");
    req.append("last_search=wireless%20noise%20cancelling%20headphones%20over%20ear; locale=en-GB\r\n");
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
