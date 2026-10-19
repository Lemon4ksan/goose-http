// HTTP/2's frames (RFC 9113 §4, §6) on bytes alone: the connection preface,
// each frame type parsed with the size and stream rules of its section, the
// settings applied, and each type written. Nothing here makes a system call,
// keeps a connection's state, or needs another of the package's files:
//
//   import http from "github.com/kaitk/goose-http@<tag>";
//   import http.h2frame;
//
//   let f, size, err = http::h2_parse(buf, settings.max_frame_size);
//   if err.code != 0 { ... }    // a connection error where err.stream is 0
//   else if size == 0 { ... }   // read more
//   else { ...; buf = buf[size..]; }
namespace http;

import std;

// What a client sends first on an h2c connection with prior knowledge (§3.4),
// before its SETTINGS.
let H2_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
let H2_HEAD = 9;

// Frame types (§6, §11.2).
let H2_DATA: u8 = 0;
let H2_HEADERS: u8 = 1;
let H2_PRIORITY: u8 = 2;
let H2_RST_STREAM: u8 = 3;
let H2_SETTINGS: u8 = 4;
let H2_PUSH_PROMISE: u8 = 5;
let H2_PING: u8 = 6;
let H2_GOAWAY: u8 = 7;
let H2_WINDOW_UPDATE: u8 = 8;
let H2_CONTINUATION: u8 = 9;

// Flags. ACK is SETTINGS' and PING's, END_STREAM DATA's and HEADERS'.
let H2_END_STREAM: u8 = 0x1;
let H2_ACK: u8 = 0x1;
let H2_END_HEADERS: u8 = 0x4;
let H2_PADDED: u8 = 0x8;
let H2_PRIORITY_FLAG: u8 = 0x20;

// Error codes (§7).
let H2_NO_ERROR: u32 = 0x0;
let H2_PROTOCOL_ERROR: u32 = 0x1;
let H2_INTERNAL_ERROR: u32 = 0x2;
let H2_FLOW_CONTROL_ERROR: u32 = 0x3;
let H2_SETTINGS_TIMEOUT: u32 = 0x4;
let H2_STREAM_CLOSED: u32 = 0x5;
let H2_FRAME_SIZE_ERROR: u32 = 0x6;
let H2_REFUSED_STREAM: u32 = 0x7;
let H2_CANCEL: u32 = 0x8;
let H2_COMPRESSION_ERROR: u32 = 0x9;
let H2_CONNECT_ERROR: u32 = 0xa;
let H2_ENHANCE_YOUR_CALM: u32 = 0xb;
let H2_INADEQUATE_SECURITY: u32 = 0xc;
let H2_HTTP_1_1_REQUIRED: u32 = 0xd;

// Settings (§6.5.2), with RFC 8441's extended CONNECT and RFC 9218's
// priorities off.
let H2_SETTINGS_HEADER_TABLE_SIZE = 0x1;
let H2_SETTINGS_ENABLE_PUSH = 0x2;
let H2_SETTINGS_MAX_CONCURRENT_STREAMS = 0x3;
let H2_SETTINGS_INITIAL_WINDOW_SIZE = 0x4;
let H2_SETTINGS_MAX_FRAME_SIZE = 0x5;
let H2_SETTINGS_MAX_HEADER_LIST_SIZE = 0x6;
let H2_SETTINGS_ENABLE_CONNECT_PROTOCOL = 0x8;
let H2_SETTINGS_NO_RFC7540_PRIORITIES = 0x9;

// The smallest and largest SETTINGS_MAX_FRAME_SIZE, the first also its
// initial value (§4.2); a window's initial size and the most it may reach
// (§6.9.1, §6.9.2); and a stream identifier's largest (§5.1.1).
let H2_MIN_FRAME_SIZE = 16384;
let H2_MAX_FRAME_SIZE = 16777215;
let H2_INITIAL_WINDOW = 65535;
let H2_MAX_WINDOW = 0x7fffffff;
let H2_MAX_STREAM = 0x7fffffff;
// What a setting the peer leaves unlimited holds.
let H2_UNLIMITED = 0xffffffff;

// One side's settings, at their initial values (§6.5.2).
struct H2Settings {
    header_table_size: i64 = 4096,
    enable_push: bool = true,
    max_concurrent_streams: i64 = H2_UNLIMITED,
    initial_window_size: i64 = H2_INITIAL_WINDOW,
    max_frame_size: i64 = H2_MIN_FRAME_SIZE,
    max_header_list_size: i64 = H2_UNLIMITED,
    connect_protocol: bool = false,
    no_rfc7540_priorities: bool = false,
}

// A parsed frame. data points into the buffer it was parsed from.
struct H2Frame {
    kind: u8,
    flags: u8,
    stream: i64,
    // The payload's length, padding included, which is what DATA's flow
    // control counts (§6.1).
    len: i64,
    // DATA's data; the field block fragment of HEADERS, PUSH_PROMISE, and
    // CONTINUATION; SETTINGS' parameters; PING's 8 bytes; GOAWAY's debug data;
    // and the payload of a type this side doesn't know.
    data: const u8[:],
    // HEADERS' with PRIORITY_FLAG, and PRIORITY's (§5.3.2, deprecated, but
    // still parsed): the stream depended on, whether exclusively, and a
    // weight of 1 to 256.
    dependency: i64,
    exclusive: bool,
    weight: i64,
    // RST_STREAM's and GOAWAY's error code, and GOAWAY's last stream.
    error: u32,
    last_stream: i64,
    // WINDOW_UPDATE's increment, and PUSH_PROMISE's promised stream.
    increment: i64,
    promised: i64,
}

// What a frame breaks: an error code, 0 for none, and the stream it ends,
// or 0 where it ends the connection (§5.4).
struct H2Error {
    code: u32,
    stream: i64,
}

fn h2_be16(b: const u8[:], at: i64) -> i64 {
    return ((b[at] as i64) << 8) | b[at + 1];
}

fn h2_be24(b: const u8[:], at: i64) -> i64 {
    return ((b[at] as i64) << 16) | ((b[at + 1] as i64) << 8) | b[at + 2];
}

fn h2_be32(b: const u8[:], at: i64) -> i64 {
    return ((b[at] as i64) << 24) | ((b[at + 1] as i64) << 16) | ((b[at + 2] as i64) << 8) | b[at + 3];
}

// A stream identifier of 31 bits at b[at], its reserved bit dropped (§4.1).
fn h2_stream_id(b: const u8[:], at: i64) -> i64 {
    return h2_be32(b, at) & H2_MAX_STREAM;
}

// Whether buf holds the client preface: its length once it does, 0 while buf
// is a part of it, and -1 when it isn't, as for an HTTP/1.1 request.
fn h2_preface(buf: const u8[:]) -> i64 {
    let n = min(buf.len, H2_PREFACE.len);
    guard buf[..n] == H2_PREFACE[..n] else { return -1; }
    return if n == H2_PREFACE.len { n } else { 0 };
}

// Whether a client may open stream id: client streams are odd (§5.1.1).
fn h2_client_stream(id: i64) -> bool {
    return id % 2 == 1;
}

// Parses the frame at the start of buf, whose payload may be max_frame_size
// long, the SETTINGS_MAX_FRAME_SIZE this side advertised. Returns the frame,
// its size with the header, 0 while buf holds only part of it, and what it
// breaks. A frame that breaks one stream is whole, and the connection goes on
// past it; what breaks the connection may leave size 0.
fn h2_parse(buf: const u8[:], max_frame_size: i64 = H2_MIN_FRAME_SIZE) -> H2Frame, i64, H2Error {
    var f = H2Frame { weight: 16, .. };
    guard buf.len >= H2_HEAD else { return f, 0, H2Error { 0, 0 }; }
    f.len = h2_be24(buf, 0);
    f.kind = buf[3];
    f.flags = buf[4];
    f.stream = h2_stream_id(buf, 5);
    // Too long for this side is a connection error for every type. RFC 9113
    // §4.2 allows a stream error only for frames that alter no connection
    // state, and the connection must be closed either way soon after.
    guard f.len <= max_frame_size else { return f, 0, H2Error { H2_FRAME_SIZE_ERROR, 0 }; }
    let size = H2_HEAD + f.len;
    guard buf.len >= size else { return f, 0, H2Error { 0, 0 }; }
    let p = buf[H2_HEAD..size];
    let id = f.stream;

    fn conn(code: u32) -> H2Error { H2Error { code, 0 } }

    // The payload past PADDED's pad length and skip bytes more, and before
    // its padding (§6.1), or the connection error: a payload too short for
    // what it must hold (§4.2), or padding longer than the rest.
    fn unpad(skip: i64) -> const u8[:], u32 {
        let pads = f.flags & H2_PADDED != 0;
        let at = if pads { 1 + skip } else { skip };
        guard p.len >= at else { return "", H2_FRAME_SIZE_ERROR; }
        guard pads else { return p[at..], 0; }
        let padding: i64 = p[0];
        guard padding <= p.len - at else { return "", H2_PROTOCOL_ERROR; }
        return p[at..p.len - padding], 0;
    }

    // A priority's five bytes at p[at] (§6.3), and a stream that depends on
    // itself, a stream error (§5.3.1).
    fn priority(at: i64) -> bool {
        let d = h2_be32(p, at);
        f.exclusive = d >= 0x80000000;
        f.dependency = d & H2_MAX_STREAM;
        f.weight = (p[at + 4] as i64) + 1;
        return f.dependency != id;
    }

    let err = match f.kind {
        H2_DATA => block {
            guard id != 0 else { break conn(H2_PROTOCOL_ERROR); }
            let d, code = unpad(0);
            guard code == 0 else { break conn(code); }
            f.data = d;
            H2Error { 0, 0 }
        },
        H2_HEADERS => block {
            guard id != 0 else { break conn(H2_PROTOCOL_ERROR); }
            let prio = f.flags & H2_PRIORITY_FLAG != 0;
            let d, code = unpad(if prio { 5 } else { 0 });
            guard code == 0 else { break conn(code); }
            f.data = d;
            if prio {
                let at = if f.flags & H2_PADDED != 0 { 1 } else { 0 };
                guard priority(at) else { break H2Error { H2_PROTOCOL_ERROR, id }; }
            }
            H2Error { 0, 0 }
        },
        H2_PRIORITY => block {
            guard id != 0 else { break conn(H2_PROTOCOL_ERROR); }
            guard p.len == 5 else { break H2Error { H2_FRAME_SIZE_ERROR, id }; }
            guard priority(0) else { break H2Error { H2_PROTOCOL_ERROR, id }; }
            H2Error { 0, 0 }
        },
        H2_RST_STREAM => block {
            guard id != 0 else { break conn(H2_PROTOCOL_ERROR); }
            guard p.len == 4 else { break conn(H2_FRAME_SIZE_ERROR); }
            f.error = h2_be32(p, 0) as! u32;
            H2Error { 0, 0 }
        },
        H2_SETTINGS => block {
            guard id == 0 else { break conn(H2_PROTOCOL_ERROR); }
            guard f.flags & H2_ACK == 0 || p.len == 0 else { break conn(H2_FRAME_SIZE_ERROR); }
            guard p.len % 6 == 0 else { break conn(H2_FRAME_SIZE_ERROR); }
            f.data = p;
            H2Error { 0, 0 }
        },
        H2_PUSH_PROMISE => block {
            guard id != 0 else { break conn(H2_PROTOCOL_ERROR); }
            let d, code = unpad(4);
            guard code == 0 else { break conn(code); }
            let at = if f.flags & H2_PADDED != 0 { 1 } else { 0 };
            f.promised = h2_stream_id(p, at);
            f.data = d;
            H2Error { 0, 0 }
        },
        H2_PING => block {
            guard id == 0 else { break conn(H2_PROTOCOL_ERROR); }
            guard p.len == 8 else { break conn(H2_FRAME_SIZE_ERROR); }
            f.data = p;
            H2Error { 0, 0 }
        },
        H2_GOAWAY => block {
            guard id == 0 else { break conn(H2_PROTOCOL_ERROR); }
            guard p.len >= 8 else { break conn(H2_FRAME_SIZE_ERROR); }
            f.last_stream = h2_stream_id(p, 0);
            f.error = h2_be32(p, 4) as! u32;
            f.data = p[8..];
            H2Error { 0, 0 }
        },
        H2_WINDOW_UPDATE => block {
            guard p.len == 4 else { break conn(H2_FRAME_SIZE_ERROR); }
            f.increment = h2_stream_id(p, 0);
            guard f.increment > 0 else { break H2Error { H2_PROTOCOL_ERROR, id }; }
            H2Error { 0, 0 }
        },
        H2_CONTINUATION => block {
            guard id != 0 else { break conn(H2_PROTOCOL_ERROR); }
            f.data = p;
            H2Error { 0, 0 }
        },
        // A type this side doesn't know is ignored (§4.1, §5.5).
        _ => block {
            f.data = p;
            H2Error { 0, 0 }
        },
    };
    return f, size, err;
}

// Applies a SETTINGS frame's parameters to s, the peer's settings, in order
// (§6.5.3). Returns the connection error a value is, or H2_NO_ERROR.
// Parameters this side doesn't know are ignored.
fn h2_apply_settings(s: H2Settings&, params: const u8[:]) -> u32 {
    for k in 0..params.len / 6 {
        let at = k * 6;
        let id = h2_be16(params, at);
        let v = h2_be32(params, at + 2);
        match id {
            H2_SETTINGS_HEADER_TABLE_SIZE => { s.header_table_size = v; },
            H2_SETTINGS_ENABLE_PUSH => {
                guard v <= 1 else { return H2_PROTOCOL_ERROR; }
                s.enable_push = v == 1;
            },
            H2_SETTINGS_MAX_CONCURRENT_STREAMS => { s.max_concurrent_streams = v; },
            H2_SETTINGS_INITIAL_WINDOW_SIZE => {
                guard v <= H2_MAX_WINDOW else { return H2_FLOW_CONTROL_ERROR; }
                s.initial_window_size = v;
            },
            H2_SETTINGS_MAX_FRAME_SIZE => {
                guard v >= H2_MIN_FRAME_SIZE && v <= H2_MAX_FRAME_SIZE else { return H2_PROTOCOL_ERROR; }
                s.max_frame_size = v;
            },
            H2_SETTINGS_MAX_HEADER_LIST_SIZE => { s.max_header_list_size = v; },
            H2_SETTINGS_ENABLE_CONNECT_PROTOCOL => {
                guard v <= 1 else { return H2_PROTOCOL_ERROR; }
                s.connect_protocol = v == 1;
            },
            H2_SETTINGS_NO_RFC7540_PRIORITIES => {
                guard v <= 1 else { return H2_PROTOCOL_ERROR; }
                s.no_rfc7540_priorities = v == 1;
            },
            _ => {},
        }
    }
    return H2_NO_ERROR;
}

fn h2_put32(out: u8[>..]&, v: i64) {
    out.push((v >> 24) as! u8);
    out.push((v >> 16) as! u8);
    out.push((v >> 8) as! u8);
    out.push(v as! u8);
}

// Appends a frame header (§4.1); the payload follows it.
fn h2_head(out: u8[>..]&, len: i64, kind: u8, flags: u8, stream: i64) {
    out.push((len >> 16) as! u8);
    out.push((len >> 8) as! u8);
    out.push(len as! u8);
    out.push(kind);
    out.push(flags);
    h2_put32(out, stream & H2_MAX_STREAM);
}

// Appends a DATA frame of data, which must fit the peer's
// SETTINGS_MAX_FRAME_SIZE and the windows (§6.1).
fn h2_write_data(out: u8[>..]&, stream: i64, data: const u8[:], end_stream: bool) {
    h2_head(out, data.len, H2_DATA, if end_stream { H2_END_STREAM } else { 0 }, stream);
    out.append(data);
}

// Appends the field block fb as a HEADERS frame (or PUSH_PROMISE's, below)
// and as many CONTINUATIONs as frames of the peer's max_frame_size need
// (§6.2, §6.10).
fn h2_write_headers(out: u8[>..]&, stream: i64, fb: const u8[:], end_stream: bool,
                    max_frame_size: i64 = H2_MIN_FRAME_SIZE) {
    let n = min(fb.len, max_frame_size);
    var flags: u8 = if end_stream { H2_END_STREAM } else { 0 };
    if n == fb.len { flags |= H2_END_HEADERS; }
    h2_head(out, n, H2_HEADERS, flags, stream);
    out.append(fb[..n]);
    h2_write_continuations(out, stream, fb[n..], max_frame_size);
}

fn h2_write_continuations(out: u8[>..]&, stream: i64, rest: const u8[:], max_frame_size: i64) {
    var at = 0;
    while at < rest.len {
        let n = min(rest.len - at, max_frame_size);
        let flags: u8 = if at + n == rest.len { H2_END_HEADERS } else { 0 };
        h2_head(out, n, H2_CONTINUATION, flags, stream);
        out.append(rest[at..at + n]);
        at += n;
    }
}

// Appends a PRIORITY frame (§6.3), weight from 1 to 256.
fn h2_write_priority(out: u8[>..]&, stream: i64, dependency: i64, exclusive: bool, weight: i64) {
    h2_head(out, 5, H2_PRIORITY, 0, stream);
    h2_put32(out, (dependency & H2_MAX_STREAM) | (if exclusive { 0x80000000 } else { 0 }));
    out.push((weight - 1) as u8);
}

fn h2_write_rst_stream(out: u8[>..]&, stream: i64, code: u32) {
    h2_head(out, 4, H2_RST_STREAM, 0, stream);
    h2_put32(out, code);
}

// Appends a SETTINGS frame with each of s that differs from its initial
// value (§6.5).
fn h2_write_settings(out: u8[>..]&, s: H2Settings) {
    let d = H2Settings { .. };
    var params: u8[..48] = [];
    fn param(id: i64, v: i64) {
        params.push((id >> 8) as! u8);
        params.push(id as! u8);
        params.push((v >> 24) as! u8);
        params.push((v >> 16) as! u8);
        params.push((v >> 8) as! u8);
        params.push(v as! u8);
    }
    if s.header_table_size != d.header_table_size {
        param(H2_SETTINGS_HEADER_TABLE_SIZE, s.header_table_size);
    }
    if s.enable_push != d.enable_push {
        param(H2_SETTINGS_ENABLE_PUSH, if s.enable_push { 1 } else { 0 });
    }
    if s.max_concurrent_streams != d.max_concurrent_streams {
        param(H2_SETTINGS_MAX_CONCURRENT_STREAMS, s.max_concurrent_streams);
    }
    if s.initial_window_size != d.initial_window_size {
        param(H2_SETTINGS_INITIAL_WINDOW_SIZE, s.initial_window_size);
    }
    if s.max_frame_size != d.max_frame_size {
        param(H2_SETTINGS_MAX_FRAME_SIZE, s.max_frame_size);
    }
    if s.max_header_list_size != d.max_header_list_size {
        param(H2_SETTINGS_MAX_HEADER_LIST_SIZE, s.max_header_list_size);
    }
    if s.connect_protocol != d.connect_protocol {
        param(H2_SETTINGS_ENABLE_CONNECT_PROTOCOL, if s.connect_protocol { 1 } else { 0 });
    }
    if s.no_rfc7540_priorities != d.no_rfc7540_priorities {
        param(H2_SETTINGS_NO_RFC7540_PRIORITIES, if s.no_rfc7540_priorities { 1 } else { 0 });
    }
    h2_head(out, params.len, H2_SETTINGS, 0, 0);
    out.append(params);
}

fn h2_write_settings_ack(out: u8[>..]&) {
    h2_head(out, 0, H2_SETTINGS, H2_ACK, 0);
}

// Appends a PUSH_PROMISE for promised on stream, with the field block fb and
// its CONTINUATIONs (§6.6).
fn h2_write_push_promise(out: u8[>..]&, stream: i64, promised: i64, fb: const u8[:],
                         max_frame_size: i64 = H2_MIN_FRAME_SIZE) {
    let n = min(fb.len, max_frame_size - 4);
    let flags: u8 = if n == fb.len { H2_END_HEADERS } else { 0 };
    h2_head(out, 4 + n, H2_PUSH_PROMISE, flags, stream);
    h2_put32(out, promised & H2_MAX_STREAM);
    out.append(fb[..n]);
    h2_write_continuations(out, stream, fb[n..], max_frame_size);
}

// Appends a PING of 8 bytes, or its acknowledgment, which echoes them (§6.7).
fn h2_write_ping(out: u8[>..]&, data: const u8[:], ack: bool) {
    assert(data.len == 8);
    h2_head(out, 8, H2_PING, if ack { H2_ACK } else { 0 }, 0);
    out.append(data);
}

fn h2_write_goaway(out: u8[>..]&, last_stream: i64, code: u32, debug: const u8[:] = "") {
    h2_head(out, 8 + debug.len, H2_GOAWAY, 0, 0);
    h2_put32(out, last_stream & H2_MAX_STREAM);
    h2_put32(out, code);
    out.append(debug);
}

// Appends a WINDOW_UPDATE of 1 to H2_MAX_WINDOW bytes, for the connection
// where stream is 0 (§6.9).
fn h2_write_window_update(out: u8[>..]&, stream: i64, increment: i64) {
    h2_head(out, 4, H2_WINDOW_UPDATE, 0, stream);
    h2_put32(out, increment & H2_MAX_WINDOW);
}
