// TechEmpower's /plaintext and /json in place of the entry's handlers.zig,
// with its contract: each response is written whole into `out`, the
// connection's inline write buffer, so pipelined responses concatenate.

const std = @import("std");
const linux = std.os.linux;
const http = @import("http.zig");

pub const Response = struct {
    /// Full HTTP/1.1 response bytes, ready to send.
    bytes: []const u8,
    close: bool,
};

const Message = struct { message: []const u8 };

// The Date field's value, formatted when the second changes, per worker thread.
threadlocal var date_buf: [29]u8 = undefined;
threadlocal var date_secs: i64 = -1;

fn date() []const u8 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    const secs: i64 = ts.sec;
    if (secs != date_secs) {
        const es = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
        const day = es.getEpochDay();
        const yd = day.calculateYearDay();
        const md = yd.calculateMonthDay();
        const ds = es.getDaySeconds();
        // 1970-01-01 was a Thursday.
        const wd = (day.day + 4) % 7;
        const names = "SunMonTueWedThuFriSat";
        const months = "JanFebMarAprMayJunJulAugSepOctNovDec";
        const m = (@as(usize, @intFromEnum(md.month)) - 1) * 3;
        _ = std.fmt.bufPrint(&date_buf, "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
            names[wd * 3 ..][0..3],
            md.day_index + 1,
            months[m..][0..3],
            yd.year,
            ds.getHoursIntoDay(),
            ds.getMinutesIntoHour(),
            ds.getSecondsIntoMinute(),
        }) catch unreachable;
        date_secs = secs;
    }
    return &date_buf;
}

pub fn handle(req: http.Request, out: []u8) Response {
    const plaintext = std.mem.eql(u8, req.path, "/plaintext");
    const json = std.mem.eql(u8, req.path, "/json");
    if (!plaintext and !json)
        return respond(out, "404 Not Found", "", "", req.close);
    // The entry's parser reads GET and POST; HEAD and the rest come as OTHER.
    if (req.method != .GET)
        return respond(out, "405 Method Not Allowed", "Allow: GET\r\n", "", req.close);
    if (plaintext)
        return respond(out, "200 OK", "Content-Type: text/plain\r\n", "Hello, World!", req.close);
    var body: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&body);
    std.json.Stringify.value(Message{ .message = "Hello, World!" }, .{}, &w) catch unreachable;
    return respond(out, "200 OK", "Content-Type: application/json\r\n", w.buffered(), req.close);
}

/// `fields` ends in CRLF.
fn respond(out: []u8, status: []const u8, fields: []const u8, body: []const u8, close: bool) Response {
    const close_hdr: []const u8 = if (close) "Connection: close\r\n" else "";
    const n = std.fmt.bufPrint(out,
        "HTTP/1.1 {s}\r\nServer: zeemo\r\nDate: {s}\r\n{s}Content-Length: {d}\r\n{s}\r\n{s}",
        .{ status, date(), fields, body.len, close_hdr, body }) catch unreachable;
    return .{ .bytes = n, .close = close };
}
