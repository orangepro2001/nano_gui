//! M6 示例应用 ①：单文档文本编辑器（菜单栏、工具栏、查找条、多行编辑区、状态栏）。
//! 运行：zig build run-text_editor

const std = @import("std");
const nano = @import("nano_gui");
const w = nano.widgets;
const ui = nano.ui;
const core = nano.core;

pub const Model = struct {
    find_buf: w.TextBuf,
    status: []const u8 = "就绪",
    show_find: bool = true,
    wrap: bool = true,
    mono: bool = true,
    dark: bool = false,
    seeded: bool = false,
    matches: usize = 0,
    revision: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !Model {
        return .{ .find_buf = try w.TextBuf.initFrom(allocator, "nano_gui") };
    }
    pub fn deinit(self: *Model) void {
        self.find_buf.deinit();
    }
    pub fn changed(self: *Model) void {
        self.revision += 1;
    }
};

pub fn page(u: *ui.Ui, m: *Model) void {
    const t = u.theme_ptr;
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(t.metric(.gap_xs)), .gap = .xs });

    _ = w.beginMenuBar(u, @src(), .{ .debug_name = "editor-menubar" });
    if (w.beginMenu(u, @src(), "文件(&F)", .{})) {
        if (w.menuItem(u, @src(), "新建", .{ .shortcut_text = "Ctrl+N" }).clicked) {
            m.status = "已新建文档";
            m.changed();
        }
        if (w.menuItem(u, @src(), "保存", .{ .shortcut_text = "Ctrl+S" }).clicked) {
            m.status = "已保存";
            m.changed();
        }
        w.endMenu(u);
    }
    if (w.beginMenu(u, @src(), "编辑(&E)", .{})) {
        if (w.menuItem(u, @src(), "查找", .{ .shortcut_text = "Ctrl+F", .checked = m.show_find }).clicked) {
            m.show_find = !m.show_find;
            m.changed();
        }
        w.endMenu(u);
    }
    if (w.beginMenu(u, @src(), "视图(&V)", .{})) {
        if (w.menuItem(u, @src(), "自动换行", .{ .checked = m.wrap }).clicked) {
            m.wrap = !m.wrap;
            m.changed();
        }
        if (w.menuItem(u, @src(), "等宽字体", .{ .checked = m.mono }).clicked) {
            m.mono = !m.mono;
            m.changed();
        }
        w.endMenu(u);
    }
    w.endMenuBar(u);

    _ = w.beginToolbar(u, @src(), .{ .debug_name = "editor-toolbar" });
    if (w.toolbarButton(u, @src(), "查找", .{ .icon = .{ .mark = .search }, .checked = m.show_find }).clicked) {
        m.show_find = !m.show_find;
        m.changed();
    }
    w.toolbarSeparator(u, @src());
    if (w.toolbarButton(u, @src(), "换行", .{ .checked = m.wrap }).clicked) {
        m.wrap = !m.wrap;
        m.changed();
    }
    if (w.toolbarButton(u, @src(), "深色", .{ .checked = m.dark }).clicked) {
        m.dark = !m.dark;
        m.changed();
    }
    w.endToolbar(u);

    if (m.show_find) {
        _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fill, .gap = .sm, .cross_align = .center });
        _ = w.label(u, @src(), "查找:", .{ .style = .small, .color = .secondary });
        _ = w.textInput(u, @src(), &m.find_buf, .{ .debug_name = "find-input", .placeholder = "输入查找关键字...", .layout = .{ .main = .{ .grow = 1 } } });
        if (w.button(u, @src(), "查找下一处", .{ .variant = .accent, .debug_name = "find-next" }).clicked) {
            m.status = "查找完成";
            m.changed();
        }
        u.endRow();
    }

    const ta = w.textArea(u, @src(), .{
        .debug_name = "editor-area",
        .mono = m.mono,
        .wrap = if (m.wrap) .word else .none,
        .accepts_tab = true,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    if (!m.seeded) {
        m.seeded = true;
        _ = w.textAreaLoad(u, ta.handle, "# nano_gui 文本编辑器\n\n支持多行编辑、自动换行、查找与等宽显示。\n") catch {};
    }
    if (m.show_find and m.find_buf.len() > 0) {
        if (w.textAreaText(u, ta.handle, u.frameAlloc(), .{})) |txt| {
            defer u.frameAlloc().free(txt);
            var cnt: usize = 0;
            var pos: usize = 0;
            const needle = m.find_buf.slice();
            while (std.mem.indexOfPos(u8, txt, pos, needle)) |hit| {
                cnt += 1;
                pos = hit + needle.len;
            }
            m.matches = cnt;
        } else |_| {}
    }

    _ = w.separator(u, @src(), .{ .structural = true });
    _ = w.beginStatusBar(u, @src(), .{});
    _ = w.label(u, @src(), m.status, .{ .style = .small, .color = .secondary });
    _ = u.spacer(@src(), 1);
    const pos_txt = std.fmt.allocPrint(u.treeAlloc(), "行 {d} 列 {d} | 匹配 {d}", .{ ta.caret_line + 1, ta.caret_column + 1, m.matches }) catch "";
    _ = w.label(u, @src(), pos_txt, .{ .key = ui.Key.str("cursor-pos"), .style = .small, .color = .secondary });
    w.endStatusBar(u);

    u.endColumn();
}

pub fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    page(u, m);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var m = try Model.init(gpa);
    defer m.deinit();
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Text Editor", .size = .{ .w = 960, .h = 640 } });
    defer app.deinit();
    app.renderOnce(&m, build);
    const out = try std.fmt.allocPrint(gpa, "text_editor: frames={d} nodes={d}\n", .{ app.frames, app.ui_state.node_count });
    defer gpa.free(out);
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
