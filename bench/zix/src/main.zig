// /plaintext and /json on zix.Http1, configured as HttpArena's zix entry runs
// it (MDA2AV/HttpArena frameworks/zix at 0720ee5): the .URING dispatch model,
// one shared-nothing worker per thread with its own SO_REUSEPORT listener and
// io_uring loop, the comptime Router, and the entry's engine settings.
// Handlers frame their own responses and append them to the engine's
// per-connection send sink with writeAllFD, as the entry's /pipeline and /json
// handlers do, so a pipelined batch leaves as one send; /json serializes with
// jzon's .GENERATED strategy, as the entry's does.
//
// What the entry doesn't do that this benchmark needs: the Server field, which
// zix's own response helpers don't write, and the Date field, which the entry
// turns off; 405 for other methods on the two paths; WORKERS for the worker
// count (the entry starts one per CPU); and the port as the first argument.
// The entry's TLS listener, compression, static files, and database lanes are
// left out.
//
//     WORKERS=n bench-zix [port]

const std = @import("std");
const linux = std.os.linux;
const zix = @import("zix");

const Message = struct { message: []const u8 };

// The Date field's value, formatted when the second changes. Each worker is a
// thread, so each keeps its own.
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

// Response assembly; writeAllFD copies it into the send sink before returning.
threadlocal var out_buf: [512]u8 = undefined;

fn put(pos: *usize, bytes: []const u8) void {
    @memcpy(out_buf[pos.*..][0..bytes.len], bytes);
    pos.* += bytes.len;
}

/// Writes a response with TechEmpower's fields. `status` ends in CRLF, and so
/// does each line of `fields`.
fn respond(fd: std.posix.fd_t, status: []const u8, fields: []const u8, body: []const u8, head_only: bool) !void {
    var pos: usize = 0;
    put(&pos, "HTTP/1.1 ");
    put(&pos, status);
    put(&pos, "Server: zix\r\nDate: ");
    put(&pos, date());
    put(&pos, "\r\n");
    put(&pos, fields);
    put(&pos, "Content-Length: ");
    var len_buf: [20]u8 = undefined;
    put(&pos, std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch unreachable);
    put(&pos, "\r\n\r\n");
    if (!head_only) put(&pos, body);
    try zix.Http1.writeAllFD(fd, out_buf[0..pos]);
}

fn allowed(req: *zix.Http1.Request) !bool {
    switch (req.method()) {
        .GET, .HEAD => return true,
        else => {
            try respond(req.fd, "405 Method Not Allowed\r\n", "Allow: GET, HEAD\r\n", "", false);
            return false;
        },
    }
}

fn plaintext(req: *zix.Http1.Request, _: *zix.Http1.Response, _: *zix.Http1.Context) !void {
    if (!try allowed(req)) return;
    try respond(req.fd, "200 OK\r\n", "Content-Type: text/plain\r\n", "Hello, World!", req.method() == .HEAD);
}

fn json(req: *zix.Http1.Request, _: *zix.Http1.Response, _: *zix.Http1.Context) !void {
    if (!try allowed(req)) return;
    var body: [64]u8 = undefined;
    const n = try zix.jzon.serialize(&body, Message{ .message = "Hello, World!" }, .{ .strategy = .GENERATED });
    try respond(req.fd, "200 OK\r\n", "Content-Type: application/json\r\n", body[0..n], req.method() == .HEAD);
}

const Routes = zix.Http1.Router(&[_]zix.Http1.Route{
    .{ .path = "/plaintext", .handler = plaintext },
    .{ .path = "/json", .handler = json },
});

pub fn main(process: std.process.Init) !void {
    const args = try process.minimal.args.toSlice(process.arena.allocator());
    const port: u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 8080;
    // 0 is zix's one worker per CPU.
    const workers: usize = if (process.environ_map.get("WORKERS")) |v| try std.fmt.parseInt(usize, v, 10) else 0;
    const n = if (workers > 0) workers else std.Thread.getCpuCount() catch 8;

    // The entry's settings, its park ring sized as it sizes it: 16,384
    // connections, its deepest scenario, spread over the workers.
    var server = zix.Http1.Server.init(Routes.dispatch, .{
        .io = process.io,
        .ip = "0.0.0.0",
        .port = port,
        .workers = workers,
        .dispatch_model = .URING,
        .max_response_headers = .{ .CUSTOM = 8 },
        .kernel_backlog = 16 * 1024,
        .max_recv_buf = 8 * 1024,
        .max_request_body = 24 * 1024 * 1024,
        .uring_send_buf_size = 16 * 1024,
        .uring_idle_pool_floor = 16,
        .uring_idle_pool_ceiling = 1 * 1024,
        .process_queue_len = @max(512, 16 * 1024 / n),
    });
    defer server.deinit();

    std.debug.print("zix: {d} workers on port {d}\n", .{ n, port });
    try server.run();
}
