// The Authorization field (RFC 9110 §11.6.2), and the Basic scheme's
// credentials (RFC 7617).
//
//   var decoded: u8[>..] = [];
//   let user, pass, ok = http::basic_auth(req, decoded);
//   guard ok && known(user, pass) else { http::challenge(out, "Basic realm=\"api\""); return; }
namespace http;

import std;
import base64;
import message;

// The scheme of req's Authorization field, as sent, and its credentials,
// and whether req has a field of that form: a token, one or more spaces, and
// the credentials, or the token alone.
fn authorization(req: const Request&) -> const u8[:], const u8[:], bool {
    let v, found = field_of(req, "authorization");
    guard found else { return v, v, false; }
    var e = 0;
    while e < v.len && is_tchar(v[e]) { e++; }
    guard e > 0 && (e == v.len || v[e] == ' ') else { return v[..0], v[..0], false; }
    var c = e;
    while c < v.len && v[c] == ' ' { c++; }
    return v[..e], v[c..], true;
}

// The user-id and password of req's Basic credentials, decoded onto the end
// of decoded, which they point into, and whether req has them: the scheme,
// ignoring case, then base64 of the two with ':' between, split at the first
// ':'. Neither is checked for UTF-8.
fn basic_auth(req: const Request&, decoded: u8[>..]&) -> const u8[:], const u8[:], bool {
    let at = decoded.len;
    let scheme, token, ok = authorization(req);
    // base64::decode shrinks its output back on bad input, which the checker
    // takes req to maybe point into, so it decodes apart.
    var text: u8[>..] = [];
    guard ok && eq_fold(scheme, "basic") && base64::decode(text, token) else {
        return decoded[at..at], decoded[at..at], false;
    }
    decoded.append(text);
    let colon = position(decoded[at..], ':');
    guard colon >= 0 else { return decoded[at..at], decoded[at..at], false; }
    return decoded[at..at + colon], decoded[at + colon + 1..], true;
}

// The token of req's Bearer credentials (RFC 6750 §2.1), and whether req has
// them: the scheme, ignoring case, then a token68 (RFC 9110 §11.2).
fn bearer(req: const Request&) -> const u8[:], bool {
    let scheme, token, ok = authorization(req);
    guard ok && eq_fold(scheme, "bearer") && is_token68(token) else { return token[..0], false; }
    return token, true;
}

// Whether s is a token68: letters, digits, and "-._~+/", then any '='s.
fn is_token68(s: const u8[:]) -> bool {
    var i = 0;
    while i < s.len {
        let c = s[i];
        let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        guard letter || is_digit(c) || c == '-' || c == '.' || c == '_' || c == '~' || c == '+' ||
              c == '/' else { break; }
        i++;
    }
    guard i > 0 else { return false; }
    while i < s.len && s[i] == '=' { i++; }
    return i == s.len;
}

// Answers 401 with value as WWW-Authenticate, as "Basic realm=\"api\"".
// A challenge field would drop goes out as a 401 without one.
fn challenge(out: Reply, value: const u8[:]) {
    start(out, 401);
    field(out, "WWW-Authenticate", value);
    finish(out, NO_TYPE, "");
}
