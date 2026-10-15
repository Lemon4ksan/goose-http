// json_string: strings with no escape, each kind, and escapes at either end
// of a 16-byte block, against a byte at a time.
import std;
import http from "../../";
import check from "../";

// What json_string writes, a byte at a time.
fn bytewise(out: u8[>..]&, s: const u8[:]) {
    out.push('"');
    for c in s {
        if c == '"' || c == '\\' {
            out.push('\\');
            out.push(c);
        } else if c < ' ' {
            out.append("\\u00");
            out.push("0123456789abcdef"[c >> 4]);
            out.push("0123456789abcdef"[c & 15]);
        } else {
            out.push(c);
        }
    }
    out.push('"');
}

fn agrees(s: const u8[:]) -> u8[>..] {
    var got: u8[>..] = [];
    var want: u8[>..] = [];
    http::json_string(got, s);
    bytewise(want, s);
    check::same(got, want);
    return got;
}

fn main() {
    print("plain: ", agrees("Hello, World! caf\xc3\xa9"));
    print("empty: ", agrees(""));
    print("quote: ", agrees("a\"b"));
    print("backslash: ", agrees("a\\b"));
    print("newline: ", agrees("a\nb"));
    print("tab, CR, NUL, 0x1f: ", agrees("\t\r\x00\x1f"));
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
    check::same(out, "{\"a\":\"x\\u000ay\"}");
    print("after a prefix: ", out);
}
