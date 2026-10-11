// Unit tests for the benchmark server's routes (routes.goose).
// scripts/test-unit.sh runs them through TinyCC.
import std;
import http from "../";
import routes;

let GET = "GET /plaintext HTTP/1.1\r\nHost: x\r\n\r\n";
let DATE = "Sat, 10 Oct 2026 12:00:00 GMT";

// Answers a request, whose body follows its head, into out, as the loops do.
// Returns whether the connection stays open.
fn response(text: const u8[:], out: u8[>..]&) -> bool {
    let r, s = http::parse(text);
    assert(s == 200);
    var keep = r.keep_alive;
    route(r, text[r.len..],
          http::Reply { buf: out, date: DATE, keep_alive: keep, minor: r.minor, head: r.method == "HEAD" });
    return keep;
}

fn same(got: const u8[:], want: const u8[:]) {
    if got != want {
        print("got:\n", got, "\nwant:\n", want);
        assert(false);
    }
}

fn main() {
    var out: u8[>..] = [];
    assert(response(GET, out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!");

    out.clear();
    assert(response("GET /json?x=1 HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: application/json\r\nContent-Length: 27\r\n\r\n{\"message\":\"Hello, World!\"}");

    out.clear();
    assert(response("HEAD /plaintext HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\n");

    out.clear();
    assert(!response("GET /nope HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n", out));
    same(out, "HTTP/1.1 404 Not Found\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");

    out.clear();
    assert(response("POST /json HTTP/1.0\r\nConnection: keep-alive\r\nContent-Length: 2\r\n\r\n", out));
    same(out, "HTTP/1.1 405 Method Not Allowed\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: keep-alive\r\nAllow: GET, HEAD\r\nContent-Length: 0\r\n\r\n");

    // HttpArena's endpoints.
    out.clear();
    assert(response("GET /baseline11?a=13&b=42 HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\n55");
    out.clear();
    assert(response("POST /baseline11?b=-50&x&a=1 HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n\r\n 20\n", out));
    same(out[^3..], "-29");
    out.clear();
    assert(response("POST /baseline11 HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nzz", out));
    same(out[^1..], "0");
    out.clear();
    assert(response("PUT /baseline11 HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 405 Method Not Allowed\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nAllow: GET, HEAD, POST\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    assert(response("GET /pipeline HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out[^2..], "ok");
    out.clear();
    assert(response("GET /bytes?n=12 HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: application/octet-stream\r\nContent-Length: 12\r\n\r\n012345678901");
    // Larger than the write buffer, which grows to take it.
    out.clear();
    assert(response("GET /bytes?n=50000 HTTP/1.1\r\nHost: x\r\n\r\n", out));
    same(out[^50017..^49997], "Length: 50000\r\n\r\n012");
    same(out[^10..], "0123456789");
    print("test_routes: ok");
}
