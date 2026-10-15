// Form bodies: each_form and form_value, and multipart bodies in pieces of
// every size, with their limits, failures, and fail_multipart.
import std;
import http from "../../";
import check from "../";

fn test_form() {
    var got: u8[>..] = [];
    http::each_form("a=1&&b=x+y%21&c&=z") { k, v =>
        got.append(k);
        got.push('=');
        got.append(v);
        got.push('|');
    };
    check::same(got, "a=1|b=x+y%21|c=|=z|");
    var v: u8[>..] = [];
    assert(http::form_value("a=1&b=x+y%21&b=2", "b", v) && v == "x y!");
    assert(http::form_value("k%20ey=1&k+ey=2", "k ey", v) && v == "1");
    assert(http::form_value("a=%zz&a=ok", "a", v) && v == "ok");
    assert(!http::form_value("a=1", "b", v) && v == "ok");
    assert(!http::form_value("a=%zz", "a", v));
    print("form: ", got);
}

// A multipart body: two fields, a file with CRLF and boundary-like bytes in
// it, a preamble, and an epilogue.
let MULTIPART = "preamble\r\n--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\none\r\n--XyZ \t\r\nContent-Disposition: form-data; name=\"f\"; filename=\"x \\\"y\\\".txt\"\r\nContent-Type: text/plain\r\n\r\nline\r\n--XyY\r\n-\r\n--Xy\r\n--XyZ\r\n\r\n\r\n--XyZ--\r\nepilogue";

// The parts of body read k bytes at a time, as "head|data|" with an End
// mark, or "fail".
fn parts_in_pieces(req: http::Request, body: const u8[:], k: i64) -> u8[>..] {
    var m = http::Multipart { .. };
    var log: u8[>..] = [];
    assert(http::start_multipart(req, m));
    var at = 0;
    while at < body.len {
        let piece = body[at..min(at + k, body.len)];
        at += piece.len;
        let ok = http::each_part(m, piece) { part =>
            match part {
                Head h => {
                    let name, filename, okd = http::disposition(h.fields);
                    log.append("[");
                    log.append(name);
                    log.append(",");
                    log.append(filename);
                    log.append("]");
                },
                Data d => { log.append(d.bytes); },
                End => { log.append("<end>"); },
            }
        };
        if !ok { log.append("<fail>"); }
    }
    if http::multipart_done(m) { log.append("<done>"); }
    return log;
}

// The parts of MULTIPART read k bytes at a time, as 'h', 'd', and 'e' for
// Head, Data, and End, with the function failing m at its nth call.
fn failed_at(req: const http::Request&, k: i64, n: i64) -> u8[>..] {
    var m = http::Multipart { .. };
    var log: u8[>..] = [];
    assert(http::start_multipart(req, m));
    var calls = 0;
    var at = 0;
    while at < MULTIPART.len {
        let piece = MULTIPART[at..min(at + k, MULTIPART.len)];
        at += piece.len;
        let ok = http::each_part(m, piece) { part =>
            calls++;
            log.push(match part { Head h => 'h', Data d => 'd', End => 'e' });
            if calls == n { http::fail_multipart(m); }
        };
        if !ok { log.append("<fail>"); }
    }
    if http::multipart_done(m) { log.append("<done>"); }
    return log;
}

// Whether start_multipart takes a request with fields.
fn takes(fields: const u8[:]) -> bool {
    var buf: u8[>..] = [];
    var m = http::Multipart { .. };
    let req = check::request("POST", fields, buf);
    return http::start_multipart(req, m);
}

fn test_multipart() {
    var buf: u8[>..] = [];
    let req = check::request("POST", "Content-Type: multipart/form-data; boundary=XyZ\r\n", buf);
    let want = "[a,]one<end>[f,x \\\"y\\\".txt]line\r\n--XyY\r\n-\r\n--Xy<end>[,]<end><done>";
    for k in MULTIPART.len {
        let got = parts_in_pieces(req, MULTIPART, k + 1);
        if got != want {
            print("in pieces of ", k + 1, ":");
            check::same(got, want);
        }
    }
    print("multipart: in pieces of 1 to ", MULTIPART.len, " bytes");

    // A boundary must be there, be at most 70 characters, and be quoted to
    // hold a space.
    assert(!takes("Content-Type: multipart/form-data\r\n"));
    assert(!takes("Content-Type: multipart/mixed; boundary=a\r\n"));
    assert(takes("Content-Type: Multipart/Form-Data; boundary=\"a b\"\r\n"));
    assert(!takes("Content-Type: multipart/form-data; boundary=\"a@b\"\r\n"));
    var long: u8[>..] = [];
    long.append("Content-Type: multipart/form-data; boundary=");
    for i in 70 { long.push('x'); }
    long.append("\r\n");
    assert(takes(long));
    long.resize(long.len - 2);
    long.append("x\r\n");
    assert(!takes(long));
    print("boundaries: missing, mixed, quoted, invalid, 70 and 71 characters");

    // A delimiter followed by neither CRLF nor "--", and a part head that
    // isn't field lines, fail the body.
    assert(parts_in_pieces(req, "--XyZx\r\n", 100) == "<fail>");
    assert(parts_in_pieces(req, "--XyZ\r\nno colon\r\n\r\n", 100) == "<fail>");
    assert(parts_in_pieces(req, "--XyZ\r\nA: b\nc\r\n\r\n", 100) == "<fail>");
    // A part's head may be MAX_PART_HEAD bytes, its blank line aside, in
    // pieces or not, and no longer.
    for extra in [0, 1] {
        var long: u8[>..] = [];
        long.append("--XyZ\r\nX: ");
        for i in http::MAX_PART_HEAD - 5 + extra { long.push('v'); }
        long.append("\r\n\r\nab\r\n--XyZ--");
        let whole = parts_in_pieces(req, long, long.len);
        let pieces = parts_in_pieces(req, long, 100);
        let want = if extra == 0 { "[,]ab<end><done>" } else { "<fail>" };
        assert(whole == pieces && pieces == want);
    }
    // A body cut short isn't done.
    assert(parts_in_pieces(req, "--XyZ\r\n\r\nab", 100) == "[,]ab");
    print("failed bodies; a part head of ", http::MAX_PART_HEAD, " bytes; a body cut short");

    // fail_multipart from each_part's function, at each of its calls: none
    // follows, that each_part and every later one return false, and the body
    // isn't done. In smaller pieces, a part's content comes in more calls.
    check::same(failed_at(req, MULTIPART.len, 0), "hdehdehe<done>");
    for k in [1, 7, MULTIPART.len] {
        let all = failed_at(req, k, 0);
        assert(all.ends_with("<done>"));
        for n in 1..all.len - 5 {
            let got = failed_at(req, k, n);
            let f = find(got, "<fail>");
            assert(f == n);
            check::same(got[..f], all[..n]);
            var at = f;
            while at < got.len {
                check::same(got[at..at + 6], "<fail>");
                at += 6;
            }
        }
        print("fail_multipart at each of ", all.len - 6, " calls, in pieces of ", k);
    }
}

fn main() {
    test_form();
    test_multipart();
}
