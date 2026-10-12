// The REST benchmark's datasets (task 021), written as JSON files that every
// server loads at startup and the checker compares responses with. The same
// seed writes the same files on every platform.
//
//   goose build -o build/rest/gen bench/rest/gen.goose && build/rest/gen OUTDIR
//
// Tier A, HttpArena's production-stack: arena-items.json, 10,000 items as
// HttpArena's dataset.json has them, and arena-users.json, 1,000 users.
//
// Tier B, snowtime's k6 hot path: snow-orgs.json, 20 organizations with their
// projects; snow-users.json, 200 users with what GET /api/v1/session answers
// for each, and the session cookie that names them; snow-entries.json, their
// time entries over the 60 days up to the dataset's moment, T0; and
// snow-load.txt, for tier-b.lua, a line per user of the Cookie field and the
// ids and the entries window its requests carry.
//
// Tier C, a clinic's schedule and records, synthetic: heavy-staff.json,
// heavy-services.json, and heavy-clients.json, the records the others name;
// heavy-bookings.json and heavy-shifts.json, four weeks of 10 staff's
// schedule from 2026-09-07; heavy-encounters.json, the visits, with their
// notes, two years of them for 100 clients and one per booking;
// heavy-meta.json, from when the schedule's version counts; and
// heavy-load.txt, for tier-c.lua, the staff's bearer tokens and the ranges
// its requests draw from. Free text is words from WORDS.
import std;
import os;
import json;
import base64;

// splitmix64: small, and the same sequence everywhere.
var seed: u64 = 0x9E3779B97F4A7C15;

fn next() -> u64 {
    seed += 0x9E3779B97F4A7C15;
    var z = seed;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

// A number in lo..hi, both included.
fn between(lo: i64, hi: i64) -> i64 { lo + (next() % ((hi - lo + 1) as u64)) as i64 }

fn pick(words: const u8[:][:]) -> const u8[:] { words[between(0, words.len - 1)] }

let ADJECTIVES: const u8[:][] = ["Alpha", "Pro", "Core", "Nova", "Prime", "Ultra", "Smart", "Rapid", "Eco",
                                 "Max", "Zen", "Flex"];
let NOUNS: const u8[:][] = ["Widget", "Valve", "Relay", "Sensor", "Gadget", "Module", "Panel", "Switch",
                            "Drive", "Filter"];
let CATEGORIES: const u8[:][] = ["electronics", "tools", "books", "home", "garden", "toys", "sports"];
let TAGS: const u8[:][] = ["sale", "heavy-duty", "popular", "fast", "new", "wireless", "eco", "compact",
                           "premium"];
let GIVEN: const u8[:][] = ["Mari", "Jaan", "Kati", "Peeter", "Liis", "Andres", "Kadri", "Toomas", "Anna",
                            "Mart"];
let FAMILY: const u8[:][] = ["Tamm", "Saar", "Sepp", "Mägi", "Kask", "Kukk", "Rebane", "Ilves", "Pärn",
                             "Koppel"];
let PLANS: const u8[:][] = ["free", "pro", "team", "enterprise"];

fn arena_items(out: u8[>..]&) {
    out.push('[');
    for i in 10000 {
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"name\":");
        json::format_string(out, str(pick(ADJECTIVES), " ", pick(NOUNS)));
        out.append(",\"category\":");
        json::format_string(out, pick(CATEGORIES));
        out.append(",\"price\":");
        format(out, between(1, 500));
        out.append(",\"quantity\":");
        format(out, between(0, 100));
        out.append(",\"active\":");
        out.append(if between(0, 9) > 0 { "true" } else { "false" });
        out.append(",\"tags\":[");
        // Up to 4 tags, without repeats.
        var used: u64 = 0;
        let n = between(1, 4);
        var k = 0;
        while k < n {
            let t = between(0, TAGS.len - 1);
            if (used >> t) & 1 == 0 {
                used |= 1 << t;
                if k > 0 { out.push(','); }
                json::format_string(out, TAGS[t]);
                k++;
            }
        }
        out.append("],\"rating\":{\"score\":");
        format(out, between(10, 50));
        out.append(",\"count\":");
        format(out, between(0, 500));
        out.append("}}");
    }
    out.push(']');
}

fn arena_users(out: u8[>..]&) {
    out.push('[');
    for i in 1000 {
        if i > 0 { out.push(','); }
        let g = pick(GIVEN);
        let f = pick(FAMILY);
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"name\":");
        json::format_string(out, str(g, " ", f));
        out.append(",\"email\":");
        json::format_string(out, str("user", i + 1, "@example.test"));
        out.append(",\"plan\":");
        json::format_string(out, pick(PLANS));
        out.push('}');
    }
    out.push(']');
}

// Tier B.

// 2026-10-12T09:00:00.000Z, a Monday: the entries end here, and the running
// timers started shortly before.
let T0: i64 = 1791795600000;
let DAY: i64 = 86400000;
let MINUTE: i64 = 60000;

struct Zone { name: const u8[:], offset: i64, country: const u8[:], locale: const u8[:] }

// snowtime's bench zones, with their offsets in minutes between August and
// October 2026, when none of them changes.
let ZONES: Zone[] = [
    Zone { name: "Europe/Tallinn", offset: 180, country: "EE", locale: "et" },
    Zone { name: "Europe/Helsinki", offset: 180, country: "FI", locale: "en" },
    Zone { name: "Europe/Stockholm", offset: 120, country: "SE", locale: "en" },
    Zone { name: "Europe/Berlin", offset: 120, country: "DE", locale: "en" },
    Zone { name: "Europe/Warsaw", offset: 120, country: "PL", locale: "en" },
    Zone { name: "Europe/Madrid", offset: 120, country: "ES", locale: "en" },
    Zone { name: "America/New_York", offset: -240, country: "US", locale: "en" },
];

let PALETTE: const u8[:][] = ["#3b82b8", "#d9703f", "#7a6fc8", "#4f8f3a", "#c9514f", "#e0a030", "#2e8b57"];
let INTERNAL: const u8[:][] = ["Internal", "Sales and pitches", "Hiring", "Training"];
let CUSTOMERS: const u8[:][] = ["Nordbank", "Lumen", "Kivi", "Sild", "Tuul", "Mets", "Laine", "Ranna",
                                "Vikerkaar", "Paju", "Kaja", "Hobe"];
let PRODUCTS: const u8[:][] = ["website", "app", "portal", "API", "audit", "shop", "intranet", "migration"];
let PHRASES: const u8[:][] = ["Code review", "Sprint planning", "Bug fixing", "Client call", "Design review",
                              "Writing tests", "Deployment", "Documentation", "Refactoring the importer",
                              "Support tickets", "Estimating the next release", "Pairing on the API",
                              "Team meeting", "Onboarding a new colleague", "Research", "Fixing the build",
                              "Release notes", "Database migration", "Performance profiling", "Workshop prep"];
let ROLES: const u8[:][] = ["owner", "admin", "member"];
let THEMES: const u8[:][] = ["system", "light", "dark"];

struct Org { id: u8[..36], name: u8[..16], slug: u8[..16], links: bool, teams: u8[..36][..3] }

struct Project {
    id: u8[..36],
    name: u8[..48],
    color: u8[..7],
    key: u8[..8],
    archived: i64,
    has_entries: bool,
    teams: i64[..2],
}

struct Member { org: i64, role: i64 }

struct Person {
    id: u8[..36],
    name: u8[..48],
    email: u8[..48],
    token: u8[..64],
    cookie: u8[..128],
    signed_in: i64,
    orgs: Member[..6],
    teams: i64[..2],
    zone: i64,
    locale: u8[..2],
    running: i64,
    last_done: i64,
}

struct Entry {
    id: u8[..36],
    user: i64,
    project: i64,
    description: u8[..64],
    ticket: u8[..12],
    started: i64,
    stopped: i64,
}

var orgs: Org[>..];
var projects: Project[>..];     // 20 per organization, by name
var people: Person[>..];
var entries: Entry[>..];        // by user, then by start
var id_count: i64 = 0;

// A uuidv7 as snowtime's bench dataset makes one: the time in the first 48
// bits, then a counter, with the variant nibble 9.
fn uuid(out: u8[..36]&, ms: i64) {
    id_count++;
    var s: u8[>..] = [];
    format_uint(s, ms as u64, 16, 12, '0');
    s.insert_at(8, '-');
    s.append("-7");
    format_uint(s, ((id_count >> 12) & 0xFFF) as u64, 16, 3, '0');
    s.append("-9");
    format_uint(s, (id_count & 0xFFF) as u64, 16, 3, '0');
    s.push('-');
    format_uint(s, next() & 0xFFFFFFFFFFFF, 16, 12, '0');
    out.clear();
    out.append(s);
}

fn digits(out: u8[>..]&, v: i64, n: i64) {
    var div = 1;
    for i in n - 1 { div *= 10; }
    while div > 0 {
        out.push(('0' + v / div % 10) as u8);
        div /= 10;
    }
}

// day, in days since the epoch, as YYYY-MM-DD (Howard Hinnant's
// civil_from_days).
fn format_date(out: u8[>..]&, day: i64) {
    let z = day + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    digits(out, yoe + era * 400 + (if m <= 2 { 1 } else { 0 }), 4);
    out.push('-');
    digits(out, m, 2);
    out.push('-');
    digits(out, d, 2);
}

// ms since the epoch as JavaScript's toISOString writes it.
fn format_iso(out: u8[>..]&, ms: i64) {
    let day = ms / DAY;
    let t = ms - day * DAY;
    format_date(out, day);
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

fn iso_or_null(out: u8[>..]&, ms: i64) {
    if ms < 0 { out.append("null"); return; }
    out.push('"');
    format_iso(out, ms);
    out.push('"');
}

fn string_or_null(out: u8[>..]&, s: const u8[:]) {
    if s.len == 0 { out.append("null"); } else { json::format_string(out, s); }
}

// The local date's midnight in a zone, in ms since the epoch.
fn midnight(day: i64, zone: i64) -> i64 { day * DAY - ZONES[zone].offset * MINUTE }

fn local_day(ms: i64, zone: i64) -> i64 { (ms + ZONES[zone].offset * MINUTE) / DAY }

// Monday is 0.
fn weekday(day: i64) -> i64 { (day + 3) % 7 }

fn visible(p: Project, u: Person) -> bool {
    if u.orgs[0].role < 2 || p.teams.len == 0 { return true; }
    for t in p.teams { if contains(u.teams, t) { return true; } }
    return false;
}

fn snow_orgs() {
    for o in 20 {
        let org .= orgs.push(Org { .. });
        uuid(org.id, T0 - 400 * DAY + o * DAY);
        format(org.name, "Company ", o + 1);
        format(org.slug, "bench-", o + 1);
        org.links = between(0, 1) == 0;
        for t in 3 { uuid(org.teams.push(""), T0 - 390 * DAY + o * DAY); }
        let first = projects.len;
        for i in 20 {
            let p .= projects.push(Project { archived: -1, .. });
            uuid(p.id, T0 - 380 * DAY + o * DAY + i * MINUTE);
            if i < INTERNAL.len {
                p.name.append(INTERNAL[i]);
                p.color.append(PALETTE[i]);
                continue;
            }
            let customer = pick(CUSTOMERS);
            format(p.name, customer, " ", pick(PRODUCTS), " ", i - INTERNAL.len + 1);
            if between(0, 19) > 0 { p.color.append(pick(PALETTE)); }
            if between(0, 9) < 7 {
                for c in customer[..3] { p.key.push(if c >= 'a' { c - 32 } else { c }); }
                format(p.key, i);
            }
            if between(0, 99) < 9 { p.archived = T0 - between(5, 200) * DAY - between(0, 1000) * MINUTE; }
            if between(0, 1) == 0 {
                p.teams.push(between(0, 2));
                if between(0, 2) == 0 {
                    let t = between(0, 2);
                    if t != p.teams[0] { p.teams.push(t); }
                }
            }
        }
        sort(projects[first..]) { a, b => compare(a.name, b.name) < 0 };
    }
}

fn snow_people() {
    for u in 200 {
        let p .= people.push(Person { running: -1, last_done: -1, .. });
        let o = u / 10;
        let j = u % 10;
        uuid(p.id, T0 - 360 * DAY + u * 3 * MINUTE);
        format(p.name, pick(GIVEN), " ", pick(FAMILY));
        format(p.email, "c", o + 1, "p", j + 1, "@bench.example.com");
        var hex: u8[>..] = [];
        for k in 4 { format_uint(hex, next(), 16, 16, '0'); }
        p.token.append(hex);
        let r = between(0, 19);
        p.zone = if r < 14 { 0 } else { r - 13 };
        p.locale.append(if p.zone == 0 && between(0, 9) < 6 { "et" } else { "en" });
        // The session cookie's value, as snowtime's bench signs it:
        // encodeURIComponent of the token, a dot, and a base64 HMAC.
        var mac: u8[>..] = [];
        for k in 32 { mac.push((next() & 0xFF) as u8); }
        var sig: u8[>..] = [];
        base64::encode(sig, mac);
        p.cookie.append(p.token);
        p.cookie.push('.');
        for c in sig {
            if c == '+' { p.cookie.append("%2B"); }
            else if c == '/' { p.cookie.append("%2F"); }
            else if c == '=' { p.cookie.append("%3D"); }
            else { p.cookie.push(c); }
        }
        p.signed_in = T0 - between(60, 20 * 24 * 60) * MINUTE - between(0, 59999);
        let role = if j == 0 { 0 } else if j == 5 && between(0, 1) == 0 { 1 } else { 2 };
        p.orgs.push(Member { org: o, role: role });
        let more = between(1, 4);
        while p.orgs.len <= more {
            let other = between(0, 19);
            let taken = p.orgs.any() { it.org == other };
            if taken { continue; }
            p.orgs.push(Member { org: other, role: if between(0, 9) == 0 { 1 } else { 2 } });
        }
        for t in 3 { if between(0, 2) == 0 && p.teams.len < 2 { p.teams.push(t); } }
    }
}

// Each user's entries: 3 to 6 on each weekday of the 60 days up to T0, in
// their primary organization, and for 15% a timer started 10 to 180 minutes
// before T0 and still running.
fn snow_entries() {
    for &p, u in people {
        let o = p.orgs[0].org;
        var usable: i64[>..] = [];
        for i in o * 20..o * 20 + 20 {
            if projects[i].archived < 0 && visible(projects[i], p) { usable.push(i); }
        }
        let runs = between(0, 99) < 15;
        let run_start = T0 - between(10, 180) * MINUTE - between(0, 59999);
        let end = if runs { run_start } else { T0 };
        let today = local_day(T0, p.zone);
        for d in today - 59..today + 1 {
            if weekday(d) > 4 { continue; }
            var at = midnight(d, p.zone) + (8 * 60 + between(0, 90)) * MINUTE + between(0, 59999);
            for k in between(3, 6) {
                let stopped = at + between(30, 150) * MINUTE + between(0, 59999);
                if stopped > end { break; }
                let e .= entries.push(Entry { user: u, project: -1, started: at, stopped: stopped, .. });
                uuid(e.id, at);
                if between(0, 9) > 0 { e.project = usable[between(0, usable.len - 1)]; }
                let phrase = pick(PHRASES);
                let key = if e.project >= 0 { projects[e.project].key } else { "" };
                if between(0, 19) == 0 {
                    // an empty description, as the dataset sometimes has
                } else if key.len > 0 && between(0, 9) < 6 {
                    format(e.ticket, key, "-", between(100, 999));
                    let form = between(0, 3);
                    if form == 0 { format(e.description, e.ticket, " ", phrase); }
                    else if form == 1 { format(e.description, "[", e.ticket, "] ", phrase); }
                    else if form == 2 { format(e.description, e.ticket, ": ", phrase); }
                    else { format(e.description, phrase, " (", e.ticket, ")"); }
                } else {
                    e.description.append(phrase);
                }
                if e.project >= 0 { projects[e.project].has_entries = true; }
                p.last_done = entries.len - 1;
                at = stopped + between(0, 30) * MINUTE + between(0, 59999);
            }
        }
        if runs {
            let e .= entries.push(Entry { user: u, project: o * 20, started: run_start, stopped: -1, .. });
            uuid(e.id, run_start);
            e.description.append("Team meeting");
            projects[o * 20].has_entries = true;
            p.running = entries.len - 1;
        }
    }
}

fn snow_orgs_json(out: u8[>..]&) {
    out.push('[');
    for org, o in orgs {
        if o > 0 { out.push(','); }
        out.append("{\"id\":");
        json::format_string(out, org.id);
        out.append(",\"name\":");
        json::format_string(out, org.name);
        out.append(",\"slug\":");
        json::format_string(out, org.slug);
        out.append(",\"issueLinks\":");
        out.append(if org.links { "\"https://issues.example.com/browse/{key}\"" } else { "null" });
        out.append(",\"projects\":[");
        for i in o * 20..o * 20 + 20 {
            let p = projects[i];
            if i > o * 20 { out.push(','); }
            out.append("{\"id\":");
            json::format_string(out, p.id);
            out.append(",\"name\":");
            json::format_string(out, p.name);
            out.append(",\"color\":");
            string_or_null(out, p.color);
            out.append(",\"archivedAt\":");
            iso_or_null(out, p.archived);
            out.append(if p.has_entries { ",\"hasEntries\":true" } else { ",\"hasEntries\":false" });
            out.append(",\"teamIds\":[");
            for t, k in p.teams {
                if k > 0 { out.push(','); }
                json::format_string(out, org.teams[t]);
            }
            out.append("]}");
        }
        out.append("]}");
    }
    out.push(']');
}

fn bool_field(out: u8[>..]&, name: const u8[:], v: bool) {
    out.append(",\"");
    out.append(name);
    out.append(if v { "\":true" } else { "\":false" });
}

fn string_field(out: u8[>..]&, name: const u8[:], v: const u8[:]) {
    out.append(",\"");
    out.append(name);
    out.append("\":");
    json::format_string(out, v);
}

// Hours logged on a local day.
fn logged(u: i64, day: i64) -> i64 {
    var ms = 0;
    for e in entries {
        if e.user == u && e.stopped >= 0 && local_day(e.started, people[u].zone) == day { ms += e.stopped - e.started; }
    }
    return ms / 3600000;
}

fn snow_users_json(out: u8[>..]&) {
    out.push('[');
    for p, u in people {
        let z = ZONES[p.zone];
        let us = p.zone == 6;
        if u > 0 { out.push(','); }
        out.append("{\"id\":");
        json::format_string(out, p.id);
        string_field(out, "name", p.name);
        string_field(out, "email", p.email);
        out.append(",\"image\":");
        if between(0, 3) == 0 {
            json::format_string(out, str("https://avatars.example.com/", p.id, ".png"));
        } else {
            out.append("null");
        }
        string_field(out, "token", p.token);
        string_field(out, "cookie", p.cookie);
        out.append(",\"signedInAt\":");
        iso_or_null(out, p.signed_in);
        out.append(",\"organizations\":[");
        // The session lists them by name, then id.
        var order = copy(p.orgs);
        sort(order) { a, b =>
            let c = compare(orgs[a.org].name, orgs[b.org].name);
            c < 0 || c == 0 && compare(orgs[a.org].id, orgs[b.org].id) < 0
        };
        for m, k in order {
            if k > 0 { out.push(','); }
            out.append("{\"id\":");
            json::format_string(out, orgs[m.org].id);
            string_field(out, "role", ROLES[m.role]);
            out.push('}');
        }
        out.append("],\"activeOrganizationId\":");
        json::format_string(out, orgs[p.orgs[0].org].id);
        out.append(",\"teamIds\":[");
        for t, k in p.teams {
            if k > 0 { out.push(','); }
            json::format_string(out, orgs[p.orgs[0].org].teams[t]);
        }
        out.append("],\"settings\":{\"timeZone\":");
        json::format_string(out, z.name);
        string_field(out, "weekStart", if us { "sun" } else { "mon" });
        string_field(out, "locale", p.locale);
        string_field(out, "theme", pick(THEMES));
        string_field(out, "timerLayout", if between(0, 4) == 0 { "focus" } else { "bar" });
        bool_field(out, "showSummary", between(0, 9) > 0);
        bool_field(out, "compactRows", between(0, 4) == 0);
        bool_field(out, "wideTimer", between(0, 9) == 0);
        string_field(out, "timerView", if between(0, 3) == 0 { "calendar" } else { "list" });
        bool_field(out, "calendarWeekend", between(0, 9) == 0);
        string_field(out, "appIcon", "02");
        string_field(out, "sceneCollection", "mountains");
        out.append(",\"scenePin\":null");
        bool_field(out, "sceneBackground", between(0, 9) > 0);
        string_field(out, "sceneStrength", if between(0, 4) == 0 { "full" } else { "dimmed" });
        string_field(out, "surfaces", if between(0, 4) == 0 { "solid" } else { "glass" });
        bool_field(out, "sceneWeather", true);
        bool_field(out, "sceneIntro", false);
        bool_field(out, "sceneTagline", true);
        string_field(out, "durationFormat", if between(0, 4) == 0 { "units" } else { "clock" });
        string_field(out, "dateFormat", if us { "mdy" } else { "dmy" });
        string_field(out, "timeFormat", if us { "12h" } else { "24h" });
        string_field(out, "copyDurationPattern", "H:MM:SS");
        string_field(out, "copyDurationControl", "text");
        out.append(",\"country\":");
        string_or_null(out, if between(0, 4) == 0 { "" } else { z.country });
        // fill, the taglines' summary, as the dataset's values: today is T0's
        // local date, and the last working day the Friday before.
        let today = local_day(T0, p.zone);
        out.append("},\"fill\":{\"date\":\"");
        format_date(out, today);
        out.append("\",\"timerStartedAt\":");
        if p.running >= 0 { format(out, entries[p.running].started); } else { out.append("null"); }
        string_field(out, "today", "open");
        out.append(",\"lastWorkingDay\":{\"date\":\"");
        format_date(out, today - 3);
        out.push('"');
        bool_field(out, "filled", logged(u, today - 3) >= 6);
        out.push('}');
        bool_field(out, "lastWeek", between(0, 2) > 0);
        bool_field(out, "lastMonth", between(0, 2) > 0);
        let empty = between(0, 3);
        bool_field(out, "caughtUp", empty == 0);
        out.append(",\"emptyDays\":");
        format(out, empty);
        out.append(",\"streak\":");
        format(out, between(0, 30));
        out.append("},\"invitationId\":null}");
    }
    out.push(']');
}

fn snow_entries_json(out: u8[>..]&) {
    out.push('[');
    for e, i in entries {
        if i > 0 { out.push(','); }
        let p = people[e.user];
        out.append("{\"id\":");
        json::format_string(out, e.id);
        out.append(",\"organizationId\":");
        json::format_string(out, orgs[p.orgs[0].org].id);
        out.append(",\"userId\":");
        json::format_string(out, p.id);
        out.append(",\"projectId\":");
        string_or_null(out, if e.project >= 0 { projects[e.project].id } else { "" });
        out.append(",\"description\":");
        json::format_string(out, e.description);
        out.append(",\"ticket\":");
        string_or_null(out, e.ticket);
        out.append(",\"startedAt\":");
        iso_or_null(out, e.started);
        out.append(",\"stoppedAt\":");
        iso_or_null(out, e.stopped);
        out.push('}');
    }
    out.push(']');
}

// An ISO time with its colons percent-encoded, as URLSearchParams writes it.
fn query_time(out: u8[>..]&, ms: i64) {
    var s: u8[>..] = [];
    format_iso(s, ms);
    format_replaced(out, s, ":", "%3A");
}

// A line per user, tab-separated: the Cookie field, the user's id, the
// primary organization's, the last finished entry's, and the 14 local days'
// window up to T0's local date, from and to, as the timer page asks for it.
fn snow_load(out: u8[>..]&) {
    for p in people {
        let today = local_day(T0, p.zone);
        format(out, "__Secure-better-auth.session_token=", p.cookie, "; PARAGLIDE_LOCALE=", p.locale, "\t",
               p.id, "\t", orgs[p.orgs[0].org].id, "\t", entries[p.last_done].id, "\t");
        query_time(out, midnight(today - 13, p.zone));
        out.push('\t');
        query_time(out, midnight(today + 1, p.zone));
        out.push('\n');
    }
}

// Tier C.

let WEEK0: i64 = 1788739200000;     // Monday 2026-09-07, the schedule's first day
let TODAY: i64 = 1789948800000;     // Monday 2026-09-21: the visits before it happened
let HISTORY0: i64 = 1725235200000;  // Monday 2024-09-02, the first visit of the history
let VERSION0: i64 = 1788220800000;  // 2026-09-01: the schedule's version is minutes since
let SLOT: i64 = 1800000;
let OPEN: i64 = 5 * 3600000;        // 08:00 in the clinic's zone, UTC+3

let TITLES: const u8[:][] = ["Physiotherapist", "Senior physiotherapist", "Occupational therapist", "Nurse",
                             "Physician", "Rehabilitation assistant"];
let STREETS: const u8[:][] = ["Pikk", "Lai", "Kooli", "Metsa", "Mere", "Aia", "Pargi", "Jaama", "Turu", "Vabriku"];
let CITIES: const u8[:][] = ["Tallinn", "Tartu", "Pärnu", "Narva", "Viljandi", "Rakvere", "Haapsalu"];
let SERVICES: const u8[:][] = ["Initial assessment", "Follow-up visit", "Manual therapy", "Exercise therapy",
                               "Gait training", "Balance training", "Hand therapy", "Taping",
                               "Shockwave treatment", "Ultrasound therapy", "Group exercise", "Home visit",
                               "Telephone consultation", "Video consultation", "Work ability review",
                               "Splint fitting", "Lymphatic drainage", "Dry needling", "Massage",
                               "Hydrotherapy", "Ergonomic advice", "Discharge review", "Pain education",
                               "Strength testing"];
let FLAGS: const u8[:][] = ["interpreter", "wheelchair", "allergy", "minor", "hearing", "vip"];
let KINDS: const u8[:][] = ["treatment", "follow-up", "review", "phone"];
let ROOMS: const u8[:][] = ["Room 1", "Room 2", "Room 3", "Gym", "Pool", "Treatment 4"];
let NOTE_KINDS: const u8[:][] = ["intake", "findings", "plan", "internal"];
// Words for the free text: notes, booking notes, and shift notes.
let WORDS: const u8[:][] = [
    "reports", "mild", "moderate", "pain", "since", "last", "week", "improved", "after", "exercise",
    "advised", "continue", "review", "in", "two", "weeks", "sleep", "stable", "no", "change", "walking",
    "range", "motion", "left", "right", "shoulder", "knee", "back", "neck", "morning", "evening",
    "stiffness", "swelling", "plan", "home", "program", "stretching", "daily", "follow", "up",
    "discussed", "goals", "work", "sitting", "posture", "tolerates", "load", "well", "reduced",
    "increase", "gradually", "monitor", "symptoms", "noted", "shows", "strength", "balance", "good",
    "fair", "limited", "tender", "on", "palpation", "with", "without", "the", "and", "to", "of", "a",
    "for", "at", "is", "was", "has", "not", "more", "less", "than", "before", "during", "stairs",
    "cycling", "running", "lifting", "carrying", "grip", "ankle", "hip", "wrist", "elbow", "spine",
    "flexion", "extension", "rotation", "rest", "ice", "heat", "taping", "brace", "night", "day",
    "steps", "minutes", "sets", "repetitions", "progress", "slowly", "today", "yesterday", "client",
    "feels", "better", "worse", "same", "able", "unable", "manage", "independently", "support",
    "family", "job", "return", "plans", "next", "visit", "booked", "phone", "call", "message",
    "letter", "referral", "scan", "results", "pending", "normal", "small", "large", "short", "long",
    "walk", "garden", "office", "desk", "chair", "car", "bus", "bike", "stretch", "core", "control",
    "breathing", "relaxation", "technique", "correct", "repeat", "measure", "score", "questionnaire",
    "completed", "agreed", "target", "end", "month", "season", "trip", "holiday", "weather", "cold",
];

struct Staff { name: u8[..32], title: u8[..32] }

struct Service { code: u8[..8], name: u8[..32], minutes: i64, price: i64 }

struct Client { name: u8[..48], code: u8[..8] }

struct Line { id: i64, service: i64 }

struct Note { kind: i64, author: i64, at: i64, text_at: i64, text_len: i64 }

struct Visit {
    client: i64,
    staff: i64,
    case_id: i64,
    status: u8[..10],
    kind: u8[..12],
    priority: u8[..8],
    start: i64,
    end: i64,
    lines: Line[..3],
    codes: u8[..8][..3],
    first_note: i64,
    notes: i64,
}

struct Reminder { channel: u8[..5], kind: u8[..12], status: u8[..9], at: i64 }

struct Booking {
    start: i64,
    staff: i64,
    client: i64,
    visit: i64,
    lines: Line[..3],
    reminders: Reminder[..3],
    status: u8[..10],
    source: u8[..8],
    note_at: i64,           // in text, or -1 for null
    note_len: i64,
    created: i64,
    updated: i64,
}

struct Shift { staff: i64, start: i64, end: i64, kind: u8[..8], room: i64, note: u8[..64] }

var staff: Staff[>..];
var services: Service[>..];
var clients: Client[>..];
var visits: Visit[>..];         // the history's, by client then start, then the bookings'
var history_visits: i64 = 0;
var notes: Note[>..];           // by visit, each visit's by kind
var text: u8[>..];
var bookings: Booking[>..];     // by start, then staff
var shifts: Shift[>..];         // by start, then staff
var line_count: i64 = 0;
var case_count: i64 = 0;

// Sentences of WORDS, about target bytes long and at most hi, onto text.
fn words_text(target: i64, hi: i64) {
    let start = text.len;
    while text.len - start < target {
        if text.len > start { text.push(' '); }
        for k in between(5, 16) {
            let w = pick(WORDS);
            // The word, a space before it, and the full stop must fit.
            if k > 0 && text.len - start + w.len + 2 > hi { break; }
            if k == 0 {
                text.push(if w[0] >= 'a' { w[0] - 32 } else { w[0] });
                text.append(w[1..]);
            } else {
                text.push(' ');
                text.append(w);
            }
        }
        text.push('.');
        if text.len - start + 8 > hi { break; }
    }
}

fn add_lines(lines: Line[..3]&) {
    for k in between(2, 3) {
        line_count++;
        lines.push(Line { id: line_count, service: between(0, services.len - 1) });
    }
}

// A note of lo to hi bytes, most of them short: the mean of a uniform length
// and a skewed one.
fn add_note(kind: i64, author: i64, at: i64, lo: i64, hi: i64) {
    let start = text.len;
    let span = hi - lo;
    words_text(lo + (between(0, span) + between(0, span) * between(0, span) / span) / 2, hi);
    notes.push(Note { kind: kind, author: author, at: at, text_at: start, text_len: text.len - start });
}

fn heavy_records() {
    for i in 10 {
        let s .= staff.push(Staff { .. });
        format(s.name, pick(GIVEN), " ", pick(FAMILY));
        s.title.append(TITLES[if i < 6 { i } else { between(0, 3) }]);
    }
    for name, i in SERVICES {
        let s .= services.push(Service { minutes: between(1, 4) * 15, price: between(20, 120) * 50, .. });
        format(s.code, "SV-", 101 + i);
        s.name.append(name);
    }
    for i in 1000 {
        let c .= clients.push(Client { .. });
        format(c.name, pick(GIVEN), " ", pick(FAMILY));
        format(c.code, "K-", 10000 + i * 7);
    }
}

fn add_codes(codes: u8[..8][..3]&) {
    for k in between(1, 3) { format(codes.push(""), ['M', 'R', 'S', 'G'][between(0, 3)], between(10, 99), ".", between(0, 9)); }
}

// Two years of visits for clients 1 to 100, 20 to 28 each, in cases of 2 to
// 12 visits, each with an intake and findings, most with a plan, and some
// with an internal note.
fn heavy_history() {
    for c in 100 {
        let n = between(20, 28);
        var days: i64[>..] = [];
        for k in n {
            var d = between(0, (WEEK0 - HISTORY0) / DAY - 3);
            while weekday(HISTORY0 / DAY + d) > 4 { d++; }
            days.push(d);
        }
        sort(days);
        let main = between(0, 9);
        var left = 0;
        for d, k in days {
            if left == 0 {
                case_count++;
                left = between(2, 12);
            }
            left--;
            let start = HISTORY0 + d * DAY + OPEN + between(0, 15) * SLOT;
            let who = if between(0, 4) == 0 { between(0, 9) } else { main };
            let v .= visits.push(Visit { client: c, staff: who, case_id: case_count, start: start, end: start + SLOT,
                                         first_note: notes.len, .. });
            v.status.append("completed");
            v.kind.append(if left == 0 || k == 0 { "assessment" } else { pick(KINDS) });
            let p = between(0, 99);
            v.priority.append(if p < 85 { "routine" } else if p < 97 { "soon" } else { "urgent" });
            add_lines(v.lines);
            add_codes(v.codes);
            add_note(0, who, start + between(1, 10) * MINUTE, 200, 2000);
            add_note(1, who, start + between(10, 25) * MINUTE, 200, 2000);
            if between(0, 9) < 7 { add_note(2, who, start + between(25, 40) * MINUTE, 200, 2000); }
            if between(0, 9) < 2 { add_note(3, between(0, 9), start + between(1, 48) * 60 * MINUTE, 200, 1200); }
            v.notes = notes.len - v.first_note;
        }
    }
    history_visits = visits.len;
}

// The four weeks' bookings: each 30-minute slot of each staff member's
// weekdays from 08:00 to 16:00, 85% of them booked, each with its visit.
fn heavy_schedule() {
    for w in 4 {
        for d in 5 {
            for slot in 16 {
                for s in 10 {
                    if between(0, 99) >= 85 { continue; }
                    let start = WEEK0 + (w * 7 + d) * DAY + OPEN + slot * SLOT;
                    let client = between(0, 999);
                    case_count++;
                    let v .= visits.push(Visit { client: client, staff: s, case_id: case_count, start: start,
                                                 end: start + SLOT, first_note: notes.len, .. });
                    let b .= bookings.push(Booking { start: start, staff: s, client: client, visit: visits.len - 1,
                                                     note_at: -1, .. });
                    let r = between(0, 99);
                    if start < TODAY {
                        let st = if r < 88 { "completed" } else if r < 93 { "no-show" } else { "cancelled" };
                        v.status.append(st);
                        b.status.append(st);
                    } else {
                        v.status.append("planned");
                        b.status.append(if r < 60 { "booked" } else { "confirmed" });
                    }
                    v.kind.append(if between(0, 4) == 0 { "assessment" } else { "treatment" });
                    v.priority.append(if between(0, 9) == 0 { "soon" } else { "routine" });
                    add_lines(v.lines);
                    for l in v.lines { b.lines.push(l); }
                    add_codes(v.codes);
                    if v.status == "completed" {
                        add_note(0, s, start + between(1, 10) * MINUTE, 200, 1200);
                        add_note(1, s, start + between(10, 25) * MINUTE, 200, 1200);
                        if between(0, 1) == 0 { add_note(2, s, start + between(25, 40) * MINUTE, 200, 1200); }
                    } else if v.status == "planned" && between(0, 9) < 4 {
                        add_note(0, s, start - between(1, 72) * 60 * MINUTE, 200, 600);
                    }
                    v.notes = notes.len - v.first_note;
                    b.created = start - between(1, 40) * DAY - between(0, 600) * MINUTE;
                    b.updated = b.created + between(0, (start - b.created) / MINUTE) * MINUTE;
                    b.source.append(["staff", "online", "phone", "recall"][between(0, 3)]);
                    let sms = between(0, 4) > 0;
                    let rm .= b.reminders.push(Reminder { at: b.created + between(1, 5) * MINUTE, .. });
                    rm.channel.append(if sms { "sms" } else { "email" });
                    rm.kind.append("confirmation");
                    rm.status.append(if between(0, 19) == 0 { "failed" } else { "delivered" });
                    for k, lead in [24, 2] {
                        if lead == 2 && between(0, 2) == 0 { continue; }
                        let at = start - lead * 60 * MINUTE;
                        let rr .= b.reminders.push(Reminder { at: at, .. });
                        rr.channel.append("sms");
                        rr.kind.append(if lead == 24 { "reminder-24h" } else { "reminder-2h" });
                        rr.status.append(if at >= TODAY { "scheduled" } else { "delivered" });
                    }
                    if between(0, 9) < 7 {
                        b.note_at = text.len;
                        words_text(between(60, 300), 300);
                        b.note_len = text.len - b.note_at;
                    }
                }
            }
        }
        for d in 5 {
            for s in 10 {
                let day = WEEK0 + (w * 7 + d) * DAY;
                let room = between(0, ROOMS.len - 1);
                if between(0, 1) == 0 {
                    shifts.push(Shift { staff: s, start: day + OPEN, end: day + OPEN + 16 * SLOT, room: room, .. })
                        .kind.append("clinic");
                } else {
                    shifts.push(Shift { staff: s, start: day + OPEN, end: day + OPEN + 8 * SLOT, room: room, .. })
                        .kind.append("clinic");
                    let sh .= shifts.push(Shift { staff: s, start: day + OPEN + 9 * SLOT, end: day + OPEN + 16 * SLOT,
                                                  room: between(0, ROOMS.len - 1), .. });
                    sh.kind.append(if between(0, 9) < 3 { "admin" } else { "clinic" });
                }
                if between(0, 6) == 0 {
                    let start = text.len;
                    words_text(between(10, 60), 60);
                    last(shifts).note.append(text[start..]);
                }
            }
        }
    }
    sort(shifts) { a, b => a.start < b.start || a.start == b.start && a.staff < b.staff };
}

fn staff_ref(out: u8[>..]&, s: i64, title: bool) {
    out.append("{\"id\":");
    format(out, s + 1);
    out.append(",\"name\":");
    json::format_string(out, staff[s].name);
    if title {
        out.append(",\"title\":");
        json::format_string(out, staff[s].title);
    }
    out.push('}');
}

fn client_ref(out: u8[>..]&, c: i64) {
    out.append("{\"id\":");
    format(out, c + 1);
    out.append(",\"name\":");
    json::format_string(out, clients[c].name);
    out.append(",\"code\":");
    json::format_string(out, clients[c].code);
    out.push('}');
}

fn lines_json(out: u8[>..]&, lines: Line[:]) {
    out.push('[');
    for l, k in lines {
        let s = services[l.service];
        if k > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, l.id);
        out.append(",\"code\":");
        json::format_string(out, s.code);
        out.append(",\"name\":");
        json::format_string(out, s.name);
        out.append(",\"minutes\":");
        format(out, s.minutes);
        out.append(",\"price\":");
        format(out, s.price);
        out.push('}');
    }
    out.push(']');
}

fn heavy_staff_json(out: u8[>..]&) {
    out.push('[');
    for s, i in staff {
        if i > 0 { out.push(','); }
        staff_ref(out, i, true);
    }
    out.push(']');
}

fn heavy_services_json(out: u8[>..]&) {
    out.push('[');
    for s, i in services {
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"code\":");
        json::format_string(out, s.code);
        out.append(",\"name\":");
        json::format_string(out, s.name);
        out.append(",\"minutes\":");
        format(out, s.minutes);
        out.append(",\"price\":");
        format(out, s.price);
        out.push('}');
    }
    out.push(']');
}

fn heavy_clients_json(out: u8[>..]&) {
    out.push('[');
    for c, i in clients {
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"name\":");
        json::format_string(out, c.name);
        out.append(",\"code\":");
        json::format_string(out, c.code);
        out.append(",\"born\":\"");
        format_date(out, (HISTORY0 / DAY) - between(18 * 365, 85 * 365));
        out.append("\",\"phone\":\"+372 5");
        digits(out, between(0, 9999999), 7);
        out.append("\",\"email\":");
        json::format_string(out, str("client", i + 1, "@mail.example.com"));
        out.append(",\"address\":{\"street\":");
        json::format_string(out, str(pick(STREETS), " ", between(1, 120)));
        out.append(",\"city\":");
        json::format_string(out, pick(CITIES));
        out.append(",\"postcode\":\"");
        digits(out, between(10000, 99999), 5);
        out.append("\"},\"preferences\":{\"channel\":");
        let ch = between(0, 9);
        json::format_string(out, if ch < 6 { "sms" } else if ch < 9 { "email" } else { "none" });
        out.append(",\"language\":");
        let lang = between(0, 9);
        json::format_string(out, if lang < 6 { "et" } else if lang < 8 { "ru" } else { "en" });
        out.append("},\"flags\":[");
        var used: u64 = 0;
        for k in between(0, 2) {
            let f = between(0, FLAGS.len - 1);
            if (used >> f) & 1 != 0 { continue; }
            if used != 0 { out.push(','); }
            used |= 1 << f;
            json::format_string(out, FLAGS[f]);
        }
        out.append("],\"emergencyContact\":{\"name\":");
        json::format_string(out, str(pick(GIVEN), " ", pick(FAMILY)));
        out.append(",\"phone\":\"+372 5");
        digits(out, between(0, 9999999), 7);
        out.append("\",\"relation\":");
        json::format_string(out, ["spouse", "parent", "child", "sibling", "friend"][between(0, 4)]);
        out.append("},\"consents\":{\"sms\":");
        json::format_bool(out, between(0, 9) > 1);
        out.append(",\"email\":");
        json::format_bool(out, between(0, 9) > 3);
        out.append(",\"research\":");
        json::format_bool(out, between(0, 9) > 6);
        let created = HISTORY0 - between(0, 900) * DAY - between(0, 1439) * MINUTE;
        out.append("},\"createdAt\":");
        iso_or_null(out, created);
        out.append(",\"updatedAt\":");
        iso_or_null(out, created + between(0, 700) * DAY);
        out.push('}');
    }
    out.push(']');
}

fn heavy_bookings_json(out: u8[>..]&) {
    out.push('[');
    for b, i in bookings {
        let v = visits[b.visit];
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"slot\":{\"start\":");
        iso_or_null(out, b.start);
        out.append(",\"end\":");
        iso_or_null(out, b.start + SLOT);
        out.append("},\"client\":");
        client_ref(out, b.client);
        out.append(",\"staff\":");
        staff_ref(out, b.staff, false);
        out.append(",\"encounter\":{\"id\":");
        format(out, b.visit + 1);
        out.append(",\"status\":");
        json::format_string(out, v.status);
        out.append(",\"start\":");
        iso_or_null(out, v.start);
        out.append(",\"end\":");
        iso_or_null(out, v.end);
        out.append("},\"items\":");
        lines_json(out, b.lines);
        out.append(",\"reminders\":[");
        for rm, k in b.reminders {
            if k > 0 { out.push(','); }
            out.append("{\"channel\":");
            json::format_string(out, rm.channel);
            out.append(",\"kind\":");
            json::format_string(out, rm.kind);
            out.append(",\"status\":");
            json::format_string(out, rm.status);
            out.append(",\"at\":");
            iso_or_null(out, rm.at);
            out.push('}');
        }
        out.append("],\"status\":");
        json::format_string(out, b.status);
        out.append(",\"source\":");
        json::format_string(out, b.source);
        out.append(",\"note\":");
        if b.note_at < 0 { out.append("null"); } else { json::format_string(out, text[b.note_at..b.note_at + b.note_len]); }
        out.append(",\"createdAt\":");
        iso_or_null(out, b.created);
        out.append(",\"updatedAt\":");
        iso_or_null(out, b.updated);
        out.push('}');
    }
    out.push(']');
}

fn heavy_shifts_json(out: u8[>..]&) {
    out.push('[');
    for s, i in shifts {
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"staff\":");
        staff_ref(out, s.staff, false);
        out.append(",\"start\":");
        iso_or_null(out, s.start);
        out.append(",\"end\":");
        iso_or_null(out, s.end);
        out.append(",\"kind\":");
        json::format_string(out, s.kind);
        out.append(",\"room\":{\"id\":");
        format(out, s.room + 1);
        out.append(",\"name\":");
        json::format_string(out, ROOMS[s.room]);
        out.append("},\"note\":");
        string_or_null(out, s.note);
        out.push('}');
    }
    out.push(']');
}

fn heavy_encounters_json(out: u8[>..]&) {
    out.push('[');
    for v, i in visits {
        if i > 0 { out.push(','); }
        out.append("{\"id\":");
        format(out, i + 1);
        out.append(",\"caseId\":");
        format(out, v.case_id);
        out.append(",\"client\":");
        client_ref(out, v.client);
        out.append(",\"staff\":");
        staff_ref(out, v.staff, true);
        out.append(",\"status\":");
        json::format_string(out, v.status);
        out.append(",\"kind\":");
        json::format_string(out, v.kind);
        out.append(",\"priority\":");
        json::format_string(out, v.priority);
        out.append(",\"start\":");
        iso_or_null(out, v.start);
        out.append(",\"end\":");
        iso_or_null(out, v.end);
        out.append(",\"items\":");
        lines_json(out, v.lines);
        out.append(",\"codes\":[");
        for c, k in v.codes {
            if k > 0 { out.push(','); }
            json::format_string(out, c);
        }
        out.append("],\"notes\":{");
        for kind, k in NOTE_KINDS {
            if k > 0 { out.push(','); }
            json::format_string(out, kind);
            out.append(":[");
            var n = 0;
            for j in v.first_note..v.first_note + v.notes {
                let note = notes[j];
                if note.kind != k { continue; }
                if n > 0 { out.push(','); }
                n++;
                out.append("{\"id\":");
                format(out, j + 1);
                out.append(",\"author\":");
                staff_ref(out, note.author, true);
                out.append(",\"text\":");
                json::format_string(out, text[note.text_at..note.text_at + note.text_len]);
                out.append(",\"at\":");
                iso_or_null(out, note.at);
                out.push('}');
            }
            out.push(']');
        }
        out.append("}}");
    }
    out.push(']');
}

fn base64url(out: u8[>..]&, data: const u8[:]) {
    var b: u8[>..] = [];
    base64::encode(b, data);
    for c in b {
        if c == '+' { out.push('-'); }
        else if c == '/' { out.push('_'); }
        else if c != '=' { out.push(c); }
    }
}

// A bearer token for staff member s: a JWT signed with ES512 in form, its
// signature 132 random bytes, as long as a P-521 signature's.
fn token(out: u8[>..]&, s: i64) {
    base64url(out, "{\"alg\":\"ES512\",\"typ\":\"JWT\"}");
    out.push('.');
    var id: u8[..36] = "";
    uuid(id, VERSION0 + s * MINUTE);
    var claims: u8[>..] = [];
    format(claims, "{\"sub\":\"staff:", 4100 + s, "\",\"uid\":\"", id, "\",\"name\":");
    json::format_string(claims, staff[s].name);
    format(claims, ",\"org\":{\"id\":1207,\"unit\":\"north-", 1 + s % 3,
           "\"},\"auth\":{\"roles\":[\"clinician\",\"scheduler\"]}",
           ",\"scope\":\"schedule:rw records:r clients:r\",\"env\":\"bench\",\"tid\":\"clinic-north\"",
           ",\"exp\":1823299200}");
    base64url(out, claims);
    out.push('.');
    var sig: u8[>..] = [];
    for k in 132 { sig.push((next() & 0xFF) as u8); }
    base64url(out, sig);
}

fn heavy_load(out: u8[>..]&) {
    for s in 10 {
        out.append("token\t");
        token(out, s);
        out.push('\n');
    }
    for w in 4 {
        out.append("week\t");
        format_date(out, WEEK0 / DAY + w * 7);
        out.push('\t');
        format_date(out, WEEK0 / DAY + w * 7 + 7);
        out.push('\n');
    }
    out.append("month\t");
    format_date(out, WEEK0 / DAY);
    out.push('\t');
    format_date(out, WEEK0 / DAY + 28);
    out.push('\n');
    format(out, "encounters\t1\t", history_visits, "\n");
    format(out, "history\t1\t100\n");
    format(out, "clients\t1\t", clients.len, "\n");
    format(out, "version0\t", VERSION0, "\n");
}

fn write(dir: const u8[:], name: const u8[:], data: const u8[:]) {
    let path = str(dir, "/", name);
    guard write_file(path, data) else { abort(str("can't write ", path)); }
    print(path, ": ", data.len, " bytes");
}

fn main() {
    let argv = args();
    guard argv.len == 2 else { abort("usage: gen OUTDIR"); }
    let dir = argv[1];
    make_dir(dir);
    var out: u8[>..] = [];
    arena_items(out);
    write(dir, "arena-items.json", out);
    out.clear();
    arena_users(out);
    write(dir, "arena-users.json", out);

    seed = 0x5EED0000000000B;
    snow_orgs();
    snow_people();
    snow_entries();
    out.clear();
    snow_users_json(out);
    write(dir, "snow-users.json", out);
    out.clear();
    snow_orgs_json(out);
    write(dir, "snow-orgs.json", out);
    out.clear();
    snow_entries_json(out);
    write(dir, "snow-entries.json", out);
    out.clear();
    snow_load(out);
    write(dir, "snow-load.txt", out);

    seed = 0x5EED0000000000C;
    heavy_records();
    heavy_history();
    heavy_schedule();
    out.clear();
    heavy_staff_json(out);
    write(dir, "heavy-staff.json", out);
    out.clear();
    heavy_services_json(out);
    write(dir, "heavy-services.json", out);
    out.clear();
    heavy_clients_json(out);
    write(dir, "heavy-clients.json", out);
    out.clear();
    heavy_bookings_json(out);
    write(dir, "heavy-bookings.json", out);
    out.clear();
    heavy_shifts_json(out);
    write(dir, "heavy-shifts.json", out);
    out.clear();
    heavy_encounters_json(out);
    write(dir, "heavy-encounters.json", out);
    out.clear();
    format(out, "{\"versionEpoch\":", VERSION0, ",\"versionMs\":60000}");
    write(dir, "heavy-meta.json", out);
    out.clear();
    heavy_load(out);
    write(dir, "heavy-load.txt", out);
}
