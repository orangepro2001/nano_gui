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

test "REQ-FRAME-010 sticky LRU and pinned retention" {
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

test "REQ-LAYOUT-016 distribute edge cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var items = [2]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = 40, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = 40, .wq = 1024 },
    };
    var out: [2]i32 = undefined;
    const r = layout.distribute(arena.allocator(), &items, 300, &out);
    try std.testing.expectEqualSlices(i32, &.{ 40, 40 }, &out);
    try std.testing.expectEqual(@as(i32, 220), r.leftover);

    var three = [3]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 150, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = 60, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
    };
    var o3: [3]i32 = undefined;
    _ = layout.distribute(arena.allocator(), &three, 300, &o3);
    try std.testing.expectEqualSlices(i32, &.{ 150, 60, 90 }, &o3);

    var two = [2]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 2048 },
    };
    var o2: [2]i32 = undefined;
    _ = layout.distribute(arena.allocator(), &two, 100, &o2);
    try std.testing.expectEqualSlices(i32, &.{ 33, 67 }, &o2);
}

test "REQ-FRAME-009 state types are distinct" {
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

// 来源：docs/09-theme.md 3.2 节颜色令牌表（行号见各行注释）；值为 0xRRGGBBAA。
const theme_color_table = [_]struct { t: theme.ColorToken, light: u32, dark: u32 }{
    .{ .t = .surface_window, .light = 0xECEEF1FF, .dark = 0x1F2125FF }, // 09:57
    .{ .t = .surface_panel, .light = 0xF4F5F7FF, .dark = 0x26292EFF }, // 09:58
    .{ .t = .surface_raised_top, .light = 0xFCFCFDFF, .dark = 0x3B3F46FF }, // 09:59
    .{ .t = .surface_raised_bottom, .light = 0xEDEFF2FF, .dark = 0x33373DFF }, // 09:60
    .{ .t = .surface_raised_hover_top, .light = 0xFFFFFFFF, .dark = 0x454A52FF }, // 09:61
    .{ .t = .surface_raised_hover_bottom, .light = 0xF3F5F8FF, .dark = 0x3C4047FF }, // 09:62
    .{ .t = .surface_raised_pressed_top, .light = 0xDCDFE4FF, .dark = 0x2A2D32FF }, // 09:63
    .{ .t = .surface_raised_pressed_bottom, .light = 0xE4E7EBFF, .dark = 0x2F3338FF }, // 09:64
    .{ .t = .surface_raised_disabled, .light = 0xF0F1F3FF, .dark = 0x222428FF }, // 09:65
    .{ .t = .surface_sunken, .light = 0xFFFFFFFF, .dark = 0x16181BFF }, // 09:66
    .{ .t = .surface_sunken_disabled, .light = 0xF0F1F3FF, .dark = 0x222428FF }, // 09:67
    .{ .t = .surface_track, .light = 0xD9DDE2FF, .dark = 0x17191CFF }, // 09:68
    .{ .t = .surface_popup, .light = 0xF9FAFBFF, .dark = 0x2B2E33FF }, // 09:69
    .{ .t = .surface_tooltip, .light = 0xFFFFFFFF, .dark = 0x34383EFF }, // 09:70
    .{ .t = .surface_row_alt, .light = 0xF7F8FAFF, .dark = 0x232529FF }, // 09:71
    .{ .t = .surface_row_hover, .light = 0xE6EAF0FF, .dark = 0x30343AFF }, // 09:72
    .{ .t = .surface_selection_inactive, .light = 0xD5D9DFFF, .dark = 0x3D4148FF }, // 09:73
    .{ .t = .border_control, .light = 0x7B838EFF, .dark = 0x747C87FF }, // 09:79
    .{ .t = .border_control_hover, .light = 0x5F6772FF, .dark = 0x8F97A2FF }, // 09:80
    .{ .t = .border_control_disabled, .light = 0xC3C8CFFF, .dark = 0x40444AFF }, // 09:81
    .{ .t = .border_strong, .light = 0x9AA1ABFF, .dark = 0x565C65FF }, // 09:82
    .{ .t = .border_subtle, .light = 0xD0D4DAFF, .dark = 0x383C42FF }, // 09:83
    .{ .t = .bevel_highlight, .light = 0xFFFFFFCC, .dark = 0xFFFFFF1A }, // 09:84
    .{ .t = .bevel_shade, .light = 0x0000001F, .dark = 0x00000059 }, // 09:85
    .{ .t = .inset_shadow, .light = 0x00000024, .dark = 0x00000066 }, // 09:86
    .{ .t = .text_primary, .light = 0x1B1F24FF, .dark = 0xE7E9ECFF }, // 09:92
    .{ .t = .text_secondary, .light = 0x555D68FF, .dark = 0xA7AEB8FF }, // 09:93
    .{ .t = .text_placeholder, .light = 0x6A727DFF, .dark = 0x8C939DFF }, // 09:94
    .{ .t = .text_disabled, .light = 0x9299A3FF, .dark = 0x646B75FF }, // 09:95
    .{ .t = .text_on_accent, .light = 0xFFFFFFFF, .dark = 0xFFFFFFFF }, // 09:96
    .{ .t = .accent_fill_top, .light = 0x2F6EDFFF, .dark = 0x2F6FDEFF }, // 09:102
    .{ .t = .accent_fill_bottom, .light = 0x1F59C6FF, .dark = 0x2561CEFF }, // 09:103
    .{ .t = .accent_fill_hover_top, .light = 0x3271E2FF, .dark = 0x3272E1FF }, // 09:104
    .{ .t = .accent_fill_hover_bottom, .light = 0x2A63CFFF, .dark = 0x2F6AD6FF }, // 09:105
    .{ .t = .accent_fill_pressed_top, .light = 0x1B50B4FF, .dark = 0x1F55B8FF }, // 09:106
    .{ .t = .accent_fill_pressed_bottom, .light = 0x2259C2FF, .dark = 0x255DC2FF }, // 09:107
    .{ .t = .accent_border, .light = 0x1A4CABFF, .dark = 0x1B4FB0FF }, // 09:108
    .{ .t = .accent_mark, .light = 0x2463D6FF, .dark = 0x4C8DF6FF }, // 09:109
    .{ .t = .accent_text, .light = 0x1F5BCBFF, .dark = 0x7FB0FFFF }, // 09:110
    .{ .t = .accent_halo, .light = 0x2463D666, .dark = 0x4C8DF666 }, // 09:111
    .{ .t = .status_danger, .light = 0xC4281CFF, .dark = 0xFF8A80FF }, // 09:117
    .{ .t = .status_warning, .light = 0x8A5A00FF, .dark = 0xF2B84BFF }, // 09:118
    .{ .t = .status_success, .light = 0x1E7B34FF, .dark = 0x6CCB7FFF }, // 09:119
    .{ .t = .status_info, .light = 0x1F5BCBFF, .dark = 0x7FB0FFFF }, // 09:120
};

// 来源：docs/09-theme.md 3.3 节度量令牌表（09:164-195）。
const theme_metric_table = [_]struct { m: theme.Metric, v: f32 }{
    .{ .m = .control_h_sm, .v = 20 }, .{ .m = .control_h, .v = 24 }, .{ .m = .control_h_lg, .v = 28 }, // 09:164
    .{ .m = .row_h, .v = 22 }, .{ .m = .header_h, .v = 24 }, // 09:165-166
    .{ .m = .radius_control, .v = 3 }, .{ .m = .radius_container, .v = 4 }, .{ .m = .radius_mark, .v = 2 }, // 09:167-169
    .{ .m = .gap_xs, .v = 2 }, .{ .m = .gap_sm, .v = 4 }, .{ .m = .gap_md, .v = 8 }, // 09:170
    .{ .m = .gap_lg, .v = 12 }, .{ .m = .gap_xl, .v = 16 }, .{ .m = .gap_2xl, .v = 24 }, // 09:170
    .{ .m = .pad_control_x, .v = 10 }, .{ .m = .pad_input_x, .v = 6 }, .{ .m = .pad_panel, .v = 8 }, // 09:171-173
    .{ .m = .pad_dialog, .v = 12 }, .{ .m = .pad_popup_y, .v = 4 }, .{ .m = .pad_item_x, .v = 8 }, // 09:174-176
    .{ .m = .icon_sm, .v = 16 }, .{ .m = .icon_md, .v = 20 }, .{ .m = .icon_lg, .v = 32 }, // 09:177
    .{ .m = .check_size, .v = 14 }, .{ .m = .switch_w, .v = 28 }, .{ .m = .switch_h, .v = 14 }, // 09:178-179
    .{ .m = .slider_track_h, .v = 4 }, .{ .m = .slider_thumb_w, .v = 10 }, .{ .m = .slider_thumb_h, .v = 16 }, // 09:180-181
    .{ .m = .slider_min_len, .v = 96 }, .{ .m = .tab_indicator_h, .v = 2 }, .{ .m = .progress_h, .v = 6 }, // 09:182-184
    .{ .m = .scrollbar_w, .v = 12 }, .{ .m = .scrollbar_thumb_min, .v = 24 }, .{ .m = .splitter_w, .v = 5 }, // 09:185-187
    .{ .m = .focus_ring_w, .v = 2 }, .{ .m = .indent, .v = 16 }, .{ .m = .button_min_w, .v = 72 }, // 09:188-190
    .{ .m = .tooltip_max_w, .v = 320 }, .{ .m = .tooltip_offset_y, .v = 20 }, // 09:191-192
    .{ .m = .pad_tooltip_x, .v = 6 }, .{ .m = .pad_tooltip_y, .v = 3 }, // 09:193
    .{ .m = .menu_max_w, .v = 360 }, .{ .m = .dialog_text_max_w, .v = 420 }, // 09:194-195
};

fn packColor(c: core.Color) u32 {
    return (@as(u32, c.r) << 24) | (@as(u32, c.g) << 16) | (@as(u32, c.b) << 8) | c.a;
}

fn hslTestColor(h_deg: f32, s: f32, l: f32) core.Color {
    const c = (1 - @abs(2 * l - 1)) * s;
    const hp = h_deg / 60.0;
    const x = c * (1 - @abs(@mod(hp, 2) - 1));
    const m = l - c / 2;
    const sector: u32 = @intFromFloat(@floor(hp));
    const rgb: [3]f32 = switch (sector % 6) {
        0 => .{ c, x, 0 },
        1 => .{ x, c, 0 },
        2 => .{ 0, c, x },
        3 => .{ 0, x, c },
        4 => .{ x, 0, c },
        else => .{ c, 0, x },
    };
    return .{
        .r = @intFromFloat(@round((rgb[0] + m) * 255)),
        .g = @intFromFloat(@round((rgb[1] + m) * 255)),
        .b = @intFromFloat(@round((rgb[2] + m) * 255)),
        .a = 255,
    };
}

fn hueOf(c: core.Color) f32 {
    const r = @as(f32, @floatFromInt(c.r)) / 255;
    const g = @as(f32, @floatFromInt(c.g)) / 255;
    const b = @as(f32, @floatFromInt(c.b)) / 255;
    const mx = @max(r, @max(g, b));
    const mn = @min(r, @min(g, b));
    const d = mx - mn;
    if (d == 0) return 0;
    var h: f32 = if (mx == r) @mod((g - b) / d, 6) else if (mx == g) (b - r) / d + 2 else (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
    return h;
}

fn hueDiff(a: f32, b: f32) f32 {
    const d = @abs(a - b);
    return @min(d, 360 - d);
}

fn expectAccentFamilyIsTable(t: theme.Theme, dark: bool) !void {
    for (theme_color_table) |row| {
        if (!std.mem.startsWith(u8, @tagName(row.t), "accent_")) continue;
        try std.testing.expectEqual(if (dark) row.dark else row.light, packColor(t.color(row.t)));
    }
}

test "AC-THEME-005 default themes validate" {
    var report: theme.Theme.ValidationReport = .{};
    const light = theme.Theme.default(.light, .{});
    try std.testing.expect(light.validate(&report));
    try std.testing.expectEqual(@as(u32, 0), report.failures);
    const dark = theme.Theme.default(.dark, .{});
    try std.testing.expect(dark.validate(&report));
    try std.testing.expectEqual(@as(u32, 0), report.failures);
}

test "AC-THEME-005 every ColorToken matches the 09 table" {
    // 表覆盖 ColorToken 的每个成员（无遗漏、无多余）。
    try std.testing.expectEqual(std.enums.values(theme.ColorToken).len, theme_color_table.len);
    const light = theme.Theme.default(.light, .{});
    const dark = theme.Theme.default(.dark, .{});
    for (theme_color_table) |row| {
        try std.testing.expectEqual(row.light, packColor(light.color(row.t)));
        try std.testing.expectEqual(row.dark, packColor(dark.color(row.t)));
    }
}

test "AC-THEME-005 text_primary equal to surface_window fails validate" {
    var t = theme.Theme.default(.light, .{});
    t.colors.set(.text_primary, t.color(.surface_window));
    var report: theme.Theme.ValidationReport = .{};
    try std.testing.expect(!t.validate(&report));
    try std.testing.expect(report.failures >= 1);
    const p = report.first_pair.?;
    try std.testing.expectEqual(theme.ColorToken.text_primary, p.fg);
    try std.testing.expectEqual(theme.ColorToken.surface_window, p.bg);
}

test "AC-THEME-006 deriveAccent over hues, grays, black and white" {
    var inputs: [24 + 3 + 2]core.Color = undefined;
    var hues: [29]?f32 = @splat(null);
    for (0..24) |i| {
        const h = @as(f32, @floatFromInt(i)) * 15.0;
        inputs[i] = hslTestColor(h, 0.9, 0.5);
        hues[i] = hueOf(inputs[i]);
    }
    inputs[24] = core.Color{ .r = 0x40, .g = 0x40, .b = 0x40, .a = 255 };
    inputs[25] = core.Color{ .r = 0x80, .g = 0x80, .b = 0x80, .a = 255 };
    inputs[26] = core.Color{ .r = 0xC0, .g = 0xC0, .b = 0xC0, .a = 255 };
    inputs[27] = core.Color.black;
    inputs[28] = core.Color.white;
    for ([_]bool{ false, true }) |dark| {
        for (inputs, 0..) |in, i| {
            var t = theme.Theme.default(if (dark) .dark else .light, .{});
            t.deriveAccent(in);
            var report: theme.Theme.ValidationReport = .{};
            const ok = t.validate(&report);
            if (!ok) std.debug.print("hue input {d} dark={} fails {any}\n", .{ i, dark, report.first_pair });
            try std.testing.expect(ok);
            if (hues[i]) |h_in| {
                try std.testing.expect(hueDiff(h_in, hueOf(t.color(.accent_fill_bottom))) <= 2.0);
            } else {
                try expectAccentFamilyIsTable(t, dark);
            }
        }
        // 灰/黑/白与默认强调色 #2F6EDF 输入：取表值（默认强调色族）。
        for (inputs[24..]) |in| {
            var t = theme.Theme.default(if (dark) .dark else .light, .{});
            t.deriveAccent(in);
            try expectAccentFamilyIsTable(t, dark);
        }
        var t = theme.Theme.default(if (dark) .dark else .light, .{});
        t.deriveAccent(core.Color.fromHex(0x2F6EDF, 255));
        try expectAccentFamilyIsTable(t, dark);
    }
}

test "AC-THEME-008 metric defaults match the 09 table" {
    try std.testing.expectEqual(std.enums.values(theme.Metric).len, theme_metric_table.len);
    const t = theme.Theme.default(.light, .{});
    const scales = [_]f32{ 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0 };
    for (theme_metric_table) |row| {
        try std.testing.expectEqual(row.v, t.metric(row.m));
        for (scales) |sc| {
            const want: i32 = @max(1, @as(i32, @intFromFloat(@round(row.v * sc))));
            try std.testing.expectEqual(want, t.px(row.m, sc));
            try std.testing.expectEqual(want, t.px(row.m, sc));
        }
    }
}

test "REQ-THEME-009 fixed accent overrides default-accent table rule" {
    const def = core.Color.fromHex(0x2F6EDF, 255);
    for ([_]bool{ false, true }) |dark| {
        const mode: theme.Mode = if (dark) .dark else .light;
        // 应用固定色 = 默认强调色：执行派生，须通过 validate。
        const t1 = theme.Theme.defaultWithAccent(mode, .{}, def);
        var report: theme.Theme.ValidationReport = .{};
        try std.testing.expect(t1.validate(&report));
        // 应用固定色为灰：取表值。
        const t2 = theme.Theme.defaultWithAccent(mode, .{}, core.Color{ .r = 0x80, .g = 0x80, .b = 0x80, .a = 255 });
        try expectAccentFamilyIsTable(t2, dark);
        // 未指定且系统色为默认强调色：取表值。
        try expectAccentFamilyIsTable(theme.Theme.defaultWithAccent(mode, .{}, null), dark);
    }
    // 派生（浅色）的 accent_fill_bottom 与表值不同，证明确实走了派生。
    const l1 = theme.Theme.defaultWithAccent(.light, .{}, def);
    try std.testing.expect(packColor(l1.color(.accent_fill_bottom)) != 0x1F59C6FF);
}

test "REQ-THEME-019 duration token values match the 09 table" {
    // 来源：docs/09-theme.md 09:229-234。
    const t = theme.Theme.default(.light, .{});
    try std.testing.expectEqual(@as(u16, 0), t.durationMs(.instant));
    try std.testing.expectEqual(@as(u16, 80), t.durationMs(.fast));
    try std.testing.expectEqual(@as(u16, 120), t.durationMs(.normal));
    try std.testing.expectEqual(@as(u16, 200), t.durationMs(.slow));
    try std.testing.expectEqual(@as(u16, 1600), t.durationMs(.indeterminate));
    try std.testing.expectEqual(@as(u16, 50), t.durationMs(.autoscroll));
}

test "REQ-W-TEXTAREA-029/030 document handle load, replace, read" {
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
    text.draw(&canvas, owned.layout, .{ .x = 2, .y = 2 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .{});
    var nonzero: usize = 0;
    for (pixels) |v| if (v != 0) {
        nonzero += 1;
    };
    try std.testing.expect(nonzero > 0);
}

test "REQ-TEST-006 fixed backend deterministic" {
    const style = text.Style{ .size = 16 };
    const a = text.measure("Hello 你好", style, 1, .{});
    const b = text.measure("Hello 你好", style, 1, .{});
    try std.testing.expectEqual(a.w, b.w);
    try std.testing.expectEqual(@as(f32, 64), a.w);
    try std.testing.expectEqual(@as(f32, 20), a.h);
    try std.testing.expectEqualStrings("fixed", text.backend_name);
}

test "REQ-CONV-012 button API does not return errors" {
    const B = widgets.button;
    const info = @typeInfo(@TypeOf(B)).@"fn";
    try std.testing.expect(info.return_type.? == widgets.ButtonResult);
}

var fake_clock_ns: u64 = 0;
fn fakeClockNs() u64 {
    return fake_clock_ns;
}

test "REQ-ARCH-021 timer samples via injected clock" {
    core.stats.initRegistry();
    // 未注入时钟：不产生样本。
    core.stats.setClock(null);
    core.stats.timerBegin("time.layout");
    core.stats.timerEnd("time.layout");
    var out: [8]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 0), core.stats.drainSamples("time.layout", &out));

    core.stats.setClock(fakeClockNs);
    defer core.stats.setClock(null);
    fake_clock_ns = 1000;
    core.stats.timerBegin("time.layout");
    fake_clock_ns = 1750;
    core.stats.timerEnd("time.layout");
    fake_clock_ns = 2000;
    core.stats.timerBegin("time.layout");
    fake_clock_ns = 2100;
    core.stats.timerEnd("time.layout");
    try std.testing.expectEqual(@as(usize, 2), core.stats.drainSamples("time.layout", &out));
    try std.testing.expectEqual(@as(u64, 750), out[0]);
    try std.testing.expectEqual(@as(u64, 100), out[1]);
    // 取出后清空。
    try std.testing.expectEqual(@as(usize, 0), core.stats.drainSamples("time.layout", &out));
    // 缓冲满了丢最旧的。
    var i: u64 = 0;
    while (i < core.stats.max_samples + 3) : (i += 1) {
        fake_clock_ns = 0;
        core.stats.timerBegin("time.paint");
        fake_clock_ns = i;
        core.stats.timerEnd("time.paint");
    }
    var small: [2]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 2), core.stats.drainSamples("time.paint", &small));
    try std.testing.expectEqual(@as(u64, 3), small[0]);
    try std.testing.expectEqual(@as(u64, 4), small[1]);
}

test "REQ-TEXT-018 hit test 命中簇前后半与行外" {
    try text.init(std.testing.allocator, .{});
    defer text.deinit();
    const style: text.Style = .{ .size = 12 };
    const l = text.layout("abcd", style, 1.0, .{});
    const a = text.measure("a", style, 1.0, .{}).w;
    // 第 3 个字符后半部：取末尾边界，偏移 3，trailing。
    const r3 = l.hitTest(.{ .x = 2.75 * a, .y = 1 });
    try std.testing.expectEqual(@as(u32, 3), r3.caret.offset);
    try std.testing.expectEqual(text.Edge.trailing, r3.edge);
    try std.testing.expect(r3.inside);
    // 第 3 个字符前半部：起始边界，偏移 2，leading。
    const r2 = l.hitTest(.{ .x = 2.25 * a, .y = 1 });
    try std.testing.expectEqual(@as(u32, 2), r2.caret.offset);
    try std.testing.expectEqual(text.Edge.leading, r2.edge);
    // 恰在中点取 trailing。
    const mid = l.hitTest(.{ .x = 1.5 * a, .y = 1 });
    try std.testing.expectEqual(@as(u32, 2), mid.caret.offset);
    try std.testing.expectEqual(text.Edge.trailing, mid.edge);
    // 行左侧之外 -> 0，右侧之外 -> 末尾，inside 为假。
    const left = l.hitTest(.{ .x = -3, .y = 1 });
    try std.testing.expectEqual(@as(u32, 0), left.caret.offset);
    try std.testing.expect(!left.inside);
    const right = l.hitTest(.{ .x = 1000, .y = 1 });
    try std.testing.expectEqual(@as(u32, 4), right.caret.offset);
    try std.testing.expect(!right.inside);
}

test "REQ-TEXT-013/014 排版缓存键命中与指针有效期" {
    try text.init(std.testing.allocator, .{ .layout_cache_entries = 4 });
    defer text.deinit();
    const style: text.Style = .{ .size = 12 };
    var buf: [16]u8 = undefined;
    // 构建 1：同键命中、不同缩放为不同键、同代内超限也不淘汰。
    text.beginBuild();
    const first = text.layout("cache-key", style, 1.0, .{});
    try std.testing.expectEqual(first, text.layout("cache-key", style, 1.0, .{}));
    try std.testing.expect(first != text.layout("cache-key", style, 1.25, .{}));
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const s = std.fmt.bufPrint(&buf, "item-{d}", .{i}) catch unreachable;
        _ = text.layout(s, style, 1.0, .{});
    }
    try std.testing.expect(text.cacheStats().entries > 4);
    try std.testing.expectEqual(first, text.layout("cache-key", style, 1.0, .{}));
    text.trimCache(); // 构建 1 完成：全部受保护，允许超限
    try std.testing.expect(text.cacheStats().entries > 4);
    // 构建 2 取得的指针在构建 3、4 期间仍有效。
    text.beginBuild();
    const second = text.layout("second", style, 1.0, .{});
    text.trimCache();
    text.beginBuild();
    text.trimCache();
    text.beginBuild();
    try std.testing.expectEqualStrings("second", second.text);
    try std.testing.expectEqual(second, text.layout("second", style, 1.0, .{}));
    text.trimCache();
    // 之后收敛到上限，且计量与占用一致。
    text.beginBuild();
    text.trimCache();
    text.beginBuild();
    text.trimCache();
    try std.testing.expect(text.cacheStats().entries <= 4);
    try std.testing.expectEqual(@as(u64, text.cacheStats().entries), core.stats.gauge("cache.text_layout.entries").*);
}

test "REQ-TEXT-013 哈希碰撞时按原文比对" {
    try text.init(std.testing.allocator, .{});
    defer text.deinit();
    text.test_hash_override = 42;
    defer text.test_hash_override = null;
    text.beginBuild();
    const style: text.Style = .{ .size = 12 };
    const a = text.layout("alpha", style, 1.0, .{});
    const b = text.layout("bravo", style, 1.0, .{});
    try std.testing.expect(a != b);
    try std.testing.expectEqualStrings("alpha", a.text);
    try std.testing.expectEqualStrings("bravo", b.text);
    try std.testing.expectEqual(a, text.layout("alpha", style, 1.0, .{}));
    try std.testing.expectEqual(b, text.layout("bravo", style, 1.0, .{}));
}

test "REQ-GFX-011 渐变顶行取起点色、底行取终点色" {
    var buf: [4 * 4]u8 = @splat(0);
    var c = gfx.Canvas.init(std.testing.allocator, &buf, 1, 4, 1);
    defer c.deinit();
    c.fillRectV(.{ .x = 0, .y = 0, .w = 1, .h = 4 }, .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 255, .g = 255, .b = 255 });
    try std.testing.expectEqual(@as(u8, 0), buf[0]);
    try std.testing.expectEqual(@as(u8, 255), buf[12]);
    try std.testing.expect(buf[4] > buf[0] and buf[8] > buf[4] and buf[12] > buf[8]);
}

test "REQ-GFX-026 着色相乘不溢出" {
    const pix = try std.heap.smp_allocator.alloc(u8, 4);
    pix[0] = 200;
    pix[1] = 100;
    pix[2] = 255;
    pix[3] = 255;
    const key = gfx.ImageKey.fromPath("tint-test");
    _ = try gfx.images.insert(key, .{ .width = 1, .height = 1, .rgba = pix, .allocator = std.heap.smp_allocator }, .{});
    defer gfx.images.clear();
    const id = gfx.images.id(key).?;
    var buf: [4]u8 = @splat(0);
    var c = gfx.Canvas.init(std.testing.allocator, &buf, 1, 1, 1);
    defer c.deinit();
    const dst: core.Rect = .{ .x = 0, .y = 0, .w = 1, .h = 1 };
    try std.testing.expect(c.drawImage(id, dst, .{ .tint = .{ .r = 255, .g = 255, .b = 255, .a = 255 } }));
    try std.testing.expectEqual(@as(u8, 200), buf[0]);
    try std.testing.expectEqual(@as(u8, 100), buf[1]);
    buf = @splat(0);
    try std.testing.expect(c.drawImage(id, dst, .{ .tint = .{ .r = 128, .g = 128, .b = 128, .a = 255 } }));
    try std.testing.expect(buf[0] >= 99 and buf[0] <= 101);
    try std.testing.expect(buf[1] >= 49 and buf[1] <= 51);
}

test "REQ-GFX-030 png bounds 截断与超限 PNG 返回错误" {
    const gpa = std.testing.allocator;
    var rgba = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    const png = try gfx.encodePng(gpa, &rgba, 2, 2);
    defer gpa.free(png);
    var n: usize = 8;
    while (n < png.len) : (n += 1) {
        try std.testing.expectError(error.DecodeFailed, gfx.decode(gpa, png[0..n]));
    }
    // 头部声明 20000x20000：先查尺寸，返回 TooLarge。
    var big: [8 + 12 + 13]u8 = @splat(0);
    @memcpy(big[0..8], "\x89PNG\r\n\x1a\n");
    std.mem.writeInt(u32, big[8..12], 13, .big);
    @memcpy(big[12..16], "IHDR");
    std.mem.writeInt(u32, big[16..20], 20000, .big);
    std.mem.writeInt(u32, big[20..24], 20000, .big);
    big[24] = 8;
    big[25] = 6;
    try std.testing.expectError(error.TooLarge, gfx.decode(gpa, &big));
    // chunk 长度声明超出剩余数据。
    std.mem.writeInt(u32, big[8..12], 0xFFFFFFF0, .big);
    try std.testing.expectError(error.DecodeFailed, gfx.decode(gpa, &big));
}

test "REQ-GFX-034 scale variant pick 取不小于 s 的最小档" {
    const k100 = gfx.ImageKey.fromPath("a100");
    const k150 = gfx.ImageKey.fromPath("a150");
    const k200 = gfx.ImageKey.fromPath("a200");
    const set: gfx.ImageSet = .{ .variants = &.{
        .{ .key = k200, .scale_pct = 200 },
        .{ .key = k100, .scale_pct = 100 },
        .{ .key = k150, .scale_pct = 150 },
    } };
    try std.testing.expectEqual(k100, gfx.images.pick(set, 1.0));
    try std.testing.expectEqual(k150, gfx.images.pick(set, 1.25));
    try std.testing.expectEqual(k150, gfx.images.pick(set, 1.5));
    try std.testing.expectEqual(k200, gfx.images.pick(set, 1.75));
    try std.testing.expectEqual(k200, gfx.images.pick(set, 3.0));
    try std.testing.expectEqual(k100, gfx.images.pick(set, 0.75));
    const two: gfx.ImageSet = .{ .variants = &.{
        .{ .key = k100, .scale_pct = 100 },
        .{ .key = k200, .scale_pct = 200 },
    } };
    try std.testing.expectEqual(k200, gfx.images.pick(two, 1.25));
    const one: gfx.ImageSet = .{ .variants = &.{.{ .key = k100, .scale_pct = 100 }} };
    try std.testing.expectEqual(k100, gfx.images.pick(one, 2.0));
}

test "REQ-PERF-005 unwritten metric is not instrumented" {
    core.stats.initRegistry();
    // 仅由 initRegistry 登记、从未在使用点调用的名字：未埋点。
    try std.testing.expect(!core.stats.isInstrumented("list.virtual_cells"));
    try std.testing.expectEqual(@as(?u64, 0), core.stats.read("list.virtual_cells"));
    // 只读查询不置位。
    try std.testing.expect(!core.stats.isInstrumented("list.virtual_cells"));
    core.stats.gauge("list.virtual_cells").* = 3;
    try std.testing.expect(core.stats.isInstrumented("list.virtual_cells"));
    try std.testing.expectEqual(@as(?u64, 3), core.stats.read("list.virtual_cells"));
    try std.testing.expectEqual(@as(?u64, null), core.stats.read("no.such.name"));
}

test "REQ-ARCH-021 stats names have independent storage" {
    try std.testing.expect(nano.core.stats.counter("frame.count") != nano.core.stats.counter("frame.build_passes"));
    try std.testing.expect(nano.core.stats.gauge("cache.text_layout.entries") != nano.core.stats.gauge("cache.text_layout.bytes"));
}

// ---- T7：帧模型 / 布局 / 分层缺陷回归 ----

const T7Model = struct {
    invalidate_once: bool = false,
    calls: u32 = 0,
    n_children: usize = 0,
};

fn t7Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *T7Model = @ptrCast(@alignCast(ctx));
    m.calls += 1;
    if (m.invalidate_once) {
        m.invalidate_once = false;
        u.invalidate(.build);
    }
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    _ = widgets.button(u, @src(), "A", .{ .debug_name = "a", .key = ui.Key.str("a") });
    _ = widgets.button(u, @src(), "B", .{ .debug_name = "b", .key = ui.Key.str("b") });
    u.endColumn();
}

fn t7Frame(u: *ui.Ui, m: *T7Model, now: u64, build_fn: *const fn (*anyopaque, *ui.Ui) void) void {
    u.beginFrame(now, true);
    u.build(@as(*anyopaque, @ptrCast(m)), build_fn);
    u.layoutTree();
    u.finishFrame();
}

test "REQ-FRAME-023 build-time invalidate survives build and requests next frame" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 400, .h = 300 } });
    defer app.deinit();
    var m = T7Model{ .invalidate_once = true };
    app.build_ctx = &m;
    app.build_fn = t7Build;

    // 第 1 帧：构建内 invalidate(.build)，构建函数不嵌套，收尾后仍需下一帧。
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 1), m.calls);
    try std.testing.expect(app.ui_state.needsFrame());
    // 第 2 帧：恰好多出的一帧，再构建一次。
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 2), m.calls);
    // 之后静止。
    try std.testing.expect(!app.ui_state.needsFrame());
    try std.testing.expect(!app.step());
    try std.testing.expectEqual(@as(u32, 2), m.calls);
}

test "REQ-FRAME-043 frame with empty damage clears dirty" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 400, .h = 300 } });
    defer app.deinit();
    var m = T7Model{};
    app.build_ctx = &m;
    app.build_fn = t7Build;
    try std.testing.expect(app.step());
    try std.testing.expect(!app.ui_state.needsFrame());
    // 仅置布局脏、树不变：损伤为空，收尾后不得再要求出帧。
    app.ui_state.invalidate(.layout);
    try std.testing.expect(app.step());
    try std.testing.expect(!app.ui_state.needsFrame());
    try std.testing.expect(!app.step());
}

test "REQ-INPUT-043 clearFocus is not overridden by auto initial focus" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const win = try platform.createWindow(.{});
    var th = theme.Theme.default(.light, .{});
    var u = ui.Ui.init(std.testing.allocator);
    defer u.deinit();
    u.setWindow(win);
    u.setTheme(&th);
    var m = T7Model{};

    t7Frame(&u, &m, 0, t7Build);
    try std.testing.expect(u.focusedId() != .none);
    u.clearFocus();
    u.invalidate(.build);
    t7Frame(&u, &m, 16, t7Build);
    try std.testing.expect(u.focusedId() == .none);
    u.invalidate(.build);
    t7Frame(&u, &m, 32, t7Build);
    try std.testing.expect(u.focusedId() == .none);
}

fn t7ManyBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *T7Model = @ptrCast(@alignCast(ctx));
    _ = u.beginRow(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    var i: usize = 0;
    while (i < m.n_children) : (i += 1) {
        u.pushId(ui.Key.int(i));
        _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
        u.endColumn();
        u.popId();
    }
    u.endRow();
}

test "REQ-LAYOUT-016 no 128 child cap in linear distribution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const n = 200;
    var items: [n]layout.FlexItem = undefined;
    for (&items) |*it| it.* = .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 };
    var out: [n]i32 = undefined;
    _ = layout.distribute(arena.allocator(), &items, 1000, &out);
    var sum: i32 = 0;
    for (out) |v| {
        try std.testing.expect(v == 5);
        sum += v;
    }
    try std.testing.expectEqual(@as(i32, 1000), sum);

    // 余数分配：1100 = 200 x 5 + 100，恰有 100 项为 6，其余为 5，总和不丢失。
    _ = layout.distribute(arena.allocator(), &items, 1100, &out);
    sum = 0;
    var sixes: usize = 0;
    for (out) |v| {
        try std.testing.expect(v == 5 or v == 6);
        if (v == 6) sixes += 1;
        sum += v;
    }
    try std.testing.expectEqual(@as(i32, 1100), sum);
    try std.testing.expectEqual(@as(usize, 100), sixes);
}

test "REQ-LAYOUT-016 200 children in a row all get non-zero width" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const win = try platform.createWindow(.{});
    var th = theme.Theme.default(.light, .{});
    var u = ui.Ui.init(std.testing.allocator);
    defer u.deinit();
    u.setWindow(win);
    u.setTheme(&th);
    var m = T7Model{ .n_children = 200 };
    t7Frame(&u, &m, 0, t7ManyBuild);
    const row = u.current_root.?.first_child.?;
    var count: usize = 0;
    var sum: i32 = 0;
    var c = row.first_child;
    while (c) |cc| : (c = cc.next) {
        count += 1;
        try std.testing.expect(cc.abs.w > 0);
        sum += cc.abs.w;
    }
    try std.testing.expectEqual(@as(usize, 200), count);
    try std.testing.expectEqual(row.abs.w, sum);
}

test "REQ-PLAT-086 headless vsync advances 1000/refresh_hz with accumulated rounding" {
    const H = nano.platform.Headless;
    const t0 = nano.platform.nowMs();
    H.vsync(60);
    try std.testing.expectEqual(@as(u64, 1000), nano.platform.nowMs() - t0);
    const p = H.peekVsyncPeriodMs();
    try std.testing.expect(p == 16 or p == 17);
}
