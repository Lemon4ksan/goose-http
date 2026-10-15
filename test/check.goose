// What the tests under test/ that import the http package share. They
// declare test/ as a package, `import check from "../";`, since a program's
// own imports resolve below its root file's directory.
namespace check;
import std;
import http from "../";

// common_fields's, for Config.server's default.
let COMMON = "Server: goose\r\nDate: Sat, 10 Oct 2026 12:00:00 GMT\r\n";

// Prints both and fails when got isn't want.
fn same(got: const u8[:], want: const u8[:]) {
    if got != want {
        print("got:\n", got, "\nwant:\n", want);
        assert(false);
    }
}

// The status parse gives text.
fn status(text: const u8[:]) -> i32 {
    let r, s = http::parse(text);
    return s;
}

fn expect(text: const u8[:], want: i32) {
    let got = status(text);
    if got != want {
        print("parse of '", text, "': got ", got, ", want ", want);
        assert(false);
    }
}

// The head of a request for /x with the field lines fields, parsed from buf,
// which it fills.
fn request(method: const u8[:], fields: const u8[:], buf: u8[>..]&) -> http::Request {
    buf.clear();
    buf.append(method);
    buf.append(" /x HTTP/1.1\r\nHost: x\r\n");
    buf.append(fields);
    buf.append("\r\n");
    let r, s = http::parse(buf);
    assert(s == 200);
    return r;
}
