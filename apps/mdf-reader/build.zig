const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "mdf-reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Reuse the repository MDF core implementation.
    const mdf_mod = b.createModule(.{ .root_source_file = b.path("../../zig/src/mdf.zig") });
    exe.root_module.addImport("mdf", mdf_mod);

    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");

    b.installArtifact(exe);
}

