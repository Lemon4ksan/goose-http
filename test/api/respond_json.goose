// respond_json: the body a block writes, its length, HEAD, and 204.
import std;
import json;
import http from "../../";
import check from "../";

fn main() {
    var out: u8[>..] = [];
    var keep = true;
    var st = http::Stream { .. };
    let name = "a \"b\"";
    http::respond_json(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st }, 201) { b =>
        b.push('{');
        json::format_key(b, "name");
        json::format_string(b, name);
        b.push(',');
        json::format_key(b, "n");
        json::format_int(b, 7);
        b.push('}');
    };
    check::same(out, "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 24\r\n\r\n{\"name\":\"a \\\"b\\\"\",\"n\":7}");
    print("201: ", out[find(out, "\r\n\r\n") + 4..]);

    // Lengths of 1 to 4 digits, after what the buffer held before; HEAD gets
    // the length without the body, and a 204 neither.
    for size in [0, 9, 10, 1234] {
        out.clear();
        out.append("before");
        http::respond_json(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st }, 200) { b =>
            for i in size { b.push('a' + (i % 26) as! u8); }
        };
        var want: u8[>..] = [];
        want.append("beforeHTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ");
        format(want, size);
        want.append("\r\n\r\n");
        for i in size { want.push('a' + (i % 26) as! u8); }
        check::same(out, want);
        print("a body of ", size, " bytes");
    }
    out.clear();
    http::respond_json(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: true, stream: st }, 200) { b =>
        b.append("[1,2]");
    };
    check::same(out, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 5\r\n\r\n");
    out.clear();
    http::respond_json(http::Reply { buf: out, common: "", keep_alive: keep, minor: 1, head: false, stream: st }, 204) { b =>
        b.append("[1,2]");
    };
    check::same(out, "HTTP/1.1 204 No Content\r\nContent-Type: application/json\r\n\r\n");
    print("HEAD, and 204");
}
