// A response begun with begin and sent in pieces, and an upgrade.
import std;
import http from "../../";
import check from "../";

fn test_stream() {
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    http::begin(c, 200, -1);
    http::field(c, "Content-Type", "text/plain");
    http::send(c, "hello");
    http::send(c, "");
    http::send(c, "0123456789abcdef!");
    http::end(c);
    check::same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nTransfer-Encoding: chunked\r\nContent-Type: text/plain\r\n\r\n5\r\nhello\r\n11\r\n0123456789abcdef!\r\n0\r\n\r\n");
    assert(keep && !st.open);
    // send and end after end write nothing.
    http::send(c, "late");
    http::end(c);
    assert(out[out.len - 5..] == "0\r\n\r\n");
    print("chunked, and nothing after end");

    // A known length; a body past it is cut, and one short of it closes.
    let m1 = out.len;
    http::begin(c, 200, 7);
    http::send(c, "abc");
    assert(keep);
    http::send(c, "defgh");
    http::end(c);
    check::same(out[m1..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Length: 7\r\n\r\nabcdefg");
    assert(!keep);
    let m2 = out.len;
    keep = true;
    http::begin(c, 200, 5);
    http::end(c);
    assert(!keep && out[out.len - 21..] == "Content-Length: 5\r\n\r\n");
    print("a known length: cut past it, closed short of it");

    // HEAD gets the head alone.
    let m3 = out.len;
    keep = true;
    let h = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: true, stream: st };
    http::begin(h, 200, -1);
    http::send(h, "hello");
    http::end(h);
    check::same(out[m3..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nTransfer-Encoding: chunked\r\n\r\n");
    assert(keep);

    // HTTP/1.0 has no chunks: the body ends at the close.
    let m4 = out.len;
    let old = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 0, head: false, stream: st };
    http::begin(old, 200, -1);
    http::send(old, "hello");
    http::end(old);
    check::same(out[m4..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\n\r\nhello");
    assert(!keep);

    // 204 has no body, and no framing.
    let m5 = out.len;
    keep = true;
    http::begin(c, 204, -1);
    http::send(c, "hello");
    http::end(c);
    check::same(out[m5..], "HTTP/1.1 204 No Content\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\n\r\n");
    assert(keep);
    print("HEAD, HTTP/1.0, 204");

    // Trailers after a chunked body.
    let m6 = out.len;
    http::begin(c, 200, -1);
    http::send(c, "ab");
    http::end(c, "Digest: x\r\n");
    check::same(out[m6..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n0\r\nDigest: x\r\n\r\n");

    // A trailer line field would drop is dropped, and the rest go out as
    // fields do; a bare LF can't end one.
    let m7 = out.len;
    http::begin(c, 200, -1);
    http::end(c, "A:1\r\nB C: 2\r\nD: 3\nE: 4\r\nno colon\r\n\r\nF:\t5 \r\nG: \x01\r\n");
    check::same(out[m7..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nA: 1\r\nF: 5\r\n\r\n");
    print("trailers, and those dropped");
}

fn test_upgrade() {
    let r, s = http::parse("GET /chat HTTP/1.1\r\nHost: x\r\nConnection: keep-alive, Upgrade\r\nUpgrade: websocket\r\n\r\n");
    assert(s == 200 && http::upgrade_of(r) == "websocket");
    // Without Connection: upgrade, and in HTTP/1.0, there's none.
    let r2, s2 = http::parse("GET /chat HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n\r\n");
    assert(s2 == 200 && http::upgrade_of(r2) == "");
    let r3, s3 = http::parse("GET /chat HTTP/1.0\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n");
    assert(s3 == 200 && http::upgrade_of(r3) == "");

    // 101, then bytes as they are, until end closes the connection.
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    http::upgrade(c, "websocket");
    http::send(c, "\x81\x00");
    check::same(out, "HTTP/1.1 101 Switching Protocols\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n\x81\x00");
    assert(st.open && keep);
    http::end(c);
    assert(!st.open && !keep);
    print("upgrade: ", http::upgrade_of(r), ", 101, and end closes");
}

fn main() {
    test_stream();
    test_upgrade();
}
