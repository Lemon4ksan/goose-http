// A handler can't write into the common fields the loop shares between
// replies: it adds fields with a copy of its own.
// error: cannot assign through this path
import http from "../../";

fn main() {
    var buf: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let out = http::Reply { buf: buf, common: "", keep_alive: keep, minor: 1, head: false, stream: st };
    out.common[0] = 'x';
}
