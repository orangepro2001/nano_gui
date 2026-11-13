//! M6 示例应用 ②：数据浏览器（左树 + 百万行虚拟表格 + 右侧属性面板）。
//! 运行：zig build run-data_browser

const std = @import("std");
const nano = @import("nano_gui");
const w = nano.widgets;
const ui = nano.ui;
const core = nano.core;

pub const Model = struct {
    row_count: usize = 1_000_000,
    selected_table: usize = 0,
    sort: w.TableSort = .{ .column = 0, .dir = .asc },
    sel: w.Selection,
    filter: w.TextBuf,
    split_main: nano.layout.SplitPos = .{ .fixed_first = 220 },
    split_right: nano.layout.SplitPos = .{ .fixed_second = 240 },
    status: []const u8 = "已连接 1,000,000 行数据集",
    revision: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !Model {
        return .{
            .sel = w.Selection.init(allocator),
            .filter = try w.TextBuf.initFrom(allocator, ""),
        };
    }
    pub fn deinit(self: *Model) void {
        self.sel.deinit();
        self.filter.deinit();
    }
    pub fn changed(self: *Model) void {
        self.revision += 1;
    }
};

const TreeModelCtx = struct {
    fn childCount(_: ?*anyopaque, node: w.TreeNode) usize {
        if (node == .root) return 4;
        if (@backingInt(node) <= 4) return 5;
        return 0;
    }
    fn childAt(_: ?*anyopaque, node: w.TreeNode, index: usize) w.TreeNode {
        if (node == .root) return @fromBackingInt(@intCast(index + 1));
        return @fromBackingInt(@intCast(@backingInt(node) * 100 + index + 1));
    }
    fn hasChildren(_: ?*anyopaque, node: w.TreeNode) bool {
        return node == .root or @backingInt(node) <= 4;
    }
    fn keyOf(_: ?*anyopaque, node: w.TreeNode) w.ItemKey {
        return @backingInt(node);
    }
    var bufs: [8][32]u8 = undefined;
    var bi: usize = 0;
    fn textOf(_: ?*anyopaque, node: w.TreeNode) []const u8 {
        bi = (bi + 1) % bufs.len;
        const id = @backingInt(node);
        if (id <= 4) return std.fmt.bufPrint(&bufs[bi], "Schema {d}", .{id}) catch "Schema";
        return std.fmt.bufPrint(&bufs[bi], "Table_{d}", .{id}) catch "Table";
    }
};

const DataTableCtx = struct {
    var bufs: [16][32]u8 = undefined;
    var bi: usize = 0;
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        bi = (bi + 1) % bufs.len;
        return switch (col) {
            0 => std.fmt.bufPrint(&bufs[bi], "{d}", .{row + 1}) catch "0",
            1 => std.fmt.bufPrint(&bufs[bi], "record_{d}", .{row + 1}) catch "rec",
            2 => if (row % 2 == 0) "INT64" else "UTF8",
            3 => std.fmt.bufPrint(&bufs[bi], "{d:.2}", .{@as(f64, @floatFromInt((row * 17) % 10000)) / 100.0}) catch "0.00",
            4 => if (row % 5 == 0) "INDEXED" else "ACTIVE",
            else => "OK",
        };
    }
};

const data_cols = [_]w.TableColumn{
    .{ .title = "ID", .width = .{ .fixed = 84 }, .h_align = .right, .font = .mono, .sortable = true },
    .{ .title = "名称", .width = .{ .grow = 2 }, .sortable = true },
    .{ .title = "类型", .width = .{ .fixed = 80 } },
    .{ .title = "数值", .width = .{ .fixed = 90 }, .h_align = .right, .font = .mono, .sortable = true },
    .{ .title = "状态", .width = .{ .fixed = 84 } },
    .{ .title = "校验", .width = .{ .fixed = 64 } },
};

pub fn page(u: *ui.Ui, m: *Model) void {
    const t = u.theme_ptr;
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(t.metric(.gap_xs)), .gap = .xs });

    _ = w.beginToolbar(u, @src(), .{ .debug_name = "browser-toolbar" });
    _ = w.label(u, @src(), "过滤:", .{ .style = .small, .color = .secondary });
    _ = w.textInput(u, @src(), &m.filter, .{ .debug_name = "filter-input", .placeholder = "按记录过滤..." });
    w.toolbarSpacer(u, @src());
    if (w.toolbarButton(u, @src(), "刷新", .{ .icon = .{ .mark = .info } }).clicked) {
        m.status = "数据视图已刷新";
        m.changed();
    }
    w.endToolbar(u);

    const sp_main = w.beginSplitter(u, @src(), .{ .orientation = .horizontal, .pos = &m.split_main, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    var tree_iter = w.beginTree(u, @src(), .{
        .child_count = TreeModelCtx.childCount,
        .child_at = TreeModelCtx.childAt,
        .has_children = TreeModelCtx.hasChildren,
        .key_of = TreeModelCtx.keyOf,
        .text_of = TreeModelCtx.textOf,
    }, .{ .debug_name = "schema-tree", .initially_expanded_depth = 1, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (tree_iter.next()) |row| w.treeLabel(u, @src(), row, TreeModelCtx.textOf(null, row.node), .{});
    _ = w.endTree(u);

    const sp_right = w.beginSplitter(u, @src(), .{ .orientation = .horizontal, .pos = &m.split_right, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    var tbl = w.beginTable(u, @src(), &data_cols, m.row_count, .{
        .debug_name = "million-table",
        .selection = &m.sel,
        .sort = &m.sort,
        .data = .{ .ctx = null, .cell_text = DataTableCtx.cell },
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    while (tbl.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| w.tableCellText(u, @src(), cell, DataTableCtx.cell(null, row.index, cell.column), .{});
    }
    const tres = w.endTable(u);

    _ = w.beginPanel(u, @src(), .{ .debug_name = "inspector-panel", .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    _ = w.label(u, @src(), "属性面板", .{ .style = .body_strong });
    _ = w.separator(u, @src(), .{});
    const row_txt = std.fmt.allocPrint(u.treeAlloc(), "当前总行数: {d}", .{m.row_count}) catch "";
    _ = w.label(u, @src(), row_txt, .{ .key = ui.Key.str("row-count"), .style = .small });
    const sel_txt = std.fmt.allocPrint(u.treeAlloc(), "已选可见行: {d}", .{tres.selected_visible}) catch "";
    _ = w.label(u, @src(), sel_txt, .{ .key = ui.Key.str("sel-count"), .style = .small, .color = .secondary });
    w.endPanel(u);
    _ = w.endSplitter(u, sp_right);
    _ = w.endSplitter(u, sp_main);

    _ = w.separator(u, @src(), .{ .structural = true });
    _ = w.beginStatusBar(u, @src(), .{});
    _ = w.label(u, @src(), m.status, .{ .style = .small, .color = .secondary });
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
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Data Browser", .size = .{ .w = 1120, .h = 680 } });
    defer app.deinit();
    app.renderOnce(&m, build);
    const out = try std.fmt.allocPrint(gpa, "data_browser: frames={d} nodes={d}\n", .{ app.frames, app.ui_state.node_count });
    defer gpa.free(out);
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
