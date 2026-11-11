//! 自定义控件示例（AC-ARCH-003）：不修改 widgets 模块，仅用公开接口实现一个
//! 带悬停 / 按下 / 焦点 / 键盘激活的自绘按钮。
//! 运行：zig build run-custom_widget -- --png /tmp/custom.png

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const core = nano.core;
const theme = nano.theme;
const text = nano.text;
const layout = nano.layout;
const input = nano.input;
const w = nano.widgets;

const CustomProps = struct { label: []const u8, layout_ptr: *const text.Layout };

fn paintCustom(ctx: *ui.PaintCtx, node: *const ui.Node) void {
    const p: *const CustomProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    const v = ctx.visual(node);
    // 自绘：不使用 widgets 的内部实现，只调用 theme 的公开基元。
    theme.drawRaised(&ctx.draw, r, .radius_control, if (v.pressed) .accent else .neutral, v);
    const fg = if (v.pressed) t.color(.text_on_accent) else t.color(.text_primary);
    text.draw(ctx.draw.canvas, p.layout_ptr, .{ .x = r.x + (r.w - p.layout_ptr.size.w) * 0.5, .y = r.y + (r.h - p.layout_ptr.size.h) * 0.5 }, fg, .{});
    if (v.focused_visible) theme.drawFocusRing(&ctx.draw, r, .radius_control, v);
}

fn customButton(u: *ui.Ui, src: std.builtin.SourceLocation, label: []const u8, key: ui.Key, clicked: *bool) void {
    const id = u.id(src, key);
    const style = u.theme_ptr.fonts.get(.body);
    const l = text.layoutOwned(u.treeAlloc(), label, style, u.scale, .{ .newlines = .as_space }) catch @panic("layout");
    const props = u.treeAlloc().create(CustomProps) catch @panic("props");
    props.* = .{ .label = label, .layout_ptr = l.layout };
    const pad = u.theme_ptr.metric(.pad_control_x);
    const node = u.leaf(id, .{
        .layout = .{
            .kind = .leaf,
            .main = .fit,
            .cross = .fit,
            .content = .{ .size = .{ .x = l.layout.size.w + pad * 2, .y = u.theme_ptr.metric(.control_h) } },
        },
        .flags = .{ .focusable = true },
        .paint = paintCustom,
        .props = props,
        .paint_outset = u.theme_ptr.metric(.focus_ring_w),
        .paint_key = core.hashBytes(0, label),
    });
    node.src_file = src.file;
    node.src_line = src.line;
    const it = u.interact(id, .{ .sense = .{ .hover = true, .click = true }, .handles = .{ .groups = .{ .space = true, .enter = true } } });
    if (it.clicked) clicked.* = true;
    for (u.events(id)) |ev| {
        switch (ev) {
            .key_down => |k| {
                if (!k.repeat and it.focused and (k.key == .enter or k.key == .space)) clicked.* = true;
            },
            else => {},
        }
    }
}

const Model = struct { clicks: u32 = 0 };

fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(20), .gap = .md, .cross_align = .center });
    _ = w.label(u, @src(), "Custom widget (public API only)", .{ .style = .title });
    var clicked = false;
    customButton(u, @src(), "Custom button", ui.Key.str("custom"), &clicked);
    if (clicked) m.clicks += 1;
    _ = w.label(u, @src(), "Tab to focus, Enter/Space to activate", .{ .style = .small, .color = .secondary });
    u.endColumn();
}

pub fn main(init: std.process.Init) !void {
    var m = Model{};
    var app = try nano.app.App.init(init.gpa, .{ .title = "自定义控件", .size = .{ .w = 460, .h = 260 } });
    defer app.deinit();
    app.io = init.io;
    app.renderOnce(&m, build);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    var png: ?[]const u8 = null;
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--png")) png = args.next() else if (std.mem.startsWith(u8, a, "--png=")) png = a[6..];
    }
    if (png) |p| try app.savePngIo(init.io, p);
    const out = try std.fmt.allocPrint(init.gpa, "custom_widget: frames={d} clicks={d}\n", .{ app.frames, m.clicks });
    defer init.gpa.free(out);
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
