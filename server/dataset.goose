// HttpArena's json and json-comp endpoint, GET /json/{count}?m={m}: the
// first count items of its data/dataset.json, each with total, its price
// times its quantity times m, and the count, serialized for each request.
// The server loads the file DATASET names, /data/dataset.json by default,
// where the HttpArena entry mounts it, before the workers start; each
// copies the items.
import std;
import os;
import json;
import http;

struct Item {
    id: i64,
    name: u8[..48],
    category: u8[..24],
    price: i64,
    quantity: i64,
    active: bool,
    tags: u8[..24][..6],
    score: i64,
    count: i64,
}

var items: Item[>..];

// The string at r's cursor, which a field of capacity cap takes, or "" with
// ok cleared for a longer one.
fn string_of(r: json::Reader&, scratch: u8[>..]&, cap: i64) -> const u8[:], bool {
    scratch.clear();
    let s = json::read_string(r, scratch);
    return if s.len <= cap { s } else { "" }, s.len <= cap;
}

// Loads the dataset, if DATASET's file, or the default, can be read; an
// unreadable one leaves /json/{count} answering 404, and one that doesn't
// parse ends the process.
fn load_dataset() {
    var path: u8[>..] = [];
    if !env("DATASET", path) { path.append("/data/dataset.json"); }
    var text: u8[>..] = [];
    guard read_file(path, text) else { return; }
    var scratch: u8[>..] = [];
    var fits = true;
    var r = json::reader(text);
    json::each_element(r) {
        var it = Item { .. };
        json::each_member(r) { key =>
            if key == "id" { it.id = json::read_int(r); }
            else if key == "name" {
                let s, ok = string_of(r, scratch, it.name.cap);
                it.name.append(s);
                fits = fits && ok;
            } else if key == "category" {
                let s, ok = string_of(r, scratch, it.category.cap);
                it.category.append(s);
                fits = fits && ok;
            } else if key == "price" { it.price = json::read_int(r); }
            else if key == "quantity" { it.quantity = json::read_int(r); }
            else if key == "active" { it.active = json::read_bool(r); }
            else if key == "tags" {
                json::each_element(r) {
                    if it.tags.len < it.tags.cap {
                        let t .= it.tags.push("");
                        let s, ok = string_of(r, scratch, t.cap);
                        t.append(s);
                        fits = fits && ok;
                    } else {
                        json::skip(r);
                        fits = false;
                    }
                };
            } else if key == "rating" {
                json::each_member(r) { k =>
                    if k == "score" { it.score = json::read_int(r); }
                    else if k == "count" { it.count = json::read_int(r); }
                    else { json::skip(r); }
                };
            } else { json::skip(r); }
        };
        items.push(it);
    };
    guard json::finish(r) else { abort(str(path, ": ", json::message(r))); }
    guard fits else { abort(str(path, ": a name, category, or tag too long, or more than 6 tags")); }
}

// The response's JSON: {"items":[...],"count":n}.
fn write_items(out: u8[>..]&, n: i64, m: i64) {
    out.append("{\"items\":[");
    for i in n {
        let it = items[i];
        if i > 0 { out.push(','); }
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
        for t, k in it.tags {
            if k > 0 { out.push(','); }
            json::format_string(out, t);
        }
        out.append("],\"rating\":{\"score\":");
        format(out, it.score);
        out.append(",\"count\":");
        format(out, it.count);
        out.append("},\"total\":");
        format(out, it.price * it.quantity * m);
        out.push('}');
    }
    out.append("],\"count\":");
    format(out, n);
    out.push('}');
}

// Answers /json/{count}, whose count is given, compressed as the request
// takes: 404 without a dataset, 400 for a count that isn't 1 to the
// dataset's size. m is 1 when the query has none.
fn json_items(req: http::Request, count: const u8[:], out: http::Reply) {
    guard items.len > 0 else {
        http::respond(out, 404, "text/plain", "no dataset");
        return;
    }
    let n, ok = parse_int(count);
    guard ok && n >= 1 && n <= items.len else {
        http::respond(out, 400, "text/plain", "count must be 1 to the dataset's size");
        return;
    }
    let mv, has_m = http::query_of(req.target, "m");
    let m, m_ok = parse_int(mv);
    var body: u8[>..] = [];
    write_items(body, n, if has_m && m_ok { m } else { 1 });
    http::respond_compressed(out, req, 200, "application/json", body);
}
