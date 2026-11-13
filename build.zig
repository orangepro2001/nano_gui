const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const text_backend = b.option([]const u8, "text-backend", "文字后端：directwrite/fontstash/fixed") orelse
        (if (target.result.os.tag == .windows) "directwrite" else "fixed");
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
    const fons_tc = b.addTranslateC(.{
        .root_source_file = b.path("third_party/fontstash_bindings.h"),
        .target = target,
        .optimize = optimize,
    });
    fons_tc.addIncludePath(b.path("third_party/nanovg"));
    const fons_mod = fons_tc.createModule();
    mod.addImport("fontstash", fons_mod);
    const font_mod = b.createModule(.{ .root_source_file = b.path("third_party/fonts/font_data.zig"), .target = target, .optimize = optimize });
    mod.addImport("dejavu", font_mod);
    mod.addOptions("build_options", options);
    mod.addIncludePath(b.path("third_party/nanovg"));
    if (target.result.os.tag == .windows) {
        const nvg_tc = b.addTranslateC(.{
            .root_source_file = b.path("third_party/nanovg_win32_api.h"),
            .target = target,
            .optimize = optimize,
        });
        nvg_tc.addIncludePath(b.path("third_party"));
        mod.addImport("nanovg_win32", nvg_tc.createModule());
        mod.addIncludePath(b.path("third_party/nanovg"));
        mod.addIncludePath(b.path("third_party"));
        mod.link_libc = true;
        mod.addCSourceFiles(.{
            .root = b.path("third_party"),
            .files = &.{ "nanovg_win32_impl.c", "nanovg/nanovg.c" },
            .flags = &.{ "-std=c99", "-D_CRT_SECURE_NO_WARNINGS" },
        });
    }
    if (std.mem.eql(u8, text_backend, "fontstash")) {
        mod.link_libc = true;
        mod.linkSystemLibrary("m", .{});
        mod.addCSourceFiles(.{
            .root = b.path("third_party"),
            .files = &.{"fontstash_impl.c"},
            .flags = &.{"-std=c99"},
        });
    }

    const examples = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "gallery", .path = "examples/gallery.zig" },
        .{ .name = "hello", .path = "examples/hello.zig" },
        .{ .name = "custom_widget", .path = "examples/custom_widget.zig" },
        .{ .name = "text_editor", .path = "examples/text_editor.zig" },
        .{ .name = "data_browser", .path = "examples/data_browser.zig" },
        .{ .name = "settings_panel", .path = "examples/settings_panel.zig" },
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

    if (target.result.os.tag == .linux) {
        const gl_tc = b.addTranslateC(.{
            .root_source_file = b.path("examples/gl_headers.h"),
            .target = target,
            .optimize = optimize,
        });
        gl_tc.addIncludePath(b.path("third_party/nanovg"));
        const gl_headers = gl_tc.createModule();
        const gl_mod = b.createModule(.{
            .root_source_file = b.path("examples/gallery_gl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "nano_gui", .module = mod },
                .{ .name = "gl_headers", .module = gl_headers },
            },
        });
        gl_mod.addIncludePath(b.path("third_party/nanovg"));
        gl_mod.addCSourceFiles(.{
            .root = b.path("third_party/nanovg"),
            .files = &.{ "nanovg.c", "nanovg_gl3.c" },
            .flags = &.{"-std=c99"},
        });
        gl_mod.linkSystemLibrary("GLEW", .{});
        gl_mod.linkSystemLibrary("glfw", .{});
        gl_mod.linkSystemLibrary("GL", .{});
        const gl_exe = b.addExecutable(.{ .name = "gallery_gl", .root_module = gl_mod });
        b.installArtifact(gl_exe);
        const run_gl = b.addRunArtifact(gl_exe);
        run_gl.setCwd(b.path("."));
        run_gl.addPassthruArgs();
        const gl_step = b.step("run-gallery-gl", "运行 NanoVG GL3 示例");
        gl_step.dependOn(&run_gl.step);
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
        win_mod.linkSystemLibrary("comdlg32", .{});
        win_mod.linkSystemLibrary("shell32", .{});
        win_mod.linkSystemLibrary("ole32", .{});
        win_mod.linkSystemLibrary("imm32", .{});
        const win_exe = b.addExecutable(.{ .name = "gallery_win32", .root_module = win_mod });
        b.installArtifact(win_exe);

        const platform_win_mod = b.createModule(.{
            .root_source_file = b.path("examples/platform_win32.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nano_gui", .module = mod }},
        });
        platform_win_mod.linkSystemLibrary("comdlg32", .{});
        platform_win_mod.linkSystemLibrary("shell32", .{});
        platform_win_mod.linkSystemLibrary("ole32", .{});
        platform_win_mod.linkSystemLibrary("imm32", .{});
        const platform_win = b.addExecutable(.{ .name = "platform_win32", .root_module = platform_win_mod });
        b.installArtifact(platform_win);
    }

    // ---- 单元测试 ----
    const gallery_test_mod = b.createModule(.{
        .root_source_file = b.path("examples/gallery.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "nano_gui", .module = mod }},
    });
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nano_gui", .module = mod },
                .{ .name = "gallery", .module = gallery_test_mod },
                .{ .name = "build_source", .module = b.createModule(.{
                    .root_source_file = b.path("build_source.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
                .{ .name = "test_source", .module = b.createModule(.{
                    .root_source_file = b.path("test_source.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
                .{ .name = "ci_source", .module = b.createModule(.{
                    .root_source_file = b.path("ci_source.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
                .{ .name = "acceptance_source", .module = b.createModule(.{
                    .root_source_file = b.path("acceptance_source.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });
    // 架构验收用的子进程探针（tests/arch_probe.zig）：固定以调试与发布两种模式各编译一份，
    // 单元测试按绝对路径启动它们（AC-ARCH-005、AC-ARCH-008、AC-ARCH-010、AC-ARCH-011）。
    const probe_paths = b.addOptions();
    inline for (.{ .{ "probe_debug", std.builtin.OptimizeMode.Debug }, .{ "probe_release", std.builtin.OptimizeMode.ReleaseFast } }) |cfg| {
        // 探针使用的 nano_gui 副本沿用 mod 的全部导入，仅优化模式不同。
        const probe_nano = b.createModule(.{
            .root_source_file = b.path("src/nano_gui.zig"),
            .target = target,
            .optimize = cfg[1],
        });
        for (mod.import_table.keys(), mod.import_table.values()) |name, dep| probe_nano.addImport(name, dep);
        if (std.mem.eql(u8, text_backend, "fontstash")) {
            probe_nano.link_libc = true;
            probe_nano.linkSystemLibrary("m", .{});
            probe_nano.addCSourceFiles(.{
                .root = b.path("third_party"),
                .files = &.{"fontstash_impl.c"},
                .flags = &.{"-std=c99"},
            });
        }
        const probe = b.addExecutable(.{
            .name = cfg[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/arch_probe.zig"),
                .target = target,
                .optimize = cfg[1],
                .imports = &.{.{ .name = "nano_gui", .module = probe_nano }},
            }),
        });
        probe_paths.addOptionPath(cfg[0], probe.getEmittedBin());
    }
    unit_tests.root_module.addOptions("probe_paths", probe_paths);
    const run_unit = b.addRunArtifact(unit_tests);
    run_unit.setCwd(b.path("."));
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
    run_golden.addPassthruArgs();
    const golden_step = b.step("test-golden", "运行金图测试（无头，全部用例）");
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
    const small_mod = b.createModule(.{
        .root_source_file = b.path("src/nano_gui.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    for (mod.import_table.keys(), mod.import_table.values()) |name, dep| small_mod.addImport(name, dep);
    if (std.mem.eql(u8, text_backend, "fontstash")) {
        small_mod.link_libc = true;
        small_mod.linkSystemLibrary("m", .{});
        small_mod.addCSourceFiles(.{
            .root = b.path("third_party"),
            .files = &.{"fontstash_impl.c"},
            .flags = &.{"-std=c99"},
        });
    }
    const hello_small = b.addExecutable(.{
        .name = "hello_small",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/hello.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .imports = &.{.{ .name = "nano_gui", .module = small_mod }},
        }),
    });
    const gallery_small = b.addExecutable(.{
        .name = "gallery_small",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/gallery.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .imports = &.{.{ .name = "nano_gui", .module = small_mod }},
        }),
    });
    const bench_opts = b.addOptions();
    bench_opts.addOptionPath("hello_small", hello_small.getEmittedBin());
    bench_opts.addOptionPath("gallery_small", gallery_small.getEmittedBin());

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nano_gui", .module = mod },
                .{ .name = "bench_paths", .module = bench_opts.createModule() },
                // 参考界面 G 的候选实现（示例“控件总览”），用于核对测量对象的节点数（REQ-PERF-003）。
                .{ .name = "gallery", .module = b.createModule(.{
                    .root_source_file = b.path("examples/gallery.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{.{ .name = "nano_gui", .module = mod }},
                }) },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench);
    run_bench.addPassthruArgs();
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
    run_check.setCwd(b.path("."));
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

    // ---- 源码静态检查（AC-ARCH-001、AC-PLAT-018、AC-CONV-*）----
    // 不依赖 nano_gui 模块，只读仓库文件与 git 历史；工作目录必须是仓库根。
    const code_opts = b.addOptions();
    code_opts.addOption([]const u8, "zig_exe", b.graph.zig_exe);
    const check_code_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_code.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = code_opts.createModule() }},
    });
    const check_code = b.addExecutable(.{ .name = "check_code", .root_module = check_code_mod });
    const run_check_code = b.addRunArtifact(check_code);
    run_check_code.setCwd(b.path("."));
    const check_code_step = b.step("check-code", "运行源码静态检查（输出全部违规，有违规则失败）");
    check_code_step.dependOn(&run_check_code.step);

    // 静态检查的测试（真实仓库扫描 + 植入缺陷样本）。现有代码尚有大量违规，
    // 真实仓库扫描的测试会失败，因此暂不挂进 `zig build test`；违规清零后再接入。
    const code_tests = b.addTest(.{ .root_module = check_code_mod });
    const run_code_tests = b.addRunArtifact(code_tests);
    run_code_tests.setCwd(b.path("."));
    const test_code_step = b.step("test-code", "运行源码静态检查的测试（暂不属于 zig build test）");
    test_code_step.dependOn(&run_code_tests.step);

    // ---- 格式化检查（可选，便于 CI）----
    const fmt_step = b.step("fmt-check", "检查 zig fmt");
    const fmt = b.addFmt(.{ .paths = &.{ b.path("src"), b.path("examples"), b.path("tests"), b.path("tools"), b.path("build.zig") }, .check = true });
    fmt_step.dependOn(&fmt.step);
}
