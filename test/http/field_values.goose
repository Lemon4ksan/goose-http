// A header value scanned by find_any: each kind of byte at every offset of a
// value longer than four of its 16-byte blocks, from every alignment, so both
// the search and the byte loop after it meet it. Tab, space, visible bytes,
// and obs-text are allowed; other control bytes, a bare CR included, and DEL
// aren't.
import std;
import http from "../../";
import check from "../";

fn main() {
    let kinds: u8[] = [0, 9, 13, 31, 32, 126, 127, 128, 255];
    var checked = 0;
    for kind in kinds {
        let want: i32 = if kind == 9 || (kind >= 32 && kind != 127) { 200 } else { 400 };
        for shift in 32 {
            for at in 80 {
                var req: u8[>..] = [];
                req.append("GET / HTTP/1.1\r\nHost: x\r\nX");
                for i in shift { req.push('x'); }
                req.append(": ");
                for i in 80 { req.push(if i == at { kind } else { 'a' + (i % 26) as! u8 }); }
                req.append("\r\n\r\n");
                let got = check::status(req);
                if got != want {
                    print("byte ", kind, " at ", at, " after ", shift, ": got ", got, ", want ", want);
                    assert(false);
                }
                checked++;
            }
        }
        print("byte ", kind, ": ", want);
    }
    print(checked, " values checked");
}
