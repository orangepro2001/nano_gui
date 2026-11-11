//! 使用 platform 编译期后端的 Win32 顶层窗口示例（不直接调用 User32）。
//! 在 Windows 目标上由 platform 的 win32 后端创建 HWND、泵消息并呈现。

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const w = nano.widgets;
const core = nano.core;

const Model = struct { clicks: u32 = 0 };

fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(16), .gap = .md });
    _ = w.label(u, @src(), "nano_gui on Win32 platform backend", .{ .style = .title });
    if (w.button(u, @src(), "Click", .{ .variant = .accent }).clicked) m.clicks += 1;
    u.endColumn();
}

pub fn main(init: std.process.Init) !void {
    var m = Model{};
    var app = try nano.app.App.init(init.gpa, .{ .title = "nano_gui Win32", .size = .{ .w = 520, .h = 260 } });
    defer app.deinit();
    app.io = init.io;
    app.renderOnce(&m, build);
    while (true) {
        _ = app.pump();
        _ = app.step();
        _ = nano.platform.waitMessages(16);
    }
}
