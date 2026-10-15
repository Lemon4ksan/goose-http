// A handler's writers, into a reply as the loops make one: respond, start
// and finish, bodyless statuses, refused fields, and insert_field.
import std;
import http from "../../";
import check from "../";

fn test_reply() {
    var out: u8[>..] = [];
    var keep = true;
    var nobody = http::Stream { .. };
    http::respond(http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: nobody },
                  201, "text/plain", "made");
    check::same(out, "HTTP/1.1 201 Created\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 4\r\n\r\nmade");

    // A field of the handler's own, a status with no reason phrase, and a
    // handler that closes the connection.
    out.clear();
    keep = false;
    let r = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: nobody };
    http::start(r, 299);
    assert(http::field(r, "X-Thing", "a b"));
    http::finish(r, "Content-Length: ", "hi");
    check::same(out, "HTTP/1.1 299 \r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nX-Thing: a b\r\nContent-Length: 2\r\n\r\nhi");

    // HEAD gets the body's fields without the body, and HTTP/1.0 kept alive
    // says so.
    out.clear();
    keep = true;
    http::respond(http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 0, head: true, stream: nobody },
                  200, "a/b", "body");
    check::same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: keep-alive\r\nContent-Type: a/b\r\nContent-Length: 4\r\n\r\n");
    print("respond, start and finish, HEAD, HTTP/1.0 kept alive");

    // 1xx, 204, and 304 get neither a Content-Length nor a body, whatever
    // the handler writes, and a HEAD for one gets the same.
    let bodyless: i32[] = [204, 304, 103];
    for status in bodyless {
        out.clear();
        keep = true;
        http::respond(http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: nobody },
                      status, "text/plain", "body");
        assert(nobody.bodyless);
        assert(find(out, "Content-Length") < 0 && out[out.len - 4..] == "\r\n\r\n");
        assert(find(out, "Content-Type: text/plain\r\n\r\n") > 0);
    }
    out.clear();
    let r304 = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: true, stream: nobody };
    http::start(r304, 304);
    http::field(r304, "ETag", "\"x\"");
    http::finish(r304, "", "ignored");
    check::same(out, "HTTP/1.1 304 Not Modified\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nETag: \"x\"\r\n\r\n");
    // A body status after them gets its length again.
    out.clear();
    http::respond(http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: nobody },
                  200, "text/plain", "ok");
    assert(!nobody.bodyless && find(out, "Content-Length: 2\r\n\r\nok") > 0);
    // An empty content type writes none, as a 204 wants.
    out.clear();
    http::respond(http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: nobody },
                  204, "", "");
    check::same(out, "HTTP/1.1 204 No Content\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\n\r\n");
    print("bodyless: 204, 304, 103, and HEAD for 304");

    // A handler clears keep_alive through its copy of the reply.
    keep = true;
    out.clear();
    let close = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: nobody };
    close.keep_alive = false;
    assert(!keep);

    // A limited array takes responses as the server's write buffer does.
    var wbuf: u8[..256] = [];
    http::refuse(wbuf, 431, check::COMMON);
    check::same(wbuf, "HTTP/1.1 431 Request Header Fields Too Large\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
    print("keep_alive through the reply; refuse into a limited array");

    // A field with CR, LF, or a bad name never reaches the client: it's
    // dropped, and so is a bad content type.
    keep = true;
    assert(http::is_field("X-A", "b c") && http::is_field("X-A", "") && http::is_field("!#$%&'*+-.^_`|~09", "\x80\tx"));
    let bad_names = ["", "X A", "X:A", "X\r\nY", "X\x80", "(X)", "X\t"];
    let bad_values = ["a\r\nSet-Cookie: x=1", "a\nb", "a\rb", "a\x00", "a\x7f", " a", "a\t", "\r\n"];
    for n in bad_names {
        out.clear();
        let bn = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: nobody };
        http::start(bn, 200);
        assert(!http::field(bn, n, "v"));
        http::finish(bn, "Content-Length: ", "");
        check::same(out, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n");
    }
    for v in bad_values {
        out.clear();
        let bv = http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: nobody };
        http::start(bv, 302);
        assert(!http::field(bv, "Location", v));
        http::finish(bv, "Content-Length: ", "");
        check::same(out, "HTTP/1.1 302 Found\r\nContent-Length: 0\r\n\r\n");
        out.clear();
        http::respond(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: nobody },
                      200, v, "");
        check::same(out, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n");
    }
    print("dropped: ", bad_names.len, " field names, ", bad_values.len, " values");

    var j: u8[>..] = [];
    http::json_string(j, "a\"b\\c\n\x01");
    check::same(j, "\"a\\\"b\\\\c\\u000a\\u0001\"");
    print("json_string: ", j);
}

fn test_insert_field() {
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let r = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };

    // After the head's last field, in the response begun at mark only, with
    // its body moved up.
    http::respond(r, 200, "text/plain", "one");
    let mark = out.len;
    http::respond(r, 200, "text/plain", "a\r\n\r\nb");
    assert(http::insert_field(r, mark, "Server-Timing", "app;dur=1.5"));
    check::same(out[mark..], "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Type: text/plain\r\nContent-Length: 6\r\nServer-Timing: app;dur=1.5\r\n\r\na\r\n\r\nb");
    assert(out[mark - 3..mark] == "one");

    // A bodyless status's head, and begin's head while it's open. A Reply
    // holds out, so each clear takes a new one.
    out.clear();
    let r204 = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    http::start(r204, 204);
    http::finish(r204, "", "");
    assert(http::insert_field(r204, 0, "X-A", "1"));
    check::same(out, "HTTP/1.1 204 No Content\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nX-A: 1\r\n\r\n");
    out.clear();
    let open = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    http::begin(open, 200, 2);
    assert(http::insert_field(open, 0, "X-A", "1"));
    http::send(open, "hi");
    http::end(open);
    check::same(out, "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nContent-Length: 2\r\nX-A: 1\r\n\r\nhi");

    // Nothing without a response after mark, or for a field is_field refuses.
    let all = out.len;
    assert(!http::insert_field(open, all, "X-A", "1"));
    assert(!http::insert_field(open, 0, "X-A", "1\r\nX-B: 2"));
    assert(!http::insert_field(open, 0, "X A", "1"));
    assert(out.len == all);

    // Fields a handler adds to common go after the loop's in each start.
    out.clear();
    let mine = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    var extra: u8[>..] = [];
    extra.append(mine.common);
    extra.append("X-Frame-Options: DENY\r\n");
    mine.common = extra;
    http::respond(mine, 404, "text/plain", "");
    check::same(out, "HTTP/1.1 404 Not Found\r\nServer: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\nX-Frame-Options: DENY\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n");
    print("insert_field: after a body, a bodyless head, an open one; refused; fields added to common");
}

fn main() {
    test_reply();
    test_insert_field();
}
