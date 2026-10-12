// Routes with parameters, a JSON response, a request body, and a graceful
// stop on Ctrl+C. The router answers 404, or 405 with Allow, for the rest.
//
//   curl localhost:8080/users/42
//   curl -d 'hi' localhost:8080/echo
import std;
import json;
import http from "../../";

thread_fn worker(cfg: http::Config) {
    let e = http::serve(cfg) { req, body, out =>
        var r = http::router(req);
        if http::on(r, "GET", "/") {
            http::respond(out, 200, "text/plain", "Hello, World!");
        } else if http::on(r, "GET", "/users/:id") {
            let id = http::param(r, "id");
            http::respond_json(out, 200) { b =>
                b.push('{');
                json::format_key(b, "id");
                json::format_string(b, id);
                b.push('}');
            };
        } else if http::on(r, "POST", "/echo") {
            // A body that fits in the read buffer with its head comes whole;
            // a longer one is empty here (http::serve with state reads it in
            // pieces).
            http::respond(out, 200, "application/octet-stream", body);
        } else {
            http::otherwise(r, out);
        }
    };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn main() {
    let s = http::stop_on_signals();
    guard s == 0 else { http::report(http::Error { call: "sigaction", code: -s }); exit(1); }
    let cfg = http::Config { port: 8080, .. };
    print("listening on port ", cfg.port);
    var ids: i64[>..] = [];
    for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
    for id in ids { thread_wait(id); }
}
