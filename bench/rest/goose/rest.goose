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
// Tier B is snowtime's k6 hot path, answered as snowtime's Hono routes answer:
//
//   GET   /api/v1/session                        the session, or null
//   GET   /api/v1/timer                          the running timer, or null
//   GET   /api/v1/organizations/:org/entries     ?from=&to=&userId=
//   GET   /api/v1/organizations/:org/projects    ?includeArchived=
//   PATCH /api/v1/organizations/:org/entries/:id {"description"}
//   POST  /api/v1/organizations/:org/timer/start {"id","description",...}
//   POST  /api/v1/timer/stop                     {"id"}
//
//   REST_DATA=DIR TIER=a|b WORKERS=n [LOOP=epoll] [JSON=template] rest [port]
//
// TIER picks the dataset to load, tier A's by default. JSON=template answers
// from each record's JSON, written once at startup, with the per-request
// values added, where the default writes each response's JSON from the
// records.
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

// Tier B, snowtime's k6 hot path, under /api/v1. A session cookie names the
// user, by its token; a write needs Origin to be the app's. The data doesn't
// change: a PATCH answers the entry with the description it was sent, and
// timer start and stop answer as of now, as if the timer had started.

// Functions, as a worker's globals must be flat and a literal is a slice.
fn app_url() -> const u8[:] { "https://time.bench.example.com" }
fn session_cookie() -> const u8[:] { "__Secure-better-auth.session_token" }

let DAY: i64 = 86400000;
let MINUTE: i64 = 60000;

struct Org { id: u8[..36], name: u8[..16], slug: u8[..16], links: u8[..64], first: i64, count: i64 }

struct Project {
    id: u8[..36],
    name: u8[..48],
    color: u8[..7],         // empty for null
    archived: i64,          // ms, -1 for null
    has_entries: bool,
    teams: u8[..36][..2],
}

struct Member { org: i64, role: u8[..6] }

struct Settings {
    time_zone: u8[..32],
    week_start: u8[..3],
    locale: u8[..2],
    theme: u8[..6],
    timer_layout: u8[..5],
    show_summary: bool,
    compact_rows: bool,
    wide_timer: bool,
    timer_view: u8[..8],
    calendar_weekend: bool,
    app_icon: u8[..8],
    scene_collection: u8[..16],
    scene_pin: u8[..16],    // empty for null
    scene_background: bool,
    scene_strength: u8[..6],
    surfaces: u8[..5],
    scene_weather: bool,
    scene_intro: bool,
    scene_tagline: bool,
    duration_format: u8[..5],
    date_format: u8[..3],
    time_format: u8[..3],
    copy_pattern: u8[..16],
    copy_control: u8[..6],
    country: u8[..2],       // empty for null
}

struct Fill {
    date: u8[..10],
    timer_started: i64,     // -1 for null
    today: u8[..6],
    last_day: u8[..10],     // empty for null
    last_day_filled: bool,
    last_week: i64,         // 0, 1, or -1 for null
    last_month: i64,
    caught_up: bool,
    empty_days: i64,
    streak: i64,
}

struct Person {
    id: u8[..36],
    name: u8[..48],
    email: u8[..48],
    image: u8[..96],        // empty for null
    token: u8[..64],
    signed_in: i64,
    orgs: Member[..6],      // as the session lists them
    active: i64,
    teams: u8[..36][..2],   // in the active organization
    settings: Settings,
    fill: Fill,
    first: i64,             // the person's entries, entries[first..first + count]
    count: i64,
    running: i64,           // an entry, or -1
}

struct Entry {
    id: u8[..36],
    user: i64,
    org: i64,
    project: i64,           // -1 for null
    description: u8[..96],
    ticket: u8[..16],       // empty for null
    started: i64,
    stopped: i64,           // -1 for null
}

var orgs: Org[>..];
var projects: Project[>..];
var people: Person[>..];
var entries: Entry[>..];        // by person, then by start
var by_token: i64[>..];         // people, by token
var by_person_id: i64[>..];     // people, by id
var by_entry_id: i64[>..];      // entries, by id
// JSON=template's: each session, each project, and each entry whole; each
// running timer as GET /timer answers it; and where in each entry the
// description's value starts and ends, for a PATCH to put another there.
var session_json: u8[>..];
var session_at: i64[>..];
var project_json: u8[>..];
var project_at: i64[>..];
var entry_json: u8[>..];
var entry_at: i64[>..];
var entry_desc: i64[>..];
var entry_tail: i64[>..];
var timer_json: u8[>..];
var timer_at: i64[>..];

fn digits(out: u8[>..]&, v: i64, n: i64) {
    var div = 1;
    for i in n - 1 { div *= 10; }
    while div > 0 {
        out.push(('0' + v / div % 10) as u8);
        div /= 10;
    }
}

// ms since the epoch as JavaScript's toISOString writes it, from Howard
// Hinnant's civil_from_days.
fn format_iso(out: u8[>..]&, ms: i64) {
    let day = ms / DAY;
    let t = ms - day * DAY;
    let z = day + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    digits(out, yoe + era * 400 + (if m <= 2 { 1 } else { 0 }), 4);
    out.push('-');
    digits(out, m, 2);
    out.push('-');
    digits(out, doy - (153 * mp + 2) / 5 + 1, 2);
    out.push('T');
    digits(out, t / 3600000, 2);
    out.push(':');
    digits(out, t / MINUTE % 60, 2);
    out.push(':');
    digits(out, t / 1000 % 60, 2);
    out.push('.');
    digits(out, t % 1000, 3);
    out.push('Z');
}

fn number_at(s: const u8[:], at: i64, n: i64) -> i64 {
    var v = 0;
    for i in at..at + n {
        guard s[i] >= '0' && s[i] <= '9' else { return -1; }
        v = v * 10 + (s[i] - '0');
    }
    return v;
}

// "YYYY-MM-DDTHH:MM:SS.sssZ", or without the milliseconds, as ms since the
// epoch (days_from_civil); false for anything else.
fn parse_iso(s: const u8[:]) -> i64, bool {
    guard (s.len == 24 || s.len == 20) && s[4] == '-' && s[7] == '-' && s[10] == 'T' && s[13] == ':' &&
          s[16] == ':' && s[s.len - 1] == 'Z' else { return 0, false; }
    let y = number_at(s, 0, 4);
    let m = number_at(s, 5, 2);
    let d = number_at(s, 8, 2);
    let h = number_at(s, 11, 2);
    let mi = number_at(s, 14, 2);
    let sec = number_at(s, 17, 2);
    let ms = if s.len == 24 && s[19] == '.' { number_at(s, 20, 3) } else if s.len == 20 { 0 } else { -1 };
    guard y >= 0 && m >= 1 && m <= 12 && d >= 1 && d <= 31 && h >= 0 && h < 24 && mi >= 0 && mi < 60 &&
          sec >= 0 && sec < 60 && ms >= 0 else { return 0, false; }
    let yy = if m <= 2 { y - 1 } else { y };
    let era = (if yy >= 0 { yy } else { yy - 399 }) / 400;
    let yoe = yy - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    return days * DAY + ((h * 60 + mi) * 60 + sec) * 1000 + ms, true;
}

fn is_lower_hex(c: u8) -> bool { c >= '0' && c <= '9' || c >= 'a' && c <= 'f' }

// snowtime's Uuidv7: 8-4-4-4-12 lower-case hex digits, version 7, variant 8
// to b.
fn is_uuid7(s: const u8[:]) -> bool {
    guard s.len == 36 && s[14] == '7' && (s[19] == '8' || s[19] == '9' || s[19] == 'a' || s[19] == 'b')
        else { return false; }
    for c, i in s {
        if i == 8 || i == 13 || i == 18 || i == 23 { if c != '-' { return false; } }
        else if !is_lower_hex(c) { return false; }
    }
    return true;
}

// The time a uuidv7 was made, from its first 48 bits.
fn uuid_ms(s: const u8[:]) -> i64 {
    var v = 0;
    for c, i in s[..13] {
        if i == 8 { continue; }
        v = v * 16 + (if c <= '9' { c - '0' } else { c - 'a' + 10 });
    }
    return v;
}

// snowtime's ticket key: [A-Z][A-Z0-9]{1,9}-[1-9][0-9]{0,6}.
fn is_ticket(s: const u8[:]) -> bool {
    let dash = position(s, '-');
    guard dash >= 2 && dash <= 10 && s[0] >= 'A' && s[0] <= 'Z' else { return false; }
    for c in s[1..dash] { if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9') { return false; } }
    let n = s[dash + 1..];
    guard n.len >= 1 && n.len <= 7 && n[0] >= '1' && n[0] <= '9' else { return false; }
    for c in n { if c < '0' || c > '9' { return false; } }
    return true;
}

fn now_ms() -> i64 { time_ns() / 1000000 }

fn iso_or_null(out: u8[>..]&, ms: i64) {
    if ms < 0 { out.append("null"); return; }
    out.push('"');
    format_iso(out, ms);
    out.push('"');
}

fn string_or_null(out: u8[>..]&, s: const u8[:]) {
    if s.len == 0 { out.append("null"); } else { json::format_string(out, s); }
}

// A string member, or null as empty.
fn read_nullable(r: json::Reader&, scratch: u8[>..]&, cap: i64) -> const u8[:] {
    if json::peek(r) == 'n' { json::skip(r); return ""; }
    return string_of(r, scratch, cap);
}

fn read_time(r: json::Reader&, scratch: u8[>..]&) -> i64 {
    if json::peek(r) == 'n' { json::skip(r); return -1; }
    let v, ok = parse_iso(string_of(r, scratch, 24));
    guard ok else { abort("a time that isn't toISOString's"); }
    return v;
}

fn read_flag(r: json::Reader&) -> i64 {
    if json::peek(r) == 'n' { json::skip(r); return -1; }
    return if json::read_bool(r) { 1 } else { 0 };
}

fn org_index(id: const u8[:]) -> i64 {
    for o, i in orgs { if o.id == id { return i; } }
    return -1;
}

fn project_index(id: const u8[:], org: i64) -> i64 {
    let o = orgs[org];
    for i in o.first..o.first + o.count { if projects[i].id == id { return i; } }
    return -1;
}

fn person_index(id: const u8[:]) -> i64 {
    let k = lower_bound(by_person_id) { compare(people[it].id, id) < 0 };
    return if k < by_person_id.len && people[by_person_id[k]].id == id { by_person_id[k] } else { -1 };
}

fn entry_index(id: const u8[:]) -> i64 {
    let k = lower_bound(by_entry_id) { compare(entries[it].id, id) < 0 };
    return if k < by_entry_id.len && entries[by_entry_id[k]].id == id { by_entry_id[k] } else { -1 };
}

fn load_orgs(dir: const u8[:]) {
    var text: u8[>..] = [];
    load(dir, "snow-orgs.json", text);
    var scratch: u8[>..] = [];
    var r = json::reader(text);
    json::each_element(r) {
        var o = Org { .. };
        json::each_member(r) { key =>
            if key == "id" { o.id.append(string_of(r, scratch, o.id.cap)); }
            else if key == "name" { o.name.append(string_of(r, scratch, o.name.cap)); }
            else if key == "slug" { o.slug.append(string_of(r, scratch, o.slug.cap)); }
            else if key == "issueLinks" { o.links.append(read_nullable(r, scratch, o.links.cap)); }
            else if key == "projects" {
                o.first = projects.len;
                json::each_element(r) {
                    var p = Project { archived: -1, .. };
                    json::each_member(r) { k =>
                        if k == "id" { p.id.append(string_of(r, scratch, p.id.cap)); }
                        else if k == "name" { p.name.append(string_of(r, scratch, p.name.cap)); }
                        else if k == "color" { p.color.append(read_nullable(r, scratch, p.color.cap)); }
                        else if k == "archivedAt" { p.archived = read_time(r, scratch); }
                        else if k == "hasEntries" { p.has_entries = json::read_bool(r); }
                        else if k == "teamIds" {
                            json::each_element(r) {
                                guard p.teams.len < p.teams.cap else { abort("more than 2 teams"); }
                                let t .= p.teams.push("");
                                t.append(string_of(r, scratch, t.cap));
                            };
                        } else { json::skip(r); }
                    };
                    projects.push(p);
                };
                o.count = projects.len - o.first;
            } else { json::skip(r); }
        };
        orgs.push(o);
    };
    guard json::finish(r) else { abort(json::message(r)); }
}

fn load_settings(r: json::Reader&, scratch: u8[>..]&, s: Settings&) {
    json::each_member(r) { k =>
        if k == "timeZone" { s.time_zone.append(string_of(r, scratch, s.time_zone.cap)); }
        else if k == "weekStart" { s.week_start.append(string_of(r, scratch, s.week_start.cap)); }
        else if k == "locale" { s.locale.append(string_of(r, scratch, s.locale.cap)); }
        else if k == "theme" { s.theme.append(string_of(r, scratch, s.theme.cap)); }
        else if k == "timerLayout" { s.timer_layout.append(string_of(r, scratch, s.timer_layout.cap)); }
        else if k == "showSummary" { s.show_summary = json::read_bool(r); }
        else if k == "compactRows" { s.compact_rows = json::read_bool(r); }
        else if k == "wideTimer" { s.wide_timer = json::read_bool(r); }
        else if k == "timerView" { s.timer_view.append(string_of(r, scratch, s.timer_view.cap)); }
        else if k == "calendarWeekend" { s.calendar_weekend = json::read_bool(r); }
        else if k == "appIcon" { s.app_icon.append(string_of(r, scratch, s.app_icon.cap)); }
        else if k == "sceneCollection" { s.scene_collection.append(string_of(r, scratch, s.scene_collection.cap)); }
        else if k == "scenePin" { s.scene_pin.append(read_nullable(r, scratch, s.scene_pin.cap)); }
        else if k == "sceneBackground" { s.scene_background = json::read_bool(r); }
        else if k == "sceneStrength" { s.scene_strength.append(string_of(r, scratch, s.scene_strength.cap)); }
        else if k == "surfaces" { s.surfaces.append(string_of(r, scratch, s.surfaces.cap)); }
        else if k == "sceneWeather" { s.scene_weather = json::read_bool(r); }
        else if k == "sceneIntro" { s.scene_intro = json::read_bool(r); }
        else if k == "sceneTagline" { s.scene_tagline = json::read_bool(r); }
        else if k == "durationFormat" { s.duration_format.append(string_of(r, scratch, s.duration_format.cap)); }
        else if k == "dateFormat" { s.date_format.append(string_of(r, scratch, s.date_format.cap)); }
        else if k == "timeFormat" { s.time_format.append(string_of(r, scratch, s.time_format.cap)); }
        else if k == "copyDurationPattern" { s.copy_pattern.append(string_of(r, scratch, s.copy_pattern.cap)); }
        else if k == "copyDurationControl" { s.copy_control.append(string_of(r, scratch, s.copy_control.cap)); }
        else if k == "country" { s.country.append(read_nullable(r, scratch, s.country.cap)); }
        else { json::skip(r); }
    };
}

fn load_fill(r: json::Reader&, scratch: u8[>..]&, f: Fill&) {
    json::each_member(r) { k =>
        if k == "date" { f.date.append(string_of(r, scratch, f.date.cap)); }
        else if k == "timerStartedAt" {
            f.timer_started = if json::peek(r) == 'n' { json::skip(r); -1 } else { json::read_int(r) };
        } else if k == "today" { f.today.append(string_of(r, scratch, f.today.cap)); }
        else if k == "lastWorkingDay" {
            if json::peek(r) == 'n' { json::skip(r); }
            else {
                json::each_member(r) { kk =>
                    if kk == "date" { f.last_day.append(string_of(r, scratch, f.last_day.cap)); }
                    else if kk == "filled" { f.last_day_filled = json::read_bool(r); }
                    else { json::skip(r); }
                };
            }
        } else if k == "lastWeek" { f.last_week = read_flag(r); }
        else if k == "lastMonth" { f.last_month = read_flag(r); }
        else if k == "caughtUp" { f.caught_up = json::read_bool(r); }
        else if k == "emptyDays" { f.empty_days = json::read_int(r); }
        else if k == "streak" { f.streak = json::read_int(r); }
        else { json::skip(r); }
    };
}

fn load_people(dir: const u8[:]) {
    var text: u8[>..] = [];
    load(dir, "snow-users.json", text);
    var scratch: u8[>..] = [];
    var r = json::reader(text);
    json::each_element(r) {
        var p = Person { active: -1, running: -1, .. };
        json::each_member(r) { key =>
            if key == "id" { p.id.append(string_of(r, scratch, p.id.cap)); }
            else if key == "name" { p.name.append(string_of(r, scratch, p.name.cap)); }
            else if key == "email" { p.email.append(string_of(r, scratch, p.email.cap)); }
            else if key == "image" { p.image.append(read_nullable(r, scratch, p.image.cap)); }
            else if key == "token" { p.token.append(string_of(r, scratch, p.token.cap)); }
            else if key == "signedInAt" { p.signed_in = read_time(r, scratch); }
            else if key == "organizations" {
                json::each_element(r) {
                    guard p.orgs.len < p.orgs.cap else { abort("more than 6 organizations"); }
                    let m .= p.orgs.push(Member { org: -1, .. });
                    json::each_member(r) { k =>
                        if k == "id" { m.org = org_index(string_of(r, scratch, 36)); }
                        else if k == "role" { m.role.append(string_of(r, scratch, m.role.cap)); }
                        else { json::skip(r); }
                    };
                    guard m.org >= 0 else { abort("a member of an organization snow-orgs.json lacks"); }
                };
            } else if key == "activeOrganizationId" { p.active = org_index(string_of(r, scratch, 36)); }
            else if key == "teamIds" {
                json::each_element(r) {
                    guard p.teams.len < p.teams.cap else { abort("more than 2 teams"); }
                    let t .= p.teams.push("");
                    t.append(string_of(r, scratch, t.cap));
                };
            } else if key == "settings" { load_settings(r, scratch, p.settings); }
            else if key == "fill" { load_fill(r, scratch, p.fill); }
            else { json::skip(r); }
        };
        guard p.active >= 0 && p.token.len == 64 else { abort("a user without an organization or a token"); }
        people.push(p);
    };
    guard json::finish(r) else { abort(json::message(r)); }
    for i in people.len { by_token.push(i); by_person_id.push(i); }
    sort(by_token) { a, b => compare(people[a].token, people[b].token) < 0 };
    sort(by_person_id) { a, b => compare(people[a].id, people[b].id) < 0 };
}

fn load_entries(dir: const u8[:]) {
    var text: u8[>..] = [];
    load(dir, "snow-entries.json", text);
    var scratch: u8[>..] = [];
    var r = json::reader(text);
    json::each_element(r) {
        var e = Entry { user: -1, org: -1, project: -1, .. };
        var project: u8[..36] = "";
        json::each_member(r) { key =>
            if key == "id" { e.id.append(string_of(r, scratch, e.id.cap)); }
            else if key == "organizationId" { e.org = org_index(string_of(r, scratch, 36)); }
            else if key == "userId" {
                let id = string_of(r, scratch, 36);
                // The file has each user's entries together.
                e.user = if entries.len > 0 && people[last(entries).user].id == id { last(entries).user }
                         else { person_index(id) };
            } else if key == "projectId" { project.append(read_nullable(r, scratch, project.cap)); }
            else if key == "description" { e.description.append(string_of(r, scratch, e.description.cap)); }
            else if key == "ticket" { e.ticket.append(read_nullable(r, scratch, e.ticket.cap)); }
            else if key == "startedAt" { e.started = read_time(r, scratch); }
            else if key == "stoppedAt" { e.stopped = read_time(r, scratch); }
            else { json::skip(r); }
        };
        guard e.user >= 0 && e.org >= 0 else { abort("an entry of a user or organization the files lack"); }
        if project.len > 0 {
            e.project = project_index(project, e.org);
            guard e.project >= 0 else { abort("an entry of a project snow-orgs.json lacks"); }
        }
        let p .= people[e.user];
        if p.count == 0 { p.first = entries.len; }
        guard p.first + p.count == entries.len else { abort("snow-entries.json doesn't have each user's entries together"); }
        guard p.count == 0 || last(entries).started < e.started else { abort("a user's entries out of order"); }
        p.count++;
        if e.stopped < 0 { p.running = entries.len; }
        entries.push(e);
    };
    guard json::finish(r) else { abort(json::message(r)); }
    for i in entries.len { by_entry_id.push(i); }
    sort(by_entry_id) { a, b => compare(entries[a].id, entries[b].id) < 0 };
}

fn session_open(out: u8[>..]&, p: Person) {
    out.append("{\"user\":{\"id\":");
    json::format_string(out, p.id);
    out.append(",\"name\":");
    json::format_string(out, p.name);
    out.append(",\"email\":");
    json::format_string(out, p.email);
    out.append(",\"image\":");
    string_or_null(out, p.image);
    out.append("},\"signedInAt\":");
    iso_or_null(out, p.signed_in);
    out.append(",\"organizations\":[");
    for m, i in p.orgs {
        let o = orgs[m.org];
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        json::format_string(out, o.id);
        out.append(",\"name\":");
        json::format_string(out, o.name);
        out.append(",\"slug\":");
        json::format_string(out, o.slug);
        out.append(",\"issueLinks\":");
        string_or_null(out, o.links);
        out.append(",\"role\":");
        json::format_string(out, m.role);
        out.push('}');
    }
    out.append("],\"activeOrganizationId\":");
    json::format_string(out, orgs[p.active].id);
    let s = p.settings;
    out.append(",\"settings\":{\"timeZone\":");
    json::format_string(out, s.time_zone);
    out.append(",\"weekStart\":");
    json::format_string(out, s.week_start);
    out.append(",\"locale\":");
    json::format_string(out, s.locale);
    out.append(",\"theme\":");
    json::format_string(out, s.theme);
    out.append(",\"timerLayout\":");
    json::format_string(out, s.timer_layout);
    out.append(",\"showSummary\":");
    json::format_bool(out, s.show_summary);
    out.append(",\"compactRows\":");
    json::format_bool(out, s.compact_rows);
    out.append(",\"wideTimer\":");
    json::format_bool(out, s.wide_timer);
    out.append(",\"timerView\":");
    json::format_string(out, s.timer_view);
    out.append(",\"calendarWeekend\":");
    json::format_bool(out, s.calendar_weekend);
    out.append(",\"appIcon\":");
    json::format_string(out, s.app_icon);
    out.append(",\"sceneCollection\":");
    json::format_string(out, s.scene_collection);
    out.append(",\"scenePin\":");
    string_or_null(out, s.scene_pin);
    out.append(",\"sceneBackground\":");
    json::format_bool(out, s.scene_background);
    out.append(",\"sceneStrength\":");
    json::format_string(out, s.scene_strength);
    out.append(",\"surfaces\":");
    json::format_string(out, s.surfaces);
    out.append(",\"sceneWeather\":");
    json::format_bool(out, s.scene_weather);
    out.append(",\"sceneIntro\":");
    json::format_bool(out, s.scene_intro);
    out.append(",\"sceneTagline\":");
    json::format_bool(out, s.scene_tagline);
    out.append(",\"durationFormat\":");
    json::format_string(out, s.duration_format);
    out.append(",\"dateFormat\":");
    json::format_string(out, s.date_format);
    out.append(",\"timeFormat\":");
    json::format_string(out, s.time_format);
    out.append(",\"copyDurationPattern\":");
    json::format_string(out, s.copy_pattern);
    out.append(",\"copyDurationControl\":");
    json::format_string(out, s.copy_control);
    out.append(",\"country\":");
    string_or_null(out, s.country);
    let f = p.fill;
    out.append("},\"fill\":{\"date\":");
    json::format_string(out, f.date);
    out.append(",\"timerStartedAt\":");
    if f.timer_started >= 0 { format(out, f.timer_started); } else { out.append("null"); }
    out.append(",\"today\":");
    json::format_string(out, f.today);
    out.append(",\"lastWorkingDay\":");
    if f.last_day.len == 0 { out.append("null"); }
    else {
        out.append("{\"date\":");
        json::format_string(out, f.last_day);
        out.append(",\"filled\":");
        json::format_bool(out, f.last_day_filled);
        out.push('}');
    }
    out.append(",\"lastWeek\":");
    out.append(if f.last_week < 0 { "null" } else if f.last_week > 0 { "true" } else { "false" });
    out.append(",\"lastMonth\":");
    out.append(if f.last_month < 0 { "null" } else if f.last_month > 0 { "true" } else { "false" });
    out.append(",\"caughtUp\":");
    json::format_bool(out, f.caught_up);
    out.append(",\"emptyDays\":");
    format(out, f.empty_days);
    out.append(",\"streak\":");
    format(out, f.streak);
    out.append("},\"invitationId\":null,\"appUrl\":\"");
    out.append(app_url());
    out.append("\"}");
}

// An entry up to its description's value, and from the member after it, so
// that a PATCH writes another description between the two.
fn entry_head(out: u8[>..]&, e: Entry) {
    out.append("{\"id\":");
    json::format_string(out, e.id);
    out.append(",\"organizationId\":");
    json::format_string(out, orgs[e.org].id);
    out.append(",\"userId\":");
    json::format_string(out, people[e.user].id);
    out.append(",\"projectId\":");
    string_or_null(out, if e.project >= 0 { projects[e.project].id } else { "" });
    out.append(",\"description\":");
}

// The members after the description, without stoppedAt's value and the
// closing brace.
fn entry_tail_open(out: u8[>..]&, e: Entry) {
    out.append(",\"ticket\":");
    string_or_null(out, e.ticket);
    out.append(",\"startedAt\":");
    iso_or_null(out, e.started);
    out.append(",\"stoppedAt\":");
}

fn entry_full(out: u8[>..]&, e: Entry, description: const u8[:], stopped: i64) {
    entry_head(out, e);
    json::format_string(out, description);
    entry_tail_open(out, e);
    iso_or_null(out, stopped);
    out.push('}');
}

fn project_full(out: u8[>..]&, p: Project) {
    out.append("{\"id\":");
    json::format_string(out, p.id);
    out.append(",\"name\":");
    json::format_string(out, p.name);
    out.append(",\"color\":");
    string_or_null(out, p.color);
    out.append(",\"archivedAt\":");
    iso_or_null(out, p.archived);
    out.append(if p.has_entries { ",\"hasEntries\":true,\"teamIds\":[" } else { ",\"hasEntries\":false,\"teamIds\":[" });
    for t, i in p.teams {
        if i > 0 { out.push(','); }
        json::format_string(out, t);
    }
    out.append("]}");
}

// GET /timer's answer for a running entry: the entry and its project.
fn timer_full(out: u8[>..]&, e: Entry) {
    entry_head(out, e);
    json::format_string(out, e.description);
    entry_tail_open(out, e);
    out.append("null,\"project\":");
    if e.project < 0 { out.append("null}"); return; }
    let p = projects[e.project];
    out.append("{\"id\":");
    json::format_string(out, p.id);
    out.append(",\"name\":");
    json::format_string(out, p.name);
    out.append(",\"color\":");
    string_or_null(out, p.color);
    out.append("}}");
}

fn prebuild_snow() {
    for p in people {
        session_at.push(session_json.len);
        session_open(session_json, p);
        timer_at.push(timer_json.len);
        if p.running >= 0 { timer_full(timer_json, entries[p.running]); } else { timer_json.append("null"); }
    }
    session_at.push(session_json.len);
    timer_at.push(timer_json.len);
    for p in projects {
        project_at.push(project_json.len);
        project_full(project_json, p);
    }
    project_at.push(project_json.len);
    for e in entries {
        entry_at.push(entry_json.len);
        entry_head(entry_json, e);
        entry_desc.push(entry_json.len);
        json::format_string(entry_json, e.description);
        entry_tail.push(entry_json.len);
        entry_tail_open(entry_json, e);
        iso_or_null(entry_json, e.stopped);
        entry_json.push('}');
    }
    entry_at.push(entry_json.len);
}

fn snow_entry(out: u8[>..]&, i: i64) {
    if template { out.append(entry_json[entry_at[i]..entry_at[i + 1]]); }
    else { let e = entries[i]; entry_full(out, e, e.description, e.stopped); }
}

// Entry i with another description.
fn snow_entry_as(out: u8[>..]&, i: i64, description: const u8[:]) {
    if template {
        out.append(entry_json[entry_at[i]..entry_desc[i]]);
        json::format_string(out, description);
        out.append(entry_json[entry_tail[i]..entry_at[i + 1]]);
    } else {
        let e = entries[i];
        entry_full(out, e, description, e.stopped);
    }
}

// Running entry i stopped at ms, as stopRunning stops it: after it started,
// and at most a day after.
fn snow_stopped(out: u8[>..]&, i: i64, now: i64) {
    let e = entries[i];
    let at = min(max(now, e.started + 1), e.started + DAY);
    if template {
        // A running entry's JSON ends in "null}".
        out.append(entry_json[entry_at[i]..entry_at[i + 1] - 5]);
        iso_or_null(out, at);
        out.push('}');
    } else {
        entry_full(out, e, e.description, at);
    }
}

// The person the session cookie names, or -1.
fn person_of(req: http::Request) -> i64 {
    let v, has = http::cookie_of(req, session_cookie());
    guard has && v.len > 65 && v[64] == '.' else { return -1; }
    let token = v[..64];
    let k = lower_bound(by_token) { compare(people[it].token, token) < 0 };
    return if k < by_token.len && people[by_token[k]].token == token { by_token[k] } else { -1 };
}

// The person's membership of the organization the path names, or -1.
fn membership(p: Person, id: const u8[:]) -> i64 {
    for m, i in p.orgs { if orgs[m.org].id == id { return i; } }
    return -1;
}

fn is_admin(m: Member) -> bool { m.role == "owner" || m.role == "admin" }

// listProjects's visibility: an admin sees every project, a member those
// with no team and those of a team of theirs.
fn sees(p: Person, m: Member, j: Project) -> bool {
    if is_admin(m) || j.teams.len == 0 { return true; }
    if m.org != p.active { return false; }
    for t in j.teams { if contains(p.teams, t) { return true; } }
    return false;
}

fn error(out: http::Reply, status: i32, body: const u8[:]) { http::respond(out, status, "application/json", body); }

fn coded(out: http::Reply, status: i32, code: const u8[:], key: const u8[:]) {
    var b: u8[>..] = [];
    format(b, "{\"error\":{\"code\":\"", code, "\",\"key\":\"", key, "\"}}");
    http::respond(out, status, "application/json", b);
}

fn invalid(out: http::Reply) { error(out, 400, "{\"error\":{\"message\":\"Invalid input.\"}}"); }

fn not_json(out: http::Reply) { error(out, 400, "{\"error\":{\"message\":\"The body is not JSON.\"}}"); }

// A query value, percent-decoded into scratch.
fn query(req: http::Request, key: const u8[:], scratch: u8[>..]&) -> const u8[:], bool {
    let v, has = http::query_of(req.target, key);
    guard has else { return "", false; }
    scratch.clear();
    guard http::decode(v, scratch) else { return "", false; }
    return scratch, true;
}

// GET .../entries: the entries of userId, or of the caller, that overlap
// [from, to), newest first, as listEntries selects them.
fn list_entries(req: http::Request, p: Person, m: Member, buf: u8[>..]&, out: http::Reply) {
    var scratch: u8[>..] = [];
    let fs, has_from = query(req, "from", scratch);
    let from, from_ok = parse_iso(fs);
    let ts, has_to = query(req, "to", scratch);
    let to, to_ok = parse_iso(ts);
    guard has_from && from_ok && has_to && to_ok && to > from && to - from <= 93 * DAY else { invalid(out); return; }
    var who = person_index(p.id);
    let uid, has_user = query(req, "userId", scratch);
    if has_user {
        guard is_uuid7(uid) else { invalid(out); return; }
        if uid != p.id {
            guard is_admin(m) else { coded(out, 403, "FORBIDDEN", "entries_forbidden"); return; }
            who = person_index(uid);
        }
    }
    buf.push('[');
    if who >= 0 && people[who].active == m.org {
        let u = people[who];
        let mine = entries[u.first..u.first + u.count];
        var i = lower_bound(mine) { it.started < to } - 1;
        var n = 0;
        while i >= 0 && mine[i].started > from - DAY {
            if mine[i].stopped < 0 || mine[i].stopped > from {
                if n > 0 { buf.push(','); }
                snow_entry(buf, u.first + i);
                n++;
            }
            i--;
        }
    }
    buf.push(']');
    http::respond(out, 200, "application/json", buf);
}

fn list_projects(req: http::Request, p: Person, m: Member, buf: u8[>..]&, out: http::Reply) {
    let v, has = http::query_of(req.target, "includeArchived");
    guard !has || v == "true" || v == "false" else { invalid(out); return; }
    let archived = has && v == "true";
    let o = orgs[m.org];
    buf.push('[');
    var n = 0;
    for i in o.first..o.first + o.count {
        let j = projects[i];
        if (archived || j.archived < 0) && sees(p, m, j) {
            if n > 0 { buf.push(','); }
            if template { buf.append(project_json[project_at[i]..project_at[i + 1]]); } else { project_full(buf, j); }
            n++;
        }
    }
    buf.push(']');
    http::respond(out, 200, "application/json", buf);
}

// Whether body is one JSON value.
fn is_json(body: const u8[:]) -> bool {
    var r = json::reader(body);
    json::skip(r);
    return json::finish(r);
}

// The trimmed string member, at most 500 bytes: false for another type or a
// longer one.
fn description_of(r: json::Reader&, scratch: u8[>..]&) -> const u8[:], bool {
    guard json::peek(r) == '"' else { json::skip(r); return "", false; }
    let s = trim(json::read_string(r, scratch));
    return s, s.len <= 500;
}

fn patch_entry(id: const u8[:], body: const u8[:], p: Person, m: Member, buf: u8[>..]&, out: http::Reply) {
    guard is_uuid7(id) else { invalid(out); return; }
    guard is_json(body) else { not_json(out); return; }
    var scratch: u8[>..] = [];
    var r = json::reader(body);
    var description: u8[>..] = [];
    var has = false;
    var ok = json::peek(r) == '{';
    if ok {
        json::each_member(r) { key =>
            if key == "description" {
                let d, fits = description_of(r, scratch);
                description.append(d);
                ok = ok && fits;
                has = true;
            } else { json::skip(r); }
        };
    }
    guard ok && json::finish(r) else { invalid(out); return; }
    let i = entry_index(id);
    guard i >= 0 && entries[i].org == m.org else { coded(out, 404, "NOT_FOUND", "entry_not_found"); return; }
    guard people[entries[i].user].id == p.id || is_admin(m) else { coded(out, 403, "FORBIDDEN", "entry_forbidden"); return; }
    if has { snow_entry_as(buf, i, description); } else { snow_entry(buf, i); }
    http::respond(out, 200, "application/json", buf);
}

// POST .../timer/start: the new entry, started now, and the timer it
// stopped, the caller's running one, or null.
fn start_timer(body: const u8[:], u: i64, m: Member, buf: u8[>..]&, out: http::Reply) {
    guard is_json(body) else { not_json(out); return; }
    var scratch: u8[>..] = [];
    var r = json::reader(body);
    var id: u8[..36] = "";
    var description: u8[>..] = [];
    var ticket: u8[..18] = "";
    var project: u8[..36] = "";
    var ok = json::peek(r) == '{';
    if ok {
        json::each_member(r) { key =>
            let c = json::peek(r);
            if key == "description" {
                let d, fits = description_of(r, scratch);
                description.append(d);
                ok = ok && fits;
            } else if c == 'n' && (key == "ticket" || key == "projectId") {
                json::skip(r);
            } else if key == "id" || key == "ticket" || key == "projectId" {
                let s = if c == '"' { json::read_string(r, scratch) } else { "" };
                if s.len == 0 { ok = false; json::skip(r); }
                else if key == "id" && s.len <= id.cap { id.append(s); }
                else if key == "ticket" && s.len <= ticket.cap && is_ticket(s) { ticket.append(s); }
                else if key == "projectId" && is_uuid7(s) { project.append(s); }
                else { ok = false; }
            } else { json::skip(r); }
        };
    }
    guard ok && json::finish(r) && is_uuid7(id) else { invalid(out); return; }
    let p = people[u];
    if project.len > 0 {
        let j = project_index(project, m.org);
        guard j >= 0 && sees(p, m, projects[j]) else { coded(out, 404, "NOT_FOUND", "project_not_found"); return; }
        guard projects[j].archived < 0 else { coded(out, 409, "CONFLICT", "project_archived"); return; }
    }
    guard entry_index(id) < 0 else { coded(out, 409, "CONFLICT", "entry_id_taken"); return; }
    let now = now_ms();
    buf.append("{\"started\":{\"id\":");
    json::format_string(buf, id);
    buf.append(",\"organizationId\":");
    json::format_string(buf, orgs[m.org].id);
    buf.append(",\"userId\":");
    json::format_string(buf, p.id);
    buf.append(",\"projectId\":");
    string_or_null(buf, project);
    buf.append(",\"description\":");
    json::format_string(buf, description);
    buf.append(",\"ticket\":");
    string_or_null(buf, ticket);
    buf.append(",\"startedAt\":");
    iso_or_null(buf, now);
    buf.append(",\"stoppedAt\":null},\"stopped\":");
    if p.running >= 0 { snow_stopped(buf, p.running, now); } else { buf.append("null"); }
    buf.push('}');
    http::respond(out, 200, "application/json", buf);
}

// POST /timer/stop: the caller's running entry, stopped now. An id the
// dataset doesn't have is taken for a timer started with it, as timer start
// answered it: a uuidv7 made in the last day.
fn stop_timer(body: const u8[:], u: i64, buf: u8[>..]&, out: http::Reply) {
    guard is_json(body) else { not_json(out); return; }
    var scratch: u8[>..] = [];
    var r = json::reader(body);
    var id: u8[..36] = "";
    var ok = json::peek(r) == '{';
    if ok {
        json::each_member(r) { key =>
            if key == "id" && json::peek(r) == '"' {
                let s = json::read_string(r, scratch);
                if s.len <= id.cap { id.append(s); } else { ok = false; }
            } else { json::skip(r); }
        };
    }
    guard ok && json::finish(r) && is_uuid7(id) else { invalid(out); return; }
    let p = people[u];
    let now = now_ms();
    if p.running >= 0 && entries[p.running].id == id {
        snow_stopped(buf, p.running, now);
    } else {
        let started = uuid_ms(id);
        guard started > now - DAY && started <= now + MINUTE && entry_index(id) < 0
            else { coded(out, 404, "NOT_FOUND", "timer_not_running"); return; }
        buf.append("{\"id\":");
        json::format_string(buf, id);
        buf.append(",\"organizationId\":");
        json::format_string(buf, orgs[p.active].id);
        buf.append(",\"userId\":");
        json::format_string(buf, p.id);
        buf.append(",\"projectId\":null,\"description\":\"\",\"ticket\":null,\"startedAt\":");
        iso_or_null(buf, started);
        buf.append(",\"stoppedAt\":");
        iso_or_null(buf, min(max(now, started + 1), started + DAY));
        buf.push('}');
    }
    http::respond(out, 200, "application/json", buf);
}

// Tier B's routes, checked in snowtime's order: an unknown call, a write
// from another origin, GET /session, which answers null to no one, the
// sign-in, and the organization's membership.
fn snow(req: http::Request, body: const u8[:], buf: u8[>..]&, out: http::Reply) {
    var r = http::router(req);
    var route = 0;
    if http::on(r, "GET", "/api/v1/session") { route = 1; }
    else if http::on(r, "GET", "/api/v1/timer") { route = 2; }
    else if http::on(r, "POST", "/api/v1/timer/stop") { route = 3; }
    else if http::on(r, "GET", "/api/v1/organizations/:org/entries") { route = 4; }
    else if http::on(r, "GET", "/api/v1/organizations/:org/projects") { route = 5; }
    else if http::on(r, "PATCH", "/api/v1/organizations/:org/entries/:id") { route = 6; }
    else if http::on(r, "POST", "/api/v1/organizations/:org/timer/start") { route = 7; }
    guard route > 0 else { error(out, 404, "{\"error\":{\"message\":\"No such call.\"}}"); return; }
    if req.method != "GET" && req.method != "HEAD" {
        let origin, has = http::field_of(req, "origin");
        guard has && origin == app_url()
            else { error(out, 403, "{\"error\":{\"message\":\"Cross-origin request refused.\"}}"); return; }
    }
    let u = person_of(req);
    if route == 1 {
        if u < 0 { buf.append("null"); }
        else if template { buf.append(session_json[session_at[u]..session_at[u + 1]]); }
        else { session_open(buf, people[u]); }
        http::respond(out, 200, "application/json", buf);
        return;
    }
    guard u >= 0 else { coded(out, 401, "UNAUTHENTICATED", "sign_in_required"); return; }
    let p = people[u];
    if route == 2 {
        if template { buf.append(timer_json[timer_at[u]..timer_at[u + 1]]); }
        else if p.running >= 0 { timer_full(buf, entries[p.running]); }
        else { buf.append("null"); }
        http::respond(out, 200, "application/json", buf);
        return;
    }
    if route == 3 { stop_timer(body, u, buf, out); return; }
    let k = membership(p, http::param(r, "org"));
    guard k >= 0 else { coded(out, 403, "FORBIDDEN", "not_organization_member"); return; }
    let m = p.orgs[k];
    if route == 4 { list_entries(req, p, m, buf, out); }
    else if route == 5 { list_projects(req, p, m, buf, out); }
    else if route == 6 { patch_entry(http::param(r, "id"), body, p, m, buf, out); }
    else { start_timer(body, u, m, buf, out); }
}

// Each response's JSON is built in a buffer of the request's own, which the
// data stack frees at the end of the request with one store: one kept in the
// worker and cleared per request is refused, the checker taking the loop's
// events for slices that may point into it.
inline fn handle(req: http::Request, body: const u8[:], out: http::Reply) {
    var buf: u8[>..] = [];
    if starts_with(req.target, "/api/v1/") { snow(req, body, buf, out); return; }
    var r = http::router(req);
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
    var tier: u8[>..] = [];
    if !env("TIER", tier) { tier.append("a"); }
    var mode: u8[>..] = [];
    template = env("JSON", mode) && mode == "template";
    if tier == "a" {
        load_items(dir);
        load_users(dir);
        if template { prebuild(); }
    } else if tier == "b" {
        load_orgs(dir);
        load_people(dir);
        load_entries(dir);
        if template { prebuild_snow(); }
    } else {
        abort("TIER is a or b");
    }
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
    print("rest: tier ", tier, ", ", items.len + entries.len, " records, ", count, " workers on port ", port,
          if epoll { ", epoll" } else { ", uring" }, if template { ", template" } else { ", serialize" });
    var ids: i64[>..] = [];
    for i in count { ids.push(if epoll { thread_spawn(worker_epoll, cfg) } else { thread_spawn(worker, cfg) }); }
    for id in ids { thread_wait(id); }
}
