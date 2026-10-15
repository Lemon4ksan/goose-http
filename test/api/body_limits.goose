// Body limits: body_within, and gather, which collects a body for a handler,
// with 413 past the limit and its run given back when a connection closes.
import std;
import http from "../../";
import check from "../";

// body_within on a request with fields, whole or not, and then pieces, with a
// limit of 10: whether each call let the body through, as "y" or "n", and the
// response.
fn limited(fields: const u8[:], whole: bool, first: const u8[:], pieces: const u8[:][:], out: u8[>..]&) -> u8[>..] {
    var buf: u8[>..] = [];
    let req = check::request("POST", fields, buf);
    var keep = true;
    var st = http::Stream { .. };
    var taken = 0;
    var log: u8[>..] = [];
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    let ok = http::body_within(taken, http::Event { kind: http::REQUEST, req: req, data: first, whole: whole, trailers: "" },
                               reply, 10);
    log.push(if ok { 'y' } else { 'n' });
    if ok {
        for p in pieces {
            let more = http::body_within(taken, http::Event { kind: http::BODY, req: req, data: p, whole: false, trailers: "" },
                                         reply, 10);
            log.push(if more { 'y' } else { 'n' });
            if !more { break; }
        }
    }
    if !keep { log.append(" close"); }
    return log;
}

fn test_body_within() {
    var out: u8[>..] = [];
    check::same(limited("Content-Length: 10\r\n", false, "", [], out), "y");
    check::same(limited("Content-Length: 10\r\n", false, "", ["abcd", "efgh", "ij"], out), "yyyy");
    check::same(limited("Content-Length: 11\r\n", false, "", [], out), "n close");
    check::same(out, "HTTP/1.1 413 Content Too Large\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    check::same(limited("Content-Length: 4\r\n", true, "abcd", [], out), "y");
    check::same(limited("Transfer-Encoding: chunked\r\n", true, "abcdefghijk", [], out), "n close");
    out.clear();
    let pieces = limited("Transfer-Encoding: chunked\r\n", false, "", ["abcd", "efgh", "ij", "k", "l"], out);
    check::same(pieces, "yyyyn close");
    assert(find(out, "413") > 0);
    print("body_within, chunked in pieces: ", pieces);
}

// gather on a request with fields, whose body comes whole as first or else
// in pieces, and then END, with a limit of 10: what the handler got, and
// " close" if the connection closes. out gets the responses.
fn gathered(fields: const u8[:], whole: bool, first: const u8[:], pieces: const u8[:][:], out: u8[>..]&) -> u8[>..] {
    var buf: u8[>..] = [];
    let req = check::request("POST", fields, buf);
    let none = http::Request { .. };
    var keep = true;
    var st = http::Stream { .. };
    var g = http::Gather { .. };
    var log: u8[>..] = [];
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    fn on(kind: u8, r: const http::Request&, data: const u8[:]) {
        http::gather(http::Event { kind: kind, req: r, data: data, whole: whole, trailers: "" }, g, reply, 10) { q, body, o =>
            format(log, q.method, " ", q.target, " ", q.minor, " ", q.body, " ", q.chunked, " [", q.fields, "] [", body,
                   "]");
            http::respond(o, 200, "text/plain", body);
        };
    }
    on(http::REQUEST, req, first);
    // The read buffer is reused once the handler returns.
    for &b in buf { b = 'x'; }
    if !whole {
        for p in pieces { on(http::BODY, none, p); }
        on(http::END, none, "");
    }
    assert(g.len == 0 && g.cap == 0);
    if !keep { log.append(" close"); }
    return log;
}

fn test_gather() {
    var out: u8[>..] = [];
    check::same(gathered("Content-Length: 10\r\n", false, "", ["abcd", "efgh", "ij"], out),
                  "POST /x 1 10 false [Host: x\r\nContent-Length: 10\r\n] [abcdefghij]");
    check::same(out, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 10\r\n\r\nabcdefghij");
    out.clear();
    check::same(gathered("Transfer-Encoding: chunked\r\n", false, "", ["abc", "de"], out),
                  "POST /x 1 0 true [Host: x\r\nTransfer-Encoding: chunked\r\n] [abcde]");
    check::same(gathered("Content-Length: 4\r\n", true, "abcd", [], out),
                  "POST /x 1 4 false [Host: x\r\nContent-Length: 4\r\n] [abcd]");
    print("gather: in pieces, chunked, whole");
    out.clear();
    check::same(gathered("Content-Length: 11\r\n", false, "", ["abcdefghijk"], out), " close");
    check::same(out, "HTTP/1.1 413 Content Too Large\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
    out.clear();
    check::same(gathered("Transfer-Encoding: chunked\r\n", true, "abcdefghijk", [], out), " close");
    assert(find(out, "413") > 0);
    out.clear();
    check::same(gathered("Transfer-Encoding: chunked\r\n", false, "", ["abcd", "efgh", "ij", "k", "l"], out), " close");
    assert(find(out, "413") > 0);
    print("gather past the limit: 413 and close");

    // A connection that closes mid-body gives its run back for the next.
    var buf: u8[>..] = [];
    let req = check::request("POST", "Content-Length: 10\r\n", buf);
    let none = http::Request { .. };
    var keep = true;
    var st = http::Stream { .. };
    var g = http::Gather { .. };
    var calls = 0;
    out.clear();
    let reply = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    for kind in [http::REQUEST, http::BODY, http::CLOSED] {
        http::gather(http::Event { kind: kind, req: if kind == http::REQUEST { req } else { none }, data: "abc",
                                   whole: false, trailers: "" }, g, reply, 10) { q, body, o => calls++; };
        if kind == http::BODY { assert(g.len > g.head && g.cap > 0); }
    }
    assert(calls == 0 && g.len == 0 && g.cap == 0 && out.len == 0);
    print("gather, closed mid-body: no call, its run given back");
}

fn main() {
    test_body_within();
    test_gather();
}
