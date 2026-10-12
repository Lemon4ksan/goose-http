// The REST benchmark's Goose server (task 021): each tier's routes, answered
// from the generator's dataset files (bench/rest/gen.goose), which it loads at
// startup. Tier A is HttpArena's production-stack application layer:
//
//   GET  /api/items/:id    the item, and servedAt, the time in seconds
//   GET  /api/me           the user X-User-Id names, and servedAt
//   POST /api/items/:id    a body of name, price, and quantity, each optional:
//                          204, or 422 for a body that isn't one; the data
//                          doesn't change, so every server serves the same
//
//   REST_DATA=DIR WORKERS=n [LOOP=epoll] [JSON=template] rest [port]
//
// JSON=template answers from each record's JSON, written once at startup,
// with servedAt added per request, where the default writes each response's
// JSON from the records.
import std;
import os;
import json;
import http from "../../../";

struct Item {
    id: i64,
    name: u8[..48],
    category: u8[..24],
    price: i64,
    quantity: i64,
    active: bool,
    tags: u8[..24][..4],
    score: i64,
    count: i64,
}

struct User { id: i64, name: u8[..48], email: u8[..48], plan: u8[..16] }

// Loaded by main before the workers start, each of which copies them.
var items: Item[>..];
var users: User[>..];
var template: bool;
// JSON=template's prebuilt records, without their closing brace: item i's
// is item_json[item_at[i]..item_at[i + 1]].
var item_json: u8[>..];
var item_at: i64[>..];
var user_json: u8[>..];
var user_at: i64[>..];

fn load(dir: const u8[:], name: const u8[:], text: u8[>..]&) {
    let path = str(dir, "/", name);
    guard read_file(path, text) else { abort(str("can't read ", path, "; run bench/rest/gen.goose")); }
}

// The string at r's cursor, at most cap bytes, which a field of that capacity
// appends: a field given here as an untyped parameter would be a copy.
fn string_of(r: json::Reader&, scratch: u8[>..]&, cap: i64) -> const u8[:] {
    scratch.clear();
    let s = json::read_string(r, scratch);
    guard s.len <= cap else { abort(str("a string longer than ", cap, ": ", s)); }
    return s;
}

fn load_items(dir: const u8[:]) {
    var text: u8[>..] = [];
    load(dir, "arena-items.json", text);
    var scratch: u8[>..] = [];
    var r = json::reader(text);
    json::each_element(r) {
        var it = Item { .. };
        json::each_member(r) { key =>
            if key == "id" { it.id = json::read_int(r); }
            else if key == "name" { it.name.append(string_of(r, scratch, it.name.cap)); }
            else if key == "category" { it.category.append(string_of(r, scratch, it.category.cap)); }
            else if key == "price" { it.price = json::read_int(r); }
            else if key == "quantity" { it.quantity = json::read_int(r); }
            else if key == "active" { it.active = json::read_bool(r); }
            else if key == "tags" {
                json::each_element(r) {
                    guard it.tags.len < it.tags.cap else { abort("more than 4 tags"); }
                    let t .= it.tags.push("");
                    t.append(string_of(r, scratch, t.cap));
                };
            } else if key == "rating" {
                json::each_member(r) { k =>
                    if k == "score" { it.score = json::read_int(r); }
                    else if k == "count" { it.count = json::read_int(r); }
                    else { json::skip(r); }
                };
            } else { json::skip(r); }
        };
        guard it.id == items.len + 1 else { abort("arena-items.json's ids aren't 1, 2, ..."); }
        items.push(it);
    };
    guard json::finish(r) else { abort(json::message(r)); }
}

fn load_users(dir: const u8[:]) {
    var text: u8[>..] = [];
    load(dir, "arena-users.json", text);
    var scratch: u8[>..] = [];
    var r = json::reader(text);
    json::each_element(r) {
        var u = User { .. };
        json::each_member(r) { key =>
            if key == "id" { u.id = json::read_int(r); }
            else if key == "name" { u.name.append(string_of(r, scratch, u.name.cap)); }
            else if key == "email" { u.email.append(string_of(r, scratch, u.email.cap)); }
            else if key == "plan" { u.plan.append(string_of(r, scratch, u.plan.cap)); }
            else { json::skip(r); }
        };
        guard u.id == users.len + 1 else { abort("arena-users.json's ids aren't 1, 2, ..."); }
        users.push(u);
    };
    guard json::finish(r) else { abort(json::message(r)); }
}

// An item's JSON without its closing brace.
fn item_open(out: u8[>..]&, it: Item) {
    out.append("{\"id\":");
    format(out, it.id);
    out.append(",\"name\":");
    json::format_string(out, it.name);
    out.append(",\"category\":");
    json::format_string(out, it.category);
    out.append(",\"price\":");
    format(out, it.price);
    out.append(",\"quantity\":");
    format(out, it.quantity);
    out.append(if it.active { ",\"active\":true,\"tags\":[" } else { ",\"active\":false,\"tags\":[" });
    for t, i in it.tags {
        if i > 0 { out.push(','); }
        json::format_string(out, t);
    }
    out.append("],\"rating\":{\"score\":");
    format(out, it.score);
    out.append(",\"count\":");
    format(out, it.count);
    out.push('}');
}

fn user_open(out: u8[>..]&, u: User) {
    out.append("{\"id\":");
    format(out, u.id);
    out.append(",\"name\":");
    json::format_string(out, u.name);
    out.append(",\"email\":");
    json::format_string(out, u.email);
    out.append(",\"plan\":");
    json::format_string(out, u.plan);
}

fn prebuild() {
    for it in items {
        item_at.push(item_json.len);
        item_open(item_json, it);
    }
    item_at.push(item_json.len);
    for u in users {
        user_at.push(user_json.len);
        user_open(user_json, u);
    }
    user_at.push(user_json.len);
}

// The record's JSON, and servedAt, the time in seconds, into body.
fn served(body: u8[>..]&) {
    body.append(",\"servedAt\":");
    format(body, http::net_time_s());
    body.push('}');
}

// id as a record's index, or -1 when it isn't one of n.
fn index_of(id: const u8[:], n: i64) -> i64 {
    let v, ok = parse_int(id);
    return if ok && v >= 1 && v <= n { v - 1 } else { -1 };
}

// A write's body: an object of name (a string), price, and quantity
// (integers), each optional. Whether it's one.
fn valid_write(body: const u8[:]) -> bool {
    var scratch: u8[>..] = [];
    var r = json::reader(body);
    guard json::peek(r) == '{' else { return false; }
    json::each_member(r) { key =>
        if key == "name" { json::read_string(r, scratch); }
        else if key == "price" || key == "quantity" { json::read_int(r); }
        else { json::skip(r); }
    };
    return json::finish(r);
}

// Each response's JSON is built in a buffer of the request's own, which the
// data stack frees at the end of the request with one store: one kept in the
// worker and cleared per request is refused, the checker taking the loop's
// events for slices that may point into it.
inline fn handle(req: http::Request, body: const u8[:], out: http::Reply) {
    var r = http::router(req);
    var buf: u8[>..] = [];
    if http::on(r, "GET", "/api/items/:id") {
        let i = index_of(http::param(r, "id"), items.len);
        guard i >= 0 else { http::respond(out, 404, "text/plain", ""); return; }
        if template { buf.append(item_json[item_at[i]..item_at[i + 1]]); } else { item_open(buf, items[i]); }
        served(buf);
        http::respond(out, 200, "application/json", buf);
    } else if http::on(r, "GET", "/api/me") {
        let id, has = http::field_of(req, "x-user-id");
        let i = if has { index_of(id, users.len) } else { -1 };
        guard i >= 0 else { http::respond(out, 401, "text/plain", ""); return; }
        if template { buf.append(user_json[user_at[i]..user_at[i + 1]]); } else { user_open(buf, users[i]); }
        served(buf);
        http::respond(out, 200, "application/json", buf);
    } else if http::on(r, "POST", "/api/items/:id") {
        let i = index_of(http::param(r, "id"), items.len);
        guard i >= 0 else { http::respond(out, 404, "text/plain", ""); return; }
        guard valid_write(body) else { http::respond(out, 422, "text/plain", ""); return; }
        http::start(out, 204);
        http::finish(out, "", "");
    } else {
        http::otherwise(r, out);
    }
}

thread_fn worker(cfg: http::Config) { stopped(http::serve(cfg, handle)); }

thread_fn worker_epoll(cfg: http::Config) { stopped(http::serve_epoll(cfg, handle)); }

fn stopped(e: http::Error) {
    guard e.code != 0 else { return; }
    http::report(e);
    exit(1);
}

fn main() {
    let argv = args();
    var port: i32 = 8080;
    if argv.len > 1 {
        let p, ok = parse_int(argv[1]);
        guard ok && p > 0 && p < 65536 else { abort("usage: rest [port]"); }
        port = p as i32;
    }
    var dir: u8[>..] = [];
    if !env("REST_DATA", dir) { dir.append("build/rest"); }
    load_items(dir);
    load_users(dir);
    var mode: u8[>..] = [];
    template = env("JSON", mode) && mode == "template";
    if template { prebuild(); }
    var workers: u8[>..] = [];
    var n: i64 = 0;
    if env("WORKERS", workers) {
        let w, ok = parse_int(workers);
        if ok && w > 0 { n = w; }
    }
    var loop_name: u8[>..] = [];
    let epoll = env("LOOP", loop_name) && loop_name == "epoll";
    let cfg = http::Config { port: port, workers: n, .. };
    let s = http::stop_on_signals();
    guard s == 0 else { stopped(http::Error { call: "sigaction", code: -s }); }
    let count = http::worker_count(cfg);
    print("rest: ", items.len, " items, ", users.len, " users, ", count, " workers on port ", port,
          if epoll { ", epoll" } else { ", uring" }, if template { ", template" } else { ", serialize" });
    var ids: i64[>..] = [];
    for i in count { ids.push(if epoll { thread_spawn(worker_epoll, cfg) } else { thread_spawn(worker, cfg) }); }
    for id in ids { thread_wait(id); }
}
