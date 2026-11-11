//! “控件总览”示例：全部基础控件、两种主题、无头截图。
//! 运行：zig build run-gallery -- --png /tmp/gallery.png

const std = @import("std");
const nano = @import("nano_gui");
const w = nano.widgets;
const ui = nano.ui;
const core = nano.core;
const theme = nano.theme;

pub const Model = struct {
    clicks: u32 = 0,
    checked: bool = true,
    mixed: w.CheckState = .mixed,
    choice: u8 = 1,
    switch_on: bool = true,
    volume: f32 = 0.62,
    progress: f32 = 0.38,
    tab: usize = 0,
    name: w.TextBuf,
    status: []const u8 = "Ready",
    dark: bool = false,
    combo: ?u32 = 0,
    spin: i64 = 42,

    pub fn init(allocator: std.mem.Allocator) !Model {
        return .{ .name = try w.TextBuf.initFrom(allocator, "nano_gui") };
    }
    pub fn deinit(self: *Model) void {
        self.name.deinit();
    }
};

fn sectionTitle(u: *ui.Ui, s: []const u8) void {
    _ = w.label(u, @src(), s, .{ .style = .body_strong, .color = .secondary });
    _ = w.separator(u, @src(), .{ .layout = .{ .cross = .{ .fixed = 1 } } });
}

const TableCtx = struct {
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        const data = [_][3][]const u8{
            .{ "Alpha", "12", "ok" },
            .{ "Beta", "7", "warn" },
            .{ "Gamma", "24", "ok" },
            .{ "Delta", "3", "error" },
        };
        return if (row < data.len and col < 3) data[row][col] else "";
    }
};

const TreeCtx = struct {
    fn childCount(ctx: ?*anyopaque, node: w.TreeNode) usize {
        _ = ctx;
        return if (node == .root) 4 else 0;
    }
    fn childAt(ctx: ?*anyopaque, node: w.TreeNode, index: usize) w.TreeNode {
        _ = ctx;
        _ = node;
        return @fromBackingInt(@intCast(index + 1));
    }
    fn hasChildren(ctx: ?*anyopaque, node: w.TreeNode) bool {
        _ = ctx;
        return node == .root;
    }
    fn keyOf(ctx: ?*anyopaque, node: w.TreeNode) w.ItemKey {
        _ = ctx;
        return @backingInt(node);
    }
    fn textOf(ctx: ?*anyopaque, node: w.TreeNode) []const u8 {
        _ = ctx;
        const items = [_][]const u8{ "", "Branch A", "Branch B", "Branch C", "Branch D" };
        const i = @backingInt(node);
        return if (i < items.len) items[i] else "";
    }
};

const ListCtx = struct {
    fn text(ctx: ?*anyopaque, index: usize) []const u8 {
        _ = ctx;
        const items = [_][]const u8{ "Alpha item", "Beta item", "Gamma item", "Delta item", "Epsilon item" };
        return if (index < items.len) items[index] else "";
    }
};

pub fn page(u: *ui.Ui, m: *Model) void {
    const t = u.theme_ptr;
    _ = u.beginColumn(@src(), .{
        .main = .{ .grow = 1 },
        .cross = .fill,
        .padding = core.Insets.all(12),
        .gap = .md,
        .clip = true,
    });

    // 标题栏
    _ = u.beginRow(@src(), .{ .main = .fixedSize(32), .cross = .fill, .gap = .md, .cross_align = .center });
    _ = w.label(u, @src(), "Instrument Widget Gallery", .{ .style = .title });
    _ = u.spacer(@src(), 1);
    if (w.button(u, @src(), if (m.dark) "Light" else "Dark", .{ .variant = .quiet, .debug_name = "theme-button" }).clicked) {
        m.dark = !m.dark;
        m.status = if (m.dark) "Switched to dark theme" else "Switched to light theme";
    }
    if (w.button(u, @src(), "Reset", .{ .variant = .quiet, .debug_name = "reset-button" }).clicked) {
        m.clicks = 0;
        m.checked = true;
        m.mixed = .mixed;
        m.choice = 1;
        m.switch_on = true;
        m.volume = 0.62;
        m.status = "Reset";
    }
    u.endRow();
    _ = w.beginMenuBar(u, @src(), .{ .debug_name = "menu-bar" });
    if (w.beginMenu(u, @src(), "File", .{})) {
        if (w.menuItem(u, @src(), "Reset", .{ .shortcut_text = "Ctrl+R" }).clicked) {
            m.clicks = 0;
            m.status = "Reset from menu";
        }
        if (w.menuItem(u, @src(), "Theme", .{}).clicked) {
            m.dark = !m.dark;
            m.status = "Theme from menu";
        }
        w.menuSeparator(u, @src());
        if (w.menuItem(u, @src(), "About", .{}).clicked) m.status = "nano_gui 0.1";
        w.endMenu(u);
    }
    if (w.beginMenu(u, @src(), "View", .{})) {
        if (w.menuItem(u, @src(), "Toggle theme", .{}).clicked) {
            m.dark = !m.dark;
            m.status = "Theme toggled";
        }
        w.endMenu(u);
    }
    w.endMenuBar(u);
    _ = w.beginToolbar(u, @src(), .{ .debug_name = "toolbar" });
    _ = w.toolbarButton(u, @src(), "Search", .{ .icon = .{ .mark = .search }, .show_text = true });
    w.toolbarSeparator(u, @src());
    _ = w.toolbarCommand(u, @src(), .none, .{ .show_text = true });
    w.toolbarSpacer(u, @src());
    _ = w.toolbarButton(u, @src(), "Settings", .{ .icon = .{ .mark = .more }, .show_text = false });
    w.endToolbar(u);
    _ = w.separator(u, @src(), .{ .structural = true });

    // 主内容：滚动视图内的两列
    const sv = w.beginScrollView(u, @src(), .{ .debug_name = "总览滚动区", .axes = .vertical, .bar_v = .auto, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fill, .gap = .lg, .cross_align = .start });

    // 左列
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .md });
    _ = w.beginPanel(u, @src(), .{ .debug_name = "buttons-panel", .layout = .{ .cross = .fill } });
    sectionTitle(u, "Button");
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
    if (w.button(u, @src(), "Primary", .{ .variant = .accent, .debug_name = "primary-button" }).clicked) {
        m.clicks += 1;
        m.status = "Primary action clicked";
    }
    if (w.button(u, @src(), "Secondary", .{ .debug_name = "secondary-button" }).clicked) {
        m.clicks += 1;
        m.status = "Secondary action clicked";
    }
    _ = w.button(u, @src(), "Disabled", .{ .enabled = false });
    if (w.button(u, @src(), "", .{ .icon = .{ .mark = .search }, .tooltip = "Search", .debug_name = "search-button" }).clicked) {
        m.status = "Search";
    }
    u.endRow();
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .xs, .cross_align = .center });
    _ = w.label(u, @src(), "Clicks:", .{ .style = .small, .color = .secondary });
    const count_text = std.fmt.allocPrint(u.treeAlloc(), "{d}", .{m.clicks}) catch "0";
    _ = w.label(u, @src(), count_text, .{ .key = ui.Key.str("click-count"), .style = .body_strong, .color = .info });
    u.endRow();
    _ = w.label(u, @src(), "Helper text and shortcut hints", .{ .style = .small, .color = .secondary });
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "selection-panel", .layout = .{ .cross = .fill } });
    sectionTitle(u, "Selection");
    if (w.checkbox(u, @src(), "Enable auto update", &m.checked, .{ .debug_name = "auto-update" }).changed) {
        m.status = if (m.checked) "Auto update on" else "Auto update off";
    }
    _ = w.checkboxTri(u, @src(), "Tri-state option", &m.mixed, .{});
    _ = w.beginRadioGroup(u, @src(), .{ .gap = .xs });
    _ = w.radio(u, @src(), "Low", &m.choice, @as(u8, 0), .{});
    _ = w.radio(u, @src(), "Medium", &m.choice, @as(u8, 1), .{ .debug_name = "option-medium" });
    _ = w.radio(u, @src(), "High", &m.choice, @as(u8, 2), .{});
    w.endRadioGroup(u);
    if (w.switchBox(u, @src(), "Use hardware acceleration", &m.switch_on, .{ .debug_name = "hardware-acceleration" }).changed) {
        m.status = if (m.switch_on) "Hardware acceleration on" else "Hardware acceleration off";
    }
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "list-panel", .layout = .{ .cross = .fill, .main = .fixedSize(180) } });
    sectionTitle(u, "List");
    var list_iter = w.beginList(u, @src(), 5, .{ .debug_name = "list", .data = .{ .ctx = null, .item_text = ListCtx.text }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (list_iter.next()) |row| w.listLabel(u, @src(), row, ListCtx.text(null, row.index), .{});
    _ = w.endList(u, &list_iter);
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "table-panel", .layout = .{ .cross = .fill, .main = .fixedSize(170) } });
    sectionTitle(u, "Table");
    const cols = [_]w.TableColumn{
        .{ .title = "Name", .width = .{ .grow = 2 } },
        .{ .title = "Count", .width = .{ .grow = 1 }, .h_align = .right },
        .{ .title = "State", .width = .{ .grow = 1 } },
    };
    var table = w.beginTable(u, @src(), &cols, 4, .{ .debug_name = "table", .data = .{ .ctx = null, .cell_text = TableCtx.cell }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (table.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| w.tableCellText(u, @src(), cell, TableCtx.cell(null, row.index, cell.column), .{});
    }
    _ = w.endTable(u);
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "tree-panel", .layout = .{ .cross = .fill, .main = .fixedSize(150) } });
    sectionTitle(u, "Tree");
    var tree_iter = w.beginTree(u, @src(), .{ .child_count = TreeCtx.childCount, .child_at = TreeCtx.childAt, .has_children = TreeCtx.hasChildren, .key_of = TreeCtx.keyOf, .text_of = TreeCtx.textOf }, .{ .debug_name = "tree", .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (tree_iter.next()) |row| w.treeLabel(u, @src(), row, TreeCtx.textOf(null, row.node), .{});
    _ = w.endTree(u);
    w.endPanel(u);
    u.endColumn();

    // 右列
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .md });
    _ = w.beginPanel(u, @src(), .{ .debug_name = "values-panel", .layout = .{ .cross = .fill } });
    sectionTitle(u, "Values");
    _ = w.label(u, @src(), "Volume", .{ .style = .small, .color = .secondary });
    if (w.slider(u, @src(), &m.volume, .{ .debug_name = "volume-slider", .layout = .{ .cross = .fill } }).changed) {
        m.status = "Volume changed";
    }
    _ = w.label(u, @src(), "Progress", .{ .style = .small, .color = .secondary });
    _ = w.progress(u, @src(), .{ .value = m.progress, .layout = .{ .cross = .fill } });
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "input-panel", .layout = .{ .cross = .fill } });
    sectionTitle(u, "Text input");
    _ = w.label(u, @src(), "Name", .{ .style = .small, .color = .secondary });
    const ti = w.textInput(u, @src(), &m.name, .{ .debug_name = "name-input", .placeholder = "Enter a name", .layout = .{ .cross = .fill } });
    if (ti.committed) m.status = "Name committed";
    _ = w.label(u, @src(), "Tab to focus, Enter to commit", .{ .style = .small, .color = .secondary });
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "more-panel", .layout = .{ .cross = .fill } });
    sectionTitle(u, "More controls");
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
    _ = w.comboBox(u, @src(), &m.combo, .{ .slice = &.{ "Alpha", "Beta", "Gamma" } }, .{ .debug_name = "combo", .layout = .{ .main = .{ .grow = 1 } } });
    _ = w.spinBoxInt(u, @src(), &m.spin, .{ .min = 0, .max = 100, .debug_name = "spin" });
    u.endRow();
    _ = w.textArea(u, @src(), .{ .debug_name = "notes", .placeholder = "Notes...", .layout = .{ .cross = .fill } });
    const dlg_buttons = [_]nano.app.DialogButton{
        .{ .label = "Cancel", .code = 2, .role = .cancel },
        .{ .label = "OK", .code = 1, .role = .default },
    };
    if (w.dialogButtons(u, @src(), &dlg_buttons)) |code| m.status = if (code == 1) "Dialog OK" else "Dialog Cancel";
    w.endPanel(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "tabs-panel", .layout = .{ .cross = .fill } });
    sectionTitle(u, "Tabs");
    if (w.tabs(u, @src(), .{ .items = &.{ "General", "Appearance", "Advanced" }, .selected = &m.tab }).changed) {
        m.status = "Tab changed";
    }
    _ = w.label(u, @src(), "This is the tab content area.", .{ .style = .small, .color = .secondary });
    w.endPanel(u);
    u.endColumn();
    u.endRow();
    _ = w.endScrollView(u, sv);

    // 状态栏
    _ = w.separator(u, @src(), .{ .structural = true });
    _ = w.beginStatusBar(u, @src(), .{});
    _ = w.label(u, @src(), m.status, .{ .style = .small, .color = .secondary });
    _ = u.spacer(@src(), 1);
    _ = w.label(u, @src(), if (m.dark) "Dark" else "Light", .{ .style = .small, .color = .secondary });
    w.endStatusBar(u);
    u.endColumn();
    _ = t;
}

fn dump(n: ?*ui.Node, depth: usize) void {
    const node = n orelse return;
    var i: usize = 0;
    while (i < depth) : (i += 1) std.debug.print("  ", .{});
    std.debug.print("{s} {s} r=({d},{d},{d},{d})\n", .{ @tagName(node.layout.kind), node.debug_name orelse "", node.rect.x, node.rect.y, node.rect.w, node.rect.h });
    var c = node.first_child;
    while (c) |cc| : (c = cc.next) dump(cc, depth + 1);
}

pub fn build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *Model = @ptrCast(@alignCast(ctx));
    page(u, m);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var m = try Model.init(gpa);
    defer m.deinit();
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Widget Gallery", .size = .{ .w = 960, .h = 620 } });
    defer app.deinit();
    app.io = init.io;

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer arg_it.deinit();
    var png_buf: [512]u8 = undefined;
    var png_path: ?[]const u8 = null;
    var dark = false;
    var debug_dump = false;
    var want_png = false;
    while (arg_it.next()) |a| {
        if (want_png) {
            const n = @min(a.len, png_buf.len);
            @memcpy(png_buf[0..n], a[0..n]);
            png_path = png_buf[0..n];
            want_png = false;
            continue;
        }
        if (std.mem.eql(u8, a, "--png")) want_png = true;
        if (std.mem.startsWith(u8, a, "--png=")) {
            const n = @min(a.len - 6, png_buf.len);
            @memcpy(png_buf[0..n], a[6 .. 6 + n]);
            png_path = png_buf[0..n];
        }
        if (std.mem.eql(u8, a, "--dark")) dark = true;
        if (std.mem.eql(u8, a, "--debug")) debug_dump = true;
    }
    m.dark = dark;
    app.setMode(if (dark) .dark else .light);
    app.renderOnce(&m, build);
    // 第二帧让滚动/焦点状态稳定，并写入截图。
    app.ui_state.invalidate(.paint);
    _ = app.step();
    if (png_path) |p| {
        try app.savePngIo(init.io, p);
        try std.Io.File.stdout().writeStreamingAll(init.io, p);
        try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
    }
    if (debug_dump) dump(app.ui_state.current_root, 0);
    const out = try std.fmt.allocPrint(gpa, "gallery: frames={d} nodes={d} damage={d} theme={s}\n", .{ app.frames, app.ui_state.node_count, app.ui_state.last_damage_area, @tagName(app.theme_state.mode) });
    defer gpa.free(out);
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
