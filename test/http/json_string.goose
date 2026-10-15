// json_string: strings with no escape, each kind, and escapes at either end
// of a 16-byte block, against json::format_string.
import std;
import json;
import http from "../../";
import check from "../";

fn agrees(s: u8[:]) -> u8[>..] {
    var got: u8[>..] = [];
    var want: u8[>..] = [];
    http::json_string(got, s);
    json::format_string(want, s);
    check::same(got, want);
    return got;
}

fn main() {
    print("plain: ", agrees("Hello, World! caf\xc3\xa9"));
    print("empty: ", agrees(""));
    print("quote: ", agrees("a\"b"));
    print("backslash: ", agrees("a\\b"));
    print("newline: ", agrees("a\nb"));
    print("tab, CR, backspace, form feed: ", agrees("\t\r\x08\x0c"));
    print("NUL, 0x01, 0x1f: ", agrees("\x00\x01\x1f"));
    print("only escapes: ", agrees("\"\\\"\\"));
    print("after 16 bytes: ", agrees("0123456789abcdefghij\"klm"));
    print("at the end: ", agrees("0123456789abcdefghij\n"));
    print("at the start: ", agrees("\x01ABCDEFGHIJKLMNOPQRST"));

    // Every byte, alone and at each offset of a 40-byte string.
    var s: u8[>..] = [];
    for c in 256 {
        for at in 40 {
            s.clear();
            for i in 40 { s.push(if i == at { c as u8 } else { 'a' + (i % 26) as! u8 }); }
            agrees(s);
        }
    }
    print("every byte at every offset of 40");

    // Appends after what the buffer held.
    var out: u8[>..] = [];
    out.append("{\"a\":");
    http::json_string(out, "x\ny");
    out.push('}');
    check::same(out, "{\"a\":\"x\\ny\"}");
    print("after a prefix: ", out);
}
