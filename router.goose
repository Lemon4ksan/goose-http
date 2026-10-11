// A router for a handler's REQUEST: method and path patterns with
// parameters, tried in order in an if chain, and 405 with Allow, or 404,
// from the routes that didn't match. Nothing allocates: the parameters are
// slices of the target and the patterns.
//
//   var r = http::router(req);
//   if http::on(r, "GET", "/users/:id") { show(http::param(r, "id"), out); }
//   else if http::on(r, "PUT", "/users/:id") { ... }
//   else if http::on(r, "GET", "/files/*path") { ... }
//   else { http::otherwise(r, out); }
namespace http;

import std;
import message;

// The most parameters a pattern captures.
let MAX_PARAMS = 8;

struct Param { name: const u8[:], value: const u8[:] }

struct Router {
    method: const u8[:],
    path: const u8[:],           // the target's path, still encoded
    params: Param[..MAX_PARAMS],  // the last matched route's
    allow: u8[..96],             // methods of routes whose path matched, ", " between
}

// A router for req, whose slices it keeps: it lasts until the handler returns.
fn router(req: const Request&) -> Router {
    return Router { method: req.method, path: path_of(req.target), params: [], allow: [] };
}

// Whether req is method on a path pattern matches, with HEAD taken by GET's
// routes. A pattern is segments after '/': a literal, ":name" for one
// segment, or "*name", last, for the rest of the path, empty or not. A
// pattern that matches with another method adds the method to r's Allow.
// The parameters are the path's bytes, still encoded: http::decode decodes
// one.
fn on(r: Router&, method: const u8[:], pattern: const u8[:]) -> bool {
    guard matches(r, pattern) else { return false; }
    if method == r.method || (method == "GET" && r.method == "HEAD") { return true; }
    allow(r, method);
    if method == "GET" { allow(r, "HEAD"); }
    return false;
}

// The value of the matched route's parameter name, or "".
fn param(r: const Router&, name: const u8[:]) -> const u8[:] {
    for p in r.params {
        if p.name == name { return p.value; }
    }
    return "";
}

// Answers a request that no route took: OPTIONS with 204 and the Allow of the
// routes whose path matched, any other method with 405 and that Allow, and a
// path no route matched with 404.
fn otherwise(r: const Router&, out: Reply) {
    if r.allow.len == 0 {
        start(out, 404);
        finish(out, "Content-Length: ", "");
    } else if r.method == "OPTIONS" {
        start(out, 204);
        field(out, "Allow", r.allow);
        finish(out, "", "");
    } else {
        start(out, 405);
        field(out, "Allow", r.allow);
        finish(out, "Content-Length: ", "");
    }
}

fn allow(r: Router&, method: const u8[:]) {
    var at = 0;
    while at < r.allow.len {
        var end = at;
        while end < r.allow.len && r.allow[end] != ',' { end++; }
        if r.allow[at..end] == method { return; }
        at = end + 2;
    }
    guard r.allow.len + method.len + 2 <= r.allow.cap else { return; }
    if r.allow.len > 0 { r.allow.append(", "); }
    r.allow.append(method);
}

// Whether r's path matches pattern, with the parameters in r.params.
fn matches(r: Router&, pattern: const u8[:]) -> bool {
    r.params.clear();
    let path = r.path;
    var p = 0;   // in pattern
    var q = 0;   // in path
    loop {
        if p == pattern.len { return q == path.len; }
        guard q < path.len && pattern[p] == '/' && path[q] == '/' else { return false; }
        p++;
        q++;
        var pe = p;
        while pe < pattern.len && pattern[pe] != '/' { pe++; }
        var qe = q;
        while qe < path.len && path[qe] != '/' { qe++; }
        let seg = pattern[p..pe];
        if seg.len > 0 && seg[0] == '*' {
            guard r.params.len < MAX_PARAMS else { return false; }
            r.params.push(Param { name: seg[1..], value: path[q..] });
            return pe == pattern.len;
        }
        if seg.len > 0 && seg[0] == ':' {
            guard qe > q && r.params.len < MAX_PARAMS else { return false; }
            r.params.push(Param { name: seg[1..], value: path[q..qe] });
        } else {
            guard seg == path[q..qe] else { return false; }
        }
        p = pe;
        q = qe;
    }
}
