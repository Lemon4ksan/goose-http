// The files of a directory, the one the command line names or the current
// one: with ranges (206, 416), conditional requests (304), and a .br, .zst,
// or .gz copy made beforehand when the request accepts it.
//
//   ./build/examples/files docs
//   curl -r 0-99 localhost:8080/files/development.md
//   curl -H 'If-None-Match: "..."' localhost:8080/files/development.md
import std;
import os;
import http from "../../";

// What the response still has to send, between the handler's calls.
struct Download { file: http::FileBody = http::FileBody { .. } }

thread_fn worker(cfg: http::Config, dir: u8[..256]) {
    let e = http::serve(cfg, Download { .. }) { ev, st, out =>
        if ev.kind == http::REQUEST {
            var r = http::router(ev.req);
            if http::on(r, "GET", "/files/*path") {
                download(ev.req, dir, http::param(r, "path"), st, out);
            } else {
                http::otherwise(r, out);
            }
        } else if ev.kind == http::MORE {
            if !http::send_file(out, st.file) { http::end(out); }
        } else if ev.kind == http::CLOSED {
            http::close_body(st.file);
        }
    };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

// Answers with the file in dir that name names. The router leaves name
// percent-encoded; file_path decodes it, and checks it doesn't leave dir.
fn download(req: const http::Request&, dir: const u8[:], name: const u8[:], st: Download&, out: http::Reply) {
    var path: u8[>..] = [];
    guard http::file_path(dir, name, path) else {
        http::respond(out, 404, "text/plain", "");
        return;
    }
    let f, status = http::open_precompressed(req, path);
    guard status == 200 else { http::respond(out, status, "text/plain", ""); return; }
    // The head now, and the body at each MORE.
    http::serve_file(req, out, f, http::content_type_of(path), st.file);
}

fn main() {
    let argv = args();
    var dir: u8[..256] = ".";
    if argv.len > 1 {
        guard argv[1].len <= 256 else { write_stderr("the directory's path is longer than 256 bytes\n"); exit(2); }
        dir.clear();
        dir.append(argv[1]);
    }
    http::exit_on_error(http::stop_on_signals());
    let cfg = http::Config { port: 8080, .. };
    print("serving ", dir, " on port ", cfg.port);
    http::run(cfg, dir, worker);
}
