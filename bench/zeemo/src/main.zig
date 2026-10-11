// HttpArena's zeemo entry (MDA2AV/HttpArena frameworks/zeemo/src/main.zig at
// 0720ee5): shared-nothing workers, each pinned to one CPU of the affinity
// mask, with its own SO_REUSEPORT listener and io_uring ring; multishot
// accept; every pipelined request in a recv answered with one batched send
// from the connection's inline buffer. Its ring, parser, buffers, and send
// path are unchanged. What this repository's benchmark needs on top:
//
// - A thread per worker where the entry forks a process per worker, so
//   bench/run.sh's CPU time and peak RSS, read from one process, cover every
//   worker, and stopping that process stops them all. The per-worker state
//   the fork kept apart is threadlocal, and the fd table is larger (MAX_FD).
// - WORKERS for the worker count (the entry takes the CPUs in its mask) and the
//   port as the first argument. Workers are pinned round-robin over the mask.
// - TechEmpower's /plaintext and /json (handlers.zig) in place of the entry's
//   routes, so the JSON-only big-buffer pool and the dataset are gone.
//
//     WORKERS=n bench-zeemo [port]

const std = @import("std");
const linux = std.os.linux;
const IoUring = linux.IoUring;
const builtin = @import("builtin");

const http = @import("http.zig");
const handlers = @import("handlers.zig");

/// Highest accepted fd. Reserves an O(1) lookup table; Linux assigns
/// fresh fds starting from the lowest free slot. The workers share one fd
/// table, so fds reach the process's connection count: this is the
/// `ulimit -n` bench/run.sh sets, where the entry's 4,096 per process would
/// refuse connections at run.sh's 4,096.
const MAX_FD: usize = 65536;
const RING_ENTRIES = 4096;
const LISTEN_BACKLOG: u32 = 1024;

/// Per-connection inline write buffer. Sized for the small-response
/// profiles; typical response is ~130 B, so 4 KiB fits a 16-deep pipeline
/// batch with headroom.
const WRITE_INLINE = 4 * 1024;
/// When accumulated inline bytes exceed this in a single drain pass we
/// flush before dispatching another request, leaving room for one more
/// pipelined response.
const WRITE_INLINE_FLUSH_AT: u32 = WRITE_INLINE - 256;

const Op = enum(u8) {
    accept = 1,
    recv = 2,
    send = 3,
    close = 4,
};

/// user_data = (op << 32) | fd. The fd both identifies the operation and
/// is the lookup key into `slot_table`.
inline fn ud(op: Op, fd: linux.fd_t) u64 {
    return (@as(u64, @intFromEnum(op)) << 32) | @as(u64, @as(u32, @bitCast(fd)));
}
inline fn udOp(u: u64) Op {
    return @enumFromInt(@as(u8, @intCast(u >> 32)));
}
inline fn udFd(u: u64) linux.fd_t {
    return @as(linux.fd_t, @bitCast(@as(u32, @truncate(u))));
}

const Slot = struct {
    fd: linux.fd_t,
    parser: http.Parser = .{},
    /// Inline buffer for responses. Pipelined batches concatenate here.
    write_inline: [WRITE_INLINE]u8 = undefined,
    send_len: u32 = 0,
    send_off: u32 = 0,
    close_after_send: bool = false,
};

/// fd-indexed pointer table, null for free fds. Threads share the fd table,
/// so each worker keeps its own and only ever sees the fds it accepted.
threadlocal var slot_table: [MAX_FD]?*Slot = .{null} ** MAX_FD;

/// `page_allocator` returns pages via mmap and releases them via munmap on
/// free, so freed Slots actually give memory back to the kernel.
const slot_allocator = std.heap.page_allocator;

fn getSlot(fd: linux.fd_t) ?*Slot {
    const fdu: usize = @intCast(fd);
    if (fdu >= MAX_FD) return null;
    return slot_table[fdu];
}

fn allocSlotFor(fd: linux.fd_t) ?*Slot {
    const fdu: usize = @intCast(fd);
    if (fdu >= MAX_FD) return null;
    const slot = slot_allocator.create(Slot) catch return null;
    slot.* = .{ .fd = fd };
    slot_table[fdu] = slot;
    return slot;
}

fn freeSlotFor(fd: linux.fd_t) void {
    const fdu: usize = @intCast(fd);
    if (fdu >= MAX_FD) return;
    if (slot_table[fdu]) |slot| {
        slot_allocator.destroy(slot);
        slot_table[fdu] = null;
    }
}

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .linux) @panic("zeemo only runs on Linux (io_uring)");

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port: u16 = if (args.len > 1) try std.fmt.parseInt(u16, args[1], 10) else 8080;

    // Ignore SIGPIPE so a peer closing mid-send doesn't kill us; the send()
    // CQE will surface as -EPIPE instead.
    var sa: linux.Sigaction = .{
        .handler = .{ .handler = linux.SIG.IGN },
        .mask = std.mem.zeroes(linux.sigset_t),
        .flags = 0,
    };
    _ = linux.sigaction(linux.SIG.PIPE, &sa, null);

    var cpu_set: linux.cpu_set_t = undefined;
    if (linux.sched_getaffinity(0, @sizeOf(linux.cpu_set_t), &cpu_set) != 0) {
        return error.SchedGetAffinityFailed;
    }
    var cpu_list: [256]u32 = undefined;
    const n_cpus = collectCpus(&cpu_set, &cpu_list);
    if (n_cpus == 0) return error.NoAllowedCpus;
    const n_workers: u32 = if (init.environ_map.get("WORKERS")) |v| try std.fmt.parseInt(u32, v, 10) else n_cpus;
    std.debug.print("zeemo: {d} workers on port {d}\n", .{ n_workers, port });

    // The main thread becomes worker 0.
    var i: u32 = 1;
    while (i < n_workers) : (i += 1) {
        const t = try std.Thread.spawn(.{}, workerThread, .{ i, cpu_list[i % n_cpus], port });
        t.detach();
    }
    pinToCpu(cpu_list[0]);
    try workerMain(port);
}

fn workerThread(worker_id: u32, cpu: u32, port: u16) void {
    pinToCpu(cpu);
    workerMain(port) catch |err| {
        std.log.err("worker {d}: {t}", .{ worker_id, err });
        std.process.exit(1);
    };
}

fn collectCpus(set: *const linux.cpu_set_t, list: []u32) u32 {
    var n: u32 = 0;
    for (set, 0..) |word, word_idx| {
        var w = word;
        while (w != 0) : (w &= w - 1) {
            const cpu: u32 = @intCast(word_idx * @bitSizeOf(usize) + @ctz(w));
            if (n >= list.len) return n;
            list[n] = cpu;
            n += 1;
        }
    }
    return n;
}

fn pinToCpu(cpu: u32) void {
    var set: linux.cpu_set_t = std.mem.zeroes(linux.cpu_set_t);
    const word_idx = cpu / @bitSizeOf(usize);
    const bit_idx: u6 = @intCast(cpu % @bitSizeOf(usize));
    set[word_idx] |= @as(usize, 1) << bit_idx;
    linux.sched_setaffinity(0, &set) catch {};
}

fn workerMain(port: u16) !void {
    const listen_fd = try makeListener(port);
    defer _ = linux.close(listen_fd);

    var ring = try IoUring.init(RING_ENTRIES, 0);
    defer ring.deinit();

    _ = try ring.accept_multishot(ud(.accept, 0), listen_fd, null, null, 0);

    var cqes: [256]linux.io_uring_cqe = undefined;
    while (true) {
        _ = try ring.submit_and_wait(1);
        const n = try ring.copy_cqes(&cqes, 0);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            handleCqe(&ring, listen_fd, &cqes[i]) catch |err| {
                std.log.warn("cqe handler: {t}", .{err});
            };
        }
    }
}

fn makeListener(port: u16) !linux.fd_t {
    const fd = try syscall(linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0));
    errdefer _ = linux.close(@intCast(fd));

    const one: c_int = 1;
    const one_bytes = std.mem.asBytes(&one);
    try std.posix.setsockopt(@intCast(fd), linux.SOL.SOCKET, linux.SO.REUSEADDR, one_bytes);
    try std.posix.setsockopt(@intCast(fd), linux.SOL.SOCKET, linux.SO.REUSEPORT, one_bytes);
    try std.posix.setsockopt(@intCast(fd), linux.IPPROTO.TCP, linux.TCP.NODELAY, one_bytes);

    var addr: linux.sockaddr.in = .{
        .family = linux.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = 0, // INADDR_ANY
        .zero = [_]u8{0} ** 8,
    };
    try syscallVoid(linux.bind(@intCast(fd), @ptrCast(&addr), @sizeOf(@TypeOf(addr))));
    try syscallVoid(linux.listen(@intCast(fd), LISTEN_BACKLOG));
    return @intCast(fd);
}

fn syscall(r: usize) !usize {
    return switch (linux.errno(r)) {
        .SUCCESS => r,
        else => |e| switch (e) {
            .ACCES => error.AccessDenied,
            .ADDRINUSE => error.AddressInUse,
            .ADDRNOTAVAIL => error.AddressNotAvailable,
            .INVAL => error.InvalidArgument,
            .MFILE => error.ProcessFdQuotaExceeded,
            .NFILE => error.SystemFdQuotaExceeded,
            .NOBUFS => error.SystemResources,
            else => error.UnexpectedSyscallError,
        },
    };
}

fn syscallVoid(r: usize) !void {
    _ = try syscall(r);
}

fn handleCqe(ring: *IoUring, listen_fd: linux.fd_t, cqe: *linux.io_uring_cqe) !void {
    switch (udOp(cqe.user_data)) {
        .accept => try handleAccept(ring, listen_fd, cqe),
        .recv => try handleRecv(ring, cqe),
        .send => try handleSend(ring, cqe),
        .close => freeSlotFor(udFd(cqe.user_data)),
    }
}

fn handleAccept(ring: *IoUring, listen_fd: linux.fd_t, cqe: *linux.io_uring_cqe) !void {
    const more = (cqe.flags & linux.IORING_CQE_F_MORE) != 0;
    if (cqe.res < 0) {
        if (!more) _ = try ring.accept_multishot(ud(.accept, 0), listen_fd, null, null, 0);
        return;
    }
    const fd: linux.fd_t = @intCast(cqe.res);
    const slot = allocSlotFor(fd) orelse {
        _ = linux.close(fd);
        if (!more) _ = try ring.accept_multishot(ud(.accept, 0), listen_fd, null, null, 0);
        return;
    };
    const buf = slot.parser.recv_slot();
    _ = try ring.recv(ud(.recv, fd), fd, .{ .buffer = buf }, 0);

    // If multishot fell off, re-arm.
    if (!more) _ = try ring.accept_multishot(ud(.accept, 0), listen_fd, null, null, 0);
}

fn handleRecv(ring: *IoUring, cqe: *linux.io_uring_cqe) !void {
    const fd = udFd(cqe.user_data);
    const slot = getSlot(fd) orelse return; // already freed — race with close CQE
    if (cqe.res <= 0) {
        _ = try ring.close(ud(.close, fd), fd);
        return;
    }
    try drainAndSend(ring, slot, @intCast(cqe.res));
}

fn handleSend(ring: *IoUring, cqe: *linux.io_uring_cqe) !void {
    const fd = udFd(cqe.user_data);
    const slot = getSlot(fd) orelse return;
    if (cqe.res <= 0) {
        _ = try ring.close(ud(.close, fd), fd);
        return;
    }
    const n: u32 = @intCast(cqe.res);
    slot.send_off += n;
    if (slot.send_off < slot.send_len) {
        const tail = slot.write_inline[slot.send_off..slot.send_len];
        _ = try ring.send(ud(.send, fd), fd, tail, linux.MSG.NOSIGNAL);
        return;
    }
    if (slot.close_after_send) {
        _ = try ring.close(ud(.close, fd), fd);
        return;
    }
    try drainAndSend(ring, slot, 0);
}

/// Drain as many complete requests as fit in the inline write buffer,
/// then submit one send for the whole batch. If no requests are ready, arm
/// a recv instead.
///
/// `initial_feed_n` is the byte count just delivered by recv (0 when called
/// from handleSend completion).
fn drainAndSend(ring: *IoUring, slot: *Slot, initial_feed_n: u32) !void {
    var inline_pos: u32 = 0;
    var feed_n = initial_feed_n;

    while (true) {
        const result = slot.parser.feed(feed_n);
        feed_n = 0;
        switch (result) {
            .protocol_error => {
                if (inline_pos > 0) {
                    submitInline(ring, slot, inline_pos, true) catch {};
                } else {
                    _ = try ring.close(ud(.close, slot.fd), slot.fd);
                }
                return;
            },
            .need_more => {
                if (inline_pos > 0) {
                    try submitInline(ring, slot, inline_pos, false);
                    return;
                }
                const buf = slot.parser.recv_slot();
                if (buf.len == 0) {
                    _ = try ring.close(ud(.close, slot.fd), slot.fd);
                    return;
                }
                _ = try ring.recv(ud(.recv, slot.fd), slot.fd, .{ .buffer = buf }, 0);
                return;
            },
            .ready => |req| {
                const resp = handlers.handle(req, slot.write_inline[inline_pos..]);
                inline_pos += @intCast(resp.bytes.len);
                slot.parser.reset(slot.parser.consumed());
                if (resp.close) {
                    try submitInline(ring, slot, inline_pos, true);
                    return;
                }
                if (inline_pos > WRITE_INLINE_FLUSH_AT) {
                    try submitInline(ring, slot, inline_pos, false);
                    return;
                }
                // Loop: feed(0) for the next pipelined request.
            },
        }
    }
}

fn submitInline(ring: *IoUring, slot: *Slot, len: u32, close_after: bool) !void {
    slot.send_len = len;
    slot.send_off = 0;
    slot.close_after_send = close_after;
    _ = try ring.send(ud(.send, slot.fd), slot.fd, slot.write_inline[0..len], linux.MSG.NOSIGNAL);
}
