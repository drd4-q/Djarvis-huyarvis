const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addCSourceFile(.{
        .file = b.path("src/audio_bridge.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });
    exe_mod.addIncludePath(b.path("src"));

    if (target.result.os.tag == .windows) {
        exe_mod.linkSystemLibrary("ole32", .{});
        exe_mod.linkSystemLibrary("user32", .{});
        exe_mod.linkSystemLibrary("kernel32", .{});
        exe_mod.linkSystemLibrary("shell32", .{});
        exe_mod.linkSystemLibrary("ws2_32", .{});
        exe_mod.linkSystemLibrary("winmm", .{});
        exe_mod.linkSystemLibrary("gdi32", .{});
    }

    const exe = b.addExecutable(.{
        .name = "jarvis",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Jarvis Assistant");
    run_step.dependOn(&run_cmd.step);
}
