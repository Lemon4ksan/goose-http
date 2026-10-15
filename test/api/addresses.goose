// Client addresses: address and format_address (RFC 5952), networks, and
// forwarded_client over X-Forwarded-For and Forwarded from trusted peers.
import std;
import http from "../../";
import check from "../";

// The address text names, formatted again.
fn reads_as(text: const u8[:], want: const u8[:]) {
    let a, ok = http::address(text);
    assert(ok);
    var out: u8[>..] = [];
    http::format_address(out, a);
    check::same(out, want);
    print(text, " -> ", out);
}

fn not_address(text: const u8[:]) {
    let a, ok = http::address(text);
    if ok { print("took: ", text); }
    assert(!ok);
}

fn inside(text: const u8[:], net: const u8[:]) -> bool {
    let a, ok = http::address(text);
    let n, good = http::network(net);
    assert(ok && good);
    return http::in_network(a, n);
}

fn not_network(text: const u8[:]) {
    let n, ok = http::network(text);
    assert(!ok);
}

fn test_addresses() {
    reads_as("192.0.2.1", "192.0.2.1");
    reads_as("0.0.0.0", "0.0.0.0");
    reads_as("255.255.255.255", "255.255.255.255");
    // RFC 5952 §4: lowercase, the longest run of zero groups, the first of
    // equal ones, and a single zero group left as it is.
    reads_as("2001:DB8:0:0:0:0:2:1", "2001:db8::2:1");
    reads_as("2001:0db8:0:1:1:1:1:1", "2001:db8:0:1:1:1:1:1");
    reads_as("2001:0:0:1:0:0:0:1", "2001:0:0:1::1");
    reads_as("2001:db8:0:0:1:0:0:1", "2001:db8::1:0:0:1");
    reads_as("1:2:3:4:5:6:7::", "1:2:3:4:5:6:7:0");
    reads_as("::1", "::1");
    reads_as("::", "::");
    reads_as("1::", "1::");
    reads_as("::ffff:192.0.2.1", "192.0.2.1");
    reads_as("64:ff9b::192.0.2.33", "64:ff9b::c000:221");
    not_address("");
    not_address("1.2.3");
    not_address("1.2.3.4.5");
    not_address("256.1.1.1");
    not_address("01.2.3.4");
    not_address("1.2.3.4 ");
    not_address("1:2:3:4:5:6:7:8:9");
    not_address("1:2:3:4:5:6:7");
    not_address("1::2::3");
    not_address(":1");
    not_address("1:");
    not_address("12345::");
    not_address("1:2:3:4:5:6:7:8::");
    not_address("::1.2.3");
    not_address("1:2:3:4:5:6:7:1.2.3.4");
    not_address("g::1");
    not_address("[::1]");
    not_address("::1%eth0");
    print("not addresses: 18");

    assert(inside("10.1.2.3", "10.0.0.0/8"));
    assert(!inside("11.0.0.1", "10.0.0.0/8"));
    assert(inside("192.168.1.130", "192.168.1.128/25"));
    assert(!inside("192.168.1.127", "192.168.1.128/25"));
    assert(inside("203.0.113.9", "0.0.0.0/0"));
    assert(!inside("::1", "0.0.0.0/0"));
    assert(inside("2001:db8::5", "2001:db8::/32"));
    assert(!inside("2001:db9::5", "2001:db8::/32"));
    assert(inside("::1", "::1"));
    assert(!inside("::2", "::1"));
    assert(inside("127.0.0.1", "127.0.0.1"));
    assert(inside("::ffff:127.0.0.1", "127.0.0.0/8"));
    not_network("10.0.0.0/33");
    not_network("::/129");
    not_network("10.0.0.0/");
    not_network("10.0.0.0/a");
    not_network("x/8");
    print("networks: 12 in_network cases, 5 not networks");
}

// The client of a request with fields from peer, trusting loopback and
// 10.0.0.0/8.
fn client_is(fields: const u8[:], peer: const u8[:], want: const u8[:]) {
    var buf: u8[>..] = [];
    let req = check::request("POST", fields, buf);
    let p, ok = http::address(peer);
    let lo, ok1 = http::network("127.0.0.0/8");
    let ten, ok2 = http::network("10.0.0.0/8");
    assert(ok && ok1 && ok2);
    let c = http::forwarded_client(req, p, [lo, ten]);
    var out: u8[>..] = [];
    http::format_address(out, c);
    check::same(out, want);
}

fn test_forwarded() {
    // Only a trusted peer's fields count.
    client_is("X-Forwarded-For: 203.0.113.5\r\n", "192.0.2.9", "192.0.2.9");
    client_is("", "127.0.0.1", "127.0.0.1");
    client_is("X-Forwarded-For: 203.0.113.5\r\n", "127.0.0.1", "203.0.113.5");
    // The nearest hop that isn't trusted, across repeated fields.
    client_is("X-Forwarded-For: 198.51.100.1, 203.0.113.5\r\n", "127.0.0.1", "203.0.113.5");
    client_is("X-Forwarded-For: 198.51.100.1,10.0.0.2\r\n", "127.0.0.1", "198.51.100.1");
    client_is("X-Forwarded-For: 198.51.100.1\r\nX-Forwarded-For: 10.0.0.2\r\n", "127.0.0.1", "198.51.100.1");
    // All trusted: the farthest.
    client_is("X-Forwarded-For: 10.0.0.3, 10.0.0.2\r\n", "127.0.0.1", "10.0.0.3");
    // A hop that can't be read ends the walk at the trusted hop before it.
    client_is("X-Forwarded-For: junk, 10.0.0.2\r\n", "127.0.0.1", "10.0.0.2");
    client_is("X-Forwarded-For: 198.51.100.1, junk\r\n", "127.0.0.1", "127.0.0.1");
    client_is("X-Forwarded-For: 198.51.100.1, , 10.0.0.2\r\n", "127.0.0.1", "10.0.0.2");
    client_is("X-Forwarded-For: 198.51.100.1, junk, 10.0.0.2\r\n", "127.0.0.1", "10.0.0.2");
    // Ports, and IPv6 bracketed or bare.
    client_is("X-Forwarded-For: [2001:db8::1]:4711\r\n", "127.0.0.1", "2001:db8::1");
    client_is("X-Forwarded-For: 2001:DB8::1\r\n", "127.0.0.1", "2001:db8::1");
    client_is("X-Forwarded-For: 203.0.113.5:80\r\n", "127.0.0.1", "203.0.113.5");
    client_is("X-Forwarded-For: 203.0.113.5:99999\r\n", "127.0.0.1", "127.0.0.1");
    client_is("X-Forwarded-For: [2001:db8::1]x\r\n", "127.0.0.1", "127.0.0.1");
    print("X-Forwarded-For: 16 cases");
    // Forwarded (RFC 7239 §4), over X-Forwarded-For when both come.
    client_is("Forwarded: for=192.0.2.60;proto=http;by=203.0.113.43, for=\"[2001:db8:cafe::17]:4711\"\r\n",
              "127.0.0.1", "2001:db8:cafe::17");
    client_is("Forwarded: for=192.0.2.60;proto=http;by=203.0.113.43, for=10.0.0.1\r\n", "127.0.0.1", "192.0.2.60");
    client_is("X-Forwarded-For: 198.51.100.1\r\nForwarded: FOR=192.0.2.60\r\n", "127.0.0.1", "192.0.2.60");
    client_is("Forwarded: for=192.0.2.60\r\nForwarded: for=10.0.0.9;proto=https\r\n", "127.0.0.1", "192.0.2.60");
    client_is("Forwarded: for=unknown\r\n", "127.0.0.1", "127.0.0.1");
    client_is("Forwarded: for=\"_hidden\", for=10.0.0.5\r\n", "127.0.0.1", "10.0.0.5");
    client_is("Forwarded: proto=https\r\n", "127.0.0.1", "127.0.0.1");
    client_is("Forwarded: for=192.0.2.60, ;;\r\n", "127.0.0.1", "127.0.0.1");
    client_is("Forwarded: for=192.0.2.60;for\r\n", "127.0.0.1", "127.0.0.1");
    client_is("Forwarded: for=\"192.0.2.60\r\n", "127.0.0.1", "127.0.0.1");
    print("Forwarded: 10 cases");
}

fn main() {
    test_addresses();
    test_forwarded();
}
