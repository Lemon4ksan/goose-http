// Form bodies: a value of an application/x-www-form-urlencoded body, whose
// pairs message.goose's each_form gives, and the parts of
// multipart/form-data (RFC 7578) from a body that comes in pieces.
//
//   // At REQUEST:
//   guard http::start_multipart(req, st.parts) else { ... 400 or 415 ... }
//   // At REQUEST with its whole data, and at each BODY:
//   let ok = http::each_part(st.parts, ev.data) { kind, data =>
//       if kind == http::PART_HEAD { ... field_in(data, "content-disposition") ... }
//       else if kind == http::PART_DATA { ... }
//       else { ... PART_END ... }
//   };
//   // At END, the body is whole if http::multipart_done(st.parts).
namespace http;

import std;
import message;
import media;

// Decodes into out the value of the first pair of body whose key decodes to
// key, and returns whether body has one. A pair whose key or value has a bad
// escape is skipped.
fn form_value(body: const u8[:], key: const u8[:], out: u8[>..]&) -> bool {
    var found = false;
    var k: u8[>..] = [];
    each_form(body) { kraw, vraw =>
        if !found {
            k.clear();
            if decode(kraw, k, true) && k == key {
                out.clear();
                if decode(vraw, out, true) { found = true; } else { out.clear(); }
            }
        }
    };
    return found;
}

// What each_part calls its function for.
let PART_HEAD: u8 = 0;   // a part's header fields, lines each ending in CRLF, for field_in
let PART_DATA: u8 = 1;   // the next piece of the part's content
let PART_END: u8 = 2;    // the end of the part

// The most bytes of a part's header fields, past which each_part fails: what
// a Multipart holds between pieces.
let MAX_PART_HEAD = 2048;

// Where a multipart body is (Multipart.place).
let MP_PREAMBLE: u8 = 0;   // before the first delimiter
let MP_AFTER: u8 = 1;      // after a delimiter: "--" ends the body, CRLF starts a part
let MP_HEAD: u8 = 2;       // in a part's header fields
let MP_DATA: u8 = 3;       // in a part's content
let MP_DONE: u8 = 4;       // past the close delimiter: the epilogue is dropped
let MP_FAILED: u8 = 5;

// A multipart body read in pieces: where it is, and the bytes held from the
// last piece, the start of a head or what could start a delimiter. Flat, for
// a handler's state, which the loops keep in each connection's slot.
struct Multipart {
    delimiter: u8[..74] = [],   // CRLF, "--", and the boundary
    place: u8 = MP_FAILED,
    held: u8[..MAX_PART_HEAD] = [],
}

// Readies m for req's multipart/form-data body, with the boundary its
// Content-Type gives. False if req has no such type, or the boundary isn't
// 1 to 70 of RFC 2046 §5.1.1's characters.
fn start_multipart(req: Request, m: Multipart&) -> bool {
    m.place = MP_FAILED;
    m.delimiter.clear();
    let v, found = field_of(req, "content-type");
    let t, ok = media_type(v);
    let b, has = param_of(t, "boundary");
    guard found && ok && is_media(t, "multipart/form-data") && has && b.len >= 1 && b.len <= 70 &&
          b[b.len - 1] != ' ' else { return false; }
    for c in b {
        guard is_digit(c) || (c | 32) >= 'a' && (c | 32) <= 'z' || position("'()+_,-./:=? ", c) >= 0 else { return false; }
    }
    m.delimiter.append("\r\n--");
    m.delimiter.append(b);
    // The first delimiter has no CRLF before it: the body starts as if after
    // one.
    m.held.clear();
    m.held.append("\r\n");
    m.place = MP_PREAMBLE;
    return true;
}

// Whether m's body has ended with its close delimiter.
fn multipart_done(m: const Multipart&) -> bool { m.place == MP_DONE }

// Reads the next piece of m's body, calling F(kind, data) for each part's
// head, the pieces of its content, and its end, in order. data lasts until F
// returns. Returns false, and fails m for the rest of the body, when the
// body isn't multipart, as a delimiter not followed by CRLF or "--", or a
// part's head that isn't field lines or is longer than MAX_PART_HEAD.
fn each_part<F>(m: Multipart&, piece: const u8[:]) -> bool {
    guard m.place != MP_FAILED else { return false; }
    guard m.place != MP_DONE else { return true; }
    // The piece goes after what the last one left, joined only when
    // something was.
    guard m.held.len > 0 else { return read_parts(m, piece) { kind, data => F(kind, data); }; }
    var joined: u8[>..] = [];
    joined.append(m.held);
    joined.append(piece);
    m.held.clear();
    return read_parts(m, joined) { kind, data => F(kind, data); };
}

// each_part on work, the bytes held and the piece.
fn read_parts<F>(m: Multipart&, work: const u8[:]) -> bool {
    let d = m.delimiter;
    var at = 0;
    loop {
        if m.place == MP_PREAMBLE || m.place == MP_DATA {
            let k = find(work[at..], d);
            if k < 0 {
                // Hold back the longest end of work that could start a
                // delimiter.
                var keep = min(d.len - 1, work.len - at);
                while keep > 0 && work[work.len - keep..] != d[..keep] { keep--; }
                let data = work[at..work.len - keep];
                if m.place == MP_DATA && data.len > 0 { F(PART_DATA, data); }
                m.held.append(work[work.len - keep..]);
                return true;
            }
            if m.place == MP_DATA {
                if k > 0 { F(PART_DATA, work[at..at + k]); }
                F(PART_END, work[at..at]);
            }
            at += k + d.len;
            m.place = MP_AFTER;
        } else if m.place == MP_AFTER {
            // "--" ends the body; otherwise, after any spaces and tabs, a CRLF
            // starts a part.
            var p = at;
            if work.len - p < 2 { break; }
            if work[p] == '-' && work[p + 1] == '-' {
                m.place = MP_DONE;
                return true;
            }
            while p < work.len && (work[p] == ' ' || work[p] == '\t') { p++; }
            if p - at > 64 { return failed(m); }
            if work.len - p < 2 { break; }
            guard work[p] == '\r' && work[p + 1] == '\n' else { return failed(m); }
            at = p + 2;
            m.place = MP_HEAD;
        } else if m.place == MP_HEAD {
            // The head ends at a blank line, which is the first line when it
            // has no fields.
            var end = -1;
            if work.len - at >= 2 && work[at] == '\r' && work[at + 1] == '\n' {
                end = at;
            } else {
                let k = find(work[at..], "\r\n\r\n");
                if k >= 0 { end = at + k + 2; }
            }
            if end < 0 {
                if work.len - at > MAX_PART_HEAD { return failed(m); }
                break;
            }
            guard end - at <= MAX_PART_HEAD && field_lines(work[at..end]) else { return failed(m); }
            F(PART_HEAD, work[at..end]);
            at = end + 2;
            m.place = MP_DATA;
        } else {
            return true;
        }
    }
    m.held.append(work[at..]);
    return true;
}

fn failed(m: Multipart&) -> bool {
    m.place = MP_FAILED;
    m.held.clear();
    return false;
}

// Whether lines are field lines, each ending in CRLF, that field_in can read:
// a token, ':', and a value is_field_value takes once trimmed.
fn field_lines(lines: const u8[:]) -> bool {
    var pos = 0;
    while pos < lines.len {
        let rest = lines[pos..];
        let e = find(rest, "\r\n");
        guard e >= 0 else { return false; }
        let colon = position(rest[..e], ':');
        guard colon > 0 && is_field(rest[..colon], trim_ows(rest[colon + 1..e])) else { return false; }
        pos += e + 2;
    }
    return true;
}

// The name and filename parameters of a part's Content-Disposition (RFC
// 7578 §4.2), as each_param gives them, and whether its type is form-data.
// filename is "" without one.
fn disposition(fields: const u8[:]) -> const u8[:], const u8[:], bool {
    let v, found = field_in(fields, "content-disposition");
    var name = v[..0];
    var filename = v[..0];
    guard found else { return name, filename, false; }
    var e = 0;
    while e < v.len && is_tchar(v[e]) { e++; }
    guard eq_fold(v[..e], "form-data") else { return name, filename, false; }
    let ok = each_param(v[e..]) { n, value =>
        if same_name(n, "name") { name = value; }
        else if same_name(n, "filename") { filename = value; }
    };
    return name, filename, ok;
}
