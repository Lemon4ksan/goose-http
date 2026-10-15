// A handler of events can't change the request an Event refers to.
// error: cannot assign through this path
import http from "../../";

fn main() {
    let fresh = false;
    http::serve(http::Config { .. }, fresh) { ev, st, out =>
        ev.req.target = "/";
    };
}
