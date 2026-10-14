// The package's server with a handler in C: each request goes to gh_handle,
// which handler.c defines and goose_http.h describes. A C handler can't call
// the package's Goose functions, since C calls Goose only on the thread that
// started it (spec §7.11), and the handler runs on the workers; so it gets the
// request's bytes, and gives back a status, a content type, and a body.
import std;
import http from "../../";

// goose_http.h's gh_response.
struct CResponse {
    status: i32,
    content_type_len: i32,
    content_type: u8[64],
}

// Writes the body into out, which it may not keep past the call, and returns
// its length, or -1 for a 500.
extern fn gh_handle(method: const u8[:], target: const u8[:], fields: const u8[:],
                    body: const u8[:], content_length: i64, res: CResponse&, out: u8[:]) -> i64;

// The most body a response may have: the size of each worker's buffer for it.
let MAX_RESPONSE = 1 << 20;

thread_fn worker(cfg: http::Config) {
    var scratch: u8[>..] = [];
    scratch.resize(MAX_RESPONSE, 0);
    let e = http::serve(cfg) { req, body, out =>
        var res = CResponse { status: 200, content_type_len: 0, content_type: [0; 64] };
        let n = gh_handle(req.method, req.target, req.fields, body, req.body, res, scratch);
        if n < 0 || n > scratch.len || res.status < 100 || res.status > 999 ||
           res.content_type_len < 0 || res.content_type_len > 64 {
            http::respond(out, 500, "text/plain", "");
        } else {
            http::start(out, res.status);
            if res.content_type_len > 0 {
                http::field(out, "Content-Type", res.content_type[..res.content_type_len]);
            }
            http::finish(out, http::NO_TYPE, scratch[..n]);
        }
    };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn main() {
    http::exit_on_error(http::stop_on_signals());
    let cfg = http::Config { port: 8080, .. };
    print("listening on port ", cfg.port);
    var ids: i64[>..] = [];
    for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
    for id in ids { thread_wait(id); }
}
