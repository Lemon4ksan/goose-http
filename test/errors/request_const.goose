// A handler can't change the request it's given: its slices point into the
// read buffer.
// error: cannot assign through this path
import http from "../../";

fn main() {
    http::serve(http::Config { .. }) { req, body, out =>
        req.method = "POST";
    };
}
