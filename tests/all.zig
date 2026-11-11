const std = @import("std");
const nano = @import("nano_gui");
const core = nano.core;
const platform = nano.platform;
const gfx = nano.gfx;
const text = nano.text;
const theme = nano.theme;
const layout = nano.layout;
const input = nano.input;
const ui = nano.ui;
const widgets = nano.widgets;

test {
    _ = core;
    _ = platform;
    _ = gfx;
    _ = text;
    _ = theme;
    _ = layout;
    _ = input;
    _ = ui;
    _ = widgets;
    _ = nano.commands;
    _ = nano.settings;
    _ = nano.uia;
}

fn emptyBuild(_: ?*anyopaque, _: *ui.Ui) void {}

const BigTree = struct {
    fn childCount(_: ?*anyopaque, node: widgets.TreeNode) usize {
        return if (node == .root) 10000 else 0;
    }
    fn childAt(_: ?*anyopaque, _: widgets.TreeNode, i: usize) widgets.TreeNode {
        return @fromBackingInt(@intCast(i + 1));
    }
    fn hasChildren(_: ?*anyopaque, node: widgets.TreeNode) bool {
        return node == .root;
    }
    fn keyOf(_: ?*anyopaque, node: widgets.TreeNode) widgets.ItemKey {
        return @backingInt(node);
    }
    fn textOf(_: ?*anyopaque, node: widgets.TreeNode) []const u8 {
        _ = node;
        return "row";
    }
};

fn bigTreeBuild(_: ?*anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    var it = widgets.beginTree(u, @src(), .{ .child_count = BigTree.childCount, .child_at = BigTree.childAt, .has_children = BigTree.hasChildren, .key_of = BigTree.keyOf, .text_of = BigTree.textOf }, .{ .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (it.next()) |row| widgets.treeLabel(u, @src(), row, "row", .{});
    _ = widgets.endTree(u);
    u.endColumn();
}

fn bigTableBuild(_: ?*anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    const cols = [_]widgets.TableColumn{ .{ .title = "A", .width = .{ .grow = 1 } }, .{ .title = "B", .width = .{ .grow = 1 } } };
    var it = widgets.beginTable(u, @src(), &cols, 10000, .{ .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (it.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| widgets.tableCellText(u, @src(), cell, "x", .{});
    }
    _ = widgets.endTable(u);
    u.endColumn();
}

const TaModel = struct { handle: widgets.TextAreaHandle = .{ .id = .none } };
fn taBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *TaModel = @ptrCast(@alignCast(ctx));
    const r = widgets.textArea(u, @src(), .{ .debug_name = "ta", .accepts_tab = true });
    m.handle = r.handle;
    u.setFocus(r.handle.id);
}

fn bigListBuild(_: ?*anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    var it = widgets.beginList(u, @src(), 10000, .{ .row_height = 20, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
    while (it.next()) |_| {}
    _ = widgets.endList(u, &it);
    u.endColumn();
}

fn findByName(root: ?*ui.Node, name: []const u8) ?*ui.Node {
    const n = root orelse return null;
    if (n.debug_name) |dn| {
        if (std.mem.eql(u8, dn, name)) return n;
    }
    var c = n.first_child;
    while (c) |cc| : (c = cc.next) {
        if (findByName(cc, name)) |found| return found;
    }
    return null;
}

const TestModel = struct {
    clicks: u32 = 0,
    checked: bool = false,
    name: widgets.TextBuf,
};

fn testBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *TestModel = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(10), .gap = .md });
    if (widgets.button(u, @src(), "计数", .{ .debug_name = "count", .key = ui.Key.str("count") }).clicked) m.clicks += 1;
    if (widgets.checkbox(u, @src(), "选项", &m.checked, .{ .debug_name = "check", .key = ui.Key.str("check") }).changed) {}
    _ = widgets.textInput(u, @src(), &m.name, .{ .debug_name = "name", .key = ui.Key.str("name"), .layout = .{ .main = .{ .grow = 1 } } });
    u.endColumn();
}

fn makeApp() !struct { app: nano.app.App, model: TestModel } {
    var m = TestModel{ .name = try widgets.TextBuf.initFrom(std.testing.allocator, "abc") };
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 400, .h = 300 } });
    app.build_ctx = &m;
    app.build_fn = testBuild;
    app.renderOnce(&m, testBuild);
    return .{ .app = app, .model = m };
}

test "integration: frame ids, click, transient state" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const win = try platform.createWindow(.{});
    var th = theme.Theme.default(.light, .{});
    var u = ui.Ui.init(std.testing.allocator);
    defer u.deinit();
    u.setWindow(win);
    u.setTheme(&th);
    var m = TestModel{ .name = widgets.TextBuf.init(std.testing.allocator) };
    defer m.name.deinit();

    var first_id: ?u64 = null;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        u.beginFrame(@intCast(i * 16), true);
        u.build(@as(*anyopaque, @ptrCast(&m)), testBuild);
        u.layoutTree();
        const n = findByName(u.current_root, "count") orelse return error.TestUnexpectedResult;
        if (first_id) |fid| try std.testing.expectEqual(fid, n.id.raw()) else first_id = n.id.raw();
        u.finishFrame();
    }

    // 鼠标点击内建按钮。
    const node = findByName(u.current_root, "count") orelse return error.TestUnexpectedResult;
    const cx: f32 = @as(f32, @floatFromInt(node.abs.x + @divTrunc(node.abs.w, 2))) / u.scale;
    const cy: f32 = @as(f32, @floatFromInt(node.abs.y + @divTrunc(node.abs.h, 2))) / u.scale;
    platform.Headless.injectMouseMove(.{ .x = @intFromFloat(cx), .y = @intFromFloat(cy) }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = @intFromFloat(cx), .y = @intFromFloat(cy) }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = @intFromFloat(cx), .y = @intFromFloat(cy) }, .{});
    u.beginFrame(100, true);
    const sink = struct {
        fn f(ctx: ?*anyopaque, e: platform.Event) void {
            const uu: *ui.Ui = @ptrCast(@alignCast(ctx.?));
            uu.dispatch(e);
        }
    };
    _ = platform.pumpMessages(.{ .ctx = &u, .func = sink.f });
    u.build(@as(*anyopaque, @ptrCast(&m)), testBuild);
    u.layoutTree();
    u.finishFrame();
    try std.testing.expectEqual(@as(u32, 1), m.clicks);

    // IME：聚焦文本输入，提交一段组字结果。
    const input_node = findByName(u.current_root, "name") orelse return error.TestUnexpectedResult;
    const ix: f32 = @as(f32, @floatFromInt(input_node.abs.x + @divTrunc(input_node.abs.w, 2))) / u.scale;
    const iy: f32 = @as(f32, @floatFromInt(input_node.abs.y + @divTrunc(input_node.abs.h, 2))) / u.scale;
    platform.Headless.injectMouseButton(.left, true, .{ .x = @intFromFloat(ix), .y = @intFromFloat(iy) }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = @intFromFloat(ix), .y = @intFromFloat(iy) }, .{});
    u.beginFrame(120, true);
    _ = platform.pumpMessages(.{ .ctx = &u, .func = sink.f });
    u.build(@as(*anyopaque, @ptrCast(&m)), testBuild);
    u.layoutTree();
    u.finishFrame();
    platform.Headless.injectImeStart();
    platform.Headless.injectImeCommit("你");
    platform.Headless.injectImeEnd();
    u.beginFrame(140, true);
    _ = platform.pumpMessages(.{ .ctx = &u, .func = sink.f });
    u.build(@as(*anyopaque, @ptrCast(&m)), testBuild);
    u.layoutTree();
    u.finishFrame();
    try std.testing.expect(std.mem.indexOf(u8, m.name.slice(), "你") != null);

    // 弹出层根：锚容器出流、可见且在布局后产生屏幕矩形。
    u.beginFrame(160, true);
    u.invalidate(.build);
    u.build(@as(*anyopaque, @ptrCast(&m)), struct {
        fn b(ctx: *anyopaque, uu: *ui.Ui) void {
            _ = ctx;
            _ = uu.beginPopup(core.WidgetId.fromHash(0x504f5055), .{ .kind = .menu, .anchor = .{ .x = 20, .y = 40, .w = 80, .h = 24 }, .placement = .{ .side = .below } });
            _ = widgets.label(uu, @src(), "MenuItem", .{});
            uu.endPopup();
        }
    }.b);
    u.layoutTree();
    try std.testing.expect(u.popup_rect != null);
    u.finishFrame();

    // 虚拟化列表：只创建可见行，节点数与总行数无关。
    u.beginFrame(180, true);
    u.invalidate(.build);
    u.build(@as(?*anyopaque, null), bigListBuild);
    u.layoutTree();
    try std.testing.expect(u.node_count < 120);
    u.finishFrame();

    u.beginFrame(190, true);
    u.invalidate(.build);
    u.build(@as(?*anyopaque, null), bigTreeBuild);
    u.layoutTree();
    try std.testing.expect(u.node_count < 160);
    u.finishFrame();

    u.beginFrame(200, true);
    u.invalidate(.build);
    u.build(@as(?*anyopaque, null), bigTableBuild);
    u.layoutTree();
    try std.testing.expect(u.node_count < 200);
    u.finishFrame();

    // AC-W-TEXTAREA-003：Enter 插入换行、accepts_tab 时 Tab 插入制表符。
    u.beginFrame(210, true);
    u.invalidate(.build);
    var tam = TaModel{};
    u.build(@as(*anyopaque, @ptrCast(&tam)), taBuild);
    u.layoutTree();
    u.finishFrame();
    platform.Headless.injectText("ab");
    platform.Headless.injectKey(.enter, true, false, .{});
    platform.Headless.injectKey(.enter, false, false, .{});
    platform.Headless.injectKey(.tab, true, false, .{});
    platform.Headless.injectKey(.tab, false, false, .{});
    u.beginFrame(230, true);
    _ = platform.pumpMessages(.{ .ctx = &u, .func = sink.f });
    u.build(@as(*anyopaque, @ptrCast(&tam)), taBuild);
    u.layoutTree();
    u.finishFrame();
    const ta_out = try widgets.textAreaText(&u, tam.handle, std.testing.allocator, .{});
    defer std.testing.allocator.free(ta_out);
    try std.testing.expectEqualStrings("ab\n\t", ta_out);

    // transient 槽在未触达的构建后回收。
    const id = core.WidgetId.fromHash(42);
    u.beginFrame(200, true);
    const st = u.state(u32, id, 1);
    st.* = 7;
    u.finishFrame();
    u.beginFrame(216, true);
    u.invalidate(.build);
    u.build(@as(?*anyopaque, null), emptyBuild);
    u.finishFrame();
    u.beginFrame(232, true);
    const st2 = u.state(u32, id, 1);
    try std.testing.expectEqual(@as(u32, 1), st2.*);

    // AC-PLAT-012：无头模式的超时/空闲/wake 合并语义。
    if (std.mem.eql(u8, platform.backend_name, "headless")) {
        const t_before = platform.nowMs();
        try std.testing.expectEqual(platform.WaitResult.timeout, platform.waitMessages(100));
        try std.testing.expectEqual(t_before + 100, platform.nowMs());
        try std.testing.expectEqual(platform.WaitResult.idle, platform.waitMessages(null));
        const W = struct {
            fn run() void {
                platform.wake();
            }
        };
        const wake_thread = try std.Thread.spawn(.{}, W.run, .{});
        wake_thread.join();
        try std.testing.expectEqual(platform.WaitResult.woken, platform.waitMessages(null));
        var k: usize = 0;
        while (k < 1000) : (k += 1) platform.wake();
        try std.testing.expectEqual(platform.WaitResult.woken, platform.waitMessages(null));
        try std.testing.expectEqual(platform.WaitResult.idle, platform.waitMessages(null));
    }

    // AC-ARCH-005：App.post 必须按入队顺序执行。
    var posted = nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 200, .h = 120 } }) catch return error.TestUnexpectedResult;
    defer posted.deinit();
    const Order = struct {
        var seen: [4]u32 = @splat(0);
        var n: usize = 0;
        fn push(ctx: ?*anyopaque) void {
            const v: *u32 = @ptrCast(@alignCast(ctx.?));
            seen[n] = v.*;
            n += 1;
        }
    };
    var vals = [3]u32{ 1, 2, 3 };
    for (&vals) |*v| _ = posted.post(.{ .ctx = v, .func = Order.push });
    _ = posted.pump();
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, Order.seen[0..3]);
}

const PinnedState = struct {
    value: u32 = 7,
    pub fn init(_: std.mem.Allocator) PinnedState {
        return .{};
    }
    pub fn deinit(_: *PinnedState) void {}
};

test "AC-FRAME-005 sticky LRU and pinned retention" {
    var u = ui.Ui.init(std.testing.allocator);
    defer u.deinit();
    const pinned_id = core.WidgetId.fromHash(0x7777);
    _ = u.retained(PinnedState, pinned_id, .pinned);
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        _ = u.stateSticky(u32, core.WidgetId.fromHash(10000 + i), 0);
    }
    u.beginFrame(0, true);
    u.invalidate(.build);
    u.build(@as(?*anyopaque, null), emptyBuild);
    u.finishFrame();
    try std.testing.expect(u.stateSlotCount() <= 4097);
    try std.testing.expect(u.getState(PinnedState, pinned_id) != null);
    try std.testing.expect(u.getState(u32, core.WidgetId.fromHash(10000)) == null);
    try std.testing.expect(u.getState(u32, core.WidgetId.fromHash(10904)) != null);
}

test "AC-LAYOUT-001/002 distribute edge cases" {
    var items = [2]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = 40, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = 40, .wq = 1024 },
    };
    var out: [2]i32 = undefined;
    const r = layout.distribute(&items, 300, &out);
    try std.testing.expectEqualSlices(i32, &.{ 40, 40 }, &out);
    try std.testing.expectEqual(@as(i32, 220), r.leftover);

    var three = [3]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 150, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = 60, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
    };
    var o3: [3]i32 = undefined;
    _ = layout.distribute(&three, 300, &o3);
    try std.testing.expectEqualSlices(i32, &.{ 150, 60, 90 }, &o3);

    var two = [2]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 2048 },
    };
    var o2: [2]i32 = undefined;
    _ = layout.distribute(&two, 100, &o2);
    try std.testing.expectEqualSlices(i32, &.{ 33, 67 }, &o2);
}

test "AC-FRAME-005 state types are distinct" {
    var u = ui.Ui.init(std.testing.allocator);
    defer u.deinit();
    const id = core.WidgetId.fromHash(7);
    u.beginFrame(0, true);
    const a = u.state(u32, id, 0);
    const b = u.state(f32, id, 0);
    a.* = 9;
    b.* = 1.5;
    try std.testing.expectEqual(@as(u32, 9), a.*);
    try std.testing.expectEqual(@as(f32, 1.5), b.*);
}

test "AC-THEME-005 default themes validate" {
    var report: theme.Theme.ValidationReport = .{};
    try std.testing.expect(theme.Theme.default(.light, .{}).validate(&report));
    try std.testing.expect(theme.Theme.default(.dark, .{}).validate(&report));
}

test "AC-W-TEXTAREA-006 document handle API" {
    var u = ui.Ui.init(std.testing.allocator);
    defer u.deinit();
    const h = widgets.TextAreaHandle{ .id = core.WidgetId.fromHash(99) };
    const info = try widgets.textAreaLoad(&u, h, "hello\nworld");
    try std.testing.expectEqual(@as(u32, 2), info.lines);
    try widgets.textAreaReplace(&u, h, 0, 5, "HELLO");
    const out = try widgets.textAreaText(&u, h, std.testing.allocator, .{});
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("HELLO\nworld", out);
}

test "DirectWrite layout metrics on Windows" {
    if (comptime @import("builtin").os.tag != .windows) return;
    const m = try nano.text.directwrite.measure(std.testing.allocator, "Hello 你好", 16, 400, "Segoe UI");
    try std.testing.expect(m.width > 0);
    try std.testing.expect(m.height > 0);
    try std.testing.expect(m.lines >= 1);
}

test "DirectWrite glyph draw on Windows" {
    if (comptime @import("builtin").os.tag != .windows) return;
    text.setDirectWrite(true);
    defer text.setDirectWrite(false);
    const w = 240;
    const h = 48;
    const pixels = try std.testing.allocator.alloc(u8, w * h * 4);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, 0);
    var canvas = gfx.Canvas.init(std.testing.allocator, pixels, w, h, 1.0);
    defer canvas.deinit();
    const owned = try text.layoutOwned(std.testing.allocator, "DirectWrite", .{ .size = 16 }, 1.0, .{});
    defer owned.layout.deinit();
    nano.text.directwrite.draw(std.testing.allocator, &canvas, "DirectWrite", 16, 400, "Segoe UI", .{ .x = 2, .y = 2 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }) catch |e| {
        std.debug.print("directwrite.draw error: {t}\n", .{e});
        return e;
    };
    var nonzero: usize = 0;
    for (pixels) |v| if (v != 0) {
        nonzero += 1;
    };
    try std.testing.expect(nonzero > 0);
}

test "AC-TEST-001 fixed backend deterministic" {
    const style = text.Style{ .size = 16 };
    const a = text.measure("Hello 你好", style, 1, .{});
    const b = text.measure("Hello 你好", style, 1, .{});
    try std.testing.expectEqual(a.w, b.w);
    try std.testing.expectEqual(@as(f32, 64), a.w);
    try std.testing.expectEqual(@as(f32, 20), a.h);
    try std.testing.expectEqualStrings("fixed", text.backend_name);
}

test "AC-CONV-012 widget APIs do not return errors" {
    const B = widgets.button;
    const info = @typeInfo(@TypeOf(B)).@"fn";
    try std.testing.expect(info.return_type.? == widgets.ButtonResult);
}
