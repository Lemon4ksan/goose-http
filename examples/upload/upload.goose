// Uploads of any size, read as they arrive: a raw body, counted, and a
// multipart form, each part's name, filename, and size. And a body of up to
// a megabyte read whole, its words counted.
//
//   curl --data-binary @big.iso localhost:8080/upload
//   curl -F note=hi -F file=@photo.jpg localhost:8080/form
//   curl --data-binary @notes.txt localhost:8080/words
import std;
import dictionary;
import http from "../../";

// The most bytes a body may have on these routes, and on /words, which
// holds it whole.
let LIMIT = 1 << 30;
let WORDS_LIMIT = 1 << 20;

// A request's state, between the handler's calls for it.
struct Upload {
    route: u8 = NONE,
    taken: i64 = 0,     // for body_within
    bytes: i64 = 0,     // /upload: the body's bytes so far
    parts: http::Multipart = http::Multipart { .. },
    failed: bool = false,
    size: i64 = 0,      // /form: the part's bytes so far
    report: u8[..1024] = [],
    body: http::Gather = http::Gather { .. },   // /words
}

let NONE: u8 = 0;
let RAW: u8 = 1;
let FORM: u8 = 2;
let WORDS: u8 = 3;

thread_fn worker(cfg: http::Config) {
    // A function by name, not a block: a block's return would return from
    // worker, ending its loop with the request unanswered.
    let e = http::serve(cfg, Upload { .. }, handle);
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

inline fn handle(ev: http::Event, st: Upload&, out: http::Reply) {
    if ev.kind == http::REQUEST {
        var r = http::router(ev.req);
        var route = NONE;
        if http::on(r, "POST", "/upload") { route = RAW; }
        else if http::on(r, "POST", "/form") { route = FORM; }
        else if http::on(r, "POST", "/words") { st.route = WORDS; }
        else { http::otherwise(r, out); return; }
        if st.route == WORDS {
            http::gather(ev, st.body, out, WORDS_LIMIT, count_words);
            return;
        }
        guard http::body_within(st.taken, ev, out, LIMIT) else { return; }
        if route == FORM && !http::start_multipart(ev.req, st.parts) {
            http::respond(out, 415, "text/plain", "want multipart/form-data\n");
            return;
        }
        st.route = route;
        // A body that fits in the read buffer with its head comes whole
        // here, and no BODY or END follows.
        piece(st, ev.data);
        if ev.whole { answer(st, out); }
    } else if st.route == NONE {
        // Answered at REQUEST: the rest of the body is dropped.
    } else if st.route == WORDS {
        http::gather(ev, st.body, out, WORDS_LIMIT, count_words);
    } else if ev.kind == http::BODY {
        if http::body_within(st.taken, ev, out, LIMIT) { piece(st, ev.data); }
        else { st.route = NONE; }
    } else if ev.kind == http::END {
        answer(st, out);
    }
}

fn piece(st: Upload&, data: const u8[:]) {
    if st.route == RAW {
        st.bytes += data.len;
        return;
    }
    guard !st.failed else { return; }
    let ok = http::each_part(st.parts, data) { part =>
        match part {
            Head h => part_head(st, h.fields),
            Data d => { st.size += d.bytes.len; },
            End => part_end(st),
        }
    };
    if !ok { st.failed = true; }
}

// A part's line of the report starts with its name and filename, which last
// only until each_part's block returns.
fn part_head(st: Upload&, fields: const u8[:]) {
    let name, filename, ok = http::disposition(fields);
    guard ok && st.report.len + name.len + filename.len + 32 <= 1024 else {
        st.failed = true;
        return;
    }
    st.report.append(name);
    if filename.len > 0 { format(st.report, " (", filename, ")"); }
    st.size = 0;
}

fn part_end(st: Upload&) { format(st.report, ": ", st.size, " bytes\n"); }

fn answer(st: Upload&, out: http::Reply) {
    if st.route == RAW {
        var text: u8[..32] = [];
        format(text, st.bytes, " bytes\n");
        http::respond(out, 200, "text/plain", text);
    } else if st.failed || !http::multipart_done(st.parts) {
        http::respond(out, 400, "text/plain", "not a multipart form\n");
    } else {
        http::respond(out, 200, "text/plain", st.report);
    }
}

// /words, once the body is whole, however it came: words split across the
// pieces it arrived in count once.
fn count_words(req: const http::Request&, body: const u8[:], out: http::Reply) {
    var seen = dictionary<const u8[:], bool> {};
    var n = 0;
    each_word(body) { w =>
        seen.insert(w, true);
        n++;
    };
    var text: u8[..64] = [];
    format(text, n, " words, ", seen.count, " different\n");
    http::respond(out, 200, "text/plain", text);
}

fn main() {
    http::exit_on_error(http::stop_on_signals());
    let cfg = http::Config { port: 8080, max_body: LIMIT, .. };
    print("listening on port ", cfg.port);
    var ids: i64[>..] = [];
    for i in http::worker_count(cfg) { ids.push(thread_spawn(worker, cfg)); }
    for id in ids { thread_wait(id); }
}
