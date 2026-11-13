//! 金图工具：无头渲染确定性场景，与基准 PNG 逐像素比对。
//! 用法：
//!   golden                 检查全部用例
//!   golden --write         写入全部用例
//!   golden --check <目录>  只检查 smoke 用例（兼容旧调用）
//!   golden --write <目录>  只写入 smoke 用例

const std = @import("std");
const nano = @import("nano_gui");
const ui = nano.ui;
const w = nano.widgets;
const core = nano.core;
const theme = nano.theme;
const layout = nano.layout;

var checked: bool = true;

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

// ---------------------------------------------------------------------------
// 布局标尺页（AC-LAYOUT-028）
// ---------------------------------------------------------------------------

const BlockProps = struct { token: theme.ColorToken };
var block_seq: u64 = 0;

fn paintBlock(ctx: *ui.PaintCtx, node: *const ui.Node) void {
    const p: *const BlockProps = @ptrCast(@alignCast(node.props.?));
    const r = ctx.rect(node);
    const t = ctx.draw.theme;
    ctx.draw.canvas.fillRect(r, t.color(p.token));
    const line = t.color(.border_strong);
    const px = 1.0;
    ctx.draw.canvas.fillRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = px }, line);
    ctx.draw.canvas.fillRect(.{ .x = r.x, .y = r.y + r.h - px, .w = r.w, .h = px }, line);
    ctx.draw.canvas.fillRect(.{ .x = r.x, .y = r.y, .w = px, .h = r.h }, line);
    ctx.draw.canvas.fillRect(.{ .x = r.x + r.w - px, .y = r.y, .w = px, .h = r.h }, line);
}

fn blockImpl(u: *ui.Ui, token: theme.ColorToken, p: layout.Params) void {
    block_seq += 1;
    const id = u.id(@src(), ui.Key.int(block_seq));
    const node = u.leaf(id, .{ .layout = p });
    const props = u.treeAlloc().create(BlockProps) catch @panic("golden: block props");
    props.* = .{ .token = token };
    node.paint = paintBlock;
    node.props = props;
}

fn paramsFromItem(item: layout.ItemOptions) layout.Params {
    return .{
        .kind = .leaf,
        .main = item.main orelse .fit,
        .cross = item.cross orelse .fit,
        .main_min = item.main_min orelse 0,
        .main_max = item.main_max orelse std.math.inf(f32),
        .cross_min = item.cross_min orelse 0,
        .cross_max = item.cross_max orelse std.math.inf(f32),
        .self_align = item.self_align,
        .content = .{ .size = .{ .x = 0, .y = 0 } },
    };
}

fn block(u: *ui.Ui, token: theme.ColorToken, item: layout.ItemOptions) void {
    blockImpl(u, token, paramsFromItem(item));
}

fn blockSpan(u: *ui.Ui, token: theme.ColorToken, item: layout.ItemOptions) void {
    var p = paramsFromItem(item);
    p.form_span = true;
    blockImpl(u, token, p);
}

fn layoutRulerScene(_: *anyopaque, u: *ui.Ui) void {
    block_seq = 0;
    _ = u.beginColumn(@src(), .{
        .main = .{ .grow = 1 },
        .cross = .fill,
        .padding = core.Insets.all(10),
        .gap = .xs,
        .clip = true,
    });

    _ = w.label(u, @src(), "Row", .{ .style = .small });
    _ = u.beginRow(@src(), .{ .main = .fixedSize(40), .cross = .fill, .gap = .sm, .clip = true });
    block(u, .accent_fill_bottom, .{ .main = .fixedSize(90), .cross = .fill });
    block(u, .surface_raised_top, .{ .main = .{ .grow = 1 }, .cross = .fill });
    block(u, .surface_row_alt, .{ .main = .fixedSize(420), .cross = .fill });
    u.endRow();

    _ = w.label(u, @src(), "Column", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(40), .cross = .fill, .gap = .xs, .clip = true });
    block(u, .surface_selection_inactive, .{ .main = .fixedSize(16), .cross = .fill });
    block(u, .status_info, .{ .main = .fixedSize(16), .cross = .fill });
    u.endColumn();

    _ = w.label(u, @src(), "Stack", .{ .style = .small });
    _ = u.beginStack(@src(), .{ .main = .fixedSize(40), .cross = .fill, .clip = true });
    block(u, .accent_fill_hover_bottom, .{ .main = .fixedSize(80), .cross = .fixedSize(20) });
    block(u, .status_success, .{ .main = .fixedSize(140), .cross = .fixedSize(32), .self_align = .end });
    u.endStack();

    _ = w.label(u, @src(), "Scroll", .{ .style = .small });
    const sv = w.beginScrollView(u, @src(), .{
        .axes = .vertical,
        .layout = .{ .main = .fixedSize(40), .cross = .fill },
        .line_step = 16,
    });
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fill, .gap = .xs });
    block(u, .surface_raised_bottom, .{ .main = .fixedSize(16), .cross = .fill });
    block(u, .surface_row_hover, .{ .main = .fixedSize(16), .cross = .fill });
    block(u, .surface_row_alt, .{ .main = .fixedSize(16), .cross = .fill });
    block(u, .surface_selection_inactive, .{ .main = .fixedSize(16), .cross = .fill });
    block(u, .status_warning, .{ .main = .fixedSize(16), .cross = .fill });
    u.endColumn();
    _ = w.endScrollView(u, sv);

    _ = w.label(u, @src(), "Splitter", .{ .style = .small });
    const sp = w.beginSplitter(u, @src(), .{
        .orientation = .horizontal,
        .default_pos = .{ .ratio = 0.42 },
        .min_first = 48,
        .min_second = 48,
        .layout = .{ .main = .fixedSize(40), .cross = .fill },
    });
    block(u, .accent_fill_top, .{ .main = .{ .grow = 1 }, .cross = .fill });
    block(u, .surface_raised_top, .{ .main = .{ .grow = 1 }, .cross = .fill });
    _ = w.endSplitter(u, sp);

    _ = w.label(u, @src(), "Table", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(40), .cross = .fill, .clip = true });
    const table_cols = [_]w.TableColumn{
        .{ .title = "A", .width = .{ .grow = 1 } },
        .{ .title = "B", .width = .{ .grow = 1 } },
    };
    var table = w.beginTable(u, @src(), &table_cols, 2, .{ .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (table.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| w.tableCellText(u, @src(), cell, "cell", .{});
    }
    _ = w.endTable(u);
    u.endColumn();

    _ = w.label(u, @src(), "Form", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(40), .cross = .fill, .padding = core.Insets.all(4), .gap = .xs, .clip = true });
    var fr: usize = 0;
    while (fr < 2) : (fr += 1) {
        u.pushId(ui.Key.int(fr));
        _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fill, .gap = .sm });
        _ = w.label(u, @src(), if (fr == 0) "Label A" else "Label B", .{ .style = .small, .layout = .{ .main = .fixedSize(80) } });
        block(u, if (fr == 0) .surface_raised_top else .accent_fill_bottom, .{ .main = .{ .grow = 1 }, .cross = .fill });
        u.endRow();
        u.popId();
    }
    u.endColumn();

    u.endColumn();
}

// ---------------------------------------------------------------------------
// 列表 / 表格 / 树金图（AC-W-LIST-001、AC-W-TABLE-001、AC-W-TREE-001）
// ---------------------------------------------------------------------------

var list_sel_store: ?w.Selection = null;
var table_sel_store: ?w.Selection = null;
var tree_sel_store: ?w.Selection = null;
var tree_expanded_store: ?w.ExpandedSet = null;
var table_sort_store = w.TableSort{ .column = 0, .dir = .asc };

fn listSelection() *w.Selection {
    if (list_sel_store == null) {
        list_sel_store = w.Selection.init(std.heap.page_allocator);
        list_sel_store.?.add(2) catch {};
        list_sel_store.?.add(3) catch {};
    }
    return &list_sel_store.?;
}

fn tableSelection() *w.Selection {
    if (table_sel_store == null) {
        table_sel_store = w.Selection.init(std.heap.page_allocator);
        table_sel_store.?.add(1) catch {};
        table_sel_store.?.add(2) catch {};
    }
    return &table_sel_store.?;
}

fn treeSelection() *w.Selection {
    if (tree_sel_store == null) {
        tree_sel_store = w.Selection.init(std.heap.page_allocator);
        tree_sel_store.?.add(@backingInt(TreeGolden.A2b)) catch {};
        tree_sel_store.?.add(@backingInt(TreeGolden.A3)) catch {};
    }
    return &tree_sel_store.?;
}

fn treeExpanded() *w.ExpandedSet {
    if (tree_expanded_store == null) {
        tree_expanded_store = w.ExpandedSet.init(std.heap.page_allocator);
        tree_expanded_store.?.set(@backingInt(TreeGolden.A), true, null) catch {};
        tree_expanded_store.?.set(@backingInt(TreeGolden.A2), true, null) catch {};
    }
    return &tree_expanded_store.?;
}

const ListGoldenRows = struct {
    const rows = [_][]const u8{ "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima" };
    fn text(_: ?*anyopaque, i: usize) []const u8 {
        return if (i < rows.len) rows[i] else "";
    }
};

fn listGoldenScene(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .sm, .clip = true });
    _ = w.label(u, @src(), "List states", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(176), .cross = .fill });
    var it = w.beginList(u, @src(), 12, .{
        .key = ui.Key.str("golden-list"),
        .mode = .multi,
        .selection = listSelection(),
        .data = .{ .item_text = ListGoldenRows.text },
        .alternate_rows = true,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    var i: usize = 0;
    while (it.next()) |row| : (i += 1) w.listLabel(u, @src(), row, ListGoldenRows.text(null, i), .{});
    _ = w.endList(u, &it);
    u.endColumn();
    _ = w.label(u, @src(), "Disabled", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(88), .cross = .fill });
    var it2 = w.beginList(u, @src(), 4, .{ .key = ui.Key.str("golden-list-disabled"), .enabled = false, .data = .{ .item_text = ListGoldenRows.text } });
    i = 0;
    while (it2.next()) |row| : (i += 1) w.listLabel(u, @src(), row, ListGoldenRows.text(null, i), .{});
    _ = w.endList(u, &it2);
    u.endColumn();
    _ = w.label(u, @src(), "Empty", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(44), .cross = .fill });
    var it3 = w.beginList(u, @src(), 0, .{ .key = ui.Key.str("golden-list-empty"), .empty_text = "No items" });
    _ = w.endList(u, &it3);
    u.endColumn();
    u.endColumn();
}

const TableGoldenCells = struct {
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        if (col == 0) {
            const names = [_][]const u8{ "readme.md", "说明.txt", "src", "build.zig", "docs", "assets", "main.zig", "LICENSE", "tests", "tools", "notes.md", "archive" };
            return if (row < names.len) names[row] else "";
        }
        if (col == 1) return if (row % 3 == 0) "—" else "1,024";
        if (col == 2) return if (row % 2 == 0) "文件" else "文件夹";
        return if (row == 1) "非常长的文件名称示例.txt" else "2026-11-12";
    }
};

const GoldenTableCols = [_]w.TableColumn{
    .{ .title = "名称", .width = .{ .grow = 1 }, .min = 60, .sortable = true },
    .{ .title = "大小", .width = .{ .fixed = 80 }, .min = 32, .h_align = .right, .font = .mono, .sortable = true },
    .{ .title = "类型", .width = .{ .fixed = 100 }, .min = 32, .sortable = true },
    .{ .title = "修改日期", .width = .{ .fixed = 140 }, .min = 32 },
};

fn tableGoldenScene(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .sm, .clip = true });
    _ = w.label(u, @src(), "Table states", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(240), .cross = .fill });
    var it = w.beginTable(u, @src(), &GoldenTableCols, 12, .{
        .key = ui.Key.str("golden-table"),
        .mode = .multi,
        .selection = tableSelection(),
        .data = .{ .cell_text = TableGoldenCells.cell },
        .alternate_rows = true,
        .grid = .both,
        .sort = &table_sort_store,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    while (it.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| w.tableCellText(u, @src(), cell, TableGoldenCells.cell(null, row.index, cell.column), .{});
    }
    _ = w.endTable(u);
    u.endColumn();
    u.endColumn();
}

const TreeGolden = struct {
    const A: w.TreeNode = @fromBackingInt(1);
    const A1: w.TreeNode = @fromBackingInt(2);
    const A2: w.TreeNode = @fromBackingInt(3);
    const A2a: w.TreeNode = @fromBackingInt(4);
    const A2b: w.TreeNode = @fromBackingInt(5);
    const A3: w.TreeNode = @fromBackingInt(6);
    const B: w.TreeNode = @fromBackingInt(7);
    const B1: w.TreeNode = @fromBackingInt(8);
    const C: w.TreeNode = @fromBackingInt(9);
    const top = [_]w.TreeNode{ A, B, C };
    const a_children = [_]w.TreeNode{ A1, A2, A3 };
    const a2_children = [_]w.TreeNode{ A2a, A2b };
    const b_children = [_]w.TreeNode{B1};
    fn children(node: w.TreeNode) []const w.TreeNode {
        if (node == .root) return &top;
        if (node == A) return &a_children;
        if (node == A2) return &a2_children;
        if (node == B) return &b_children;
        return &.{};
    }
    fn childCount(_: ?*anyopaque, node: w.TreeNode) usize {
        return children(node).len;
    }
    fn childAt(_: ?*anyopaque, node: w.TreeNode, i: usize) w.TreeNode {
        return children(node)[i];
    }
    fn hasChildren(_: ?*anyopaque, node: w.TreeNode) bool {
        return children(node).len > 0;
    }
    fn keyOf(_: ?*anyopaque, node: w.TreeNode) w.ItemKey {
        return @backingInt(node);
    }
    fn textOf(_: ?*anyopaque, node: w.TreeNode) []const u8 {
        return switch (node) {
            A => "A",
            A1 => "A1",
            A2 => "A2",
            A2a => "A2a",
            A2b => "A2b",
            A3 => "A3",
            B => "B",
            B1 => "B1",
            C => "C",
            else => "",
        };
    }
    fn model() w.TreeModel {
        return .{ .child_count = childCount, .child_at = childAt, .has_children = hasChildren, .key_of = keyOf, .text_of = textOf };
    }
};

fn treeGoldenScene(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .sm, .clip = true });
    _ = w.label(u, @src(), "Tree states", .{ .style = .small });
    _ = u.beginColumn(@src(), .{ .main = .fixedSize(220), .cross = .fill });
    var it = w.beginTree(u, @src(), TreeGolden.model(), .{
        .key = ui.Key.str("golden-tree"),
        .mode = .multi,
        .selection = treeSelection(),
        .expanded = treeExpanded(),
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    while (it.next()) |row| w.treeLabel(u, @src(), row, TreeGolden.textOf(null, row.node), .{});
    _ = w.endTree(u);
    u.endColumn();
    u.endColumn();
}

const GoldenCase = struct {
    name: []const u8,
    dir: []const u8,
    scene: *const fn (*anyopaque, *ui.Ui) void,
    size: core.Size,
    dpi: u32,
};

const cases = [_]GoldenCase{
    .{ .name = "smoke.png", .dir = "tests/golden/glfw/instrument_light/s100", .scene = scene, .size = .{ .w = 240, .h = 140 }, .dpi = 96 },
    .{ .name = "list.png", .dir = "tests/golden/glfw/instrument_light/s100/widgets/list", .scene = listGoldenScene, .size = .{ .w = 360, .h = 360 }, .dpi = 96 },
    .{ .name = "list.png", .dir = "tests/golden/glfw/instrument_light/s125/widgets/list", .scene = listGoldenScene, .size = .{ .w = 360, .h = 360 }, .dpi = 120 },
    .{ .name = "list.png", .dir = "tests/golden/glfw/instrument_light/s150/widgets/list", .scene = listGoldenScene, .size = .{ .w = 360, .h = 360 }, .dpi = 144 },
    .{ .name = "list.png", .dir = "tests/golden/glfw/instrument_light/s200/widgets/list", .scene = listGoldenScene, .size = .{ .w = 360, .h = 360 }, .dpi = 192 },
    .{ .name = "table.png", .dir = "tests/golden/glfw/instrument_light/s100/widgets/table", .scene = tableGoldenScene, .size = .{ .w = 500, .h = 300 }, .dpi = 96 },
    .{ .name = "table.png", .dir = "tests/golden/glfw/instrument_light/s125/widgets/table", .scene = tableGoldenScene, .size = .{ .w = 500, .h = 300 }, .dpi = 120 },
    .{ .name = "table.png", .dir = "tests/golden/glfw/instrument_light/s150/widgets/table", .scene = tableGoldenScene, .size = .{ .w = 500, .h = 300 }, .dpi = 144 },
    .{ .name = "table.png", .dir = "tests/golden/glfw/instrument_light/s200/widgets/table", .scene = tableGoldenScene, .size = .{ .w = 500, .h = 300 }, .dpi = 192 },
    .{ .name = "tree.png", .dir = "tests/golden/glfw/instrument_light/s100/widgets/tree", .scene = treeGoldenScene, .size = .{ .w = 320, .h = 280 }, .dpi = 96 },
    .{ .name = "tree.png", .dir = "tests/golden/glfw/instrument_light/s125/widgets/tree", .scene = treeGoldenScene, .size = .{ .w = 320, .h = 280 }, .dpi = 120 },
    .{ .name = "tree.png", .dir = "tests/golden/glfw/instrument_light/s150/widgets/tree", .scene = treeGoldenScene, .size = .{ .w = 320, .h = 280 }, .dpi = 144 },
    .{ .name = "tree.png", .dir = "tests/golden/glfw/instrument_light/s200/widgets/tree", .scene = treeGoldenScene, .size = .{ .w = 320, .h = 280 }, .dpi = 192 },
    .{ .name = "layout_ruler.png", .dir = "tests/golden/glfw/instrument_light/s100/layout_ruler", .scene = layoutRulerScene, .size = .{ .w = 640, .h = 480 }, .dpi = 96 },
    .{ .name = "layout_ruler.png", .dir = "tests/golden/glfw/instrument_light/s125/layout_ruler", .scene = layoutRulerScene, .size = .{ .w = 640, .h = 480 }, .dpi = 120 },
    .{ .name = "layout_ruler.png", .dir = "tests/golden/glfw/instrument_light/s150/layout_ruler", .scene = layoutRulerScene, .size = .{ .w = 640, .h = 480 }, .dpi = 144 },
    .{ .name = "layout_ruler.png", .dir = "tests/golden/glfw/instrument_light/s200/layout_ruler", .scene = layoutRulerScene, .size = .{ .w = 640, .h = 480 }, .dpi = 192 },
};

fn runCase(gpa: std.mem.Allocator, io: std.Io, c: GoldenCase, write: bool) !bool {
    var app = try nano.app.App.init(gpa, .{ .size = c.size, .title = "golden" });
    defer app.deinit();
    nano.text.setDirectWrite(false);
    app.io = io;
    if (c.dpi != 96) {
        nano.platform.Headless.setDpi(c.dpi);
        app.window.setClientSize(c.size);
    }
    app.renderOnce(@as(*anyopaque, @ptrCast(&checked)), c.scene);

    try std.Io.Dir.cwd().createDirPath(io, c.dir);
    const case_path = try std.fs.path.join(gpa, &.{ c.dir, c.name });
    defer gpa.free(case_path);
    const actual_path = try std.fmt.allocPrint(gpa, "{s}.actual.png", .{case_path[0 .. case_path.len - 4]});
    defer gpa.free(actual_path);
    const diff_path = try std.fmt.allocPrint(gpa, "{s}.diff.png", .{case_path[0 .. case_path.len - 4]});
    defer gpa.free(diff_path);

    if (write) {
        try app.savePngIo(io, case_path);
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "golden: 已写入基准 {s}\n", .{case_path});
        try std.Io.File.stdout().writeStreamingAll(io, msg);
        return true;
    }

    const baseline = nano.app.readPng(gpa, io, case_path) catch |e| {
        if (e == error.FileNotFound) {
            var buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "golden: 基准不存在 {s}（用 --write 生成并单独提交，REQ-TEST-011）\n", .{case_path});
            try std.Io.File.stderr().writeStreamingAll(io, msg);
            return false;
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
        const red_fill = try gpa.alloc(u8, actual.len);
        defer gpa.free(red_fill);
        var k: usize = 0;
        while (k < red_fill.len) : (k += 4) {
            red_fill[k] = 255;
            red_fill[k + 1] = 0;
            red_fill[k + 2] = 0;
            red_fill[k + 3] = 255;
        }
        const png = try nano.gfx.encodePng(gpa, red_fill, app.surface.width, app.surface.height);
        defer gpa.free(png);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = diff_path, .data = png });
        var buf: [512]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "golden: 尺寸不一致 {s}\n", .{case_path});
        try std.Io.File.stderr().writeStreamingAll(io, msg);
        return false;
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
            diff[o + 2] = 0;
            diff[o + 3] = 255;
        }
    }
    if (diff_count > 0) {
        try app.savePngIo(io, actual_path);
        const png = try nano.gfx.encodePng(gpa, diff, app.surface.width, app.surface.height);
        defer gpa.free(png);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = diff_path, .data = png });
        var buf: [512]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "golden: 失败 {s}，差异像素 {d}，首个索引 {d}\n", .{ case_path, diff_count, first });
        try std.Io.File.stderr().writeStreamingAll(io, msg);
        return false;
    }
    var buf: [512]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "golden: 通过 {s} ({d}x{d})\n", .{ case_path, app.surface.width, app.surface.height });
    try std.Io.File.stdout().writeStreamingAll(io, msg);
    return true;
}

pub fn main(init: std.process.Init) !void {
    nano.platform.forceHeadless();
    const gpa = init.gpa;
    const io = init.io;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    var write = false;
    var only_smoke = false;
    var base_override: ?[]const u8 = null;
    var smoke_dir: []const u8 = "tests/golden/glfw/instrument_light/s100";
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--check")) {
            write = false;
            if (args.next()) |p| {
                smoke_dir = p;
                only_smoke = true;
            }
        } else if (std.mem.eql(u8, a, "--write")) {
            write = true;
            if (args.next()) |p| {
                if (!std.mem.startsWith(u8, p, "--")) {
                    smoke_dir = p;
                    only_smoke = true;
                }
            }
        } else if (std.mem.eql(u8, a, "--base")) {
            if (args.next()) |p| base_override = p;
        }
    }

    var failures: usize = 0;
    for (cases) |c| {
        if (only_smoke and c.scene != scene) continue;
        var cc = c;
        var joined: ?[]u8 = null;
        defer if (joined) |j| gpa.free(j);
        if (only_smoke) cc.dir = smoke_dir;
        if (base_override) |base| {
            const prefix = "tests/golden/glfw/instrument_light/";
            const rel = if (std.mem.startsWith(u8, c.dir, prefix)) c.dir[prefix.len..] else c.dir;
            joined = try std.fs.path.join(gpa, &.{ base, rel });
            cc.dir = joined.?;
        }
        if (!try runCase(gpa, io, cc, write)) failures += 1;
    }
    if (failures > 0) {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "golden: {d} 个用例失败\n", .{failures});
        try std.Io.File.stderr().writeStreamingAll(io, msg);
        std.process.exit(1);
    }
}

test "AC-LAYOUT-028 layout ruler 四档缩放用例" {
    var found: usize = 0;
    const scales = [_]u32{ 96, 120, 144, 192 };
    for (cases) |c| {
        if (c.scene != layoutRulerScene) continue;
        found += 1;
        try std.testing.expectEqual(@as(f32, 640), c.size.w);
        try std.testing.expectEqual(@as(f32, 480), c.size.h);
        var matched = false;
        for (scales) |dpi| if (c.dpi == dpi) {
            matched = true;
        };
        try std.testing.expect(matched);
    }
    try std.testing.expectEqual(@as(usize, 4), found);
}

test "AC-W-LIST-001 list 金图四档缩放用例" {
    var found: usize = 0;
    for (cases) |c| {
        if (c.scene != listGoldenScene) continue;
        found += 1;
        try std.testing.expectEqual(@as(f32, 360), c.size.w);
        try std.testing.expectEqual(@as(f32, 360), c.size.h);
    }
    try std.testing.expectEqual(@as(usize, 4), found);
}

test "AC-W-TABLE-001 table 金图四档缩放用例" {
    var found: usize = 0;
    for (cases) |c| {
        if (c.scene != tableGoldenScene) continue;
        found += 1;
        try std.testing.expectEqual(@as(f32, 500), c.size.w);
        try std.testing.expectEqual(@as(f32, 300), c.size.h);
    }
    try std.testing.expectEqual(@as(usize, 4), found);
}

test "AC-W-TREE-001 tree 金图四档缩放用例" {
    var found: usize = 0;
    for (cases) |c| {
        if (c.scene != treeGoldenScene) continue;
        found += 1;
        try std.testing.expectEqual(@as(f32, 320), c.size.w);
        try std.testing.expectEqual(@as(f32, 280), c.size.h);
    }
    try std.testing.expectEqual(@as(usize, 4), found);
}
