// HttpArena's zix entry's build.zig, without its run step.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const zix_dep = b.dependency("zix", .{ .target = target, .optimize = optimize });
    const zix_mod = zix_dep.module("zix");

    const exe = b.addExecutable(.{
        .name = "bench-zix",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
        }),
    });
    exe.root_module.addImport("zix", zix_mod);
    b.installArtifact(exe);
}
