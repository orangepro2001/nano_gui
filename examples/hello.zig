//! 最小示例：一个空窗口里的 Hello。
//! 运行：zig build run-hello -- --png /tmp/hello.png

const std = @import("std");
const nano = @import("nano_gui");
const w = nano.widgets;
const ui = nano.ui;
const core = nano.core;

const Model = struct { clicks: u32 = 0 };

fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{
        .main = .{ .grow = 1 },
        .cross = .fill,
        .padding = core.Insets.all(24),
        .gap = .md,
        .cross_align = .center,
    });
    _ = w.label(u, @src(), "Hello, nano_gui", .{ .style = .title });
    _ = w.label(u, @src(), "Controlled immediate mode - passive refresh - deterministic rendering", .{ .style = .small, .color = .secondary });
    if (w.button(u, @src(), "Click me", .{ .variant = .accent, .debug_name = "hello-button" }).clicked) m.clicks += 1;
    _ = w.label(u, @src(), "Clicks", .{ .style = .small, .color = .secondary });
    u.endColumn();
}

pub fn main(init: std.process.Init) !void {
    var m = Model{};
    var app = try nano.app.App.init(init.gpa, .{ .title = "Hello nano_gui", .size = .{ .w = 480, .h = 260 } });
    defer app.deinit();
    app.io = init.io;
    app.renderOnce(&m, build);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    var png: ?[]const u8 = null;
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--png")) {
            png = args.next();
        } else if (std.mem.startsWith(u8, a, "--png=")) {
            png = a[6..];
        }
    }
    if (png) |p| try app.savePngIo(init.io, p);
    const out = try std.fmt.allocPrint(init.gpa, "hello: frames={d} clicks={d}\n", .{ app.frames, m.clicks });
    defer init.gpa.free(out);
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
