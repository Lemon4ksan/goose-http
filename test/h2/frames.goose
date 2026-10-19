// HTTP/2's frames: the preface, each type written and parsed back, padding
// and priorities, field blocks split into CONTINUATIONs, the settings, and
// each size and stream rule of RFC 9113 §6 that makes a frame an error.
import std;
import http from "../../";
import http.h2frame;
import check from "../";

fn hex(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for i in 0..s.len / 2 {
        let v, ok = parse_int(s[2 * i..2 * i + 2], 16);
        assert(ok);
        out.push(v as u8);
    }
    return out;
}

fn to_hex(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for c in s { format_int(out, c, 16, 2, '0'); }
    return out;
}

fn code_name(c: u32) -> const u8[:] {
    match c {
        http::H2_NO_ERROR => "NO_ERROR",
        http::H2_PROTOCOL_ERROR => "PROTOCOL_ERROR",
        http::H2_FLOW_CONTROL_ERROR => "FLOW_CONTROL_ERROR",
        http::H2_FRAME_SIZE_ERROR => "FRAME_SIZE_ERROR",
        _ => "other",
    }
}

// The frame buf holds, which must parse whole and alone.
fn parse(buf: const u8[:]) -> http::H2Frame {
    let f, size, err = http::h2_parse(buf);
    assert(err.code == 0 && size == buf.len);
    return f;
}

fn preface() {
    assert(http::h2_preface(http::H2_PREFACE) == 24);
    var more: u8[>..] = [];
    more.append(http::H2_PREFACE);
    more.append("\x00\x00\x00\x04\x00\x00\x00\x00\x00");
    assert(http::h2_preface(more) == 24);
    assert(http::h2_preface("") == 0 && http::h2_preface("PRI * HT") == 0);
    assert(http::h2_preface("GET / HTTP/1.1\r\n") == -1 && http::h2_preface("PRI * HTTP/1.1\r\n") == -1);
    print("preface: whole, followed by SETTINGS, in part, and an HTTP/1.1 request");
}

fn round_trips() {
    {
        var out: u8[>..] = [];
        http::h2_write_data(out, 1, "hello", true);
        check::same(to_hex(out), "00000500010000000168656c6c6f");
        let f = parse(out);
        assert(f.kind == http::H2_DATA && f.flags == http::H2_END_STREAM && f.stream == 1);
        check::same(f.data, "hello");
    }
    {
        var out: u8[>..] = [];
        http::h2_write_headers(out, 3, "\x82\x86\x84", false);
        let f = parse(out);
        assert(f.kind == http::H2_HEADERS && f.flags == http::H2_END_HEADERS && f.stream == 3);
        check::same(f.data, "\x82\x86\x84");
    }
    {
        var out: u8[>..] = [];
        http::h2_write_priority(out, 5, 3, true, 256);
        check::same(to_hex(out), "00000502000000000580000003ff");
        let f = parse(out);
        assert(f.dependency == 3 && f.exclusive && f.weight == 256);
    }
    {
        var out: u8[>..] = [];
        http::h2_write_rst_stream(out, 7, http::H2_CANCEL);
        let f = parse(out);
        assert(f.kind == http::H2_RST_STREAM && f.stream == 7 && f.error == http::H2_CANCEL);
    }
    {
        var out: u8[>..] = [];
        http::h2_write_settings(out, http::H2Settings { .. });
        check::same(to_hex(out), "000000040000000000");
    }
    {
        var out: u8[>..] = [];
        let mine = http::H2Settings {
            enable_push: false, max_concurrent_streams: 100, initial_window_size: 1048576,
            max_frame_size: 65536, header_table_size: 0, ..
        };
        http::h2_write_settings(out, mine);
        let f = parse(out);
        assert(f.kind == http::H2_SETTINGS && f.len == 30);
        var got = http::H2Settings { .. };
        assert(http::h2_apply_settings(got, f.data) == http::H2_NO_ERROR);
        assert(got == mine);
    }
    {
        var out: u8[>..] = [];
        http::h2_write_settings_ack(out);
        let f = parse(out);
        assert(f.flags == http::H2_ACK && f.len == 0);
    }
    {
        var out: u8[>..] = [];
        http::h2_write_push_promise(out, 1, 2, "\x82");
        let f = parse(out);
        assert(f.kind == http::H2_PUSH_PROMISE && f.promised == 2 && f.flags == http::H2_END_HEADERS);
        check::same(f.data, "\x82");
    }
    {
        var out: u8[>..] = [];
        http::h2_write_ping(out, "goosepng", true);
        let f = parse(out);
        assert(f.kind == http::H2_PING && f.flags == http::H2_ACK);
        check::same(f.data, "goosepng");
    }
    {
        var out: u8[>..] = [];
        http::h2_write_goaway(out, 9, http::H2_ENHANCE_YOUR_CALM, "slow down");
        let f = parse(out);
        assert(f.last_stream == 9 && f.error == http::H2_ENHANCE_YOUR_CALM);
        check::same(f.data, "slow down");
    }
    {
        var out: u8[>..] = [];
        http::h2_write_window_update(out, 0, http::H2_MAX_WINDOW);
        let f = parse(out);
        assert(f.kind == http::H2_WINDOW_UPDATE && f.stream == 0 && f.increment == http::H2_MAX_WINDOW);
    }
    print("round trips: DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS and its ACK, ",
          "PUSH_PROMISE, PING, GOAWAY, WINDOW_UPDATE");
}

fn padding_and_priority() {
    // DATA, padded: pad length 3, "hi", 3 bytes of padding.
    let data = hex("000006000900000001036869000000");
    let d = parse(data);
    check::same(d.data, "hi");
    assert(d.len == 6);
    // HEADERS, padded and with a priority: pad length 2, stream 1 depended on
    // exclusively at weight 17 (16 on the wire), the fragment 0x82, 2 bytes
    // of padding.
    let headers = hex("000009012d00000003028000000110820000");
    let h = parse(headers);
    assert(h.dependency == 1 && h.exclusive && h.weight == 17);
    check::same(h.data, "\x82");
    assert(h.flags & http::H2_END_STREAM != 0);
    // The reserved bit of a stream identifier is ignored (§4.1).
    let reserved = hex("000000000080000001");
    assert(parse(reserved).stream == 1);
    // A type this side doesn't know is parsed and left to be ignored.
    let unknown = hex("0000020aff00000000abcd");
    let u = parse(unknown);
    assert(u.kind == 0x0a && u.data.len == 2);
    print("padding and priorities: padded DATA, padded HEADERS with a priority, ",
          "the reserved bit, an unknown type");
}

fn continuations() {
    var fb: u8[>..] = [];
    for i in 40000 { fb.push((i % 251) as u8); }
    var out: u8[>..] = [];
    http::h2_write_headers(out, 1, fb, true);
    var joined: u8[>..] = [];
    var rest: const u8[:] = out;
    var kinds: u8[>..] = [];
    while rest.len > 0 {
        let f, size, err = http::h2_parse(rest);
        assert(err.code == 0 && size > 0 && f.stream == 1);
        format(kinds, f.kind, if f.flags & http::H2_END_HEADERS != 0 { "e" } else { "" }, " ");
        joined.append(f.data);
        rest = rest[size..];
    }
    check::same(kinds, "1 9 9e ");
    assert(joined == fb);
    out.clear();
    http::h2_write_push_promise(out, 1, 2, fb[..16381]);
    let f, size, err = http::h2_parse(out);
    assert(f.kind == http::H2_PUSH_PROMISE && f.flags == 0 && f.len == 16384);
    print("a 40000-byte field block: HEADERS and 2 CONTINUATIONs, the last with END_HEADERS; ",
          "PUSH_PROMISE's leaves room for the promised stream");
}

fn incomplete() {
    var out: u8[>..] = [];
    http::h2_write_data(out, 1, "hello", false);
    for n in out.len {
        let f, size, err = http::h2_parse(out[..n]);
        assert(size == 0 && err.code == 0);
    }
    out.clear();
    http::h2_write_data(out, 1, "", false);
    let f, size, err = http::h2_parse(out);
    assert(size == 9 && err.code == 0);
    print("incomplete: every prefix of a frame asks for more");
}

struct Bad { what: const u8[:], frame: const u8[:] }

fn errors() {
    let cases = [
        Bad { "DATA longer than SETTINGS_MAX_FRAME_SIZE", "004001000000000001" },
        Bad { "DATA on stream 0", "00000100000000000000" },
        Bad { "DATA padded past its end", "000003000800000001030000" },
        Bad { "DATA padded with no pad length", "000000000800000001" },
        Bad { "HEADERS on stream 0", "00000101040000000082" },
        Bad { "HEADERS too short for its priority", "00000401240000000100000000" },
        Bad { "HEADERS depending on itself", "000006012400000001000000011082" },
        Bad { "PRIORITY on stream 0", "0000050200000000000000000110" },
        Bad { "PRIORITY of 4 bytes", "00000402000000000100000003" },
        Bad { "PRIORITY depending on itself", "0000050200000000010000000110" },
        Bad { "RST_STREAM on stream 0", "00000403000000000000000008" },
        Bad { "RST_STREAM of 3 bytes", "000003030000000001000008" },
        Bad { "SETTINGS on stream 1", "000000040000000001" },
        Bad { "SETTINGS ACK with parameters", "000006040100000000000100000000" },
        Bad { "SETTINGS of 5 bytes", "0000050400000000000001000000" },
        Bad { "PUSH_PROMISE on stream 0", "00000405040000000000000002" },
        Bad { "PUSH_PROMISE too short for its stream", "000003050400000001000000" },
        Bad { "PING on stream 1", "0000080600000000010000000000000000" },
        Bad { "PING of 7 bytes", "00000706000000000000000000000000" },
        Bad { "GOAWAY on stream 1", "0000080700000000010000000000000000" },
        Bad { "GOAWAY of 7 bytes", "00000707000000000000000000000000" },
        Bad { "WINDOW_UPDATE of 3 bytes", "000003080000000000000001" },
        Bad { "WINDOW_UPDATE of 0 on the connection", "00000408000000000000000000" },
        Bad { "WINDOW_UPDATE of 0 on a stream", "00000408000000000100000000" },
        Bad { "CONTINUATION on stream 0", "00000109040000000082" },
    ];
    for c in cases {
        let buf = hex(c.frame);
        let f, size, err = http::h2_parse(buf);
        assert(err.code != 0);
        // A stream error leaves the frame whole, to be skipped.
        assert(err.stream == 0 || (err.stream == f.stream && size == buf.len));
        print("  ", c.what, ": ", code_name(err.code), if err.stream == 0 { ", connection" } else { ", stream" });
    }
    // A longer frame is taken where this side advertised more.
    let big = hex("004001000000000001");
    var long: u8[>..] = [];
    long.append(big);
    for i in 16385 { long.push(0); }
    let f, size, err = http::h2_parse(long, 16385);
    assert(err.code == 0 && size == long.len);
}

fn settings() {
    var s = http::H2Settings { .. };
    let bad = [
        "000200000002",
        "000480000000",
        "000500003fff",
        "000501000000",
        "000800000002",
        "000900000002",
    ];
    for b in bad {
        let code = http::h2_apply_settings(s, hex(b));
        print("  setting ", b[..4], " = ", b[4..], ": ", code_name(code));
        assert(code != http::H2_NO_ERROR);
    }
    s = http::H2Settings { .. };
    // An unknown setting is ignored, and a repeated one's last value stands.
    assert(http::h2_apply_settings(s, hex("00ff000000010003000000640003000000c8000400000000")) == 0);
    assert(s.max_concurrent_streams == 200 && s.initial_window_size == 0);
    assert(http::h2_apply_settings(s, hex("00040000ffff000500ffffff00047fffffff")) == 0);
    assert(s.max_frame_size == http::H2_MAX_FRAME_SIZE && s.initial_window_size == http::H2_MAX_WINDOW);
    print("settings: unknown ones ignored, the last of a repeated one kept, the limits taken");
}

fn main() {
    preface();
    round_trips();
    padding_and_priority();
    continuations();
    incomplete();
    print("errors:");
    errors();
    print("settings refused:");
    settings();
}
