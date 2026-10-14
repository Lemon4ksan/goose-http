// Cookies (RFC 6265): the pairs of a request's Cookie fields, and a
// response's Set-Cookie.
//
//   let sid, found = http::cookie_of(req, "sid");
//   http::set_cookie(out, http::Cookie { name: "sid", value: id, max_age: 3600,
//                                        path: "/", http_only: true, same_site: "Lax", .. });
namespace http;

import std;
import message;

// Calls F(name, value) for each pair of req's Cookie fields, in order: the
// value without the quotes it may have (RFC 6265 §4.2.1). A pair without '='
// is skipped, as a user agent sends none.
fn each_cookie<F>(req: const Request&) {
    each_field(req) { name, value =>
        if same_name(name, "cookie") {
            each_split(value, ';') { piece =>
                let pair = trim_ows(piece);
                let eq = position(pair, '=');
                if eq > 0 {
                    var v = trim_ows(pair[eq + 1..]);
                    if v.len >= 2 && v[0] == '"' && v[v.len - 1] == '"' { v = v[1..v.len - 1]; }
                    F(trim_ows(pair[..eq]), v);
                }
            };
        }
    };
}

// The value of req's cookie name, compared as sent, and whether req has it;
// the first, if it repeats.
fn cookie_of(req: const Request&, name: const u8[:]) -> const u8[:], bool {
    var v = req.fields[..0];
    var found = false;
    each_cookie(req) { n, value =>
        if !found && n == name {
            v = value;
            found = true;
        }
    };
    return v, found;
}

// A Set-Cookie field's cookie and attributes (RFC 6265 §4.1).
struct Cookie {
    name: const u8[:],
    value: const u8[:],
    // In seconds, or -1 for none; any other value of 0 or less removes the
    // cookie.
    max_age: i64 = -1,
    // In seconds since the epoch. -1 for none.
    expires: i64 = -1,
    path: const u8[:] = "",
    domain: const u8[:] = "",
    secure: bool = false,
    http_only: bool = false,
    // "Strict", "Lax", or "None", or "" for none. "None" needs secure.
    same_site: const u8[:] = "",
}

// Whether c makes a Set-Cookie field (RFC 6265 §4.1.1): a token for the
// name, cookie octets for the value, quoted or not, and path and domain
// without control bytes or ';'.
fn is_cookie(c: Cookie) -> bool {
    guard c.name.len > 0 && find_any(c.name, NAME_END) < 0 else { return false; }
    var v = c.value;
    if v.len >= 2 && v[0] == '"' && v[v.len - 1] == '"' { v = v[1..v.len - 1]; }
    for b in v {
        guard b == 0x21 || b >= 0x23 && b <= 0x2b || b >= 0x2d && b <= 0x3a || b >= 0x3c && b <= 0x5b ||
              b >= 0x5d && b <= 0x7e else { return false; }
    }
    guard is_attribute(c.path) && is_attribute(c.domain) else { return false; }
    return c.same_site == "" || c.same_site == "Strict" || c.same_site == "Lax" || c.same_site == "None";
}

// Whether s can be a cookie attribute's value: no control bytes, DEL, or ';'.
fn is_attribute(s: const u8[:]) -> bool {
    for b in s {
        guard b >= ' ' && b < 0x7f && b != ';' else { return false; }
    }
    return true;
}

// Writes c as a Set-Cookie field, between start and finish, or begin and the
// first send, and returns whether it did. A cookie that is_cookie refuses is
// dropped, as field drops a field.
fn set_cookie(out: Reply, c: Cookie) -> bool {
    guard is_cookie(c) else { return false; }
    out.buf.append("Set-Cookie: ");
    out.buf.append(c.name);
    out.buf.push('=');
    out.buf.append(c.value);
    if c.max_age != -1 {
        out.buf.append("; Max-Age=");
        format(out.buf, max(c.max_age, 0));
    }
    if c.expires >= 0 {
        out.buf.append("; Expires=");
        format_date(out.buf, c.expires);
    }
    if c.path.len > 0 {
        out.buf.append("; Path=");
        out.buf.append(c.path);
    }
    if c.domain.len > 0 {
        out.buf.append("; Domain=");
        out.buf.append(c.domain);
    }
    if c.secure { out.buf.append("; Secure"); }
    if c.http_only { out.buf.append("; HttpOnly"); }
    if c.same_site.len > 0 {
        out.buf.append("; SameSite=");
        out.buf.append(c.same_site);
    }
    out.buf.append("\r\n");
    return true;
}
