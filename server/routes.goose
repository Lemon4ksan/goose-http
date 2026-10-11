// The benchmark server's handler: TechEmpower's plaintext and JSON tests,
// HttpArena's endpoints (bench/httparena), and for the tests, /bytes and
// /stream, which send a response of any size in pieces, and /upload and
// /echo, which take a body of any size in pieces.
import std;
import http;

// The most bytes /bytes and /stream send.
let MAX_BYTES = 1000000000;
// The most bytes /bytes and /stream send for one MORE.
let PIECE = 16384;
// What /bytes and /stream send: the digits over and over, from any offset.
let DIGITS = digits();

fn digits() -> u8[PIECE + 10] {
    var d: u8[PIECE + 10] = [0; PIECE + 10];
    for i in d.len { d[i] = ('0' + i % 10) as! u8; }
    return d;
}

// A request's state, between the handler's calls for it.
struct Transfer {
    route: u8 = NONE,
    count: i64 = 0,     // /upload: body bytes so far; /bytes, /stream: bytes sent
    left: i64 = 0,      // /bytes, /stream: bytes still to send
    sum: u64 = 0,       // /upload: the sum of the body's bytes
}

let NONE: u8 = 0;
let UPLOAD: u8 = 1;
let ECHO: u8 = 2;
let SEND: u8 = 3;

// The handler: routes each request, and carries on with those that take or
// send their bodies in pieces. Inline, so that http::start and http::finish
// fold into each route.
inline fn handle(ev: http::Event, st: Transfer&, out: http::Reply) {
    if ev.kind == http::REQUEST {
        route(ev.req, ev.data, ev.whole, st, out);
    } else if st.route == UPLOAD {
        if ev.kind == http::BODY { take(st, ev.data); }
        else if ev.kind == http::END { uploaded(st, out); }
    } else if st.route == ECHO {
        if ev.kind == http::BODY { http::send(out, ev.data); }
        else if ev.kind == http::END { http::end(out); }
    } else if st.route == SEND && ev.kind == http::MORE {
        let k = min(st.left, PIECE);
        let at = st.count % 10;
        http::send(out, DIGITS[at..at + k]);
        st.count += k;
        st.left -= k;
        if st.left == 0 { http::end(out); }
    }
}

// Answers req, or starts to. body is its body when whole is set, or empty.
inline fn route(req: http::Request, body: const u8[:], whole: bool, st: Transfer&, out: http::Reply) {
    let path = http::path_of(req.target);
    let plaintext = path == "/plaintext";
    let json = path == "/json";
    let baseline = path == "/baseline11";
    let pipeline = path == "/pipeline";
    // n bytes, with a Content-Length, and chunked: responses larger than the
    // write buffer, sent as the client takes them.
    let bytes = path == "/bytes";
    let stream = path == "/stream";
    // A body of any size: its length and the sum of its bytes, and the body
    // itself.
    let upload = path == "/upload";
    let echo = path == "/echo";
    let get = out.head || req.method == "GET";
    let post = req.method == "POST";
    // TechEmpower's routes first, where most requests go.
    if plaintext && get {
        http::start(out, 200);
        http::finish(out, "Content-Type: text/plain\r\nContent-Length: ", "Hello, World!");
    } else if json && get {
        var text: u8[..64] = [];
        json_object(text, Message { message: "Hello, World!" });
        http::start(out, 200);
        http::finish(out, "Content-Type: application/json\r\nContent-Length: ", text);
    } else if !get && !post && !http::known_method(req.method) {
        http::start(out, 501);
        http::finish(out, "Content-Length: ", "");
    } else if !get && (plaintext || json || pipeline || bytes || stream || baseline && !post) ||
              !post && (upload || echo) {
        http::start(out, 405);
        out.buf.append(if baseline { "Allow: GET, HEAD, POST\r\n" }
                       else if upload || echo { "Allow: POST\r\n" }
                       else { "Allow: GET, HEAD\r\n" });
        http::finish(out, "Content-Length: ", "");
    } else if baseline {
        // A body too long for the read buffer counts as empty.
        var sum = http::query_int(req.target, "a") + http::query_int(req.target, "b");
        if post {
            let n, ok = parse_int(trim(body));
            if ok { sum += n; }
        }
        var text: u8[..24] = [];
        format(text, sum);
        http::start(out, 200);
        http::finish(out, "Content-Type: text/plain\r\nContent-Length: ", text);
    } else if pipeline {
        http::start(out, 200);
        http::finish(out, "Content-Type: text/plain\r\nContent-Length: ", "ok");
    } else if bytes || stream {
        let n = min(max(http::query_int(req.target, "n"), 0), MAX_BYTES);
        http::begin(out, 200, if bytes { n } else { -1 });
        http::field(out, "Content-Type", "application/octet-stream");
        st.route = SEND;
        st.left = n;
        if n == 0 || out.head { http::end(out); }
    } else if upload {
        st.route = UPLOAD;
        take(st, body);
        if whole { uploaded(st, out); }
    } else if echo {
        http::begin(out, 200, if req.chunked { -1 } else { req.body });
        http::field(out, "Content-Type", "application/octet-stream");
        http::send(out, body);
        if whole { http::end(out); } else { st.route = ECHO; }
    } else if req.target == "*" {
        // OPTIONS *, the only method parse lets "*" through with: what the
        // server as a whole allows (RFC 9110 §9.3.7).
        http::start(out, 200);
        http::finish(out, "Allow: GET, HEAD, POST, OPTIONS\r\nContent-Length: ", "");
    } else {
        http::start(out, 404);
        http::finish(out, "Content-Length: ", "");
    }
}

fn take(st: Transfer&, data: const u8[:]) {
    st.count += data.len;
    for b in data { st.sum += b; }
}

// /upload's response: the body's length and the sum of its bytes.
fn uploaded(st: Transfer&, out: http::Reply) {
    var text: u8[..48] = [];
    format(text, st.count, " ", st.sum);
    http::start(out, 200);
    http::finish(out, "Content-Type: text/plain\r\nContent-Length: ", text);
}

// The object /json serializes for each request, as TechEmpower's JSON test
// asks.
struct Message { message: const u8[:] }

fn json_object<A>(out: A&, m: Message) {
    out.append("{\"message\":");
    http::json_string(out, m.message);
    out.push('}');
}
