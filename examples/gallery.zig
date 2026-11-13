//! “控件总览”示例（参考界面 G）：涵盖菜单栏、工具栏、6 页标签、基础/输入/列表(1万行)/树/表格(10万行×12列)/布局/文字/状态栏，稳定节点数 1400–1600。
//! 运行：zig build run-gallery -- --png /tmp/gallery.png

const std = @import("std");
const nano = @import("nano_gui");
const w = nano.widgets;
const ui = nano.ui;
const core = nano.core;
const theme = nano.theme;
const layout = nano.layout;

pub const Model = struct {
    allocator: std.mem.Allocator,
    clicks: u32 = 0,
    checked: bool = true,
    unchecked: bool = false,
    mixed: w.CheckState = .mixed,
    choice: u8 = 1,
    choice2: u8 = 2,
    switch_on: bool = true,
    switch_off: bool = false,
    volume: f32 = 0.62,
    s_h1: f32 = 0.25,
    s_h2: f32 = 0.50,
    s_h3: f32 = 0.75,
    s_v1: f32 = 0.40,
    s_v2: f32 = 0.80,
    progress: f32 = 0.38,
    tab: usize = 0,
    name: w.TextBuf,
    search: w.TextBuf,
    ro_buf: w.TextBuf,
    dis_buf: w.TextBuf,
    pwd_buf: w.TextBuf,
    err_buf: w.TextBuf,
    clr_buf: w.TextBuf,
    combo_buf: w.TextBuf,
    status: []const u8 = "Ready",
    dark: bool = false,
    combo: ?u32 = 0,
    toolbar_combo: ?u32 = 0,
    spin: i64 = 42,
    spin_f: f64 = 3.14,
    table_sort: w.TableSort = .{ .column = 0, .dir = .asc },
    revision: u64 = 0,
    items: [100]u16 = @splat(0),
    var_text_toggle: bool = false,
    ta_seeded: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Model {
        return .{
            .allocator = allocator,
            .name = try w.TextBuf.initFrom(allocator, "nano_gui"),
            .search = try w.TextBuf.initFrom(allocator, ""),
            .ro_buf = try w.TextBuf.initFrom(allocator, "只读内容"),
            .dis_buf = try w.TextBuf.initFrom(allocator, "禁用内容"),
            .pwd_buf = try w.TextBuf.initFrom(allocator, "secret123"),
            .err_buf = try w.TextBuf.initFrom(allocator, "invalid!"),
            .clr_buf = try w.TextBuf.initFrom(allocator, "可清除文本"),
            .combo_buf = try w.TextBuf.initFrom(allocator, "可编辑选项"),
        };
    }
    pub fn deinit(self: *Model) void {
        self.name.deinit();
        self.search.deinit();
        self.ro_buf.deinit();
        self.dis_buf.deinit();
        self.pwd_buf.deinit();
        self.err_buf.deinit();
        self.clr_buf.deinit();
        self.combo_buf.deinit();
    }

    pub fn changed(self: *Model) void {
        self.revision += 1;
    }

    pub fn setStatus(self: *Model, status: []const u8) void {
        if (std.mem.eql(u8, self.status, status)) return;
        self.status = status;
        self.changed();
    }

    pub fn toggleDark(self: *Model, status: []const u8) void {
        self.dark = !self.dark;
        self.status = status;
        self.changed();
    }

    pub fn bumpClicks(self: *Model, status: []const u8) void {
        self.clicks += 1;
        self.status = status;
        self.changed();
    }

    pub fn resetAll(self: *Model, status: []const u8) void {
        self.clicks = 0;
        self.checked = true;
        self.mixed = .mixed;
        self.choice = 1;
        self.switch_on = true;
        self.volume = 0.62;
        self.status = status;
        self.changed();
    }

    /// 批量变更只通知一次（AC-APP-028）。
    pub fn applyBulk(self: *Model, value: u16) void {
        for (&self.items) |*item| item.* = value;
        self.changed();
    }
};

const TableCtx = struct {
    var cell_bufs: [16][32]u8 = undefined;
    var cell_idx: usize = 0;

    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        cell_idx = (cell_idx + 1) % cell_bufs.len;
        const buf = &cell_bufs[cell_idx];
        return switch (col) {
            0 => std.fmt.bufPrint(buf, "Row #{d}", .{row + 1}) catch "Row",
            1 => std.fmt.bufPrint(buf, "{d} KB", .{(row * 37 + 13) % 9999}) catch "0 KB",
            2 => if (row % 3 == 0) "Active" else if (row % 3 == 1) "Idle" else "Warn",
            else => std.fmt.bufPrint(buf, "C{d}:{d}", .{ col, (row + col) % 100 }) catch "-",
        };
    }
};

const TreeCtx = struct {
    // 3 层确定树：根 25 个分支，每个分支 20 个叶节点（展开约 525 节点）。
    fn childCount(_: ?*anyopaque, node: w.TreeNode) usize {
        const raw = @backingInt(node);
        if (node == .root) return 25;
        if (raw >= 1 and raw <= 25) return 20;
        return 0;
    }
    fn childAt(_: ?*anyopaque, node: w.TreeNode, index: usize) w.TreeNode {
        const raw = @backingInt(node);
        if (node == .root) return @fromBackingInt(@intCast(index + 1));
        return @fromBackingInt(@intCast(100 + raw * 100 + index));
    }
    fn hasChildren(_: ?*anyopaque, node: w.TreeNode) bool {
        const raw = @backingInt(node);
        return node == .root or (raw >= 1 and raw <= 25);
    }
    fn keyOf(_: ?*anyopaque, node: w.TreeNode) w.ItemKey {
        return @backingInt(node);
    }
    var tree_bufs: [8][32]u8 = undefined;
    var tree_idx: usize = 0;
    fn textOf(_: ?*anyopaque, node: w.TreeNode) []const u8 {
        const raw = @backingInt(node);
        tree_idx = (tree_idx + 1) % tree_bufs.len;
        const buf = &tree_bufs[tree_idx];
        if (raw >= 1 and raw <= 25) {
            return std.fmt.bufPrint(buf, "Branch {d}", .{raw}) catch "Branch";
        }
        return std.fmt.bufPrint(buf, "Node {d}", .{raw}) catch "Node";
    }
};

const ListCtx = struct {
    var list_bufs: [8][32]u8 = undefined;
    var list_idx: usize = 0;
    fn text(_: ?*anyopaque, index: usize) []const u8 {
        list_idx = (list_idx + 1) % list_bufs.len;
        return std.fmt.bufPrint(&list_bufs[list_idx], "Virtual item #{d}", .{index + 1}) catch "Item";
    }
};

const table_cols_12 = [_]w.TableColumn{
    .{ .title = "Name", .width = .{ .grow = 2 }, .sortable = true },
    .{ .title = "Size", .width = .{ .fixed = 76 }, .h_align = .right, .font = .mono, .sortable = true },
    .{ .title = "State", .width = .{ .fixed = 64 }, .sortable = true },
    .{ .title = "Col3", .width = .{ .fixed = 56 }, .sortable = true },
    .{ .title = "Col4", .width = .{ .fixed = 56 } },
    .{ .title = "Col5", .width = .{ .fixed = 56 } },
    .{ .title = "Col6", .width = .{ .fixed = 56 } },
    .{ .title = "Col7", .width = .{ .fixed = 56 } },
    .{ .title = "Col8", .width = .{ .fixed = 56 } },
    .{ .title = "Col9", .width = .{ .fixed = 56 } },
    .{ .title = "Col10", .width = .{ .fixed = 56 } },
    .{ .title = "Col11", .width = .{ .fixed = 56 } },
};

fn buildBasics(u: *ui.Ui, m: *Model) void {
    _ = w.beginGroupBox(u, @src(), .{ .title = "基础控件矩阵", .layout = .{ .cross = .fill } });

    // 按钮子组：3 变体 × 3 尺寸 × 启用/禁用 + 图标按钮 + 状态行
    _ = w.beginGroupBox(u, @src(), .{ .title = "按钮矩阵", .layout = .{ .cross = .fill } });
    const variants = [_]w.ButtonVariant{ .neutral, .accent, .quiet };
    const sizes = [_]w.ControlSize{ .sm, .md, .lg };
    for (variants, 0..) |v, vi| {
        u.pushId(ui.Key.int(vi + 1));
        _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
        for (sizes, 0..) |sz, si| {
            u.pushId(ui.Key.int(si + 1));
            const label_txt = if (v == .accent and sz == .md) "Primary" else if (v == .neutral and sz == .md) "Secondary" else "Btn";
            const dname: ?[]const u8 = if (v == .accent and sz == .md) "primary-button" else if (v == .neutral and sz == .md) "secondary-button" else null;
            if (w.button(u, @src(), label_txt, .{ .variant = v, .size = sz, .debug_name = dname }).clicked) {
                m.bumpClicks("Button clicked");
            }
            _ = w.button(u, @src(), "Dis", .{ .variant = v, .size = sz, .enabled = false });
            _ = w.button(u, @src(), "Ic", .{ .variant = v, .size = sz, .icon = .{ .mark = .check } });
            u.popId();
        }
        if (vi == 0) {
            if (w.button(u, @src(), "With Icon", .{ .icon = .{ .mark = .info } }).clicked) m.setStatus("Info");
            if (w.button(u, @src(), "", .{ .icon = .{ .mark = .search }, .tooltip = "Search", .debug_name = "search-button" }).clicked) m.setStatus("Search");
        }
        u.endRow();
        u.popId();
    }
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .xs, .cross_align = .center });
    _ = w.label(u, @src(), "Clicks:", .{ .style = .small, .color = .secondary });
    const count_text = std.fmt.allocPrint(u.treeAlloc(), "{d}", .{m.clicks}) catch "0";
    _ = w.label(u, @src(), count_text, .{ .key = ui.Key.str("click-count"), .style = .body_strong, .color = .info });
    _ = w.label(u, @src(), if (m.var_text_toggle) "Variable text expanded" else "Var", .{ .key = ui.Key.str("var-leaf"), .debug_name = "var-leaf", .style = .small });
    u.endRow();
    w.endGroupBox(u);

    // 勾选、单选、开关、标记子组
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .lg, .cross_align = .start });
    _ = w.beginGroupBox(u, @src(), .{ .title = "勾选框" });
    if (w.checkbox(u, @src(), "Enable auto update", &m.checked, .{ .debug_name = "auto-update" }).changed) {
        m.setStatus(if (m.checked) "Auto update on" else "Auto update off");
    }
    _ = w.checkbox(u, @src(), "Unchecked", &m.unchecked, .{});
    _ = w.checkboxTri(u, @src(), "Tri-state", &m.mixed, .{});
    _ = w.checkbox(u, @src(), "Dis On", &m.checked, .{ .enabled = false });
    _ = w.checkbox(u, @src(), "Dis Off", &m.unchecked, .{ .enabled = false });
    _ = w.checkboxTri(u, @src(), "Dis Mix", &m.mixed, .{ .enabled = false });
    w.endGroupBox(u);

    _ = w.beginGroupBox(u, @src(), .{ .title = "单选组 A" });
    _ = w.beginRadioGroup(u, @src(), .{ .gap = .xs });
    _ = w.radio(u, @src(), "Low", &m.choice, @as(u8, 0), .{});
    _ = w.radio(u, @src(), "Medium", &m.choice, @as(u8, 1), .{ .debug_name = "option-medium" });
    _ = w.radio(u, @src(), "High", &m.choice, @as(u8, 2), .{});
    _ = w.radio(u, @src(), "Ultra", &m.choice, @as(u8, 3), .{});
    w.endRadioGroup(u);
    w.endGroupBox(u);

    _ = w.beginGroupBox(u, @src(), .{ .title = "单选组 B" });
    _ = w.beginRadioGroup(u, @src(), .{ .gap = .xs });
    _ = w.radio(u, @src(), "Mode A", &m.choice2, @as(u8, 0), .{});
    _ = w.radio(u, @src(), "Mode B", &m.choice2, @as(u8, 1), .{});
    _ = w.radio(u, @src(), "Mode C", &m.choice2, @as(u8, 2), .{});
    _ = w.radio(u, @src(), "Mode D", &m.choice2, @as(u8, 3), .{ .enabled = false });
    w.endRadioGroup(u);
    w.endGroupBox(u);

    _ = w.beginGroupBox(u, @src(), .{ .title = "开关与标签" });
    if (w.switchBox(u, @src(), "Hardware accel", &m.switch_on, .{ .debug_name = "hardware-acceleration" }).changed) {
        m.setStatus(if (m.switch_on) "Hardware accel on" else "Hardware accel off");
    }
    _ = w.switchBox(u, @src(), "Switch off", &m.switch_off, .{});
    _ = w.switchBox(u, @src(), "Switch disabled", &m.switch_on, .{ .enabled = false });
    _ = w.label(u, @src(), "Docs Link", .{ .variant = .link });
    _ = w.label(u, @src(), "Title style", .{ .style = .title });
    _ = w.label(u, @src(), "Body strong", .{ .style = .body_strong });
    _ = w.label(u, @src(), "Danger hint", .{ .style = .small, .color = .danger });
    _ = w.label(u, @src(), "Success hint", .{ .style = .small, .color = .success });
    w.endGroupBox(u);
    u.endRow();

    // 图像与标记
    _ = w.beginGroupBox(u, @src(), .{ .title = "标记与图像", .layout = .{ .cross = .fill } });
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
    const marks = [_]theme.MarkKind{ .check, .info, .warning, .@"error", .success, .search, .more, .close, .sort_asc, .sort_desc, .grip, .chevron_right };
    for (marks, 0..) |mk, i| {
        u.pushId(ui.Key.int(i + 10));
        _ = w.label(u, @src(), "", .{ .icon = .{ .mark = mk } });
        u.popId();
    }
    _ = w.image(u, @src(), null, .{});
    _ = w.image(u, @src(), null, .{});
    _ = w.image(u, @src(), null, .{});
    _ = w.image(u, @src(), null, .{});
    u.endRow();
    w.endGroupBox(u);

    w.endGroupBox(u);
}

fn buildInputs(u: *ui.Ui, m: *Model) void {
    _ = w.beginGroupBox(u, @src(), .{ .title = "输入控件表单", .layout = .{ .cross = .fill } });
    _ = u.beginForm(@src(), .{ .cross = .fill, .gap = .xs }, .{});
    _ = w.label(u, @src(), "常态输入", .{});
    if (w.textInput(u, @src(), &m.name, .{ .debug_name = "name-input", .placeholder = "Enter a name", .layout = .{ .cross = .fill } }).committed) {
        m.setStatus("Name committed");
    }
    _ = w.label(u, @src(), "占位提示", .{});
    _ = w.textInput(u, @src(), &m.search, .{ .placeholder = "请输入关键字...", .layout = .{ .cross = .fill } });
    _ = w.label(u, @src(), "只读输入", .{});
    _ = w.textInput(u, @src(), &m.ro_buf, .{ .read_only = true, .layout = .{ .cross = .fill } });
    _ = w.label(u, @src(), "禁用输入", .{});
    _ = w.textInput(u, @src(), &m.dis_buf, .{ .enabled = false, .layout = .{ .cross = .fill } });
    _ = w.label(u, @src(), "密码输入", .{});
    _ = w.textInput(u, @src(), &m.pwd_buf, .{ .password = true, .layout = .{ .cross = .fill } });
    _ = w.label(u, @src(), "校验失败", .{});
    _ = w.textInput(u, @src(), &m.err_buf, .{ .invalid = true, .layout = .{ .cross = .fill } });
    _ = w.label(u, @src(), "带清除", .{});
    _ = w.textInput(u, @src(), &m.clr_buf, .{ .clear_button = true, .layout = .{ .cross = .fill } });
    _ = w.label(u, @src(), "整数微调", .{});
    _ = w.spinBoxInt(u, @src(), &m.spin, .{ .min = 0, .max = 100, .debug_name = "spin" });
    _ = w.label(u, @src(), "小数微调", .{});
    _ = w.spinBoxFloat(u, @src(), &m.spin_f, .{ .min = 0, .max = 100, .step = 0.5 });
    _ = w.label(u, @src(), "下拉列表", .{});
    _ = w.comboBox(u, @src(), &m.combo, .{ .slice = &.{ "Alpha", "Beta", "Gamma", "Delta" } }, .{ .debug_name = "combo", .layout = .{ .main = .{ .grow = 1 } } });
    _ = w.label(u, @src(), "可编辑下拉", .{});
    _ = w.comboBoxEditable(u, @src(), &m.combo_buf, .{ .slice = &.{ "Option 1", "Option 2", "Option 3" } }, .{});
    _ = w.label(u, @src(), "滑块组", .{});
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
    if (w.slider(u, @src(), &m.volume, .{ .debug_name = "volume-slider" }).changed) m.setStatus("Volume changed");
    _ = w.slider(u, @src(), &m.s_h1, .{});
    _ = w.slider(u, @src(), &m.s_h2, .{});
    _ = w.slider(u, @src(), &m.s_h3, .{});
    _ = w.slider(u, @src(), &m.s_v1, .{ .orientation = .vertical });
    _ = w.slider(u, @src(), &m.s_v2, .{ .orientation = .vertical });
    u.endRow();
    _ = w.label(u, @src(), "进度条", .{});
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fill, .gap = .xs });
    _ = w.progress(u, @src(), .{ .value = m.progress, .layout = .{ .cross = .fill } });
    _ = w.progress(u, @src(), .{ .value = 0.72, .layout = .{ .cross = .fill } });
    _ = w.progress(u, @src(), .{ .value = 1.0, .layout = .{ .cross = .fill } });
    _ = w.progress(u, @src(), .{ .indeterminate = true, .layout = .{ .cross = .fill } });
    u.endColumn();
    _ = w.label(u, @src(), "多行文本", .{});
    const seed_ta = comptime blk: {
        var buf: [4096]u8 = undefined;
        var pos: usize = 0;
        var li: usize = 0;
        while (li < 200 and pos + 24 < buf.len) : (li += 1) {
            const digits = [3]u8{ '0' + @as(u8, @intCast((li + 1) / 100)), '0' + @as(u8, @intCast(((li + 1) / 10) % 10)), '0' + @as(u8, @intCast((li + 1) % 10)) };
            const pre = "Line ";
            const suf = ": sample text\n";
            @memcpy(buf[pos .. pos + pre.len], pre);
            pos += pre.len;
            @memcpy(buf[pos .. pos + 3], &digits);
            pos += 3;
            @memcpy(buf[pos .. pos + suf.len], suf);
            pos += suf.len;
        }
        const final = buf[0..pos].*;
        break :blk final;
    };
    _ = w.textArea(u, @src(), .{ .debug_name = "notes", .placeholder = "Notes...", .initial_text = &seed_ta, .layout = .{ .cross = .fill } });
    u.endForm();
    const dlg_buttons = [_]nano.app.DialogButton{
        .{ .label = "Cancel", .code = 2, .role = .cancel },
        .{ .label = "OK", .code = 1, .role = .default },
    };
    if (w.dialogButtons(u, @src(), &dlg_buttons)) |code| m.setStatus(if (code == 1) "Dialog OK" else "Dialog Cancel");
    w.endGroupBox(u);
}

fn buildListAndTree(u: *ui.Ui) void {
    const t = u.theme_ptr;
    _ = w.beginGroupBox(u, @src(), .{ .title = "虚拟列表（1万行）与树", .layout = .{ .cross = .fill, .main = .fixedSize(t.metric(.control_h) * 20) } });
    const sp1 = w.beginSplitter(u, @src(), .{ .orientation = .horizontal, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    var list_iter = w.beginList(u, @src(), 10_000, .{ .debug_name = "list", .mode = .multi, .data = .{ .ctx = null, .item_text = ListCtx.text }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (list_iter.next()) |row| w.listLabel(u, @src(), row, ListCtx.text(null, row.index), .{});
    _ = w.endList(u, &list_iter);

    var tree_iter = w.beginTree(u, @src(), .{ .child_count = TreeCtx.childCount, .child_at = TreeCtx.childAt, .has_children = TreeCtx.hasChildren, .key_of = TreeCtx.keyOf, .text_of = TreeCtx.textOf }, .{ .debug_name = "tree", .initially_expanded_depth = 1, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (tree_iter.next()) |row| w.treeLabel(u, @src(), row, TreeCtx.textOf(null, row.node), .{});
    _ = w.endTree(u);
    _ = w.endSplitter(u, sp1);
    w.endGroupBox(u);
}

fn buildTableSection(u: *ui.Ui, m: *Model) void {
    const t = u.theme_ptr;
    _ = w.beginGroupBox(u, @src(), .{ .title = "虚拟表格（10万行×12列）", .layout = .{ .cross = .fill, .main = .fixedSize(t.metric(.control_h) * 18) } });
    var table = w.beginTable(u, @src(), &table_cols_12, 100_000, .{ .debug_name = "table", .sort = &m.table_sort, .data = .{ .ctx = null, .cell_text = TableCtx.cell }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (table.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| w.tableCellText(u, @src(), cell, TableCtx.cell(null, row.index, cell.column), .{});
    }
    _ = w.endTable(u);
    w.endGroupBox(u);
}

fn buildLayoutSection(u: *ui.Ui) void {
    const t = u.theme_ptr;
    _ = w.beginGroupBox(u, @src(), .{ .title = "嵌套布局与分隔演示", .layout = .{ .cross = .fill } });
    var r: usize = 0;
    while (r < 92) : (r += 1) {
        u.pushId(ui.Key.int(r + 1));
        _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .sm, .cross_align = .center });
        _ = u.beginStack(@src(), .{ .main = .fit, .cross = .fit });
        _ = w.label(u, @src(), "Stack", .{ .style = .small, .color = .secondary });
        _ = w.label(u, @src(), "Top", .{ .style = .small });
        u.endStack();
        _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fit, .gap = .xs });
        _ = w.label(u, @src(), "Grow", .{ .style = .small, .layout = .{ .main = .{ .grow = 1 } } });
        _ = w.label(u, @src(), "Shrinkable layout text item", .{ .style = .small, .layout = .{ .main = .fit_shrink } });
        u.endColumn();
        _ = w.button(u, @src(), "L", .{ .variant = .quiet, .size = .sm });
        _ = w.label(u, @src(), "Tag", .{ .style = .small, .color = .info });
        u.endRow();
        u.popId();
    }
    const sp2 = w.beginSplitter(u, @src(), .{ .orientation = .vertical, .layout = .{ .main = .fixedSize(t.metric(.control_h) * 3), .cross = .fill } });
    const nsv = w.beginScrollView(u, @src(), .{ .axes = .vertical, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    _ = w.label(u, @src(), "Nested scroll top", .{ .style = .small });
    _ = w.endScrollView(u, nsv);
    _ = w.label(u, @src(), "Nested split bottom", .{ .style = .small });
    _ = w.endSplitter(u, sp2);
    w.endGroupBox(u);
}

fn buildTextSection(u: *ui.Ui) void {
    _ = w.beginGroupBox(u, @src(), .{ .title = "文字排版示例（60 标签）", .layout = .{ .cross = .fill } });
    var i: usize = 0;
    while (i < 35) : (i += 1) {
        u.pushId(ui.Key.int(i + 1));
        _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .gap = .md, .cross_align = .center });
        _ = w.label(u, @src(), "中英混排 Mixed Text", .{ .style = .body });
        _ = w.label(u, @src(), "超长文本省略验证示例字符串", .{ .style = .body_strong, .layout = .{ .main = .fit_shrink } });
        _ = w.label(u, @src(), "123,456.78", .{ .style = .mono, .color = .secondary });
        _ = w.label(u, @src(), "Small", .{ .style = .small, .color = .secondary });
        u.endRow();
        u.popId();
    }
    w.endGroupBox(u);
}

pub fn page(u: *ui.Ui, m: *Model) void {
    TableCtx.cell_idx = 0;
    TreeCtx.tree_idx = 0;
    ListCtx.list_idx = 0;
    const t = u.theme_ptr;
    _ = u.beginColumn(@src(), .{
        .main = .{ .grow = 1 },
        .cross = .fill,
        .padding = core.Insets.all(t.metric(.pad_panel)),
        .gap = .sm,
        .clip = true,
    });

    // 标题栏
    _ = u.beginRow(@src(), .{ .main = .fixedSize(t.metric(.control_h_lg)), .cross = .fill, .gap = .md, .cross_align = .center });
    _ = w.label(u, @src(), "Instrument Widget Gallery", .{ .style = .title });
    _ = u.spacer(@src(), 1);
    if (w.button(u, @src(), if (m.dark) "Light" else "Dark", .{ .variant = .quiet, .debug_name = "theme-button" }).clicked) {
        m.toggleDark(if (m.dark) "Switched to light theme" else "Switched to dark theme");
    }
    if (w.button(u, @src(), "Reset", .{ .variant = .quiet, .debug_name = "reset-button" }).clicked) {
        m.resetAll("Reset");
    }
    u.endRow();

    // 菜单栏（5 个顶层菜单）
    _ = w.beginMenuBar(u, @src(), .{ .debug_name = "menu-bar" });
    const menus = [_][]const u8{ "File", "Edit", "View", "Tools", "Help" };
    for (menus, 0..) |mn, mi| {
        u.pushId(ui.Key.int(mi + 1));
        if (w.beginMenu(u, @src(), mn, .{})) {
            if (w.menuItem(u, @src(), "Reset", .{ .shortcut_text = "Ctrl+R" }).clicked) m.resetAll("Reset from menu");
            if (w.menuItem(u, @src(), "Theme", .{ .checked = m.dark }).clicked) m.toggleDark("Theme from menu");
            w.menuSeparator(u, @src());
            if (w.menuItem(u, @src(), "Action A", .{}).clicked) m.setStatus("Action A");
            if (w.menuItem(u, @src(), "Action B", .{}).clicked) m.setStatus("Action B");
            if (w.menuItem(u, @src(), "Action C", .{}).clicked) m.setStatus("Action C");
            if (w.menuItem(u, @src(), "About", .{}).clicked) m.setStatus("nano_gui 0.1");
            w.endMenu(u);
        }
        u.popId();
    }
    w.endMenuBar(u);

    // 工具栏（12 命令按钮、3 分隔符、1 下拉、1 搜索框、溢出按钮）
    _ = w.beginToolbar(u, @src(), .{ .debug_name = "toolbar" });
    var tb_i: usize = 0;
    while (tb_i < 12) : (tb_i += 1) {
        u.pushId(ui.Key.int(tb_i + 1));
        if (tb_i == 4 or tb_i == 8 or tb_i == 11) w.toolbarSeparator(u, @src());
        if (w.toolbarButton(u, @src(), "Cmd", .{ .icon = .{ .mark = if (tb_i == 0) .search else .check }, .show_text = tb_i < 4 }).clicked) {
            m.bumpClicks("Toolbar cmd");
        }
        u.popId();
    }
    _ = w.comboBox(u, @src(), &m.toolbar_combo, .{ .slice = &.{ "100%", "125%", "150%" } }, .{});
    _ = w.textInput(u, @src(), &m.search, .{ .debug_name = "toolbar-search", .placeholder = "Search..." });
    w.toolbarSpacer(u, @src());
    _ = w.toolbarButton(u, @src(), "More", .{ .icon = .{ .mark = .more }, .show_text = false });
    w.endToolbar(u);

    // 6 页标签条
    if (w.tabs(u, @src(), .{ .items = &.{ "全部", "基础", "输入", "列表", "表格", "文字" }, .selected = &m.tab }).changed) {
        m.setStatus("Tab changed");
    }

    // 主滚动区域
    const sv = w.beginScrollView(u, @src(), .{ .debug_name = "总览滚动区", .axes = .vertical, .bar_v = .auto, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fill, .gap = .md });
    switch (m.tab) {
        0 => {
            buildBasics(u, m);
            buildInputs(u, m);
            buildListAndTree(u);
            buildTableSection(u, m);
            buildLayoutSection(u);
            buildTextSection(u);
        },
        1 => buildBasics(u, m),
        2 => buildInputs(u, m),
        3 => buildListAndTree(u),
        4 => buildTableSection(u, m),
        else => buildTextSection(u),
    }
    u.endColumn();
    _ = w.endScrollView(u, sv);

    // 状态栏（4 窗格，含进度条）
    _ = w.separator(u, @src(), .{ .structural = true });
    _ = w.beginStatusBar(u, @src(), .{});
    _ = w.label(u, @src(), m.status, .{ .style = .small, .color = .secondary });
    _ = u.spacer(@src(), 1);
    _ = w.progress(u, @src(), .{ .value = m.progress });
    _ = w.label(u, @src(), "100%", .{ .style = .small, .color = .secondary });
    _ = w.label(u, @src(), if (m.dark) "Dark" else "Light", .{ .style = .small, .color = .secondary });
    w.endStatusBar(u);
    u.endColumn();
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
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Widget Gallery", .size = .{ .w = 1280, .h = 800 } });
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
