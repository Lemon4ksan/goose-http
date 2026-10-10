// HTTP/1.1 on bytes alone: the request parser, the Date header, and the
// responses. Nothing here makes a system call, so src/test_http.goose runs it
// through TinyCC without the shim.
namespace http;

import std;

// The longest request head (the request line, the header fields, and the
// blank line). The server's read buffer is this size, so a head always fits
// whole; one that doesn't is refused with 431.
let MAX_HEAD = 8192;
// Longer request lines are refused with 414, longer methods with 400.
let MAX_LINE = 4096;
let MAX_METHOD = 16;
// More header fields than this are refused with 431.
let MAX_FIELDS = 100;
// A Content-Length body longer than this is refused with 413. Bodies are read
// and dropped as they arrive, except for a route that reads its body
// (reads_body) and a chunked body: those must fit in the read buffer with the
// head, or they are refused with 413 too.
let MAX_BODY = 1048576;
// More than respond or refuse ever writes for one request.
let MAX_RESPONSE = 512;

// parse's status for a buffer that holds only the start of a request.
let INCOMPLETE = 0;

// Where find_any stops a field value: a byte below ' ', DEL, or above. Being
// the complement of one range, the set is searched 16 bytes at a time
// (docs/stdlib.md, "Byte sets"); parse's byte loop then takes a tab or
// obs-text and goes on.
let VALUE_END = value_end_set();

fn value_end_set() -> ByteSet {
    var m = [false; 256];
    for i in 256 { m[i] = i < 32 || i >= 127; }
    return byte_set(m);
}

// Where find_any stops a request target: a byte that isn't visible ASCII.
let TARGET_END = target_end_set();

fn target_end_set() -> ByteSet {
    var m = [false; 256];
    for i in 256 { m[i] = i <= 32 || i >= 127; }
    return byte_set(m);
}

// A parsed request head. The slices point into the buffer it was parsed from.
struct Request {
    method: const u8[:],
    target: const u8[:],     // as sent: the path and any query
    minor: i32,              // the x of HTTP/1.x
    keep_alive: bool,
    body: i64,               // Content-Length, 0 without one
    chunked: bool,           // Transfer-Encoding: chunked
    len: i64,                // bytes of the head, the blank line included
}

// Parses the request head at the start of buf. Returns the request and 200
// once the whole head is there, INCOMPLETE until then, or the status to
// refuse it with. Lines end in CRLF only: a bare LF is 400, which
// RFC 9112 §2.2 allows.
fn parse(buf: const u8[:]) -> Request, i32 {
    // Empty lines before the request line are skipped (RFC 9112 §2.2).
    var pos = 0;
    while pos < buf.len && buf[pos] == '\r' {
        guard pos + 1 < buf.len else { return Request { .. }, short(buf); }
        guard buf[pos + 1] == '\n' else { return Request { .. }, 400; }
        pos += 2;
    }

    // The method, a token, and one space.
    let m0 = pos;
    while pos < buf.len && is_tchar(buf[pos]) { pos++; }
    guard pos - m0 <= MAX_METHOD else { return Request { .. }, 400; }
    guard pos < buf.len else { return Request { .. }, short(buf); }
    guard pos > m0 && buf[pos] == ' ' else { return Request { .. }, 400; }
    let method = buf[m0..pos];
    pos++;

    // The target, visible ASCII, and one space.
    let t0 = pos;
    let kt = find_any(buf[pos..], TARGET_END);
    if kt > 0 && kt <= buf.len - pos { pos = pos + kt; }
    while pos < buf.len && buf[pos] > ' ' && buf[pos] < 0x7f { pos++; }
    guard pos - m0 <= MAX_LINE else { return Request { .. }, 414; }
    guard pos < buf.len else { return Request { .. }, short(buf); }
    guard pos > t0 && buf[pos] == ' ' else { return Request { .. }, 400; }
    let target = buf[t0..pos];
    pos++;

    // The version, HTTP/d.d, and CRLF: ten bytes. Waiting for them would
    // hang a client that ended the line early, so a line end is checked first.
    let rest = buf[pos..];
    if rest.len < 10 {
        guard position(rest, '\n') < 0 else { return Request { .. }, 400; }
        return Request { .. }, short(buf);
    }
    guard rest[..5] == "HTTP/" && is_digit(rest[5]) && rest[6] == '.' && is_digit(rest[7]) else {
        return Request { .. }, 400;
    }
    guard rest[5] == '1' else { return Request { .. }, 505; }
    guard rest[8] == '\r' && rest[9] == '\n' else { return Request { .. }, 400; }
    let minor: i32 = rest[7] - '0';
    pos += 10;

    // The header fields, up to the blank line.
    var r = Request { method: method, target: target, minor: minor, .. };
    var fields = 0;
    var hosts = 0;
    var has_length = false;
    var close = false;
    var keep = false;
    loop {
        guard pos < buf.len else { return Request { .. }, short(buf); }
        if buf[pos] == '\r' {
            guard pos + 1 < buf.len else { return Request { .. }, short(buf); }
            guard buf[pos + 1] == '\n' else { return Request { .. }, 400; }
            pos += 2;
            break;
        }
        fields++;
        guard fields <= MAX_FIELDS else { return Request { .. }, 431; }

        // The name, a token, and a colon right after it. This refuses
        // whitespace before the colon and obsolete line folding (§5.1, §5.2).
        let n0 = pos;
        let kn = find_any(buf[pos..], NAME_END);
        if kn > 0 && kn <= buf.len - pos { pos = pos + kn; }
        while pos < buf.len && is_tchar(buf[pos]) { pos++; }
        guard pos < buf.len else { return Request { .. }, short(buf); }
        guard pos > n0 && buf[pos] == ':' else { return Request { .. }, 400; }
        let name = buf[n0..pos];
        pos++;

        // The value, without the whitespace around it. Control bytes other
        // than tab aren't allowed in it.
        while pos < buf.len && (buf[pos] == ' ' || buf[pos] == '\t') { pos++; }
        let v0 = pos;
        // Values are most of a request's bytes, so find_any skips to the
        // first byte of VALUE_END. The guard on k is what lets the
        // bounds-check analysis keep pos proven; pos += k alone would lose
        // every check on pos in parse (docs/goose-findings.md).
        let k = find_any(buf[pos..], VALUE_END);
        if k > 0 && k <= buf.len - pos { pos = pos + k; }
        while pos < buf.len && ((buf[pos] >= ' ' && buf[pos] != 0x7f) || buf[pos] == '\t') { pos++; }
        guard pos < buf.len else { return Request { .. }, short(buf); }
        guard buf[pos] == '\r' else { return Request { .. }, 400; }
        guard pos + 1 < buf.len else { return Request { .. }, short(buf); }
        guard buf[pos + 1] == '\n' else { return Request { .. }, 400; }
        var v1 = pos;
        while v1 > v0 && (buf[v1 - 1] == ' ' || buf[v1 - 1] == '\t') { v1--; }
        let value = buf[v0..v1];
        pos += 2;

        if eq_fold(name, "content-length") {
            guard value.len > 0 && value.len <= 18 else { return Request { .. }, 400; }
            var n = 0;
            for c in value {
                guard is_digit(c) else { return Request { .. }, 400; }
                n = n * 10 + (c - '0');
            }
            guard !has_length || n == r.body else { return Request { .. }, 400; }
            guard n <= MAX_BODY else { return Request { .. }, 413; }
            has_length = true;
            r.body = n;
        } else if eq_fold(name, "transfer-encoding") {
            // Chunked alone, in HTTP/1.1 (RFC 9112 §6.1). Other codings
            // aren't implemented.
            guard eq_fold(value, "chunked") else { return Request { .. }, 501; }
            guard minor > 0 && !r.chunked else { return Request { .. }, 400; }
            r.chunked = true;
        } else if eq_fold(name, "connection") {
            // A single option, as clients almost always send, skips the split.
            if eq_fold(value, "keep-alive") { keep = true; }
            else if eq_fold(value, "close") { close = true; }
            else {
                each_split(value, ',') {
                    let opt = trim(it);
                    if eq_fold(opt, "close") { close = true; }
                    else if eq_fold(opt, "keep-alive") { keep = true; }
                };
            }
        } else if eq_fold(name, "host") {
            hosts++;
        }
    }
    // HTTP/1.1 requires exactly one Host (RFC 9112 §3.2).
    guard hosts == 1 || (hosts == 0 && minor == 0) else { return Request { .. }, 400; }
    // Both framings at once are refused, as §6.3 allows, so that no two
    // parsers on the way can disagree on where the message ends.
    guard !(r.chunked && has_length) else { return Request { .. }, 400; }
    r.keep_alive = !close && (minor > 0 || keep);
    r.len = pos;
    return r, 200;
}

// The status for a head that has only partly arrived: wait for the rest,
// unless it can't fit.
fn short(buf: const u8[:]) -> i32 {
    if buf.len >= MAX_HEAD { 431 } else { INCOMPLETE }
}

fn is_digit(c: u8) -> bool { c >= '0' && c <= '9' }

fn is_hex(c: u8) -> bool { is_digit(c) || (c | 32) >= 'a' && (c | 32) <= 'f' }

// Whether the route reads the request's body, which the server then holds
// whole in its buffer before answering.
fn reads_body(req: Request) -> bool {
    req.method == "POST" && path_of(req.target) == "/baseline11"
}

// Frames the body of req at the start of rest, the bytes after its head,
// where a buffer of room bytes after the head must hold it whole. Returns the
// body's length on the wire and 200 once it has all arrived, INCOMPLETE until
// then, or the status to refuse the request with.
fn frame_body(rest: const u8[:], req: Request, room: i64) -> i64, i32 {
    if req.chunked {
        let n, status = chunked_len(rest);
        if status == INCOMPLETE && rest.len >= room { return 0, 413; }
        return n, status;
    }
    guard req.body <= room else { return 0, 413; }
    if rest.len < req.body { return 0, INCOMPLETE; }
    return req.body, 200;
}

// Measures the chunked body at the start of buf (RFC 9112 §7.1): its length on
// the wire and 200, INCOMPLETE, or 400. Chunk extensions and trailer fields
// are allowed and skipped.
fn chunked_len(buf: const u8[:]) -> i64, i32 {
    var pos = 0;
    loop {
        let s0 = pos;
        while pos < buf.len && is_hex(buf[pos]) { pos++; }
        guard pos - s0 <= 15 else { return 0, 400; }
        guard pos < buf.len else { return 0, INCOMPLETE; }
        guard pos > s0 && (buf[pos] == ';' || buf[pos] == '\r') else { return 0, 400; }
        let size, ok = parse_int(buf[s0..pos], 16);
        let e = line_end(buf, pos);
        guard e > 0 else { return 0, if e == 0 { INCOMPLETE } else { 400 }; }
        pos = e;
        if size == 0 {
            // Trailer fields, then the blank line.
            loop {
                guard pos < buf.len else { return 0, INCOMPLETE; }
                if buf[pos] == '\r' {
                    guard pos + 1 < buf.len else { return 0, INCOMPLETE; }
                    guard buf[pos + 1] == '\n' else { return 0, 400; }
                    return pos + 2, 200;
                }
                let t = line_end(buf, pos);
                guard t > 0 else { return 0, if t == 0 { INCOMPLETE } else { 400 }; }
                pos = t;
            }
        }
        guard buf.len - pos >= size + 2 else { return 0, INCOMPLETE; }
        pos += size;
        guard buf[pos] == '\r' && buf[pos + 1] == '\n' else { return 0, 400; }
        pos += 2;
    }
}

// The index after the CRLF that ends the line at pos, 0 if it hasn't arrived,
// or -1 if the line holds a control byte other than tab.
fn line_end(buf: const u8[:], pos: i64) -> i64 {
    var i = pos;
    while i < buf.len && ((buf[i] >= ' ' && buf[i] != 0x7f) || buf[i] == '\t') { i++; }
    if i + 1 >= buf.len { return if i < buf.len && buf[i] != '\r' { -1 } else { 0 }; }
    return if buf[i] == '\r' && buf[i + 1] == '\n' { i + 2 } else { -1 };
}

// Decodes, in place, a chunked body that chunked_len accepted: the data moves
// to the front of buf. Returns its length.
fn dechunk(buf: u8[:]) -> i64 {
    var pos = 0;
    var n = 0;
    loop {
        let s0 = pos;
        while is_hex(buf[pos]) { pos++; }
        let size, ok = parse_int(buf[s0..pos], 16);
        while buf[pos] != '\n' { pos++; }
        pos++;
        if size == 0 { return n; }
        copy_into(buf[n..n + size], buf[pos..pos + size]);
        n += size;
        pos += size + 2;
    }
}

// A token character (RFC 9110 §5.6.2): bit c of TCHAR_LO, or of TCHAR_HI
// for c from 64 to 127.
let TCHAR_LO: u64 = 0x03ff6cfa00000000;   // ! # $ % & ' * + - . 0-9
let TCHAR_HI: u64 = 0x57ffffffc7fffffe;   // A-Z ^ _ ` a-z | ~

fn is_tchar(c: u8) -> bool {
    let mask = if c < 64 { TCHAR_LO } else if c < 128 { TCHAR_HI } else { 0 };
    (mask >> (c & 63)) & 1 != 0
}

// Where find_any stops a field name: a byte that isn't a token character.
let NAME_END = name_end_set();

fn name_end_set() -> ByteSet {
    var m = [false; 256];
    for i in 256 { m[i] = !is_tchar(i as u8); }
    return byte_set(m);
}

// Whether a equals lower, ignoring the case of ASCII letters in a. lower
// must hold only lowercase letters and '-', and a no control bytes but tab:
// then c | 32 equals a byte of lower only where c does, ignoring case.
inline fn eq_fold(a: const u8[:], lower: const u8[:]) -> bool {
    guard a.len == lower.len else { return false; }
    for c, i in a {
        if c | 32 != lower[i] { return false; }
    }
    return true;
}

// The writers below take out as A&, a growable or limited u8 array. The
// server's write buffer is a limited array, a fixed-size value, so an untyped
// parameter would get a copy of it.

// The target without its query.
fn path_of(target: const u8[:]) -> const u8[:] {
    let q = position(target, '?');
    return if q >= 0 { target[..q] } else { target };
}

// Writes the response to req, whose body is body, into out, and returns
// whether the connection stays open after it. body is empty unless
// reads_body(req).
fn respond<A>(out: A&, req: Request, body: const u8[:], date: const u8[:]) -> bool {
    let path = path_of(req.target);
    let plaintext = path == "/plaintext";
    let json = path == "/json";
    // HttpArena's endpoints (bench/httparena).
    let baseline = path == "/baseline11";
    let pipeline = path == "/pipeline";
    let head_only = req.method == "HEAD";
    let get = head_only || req.method == "GET";
    if (plaintext || json || pipeline) && !get || baseline && !get && req.method != "POST" {
        start(out, 405, date, req.keep_alive, req.minor);
        out.append(if baseline { "Allow: GET, HEAD, POST\r\n" } else { "Allow: GET, HEAD\r\n" });
        finish(out, "Content-Length: ", "", false);
    } else if plaintext {
        start(out, 200, date, req.keep_alive, req.minor);
        finish(out, "Content-Type: text/plain\r\nContent-Length: ", "Hello, World!", head_only);
    } else if json {
        var body: u8[..64] = [];
        json_object(body, Message { message: "Hello, World!" });
        start(out, 200, date, req.keep_alive, req.minor);
        finish(out, "Content-Type: application/json\r\nContent-Length: ", body, head_only);
    } else if baseline {
        var sum = query_int(req.target, "a") + query_int(req.target, "b");
        if req.method == "POST" {
            let n, ok = parse_int(trim(body));
            if ok { sum += n; }
        }
        var text: u8[..24] = [];
        format(text, sum);
        start(out, 200, date, req.keep_alive, req.minor);
        finish(out, "Content-Type: text/plain\r\nContent-Length: ", text, head_only);
    } else if pipeline {
        start(out, 200, date, req.keep_alive, req.minor);
        finish(out, "Content-Type: text/plain\r\nContent-Length: ", "ok", head_only);
    } else {
        start(out, 404, date, req.keep_alive, req.minor);
        finish(out, "Content-Length: ", "", head_only);
    }
    return req.keep_alive;
}

// The integer value of key in target's query, or 0.
fn query_int(target: const u8[:], key: const u8[:]) -> i64 {
    let q = position(target, '?');
    guard q >= 0 else { return 0; }
    var v = 0;
    each_split(target[q + 1..], '&') {
        let eq = position(it, '=');
        if eq >= 0 && it[..eq] == key {
            let n, ok = parse_int(it[eq + 1..]);
            if ok { v = n; }
        }
    };
    return v;
}

// Writes the response that refuses a request with status. The connection
// closes after it.
fn refuse<A>(out: A&, status: i32, date: const u8[:]) {
    start(out, status, date, false, 1);
    finish(out, "Content-Length: ", "", false);
}

// The status line and the fields every response has.
fn start<A>(out: A&, status: i32, date: const u8[:], keep_alive: bool, minor: i32) {
    out.append(status_line(status));
    out.append(date);
    out.append(if !keep_alive { "\r\nConnection: close\r\n" }
               else if minor == 0 { "\r\nConnection: keep-alive\r\n" }
               else { "\r\n" });
}

// The body's fields, the blank line, and the body unless head_only. fields
// holds every field before the length's value, ending in "Content-Length: ",
// so that they take one append.
fn finish<A>(out: A&, fields: const u8[:], body: const u8[:], head_only: bool) {
    out.append(fields);
    format(out, body.len);
    out.append("\r\n\r\n");
    if !head_only { out.append(body); }
}

// The status line and the fields up to the Date field's value.
fn status_line(status: i32) -> const u8[:] {
    match status {
        200 => "HTTP/1.1 200 OK\r\nServer: goose\r\nDate: ",
        400 => "HTTP/1.1 400 Bad Request\r\nServer: goose\r\nDate: ",
        404 => "HTTP/1.1 404 Not Found\r\nServer: goose\r\nDate: ",
        405 => "HTTP/1.1 405 Method Not Allowed\r\nServer: goose\r\nDate: ",
        408 => "HTTP/1.1 408 Request Timeout\r\nServer: goose\r\nDate: ",
        413 => "HTTP/1.1 413 Content Too Large\r\nServer: goose\r\nDate: ",
        414 => "HTTP/1.1 414 URI Too Long\r\nServer: goose\r\nDate: ",
        431 => "HTTP/1.1 431 Request Header Fields Too Large\r\nServer: goose\r\nDate: ",
        501 => "HTTP/1.1 501 Not Implemented\r\nServer: goose\r\nDate: ",
        505 => "HTTP/1.1 505 HTTP Version Not Supported\r\nServer: goose\r\nDate: ",
        _ => "HTTP/1.1 500 Internal Server Error\r\nServer: goose\r\nDate: ",
    }
}

// The object /json serializes for each request, as TechEmpower's JSON test
// asks.
struct Message { message: const u8[:] }

fn json_object<A>(out: A&, m: Message) {
    out.append("{\"message\":");
    json_string(out, m.message);
    out.push('}');
}

fn json_string<A>(out: A&, s: const u8[:]) {
    out.push('"');
    for c in s {
        if c == '"' || c == '\\' {
            out.push('\\');
            out.push(c);
        } else if c < ' ' {
            out.append("\\u00");
            out.push("0123456789abcdef"[c >> 4]);
            out.push("0123456789abcdef"[c & 15]);
        } else {
            out.push(c);
        }
    }
    out.push('"');
}

// Appends t, in seconds since the epoch and not negative, as an HTTP date
// (RFC 9110 §5.6.7): "Sat, 10 Oct 2026 12:00:00 GMT", 29 bytes.
fn format_date<A>(out: A&, t: i64) {
    let days = t / 86400;
    let secs = t % 86400;
    // The civil date of a day count, by Howard Hinnant's days_from_civil
    // inverse: a 400-year era, then March-based years, so leap days fall last.
    let z = days + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + (if month <= 2 { 1 } else { 0 });

    // 1970-01-01 was a Thursday.
    let w = (days + 4) % 7 * 3;
    out.append("SunMonTueWedThuFriSat"[w..w + 3]);
    out.append(", ");
    two_digits(out, day);
    out.push(' ');
    let m = (month - 1) * 3;
    out.append("JanFebMarAprMayJunJulAugSepOctNovDec"[m..m + 3]);
    out.push(' ');
    two_digits(out, year / 100);
    two_digits(out, year % 100);
    out.push(' ');
    two_digits(out, secs / 3600);
    out.push(':');
    two_digits(out, secs / 60 % 60);
    out.push(':');
    two_digits(out, secs % 60);
    out.append(" GMT");
}

fn two_digits<A>(out: A&, v: i64) {
    out.push(('0' + v / 10) as u8);
    out.push(('0' + v % 10) as u8);
}
