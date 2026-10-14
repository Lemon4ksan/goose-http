// Unit tests for compression.goose: which coding a request gets, the
// responses left uncompressed, and a streamed response's chunks and
// encoders. scripts/http_client.py compress decompresses real responses.
import std;
import http from "../";
import compress from "github.com/kaitk/goose-compress@2c7df270b88ed8a00e2d73b6f84d50908cf5a558";
import http.compression;

let COMMON = "Server: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\n";

fn get_with(method: const u8[:], extra: const u8[:], out: u8[>..]&) -> http::Request {
    out.append(method);
    out.append(" /f HTTP/1.1\r\nHost: x\r\n");
    out.append(extra);
    out.append("\r\n");
    let r, s = http::parse(out);
    assert(s == 200);
    return r;
}

// A body that compresses: 2,000 bytes of a repeating line.
fn text() -> u8[>..] {
    var t: u8[>..] = [];
    while t.len < 2000 { t.append("{\"id\":1,\"name\":\"Alpha Widget\"},"); }
    return t;
}

// The value of field name in a response's head, or "".
fn value_of(response: const u8[:], name: const u8[:]) -> const u8[:] {
    let head_end = find(response, "\r\n\r\n");
    var from = -1;
    var to = 0;
    var at = 0;
    while at < head_end {
        let eol = at + find(response[at..], "\r\n");
        let line = response[at..eol];
        let colon = position(line, ':');
        if colon > 0 && line[..colon] == name {
            from = at + colon + 2;
            to = eol;
        }
        at = eol + 2;
    }
    return if from < 0 { "" } else { response[from..to] };
}

fn body_of(response: const u8[:]) -> const u8[:] {
    return response[find(response, "\r\n\r\n") + 4..];
}

struct Pick { fields: const u8[:], coding: http::Coding }

fn test_coding_for() {
    let c = http::Compression { .. };
    let cases = [
        Pick { fields: "", coding: http::Coding.Identity },
        Pick { fields: "Accept-Encoding: gzip, br\r\n", coding: http::Coding.Gzip },
        Pick { fields: "Accept-Encoding: gzip, deflate, br, zstd\r\n", coding: http::Coding.Zstd },
        Pick { fields: "Accept-Encoding: deflate\r\n", coding: http::Coding.Deflate },
        Pick { fields: "Accept-Encoding: deflate, gzip\r\n", coding: http::Coding.Gzip },
        Pick { fields: "Accept-Encoding: zstd;q=0.5, gzip\r\n", coding: http::Coding.Gzip },
        Pick { fields: "Accept-Encoding: br\r\n", coding: http::Coding.Identity },
        Pick { fields: "Accept-Encoding: *\r\n", coding: http::Coding.Zstd },
        Pick { fields: "Accept-Encoding: identity\r\n", coding: http::Coding.Identity },
    ];
    for k in cases {
        var b: u8[>..] = [];
        let r = get_with("GET", k.fields, b);
        if http::coding_for(r, c) != k.coding { print("coding_for: ", k.fields); }
        assert(http::coding_for(r, c) == k.coding);
    }
    var b: u8[>..] = [];
    let r = get_with("GET", "Accept-Encoding: zstd, gzip;q=0.9\r\n", b);
    assert(http::coding_for(r, http::Compression { zstd: false, .. }) == http::Coding.Gzip);

    assert(http::compressible("application/json"));
    assert(http::compressible("text/html; charset=utf-8"));
    assert(http::compressible("image/svg+xml"));
    assert(!http::compressible("image/png"));
    assert(!http::compressible("Video/mp4"));
    assert(!http::compressible("application/zip"));
    assert(!http::compressible("font/woff2"));
}

// respond_compressed's response to a request with the fields extra.
fn respond(method: const u8[:], extra: const u8[:], status: i32, content_type: const u8[:],
           body: const u8[:], out: u8[>..]&) {
    var b: u8[>..] = [];
    let r = get_with(method, extra, b);
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, common: COMMON, keep_alive: keep, minor: 1, head: method == "HEAD", stream: st };
    http::respond_compressed(c, r, status, content_type, body);
}

struct Plain { method: const u8[:], fields: const u8[:], status: i32 }

fn test_whole() {
    let t = text();
    let gzip = "Accept-Encoding: gzip, br\r\n";

    var out: u8[>..] = [];
    respond("GET", gzip, 200, "application/json", t, out);
    assert(value_of(out, "Content-Encoding") == "gzip");
    assert(value_of(out, "Vary") == "Accept-Encoding");
    let body = body_of(out);
    assert(body.len < t.len / 4 && body[0] == 0x1f && body[1] == 0x8b);
    let n, ok = parse_int(value_of(out, "Content-Length"));
    assert(ok && n == body.len);
    // The same bytes as compress gives.
    var want: u8[>..] = [];
    compress::compress(t, want, compress::GZIP, 1);
    assert(body == want);

    out.clear();
    respond("GET", "Accept-Encoding: deflate\r\n", 200, "text/plain", t, out);
    assert(value_of(out, "Content-Encoding") == "deflate" && body_of(out)[0] == 0x78);
    out.clear();
    respond("GET", "Accept-Encoding: zstd\r\n", 200, "text/plain", t, out);
    let zb = body_of(out);
    assert(value_of(out, "Content-Encoding") == "zstd");
    assert(zb[0] == 0x28 && zb[1] == 0xb5 && zb[2] == 0x2f && zb[3] == 0xfd);

    // Left alone, with Vary: no Accept-Encoding, a short body, HEAD, 206,
    // and 304.
    let alone = [Plain { method: "GET", fields: "", status: 200 }, Plain { method: "GET", fields: gzip, status: 206 },
                 Plain { method: "HEAD", fields: gzip, status: 200 }, Plain { method: "GET", fields: gzip, status: 304 }];
    for a in alone {
        out.clear();
        respond(a.method, a.fields, a.status, "application/json", t, out);
        assert(value_of(out, "Content-Encoding") == "" && value_of(out, "Vary") == "Accept-Encoding");
    }
    out.clear();
    respond("GET", gzip, 200, "application/json", "{\"short\":true}", out);
    assert(value_of(out, "Content-Encoding") == "" && body_of(out) == "{\"short\":true}");
    assert(value_of(out, "Vary") == "Accept-Encoding");
    out.clear();
    respond("HEAD", gzip, 200, "application/json", t, out);
    let head_n, head_ok = parse_int(value_of(out, "Content-Length"));
    assert(head_ok && head_n == t.len && body_of(out) == "");
    // An image goes as it is, without Vary.
    out.clear();
    respond("GET", gzip, 200, "image/png", t, out);
    assert(value_of(out, "Content-Encoding") == "" && value_of(out, "Vary") == "");
    assert(body_of(out) == t);
}

// A streamed response, its chunks unwrapped into body.
fn unchunk(response: const u8[:], body: u8[>..]&) {
    var at = find(response, "\r\n\r\n") + 4;
    while at < response.len {
        let eol = at + find(response[at..], "\r\n");
        var n: i64 = 0;
        for c in response[at..eol] { n = n * 16 + http::hex(c); }
        guard n > 0 else { return; }
        body.append(response[eol + 2..eol + 2 + n]);
        at = eol + 2 + n + 2;
    }
}

fn test_stream() {
    let t = text();
    var b: u8[>..] = [];
    let r = get_with("GET", "Accept-Encoding: gzip\r\n", b);
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, common: COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    var z = http::Compressed { .. };
    http::begin_compressed(c, r, 200, "text/event-stream", z);
    assert(z.coding == http::Coding.Gzip && z.slot == 0);
    http::send_compressed(c, z, t[..1000]);
    // A flush ends a piece with an empty stored block.
    let first = out.len;
    assert(out[first - 7..first - 2] == "\x00\x00\x00\xff\xff");
    http::send_compressed(c, z, t[1000..]);
    http::end_compressed(c, z);
    assert(z.slot == -1 && !st.open && keep);
    assert(value_of(out, "Content-Encoding") == "gzip" && value_of(out, "Transfer-Encoding") == "chunked");
    assert(out[out.len - 5..] == "0\r\n\r\n");
    var gz: u8[>..] = [];
    unchunk(out, gz);
    assert(gz[0] == 0x1f && gz[1] == 0x8b && gz.len < t.len / 2);

    // The pool lends the same encoder again, and a second at once.
    var z2 = http::Compressed { .. };
    http::begin_compressed(c, r, 200, "text/plain", z);
    assert(z.slot == 0);
    http::begin_compressed(c, r, 200, "text/plain", z2);
    assert(z2.slot == 1);
    http::release_compressed(z);
    http::release_compressed(z2);
    http::release_compressed(z2);
    var z3 = http::Compressed { .. };
    http::begin_compressed(c, r, 200, "text/plain", z3);
    assert(z3.slot == 0);
    http::release_compressed(z3);

    // zstd, and identity for a client that takes neither.
    var bz: u8[>..] = [];
    let rz = get_with("GET", "Accept-Encoding: zstd\r\n", bz);
    let mz = out.len;
    http::begin_compressed(c, rz, 200, "text/plain", z);
    assert(z.coding == http::Coding.Zstd && z.slot == 0);
    http::send_compressed(c, z, t);
    http::end_compressed(c, z);
    var zs: u8[>..] = [];
    unchunk(out[mz..], zs);
    assert(zs[0] == 0x28 && zs[1] == 0xb5);

    var bn: u8[>..] = [];
    let rn = get_with("GET", "", bn);
    let mn = out.len;
    http::begin_compressed(c, rn, 200, "text/plain", z);
    assert(z.slot == -1);
    http::send_compressed(c, z, "plain");
    http::end_compressed(c, z);
    var plain: u8[>..] = [];
    unchunk(out[mn..], plain);
    assert(plain == "plain" && value_of(out[mn..], "Vary") == "Accept-Encoding");
}

fn main() {
    test_coding_for();
    test_whole();
    test_stream();
    print("test_compression: ok");
}
