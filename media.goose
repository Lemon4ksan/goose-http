// Media types (RFC 9110 §8.3.1): a request's Content-Type, and the type a
// response takes from the request's Accept (§12.5.1).
//
//   guard http::require_type(req, out, "application/json") else { return; }
//   let i = http::accept_or_406(req, out, ["application/json", "text/csv"]);
//   guard i >= 0 else { return; }
namespace http;

import std;
import message;

// A media type, as "text/html; charset=utf-8": slices of the text it was
// parsed from.
struct MediaType {
    top: const u8[:],       // the top-level type (RFC 6838 §4.2)
    sub: const u8[:],
    params: const u8[:],    // what follows the subtype, for each_param
}

// The media type in text, and whether it is one: a type and a subtype of
// token characters, and parameters that each_param takes.
fn media_type(text: const u8[:]) -> MediaType, bool {
    let s = trim_ows(text);
    var slash = 0;
    while slash < s.len && is_tchar(s[slash]) { slash++; }
    guard slash > 0 && slash < s.len && s[slash] == '/' else { return MediaType { .. }, false; }
    var end = slash + 1;
    while end < s.len && is_tchar(s[end]) { end++; }
    guard end > slash + 1 else { return MediaType { .. }, false; }
    let m = MediaType { top: s[..slash], sub: s[slash + 1..end], params: s[end..] };
    let rest = each_param_until(m.params, false) { n, v => };
    return m, rest == m.params.len;
}

// Calls F(name, value) for each parameter in params, as "; a=1; b="x y"":
// the name as sent, and the value without the quotes of a quoted string,
// whose backslash escapes are left in it. Returns false, after the
// parameters before it, at one that isn't a token, '=', and a token or a
// quoted string.
fn each_param<F>(params: const u8[:]) -> bool {
    return each_param_until(params, false) { n, v => F(n, v); } == params.len;
}

// each_param, stopping before a ',' outside a quoted string when comma is
// set, as one element of a list ends. Returns where it stopped: at the comma,
// the end, or the parameter it couldn't read.
fn each_param_until<F>(params: const u8[:], comma: bool) -> i64 {
    var i = 0;
    loop {
        var j = i;
        while j < params.len && (params[j] == ' ' || params[j] == '\t') { j++; }
        if j == params.len || comma && params[j] == ',' { return j; }
        guard params[j] == ';' else { return i; }
        j++;
        while j < params.len && (params[j] == ' ' || params[j] == '\t') { j++; }
        // RFC 9110 allows an empty parameter, as in "a/b;;c=d".
        if j == params.len || params[j] == ';' || comma && params[j] == ',' {
            i = j;
            continue;
        }
        let n0 = j;
        while j < params.len && is_tchar(params[j]) { j++; }
        guard j > n0 && j < params.len && params[j] == '=' else { return i; }
        let name = params[n0..j];
        j++;
        var value = params[j..j];
        if j < params.len && params[j] == '"' {
            let q = quoted_end(params, j);
            guard q > 0 else { return i; }
            value = params[j + 1..q - 1];
            j = q;
        } else {
            let v0 = j;
            while j < params.len && is_tchar(params[j]) { j++; }
            guard j > v0 else { return i; }
            value = params[v0..j];
        }
        F(name, value);
        i = j;
    }
}

// Where the quoted string at s[at] ends, past its closing quote, or 0 if it
// doesn't (RFC 9110 §5.6.4).
fn quoted_end(s: const u8[:], at: i64) -> i64 {
    var i = at + 1;
    while i < s.len {
        let c = s[i];
        if c == '"' { return i + 1; }
        if c == '\\' {
            guard i + 1 < s.len && (s[i + 1] == '\t' || s[i + 1] >= ' ' && s[i + 1] != 0x7f) else { return 0; }
            i += 2;
        } else {
            guard c == '\t' || c >= ' ' && c != 0x7f else { return 0; }
            i++;
        }
    }
    return 0;
}

// The value of m's parameter name, compared ignoring case, and whether m
// has it; the first, if it repeats. As each_param gives it.
fn param_of(m: MediaType, name: const u8[:]) -> const u8[:], bool {
    var v = m.params[..0];
    var found = false;
    each_param(m.params) { n, value =>
        if !found && same_name(n, name) {
            v = value;
            found = true;
        }
    };
    return v, found;
}

// Whether m is the type and subtype of want, as "application/json",
// ignoring case and m's parameters.
fn is_media(m: MediaType, want: const u8[:]) -> bool {
    let slash = position(want, '/');
    guard slash > 0 else { return false; }
    return same_name(m.top, want[..slash]) && same_name(m.sub, want[slash + 1..]);
}

// Whether req's Content-Type is want, as is_media compares them.
fn has_type(req: Request, want: const u8[:]) -> bool {
    let v, found = field_of(req, "content-type");
    guard found else { return false; }
    let m, ok = media_type(v);
    return ok && is_media(m, want);
}

// Whether req's Content-Type is want, as has_type; if it isn't, answers 415
// with want in Accept, as RFC 9110 §15.5.16 suggests.
fn require_type(req: Request, out: Reply, want: const u8[:]) -> bool {
    guard !has_type(req, want) else { return true; }
    start(out, 415);
    field(out, "Accept", want);
    finish(out, "Content-Length: ", "");
    return false;
}

// The index of the offer, a media type as "text/html", that req's Accept
// prefers (RFC 9110 §12.5.1), or -1 if it takes none of them. Each offer
// gets the weight of the most specific media range that matches it, and of
// equal weights the first offer wins. A request without Accept takes the
// first. A range whose weight or parameters can't be read is skipped.
fn negotiate(req: Request, offers: const u8[:][:]) -> i64 {
    var any = false;
    var best = -1;
    var best_q = 0;
    var weights: i64[>..] = [];
    var ranks: i64[>..] = [];
    for i in offers.len {
        weights.push(-1);
        ranks.push(-1);
    }
    each_field(req) { name, value =>
        if same_name(name, "accept") {
            any = true;
            weigh(value, offers, weights, ranks);
        }
    };
    guard any else { return if offers.len > 0 { 0 } else { -1 }; }
    for w, i in weights {
        if w > best_q {
            best = i;
            best_q = w;
        }
    }
    return best;
}

// Weighs each offer by the ranges of list, an Accept value: weights[i] and
// ranks[i] become the weight, 0 to 1000, and the specificity of the most
// specific range that matches offers[i], if it's more specific than any
// before.
fn weigh(list: const u8[:], offers: const u8[:][:], weights: i64[>..]&, ranks: i64[>..]&) {
    var at = 0;
    while at < list.len {
        // A range runs to the next ',' outside a quoted string.
        var s = at;
        while s < list.len && (list[s] == ' ' || list[s] == '\t' || list[s] == ',') { s++; }
        guard s < list.len else { return; }
        var e = s;
        while e < list.len && is_tchar(list[e]) { e++; }
        var slash = e;
        if e < list.len && list[e] == '/' {
            e++;
            while e < list.len && is_tchar(list[e]) { e++; }
        }
        let range = list[s..e];
        var q = 1000;
        var good = slash > s && e > slash + 1;
        var params: u8[>..] = [];
        let stop = e + each_param_until(list[e..], true) { n, v =>
            if same_name(n, "q") {
                let w, ok = qvalue(v);
                if ok { q = w; } else { good = false; }
            } else {
                params.append(";");
                params.append(n);
                params.push('=');
                params.append(v);
            }
        };
        // A range that ends anywhere but a comma or the end is skipped to the
        // next comma.
        var next = stop;
        if next < list.len && list[next] != ',' {
            good = false;
            next = element_end(list, next);
        }
        at = next;
        guard good else { continue; }
        let rtype = range[..slash - s];
        let rsub = range[slash - s + 1..];
        for o, i in offers {
            let m, ok = media_type(o);
            guard ok else { continue; }
            var rank = 0;
            if rtype == "*" {
                guard rsub == "*" else { continue; }
            } else {
                guard same_name(rtype, m.top) else { continue; }
                if rsub != "*" {
                    guard same_name(rsub, m.sub) else { continue; }
                    rank = 2;
                } else {
                    rank = 1;
                }
            }
            if params.len > 0 {
                guard rank == 2 && params_in(params, m) else { continue; }
                rank = 3;
            }
            if rank > ranks[i] {
                ranks[i] = rank;
                weights[i] = q;
            }
        }
    }
}

// Where the element of list that i is in ends: the next ',' outside a quoted
// string, or the end.
fn element_end(list: const u8[:], i: i64) -> i64 {
    var at = i;
    while at < list.len && list[at] != ',' {
        if list[at] == '"' {
            let qe = quoted_end(list, at);
            at = if qe > 0 { qe } else { list.len };
        } else {
            at++;
        }
    }
    return at;
}

// The weight req's Accept-Encoding gives coding (RFC 9110 §12.5.3), 0 to
// 1000: its own, or else that of "*", or else 0. A request without
// Accept-Encoding gets 0 for every coding, so it is answered without one,
// as clients that send none expect. x-gzip counts as gzip (§8.4.1.3). An
// element whose weight or parameters can't be read is skipped.
fn coding_q(req: Request, coding: const u8[:]) -> i64 {
    var own = -1;
    var any = -1;
    each_field(req) { name, value =>
        var at = if same_name(name, "accept-encoding") { 0 } else { value.len };
        while at < value.len {
            var s = at;
            while s < value.len && (value[s] == ' ' || value[s] == '\t' || value[s] == ',') { s++; }
            guard s < value.len else { break; }
            var e = s;
            while e < value.len && is_tchar(value[e]) { e++; }
            let c = value[s..e];
            var q = 1000;
            var good = e > s;
            let stop = e + each_param_until(value[e..], true) { n, v =>
                let w, ok = qvalue(v);
                if same_name(n, "q") && ok { q = w; } else { good = false; }
            };
            at = stop;
            if at < value.len && value[at] != ',' {
                good = false;
                at = element_end(value, at);
            }
            guard good else { continue; }
            if same_name(c, coding) || coding == "gzip" && same_name(c, "x-gzip") { own = max(own, q); }
            else if c == "*" { any = max(any, q); }
        }
    };
    return if own >= 0 { own } else { max(any, 0) };
}

// Whether each parameter in params, as "; a=1", is m's too, with the name
// ignoring case and the value as sent.
fn params_in(params: const u8[:], m: MediaType) -> bool {
    var all = true;
    each_param(params) { n, v =>
        let mv, found = param_of(m, n);
        if !found || mv != v { all = false; }
    };
    return all;
}

// The weight of a qvalue (RFC 9110 §12.4.2), in thousandths, and whether
// text is one.
fn qvalue(text: const u8[:]) -> i64, bool {
    guard text.len > 0 && text.len <= 5 && (text[0] == '0' || text[0] == '1') else { return 0, false; }
    guard text.len == 1 || text[1] == '.' else { return 0, false; }
    var w = (text[0] - '0') as i64 * 1000;
    var scale = 100;
    for c in text[min(2, text.len)..] {
        guard is_digit(c) else { return 0, false; }
        w += (c - '0') * scale;
        scale /= 10;
    }
    return w, w <= 1000;
}

// The index of the offer negotiate picks; if it picks none, answers 406
// and returns -1.
fn accept_or_406(req: Request, out: Reply, offers: const u8[:][:]) -> i64 {
    let i = negotiate(req, offers);
    guard i < 0 else { return i; }
    start(out, 406);
    finish(out, "Content-Length: ", "");
    return -1;
}

// A whole response whose body W writes as JSON, W(body), with json.goose's
// writers, and its content type: application/json, which takes no charset
// (RFC 8259 §11).
//
//   http::respond_json(out, 200) { b =>
//       b.push('{');
//       json::format_key(b, "id");
//       json::format_int(b, id);
//       b.push('}');
//   };
fn respond_json<W>(out: Reply, status: i32) {
    var body: u8[>..] = [];
    W(&body);
    respond(out, status, "application/json", body);
}

