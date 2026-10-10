// HttpArena's dusty entry's build.zig, without the dependencies only its
// other endpoints use (json, pg, zt).
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const dusty_dep = b.dependency("dusty", .{
        .target = target,
        .optimize = optimize,
    });
    const dusty_mod = dusty_dep.module("dusty");

    const zio_dep = b.dependency("zio", .{
        .target = target,
        .optimize = optimize,
    });
    const zio_mod = zio_dep.module("zio");

    dusty_mod.addImport("zio", zio_mod);

    const exe = b.addExecutable(.{
        .name = "bench-dusty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
        }),
    });
    exe.root_module.addImport("dusty", dusty_mod);
    exe.root_module.addImport("zio", zio_mod);
    b.installArtifact(exe);
}
