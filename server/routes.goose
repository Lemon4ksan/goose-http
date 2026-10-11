// The benchmark server's handler: TechEmpower's plaintext and JSON tests,
// HttpArena's endpoints (bench/httparena), and /bytes for the tests.
import std;
import http;

// The most bytes /bytes sends.
let MAX_BYTES = 16777216;

// Writes the response to req, whose body is body, into out.
fn route(req: http::Request, body: const u8[:], out: http::Reply) {
    let path = http::path_of(req.target);
    let plaintext = path == "/plaintext";
    let json = path == "/json";
    let baseline = path == "/baseline11";
    let pipeline = path == "/pipeline";
    // n bytes, for testing responses larger than the write buffer.
    let bytes = path == "/bytes";
    let get = out.head || req.method == "GET";
    if (plaintext || json || pipeline || bytes) && !get || baseline && !get && req.method != "POST" {
        http::start(out, 405);
        out.buf.append(if baseline { "Allow: GET, HEAD, POST\r\n" } else { "Allow: GET, HEAD\r\n" });
        http::finish(out, "Content-Length: ", "");
    } else if plaintext {
        http::start(out, 200);
        http::finish(out, "Content-Type: text/plain\r\nContent-Length: ", "Hello, World!");
    } else if json {
        var text: u8[..64] = [];
        json_object(text, Message { message: "Hello, World!" });
        http::start(out, 200);
        http::finish(out, "Content-Type: application/json\r\nContent-Length: ", text);
    } else if baseline {
        var sum = http::query_int(req.target, "a") + http::query_int(req.target, "b");
        if req.method == "POST" {
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
    } else if bytes {
        let n = min(max(http::query_int(req.target, "n"), 0), MAX_BYTES);
        http::start(out, 200);
        out.buf.append("Content-Type: application/octet-stream\r\nContent-Length: ");
        format(out.buf, n);
        out.buf.append("\r\n\r\n");
        if !out.head {
            for i in n { out.buf.push(('0' + i % 10) as! u8); }
        }
    } else {
        http::start(out, 404);
        http::finish(out, "Content-Length: ", "");
    }
}

// The object /json serializes for each request, as TechEmpower's JSON test
// asks.
struct Message { message: const u8[:] }

fn json_object<A>(out: A&, m: Message) {
    out.append("{\"message\":");
    http::json_string(out, m.message);
    out.push('}');
}
