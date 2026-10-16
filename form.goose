// Form bodies: a value of an application/x-www-form-urlencoded body, whose
// pairs message.goose's each_form gives, and the parts of
// multipart/form-data (RFC 7578) from a body that comes in pieces.
//
//   // At REQUEST:
//   guard http::start_multipart(req, st.parts) else { ... 400 or 415 ... }
//   // At REQUEST with its whole data, and at each BODY:
//   let ok = http::each_part(st.parts, ev.data) { part =>
//       match part {
//           Head h => { ... field_in(h.fields, "content-disposition") ... },
//           Data d => { ... d.bytes ... },
//           End => { ... },
//       }
//   };
//   // At END, the body is whole if http::multipart_done(st.parts).
//
//   // Or, for a body already whole, one part as slices of it:
//   let v, fields, status = http::find_part(req, body, "name");
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

// What each_part calls its function with: a part's header fields, lines each
// ending in CRLF, for field_in; the next piece of the part's content; or the
// end of the part.
enum Part {
    Head { fields: const u8[:] },
    Data { bytes: const u8[:] },
    End,
}

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
fn start_multipart(req: const Request&, m: Multipart&) -> bool {
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

// Reads the next piece of m's body, calling F(part) for each part's head, the
// pieces of its content, and its end, in order. A part's bytes last until F
// returns. Returns false, and fails m for the rest of the body, when the
// body isn't multipart, as a delimiter not followed by CRLF or "--", or a
// part's head that isn't field lines or is longer than MAX_PART_HEAD, or
// when F calls fail_multipart.
fn each_part<F>(m: Multipart&, piece: const u8[:]) -> bool {
    guard m.place != MP_FAILED else { return false; }
    guard m.place != MP_DONE else { return true; }
    // The piece goes after what the last one left, joined only when
    // something was.
    guard m.held.len > 0 else { return read_parts(m, piece) { part => F(part); }; }
    var joined: u8[>..] = [];
    joined.append(m.held);
    joined.append(piece);
    m.held.clear();
    return read_parts(m, joined) { part => F(part); };
}

// The first i where sub starts in xs, -1 if none; sub isn't empty. This
// compares only where sub's first byte is. With the stdlib's find in its
// place, tier D's forms ran 2-3% slower at Goose 46356c2, at the same
// instructions a request.
fn find_bytes(xs: const u8[:], sub: const u8[:]) -> i64 {
    let first = sub[0];
    let last = xs.len - sub.len;
    var i = 0;
    while i <= last {
        if xs[i] == first && xs[i..i + sub.len] == sub { return i; }
        i++;
    }
    return -1;
}

// each_part on work, the bytes held and the piece.
fn read_parts<F>(m: Multipart&, work: const u8[:]) -> bool {
    let d = m.delimiter;
    var at = 0;
    loop {
        if m.place == MP_PREAMBLE || m.place == MP_DATA {
            let k = find_bytes(work[at..], d);
            if k < 0 {
                // Hold back the longest end of work that could start a
                // delimiter.
                var keep = min(d.len - 1, work.len - at);
                while keep > 0 && work[work.len - keep..] != d[..keep] { keep--; }
                let data = work[at..work.len - keep];
                if m.place == MP_DATA && data.len > 0 {
                    let p: Part = Part.Data { bytes: data };
                    F(p);
                    guard m.place != MP_FAILED else { return failed(m); }
                }
                m.held.append(work[work.len - keep..]);
                return true;
            }
            if m.place == MP_DATA {
                if k > 0 {
                    let p: Part = Part.Data { bytes: work[at..at + k] };
                    F(p);
                    guard m.place != MP_FAILED else { return failed(m); }
                }
                let end: Part = Part.End;
                F(end);
                guard m.place != MP_FAILED else { return failed(m); }
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
            let end = head_end(work, at);
            if end < 0 {
                if work.len - at > MAX_PART_HEAD { return failed(m); }
                break;
            }
            guard end - at <= MAX_PART_HEAD && field_lines(work[at..end]) else { return failed(m); }
            let head: Part = Part.Head { fields: work[at..end] };
            F(head);
            guard m.place != MP_FAILED else { return failed(m); }
            at = end + 2;
            m.place = MP_DATA;
        } else {
            return true;
        }
    }
    m.held.append(work[at..]);
    return true;
}

// Where the head that starts at work[at] ends, after its last field line's
// CRLF, or -1 if its blank line isn't in work. The head ends at a blank line,
// which is the first line when it has no fields.
fn head_end(work: const u8[:], at: i64) -> i64 {
    if work.len - at >= 2 && work[at] == '\r' && work[at + 1] == '\n' { return at; }
    let k = find_bytes(work[at..], "\r\n\r\n");
    if k >= 0 { return at + k + 2; }
    return -1;
}

fn failed(m: Multipart&) -> bool {
    fail_multipart(m);
    return false;
}

// Fails m as each_part fails a body that isn't multipart, for a check of the
// program's own, such as of a part's head. Called from each_part's function,
// each_part calls it no more and returns false. Every later each_part returns
// false, and multipart_done too.
fn fail_multipart(m: Multipart&) {
    m.place = MP_FAILED;
    m.held.clear();
}

// Whether lines are field lines, each ending in CRLF, that field_in can read:
// a token, ':', and a value is_field_value takes once trimmed.
fn field_lines(lines: const u8[:]) -> bool {
    var pos = 0;
    while pos < lines.len {
        let rest = lines[pos..];
        let e = find_bytes(rest, "\r\n");
        guard e >= 0 else { return false; }
        let colon = position(rest[..e], ':');
        guard colon > 0 && is_field(rest[..colon], trim_ows(rest[colon + 1..e])) else { return false; }
        pos += e + 2;
    }
    return true;
}

// find_part's statuses.
let PART_FOUND = 0;
let PART_ABSENT = 1;   // a whole multipart body without that name
let PART_TYPE = 2;     // not multipart/form-data, or no usable boundary
let PART_BAD = 3;      // a body each_part would fail, a part without a
                       // form-data Content-Disposition, or one never closed

// The first part of the whole multipart/form-data body that req announces whose
// Content-Disposition name is name: its content, its header fields for
// disposition and field_in, and a PART_ status. Both are slices of body, which
// each_part can't give for a whole body, since it joins the first piece to the
// bytes it holds. The rules are each_part's: start_multipart's boundary check,
// the same delimiters and head limits, and a part's head checked by
// field_lines. Parts after the one found aren't read, so damage past it goes
// unseen; one before it is PART_BAD. Content and fields are empty unless found.
fn find_part(req: const Request&, body: const u8[:], name: const u8[:]) -> const u8[:], const u8[:], i64 {
    let none = body[..0];
    var m = Multipart { .. };
    guard start_multipart(req, m) else { return none, none, PART_TYPE; }
    let d = m.delimiter;
    // The first delimiter has no CRLF before it.
    var at = 0;
    if body.len >= d.len - 2 && body[..d.len - 2] == d[2..] {
        at = d.len - 2;
    } else {
        let k = find_bytes(body, d);
        guard k >= 0 else { return none, none, PART_BAD; }
        at = k + d.len;
    }
    loop {
        guard body.len - at >= 2 else { return none, none, PART_BAD; }
        if body[at] == '-' && body[at + 1] == '-' { return none, none, PART_ABSENT; }
        var p = at;
        while p < body.len && (body[p] == ' ' || body[p] == '\t') { p++; }
        guard p - at <= 64 && body.len - p >= 2 && body[p] == '\r' && body[p + 1] == '\n' else {
            return none, none, PART_BAD;
        }
        at = p + 2;
        let end = head_end(body, at);
        guard end >= 0 && end - at <= MAX_PART_HEAD && field_lines(body[at..end]) else {
            return none, none, PART_BAD;
        }
        let fields = body[at..end];
        let start = end + 2;
        let k = find_bytes(body[start..], d);
        guard k >= 0 else { return none, none, PART_BAD; }
        let n, filename, ok = disposition(fields);
        guard ok else { return none, none, PART_BAD; }
        if n == name { return body[start..start + k], fields, PART_FOUND; }
        at = start + k + d.len;
    }
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
