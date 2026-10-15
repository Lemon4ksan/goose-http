// Conditional requests and ranges: parse_date, not_modified, range_of, and
// content_range.
import std;
import http from "../../";
import check from "../";

// not_modified for a GET with the fields extra.
fn unchanged(extra: const u8[:], etag: const u8[:], modified: i64) -> bool {
    var b: u8[>..] = [];
    let r = check::request("GET", extra, b);
    return http::not_modified(r, etag, modified);
}

// range_of for a GET with the fields extra, of 100 bytes.
fn range_in_100(extra: const u8[:], etag: const u8[:]) -> i64, i64, i32 {
    var b: u8[>..] = [];
    let r = check::request("GET", extra, b);
    return http::range_of(r, 100, etag);
}

// A Range field, and what range_of makes of it for 100 bytes.
struct Ranged { spec: const u8[:], start: i64, end: i64, status: i32 }

fn main() {
    // Dates as format_date writes them come back.
    for t in [0, 951782400, 1791633600, 4102444799] {
        var d: u8[>..] = [];
        http::format_date(d, t);
        let back, ok = http::parse_date(d);
        assert(ok && back == t);
    }
    let bad, ok = http::parse_date("Sunday, 06-Nov-94 08:49:37 GMT");
    assert(!ok);
    print("parse_date: format_date's dates come back; RFC 850's doesn't parse");

    let etag = "\"v1\"";
    let modified = 1791633600;   // Sat, 10 Oct 2026 12:00:00 GMT
    assert(unchanged("If-None-Match: \"v0\", W/\"v1\"\r\n", etag, modified));
    assert(!unchanged("If-None-Match: \"v2\"\r\n", etag, modified));
    assert(unchanged("If-None-Match: *\r\n", etag, modified));
    assert(unchanged("If-Modified-Since: Sat, 10 Oct 2026 12:00:00 GMT\r\n", etag, modified));
    assert(!unchanged("If-Modified-Since: Sat, 10 Oct 2026 11:59:59 GMT\r\n", etag, modified));
    // If-None-Match decides alone when it's there.
    assert(!unchanged("If-None-Match: \"v2\"\r\nIf-Modified-Since: Sat, 10 Oct 2026 12:00:00 GMT\r\n",
                      etag, modified));
    assert(!unchanged("", etag, modified));
    print("not_modified: If-None-Match, If-Modified-Since");

    // Ranges of a 100-byte representation.
    let cases = [Ranged { spec: "bytes=0-9", start: 0, end: 10, status: 206 },
                 Ranged { spec: "bytes=90-", start: 90, end: 100, status: 206 },
                 Ranged { spec: "bytes=-5", start: 95, end: 100, status: 206 },
                 Ranged { spec: "bytes=-500", start: 0, end: 100, status: 206 },
                 Ranged { spec: "bytes=95-200", start: 95, end: 100, status: 206 },
                 Ranged { spec: "bytes=100-", start: 0, end: 0, status: 416 },
                 Ranged { spec: "bytes=-0", start: 0, end: 0, status: 416 },
                 Ranged { spec: "bytes=0-9,20-29", start: 0, end: 100, status: 200 },
                 Ranged { spec: "items=0-9", start: 0, end: 100, status: 200 },
                 Ranged { spec: "bytes=5-2", start: 0, end: 100, status: 200 },
                 Ranged { spec: "bytes=x-2", start: 0, end: 100, status: 200 }];
    for c in cases {
        var line: u8[>..] = [];
        format(line, "Range: ", c.spec, "\r\n");
        let a, e, s = range_in_100(line, etag);
        if a != c.start || e != c.end || s != c.status {
            print(c.spec, ": ", a, " ", e, " ", s);
            assert(false);
        }
        print(c.spec, ": ", a, "..", e, " ", s);
    }
    let a8, e8, s8 = range_in_100("Range: bytes=0-9\r\nIf-Range: \"v1\"\r\n", etag);
    assert(s8 == 206);
    let a9, e9, s9 = range_in_100("Range: bytes=0-9\r\nIf-Range: \"v0\"\r\n", etag);
    assert(s9 == 200 && e9 == 100);
    print("If-Range: ", s8, " for the same tag, ", s9, " for another");

    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let c = http::Reply { buf: out, common: check::COMMON, keep_alive: keep, minor: 1, head: false, stream: st };
    http::content_range(c, 90, 100, 100);
    http::content_range(c, 0, 0, 100);
    check::same(out, "Content-Range: bytes 90-99/100\r\nContent-Range: bytes */100\r\n");
    print("content_range: bytes 90-99/100, bytes */100");
}
