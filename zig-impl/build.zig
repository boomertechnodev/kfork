const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options
    const target = b.standardTargetOptions(.{});

    // Standard optimization options
    const optimize = b.standardOptimizeOption(.{});

    // Version matching Python implementation
    const version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 3 };

    //
    // Core Library
    //
    const k7core = b.addStaticLibrary(.{
        .name = "k7core",
        .root_source_file = b.path("src/core/core.zig"),
        .target = target,
        .optimize = optimize,
        .version = version,
    });
    b.installArtifact(k7core);

    //
    // CLI Executable
    //
    const k7_cli = b.addExecutable(.{
        .name = "k7",
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .version = version,
    });
    k7_cli.linkLibrary(k7core);
    b.installArtifact(k7_cli);

    //
    // API Server Executable
    //
    const k7_api = b.addExecutable(.{
        .name = "k7-api",
        .root_source_file = b.path("src/api/main.zig"),
        .target = target,
        .optimize = optimize,
        .version = version,
    });
    k7_api.linkLibrary(k7core);
    b.installArtifact(k7_api);

    //
    // SDK Library (C-compatible for FFI)
    //
    const k7sdk = b.addSharedLibrary(.{
        .name = "k7sdk",
        .root_source_file = b.path("src/sdk/sdk.zig"),
        .target = target,
        .optimize = optimize,
        .version = version,
    });
    k7sdk.linkLibrary(k7core);
    k7sdk.linkLibC();
    b.installArtifact(k7sdk);

    //
    // Tests
    //
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core/models.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    //
    // Run commands
    //
    const run_cli = b.addRunArtifact(k7_cli);
    run_cli.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cli.addArgs(args);
    }

    const run_cli_step = b.step("run-cli", "Run the k7 CLI");
    run_cli_step.dependOn(&run_cli.step);

    const run_api = b.addRunArtifact(k7_api);
    run_api.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_api.addArgs(args);
    }

    const run_api_step = b.step("run-api", "Run the k7 API server");
    run_api_step.dependOn(&run_api.step);
}
