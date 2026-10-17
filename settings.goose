// Files of settings, a line each: NAME = VALUE, with # comments, read by
// each_setting. A placement file (place.goose) is one, and so is a .env file
// for development, which env_load puts into the process's environment, where
// env reads it. In production, systemd's EnvironmentFile and Compose's
// env_file load one already.
//
// A # starts a comment at the start of a line, or after a space or tab
// outside quotes. env_load also takes `export NAME=VALUE`, and a value in
// double or single quotes, which keeps its spaces and # signs; double quotes
// read \n, \t, \", and \\ as their characters.
//
// The C is the shim's (shim/place.c), as Goose can read the environment but
// not change it. Nothing here knows HTTP.
namespace http;

import std;
import os;

extern "place_setenv" fn setenv_c(name: const u8[:], value: const u8[:]) -> i32;

// line with its comment cut off, if it has one outside quotes.
fn setting_text(line: const u8[:]) -> const u8[:] {
    var quote: u8 = 0;
    for c, i in line {
        if quote != 0 {
            if c == quote { quote = 0; }
        } else if c == '"' || c == '\'' {
            quote = c;
        } else if c == '#' && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t') {
            return line[..i];
        }
    }
    return line;
}

// Calls F with each setting of text: its line number from 1, the name, and the
// value, both trimmed, and true; or, for a line with no =, the line and an
// empty value, and false. Blank lines and comments are skipped.
fn each_setting<F>(text: const u8[:]) {
    var n = 0;
    each_split(text, '\n') {
        n++;
        let line = trim(setting_text(it));
        if line.len > 0 {
            let eq = find(line, "=");
            if eq >= 0 { F(n, trim(line[..eq]), trim(line[eq + 1..]), true); } else { F(n, line, "", false); }
        }
    };
}

// value as a .env file means it: unquoted, and with double quotes' escapes
// read. The bool is false for a quote that isn't closed.
fn env_value(value: const u8[:], out: u8[>..]&) -> bool {
    guard value.len > 0 && (value[0] == '"' || value[0] == '\'') else {
        out.append(value);
        return true;
    }
    let q = value[0];
    guard value.len >= 2 && value[value.len - 1] == q else { return false; }
    let inner = value[1..value.len - 1];
    guard q == '"' else {
        out.append(inner);
        return true;
    }
    var i = 0;
    while i < inner.len {
        let c = inner[i];
        if c == '\\' && i + 1 < inner.len {
            let e = inner[i + 1];
            out.push(if e == 'n' { '\n' } else if e == 't' { '\t' } else { e });
            i += 2;
        } else {
            out.push(c);
            i++;
        }
    }
    return true;
}

// Puts the settings of the .env file at path into the environment, but those
// it has already: the real environment wins, as in other .env loaders.
// Returns how many it set, and "" or the error, as "path:line: message"; a
// file that isn't there sets none and is no error, so that a deployment
// without one runs as it is.
fn env_load(path: const u8[:] = ".env") -> i64, u8[] {
    var text: u8[>..] = [];
    guard read_file(path, text) else { return 0, ""; }
    var set = 0;
    var err: u8[>..] = [];
    var value: u8[>..] = [];
    var had: u8[>..] = [];
    each_setting(text) { n, name, raw, eq =>
        if err.len == 0 {
            var key = name;
            if starts_with(key, "export ") { key = trim(key[7..]); }
            if !eq {
                format(err, path, ":", n, ": NAME=VALUE, not \"", name, "\"");
            } else if key.len == 0 || find(key, " ") >= 0 {
                format(err, path, ":", n, ": a name with no spaces, not \"", key, "\"");
            } else {
                value.clear();
                if !env_value(raw, value) {
                    format(err, path, ":", n, ": a quote that isn't closed");
                } else {
                    had.clear();
                    if !env(key, had) && setenv_c(key, value) == 0 { set++; }
                }
            }
        }
    };
    guard err.len == 0 else { return 0, err; }
    return set, "";
}
