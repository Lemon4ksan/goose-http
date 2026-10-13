// The REST benchmark (task 021) on dusty and the zio runtime, as
// bench/dusty serves /plaintext and /json: one dusty Server on a
// work-stealing zio runtime with WORKERS executors, and the Server and Date
// fields. The routes are rest.zig's, behind one handler that dusty's router
// gives every path, as xitca-web's REST server is one service: rest.zig
// matches the paths itself, so that each tier's errors are answered as the
// other servers answer them.
//
// Tiers A to C read a request's body whole, with Request.body. Tier D reads
// the CSV and the multipart body as they arrive, through Request.reader,
// which undoes chunked framing, and joins the batch and the form.
//
//     REST_DATA=DIR TIER=a|b|c|d WORKERS=n [JSON=template] rest-dusty [port]

const std = @import("std");
const zio = @import("zio");
const http = @import("dusty");
const rest = @import("rest.zig");

// The Date field, formatted once a second per thread. A handler copies it into
// its arena: the response is sent after the handler returns, by which time
// another handler on this thread may have rewritten the buffer.
threadlocal var date_buf: [29]u8 = undefined;
threadlocal var date_secs: i64 = -1;

fn date(req: *http.Request) ![]const u8 {
    const now = std.Io.Timestamp.now(req.io, .real);
    const secs: i64 = @intCast(@divFloor(now.nanoseconds, std.time.ns_per_s));
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
        _ = try std.fmt.bufPrint(&date_buf, "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
            names[wd * 3 ..][0..3],
            md.day_index + 1,
            months[m..][0..3],
            yd.year,
            ds.getHoursIntoDay(),
            ds.getMinutesIntoHour(),
            ds.getSecondsIntoMinute(),
        });
        date_secs = secs;
    }
    return req.arena.dupe(u8, &date_buf);
}

fn methodOf(m: http.Method) rest.Method {
    return switch (m) {
        .get => .get,
        .head => .head,
        .post => .post,
        .patch => .patch,
        else => .other,
    };
}

fn handle(req: *http.Request, res: *http.Response) !void {
    try res.header("Server", "dusty");
    try res.header("Date", try date(req));
    var head = rest.Head.init(methodOf(req.method), req.url);
    var fields = req.headers.iterator();
    while (fields.next()) |f| head.field(f.key, f.value);
    const ctx: rest.Ctx = .{ .arena = req.arena, .io = req.io };
    const r = if (rest.writes.isWrites(head.path)) try writes(req, ctx, &head) else blk: {
        // Only writes carry a body here; dusty drains any other.
        const body = if (head.method == .post or head.method == .patch)
            (req.body() catch |e| switch (e) {
                error.BodyTooBig => break :blk rest.Resp{ .status = 413, .close = true },
                else => return e,
            }) orelse ""
        else
            "";
        break :blk try rest.handle(ctx, &head, body);
    };
    res.status = try http.Status.fromCode(r.status);
    if (r.json) try res.header("Content-Type", "application/json");
    res.body = r.body;
    if (r.close) {
        // dusty drains a body of a known length after the handler before it
        // sends the response, and the peer may never send the rest of one
        // refused for its length, so the 413 goes now.
        res.keepalive = false;
        try res.write();
    }
}

// Tier D: the body read as rest.writes takes it, and the rest of it dropped
// after an answer that comes before its end.
fn writes(req: *http.Request, ctx: rest.Ctx, head: *const rest.Head) !rest.Resp {
    var body = try req.reader(&.{});
    const piece = try ctx.arena.alloc(u8, 64 << 10);
    var start = try rest.writes.start(ctx, head);
    const answer: rest.Resp = switch (start) {
        .answer => |a| a,
        .read => |*w| blk: {
            while (try readPiece(&body, piece)) |n| {
                if (try w.push(piece[0..n])) |a| break :blk a;
            }
            return w.finish();
        },
    };
    // discardRemaining on dusty's body reader doesn't return once the body
    // has ended, so the rest is read into piece instead.
    if (!answer.close) while (try readPiece(&body, piece)) |_| {};
    return answer;
}

// Reads what has arrived of the body into piece, up to its length, or null
// at the body's end.
fn readPiece(body: anytype, piece: []u8) !?usize {
    var vec = [1][]u8{piece};
    return body.interface.readVec(&vec) catch |e| switch (e) {
        error.EndOfStream => null,
        error.ReadFailed => body.err orelse error.Unexpected,
    };
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const cfg = rest.init(a, init.io, init.environ_map, args, "dusty");

    var rt = try zio.Runtime.init(init.gpa, .{ .executors = .exact(cfg.workers) });
    defer rt.deinit();

    const listeners = [_]http.Listener{
        .{ .address = .{ .ip = try std.Io.net.IpAddress.parse("0.0.0.0", cfg.port) } },
    };
    var server = http.Server(void).init(init.gpa, rt.io(), .{
        .listeners = &listeners,
        .max_connections = 65_536,
        .request = .{ .max_body_size = rest.writes.import_limit },
    }, {});
    defer server.deinit();

    server.router.any("/*path", handle);
    try server.run();
}
