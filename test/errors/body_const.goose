// A handler can't write into the body it's given, which is the read buffer.
// error: cannot assign through this path
import http from "../../";

fn main() {
    http::serve(http::Config { .. }) { req, body, out =>
        body[0] = 'x';
    };
}
