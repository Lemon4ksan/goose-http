// The REST benchmark's datasets (task 021), written as JSON files that every
// server loads at startup and the checker compares responses with. The same
// seed writes the same files on every platform.
//
//   goose build -o build/rest/gen bench/rest/gen.goose && build/rest/gen OUTDIR
//
// Tier A, HttpArena's production-stack: arena-items.json, 10,000 items as
// HttpArena's dataset.json has them, and arena-users.json, 1,000 users.
import std;
import os;
import json;

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
}
