//! 金图工具：无头渲染一个确定性场景，与基准 PNG 逐像素比对。
//! 用法：golden --check <目录> | golden --write <目录>

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const w = nano.widgets;
const core = nano.core;

fn scene(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{
        .main = .{ .grow = 1 },
        .cross = .fill,
        .padding = core.Insets.all(12),
        .gap = .md,
        .clip = true,
    });
    _ = w.label(u, @src(), "Golden scene", .{ .style = .title });
    _ = w.separator(u, @src(), .{ .structural = true });
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
    _ = w.button(u, @src(), "OK", .{ .variant = .accent });
    _ = w.button(u, @src(), "Cancel", .{});
    _ = w.checkbox(u, @src(), "Option", &checked, .{});
    u.endRow();
    _ = w.label(u, @src(), "Deterministic software raster, 100% scale.", .{ .style = .small, .color = .secondary });
    u.endColumn();
}

var checked: bool = true;

pub fn main(init: std.process.Init) !void {
    nano.platform.forceHeadless();
    const gpa = init.gpa;
    const io = init.io;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    var mode: enum { check, write } = .check;
    var dir_path: []const u8 = "tests/golden/glfw/instrument_light/s100";
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--check")) {
            mode = .check;
            if (args.next()) |p| dir_path = p;
        } else if (std.mem.eql(u8, a, "--write")) {
            mode = .write;
            if (args.next()) |p| dir_path = p;
        }
    }
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 240, .h = 140 }, .title = "golden" });
    defer app.deinit();
    app.io = io;
    app.renderOnce(@as(*anyopaque, @ptrCast(&checked)), scene);

    const case_path = try std.fs.path.join(gpa, &.{ dir_path, "smoke.png" });
    defer gpa.free(case_path);
    const actual_path = try std.fs.path.join(gpa, &.{ dir_path, "smoke.actual.png" });
    defer gpa.free(actual_path);
    const diff_path = try std.fs.path.join(gpa, &.{ dir_path, "smoke.diff.png" });
    defer gpa.free(diff_path);

    if (mode == .write) {
        try app.savePngIo(io, case_path);
        try std.Io.File.stdout().writeStreamingAll(io, "golden: 已写入基准 ");
        try std.Io.File.stdout().writeStreamingAll(io, case_path);
        try std.Io.File.stdout().writeStreamingAll(io, "\n");
        return;
    }

    const baseline = nano.app.readPng(gpa, io, case_path) catch |e| {
        if (e == error.FileNotFound) {
            try app.savePngIo(io, case_path);
            try std.Io.File.stdout().writeStreamingAll(io, "golden: 基准不存在，已创建 ");
            try std.Io.File.stdout().writeStreamingAll(io, case_path);
            try std.Io.File.stdout().writeStreamingAll(io, "\n");
            return;
        }
        return e;
    };
    defer {
        var b = baseline;
        b.deinit();
    }
    const actual = app.surface.pixels;
    if (baseline.width != app.surface.width or baseline.height != app.surface.height or baseline.rgba.len != actual.len) {
        try app.savePngIo(io, actual_path);
        try std.Io.File.stderr().writeStreamingAll(io, "golden: 尺寸不一致\n");
        std.process.exit(1);
    }
    var diff_count: usize = 0;
    var first: usize = 0;
    const diff = try gpa.alloc(u8, actual.len);
    defer gpa.free(diff);
    @memcpy(diff, actual);
    for (0..actual.len / 4) |i| {
        const o = i * 4;
        if (!std.mem.eql(u8, baseline.rgba[o .. o + 4], actual[o .. o + 4])) {
            diff_count += 1;
            if (diff_count == 1) first = i;
            diff[o] = 255;
            diff[o + 1] = 0;
            diff[o + 2] = 255;
            diff[o + 3] = 255;
        }
    }
    if (diff_count > 0) {
        try app.savePngIo(io, actual_path);
        const png = try nano.gfx.encodePng(gpa, diff, app.surface.width, app.surface.height);
        defer gpa.free(png);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = diff_path, .data = png });
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "golden: 失败，差异像素 {d}，首个索引 {d}\n", .{ diff_count, first });
        try std.Io.File.stderr().writeStreamingAll(io, msg);
        std.process.exit(1);
    }
    var buf: [128]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "golden: 通过 {s} ({d}x{d})\n", .{ case_path, app.surface.width, app.surface.height });
    try std.Io.File.stdout().writeStreamingAll(io, msg);
}
