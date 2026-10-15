// A JSON API: notes listed as JSON or CSV by Accept, read by id with an
// entity tag, written as JSON or a form with a bearer token, and deleted
// with Basic credentials; a visit count kept in a cookie; and the client's
// address, through a trusted proxy.
//
//   curl -H 'Authorization: Bearer let-me-in' -H 'Content-Type: application/json' \
//        -d '{"text":"buy milk"}' localhost:8080/notes
//   curl -H 'Authorization: Bearer let-me-in' -d 'text=call+mum' localhost:8080/notes
//   curl -H 'Accept: text/csv' localhost:8080/notes
//   curl -H 'If-None-Match: "1"' localhost:8080/notes/1
//   curl -u admin:secret -X DELETE localhost:8080/notes/1
//   curl -c jar -b jar localhost:8080/visits
//   curl -H 'X-Forwarded-For: 203.0.113.7' localhost:8080/whoami
import std;
import json;
import http from "../../";

struct Note { text: u8[..200], live: bool = true }

let TOKEN = "let-me-in";
let ADMIN = "admin";
let PASSWORD = "secret";

thread_fn worker(cfg: http::Config) {
    // Each worker has its own notes: a note written through one connection
    // isn't there for a connection another worker took.
    var notes: Note[>..] = [];
    // The proxies trusted to say who the client is: here, this machine.
    var trusted: http::Network[>..] = [];
    for text in ["127.0.0.0/8", "::1"] {
        let n, ok = http::network(text);
        if ok { trusted.push(n); }
    }
    // A function of its own, not the block: a block's return would return from
    // worker, ending its loop with the request unanswered.
    let e = http::serve(cfg) { req, body, out => answer(req, body, out, notes, trusted); };
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn answer(req: const http::Request&, body: const u8[:], out: http::Reply, notes: Note[>..]&,
          trusted: const http::Network[:]) {
    var r = http::router(req);
    if http::on(r, "GET", "/notes") {
        let pick = http::accept_or_406(req, out, ["application/json", "text/csv"]);
        if pick == 0 { list_json(notes, out); }
        else if pick == 1 { list_csv(notes, out); }
    } else if http::on(r, "GET", "/notes/:id") {
        let i = index_of(http::param(r, "id"), notes);
        guard i >= 0 else { http::respond(out, 404, "text/plain", ""); return; }
        // A note never changes, so its id serves as its entity tag.
        var tag: u8[..24] = [];
        format(tag, "\"", i + 1, "\"");
        if http::not_modified(req, tag, -1) {
            http::start(out, 304);
            http::field(out, "ETag", tag);
            http::finish(out, http::NO_TYPE, "");
            return;
        }
        var b: u8[>..] = [];
        b.push('{');
        json::format_key(b, "id");
        json::format_int(b, i + 1);
        b.push(',');
        json::format_key(b, "text");
        json::format_string(b, notes[i].text);
        b.push('}');
        http::start(out, 200);
        http::field(out, "ETag", tag);
        http::finish(out, http::JSON, b);
    } else if http::on(r, "POST", "/notes") {
        guard authorized(req, out) else { return; }
        var n = Note { text: "", .. };
        if http::has_type(req, "application/x-www-form-urlencoded") {
            var text: u8[>..] = [];
            guard http::form_value(body, "text", text) && text.len <= 200 else {
                http::respond(out, 422, "text/plain", "want text=...");
                return;
            }
            n.text.append(text);
        } else {
            guard http::require_type(req, out, "application/json") else { return; }
            guard read_note(body, n) else { http::respond(out, 422, "text/plain", "want {\"text\": \"...\"}"); return; }
        }
        notes.push(n);
        http::respond_json(out, 201) { b =>
            b.push('{');
            json::format_key(b, "id");
            json::format_int(b, notes.len);
            b.push('}');
        };
    } else if http::on(r, "DELETE", "/notes/:id") {
        guard admin(req, out) else { return; }
        let i = index_of(http::param(r, "id"), notes);
        guard i >= 0 else { http::respond(out, 404, "text/plain", ""); return; }
        notes[i].live = false;
        http::respond(out, 204, "", "");
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
        http::finish(out, http::TEXT, text);
    } else if http::on(r, "GET", "/whoami") {
        // The peer, or, when the peer is a trusted proxy, the client it
        // forwarded for.
        let a, ok = http::client(req, out, trusted);
        var text: u8[>..] = [];
        if ok { http::format_address(text, a); } else { text.append("unknown"); }
        text.push('\n');
        http::respond(out, 200, "text/plain", text);
    } else {
        http::otherwise(r, out);
    }
}

fn list_json(notes: const Note[:], out: http::Reply) {
    http::respond_json(out, 200) { b =>
        b.push('[');
        var first = true;
        for n, i in notes {
            guard n.live else { continue; }
            if !first { b.push(','); }
            first = false;
            b.push('{');
            json::format_key(b, "id");
            json::format_int(b, i + 1);
            b.push(',');
            json::format_key(b, "text");
            json::format_string(b, n.text);
            b.push('}');
        }
        b.push(']');
    };
}

// id,text, with the text quoted and its quotes doubled (RFC 4180).
fn list_csv(notes: const Note[:], out: http::Reply) {
    var b: u8[>..] = [];
    b.append("id,text\r\n");
    for n, i in notes {
        guard n.live else { continue; }
        format(b, i + 1, ",\"");
        for c in n.text {
            if c == '"' { b.push('"'); }
            b.push(c);
        }
        b.append("\"\r\n");
    }
    http::start(out, 200);
    http::finish(out, "Content-Type: text/csv\r\nContent-Length: ", b);
}

// Whether req carries the bearer token; if not, answers 401.
fn authorized(req: const http::Request&, out: http::Reply) -> bool {
    let token, ok = http::bearer(req);
    guard ok && token == TOKEN else {
        http::challenge(out, "Bearer realm=\"notes\"");
        return false;
    }
    return true;
}

// Whether req carries the admin's Basic credentials; if not, answers 401.
fn admin(req: const http::Request&, out: http::Reply) -> bool {
    var decoded: u8[>..] = [];
    let user, password, ok = http::basic_auth(req, decoded);
    guard ok && user == ADMIN && password == PASSWORD else {
        http::challenge(out, "Basic realm=\"notes\"");
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
    http::exit_on_error(http::stop_on_signals());
    let cfg = http::Config { port: 8080, .. };
    print("listening on port ", cfg.port);
    var ids: i64[>..] = [];
    for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
    for id in ids { thread_wait(id); }
}
