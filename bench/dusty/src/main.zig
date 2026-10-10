// /plaintext and /json on dusty and the zio runtime, configured as HttpArena's
// dusty entry runs it (MDA2AV/HttpArena frameworks/dusty, at the commit in
// bench/build.sh): one dusty Server on a work-stealing zio runtime, with the
// listener's default accept loops and the entry's connection limit. zio runs
// on io_uring where the kernel has it and falls back to epoll.
//
// What the entry doesn't do that this benchmark needs: the Server and Date
// fields, 405 for other methods on the two paths, WORKERS for the executor
// count (the entry takes the CPU count), and the port as the first argument.
//
//     WORKERS=n bench-dusty [port]

const std = @import("std");
const zio = @import("zio");
const http = @import("dusty");

const Message = struct { message: []const u8 };

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

fn fields(req: *http.Request, res: *http.Response) !void {
    try res.header("Server", "dusty");
    try res.header("Date", try date(req));
}

fn plaintext(req: *http.Request, res: *http.Response) !void {
    try fields(req, res);
    try res.header("Content-Type", "text/plain");
    res.body = "Hello, World!";
}

fn json(req: *http.Request, res: *http.Response) !void {
    try fields(req, res);
    try res.header("Content-Type", "application/json");
    res.body = try std.json.Stringify.valueAlloc(req.arena, Message{ .message = "Hello, World!" }, .{});
}

fn notAllowed(req: *http.Request, res: *http.Response) !void {
    try fields(req, res);
    try res.header("Allow", "GET, HEAD");
    res.status = .method_not_allowed;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port: u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 8080;
    const executors: @FieldType(zio.RuntimeOptions, "executors") = if (init.environ_map.get("WORKERS")) |v|
        .exact(try std.fmt.parseInt(u8, v, 10))
    else
        .auto;

    var rt = try zio.Runtime.init(init.gpa, .{ .executors = executors });
    defer rt.deinit();

    const listeners = [_]http.Listener{
        .{ .address = .{ .ip = try std.Io.net.IpAddress.parse("0.0.0.0", port) } },
    };
    var server = http.Server(void).init(init.gpa, rt.io(), .{
        .listeners = &listeners,
        .max_connections = 65_536,
    }, {});
    defer server.deinit();

    for ([_][]const u8{ "/plaintext", "/json" }) |path| {
        server.router.post(path, notAllowed);
        server.router.put(path, notAllowed);
        server.router.delete(path, notAllowed);
        server.router.patch(path, notAllowed);
    }
    server.router.get("/plaintext", plaintext);
    server.router.get("/json", json);

    std.debug.print("dusty: {d} workers on port {d}\n", .{ executors.resolve(), port });
    try server.run();
}
