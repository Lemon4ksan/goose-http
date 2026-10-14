// A JSON API: notes read by id, written with a bearer token, and a visit
// count kept in a cookie.
//
//   curl -H 'Authorization: Bearer let-me-in' -H 'Content-Type: application/json' \
//        -d '{"text":"buy milk"}' localhost:8080/notes
//   curl localhost:8080/notes/1
//   curl -c jar -b jar localhost:8080/visits
import std;
import json;
import http from "../../";

struct Note { text: u8[..200], live: bool = true }

let TOKEN = "let-me-in";

thread_fn worker(cfg: http::Config) {
    // Each worker has its own notes: a note written through one connection
    // isn't there for a connection another worker took.
    var notes: Note[>..] = [];
    // A function of its own, not the block: a block's return would return from
    // worker, ending its loop with the request unanswered.
    let e = http::serve(cfg) { req, body, out => answer(req, body, out, notes); };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn answer(req: http::Request, body: const u8[:], out: http::Reply, notes: Note[>..]&) {
    var r = http::router(req);
    if http::on(r, "GET", "/notes/:id") {
        let i = index_of(http::param(r, "id"), notes);
        guard i >= 0 else { http::respond(out, 404, "text/plain", ""); return; }
        http::respond_json(out, 200) { b =>
            b.push('{');
            json::format_key(b, "id");
            json::format_int(b, i + 1);
            b.push(',');
            json::format_key(b, "text");
            json::format_string(b, notes[i].text);
            b.push('}');
        };
    } else if http::on(r, "POST", "/notes") {
        guard authorized(req, out) else { return; }
        guard http::require_type(req, out, "application/json") else { return; }
        var n = Note { text: "", .. };
        guard read_note(body, n) else { http::respond(out, 422, "text/plain", "want {\"text\": \"...\"}"); return; }
        notes.push(n);
        http::respond_json(out, 201) { b =>
            b.push('{');
            json::format_key(b, "id");
            json::format_int(b, notes.len);
            b.push('}');
        };
    } else if http::on(r, "DELETE", "/notes/:id") {
        guard authorized(req, out) else { return; }
        let i = index_of(http::param(r, "id"), notes);
        guard i >= 0 else { http::respond(out, 404, "text/plain", ""); return; }
        notes[i].live = false;
        http::start(out, 204);
        http::finish(out, "", "");
    } else if http::on(r, "GET", "/visits") {
        // The visits so far, counted in a cookie.
        let v, has = http::cookie_of(req, "visits");
        let n, ok = parse_int(v);
        let visits = if has && ok && n >= 0 { n + 1 } else { 1 };
        var text: u8[..24] = [];
        format(text, visits);
        http::start(out, 200);
        http::set_cookie(out, http::Cookie { name: "visits", value: text, max_age: 86400, http_only: true,
                                             same_site: "Lax", .. });
        http::finish(out, "Content-Type: text/plain\r\nContent-Length: ", text);
    } else {
        http::otherwise(r, out);
    }
}

// Whether req carries the bearer token; if not, answers 401.
fn authorized(req: http::Request, out: http::Reply) -> bool {
    let scheme, credentials, ok = http::authorization(req);
    guard ok && http::eq_fold(scheme, "bearer") && credentials == TOKEN else {
        http::challenge(out, "Bearer realm=\"notes\"");
        return false;
    }
    return true;
}

// The index of the live note id names, or -1.
fn index_of(id: const u8[:], notes: const Note[:]) -> i64 {
    let n, ok = parse_int(id);
    guard ok && n >= 1 && n <= notes.len && notes[n - 1].live else { return -1; }
    return n - 1;
}

// Reads {"text": "..."} into n. False for other JSON, a text longer than a
// note holds, or a body too long for the read buffer, which comes empty.
fn read_note(body: const u8[:], n: Note&) -> bool {
    var scratch: u8[>..] = [];
    var r = json::reader(body);
    var has = false;
    guard json::peek(r) == '{' else { return false; }
    json::each_member(r) { key =>
        if key == "text" {
            let s = json::read_string(r, scratch);
            if s.len <= 200 {
                n.text.clear();
                n.text.append(s);
                has = true;
            }
        } else {
            json::skip(r);
        }
    };
    return json::finish(r) && has;
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
