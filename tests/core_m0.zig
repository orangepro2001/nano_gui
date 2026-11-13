//! M0 core/app 架构验收测试（AC-ARCH-*、AC-CONV-013）。
const std = @import("std");
const builtin = @import("builtin");
const nano = @import("nano_gui");
const gallery = @import("gallery");
const probe_paths = @import("probe_paths");
const core = nano.core;
const ui = nano.ui;
const widgets = nano.widgets;

const io = std.testing.io;
const gpa = std.testing.allocator;

/// 读取 src/ 下全部 .zig 文件（测试在仓库根目录运行，见 build.zig 的 setCwd）。
const SrcFile = struct { name: []u8, bytes: []u8 };

fn loadSrcFiles() !std.ArrayList(SrcFile) {
    var list: std.ArrayList(SrcFile) = .empty;
    errdefer freeSrcFiles(&list);
    var dir = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        const name = try gpa.dupe(u8, entry.name);
        errdefer gpa.free(name);
        const bytes = try dir.readFileAlloc(io, entry.name, gpa, .unlimited);
        errdefer gpa.free(bytes);
        try list.append(gpa, .{ .name = name, .bytes = bytes });
    }
    return list;
}

fn freeSrcFiles(list: *std.ArrayList(SrcFile)) void {
    for (list.items) |f| {
        gpa.free(f.name);
        gpa.free(f.bytes);
    }
    list.deinit(gpa);
}

fn runProbe(path: []const u8, mode: []const u8) !std.process.RunResult {
    return std.process.run(gpa, io, .{ .argv = &.{ path, mode } });
}

fn expectExitedZero(term: std.process.Child.Term) !void {
    switch (term) {
        .exited => |c| try std.testing.expectEqual(@as(u8, 0), c),
        else => return error.TestUnexpectedResult,
    }
}

fn isNonZeroEnd(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |c| c != 0,
        else => true, // 被信号终止（断言中止）同样是非零结束
    };
}

// ---------------------------------------------------------------------------
// AC-ARCH-004
// ---------------------------------------------------------------------------

test "AC-ARCH-004 framework creates no threads while the gallery runs" {
    const before = core.thread.createdCount();

    var model = try gallery.Model.init(gpa);
    defer model.deinit();
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 960, .h = 620 } });
    defer app.deinit();
    const frames = app.runHeadless(&model, gallery.build, 30);
    try std.testing.expect(frames > 0);
    try std.testing.expectEqual(before, core.thread.createdCount());

    // 静态补充：框架源码中只有 core 的包装可以创建线程。
    var files = try loadSrcFiles();
    defer freeSrcFiles(&files);
    for (files.items) |f| {
        if (std.mem.eql(u8, f.name, "core.zig")) continue;
        try std.testing.expect(std.mem.indexOf(u8, f.bytes, "Thread.spawn") == null);
    }

    // 对照：经包装创建线程必须使计数加一，否则上面的零计数没有意义。
    const W = struct {
        fn run() void {}
    };
    const t = try core.thread.spawn(.{}, W.run, .{});
    t.join();
    try std.testing.expectEqual(before + 1, core.thread.createdCount());
}

// ---------------------------------------------------------------------------
// AC-ARCH-005
// ---------------------------------------------------------------------------

const post_count = 10_000;

const PostRun = struct {
    var seq: [post_count]u32 = undefined;
    var seen: [post_count]u32 = undefined;
    var seen_n: usize = 0;
    var overflow: bool = false;

    fn record(ctx: ?*anyopaque) void {
        const v: *u32 = @ptrCast(@alignCast(ctx.?));
        if (seen_n >= post_count) {
            overflow = true;
            return;
        }
        seen[seen_n] = v.*;
        seen_n += 1;
    }

    fn worker(app: *nano.app.App) void {
        for (&seq, 0..) |*v, i| {
            v.* = @intCast(i);
            while (!app.post(.{ .ctx = v, .func = record })) std.atomic.spinLoopHint();
        }
    }
};

test "AC-ARCH-005 posted closures run in order without loss" {
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 200, .h = 120 } });
    defer app.deinit();
    PostRun.seen_n = 0;
    PostRun.overflow = false;
    const t = try std.Thread.spawn(.{}, PostRun.worker, .{&app});
    // 界面线程反复泵消息，直到全部闭包执行完毕或超时。
    var spins: usize = 0;
    while (PostRun.seen_n < post_count and spins < 50_000_000) : (spins += 1) _ = app.pump();
    t.join();
    _ = app.pump();
    try std.testing.expect(!PostRun.overflow);
    try std.testing.expectEqual(@as(usize, post_count), PostRun.seen_n);
    for (PostRun.seen, 0..) |v, i| try std.testing.expectEqual(@as(u32, @intCast(i)), v);
}

test "AC-ARCH-005 non thread safe API aborts in debug build when called off the ui thread" {
    const r = try runProbe(probe_paths.probe_debug, "worker-api");
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    try std.testing.expect(isNonZeroEnd(r.term));
    try std.testing.expect(std.mem.indexOf(u8, r.stderr, "REQ-ARCH-009") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stderr, "App.invalidateAll") != null);
}

// ---------------------------------------------------------------------------
// AC-ARCH-008
// ---------------------------------------------------------------------------

test "AC-ARCH-008 leaked persistent allocation fails debug exit and names the allocation site" {
    // 对照组：不泄漏时退出码为 0 且无泄漏报告。
    const ok = try runProbe(probe_paths.probe_debug, "noleak");
    defer gpa.free(ok.stdout);
    defer gpa.free(ok.stderr);
    try expectExitedZero(ok.term);
    try std.testing.expect(std.mem.indexOf(u8, ok.stderr, "leak") == null);

    const r = try runProbe(probe_paths.probe_debug, "leak");
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    try std.testing.expect(isNonZeroEnd(r.term));
    try std.testing.expect(std.mem.indexOf(u8, r.stderr, "leak") != null);
    // 标准错误须包含泄漏的分配点（探针源文件即分配点）。
    try std.testing.expect(std.mem.indexOf(u8, r.stderr, "arch_probe.zig") != null);
}

// ---------------------------------------------------------------------------
// AC-ARCH-009
// ---------------------------------------------------------------------------

const TextCtx = struct { text: []const u8 };

fn labelBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const c: *TextCtx = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{});
    _ = widgets.label(u, @src(), c.text, .{ .debug_name = "ac-arch-009" });
    u.endColumn();
}

fn renderLabel(text: []const u8) ![]u8 {
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 240, .h = 80 } });
    defer app.deinit();
    var ctx = TextCtx{ .text = text };
    app.renderOnce(&ctx, labelBuild);
    return gpa.dupe(u8, app.surface.pixels);
}

test "AC-ARCH-009 label survives odd text and invalid UTF-8 shows U+FFFD" {
    // 含 BMP 外字符、空串：不崩溃，且非空文本画出了东西。
    const blank = try renderLabel("");
    defer gpa.free(blank);
    const astral = try renderLabel("a \u{1F600} b");
    defer gpa.free(astral);
    try std.testing.expect(!std.mem.eql(u8, blank, astral));

    // 非法序列与 U+FFFD 逐像素一致（孤立 0xFF、孤立续字节、过长编码 C0 80）。
    const Case = struct { bad: []const u8, good: []const u8 };
    const cases = [_]Case{
        .{ .bad = "a\xFFb", .good = "a\u{FFFD}b" },
        .{ .bad = "a\x80b", .good = "a\u{FFFD}b" },
        .{ .bad = "a\xC0\x80b", .good = "a\u{FFFD}\u{FFFD}b" },
    };
    for (cases) |c| {
        const bad = try renderLabel(c.bad);
        defer gpa.free(bad);
        const good = try renderLabel(c.good);
        defer gpa.free(good);
        try std.testing.expect(std.mem.eql(u8, bad, good));
        // 对照：替换字符确实被画出（与把它换成空格不同）。
        const spaced = try renderLabel("a b");
        defer gpa.free(spaced);
        try std.testing.expect(!std.mem.eql(u8, good, spaced));
    }

    // 超长串（1 MB）：不崩溃。
    const big = try gpa.alloc(u8, 1024 * 1024);
    defer gpa.free(big);
    @memset(big, 'x');
    const huge = try renderLabel(big);
    defer gpa.free(huge);
    try std.testing.expect(huge.len > 0);
}

test "AC-ARCH-009 rewriting the source buffer does not change the committed frame" {
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 240, .h = 80 } });
    defer app.deinit();
    var buf = [_]u8{ 'H', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd' };
    var ctx = TextCtx{ .text = &buf };
    app.renderOnce(&ctx, labelBuild);
    const before = try gpa.dupe(u8, app.surface.pixels);
    defer gpa.free(before);

    // 调用返回后立即改写原缓冲，再强制整面重绘一帧（不重新构建）。
    @memset(&buf, 'Z');
    app.ui_state.repaint_all = true;
    app.ui_state.invalidate(.paint);
    _ = app.step();
    try std.testing.expect(std.mem.eql(u8, before, app.surface.pixels));

    // 对照：确实重新构建后画面会随新内容改变，证明上面的重绘路径是有效的。
    app.renderOnce(&ctx, labelBuild);
    try std.testing.expect(!std.mem.eql(u8, before, app.surface.pixels));
}

// ---------------------------------------------------------------------------
// AC-ARCH-010 / AC-CONV-013
// ---------------------------------------------------------------------------

const missing_image_path = "does/not/exist/nano_gui_missing.png";

var warn_seen: u32 = 0;
var err_seen: u32 = 0;
fn countSink(level: core.log.Level, _: []const u8, _: []const u8) void {
    switch (level) {
        .warn => warn_seen += 1,
        .err => err_seen += 1,
        else => {},
    }
}

fn missingImageBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{});
    widgets.imageFile(u, @src(), io, missing_image_path, .{});
    u.endColumn();
}
fn placeholderBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{});
    widgets.image(u, @src(), null, .{});
    u.endColumn();
}
fn emptyColumnBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{});
    u.endColumn();
}

fn renderWith(build: nano.app.BuildFn) ![]u8 {
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 120, .h = 80 } });
    defer app.deinit();
    var dummy: u8 = 0;
    app.renderOnce(&dummy, build);
    return gpa.dupe(u8, app.surface.pixels);
}

test "AC-ARCH-010 missing image shows placeholder with exactly one warn and no try" {
    // 构建函数无需 try：控件入口不返回错误联合。
    try std.testing.expect(@typeInfo(@TypeOf(widgets.imageFile)).@"fn".return_type.? == void);
    try std.testing.expect(@typeInfo(@TypeOf(widgets.image)).@"fn".return_type.? == void);

    warn_seen = 0;
    err_seen = 0;
    core.log.setSink(countSink);
    defer core.log.setSink(null);

    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 120, .h = 80 } });
    defer app.deinit();
    var dummy: u8 = 0;
    // 多次构建与重绘：同一路径只记录一条 warn。
    app.renderOnce(&dummy, missingImageBuild);
    app.renderOnce(&dummy, missingImageBuild);
    app.renderOnce(&dummy, missingImageBuild);
    try std.testing.expectEqual(@as(u32, 1), warn_seen);
    try std.testing.expectEqual(@as(u32, 0), err_seen);
    const missing = try gpa.dupe(u8, app.surface.pixels);
    defer gpa.free(missing);

    // 显示的是占位框：与直接传入空图像的占位画面一致，且不同于什么都没画。
    const placeholder = try renderWith(placeholderBuild);
    defer gpa.free(placeholder);
    const nothing = try renderWith(emptyColumnBuild);
    defer gpa.free(nothing);
    try std.testing.expect(std.mem.eql(u8, missing, placeholder));
    try std.testing.expect(!std.mem.eql(u8, missing, nothing));
}

/// 返回 src 中 `anyerror` 出现的行（排除注释行）。
fn countAnyerror(bytes: []const u8) usize {
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "//")) continue;
        const code = if (std.mem.indexOf(u8, t, "//")) |i| t[0..i] else t;
        if (std.mem.indexOf(u8, code, "anyerror") != null) n += 1;
    }
    return n;
}

test "AC-ARCH-010 public API signatures contain no anyerror" {
    // 扫描器自检：植入缺陷必须被发现，注释中的字样不算。
    try std.testing.expectEqual(@as(usize, 1), countAnyerror("pub fn f() anyerror!void {}\n"));
    try std.testing.expectEqual(@as(usize, 0), countAnyerror("// anyerror 不得使用\npub fn f() !void {}\n"));

    var files = try loadSrcFiles();
    defer freeSrcFiles(&files);
    var total: usize = 0;
    for (files.items) |f| {
        const n = countAnyerror(f.bytes);
        if (n != 0) std.debug.print("anyerror in src/{s}: {d}\n", .{ f.name, n });
        total += n;
    }
    try std.testing.expectEqual(@as(usize, 0), total);
}

test "AC-ARCH-010 duplicate widget id in release build does not crash and logs one err" {
    if (builtin.optimize == .debug) {
        // 调试构建中重复 ID 是断言中止的编程错误；发布构建行为由发布探针验证。
    }
    const r = try runProbe(probe_paths.probe_release, "dup-id");
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    try expectExitedZero(r.term);
    // 同一冲突在多次构建中只记一条 err。
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "err=1") != null);
}

test "AC-CONV-013 image load failure is an error value and not an assertion" {
    const r = widgets.loadImageFile(gpa, io, missing_image_path);
    try std.testing.expectError(error.FileNotFound, r);
    // 控件显示占位框（AC-ARCH-010）：进程仍在运行即证明未触发断言，画面与占位一致。
    const missing = try renderWith(missingImageBuild);
    defer gpa.free(missing);
    const placeholder = try renderWith(placeholderBuild);
    defer gpa.free(placeholder);
    try std.testing.expect(std.mem.eql(u8, missing, placeholder));
}

/// 返回没有描述性消息的 `std.debug.assert` 行数：同一行含 `//` 注释，或上一行是注释行。
fn countBareAsserts(name: []const u8, bytes: []const u8, report: bool) usize {
    var n: usize = 0;
    var prev: []const u8 = "";
    var lineno: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        lineno += 1;
        defer prev = line;
        const t = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "//")) continue;
        const at = std.mem.indexOf(u8, t, "std.debug.assert(") orelse continue;
        if (std.mem.indexOf(u8, t[0..at], "//") != null) continue;
        const has_inline = std.mem.indexOf(u8, t[at..], "//") != null;
        const has_prev = std.mem.startsWith(u8, std.mem.trim(u8, prev, " \t"), "//");
        if (has_inline or has_prev) continue;
        n += 1;
        if (report) std.debug.print("无描述性消息的断言：src/{s}:{d}\n", .{ name, lineno });
    }
    return n;
}

test "AC-CONV-013 every std.debug.assert has a descriptive message nearby" {
    try std.testing.expectEqual(@as(usize, 1), countBareAsserts("x", "    std.debug.assert(a);\n", false));
    try std.testing.expectEqual(@as(usize, 0), countBareAsserts("x", "    std.debug.assert(a); // 消息\n", false));
    try std.testing.expectEqual(@as(usize, 0), countBareAsserts("x", "// 消息\nstd.debug.assert(a);\n", false));

    var files = try loadSrcFiles();
    defer freeSrcFiles(&files);
    var total: usize = 0;
    for (files.items) |f| total += countBareAsserts(f.name, f.bytes, true);
    try std.testing.expectEqual(@as(usize, 0), total);
}

// ---------------------------------------------------------------------------
// AC-ARCH-011
// ---------------------------------------------------------------------------

var sink_levels: [4]u32 = .{ 0, 0, 0, 0 };
var sink_tag_ok: bool = true;
fn recordSink(level: core.log.Level, tag: []const u8, _: []const u8) void {
    sink_levels[@backingInt(level)] += 1;
    if (!std.mem.eql(u8, tag, "ac011")) sink_tag_ok = false;
}

var fake_now: u64 = 0;
fn fakeClock() u64 {
    return fake_now;
}

test "AC-ARCH-011 log levels filter by build mode and stats counter and timer read back" {
    sink_levels = .{ 0, 0, 0, 0 };
    sink_tag_ok = true;
    core.log.setSink(recordSink);
    defer core.log.setSink(null);
    const L = core.log.scoped(.ac011);
    L.err("e", .{});
    L.warn("w", .{});
    L.info("i", .{});
    L.debug("d", .{});
    var total: u32 = 0;
    for (sink_levels) |c| total += c;
    // 调试构建四条，发布构建两条（只保留 err/warn）；另一种模式由发布探针验证。
    const expected: u32 = if (builtin.optimize == .debug) 4 else 2;
    try std.testing.expectEqual(expected, total);
    try std.testing.expectEqual(@as(u32, 1), sink_levels[@backingInt(core.log.Level.err)]);
    try std.testing.expectEqual(@as(u32, 1), sink_levels[@backingInt(core.log.Level.warn)]);
    try std.testing.expect(sink_tag_ok);

    // 另一种构建模式：以固定的调试/发布探针各跑一次，断言各自的条数。
    inline for (.{ .{ probe_paths.probe_debug, "total=4" }, .{ probe_paths.probe_release, "total=2" } }) |cfg| {
        const r = try runProbe(cfg[0], "log");
        defer gpa.free(r.stdout);
        defer gpa.free(r.stderr);
        try expectExitedZero(r.term);
        try std.testing.expect(std.mem.indexOf(u8, r.stdout, cfg[1]) != null);
    }

    // 计数器：值与递增次数一致，且单调。
    const c = core.stats.counter("test.ac011.counter");
    const base = c.*;
    var i: u64 = 0;
    while (i < 7) : (i += 1) c.* += 1;
    try std.testing.expectEqual(base + 7, core.stats.read("test.ac011.counter").?);

    // 计时器：注入时钟后留下逐次样本，可按名字取出。
    core.stats.setClock(fakeClock);
    defer core.stats.setClock(null);
    fake_now = 1_000;
    core.stats.timerBegin("test.ac011.timer");
    fake_now = 1_750;
    core.stats.timerEnd("test.ac011.timer");
    fake_now = 2_000;
    core.stats.timerBegin("test.ac011.timer");
    fake_now = 2_100;
    core.stats.timerEnd("test.ac011.timer");
    var samples: [4]u64 = undefined;
    const n = core.stats.drainSamples("test.ac011.timer", &samples);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(u64, 750), samples[0]);
    try std.testing.expectEqual(@as(u64, 100), samples[1]);
}
