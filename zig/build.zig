const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mdf",
        .root_source_file = b.path("src/mdf.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const mdf_mod = b.createModule(.{ .root_source_file = b.path("src/mdf.zig") });

    const exe = b.addExecutable(.{
        .name = "mdf",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("mdf", mdf_mod);
    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/mdf_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("mdf", mdf_mod);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run Zig unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

