const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const text_backend = b.option([]const u8, "text-backend", "文字后端：directwrite/fontstash/fixed") orelse "fixed";
    const force_rebuild = b.option(bool, "force-rebuild", "每帧强制构建脏") orelse false;
    const show_damage = b.option(bool, "show-damage", "标出损伤矩形") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "force_rebuild", force_rebuild);
    options.addOption(bool, "show_damage", show_damage);
    options.addOption([]const u8, "text_backend", text_backend);

    const mod = b.addModule("nano_gui", .{
        .root_source_file = b.path("src/nano_gui.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    const examples = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "gallery", .path = "examples/gallery.zig" },
        .{ .name = "hello", .path = "examples/hello.zig" },
        .{ .name = "custom_widget", .path = "examples/custom_widget.zig" },
    };
    for (examples) |e| {
        const exe = b.addExecutable(.{
            .name = e.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(e.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "nano_gui", .module = mod }},
            }),
        });
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addPassthruArgs();
        const run_step = b.step(b.fmt("run-{s}", .{e.name}), b.fmt("运行 {s} 示例", .{e.name}));
        run_step.dependOn(&run_cmd.step);
    }

    if (target.result.os.tag == .linux) {
        const tc = b.addTranslateC(.{
            .root_source_file = b.path("examples/x11_bindings.h"),
            .target = target,
            .optimize = optimize,
        });
        const x11_mod = tc.createModule();
        const win_mod = b.createModule(.{
            .root_source_file = b.path("examples/gallery_window.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nano_gui", .module = mod },
                .{ .name = "x11", .module = x11_mod },
            },
        });
        win_mod.linkSystemLibrary("X11", .{});
        const win_exe = b.addExecutable(.{ .name = "gallery_window", .root_module = win_mod });
        b.installArtifact(win_exe);
        const run_win = b.addRunArtifact(win_exe);
        run_win.step.dependOn(b.getInstallStep());
        run_win.addPassthruArgs();
        const run_win_step = b.step("run-gallery-window", "在真实 X11 窗口中运行控件总览");
        run_win_step.dependOn(&run_win.step);
    }

    if (target.result.os.tag == .windows) {
        const win_mod = b.createModule(.{
            .root_source_file = b.path("examples/gallery_win32.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        });
        win_mod.linkSystemLibrary("user32", .{});
        win_mod.linkSystemLibrary("gdi32", .{});
        win_mod.linkSystemLibrary("opengl32", .{});
        const win_exe = b.addExecutable(.{ .name = "gallery_win32", .root_module = win_mod });
        b.installArtifact(win_exe);
    }

    // ---- 单元测试 ----
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        }),
    });
    const run_unit = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "运行单元测试");
    test_step.dependOn(&run_unit.step);

    // ---- 金图 ----
    const golden = b.addExecutable(.{
        .name = "golden",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/golden.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        }),
    });
    const run_golden = b.addRunArtifact(golden);
    run_golden.setCwd(b.path("."));
    run_golden.addArgs(&.{ "--check", "tests/golden/glfw/instrument_light/s100" });
    const golden_step = b.step("test-golden", "运行金图测试（无头）");
    golden_step.dependOn(&run_golden.step);

    // ---- 回放 ----
    const replay = b.addExecutable(.{
        .name = "replay",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/replay.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        }),
    });
    const run_replay = b.addRunArtifact(replay);
    run_replay.setCwd(b.path("."));
    run_replay.addArg("tests/replay/basic.replay");
    const replay_step = b.step("test-replay", "运行输入回放测试");
    replay_step.dependOn(&run_replay.step);

    // ---- 基准 ----
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        }),
    });
    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "运行基准场景并输出预算对照表");
    bench_step.dependOn(&run_bench.step);

    // ---- 文档检查 ----
    const check_docs = b.addExecutable(.{
        .name = "check_docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_docs.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        }),
    });
    const run_check = b.addRunArtifact(check_docs);
    const docs_step = b.step("check-docs", "运行文档一致性检查");
    docs_step.dependOn(&run_check.step);

    // ---- 文档哈希（证明构建不写 docs/）----
    const hash_docs = b.addExecutable(.{
        .name = "hash_docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/hash_docs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_hash = b.addRunArtifact(hash_docs);
    run_hash.setCwd(b.path("."));
    run_hash.addArgs(&.{ "--write", "docs.sha256.current" });
    const hash_step = b.step("docs-hash", "写出当前 docs/ 的 SHA-256 清单");
    hash_step.dependOn(&run_hash.step);

    const check_hash = b.addExecutable(.{
        .name = "check_docs_hash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/hash_docs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_check_hash = b.addRunArtifact(check_hash);
    run_check_hash.setCwd(b.path("."));
    run_check_hash.addArgs(&.{ "--check", "docs.sha256" });
    const check_hash_step = b.step("check-docs-unchanged", "对比 docs/ 与基线哈希");
    check_hash_step.dependOn(&run_check_hash.step);

    const baseline_hash = b.addExecutable(.{
        .name = "baseline_docs_hash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/hash_docs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_baseline = b.addRunArtifact(baseline_hash);
    run_baseline.setCwd(b.path("."));
    run_baseline.addArgs(&.{ "--write", "docs.sha256" });
    const baseline_step = b.step("docs-hash-baseline", "刷新 docs.sha256 基线");
    baseline_step.dependOn(&run_baseline.step);

    // ---- 格式化检查（可选，便于 CI）----
    const fmt_step = b.step("fmt-check", "检查 zig fmt");
    const fmt = b.addFmt(.{ .paths = &.{ b.path("src"), b.path("examples"), b.path("tests"), b.path("tools"), b.path("build.zig") }, .check = true });
    fmt_step.dependOn(&fmt.step);
}
