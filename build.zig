const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "dugra", .root_source_file = .{ .path = "src/main.zig" }, .target = target, .optimize = optimize });

    b.installArtifact(exe);
    install_web_files(b);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const check_step = b.step("check", "Do sema but no linking.");
    check_step.dependOn(&exe.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn install_web_files(b: *std.Build) void {
    const wf = std.fs.cwd().openDir("src/web_files/", .{ .iterate = true }) catch unreachable;
    var walker = wf.walk(std.heap.page_allocator) catch unreachable;
    defer walker.deinit();

    const cwd = std.fs.cwd().realpathAlloc(std.heap.page_allocator, "") catch unreachable;
    defer std.heap.page_allocator.free(cwd);

    while (walker.next() catch null) |ent| {
        if (ent.kind != .file) continue;

        const rel_src = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ cwd, "src/web_files/", ent.path }) catch unreachable;
        const rel_dst = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ "web_files", ent.path }) catch unreachable;

        b.installFile(rel_src, rel_dst);

        std.heap.page_allocator.free(rel_src);
        std.heap.page_allocator.free(rel_dst);
    }
}
