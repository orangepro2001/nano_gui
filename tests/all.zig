const std = @import("std");
const nano = @import("nano_gui");
const gallery = @import("gallery");
const core = nano.core;
const platform = nano.platform;
const gfx = nano.gfx;
const text = nano.text;
const theme = nano.theme;
const layout = nano.layout;
const input = nano.input;
const ui = nano.ui;
const widgets = nano.widgets;
const uia = nano.uia;
const settings = nano.settings;
const build_source = @import("build_source");
const test_source = @import("test_source");
const ci_source = @import("ci_source");
const acceptance_source = @import("acceptance_source");

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
    _ = @import("platform_m0.zig");
    _ = @import("core_m0.zig");
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
    if (!std.mem.eql(u8, text.backend_name, "fixed")) return error.SkipZigTest;
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
    if (!std.mem.eql(u8, text.backend_name, "fixed")) return error.SkipZigTest;
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
    try std.testing.expect(!core.stats.isInstrumented("loop.block_waits"));
    try std.testing.expectEqual(@as(?u64, 0), core.stats.read("loop.block_waits"));
    // 只读查询不置位。
    try std.testing.expect(!core.stats.isInstrumented("loop.block_waits"));
    core.stats.counter("loop.block_waits").* = 3;
    try std.testing.expect(core.stats.isInstrumented("loop.block_waits"));
    try std.testing.expectEqual(@as(?u64, 3), core.stats.read("loop.block_waits"));
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

// ---------------------------------------------------------------------------
// M5：列表选择模型与输入状态机
// ---------------------------------------------------------------------------

fn expectSel(sel: *const widgets.Selection, keys: []const widgets.ItemKey) !void {
    try std.testing.expectEqual(keys.len, sel.len());
    for (keys) |k| try std.testing.expect(sel.contains(k));
}

fn expectNoSel(sel: *const widgets.Selection) !void {
    try std.testing.expectEqual(@as(usize, 0), sel.len());
}

test "AC-W-LIST-002 Selection 集合语义与 none/single 模式" {
    var sel = widgets.Selection.init(std.testing.allocator);
    defer sel.deinit();
    try sel.add(5);
    try sel.add(5);
    try std.testing.expectEqual(@as(usize, 1), sel.len());
    try std.testing.expectEqual(false, try sel.toggle(5));
    try std.testing.expectEqual(@as(usize, 0), sel.len());
    const view = widgets.KeyView{ .count = 10 };
    try sel.addRange(view, 7, 3);
    try expectSel(&sel, &.{ 3, 4, 5, 6, 7 });
    try sel.setOnly(2);
    try expectSel(&sel, &.{2});
    sel.clear();
    try expectNoSel(&sel);
    try sel.add(1);
    try sel.add(3);
    try sel.add(8);
    sel.pruneTo(.{ .count = 5 });
    try expectSel(&sel, &.{ 1, 3 });

    const Keys = struct {
        fn at(ctx: ?*anyopaque, i: usize) widgets.ItemKey {
            _ = ctx;
            return 100 + @as(widgets.ItemKey, @intCast(i));
        }
    };
    const keyed = widgets.KeyView{ .count = 10, .key_of = Keys.at };
    sel.clear();
    try sel.addRange(keyed, 2, 4);
    try expectSel(&sel, &.{ 102, 103, 104 });

    // 稳定键：数据重排后仍按条目选中；缺省键则停留在下标。
    var order = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const Reorder = struct {
        var rows: []usize = &.{};
        fn keyOf(_: ?*anyopaque, i: usize) widgets.ItemKey {
            return @intCast(rows[i]);
        }
    };
    Reorder.rows = &order;
    const ctr = try std.testing.allocator.create(widgets.ListController);
    defer std.testing.allocator.destroy(ctr);
    ctr.* = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .data = .{ .key_of = Reorder.keyOf } });
    defer ctr.deinit();
    try ctr.selectionPtr().add(2);
    order[2] = 99;
    order[7] = 2;
    try std.testing.expect(ctr.selection().contains(2));

    // single：应用传入 {1,2} 时显示两项，首次点击收敛到 {5}。
    var app_sel = widgets.Selection.init(std.testing.allocator);
    defer app_sel.deinit();
    try app_sel.add(1);
    try app_sel.add(2);
    var single = widgets.ListController.init(std.testing.allocator, .{ .mode = .single, .selection = &app_sel });
    defer single.deinit();
    single.correct(10);
    try std.testing.expectEqual(@as(usize, 2), app_sel.len());
    _ = single.pointerPress(5, .left, .{}, 10);
    try expectSel(&app_sel, &.{5});

    // none：传入集合被忽略（不改写应用集合），所有选择操作无效果。
    var none_sel = widgets.Selection.init(std.testing.allocator);
    defer none_sel.deinit();
    try none_sel.add(1);
    var none = widgets.ListController.init(std.testing.allocator, .{ .mode = .none, .selection = &none_sel });
    defer none.deinit();
    none.correct(10);
    const np = none.pointerPress(3, .left, .{}, 10);
    const nspace = none.keyDown(.space, .{}, false, 10, 0);
    const nall = none.keyDown(.a, .{ .ctrl = true }, false, 10, 0);
    try std.testing.expect(!np.selection_changed and !nspace.selection_changed and !nall.selection_changed);
    try expectSel(&none_sel, &.{1});
    try std.testing.expectEqual(@as(?usize, 3), none.update.focus_index);

    // selection_changed：选中单行再次点击为假；多选折叠为真。
    var click_sel = widgets.Selection.init(std.testing.allocator);
    defer click_sel.deinit();
    try click_sel.add(3);
    var multi = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .selection = &click_sel });
    defer multi.deinit();
    multi.correct(10);
    try std.testing.expect(!multi.pointerPress(3, .left, .{}, 10).selection_changed);
    _ = multi.pointerRelease(3, true, 1, .{}, 10);
    try click_sel.add(4);
    // 多选中的已选行按下不改变选择，释放折叠时改变。
    try std.testing.expect(!multi.pointerPress(3, .left, .{}, 10).selection_changed);
    try std.testing.expect(multi.pointerRelease(3, true, 1, .{}, 10).selection_changed);
    try expectSel(&click_sel, &.{3});
}

test "AC-W-LIST-003 鼠标选择：单击、Shift、Ctrl、Ctrl+Shift、替换区间" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.correct(10);
    const sel = c.selectionPtr();

    var u = c.pointerPress(3, .left, .{}, 10);
    _ = c.pointerRelease(3, true, 1, .{}, 10);
    try expectSel(sel, &.{3});
    try std.testing.expect(u.selection_changed);
    try std.testing.expectEqual(@as(?usize, 3), c.update.focus_index);

    u = c.pointerPress(7, .left, .{ .shift = true }, 10);
    _ = c.pointerRelease(7, true, 1, .{ .shift = true }, 10);
    try expectSel(sel, &.{ 3, 4, 5, 6, 7 });
    try std.testing.expect(u.selection_changed);
    try std.testing.expectEqual(@as(?usize, 3), c.anchor.?.index);

    u = c.pointerPress(5, .left, .{ .ctrl = true }, 10);
    _ = c.pointerRelease(5, true, 1, .{ .ctrl = true }, 10);
    try expectSel(sel, &.{ 3, 4, 6, 7 });
    try std.testing.expect(u.selection_changed);
    try std.testing.expectEqual(@as(?usize, 5), c.anchor.?.index);

    _ = c.pointerPress(9, .left, .{ .ctrl = true }, 10);
    _ = c.pointerRelease(9, true, 1, .{ .ctrl = true }, 10);
    try expectSel(sel, &.{ 3, 4, 6, 7, 9 });
    _ = c.pointerPress(1, .left, .{ .ctrl = true, .shift = true }, 10);
    _ = c.pointerRelease(1, true, 1, .{ .ctrl = true, .shift = true }, 10);
    try expectSel(sel, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 });
    try std.testing.expectEqual(@as(?usize, 9), c.anchor.?.index);

    _ = c.pointerPress(6, .left, .{ .shift = true }, 10);
    _ = c.pointerRelease(6, true, 1, .{ .shift = true }, 10);
    try expectSel(sel, &.{ 6, 7, 8, 9 });
    _ = c.pointerPress(6, .left, .{ .ctrl = true }, 10);
    _ = c.pointerRelease(6, true, 1, .{ .ctrl = true }, 10);
    try expectSel(sel, &.{ 7, 8, 9 });

    _ = c.pointerPress(0, .left, .{}, 10);
    _ = c.pointerRelease(0, true, 1, .{}, 10);
    try expectSel(sel, &.{0});
    try std.testing.expect(!c.pointerPress(0, .left, .{}, 10).selection_changed);
    _ = c.pointerRelease(0, true, 1, .{}, 10);
    _ = c.pointerPress(4, .left, .{ .shift = true }, 10);
    _ = c.pointerRelease(4, true, 1, .{ .shift = true }, 10);
    try expectSel(sel, &.{ 0, 1, 2, 3, 4 });

    var c2 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c2.deinit();
    c2.correct(10);
    _ = c2.pointerPress(4, .left, .{ .shift = true }, 10);
    _ = c2.pointerRelease(4, true, 1, .{ .shift = true }, 10);
    try expectSel(c2.selectionPtr(), &.{4});
    try std.testing.expectEqual(@as(?usize, 4), c2.anchor.?.index);
}

test "AC-W-LIST-004 多选中已选行按下延迟折叠与拖动不折叠" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.correct(10);
    const sel = c.selectionPtr();
    for ([_]widgets.ItemKey{ 2, 3, 4, 5 }) |k| try sel.add(k);
    c.focus = .{ .index = 5, .key = 5 };
    c.anchor = .{ .index = 2, .key = 2 };

    var u = c.pointerPress(3, .left, .{}, 10);
    try std.testing.expect(!u.selection_changed);
    try expectSel(sel, &.{ 2, 3, 4, 5 });
    try std.testing.expectEqual(@as(?usize, 3), c.focus.?.index);
    u = c.pointerRelease(3, true, 1, .{}, 10);
    try std.testing.expect(u.selection_changed);
    try expectSel(sel, &.{3});

    // 在行 3 按下后移到行 6 释放：不折叠。
    sel.clear();
    for ([_]widgets.ItemKey{ 2, 3, 4, 5 }) |k| try sel.add(k);
    _ = c.pointerPress(3, .left, .{}, 10);
    u = c.pointerRelease(6, false, 1, .{}, 10);
    try std.testing.expect(!u.selection_changed);
    try expectSel(sel, &.{ 2, 3, 4, 5 });

    // reorder：越过阈值开始拖动，随后取消不折叠。
    var ro = widgets.ListController.init(std.testing.allocator, .{
        .mode = .multi,
        .reorder = true,
        .data = .{ .key_of = struct {
            fn f(_: ?*anyopaque, i: usize) widgets.ItemKey {
                return @intCast(i);
            }
        }.f },
    });
    defer ro.deinit();
    ro.correct(10);
    for ([_]widgets.ItemKey{ 2, 3, 4, 5 }) |k| try ro.selectionPtr().add(k);
    _ = ro.pointerPress(3, .left, .{}, 10);
    const du = ro.dragStart(10);
    try std.testing.expect(du.drag_started);
    ro.cancelDrag();
    u = ro.pointerRelease(3, true, 1, .{}, 10);
    try std.testing.expect(!u.selection_changed);
    try expectSel(ro.selectionPtr(), &.{ 2, 3, 4, 5 });

    // Ctrl 按下立即切换。
    sel.clear();
    for ([_]widgets.ItemKey{ 2, 3, 4, 5 }) |k| try sel.add(k);
    _ = c.pointerPress(3, .left, .{ .ctrl = true }, 10);
    _ = c.pointerRelease(3, true, 1, .{ .ctrl = true }, 10);
    try expectSel(sel, &.{ 2, 4, 5 });
    // 未选中行按下立即收敛。
    _ = c.pointerPress(8, .left, .{}, 10);
    _ = c.pointerRelease(8, true, 1, .{}, 10);
    try expectSel(sel, &.{8});
    // 只选中一行时无待折叠。
    try std.testing.expect(!c.pointerPress(8, .left, .{}, 10).selection_changed);
}

test "AC-W-LIST-005 single 与 none 模式" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .single });
    defer c.deinit();
    c.correct(10);
    const sel = c.selectionPtr();
    _ = c.pointerPress(3, .left, .{}, 10);
    try expectSel(sel, &.{3});
    _ = c.pointerPress(5, .left, .{}, 10);
    try expectSel(sel, &.{5});
    _ = c.pointerPress(8, .left, .{ .shift = true }, 10);
    try expectSel(sel, &.{8});
    _ = c.pointerPress(8, .left, .{ .ctrl = true }, 10);
    try expectNoSel(sel);
    try std.testing.expectEqual(@as(?usize, 8), c.focus.?.index);
    _ = c.pointerPress(2, .left, .{ .ctrl = true }, 10);
    try expectSel(sel, &.{2});
    _ = c.keyDown(.down, .{}, false, 10, 0);
    try expectSel(sel, &.{3});
    _ = c.keyDown(.space, .{ .ctrl = true }, false, 10, 0);
    try expectNoSel(sel);
    const u = c.keyDown(.a, .{ .ctrl = true }, false, 10, 0);
    try std.testing.expect(!u.consumed);
    try expectNoSel(sel);

    var n = widgets.ListController.init(std.testing.allocator, .{ .mode = .none });
    defer n.deinit();
    n.correct(10);
    const np = n.pointerPress(3, .left, .{}, 10);
    try std.testing.expect(!np.selection_changed);
    try std.testing.expectEqual(@as(?usize, 3), n.focus.?.index);
    _ = n.keyDown(.down, .{}, false, 10, 0);
    try std.testing.expectEqual(@as(?usize, 4), n.focus.?.index);
    _ = n.keyDown(.space, .{}, false, 10, 0);
    _ = n.keyDown(.a, .{ .ctrl = true }, false, 10, 0);
    try expectNoSel(n.selectionPtr());
    try std.testing.expectEqual(@as(?usize, 5), n.pointerRelease(5, true, 2, .{}, 10).activated);
    try std.testing.expectEqual(@as(?usize, 4), n.keyDown(.enter, .{}, false, 10, 0).activated);
}

test "AC-W-LIST-006 右键、空白处与上下文菜单" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.correct(10);
    const sel = c.selectionPtr();
    try sel.add(2);
    try sel.add(3);
    c.anchor = .{ .index = 2, .key = 2 };
    c.focus = .{ .index = 3, .key = 3 };

    _ = c.pointerPress(8, .right, .{}, 10);
    try expectSel(sel, &.{8});
    try std.testing.expectEqual(@as(?usize, 8), c.anchor.?.index);
    const cm = c.contextMenu(8, .{ .x = 10, .y = 200 }, false);
    try std.testing.expectEqual(@as(?usize, 8), cm.context_menu.?.index);
    try std.testing.expect(!cm.context_menu.?.from_keyboard);

    sel.clear();
    try sel.add(2);
    try sel.add(3);
    c.anchor = .{ .index = 2, .key = 2 };
    c.focus = .{ .index = 3, .key = 3 };
    _ = c.pointerPress(3, .right, .{}, 10);
    try expectSel(sel, &.{ 2, 3 });
    try std.testing.expectEqual(@as(?usize, 3), c.contextMenu(3, .{}, false).context_menu.?.index);

    _ = c.pointerPress(null, .left, .{}, 10);
    try expectNoSel(sel);
    try std.testing.expectEqual(@as(?usize, 3), c.focus.?.index);
    try std.testing.expect(!c.pointerPress(null, .left, .{}, 10).selection_changed);
    try std.testing.expectEqual(@as(?usize, null), c.contextMenu(null, .{}, false).context_menu.?.index);

    c.focus = .{ .index = 4, .key = 4 };
    const kb = c.keyDown(.f10, .{ .shift = true }, false, 10, 0);
    try std.testing.expectEqual(@as(?usize, 4), kb.context_menu.?.index);
    try std.testing.expect(kb.context_menu.?.from_keyboard);
    try std.testing.expectEqual(@as(f32, 88), kb.context_menu.?.anchor.y);
    try std.testing.expectEqual(@as(f32, 22), kb.context_menu.?.anchor.h);
}

test "AC-W-LIST-007 双击激活与滚入" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.viewport_h = 220;
    c.correct(10);
    _ = c.pointerPress(4, .left, .{}, 10);
    try std.testing.expectEqual(@as(?usize, null), c.pointerRelease(4, true, 1, .{}, 10).activated);
    _ = c.pointerPress(4, .left, .{}, 10);
    try std.testing.expectEqual(@as(?usize, 4), c.pointerRelease(4, true, 2, .{}, 10).activated);
    try expectSel(c.selectionPtr(), &.{4});
    _ = c.pointerPress(4, .left, .{ .ctrl = true }, 10);
    try std.testing.expectEqual(@as(?usize, null), c.pointerRelease(4, true, 2, .{ .ctrl = true }, 10).activated);
    _ = c.pointerPress(4, .left, .{ .shift = true }, 10);
    try std.testing.expectEqual(@as(?usize, null), c.pointerRelease(4, true, 2, .{ .shift = true }, 10).activated);
    try std.testing.expectEqual(@as(?usize, null), c.pointerRelease(null, true, 2, .{}, 10).activated);

    // 100 行、偏移 11 时单击行 0 的可见部分 → 偏移回到 0。
    var c2 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c2.deinit();
    c2.viewport_h = 220;
    c2.correct(100);
    c2.offset = 11;
    _ = c2.pointerPress(0, .left, .{}, 100);
    try std.testing.expectEqual(@as(f32, 0), c2.offset);
    c2.offset = 0;
    _ = c2.pointerPress(5, .left, .{}, 100);
    try std.testing.expectEqual(@as(f32, 0), c2.offset);
}

test "AC-W-LIST-008 键盘方向键与焦点初始值" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.viewport_h = 220;
    c.correct(10);
    // 以键盘获得焦点且无焦点行时取第 0 行。
    if (c.focus == null) c.focus = c.refAt(0);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    _ = c.keyDown(.down, .{}, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{1});
    try std.testing.expectEqual(@as(?usize, 1), c.anchor.?.index);
    _ = c.keyDown(.down, .{}, false, 10, 0);
    _ = c.keyDown(.down, .{}, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{3});
    _ = c.keyDown(.up, .{}, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{2});
    c.focus = c.refAt(0);
    c.selectionPtr().setOnly(0) catch {};
    _ = c.keyDown(.up, .{}, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{0});

    c.selectionPtr().setOnly(3) catch {};
    c.focus = c.refAt(3);
    c.anchor = c.refAt(3);
    _ = c.keyDown(.down, .{ .shift = true }, false, 10, 0);
    _ = c.keyDown(.down, .{ .shift = true }, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{ 3, 4, 5 });
    _ = c.keyDown(.up, .{ .shift = true }, false, 10, 0);
    _ = c.keyDown(.up, .{ .shift = true }, false, 10, 0);
    _ = c.keyDown(.up, .{ .shift = true }, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{ 2, 3 });

    // Ctrl+↓ 仅移动焦点。
    c.selectionPtr().clear();
    c.selectionPtr().add(2) catch {};
    c.selectionPtr().add(3) catch {};
    c.focus = c.refAt(2);
    c.anchor = c.refAt(3);
    _ = c.keyDown(.down, .{ .ctrl = true }, false, 10, 0);
    _ = c.keyDown(.down, .{ .ctrl = true }, false, 10, 0);
    _ = c.keyDown(.down, .{ .ctrl = true }, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{ 2, 3 });
    try std.testing.expectEqual(@as(?usize, 5), c.focus.?.index);

    // Ctrl+Shift+↑ 并入区间。
    c.selectionPtr().clear();
    c.selectionPtr().add(1) catch {};
    c.selectionPtr().add(5) catch {};
    c.focus = c.refAt(5);
    c.anchor = c.refAt(5);
    _ = c.keyDown(.up, .{ .ctrl = true, .shift = true }, false, 10, 0);
    _ = c.keyDown(.up, .{ .ctrl = true, .shift = true }, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{ 1, 3, 4, 5 });

    // Alt+↓ 不处理。
    const before = c.focus.?.index;
    const u = c.keyDown(.down, .{ .alt = true }, false, 10, 0);
    try std.testing.expect(!u.consumed);
    try std.testing.expectEqual(before, c.focus.?.index);
}

test "AC-W-LIST-009 Page/Home/End 与夹紧" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.viewport_h = 132;
    c.correct(20);
    try std.testing.expectEqual(@as(usize, 5), c.pageRows());
    c.focus = c.refAt(0);
    c.selectionPtr().setOnly(0) catch {};
    _ = c.keyDown(.page_down, .{}, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{5});
    _ = c.keyDown(.page_down, .{}, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{10});
    _ = c.keyDown(.page_up, .{}, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{5});
    c.focus = c.refAt(3);
    _ = c.keyDown(.page_up, .{}, false, 20, 0);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    c.focus = c.refAt(17);
    _ = c.keyDown(.page_down, .{}, false, 20, 0);
    try std.testing.expectEqual(@as(?usize, 19), c.focus.?.index);

    c.focus = c.refAt(5);
    c.anchor = c.refAt(5);
    c.selectionPtr().setOnly(5) catch {};
    _ = c.keyDown(.page_down, .{ .shift = true }, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{ 5, 6, 7, 8, 9, 10 });
    _ = c.keyDown(.page_down, .{ .shift = true }, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{ 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 });
    const f_before = c.focus.?.index;
    const sel_before = c.selectionPtr().len();
    const u = c.keyDown(.page_down, .{ .ctrl = true }, false, 20, 0);
    try std.testing.expect(!u.consumed);
    try std.testing.expectEqual(f_before, c.focus.?.index);
    try std.testing.expectEqual(sel_before, c.selectionPtr().len());

    _ = c.keyDown(.home, .{}, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{0});
    _ = c.keyDown(.end, .{}, false, 20, 0);
    try expectSel(c.selectionPtr(), &.{19});
    _ = c.keyDown(.home, .{ .shift = true }, false, 20, 0);
    try std.testing.expectEqual(@as(usize, 20), c.selectionPtr().len());
    _ = c.keyDown(.end, .{ .ctrl = true }, false, 20, 0);
    try std.testing.expectEqual(@as(usize, 20), c.selectionPtr().len());
    try std.testing.expectEqual(@as(?usize, 19), c.focus.?.index);

    c.viewport_h = 20;
    try std.testing.expectEqual(@as(usize, 1), c.pageRows());
}

test "AC-W-LIST-010 Space、Ctrl+A、Enter 与空列表" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.correct(10);
    c.focus = c.refAt(4);
    c.selectionPtr().add(1) catch {};
    c.selectionPtr().add(2) catch {};
    _ = c.keyDown(.space, .{}, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{4});
    _ = c.keyDown(.space, .{ .ctrl = true }, false, 10, 0);
    try expectNoSel(c.selectionPtr());
    _ = c.keyDown(.space, .{ .ctrl = true }, false, 10, 0);
    try expectSel(c.selectionPtr(), &.{4});
    const u = c.keyDown(.a, .{ .ctrl = true }, false, 10, 0);
    try std.testing.expect(u.selection_changed);
    try std.testing.expectEqual(@as(usize, 10), c.selectionPtr().len());
    try std.testing.expect(!c.keyDown(.a, .{ .ctrl = true }, false, 10, 0).selection_changed);
    _ = c.keyDown(.enter, .{}, false, 10, 0);
    try std.testing.expectEqual(@as(?usize, 4), c.update.activated);
    try std.testing.expectEqual(@as(?usize, null), c.keyDown(.enter, .{}, true, 10, 0).activated);
    try std.testing.expectEqual(@as(usize, 10), c.selectionPtr().len());

    var empty = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer empty.deinit();
    empty.correct(0);
    try std.testing.expectEqual(@as(?usize, null), empty.keyDown(.down, .{}, false, 0, 0).focus_index);
    try std.testing.expect(!empty.keyDown(.a, .{ .ctrl = true }, false, 0, 0).consumed);
    try std.testing.expectEqual(@as(?usize, null), empty.keyDown(.enter, .{}, false, 0, 0).activated);
    try std.testing.expectEqual(@as(usize, 0), empty.selectionPtr().len());
}

const SearchRows = struct {
    const rows = [_][]const u8{ "Apple", "Apricot", "Banana", "Blueberry", "Cherry", "Date", "Elderberry", "Fig", "Grape", "Honeydew" };
    fn text(_: ?*anyopaque, i: usize) []const u8 {
        return rows[i];
    }
};

test "AC-W-LIST-011 前缀搜索与超时" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .data = .{ .item_text = SearchRows.text } });
    defer c.deinit();
    c.correct(10);
    c.focus = c.refAt(0);
    _ = c.charInput('b', .{}, 10, 0);
    try std.testing.expectEqual(@as(?usize, 2), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{2});
    _ = c.charInput('l', .{}, 10, 300);
    try std.testing.expectEqual(@as(?usize, 3), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{3});
    _ = c.charInput('b', .{}, 10, 1301);
    try std.testing.expectEqual(@as(?usize, 2), c.focus.?.index);
    _ = c.charInput('z', .{}, 10, 1302);
    try std.testing.expectEqual(@as(?usize, 2), c.focus.?.index);
    try std.testing.expectEqualStrings("bz", c.searchText());
    _ = c.charInput('B', .{ .shift = true }, 10, 2303);
    try std.testing.expectEqual(@as(?usize, 3), c.focus.?.index);
    const no = c.charInput('b', .{ .ctrl = true }, 10, 2304);
    try std.testing.expect(!no.consumed);

    // 缓冲非空时 Space 追加为字符而不是选择。
    _ = c.charInput('a', .{}, 10, 3400);
    c.focus = c.refAt(3);
    c.selectionPtr().setOnly(3) catch {};
    _ = c.keyDown(.space, .{}, false, 10, 3400);
    try expectSel(c.selectionPtr(), &.{3});
    _ = c.charInput(' ', .{}, 10, 3401);
    try std.testing.expectEqualStrings("a ", c.searchText());

    // none 模式只移动焦点。
    var n = widgets.ListController.init(std.testing.allocator, .{ .mode = .none, .data = .{ .item_text = SearchRows.text } });
    defer n.deinit();
    n.correct(10);
    n.focus = n.refAt(0);
    _ = n.charInput('c', .{}, 10, 0);
    try std.testing.expectEqual(@as(?usize, 4), n.focus.?.index);
    try expectNoSel(n.selectionPtr());

    // 没有 item_text / prefix_search：字符不被消费。
    var plain = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer plain.deinit();
    plain.correct(10);
    try std.testing.expect(!plain.charInput('a', .{}, 10, 0).consumed);
}

const PrefixCalls = struct {
    var count: usize = 0;
    fn search(_: ?*anyopaque, prefix: []const u8, start: usize) ?usize {
        _ = prefix;
        count += 1;
        return start + 5;
    }
};

test "AC-W-LIST-011 prefix_search 回调优先" {
    PrefixCalls.count = 0;
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .data = .{ .prefix_search = PrefixCalls.search } });
    defer c.deinit();
    c.correct(100000);
    _ = c.charInput('x', .{}, 100000, 0);
    try std.testing.expect(PrefixCalls.count > 0);
}

test "AC-W-LIST-012 焦点行始终以最小位移滚入" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.viewport_h = 220;
    c.correct(100);
    c.focus = c.refAt(0);
    var i: usize = 0;
    while (i < 10) : (i += 1) _ = c.keyDown(.down, .{}, false, 100, 0);
    try std.testing.expectEqual(@as(?usize, 10), c.focus.?.index);
    try std.testing.expectEqual(@as(f32, 22), c.offset);
    _ = c.keyDown(.down, .{}, false, 100, 0);
    try std.testing.expectEqual(@as(f32, 44), c.offset);
    _ = c.keyDown(.end, .{}, false, 100, 0);
    try std.testing.expectEqual(@as(f32, 1980), c.offset);
    _ = c.keyDown(.home, .{}, false, 100, 0);
    try std.testing.expectEqual(@as(f32, 0), c.offset);
    _ = c.keyDown(.page_down, .{}, false, 100, 0);
    try std.testing.expectEqual(@as(?usize, 9), c.focus.?.index);
    try std.testing.expectEqual(@as(f32, 0), c.offset);
    _ = c.keyDown(.page_down, .{}, false, 100, 0);
    try std.testing.expectEqual(@as(f32, 198), c.offset);
    _ = c.scrollIntoView(60, 100);
    try std.testing.expectEqual(@as(f32, 1122), c.offset);
    c.focus = c.refAt(60);
    _ = c.keyDown(.down, .{ .ctrl = true }, false, 100, 0);
    try std.testing.expectEqual(@as(f32, 1144), c.offset);
}

test "AC-W-LIST-013 可见窗口公式与虚拟范围" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .row_height = 22 });
    defer c.deinit();
    c.viewport_h = 660;
    c.correct(100000);
    var r = c.visibleRange(100000);
    try std.testing.expectEqual(@as(usize, 0), r.first);
    try std.testing.expectEqual(@as(usize, 34), r.last);
    c.offset = 22000;
    r = c.visibleRange(100000);
    try std.testing.expectEqual(@as(usize, 995), r.first);
    try std.testing.expectEqual(@as(usize, 1034), r.last);
    c.offset = 22011;
    r = c.visibleRange(100000);
    try std.testing.expectEqual(@as(usize, 995), r.first);
    try std.testing.expectEqual(@as(usize, 1035), r.last);
    c.offset = c.maxOffset(100000);
    try std.testing.expectEqual(@as(f32, 2199340), c.offset);
    r = c.visibleRange(100000);
    try std.testing.expectEqual(@as(usize, 99965), r.first);
    try std.testing.expectEqual(@as(usize, 99999), r.last);
    try std.testing.expectEqual(@as(f32, 2200000), @as(f32, @floatFromInt(100000)) * c.rowHeight());
    c.offset = 0;
    r = c.visibleRange(0);
    try std.testing.expect(!r.has_rows);
    r = c.visibleRange(3);
    try std.testing.expectEqual(@as(usize, 0), r.first);
    try std.testing.expectEqual(@as(usize, 2), r.last);
}

test "AC-W-LIST-015 焦点/锚点按键校正与数据重排" {
    const Model = struct {
        var order = [_]widgets.ItemKey{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        fn keyOf(_: ?*anyopaque, i: usize) widgets.ItemKey {
            return order[i];
        }
        fn indexOf(_: ?*anyopaque, key: widgets.ItemKey) ?usize {
            for (order, 0..) |k, i| if (k == key) return i;
            return null;
        }
    };
    Model.order = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var c = widgets.ListController.init(std.testing.allocator, .{
        .mode = .multi,
        .data = .{ .key_of = Model.keyOf, .index_of = Model.indexOf },
    });
    defer c.deinit();
    c.correct(10);
    try c.selectionPtr().add(2);
    try c.selectionPtr().add(3);
    c.focus = .{ .index = 3, .key = 3 };
    c.anchor = .{ .index = 2, .key = 2 };
    // 顺序 D, C, A, B, E...
    Model.order = .{ 3, 2, 0, 1, 4, 5, 6, 7, 8, 9 };
    c.correct(10);
    try expectSel(c.selectionPtr(), &.{ 2, 3 });
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    try std.testing.expectEqual(@as(?usize, 1), c.anchor.?.index);
    // 删除 D（键 3）。
    Model.order = .{ 2, 0, 1, 4, 5, 6, 7, 8, 9, 9 };
    c.correct(9);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    try std.testing.expectEqual(@as(?usize, 0), c.anchor.?.index);
    try std.testing.expect(c.selectionPtr().contains(3));
    try std.testing.expectEqual(@as(usize, 2), c.selectionPtr().len());
    c.selectionPtr().pruneTo(.{ .count = 9, .key_of = Model.keyOf });
    try std.testing.expectEqual(@as(usize, 1), c.selectionPtr().len());
    try std.testing.expect(!c.selectionPtr().contains(3));

    // 无 index_of：保持下标，键更新。
    const Plain = struct {
        var order = [_]widgets.ItemKey{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        fn keyOf(_: ?*anyopaque, i: usize) widgets.ItemKey {
            return order[i];
        }
    };
    Plain.order = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var p = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .data = .{ .key_of = Plain.keyOf } });
    defer p.deinit();
    p.correct(10);
    p.focus = .{ .index = 3, .key = 3 };
    p.anchor = .{ .index = 2, .key = 2 };
    Plain.order = .{ 3, 2, 0, 1, 4, 5, 6, 7, 8, 9 };
    p.correct(10);
    try std.testing.expectEqual(@as(?usize, 3), p.focus.?.index);
    try std.testing.expectEqual(@as(widgets.ItemKey, 1), p.focus.?.key);

    // count 变 0：焦点、锚点清空，偏移归零。
    p.correct(0);
    try std.testing.expect(p.focus == null);
    try std.testing.expect(p.anchor == null);
    try std.testing.expectEqual(@as(f32, 0), p.offset);
    // count 缩小：偏移夹紧。
    var q = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .row_height = 22 });
    defer q.deinit();
    q.viewport_h = 220;
    q.correct(100);
    q.offset = 1000;
    q.correct(20);
    try std.testing.expectEqual(@as(f32, 220), q.offset);
}

test "AC-W-LIST-016 拖动重排的插入位置与无操作判定" {
    const Keys = struct {
        fn f(_: ?*anyopaque, i: usize) widgets.ItemKey {
            return @intCast(i);
        }
    };
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .reorder = true, .data = .{ .key_of = Keys.f } });
    defer c.deinit();
    c.viewport_h = 220;
    c.correct(10);
    try c.selectionPtr().add(2);
    try c.selectionPtr().add(3);
    c.focus = c.refAt(3);
    c.anchor = c.refAt(2);
    _ = c.pointerPress(3, .left, .{}, 10);
    try std.testing.expect(c.dragStart(10).drag_started);
    try expectSel(c.selectionPtr(), &.{ 2, 3 });
    var u = c.drop(std.testing.allocator, 149, 10);
    try std.testing.expectEqual(@as(?usize, 7), if (u.reordered) |r| r.insert_at else null);
    try std.testing.expectEqual(@as(usize, 2), u.reordered.?.keys.len);
    try std.testing.expectEqual(@as(widgets.ItemKey, 2), u.reordered.?.keys[0]);
    std.testing.allocator.free(u.reordered.?.keys);
    try expectSel(c.selectionPtr(), &.{ 2, 3 });

    // 连续块边界之内：无操作。
    const Noop = struct {
        fn check(ins_y: f32) !void {
            var c2 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .reorder = true, .data = .{ .key_of = Keys.f } });
            defer c2.deinit();
            c2.correct(10);
            try c2.selectionPtr().add(2);
            try c2.selectionPtr().add(3);
            c2.focus = c2.refAt(3);
            _ = c2.pointerPress(3, .left, .{}, 10);
            _ = c2.dragStart(10);
            const uu = c2.drop(std.testing.allocator, ins_y, 10);
            try std.testing.expectEqual(@as(?usize, null), if (uu.reordered) |r| r.insert_at else null);
        }
    };
    try Noop.check(50);
    try Noop.check(80);
    try Noop.check(91);
    var c3 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .reorder = true, .data = .{ .key_of = Keys.f } });
    defer c3.deinit();
    c3.correct(10);
    try c3.selectionPtr().add(2);
    try c3.selectionPtr().add(3);
    c3.focus = c3.refAt(3);
    _ = c3.pointerPress(3, .left, .{}, 10);
    _ = c3.dragStart(10);
    u = c3.drop(std.testing.allocator, 113, 10);
    try std.testing.expectEqual(@as(?usize, 5), if (u.reordered) |r| r.insert_at else null);
    std.testing.allocator.free(u.reordered.?.keys);

    // 非连续选择一律报告。
    var c4 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .reorder = true, .data = .{ .key_of = Keys.f } });
    defer c4.deinit();
    c4.correct(10);
    try c4.selectionPtr().add(1);
    try c4.selectionPtr().add(5);
    c4.focus = c4.refAt(5);
    _ = c4.pointerPress(5, .left, .{}, 10);
    _ = c4.dragStart(10);
    u = c4.drop(std.testing.allocator, 70, 10);
    try std.testing.expect(u.reordered != null);
    try std.testing.expectEqual(@as(?usize, 3), if (u.reordered) |r| r.insert_at else null);
    std.testing.allocator.free(u.reordered.?.keys);

    // Esc / 取消：无结果。
    var c5 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .reorder = true, .data = .{ .key_of = Keys.f } });
    defer c5.deinit();
    c5.correct(10);
    try c5.selectionPtr().add(2);
    _ = c5.pointerPress(2, .left, .{}, 10);
    _ = c5.dragStart(10);
    c5.cancelDrag();
    try std.testing.expect(c5.drop(std.testing.allocator, 149, 10).reordered == null);
}

test "AC-W-LIST-017 滚轮行数与整页" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.viewport_h = 220;
    c.correct(100);
    _ = c.wheel(-1, 100, .{ .lines = 3 }, .{});
    try std.testing.expectEqual(@as(f32, 66), c.offset);
    _ = c.wheel(1, 100, .{ .lines = 3 }, .{});
    try std.testing.expectEqual(@as(f32, 0), c.offset);
    _ = c.wheel(-1, 100, .page, .{});
    try std.testing.expectEqual(@as(f32, 198), c.offset);
    c.offset = 0;
    _ = c.wheel(-1, 100, .{ .lines = 0 }, .{});
    try std.testing.expectEqual(@as(f32, 0), c.offset);
    var i: usize = 0;
    while (i < 4) : (i += 1) _ = c.wheel(-0.25, 100, .{ .lines = 3 }, .{});
    try std.testing.expectEqual(@as(f32, 66), c.offset);
    c.offset = 0;
    _ = c.wheel(-1, 100, .{ .lines = 3 }, .{ .shift = true });
    try std.testing.expectEqual(@as(f32, 0), c.offset);
    c.offset = c.maxOffset(100);
    _ = c.wheel(-1, 100, .{ .lines = 3 }, .{});
    try std.testing.expectEqual(c.maxOffset(100), c.offset);
}

test "AC-W-LIST-020 空列表状态" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi });
    defer c.deinit();
    c.correct(0);
    try std.testing.expect(c.focus == null);
    try std.testing.expect(!c.visibleRange(0).has_rows);
    try std.testing.expectEqual(@as(?usize, null), c.keyDown(.down, .{}, false, 0, 0).focus_index);
    try std.testing.expectEqual(@as(?usize, null), c.keyDown(.enter, .{}, false, 0, 0).activated);
    try std.testing.expect(!c.keyDown(.space, .{}, false, 0, 0).consumed);
    try std.testing.expectEqual(@as(usize, 0), c.selectionPtr().len());
    c.correct(5);
    try std.testing.expect(c.focus == null);
    try std.testing.expect(c.visibleRange(5).has_rows);
}

test "AC-W-LIST-023 百万行逐像素精确" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .row_height = 22 });
    defer c.deinit();
    c.viewport_h = 660;
    c.correct(1000000);
    try std.testing.expectEqual(@as(f32, 22000000), @as(f32, @floatFromInt(1000000)) * c.rowHeight());
    c.offset = c.maxOffset(1000000);
    try std.testing.expectEqual(@as(f32, 21999340), c.offset);
    const r = c.visibleRange(1000000);
    try std.testing.expectEqual(@as(usize, 999965), r.first);
    try std.testing.expectEqual(@as(usize, 999999), r.last);
    try std.testing.expectEqual(@as(f32, 0), c.rowRect(999970).y);
    try std.testing.expectEqual(@as(f32, -110), c.rowRect(999965).y);
    c.offset = 16777216;
    try std.testing.expectEqual(@as(f32, -16), c.rowRect(762600).y);
    c.offset += 22;
    try std.testing.expectEqual(@as(f32, -38), c.rowRect(762600).y);
    try std.testing.expectEqual(@as(f32, 22), c.rowRect(762601).y - c.rowRect(762600).y);
}

// ---------------------------------------------------------------------------
// M5：树
// ---------------------------------------------------------------------------

const T1 = struct {
    const A: widgets.TreeNode = @fromBackingInt(1);
    const A1: widgets.TreeNode = @fromBackingInt(2);
    const A2: widgets.TreeNode = @fromBackingInt(3);
    const A2a: widgets.TreeNode = @fromBackingInt(4);
    const A2b: widgets.TreeNode = @fromBackingInt(5);
    const A3: widgets.TreeNode = @fromBackingInt(6);
    const B: widgets.TreeNode = @fromBackingInt(7);
    const B1: widgets.TreeNode = @fromBackingInt(8);
    const C: widgets.TreeNode = @fromBackingInt(9);

    const top = [_]widgets.TreeNode{ A, B, C };
    const a_children = [_]widgets.TreeNode{ A1, A2, A3 };
    const a2_children = [_]widgets.TreeNode{ A2a, A2b };
    const b_children = [_]widgets.TreeNode{B1};

    var loading_b = false;
    var b_child_count: usize = 1;
    var child_count_calls: usize = 0;
    var child_at_calls: usize = 0;
    var has_children_calls: usize = 0;
    var key_of_calls: usize = 0;
    var text_of_calls: usize = 0;

    fn resetCounts() void {
        child_count_calls = 0;
        child_at_calls = 0;
        has_children_calls = 0;
        key_of_calls = 0;
        text_of_calls = 0;
    }

    fn children(node: widgets.TreeNode) []const widgets.TreeNode {
        if (node == .root) return &top;
        if (node == A) return &a_children;
        if (node == A2) return &a2_children;
        if (node == B) return b_children[0..b_child_count];
        return &.{};
    }
    fn childCount(_: ?*anyopaque, node: widgets.TreeNode) usize {
        child_count_calls += 1;
        return children(node).len;
    }
    fn childAt(_: ?*anyopaque, node: widgets.TreeNode, i: usize) widgets.TreeNode {
        child_at_calls += 1;
        return children(node)[i];
    }
    fn hasChildren(_: ?*anyopaque, node: widgets.TreeNode) bool {
        has_children_calls += 1;
        return node == A or node == A2 or node == B;
    }
    fn keyOf(_: ?*anyopaque, node: widgets.TreeNode) widgets.ItemKey {
        key_of_calls += 1;
        return @backingInt(node);
    }
    fn textOf(_: ?*anyopaque, node: widgets.TreeNode) []const u8 {
        text_of_calls += 1;
        return nameOf(node);
    }
    fn loadState(_: ?*anyopaque, node: widgets.TreeNode) widgets.LoadState {
        return if (node == B and loading_b) .loading else .loaded;
    }
    fn nameOf(node: widgets.TreeNode) []const u8 {
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
    fn model(version: u64) widgets.TreeModel {
        return .{
            .child_count = childCount,
            .child_at = childAt,
            .has_children = hasChildren,
            .key_of = keyOf,
            .text_of = textOf,
            .load_state = loadState,
            .version = version,
        };
    }
    fn opts(mode: widgets.SelectionMode) widgets.TreeOptions {
        return .{ .mode = mode };
    }
};

test "AC-W-TREE-002 展平缓存增量更新与回调计数" {
    T1.resetCounts();
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    c.correct();
    try std.testing.expectEqual(@as(usize, 3), c.rowsSlice().len);
    try std.testing.expectEqual(@as(widgets.TreeNode, T1.A), c.rowsSlice()[0].node);
    try std.testing.expectEqual(@as(widgets.TreeNode, T1.B), c.rowsSlice()[1].node);
    try std.testing.expectEqual(@as(widgets.TreeNode, T1.C), c.rowsSlice()[2].node);
    try std.testing.expectEqual(@as(usize, 1), T1.child_count_calls);
    try std.testing.expect(T1.child_at_calls == 3);

    // 展开 A：只调用 A 的 child_count。
    T1.resetCounts();
    const u = c.toggle(0);
    try std.testing.expectEqual(@as(usize, 6), c.rowsSlice().len);
    try std.testing.expectEqual(@as(usize, 1), T1.child_count_calls);
    try std.testing.expectEqual(@as(usize, 3), T1.child_at_calls);
    try std.testing.expectEqual(@as(usize, 1), u.toggled.len);
    try std.testing.expect(u.toggled[0].expanded);
    try std.testing.expectEqual(@as(?usize, null), c.rowsSlice()[0].parent);
    try std.testing.expectEqual(@as(?usize, 0), c.rowsSlice()[1].parent);
    try std.testing.expectEqual(@as(?usize, 0), c.rowsSlice()[3].parent);
    try std.testing.expectEqual(@as(?usize, null), c.rowsSlice()[4].parent);

    // 焦点与锚点随插入平移。
    c.focus = c.refAt(3);
    c.anchor = c.refAt(1);
    T1.resetCounts();
    _ = c.toggle(2);
    try std.testing.expectEqual(@as(usize, 8), c.rowsSlice().len);
    try std.testing.expectEqual(@as(usize, 1), T1.child_count_calls);
    try std.testing.expectEqual(@as(usize, 2), T1.child_at_calls);
    try std.testing.expectEqual(@as(?usize, 5), c.focus.?.index);
    try std.testing.expectEqual(@as(?usize, 1), c.anchor.?.index);
    try std.testing.expectEqual(@as(?usize, 5), c.indexOfKey(@backingInt(T1.A3)));
    const full = [_]widgets.TreeNode{ T1.A, T1.A1, T1.A2, T1.A2a, T1.A2b, T1.A3, T1.B, T1.C };
    for (full, 0..) |node, i| try std.testing.expectEqual(node, c.rowsSlice()[i].node);
    try std.testing.expectEqual(@as(?usize, 2), c.rowsSlice()[3].parent);
    try std.testing.expectEqual(@as(?usize, 0), c.rowsSlice()[5].parent);

    // 折叠 A 后 A2 仍在展开集合中，再展开恢复后代。
    T1.resetCounts();
    _ = c.toggle(0);
    try std.testing.expectEqual(@as(usize, 3), c.rowsSlice().len);
    try std.testing.expect(c.expanded().contains(@backingInt(T1.A2)));
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    _ = c.toggle(0);
    try std.testing.expectEqual(@as(usize, 8), c.rowsSlice().len);
    try std.testing.expectEqual(@as(?usize, 5), c.indexOfKey(@backingInt(T1.A3)));
}

test "AC-W-TREE-003 方向键展开/折叠、移动到子项与父项" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    c.correct();
    c.focus = c.refAt(0);
    var u = c.keyDown(.right, .{}, false, 0);
    try std.testing.expectEqual(@as(usize, 1), u.toggled.len);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    try std.testing.expectEqual(@as(usize, 0), c.selection().len());
    u = c.keyDown(.right, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 1), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A1)});
    try std.testing.expectEqual(@as(?usize, 1), c.anchor.?.index);
    // 叶子 → 无变化。
    _ = c.keyDown(.right, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 1), c.focus.?.index);
    // ← 移到父节点并选中。
    _ = c.keyDown(.left, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A)});
    // 再 ← 折叠 A。
    u = c.keyDown(.left, .{}, false, 0);
    try std.testing.expectEqual(@as(usize, 1), u.toggled.len);
    try std.testing.expectEqual(@as(usize, 3), c.rowsSlice().len);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    _ = c.keyDown(.left, .{}, false, 0);
    try std.testing.expectEqual(@as(usize, 3), c.rowsSlice().len);
    // ↓ 到 B，展开后移动到 B1。
    _ = c.keyDown(.down, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 1), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.B)});
    _ = c.keyDown(.right, .{}, false, 0);
    _ = c.keyDown(.right, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 2), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.B1)});
    _ = c.keyDown(.left, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 1), c.focus.?.index);

    // Ctrl+→ / Alt+→ / Ctrl+PageDown 不处理。
    const before = c.focus.?.index;
    try std.testing.expect(!c.keyDown(.right, .{ .ctrl = true }, false, 0).consumed);
    try std.testing.expect(!c.keyDown(.right, .{ .alt = true }, false, 0).consumed);
    try std.testing.expect(!c.keyDown(.page_down, .{ .ctrl = true }, false, 0).consumed);
    try std.testing.expectEqual(before, c.focus.?.index);
}

test "AC-W-TREE-004 星号展开全部、加减号与 Enter" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    c.correct();
    c.focus = c.refAt(0);
    const u = c.expandAllFrom(0);
    try std.testing.expectEqual(@as(usize, 8), c.rowsSlice().len);
    try std.testing.expectEqual(@as(usize, 2), u.toggled.len);
    try std.testing.expectEqual(@as(widgets.TreeNode, T1.A), u.toggled[0].node);
    try std.testing.expectEqual(@as(widgets.TreeNode, T1.A2), u.toggled[1].node);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    try std.testing.expectEqual(@as(usize, 0), c.selection().len());

    // A2 折叠后 + 展开、- 折叠。
    _ = c.toggle(2);
    try std.testing.expectEqual(@as(usize, 6), c.rowsSlice().len);
    c.focus = c.refAt(2);
    var k = c.keyDown(.np_add, .{}, false, 0);
    try std.testing.expectEqual(@as(usize, 8), c.rowsSlice().len);
    try std.testing.expectEqual(@as(usize, 1), k.toggled.len);
    try std.testing.expectEqual(@as(usize, 0), c.keyDown(.np_add, .{}, false, 0).toggled.len);
    k = c.keyDown(.np_sub, .{}, false, 0);
    try std.testing.expectEqual(@as(usize, 1), k.toggled.len);
    try std.testing.expectEqual(@as(usize, 0), c.keyDown(.np_sub, .{}, false, 0).toggled.len);

    // 叶子上的 + / - 无作用。
    c.focus = c.refAt(1);
    try std.testing.expectEqual(@as(usize, 0), c.keyDown(.np_add, .{}, false, 0).toggled.len);
    try std.testing.expectEqual(@as(usize, 0), c.keyDown(.np_sub, .{}, false, 0).toggled.len);

    // Enter：有子项切换展开不激活；叶子激活。
    c.focus = c.refAt(2);
    k = c.keyDown(.enter, .{}, false, 0);
    try std.testing.expectEqual(@as(?widgets.TreeNode, null), k.activated);
    try std.testing.expectEqual(@as(usize, 1), k.toggled.len);
    c.focus = c.refAt(1);
    try std.testing.expectEqual(@as(?widgets.TreeNode, T1.A1), c.keyDown(.enter, .{}, false, 0).activated);
    try std.testing.expectEqual(@as(?widgets.TreeNode, null), c.keyDown(.enter, .{}, true, 0).activated);

    // activate_parents：Enter 在父节点同时激活。
    var ap = widgets.TreeController.init(std.testing.allocator, T1.model(0), .{ .mode = .multi, .activate_parents = true });
    defer ap.deinit();
    ap.correct();
    ap.focus = ap.refAt(0);
    _ = ap.keyDown(.right, .{}, false, 0);
    const apk = ap.keyDown(.enter, .{}, false, 0);
    try std.testing.expectEqual(@as(?widgets.TreeNode, T1.A), apk.activated);
    try std.testing.expectEqual(@as(usize, 1), apk.toggled.len);
}

test "AC-W-TREE-005 箭头位点击、双击与可见行区间" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    try c.expandedPtr().set(@backingInt(T1.A), true, null);
    try c.expandedPtr().set(@backingInt(T1.A2), true, null);
    c.correct();
    try c.selectionPtr().add(@backingInt(T1.A1));
    c.focus = c.refAt(1);
    c.anchor = c.refAt(1);

    // 点击 A2 的箭头位（depth 1，x ∈ [24,40)）。
    var u = c.pointerPressArrow(2, 30).?;
    try std.testing.expectEqual(@as(usize, 1), u.toggled.len);
    try std.testing.expectEqual(@as(usize, 6), c.rowsSlice().len);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A1)});
    try std.testing.expectEqual(@as(?usize, 1), c.focus.?.index);
    try std.testing.expect(!u.selection_changed);
    _ = c.pointerPressArrow(2, 30);

    // 叶子 A3 的箭头位按行点击处理。
    try std.testing.expect(c.pointerPressArrow(5, 30) == null);
    _ = c.pointerPress(5, .left, .{});
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A3)});

    // 双击：有子项切换；叶子激活；Ctrl+双击无效果。
    u = c.doubleClick(2, .{});
    try std.testing.expectEqual(@as(?widgets.TreeNode, null), u.activated);
    try std.testing.expectEqual(@as(usize, 1), u.toggled.len);
    _ = c.doubleClick(2, .{});
    u = c.doubleClick(1, .{});
    try std.testing.expectEqual(@as(?widgets.TreeNode, T1.A1), u.activated);
    const rows_before = c.rowsSlice().len;
    try std.testing.expectEqual(@as(?widgets.TreeNode, null), c.doubleClick(2, .{ .ctrl = true }).activated);
    try std.testing.expectEqual(rows_before, c.rowsSlice().len);

    // 可见行区间包含 A2 的后代。
    c.selectionPtr().clear();
    _ = c.pointerPress(1, .left, .{});
    _ = c.pointerPress(5, .left, .{ .shift = true });
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.A1), @backingInt(T1.A2), @backingInt(T1.A2a), @backingInt(T1.A2b), @backingInt(T1.A3) });
    // 折叠 A2 后区间只含可见行，并替换隐藏选择。
    _ = c.toggle(2);
    _ = c.pointerPress(3, .left, .{ .shift = true });
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.A1), @backingInt(T1.A2), @backingInt(T1.A3) });

    // 右键与上下文菜单。
    _ = c.pointerPress(4, .right, .{});
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.B)});
    try std.testing.expectEqual(@as(?widgets.TreeNode, T1.B), c.contextMenu(4, .{}, false).context_menu.?.node);
    try std.testing.expectEqual(@as(?widgets.TreeNode, null), c.contextMenu(null, .{}, false).context_menu.?.node);
}

test "AC-W-TREE-006 折叠保留隐藏选择、焦点移到祖先" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    try c.expandedPtr().set(@backingInt(T1.A), true, null);
    try c.expandedPtr().set(@backingInt(T1.A2), true, null);
    c.correct();
    try c.selectionPtr().add(@backingInt(T1.A2b));
    try c.selectionPtr().add(@backingInt(T1.A3));
    c.focus = c.refAt(4);
    c.anchor = c.refAt(4);
    try std.testing.expectEqual(@as(usize, 2), c.selectedVisibleCount());

    const u = c.toggle(0);
    try std.testing.expectEqual(@as(usize, 3), c.rowsSlice().len);
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.A2b), @backingInt(T1.A3) });
    try std.testing.expect(!u.selection_changed);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    try std.testing.expectEqual(@as(?usize, 0), c.anchor.?.index);
    try std.testing.expectEqual(@as(usize, 0), c.selectedVisibleCount());

    // Shift+点击 C：替换并清除隐藏项。
    _ = c.pointerPress(2, .left, .{ .shift = true });
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.A), @backingInt(T1.B), @backingInt(T1.C) });
    try std.testing.expectEqual(@as(?usize, 2), c.focus.?.index);
    try std.testing.expectEqual(@as(?usize, 0), c.anchor.?.index);

    // Ctrl+Shift+点击 C：并入区间，隐藏项保留。
    c.selectionPtr().clear();
    try c.selectionPtr().add(@backingInt(T1.A2b));
    try c.selectionPtr().add(@backingInt(T1.A3));
    c.anchor = c.refAt(0);
    _ = c.pointerPress(2, .left, .{ .ctrl = true, .shift = true });
    try std.testing.expectEqual(@as(usize, 5), c.selection().len());
    // Ctrl+点击 B 保留隐藏项。
    c.selectionPtr().clear();
    try c.selectionPtr().add(@backingInt(T1.A2b));
    try c.selectionPtr().add(@backingInt(T1.A3));
    c.anchor = c.refAt(0);
    _ = c.pointerPress(1, .left, .{ .ctrl = true });
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.A2b), @backingInt(T1.A3), @backingInt(T1.B) });
    // Ctrl+A 只添加可见行。
    _ = c.keyDown(.a, .{ .ctrl = true }, false, 0);
    try std.testing.expectEqual(@as(usize, 5), c.selection().len());
    // 普通点击清除隐藏项。
    _ = c.pointerPress(1, .left, .{});
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.B)});

    // 重新展开：隐藏项恢复显示。
    c.selectionPtr().clear();
    try c.selectionPtr().add(@backingInt(T1.A2b));
    try c.selectionPtr().add(@backingInt(T1.A3));
    _ = c.toggle(0);
    try std.testing.expectEqual(@as(usize, 8), c.rowsSlice().len);
    try std.testing.expectEqual(@as(usize, 2), c.selectedVisibleCount());
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.A2b), @backingInt(T1.A3) });
}

test "AC-W-TREE-007 惰性加载占位行" {
    T1.loading_b = true;
    T1.b_child_count = 1;
    defer T1.loading_b = false;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    c.correct();
    const u = c.pointerPressArrow(1, 10).?;
    try std.testing.expectEqual(@as(usize, 1), u.toggled.len);
    try std.testing.expectEqual(@as(usize, 4), c.rowsSlice().len);
    try std.testing.expect(c.rowsSlice()[2].placeholder);
    _ = c.pointerPress(2, .left, .{});
    try std.testing.expectEqual(@as(usize, 0), c.selection().len());
    // ↓ 跳过占位行。
    c.focus = c.refAt(1);
    _ = c.keyDown(.down, .{}, false, 0);
    try std.testing.expectEqual(@as(?usize, 3), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.C)});
    // Shift 区间跳过占位行。
    c.focus = c.refAt(1);
    c.anchor = c.refAt(1);
    _ = c.keyDown(.down, .{ .shift = true }, false, 0);
    try expectSel(c.selectionPtr(), &.{ @backingInt(T1.B), @backingInt(T1.C) });
    // Ctrl+A 不选占位行。
    c.selectionPtr().clear();
    _ = c.keyDown(.a, .{ .ctrl = true }, false, 0);
    try std.testing.expectEqual(@as(usize, 3), c.selection().len());
    // 应用提供子项并递增 version。
    T1.loading_b = false;
    c.model.version = 1;
    c.correct();
    try std.testing.expectEqual(@as(usize, 4), c.rowsSlice().len);
    try std.testing.expect(!c.rowsSlice()[2].placeholder);
    try std.testing.expectEqual(@as(widgets.TreeNode, T1.B1), c.rowsSlice()[2].node);
    try std.testing.expect(c.expanded().contains(@backingInt(T1.B)));

    // has_children 为真但 child_count = 0：不插入行，箭头位保留。
    T1.b_child_count = 0;
    var empty = widgets.TreeController.init(std.testing.allocator, T1.model(1), T1.opts(.multi));
    defer empty.deinit();
    empty.correct();
    _ = empty.pointerPressArrow(1, 10);
    try std.testing.expectEqual(@as(usize, 3), empty.rowsSlice().len);
    try std.testing.expect(empty.rowsSlice()[1].expanded);
    try std.testing.expect(empty.rowsSlice()[1].has_children);
    T1.b_child_count = 1;
}

test "AC-W-TREE-012 前缀搜索只在可见行" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    try c.expandedPtr().set(@backingInt(T1.A), true, null);
    try c.expandedPtr().set(@backingInt(T1.A2), true, null);
    c.correct();
    c.focus = c.refAt(0);
    _ = c.charInput('a', .{}, 0);
    try std.testing.expectEqual(@as(?usize, 1), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A1)});
    _ = c.charInput('2', .{}, 400);
    try std.testing.expectEqual(@as(?usize, 2), c.focus.?.index);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A2)});

    // 折叠 A 后只在可见行搜索。
    _ = c.toggle(0);
    _ = c.charInput('a', .{}, 2000);
    try std.testing.expectEqual(@as(?usize, 0), c.focus.?.index);
    // Ctrl+A 只选可见行。
    c.selectionPtr().clear();
    _ = c.keyDown(.a, .{ .ctrl = true }, false, 0);
    try std.testing.expectEqual(@as(usize, 3), c.selection().len());
    try std.testing.expect(c.selection().contains(@backingInt(T1.B)));
}

test "AC-W-TREE-014 箭头位几何、深度上限与叶子展开" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    c.correct();
    const zone2 = c.arrowZoneX(2);
    try std.testing.expectEqual(@as(f32, 40), zone2.x);
    try std.testing.expectEqual(@as(f32, 56), zone2.y);
    try std.testing.expectEqual(@as(f32, 58), c.contentX(2));
    const zone1 = c.arrowZoneX(1);
    try std.testing.expectEqual(@as(f32, 24), zone1.x);
    try std.testing.expectEqual(@as(f32, 40), zone1.y);
    try std.testing.expectEqual(@as(f32, 42), c.contentX(1));

    // 叶子展开无效果且不入集合。
    _ = c.pointerPressArrow(0, 10); // A 展开
    try std.testing.expect(c.expanded().contains(@backingInt(T1.A)));
    const leaf_index = c.indexOfKey(@backingInt(T1.A1)).?;
    _ = c.pointerPressArrow(leaf_index, 26);
    try std.testing.expect(!c.expanded().contains(@backingInt(T1.A1)));
}

test "AC-W-TREE-014 深度上限与环不死循环" {
    const Chain = struct {
        var child_calls: usize = 0;
        fn childCount(_: ?*anyopaque, node: widgets.TreeNode) usize {
            _ = node;
            child_calls += 1;
            return 1;
        }
        fn childAt(_: ?*anyopaque, node: widgets.TreeNode, _: usize) widgets.TreeNode {
            return @fromBackingInt(@backingInt(node) + 1);
        }
        fn hasChildren(_: ?*anyopaque, _: widgets.TreeNode) bool {
            return true;
        }
        fn keyOf(_: ?*anyopaque, node: widgets.TreeNode) widgets.ItemKey {
            return @backingInt(node);
        }
        fn model() widgets.TreeModel {
            return .{ .child_count = childCount, .child_at = childAt, .has_children = hasChildren, .key_of = keyOf };
        }
    };
    Chain.child_calls = 0;
    var c = widgets.TreeController.init(std.testing.allocator, Chain.model(), .{ .mode = .multi, .initially_expanded_depth = 255 });
    defer c.deinit();
    c.correct();
    try std.testing.expect(c.rowsSlice().len <= 257);
    try std.testing.expect(Chain.child_calls <= 258);

    // 自环：childAt 返回自身，深度上限终止。
    const Cycle = struct {
        fn childCount(_: ?*anyopaque, _: widgets.TreeNode) usize {
            return 1;
        }
        fn childAt(_: ?*anyopaque, node: widgets.TreeNode, _: usize) widgets.TreeNode {
            return node;
        }
        fn hasChildren(_: ?*anyopaque, _: widgets.TreeNode) bool {
            return true;
        }
        fn keyOf(_: ?*anyopaque, _: widgets.TreeNode) widgets.ItemKey {
            return 1;
        }
    };
    var cy = widgets.TreeController.init(std.testing.allocator, .{
        .child_count = Cycle.childCount,
        .child_at = Cycle.childAt,
        .has_children = Cycle.hasChildren,
        .key_of = Cycle.keyOf,
    }, .{ .mode = .multi, .initially_expanded_depth = 255 });
    defer cy.deinit();
    cy.correct();
    try std.testing.expect(cy.rowsSlice().len <= 257);
}

// ---------------------------------------------------------------------------
// M5：表格
// ---------------------------------------------------------------------------

const G1 = struct {
    const columns = [_]widgets.TableColumn{
        .{ .title = "名称", .width = .{ .grow = 1 }, .min = 60, .sortable = true },
        .{ .title = "大小", .width = .{ .fixed = 80 }, .min = 32, .h_align = .right, .font = .mono, .sortable = true },
        .{ .title = "类型", .width = .{ .fixed = 100 }, .min = 32, .sortable = true },
        .{ .title = "修改日期", .width = .{ .fixed = 140 }, .min = 32 },
    };
    fn opts() widgets.TableOptions {
        return .{ .mode = .multi };
    }
    fn make(allocator: std.mem.Allocator) !widgets.TableController {
        return widgets.TableController.init(allocator, &columns, 10, opts());
    }
    fn layout(c: *widgets.TableController, vw: f32) void {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        c.layoutColumns(arena.allocator(), vw, 1.0, 7);
    }
};

test "AC-W-TABLE-002 列宽求解与最小宽度" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    try std.testing.expectEqual(@as(f32, 480), c.widths[0]);
    try std.testing.expectEqual(@as(f32, 80), c.widths[1]);
    try std.testing.expectEqual(@as(f32, 100), c.widths[2]);
    try std.testing.expectEqual(@as(f32, 140), c.widths[3]);
    try std.testing.expectEqual(@as(f32, 800), c.contentWidth());

    c.user_widths[1] = 120;
    G1.layout(&c, 800);
    try std.testing.expectEqual(@as(f32, 440), c.widths[0]);
    try std.testing.expectEqual(@as(f32, 120), c.widths[1]);
    G1.layout(&c, 600);
    try std.testing.expectEqual(@as(f32, 240), c.widths[0]);
    G1.layout(&c, 300);
    try std.testing.expectEqual(@as(f32, 60), c.widths[0]);
    try std.testing.expectEqual(@as(f32, 420), c.contentWidth());

    // auto_header：4 字符 * 7 + 2*8 + 可排序 (4+16) = 64。
    var auto_cols = [_]widgets.TableColumn{
        .{ .title = "修改日期", .width = .auto_header, .sortable = true },
        .{ .title = "其他", .width = .auto_header },
    };
    var ac = try widgets.TableController.init(std.testing.allocator, &auto_cols, 0, .{ .mode = .multi });
    defer ac.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    ac.layoutColumns(arena.allocator(), 800, 1.0, 7);
    try std.testing.expectEqual(@as(f32, 64), ac.widths[0]);
    try std.testing.expectEqual(@as(f32, 32), ac.widths[1]);

    // 隐藏列不参与求解。
    var hidden_cols = [_]widgets.TableColumn{
        .{ .title = "A", .width = .{ .grow = 1 } },
        .{ .title = "B", .width = .{ .fixed = 80 } },
        .{ .title = "C", .width = .{ .fixed = 100 }, .hidden = true },
    };
    var hc = try widgets.TableController.init(std.testing.allocator, &hidden_cols, 10, .{ .mode = .multi });
    defer hc.deinit();
    hc.layoutColumns(arena.allocator(), 600, 1.0, 7);
    try std.testing.expectEqual(@as(usize, 2), hc.displayCount());
    try std.testing.expectEqual(@as(f32, 0), hc.widths[2]);
    try std.testing.expectEqual(@as(f32, 520), hc.widths[0]);
}

test "AC-W-TABLE-003 列虚拟化与前导占位" {
    var cols: [20]widgets.TableColumn = undefined;
    var ci: usize = 0;
    while (ci < cols.len) : (ci += 1) cols[ci] = .{ .title = "x", .width = .{ .fixed = 100 } };
    var c = try widgets.TableController.init(std.testing.allocator, &cols, 100000, .{ .mode = .multi });
    defer c.deinit();
    G1.layout(&c, 800);
    try std.testing.expectEqual(@as(f32, 100), c.widths[0]);
    try std.testing.expectEqual(@as(f32, 2000), c.contentWidth());
    var s = c.columnSpan(0);
    try std.testing.expectEqual(@as(usize, 0), s.first_visible);
    try std.testing.expectEqual(@as(usize, 7), s.last_visible);
    try std.testing.expectEqual(@as(usize, 0), s.first_created);
    try std.testing.expectEqual(@as(usize, 8), s.last_created);
    try std.testing.expectEqual(@as(usize, 9), s.created);
    try std.testing.expectEqual(@as(f32, 0), s.leader_width);
    s = c.columnSpan(450);
    try std.testing.expectEqual(@as(usize, 4), s.first_visible);
    try std.testing.expectEqual(@as(usize, 12), s.last_visible);
    try std.testing.expectEqual(@as(usize, 3), s.first_created);
    try std.testing.expectEqual(@as(usize, 13), s.last_created);
    try std.testing.expectEqual(@as(f32, 300), s.leader_width);
    try std.testing.expectEqual(@as(usize, 11), s.created);
    try std.testing.expectEqual(@as(f32, 1200), c.maxOffsetX());
    s = c.columnSpan(1200);
    try std.testing.expectEqual(@as(usize, 12), s.first_visible);
    try std.testing.expectEqual(@as(usize, 19), s.last_visible);
    try std.testing.expectEqual(@as(usize, 11), s.first_created);
    try std.testing.expectEqual(@as(usize, 19), s.last_created);
    try std.testing.expectEqual(@as(f32, 1100), s.leader_width);
    try std.testing.expectEqual(@as(usize, 9), s.created);
}

test "AC-W-TABLE-004 表头排序与释放时生效" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    // 按下不排序；释放才生效。
    const hit = c.headerPress(100);
    try std.testing.expect(hit == .cell);
    try std.testing.expectEqual(@as(u16, 0), hit.cell.column);
    try std.testing.expectEqual(@as(?u16, null), c.sort().column);
    c.headerRelease(100);
    try std.testing.expectEqual(@as(?u16, 0), c.update.sort_changed.?.column);
    try std.testing.expectEqual(widgets.SortDir.asc, c.update.sort_changed.?.dir.?);
    try std.testing.expectEqual(@as(?u16, 0), c.sort().column);
    _ = c.headerPress(100);
    c.headerRelease(100);
    try std.testing.expectEqual(widgets.SortDir.desc, c.sort().dir);
    _ = c.headerPress(100);
    c.headerRelease(100);
    try std.testing.expectEqual(widgets.SortDir.asc, c.sort().dir);
    // 点击其他排序列。
    _ = c.headerPress(600);
    c.headerRelease(600);
    try std.testing.expectEqual(@as(?u16, 2), c.sort().column);
    try std.testing.expectEqual(widgets.SortDir.asc, c.sort().dir);
    // 不可排序列。
    _ = c.headerPress(700);
    c.headerRelease(700);
    try std.testing.expectEqual(@as(?u16, 2), c.sort().column);
    // 边界命中带不排序。
    const bhit = c.headerPress(477);
    try std.testing.expect(bhit == .boundary);
    c.cancelResize();
    try std.testing.expectEqual(@as(?u16, 2), c.sort().column);

    // allow_unsorted：第三次点击取消排序。
    var c2 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .allow_unsorted = true });
    defer c2.deinit();
    G1.layout(&c2, 800);
    _ = c2.headerPress(100);
    c2.headerRelease(100);
    _ = c2.headerPress(100);
    c2.headerRelease(100);
    _ = c2.headerPress(100);
    c2.headerRelease(100);
    try std.testing.expectEqual(@as(?u16, null), c2.sort().column);
    try std.testing.expectEqual(@as(?widgets.SortDir, null), c2.update.sort_changed.?.dir);

    // 应用持有排序指针。
    var app_sort = widgets.TableSort{ .column = null, .dir = .asc };
    var c3 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .sort = &app_sort });
    defer c3.deinit();
    G1.layout(&c3, 800);
    _ = c3.headerPress(100);
    c3.headerRelease(100);
    try std.testing.expectEqual(@as(?u16, 0), app_sort.column);
    app_sort = .{ .column = 1, .dir = .desc };
    c3.correct();
    try std.testing.expectEqual(@as(?u16, 1), c3.sort().column);
    try std.testing.expectEqual(widgets.SortDir.desc, c3.sort().dir);
}

test "AC-W-TABLE-005 表头边界与列宽拖动" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    const b = c.headerPress(557);
    try std.testing.expect(b == .boundary);
    try std.testing.expectEqual(@as(u16, 1), b.boundary.column);
    try std.testing.expectEqual(@as(u16, 1), c.update.resizing.?);
    c.headerDrag(597);
    try std.testing.expectEqual(@as(f32, 120), c.widths[1]);
    G1.layout(&c, 800);
    try std.testing.expectEqual(@as(f32, 440), c.widths[0]);
    c.headerDrag(300);
    try std.testing.expectEqual(@as(f32, 32), c.widths[1]);
    c.headerDrag(5000);
    try std.testing.expectEqual(@as(f32, 4523), c.widths[1]);
    G1.layout(&c, 800);
    try std.testing.expect(c.contentWidth() > 800);
    // Esc 恢复。
    c.cancelResize();
    try std.testing.expectEqual(@as(f32, 80), c.widths[1]);

    // resizable = false 的边界不被命中。
    var cols = [_]widgets.TableColumn{
        .{ .title = "A", .width = .{ .fixed = 100 }, .resizable = false },
        .{ .title = "B", .width = .{ .fixed = 100 } },
    };
    var c2 = try widgets.TableController.init(std.testing.allocator, &cols, 0, .{ .mode = .multi });
    defer c2.deinit();
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    c2.layoutColumns(arena2.allocator(), 400, 1.0, 7);
    const nh = c2.headerPress(98);
    try std.testing.expect(nh == .cell);
}

test "table 列重排与无操作判定" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    // 显示序 [0,1,2,3]；移动 1 到边界 3 → [0,2,1,3]。
    c.moveColumn(1, 3);
    try std.testing.expect(c.update.columns_reordered);
    try std.testing.expectEqual(@as(u16, 0), c.order[0]);
    try std.testing.expectEqual(@as(u16, 2), c.order[1]);
    try std.testing.expectEqual(@as(u16, 1), c.order[2]);
    try std.testing.expectEqual(@as(u16, 3), c.order[3]);
    // ins ∈ {p, p+1} 为无操作。
    var c2 = try G1.make(std.testing.allocator);
    defer c2.deinit();
    G1.layout(&c2, 800);
    c2.moveColumn(1, 1);
    try std.testing.expect(!c2.update.columns_reordered);
    c2.moveColumn(1, 2);
    try std.testing.expect(!c2.update.columns_reordered);
    c2.moveColumn(1, 4);
    try std.testing.expect(c2.update.columns_reordered);
    try std.testing.expectEqual(@as(u16, 1), c2.order[3]);
}

test "AC-W-TABLE-013 空表、隐藏列与表头仍可用" {
    var c = try widgets.TableController.init(std.testing.allocator, &G1.columns, 0, G1.opts());
    defer c.deinit();
    G1.layout(&c, 800);
    c.correct();
    try std.testing.expectEqual(@as(usize, 0), c.count);
    try std.testing.expect(!c.rowVisibleRange().has_rows);
    _ = c.headerPress(100);
    c.headerRelease(100);
    try std.testing.expectEqual(@as(?u16, 0), c.sort().column);
    c.setColumnHidden(2, true);
    try std.testing.expectEqual(@as(usize, 3), c.displayCount());
    G1.layout(&c, 800);
    try std.testing.expectEqual(@as(f32, 0), c.widths[2]);
    c.setColumnHidden(2, false);
    try std.testing.expectEqual(@as(usize, 4), c.displayCount());
}

test "AC-W-TABLE-008 行选择沿用列表选择模型" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    c.correct();
    const u = c.pointerPress(3, .left, .{});
    try std.testing.expect(u.selection_changed);
    try expectSel(c.selectionPtr(), &.{3});
    _ = c.pointerPress(5, .left, .{ .shift = true });
    try expectSel(c.selectionPtr(), &.{ 3, 4, 5 });
    _ = c.pointerPress(4, .left, .{ .ctrl = true });
    try expectSel(c.selectionPtr(), &.{ 3, 5 });
    _ = c.keyDown(.a, .{ .ctrl = true }, false, 0);
    try std.testing.expectEqual(@as(usize, 10), c.selection().len());
    _ = c.pointerRelease(2, true, 2, .{});
}

test "AC-PLAT-008 validatePlacement 工作区校验与 DPI 换算" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const base = platform.Monitor{ .bounds = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 }, .work_area = .{ .x = 0, .y = 0, .w = 1920, .h = 1040 }, .dpi = 96, .scale = 1 };
    platform.Headless.setMonitors(&.{base});
    const a = platform.validatePlacement(.{ .normal_rect = .{ .x = 100, .y = 80, .w = 900, .h = 600 }, .state = .normal, .dpi = 96 });
    try std.testing.expectEqual(platform.RectI{ .x = 100, .y = 80, .w = 900, .h = 600 }, a.normal_rect);
    try std.testing.expectEqual(@as(u32, 96), a.dpi);

    const b = platform.validatePlacement(.{ .normal_rect = .{ .x = 1700, .y = 80, .w = 900, .h = 600 }, .state = .normal, .dpi = 96 });
    // 交集 220×600 = 132000 / 540000 = 24.4% < 25% → 丢弃位置。
    try std.testing.expect(b.normal_rect.x != 1700);
    try std.testing.expectEqual(@as(i32, 900), b.normal_rect.w);
    try std.testing.expectEqual(@as(i32, 600), b.normal_rect.h);

    const c = platform.validatePlacement(.{ .normal_rect = .{ .x = 3000, .y = 2000, .w = 900, .h = 600 }, .state = .normal, .dpi = 96 });
    try std.testing.expect(c.normal_rect.x != 3000);
    try std.testing.expect(c.normal_rect.w <= 1920 and c.normal_rect.h <= 1040);

    const d = platform.validatePlacement(.{ .normal_rect = .{ .x = 100, .y = 80, .w = 900, .h = 600 }, .state = .maximized, .dpi = 96 });
    try std.testing.expectEqual(platform.WindowState.maximized, d.state);
    try std.testing.expectEqual(platform.RectI{ .x = 100, .y = 80, .w = 900, .h = 600 }, d.normal_rect);

    const hi = platform.Monitor{ .bounds = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 }, .work_area = .{ .x = 0, .y = 0, .w = 1920, .h = 1040 }, .dpi = 144, .scale = 1.5 };
    platform.Headless.setMonitors(&.{hi});
    const e = platform.validatePlacement(.{ .normal_rect = .{ .x = 100, .y = 80, .w = 800, .h = 600 }, .state = .normal, .dpi = 96 });
    try std.testing.expectEqual(@as(i32, 1200), e.normal_rect.w);
    try std.testing.expectEqual(@as(i32, 900), e.normal_rect.h);
    try std.testing.expectEqual(@as(u32, 144), e.dpi);
    try std.testing.expectEqual(@as(i32, 100), e.normal_rect.x);
    platform.Headless.setMonitors(&.{base});
}

// ---------------------------------------------------------------------------
// M5：应用标识、命令、字符串与命令行
// ---------------------------------------------------------------------------

test "AC-APP-001 AppId 校验与 init 注册标准编辑命令" {
    try nano.app.validateAppId(.{ .vendor = "Acme", .name = "Tool" });
    const bad = [_]nano.app.AppId{
        .{ .vendor = "", .name = "Tool" },
        .{ .vendor = "Acme", .name = "" },
        .{ .vendor = "Ac/me", .name = "Tool" },
        .{ .vendor = "Ac:me", .name = "Tool" },
        .{ .vendor = "Acme.", .name = "Tool" },
        .{ .vendor = "Acme", .name = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" },
        .{ .vendor = "CON", .name = "x" },
        .{ .vendor = "acme", .name = "nul" },
    };
    for (bad) |id| try std.testing.expectError(error.InvalidAppId, nano.app.validateAppId(id));
    // 非法标识在 init 创建任何窗口之前失败。
    try std.testing.expectError(error.InvalidAppId, nano.app.App.init(std.testing.allocator, .{ .id = bad[0] }));

    var app = try nano.app.App.init(std.testing.allocator, .{ .id = .{ .vendor = "Acme", .name = "Tool" }, .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    try std.testing.expect(app.commands.find("edit.copy") != null);
    try std.testing.expect(app.commands.find("edit.undo") != null);
    try std.testing.expect(app.commands.find("edit.delete") != null);
    const copy = app.commands.get(app.commands.find("edit.copy").?).?;
    var chord_buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("Ctrl+C", app.commands.formatChord(&chord_buf, copy.shortcut.?));
}

test "AC-APP-015 命令注册、重复与非法标识" {
    var reg = nano.commands.Registry.init(std.testing.allocator);
    defer reg.deinit();
    const id = try reg.register(.{ .name = "file.save", .title = "保存(&S)" });
    try std.testing.expectError(error.DuplicateCommand, reg.register(.{ .name = "file.save", .title = "x" }));
    const invalid = [_][]const u8{ "File.Save", "a..b", "a b", "", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", ".a", "a." };
    for (invalid) |name| try std.testing.expectError(error.InvalidCommandId, reg.register(.{ .name = name, .title = "x" }));
    try std.testing.expectEqual(id, reg.find("file.save").?);
    try std.testing.expectEqualStrings("保存(&S)", reg.titleOf(id));
}

test "AC-APP-018 快捷键改绑冲突、steal 与非法和弦" {
    var reg = nano.commands.Registry.init(std.testing.allocator);
    defer reg.deinit();
    const save = try reg.register(.{ .name = "file.save", .title = "保存", .shortcut = .{ .key = .s, .mods = .{ .ctrl = true } } });
    const all = try reg.register(.{ .name = "file.save_all", .title = "全部保存", .shortcut = .{ .key = .s, .mods = .{ .ctrl = true, .shift = true } } });
    try std.testing.expectError(error.ShortcutConflict, reg.setShortcut(save, .{ .key = .s, .mods = .{ .ctrl = true, .shift = true } }, .reject));
    try reg.setShortcut(save, .{ .key = .s, .mods = .{ .ctrl = true, .shift = true } }, .steal);
    try std.testing.expect(reg.shortcutOf(all) == null);
    try std.testing.expect(reg.shortcutOf(save).?.mods.shift);
    try reg.setShortcut(save, null, .reject);
    try std.testing.expect(reg.shortcutOf(save) == null);
    const invalid_chords = [_]input.Chord{
        .{ .key = .shift },
        .{ .key = .ctrl, .mods = .{ .ctrl = true } },
        .{ .key = .a, .mods = .{ .shift = true } },
    };
    for (invalid_chords) |ch| try std.testing.expectError(error.InvalidShortcut, reg.setShortcut(save, ch, .reject));
    try reg.setShortcut(save, .{ .key = .f5 }, .reject);
    try reg.setShortcut(save, .{ .key = .a, .mods = .{ .ctrl = true } }, .reject);
    try reg.setShortcut(save, .{ .key = .f5, .mods = .{ .shift = true } }, .reject);
    reg.resetShortcuts();
    try std.testing.expect(reg.shortcutOf(save).?.key == .s);
    try std.testing.expect(reg.shortcutOf(all).?.mods.shift);
}

test "AC-APP-019 快捷键文本格式与固定格式往返" {
    var reg = nano.commands.Registry.init(std.testing.allocator);
    defer reg.deinit();
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Ctrl+Shift+S", reg.formatChord(&buf, .{ .key = .s, .mods = .{ .ctrl = true, .shift = true } }));
    try std.testing.expectEqualStrings("F5", reg.formatChord(&buf, .{ .key = .f5 }));
    try std.testing.expectEqualStrings("Del", reg.formatChord(&buf, .{ .key = .delete }));
    try std.testing.expectEqualStrings("Alt+Enter", reg.formatChord(&buf, .{ .key = .enter, .mods = .{ .alt = true } }));
    try std.testing.expectEqualStrings("Ctrl+Alt+Shift+Win+Left", reg.formatChord(&buf, .{ .key = .left, .mods = .{ .ctrl = true, .alt = true, .shift = true, .win = true } }));
    try std.testing.expectEqualStrings("Ctrl+PgDn", reg.formatChord(&buf, .{ .key = .page_down, .mods = .{ .ctrl = true } }));
    try std.testing.expectEqualStrings("Ctrl+1", reg.formatChord(&buf, .{ .key = .n1, .mods = .{ .ctrl = true } }));
    try std.testing.expectEqualStrings("Shift+Space", reg.formatChord(&buf, .{ .key = .space, .mods = .{ .shift = true } }));
    try std.testing.expectEqualStrings("Esc", reg.formatChord(&buf, .{ .key = .escape }));
    try std.testing.expectEqualStrings("Menu", reg.formatChord(&buf, .{ .key = .apps }));
    try std.testing.expectEqualStrings("F24", reg.formatChord(&buf, .{ .key = .f24 }));
    try std.testing.expectEqualStrings("Ctrl+F12", reg.formatChord(&buf, .{ .key = .f12, .mods = .{ .ctrl = true } }));

    const chord = try reg.chordFromInvariant("ctrl+shift+s");
    try std.testing.expectEqual(platform.VirtualKey.s, chord.key);
    try std.testing.expect(chord.mods.ctrl and chord.mods.shift);
    try std.testing.expectError(error.InvalidShortcut, reg.chordFromInvariant("Ctrl+"));
    try std.testing.expectError(error.InvalidShortcut, reg.chordFromInvariant("Foo"));
    try std.testing.expectError(error.InvalidShortcut, reg.chordFromInvariant(""));
    const all_chords = [_]input.Chord{
        .{ .key = .s, .mods = .{ .ctrl = true } },
        .{ .key = .f5 },
        .{ .key = .enter, .mods = .{ .alt = true } },
        .{ .key = .left, .mods = .{ .ctrl = true, .alt = true, .shift = true, .win = true } },
        .{ .key = .page_down, .mods = .{ .ctrl = true } },
        .{ .key = .n1, .mods = .{ .ctrl = true } },
        .{ .key = .space, .mods = .{ .shift = true } },
        .{ .key = .escape },
    };
    for (all_chords) |ch| {
        const chord_text = reg.formatChord(&buf, ch);
        const back = try reg.chordFromInvariant(chord_text);
        try std.testing.expectEqual(ch.key, back.key);
        try std.testing.expect(ch.mods.eql(back.mods));
    }
}

test "AC-APP-029 内建字符串表与语言选择" {
    const zh = nano.app.stringsForLocale("zh-CN");
    try std.testing.expectEqualStrings("确定", zh.ok);
    try std.testing.expectEqualStrings("取消", zh.cancel);
    try std.testing.expectEqualStrings("确定", nano.app.stringsForLocale("zh-Hans-CN").ok);
    try std.testing.expectEqualStrings("确定", nano.app.stringsForLocale("zh-SG").ok);
    try std.testing.expectEqualStrings("OK", nano.app.stringsForLocale("en-US").ok);
    try std.testing.expectEqualStrings("OK", nano.app.stringsForLocale("fr-FR").ok);
    try std.testing.expectEqualStrings("OK", nano.app.stringsForLocale("zh-TW").ok);
    try std.testing.expectEqualStrings("OK", nano.app.stringsForLocale("C").ok);
    const tables = [_]*const nano.app.Strings{ &nano.app.Strings.zh_cn, &nano.app.Strings.en };
    for (tables) |t| {
        try std.testing.expect(t.ok.len > 0 and t.cancel.len > 0 and t.clear.len > 0);
        try std.testing.expect(t.key_names.ctrl.len > 0 and t.key_names.function_prefix.len > 0);
    }
}

test "AC-APP-030 启动参数拆分" {
    var args = try nano.app.parseCommandLine(std.testing.allocator, "tool.exe \"C:\\a b\\c.txt\" --flag 文件");
    defer args.deinit();
    const got = args.slice();
    try std.testing.expectEqual(@as(usize, 4), got.len);
    try std.testing.expectEqualStrings("tool.exe", got[0]);
    try std.testing.expectEqualStrings("C:\\a b\\c.txt", got[1]);
    try std.testing.expectEqualStrings("--flag", got[2]);
    try std.testing.expectEqualStrings("文件", got[3]);
}

// ---------------------------------------------------------------------------
// M5：设置持久化
// ---------------------------------------------------------------------------

fn settingsTestPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const dir = try std.fmt.allocPrint(allocator, "/tmp/opencode/nano_gui_settings_{s}", .{name});
    defer allocator.free(dir);
    std.Io.Dir.cwd().createDirPath(std.testing.io, dir) catch {};
    return std.fmt.allocPrint(allocator, "{s}/settings.json", .{dir});
}

test "AC-APP-022 设置 JSON 顶层结构与未知键保留" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    const path = try settingsTestPath(std.testing.allocator, "app022");
    defer std.testing.allocator.free(path);
    std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    s.setInt("editor.font_size", 14);
    try s.save(std.testing.io, path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("format").?.integer);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("app_version").?.integer);
    try std.testing.expect(parsed.value.object.get("app").? == .object);
    try std.testing.expect(parsed.value.object.get("ui").? == .object);

    // 未知顶层键在读写往返中原样保留。
    const with_future = "{\"format\":1,\"app_version\":1,\"app\":{},\"ui\":{},\"x_future\":{\"a\":1}}";
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = with_future });
    try s.load(std.testing.io, path);
    s.setBool("flag", true);
    try s.save(std.testing.io, path);
    const bytes2 = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(bytes2);
    var parsed2 = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bytes2, .{});
    defer parsed2.deinit();
    try std.testing.expect(parsed2.value.object.get("x_future") != null);
    try std.testing.expectEqual(@as(i64, 1), parsed2.value.object.get("x_future").?.object.get("a").?.integer);
}

test "AC-APP-027 类型化设置访问器" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    s.setInt("editor.font_size", 14);
    try std.testing.expectEqual(@as(i64, 14), s.getInt("editor.font_size", 0));
    try std.testing.expectEqual(@as(i64, 3), s.getInt("missing", 3));
    // 布尔读取整数键 → 默认值并记一条 warn。
    const warnings = s.warnings;
    try std.testing.expectEqual(true, s.getBool("editor.font_size", true));
    try std.testing.expectEqual(warnings + 1, s.warnings);
    var buf = [_]u8{ 'a', 'b', 'c' };
    s.setString("name", &buf);
    buf[0] = 'z';
    try std.testing.expectEqualStrings("abc", s.getString("name", ""));
    s.setString("name", "xyz");
    try std.testing.expectEqualStrings("xyz", s.getString("name", ""));
    s.setFloat("ratio", 0.3);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), s.getFloat("ratio", 0), 0.0001);
    s.remove("name");
    try std.testing.expectEqualStrings("default", s.getString("name", "default"));
}

test "AC-APP-023/024 原子写入与去抖写入次数" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    const path = try settingsTestPath(std.testing.allocator, "app023");
    defer std.testing.allocator.free(path);
    std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    s.setInt("x", 1);
    try s.save(std.testing.io, path);
    try std.testing.expect(!s.dirty);
    // 临时文件已被重命名，只剩目标文件。
    const tmp_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.tmp", .{path});
    defer std.testing.allocator.free(tmp_path);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, tmp_path, .{}));
    // 读取得到完整 JSON。
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"x\":1") != null);
    // 干净状态下 flush 不写入；脏状态下同步写入。
    s.flush(std.testing.io);
    try std.testing.expect(!s.dirty);
    s.setInt("x", 2);
    try std.testing.expect(s.dirty);
    s.flush(std.testing.io);
    try std.testing.expect(!s.dirty);
}

test "AC-APP-025 损坏设置文件恢复" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    const path = try settingsTestPath(std.testing.allocator, "app025");
    defer std.testing.allocator.free(path);
    std.Io.Dir.cwd().deleteFile(std.testing.io, path) catch {};
    const bad_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.bad", .{path});
    defer std.testing.allocator.free(bad_path);
    std.Io.Dir.cwd().deleteFile(std.testing.io, bad_path) catch {};
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "{ not json" });
    try s.load(std.testing.io, path);
    try std.testing.expect(s.recoveredFromCorruption());
    try std.testing.expect(s.warnings > 0);
    try std.Io.Dir.cwd().access(std.testing.io, bad_path, .{});
    // 不存在文件不算损坏。
    var s2 = nano.settings.Settings.init(std.testing.allocator);
    defer s2.deinit();
    try s2.load(std.testing.io, "/tmp/opencode/does_not_exist_settings.json");
    try std.testing.expect(!s2.recoveredFromCorruption());
}

// ---------------------------------------------------------------------------
// M5：多窗口与应用生命周期
// ---------------------------------------------------------------------------

const WindowFixture = struct {
    builds: u32 = 0,
    closed: u32 = 0,
    asked: u32 = 0,
    last_reason: nano.app.CloseReason = .user,
    veto: bool = false,
    ctx: *anyopaque = undefined,
    fn build(ctx: *anyopaque, u: *ui.Ui) void {
        const self: *WindowFixture = @ptrCast(@alignCast(ctx));
        self.builds += 1;
        _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
        u.endColumn();
    }
    fn close(ctx: *anyopaque, reason: nano.app.CloseReason) nano.app.CloseDecision {
        const self: *WindowFixture = @ptrCast(@alignCast(ctx));
        self.asked += 1;
        self.last_reason = reason;
        return if (self.veto) .veto else .allow;
    }
    fn closedCb(ctx: *anyopaque) void {
        const self: *WindowFixture = @ptrCast(@alignCast(ctx));
        self.closed += 1;
    }
    fn handlers(self: *WindowFixture) nano.app.WindowHandlers {
        self.ctx = self;
        return .{ .build = build, .ctx = self, .on_close_request = close, .on_closed = closedCb };
    }
};

test "AC-APP-002 退出询问顺序、否决与退出策略" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var fa = WindowFixture{};
    var fb = WindowFixture{};
    var na = [_]u8{'A'};
    var nb = [_]u8{'B'};
    const a = try app.createWindow(.{ .title = &na, .persist_name = "a" }, fa.handlers());
    const b = try app.createWindow(.{ .title = &nb, .persist_name = "b" }, fb.handlers());
    _ = a;
    _ = b;
    fa.veto = true;
    app.quit(7);
    try std.testing.expectEqual(@as(usize, 2), app.managed.items.len);
    try std.testing.expect(!app.quitting);
    try std.testing.expectEqual(@as(i32, 0), app.quit_code);
    // 逆序询问：B 先于 A。
    try std.testing.expectEqual(@as(u32, 1), fb.asked);
    try std.testing.expectEqual(@as(u32, 1), fa.asked);
    try std.testing.expectEqual(nano.app.CloseReason.app_quit, fa.last_reason);
    fa.veto = false;
    app.quit(7);
    try std.testing.expectEqual(@as(usize, 0), app.managed.items.len);
    try std.testing.expect(app.quitting);
    try std.testing.expectEqual(@as(i32, 7), app.quit_code);
    try std.testing.expectEqual(@as(u32, 1), fa.closed);
    try std.testing.expectEqual(@as(u32, 1), fb.closed);

    // 默认策略：关闭最后一个窗口自动退出，退出码 0。
    var app2 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app2.deinit();
    var f2 = WindowFixture{};
    const w2 = try app2.createWindow(.{ .title = "one" }, f2.handlers());
    w2.requestClose(.user);
    try std.testing.expect(app2.quitting);
    try std.testing.expectEqual(@as(i32, 0), app2.quit_code);
    try std.testing.expectEqual(@as(u32, 1), f2.closed);

    // explicit：最后一个窗口关闭后继续运行；隐藏窗口仍计为存活。
    var app3 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 }, .exit_policy = .explicit });
    defer app3.deinit();
    var f3 = WindowFixture{};
    var f4 = WindowFixture{};
    const w3 = try app3.createWindow(.{ .title = "a" }, f3.handlers());
    const w4 = try app3.createWindow(.{ .title = "b", .visible = false }, f4.handlers());
    w3.destroy();
    try std.testing.expect(!app3.quitting);
    try std.testing.expectEqual(@as(usize, 1), app3.managed.items.len);
    w4.destroy();
    try std.testing.expect(!app3.quitting);
    app3.quit(3);
    try std.testing.expect(app3.quitting);
    try std.testing.expectEqual(@as(i32, 3), app3.quit_code);
}

test "AC-APP-006 窗口标题复制、on_closed 与 persist_name 唯一" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var f = WindowFixture{};
    var title_buf = [_]u8{ 'T', '1', 0 };
    const w = try app.createWindow(.{ .title = title_buf[0..2], .min_size = .{ .w = 300, .h = 40 }, .persist_name = "main" }, f.handlers());
    title_buf[0] = 'X';
    try std.testing.expectEqualStrings("T1", w.title);
    try std.testing.expectEqualStrings("T1", w.native.title);
    try std.testing.expectEqual(@as(f32, 300), w.minWindowSize().w);
    try std.testing.expectEqual(@as(f32, 40), w.minWindowSize().h);
    w.build();
    try std.testing.expectEqual(@as(u32, 1), f.builds);
    try std.testing.expectEqual(@as(*anyopaque, &f), f.ctx);
    try std.testing.expectError(error.DuplicatePersistName, app.createWindow(.{ .title = "dup", .persist_name = "main" }, f.handlers()));
    w.destroy();
    try std.testing.expectEqual(@as(u32, 1), f.closed);
    w.destroy();
    try std.testing.expectEqual(@as(u32, 1), f.closed);
    try std.testing.expectEqual(@as(usize, 0), app.managed.items.len);
}

test "AC-APP-008 多窗口独立焦点与共享命令" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    const FocusModel = struct {
        name: widgets.TextBuf,
        fn buildA(ctx: *anyopaque, u: *ui.Ui) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
            _ = widgets.textInput(u, @src(), &self.name, .{ .debug_name = "a_name", .key = ui.Key.str("a_name") });
            u.endColumn();
        }
        fn buildB(_: *anyopaque, u: *ui.Ui) void {
            _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
            _ = widgets.button(u, @src(), "B", .{ .debug_name = "b_btn" });
            u.endColumn();
        }
    };
    var m1 = FocusModel{ .name = widgets.TextBuf.init(std.testing.allocator) };
    defer m1.name.deinit();
    var m2: u8 = 0;
    const wa = try app.createWindow(.{ .title = "A" }, .{ .build = FocusModel.buildA, .ctx = &m1 });
    const wb = try app.createWindow(.{ .title = "B" }, .{ .build = FocusModel.buildB, .ctx = &m2 });
    // 两个窗口分别聚焦不同节点。
    wa.build();
    wb.build();
    const a_name = findByName(wa.ui().current_root, "a_name") orelse return error.TestUnexpectedResult;
    const b_btn = findByName(wb.ui().current_root, "b_btn") orelse return error.TestUnexpectedResult;
    wa.ui().setFocus(a_name.id);
    wb.ui().setFocus(b_btn.id);
    wa.build();
    wb.build();
    try std.testing.expectEqual(a_name.id, wa.ui().focusedId());
    try std.testing.expectEqual(b_btn.id, wb.ui().focusedId());
    // 状态槽不跨窗口：A 的节点 ID 不出现在 B 的树中。
    try std.testing.expect(findByName(wb.ui().current_root, "a_name") == null);
    // 命令共享。
    const copy_a = app.commands.find("edit.copy").?;
    try std.testing.expect(copy_a == app.commands.find("edit.copy").?);
}

test "AC-APP-031 会话结束询问与回答" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var fa = WindowFixture{};
    var fb = WindowFixture{};
    const wa = try app.createWindow(.{ .title = "A" }, fa.handlers());
    const wb = try app.createWindow(.{ .title = "B" }, fb.handlers());
    _ = wa;
    _ = wb;
    app.onSessionEnding(true);
    try std.testing.expectEqual(@as(?bool, true), app.session_allowed);
    try std.testing.expectEqual(@as(?bool, true), platform.Headless.lastSessionAllowed());
    try std.testing.expectEqual(nano.app.CloseReason.session_end, fa.last_reason);
    try std.testing.expectEqual(@as(usize, 2), app.managed.items.len);
    // 否决：询问停止、回答 false、窗口不销毁。
    fa.veto = true;
    fb.asked = 0;
    app.onSessionEnding(true);
    try std.testing.expectEqual(@as(?bool, false), app.session_allowed);
    try std.testing.expectEqual(@as(?bool, false), platform.Headless.lastSessionAllowed());
    try std.testing.expectEqual(@as(usize, 2), app.managed.items.len);
    try std.testing.expectEqual(@as(u32, 1), fb.asked);
    try std.testing.expectEqual(@as(u32, 2), fa.asked);
}

test "AC-APP-021 设置文件路径解析" {
    const Env = struct {
        var appdata: []const u8 = "";
        var xdg: ?[]const u8 = null;
        var home: []const u8 = "/home/u";
        fn get(_: ?*anyopaque, key: []const u8) ?[]const u8 {
            if (std.mem.eql(u8, key, "APPDATA")) return appdata;
            if (std.mem.eql(u8, key, "XDG_CONFIG_HOME")) return xdg;
            if (std.mem.eql(u8, key, "HOME")) return home;
            return null;
        }
    };
    Env.appdata = "C:\\Users\\u\\AppData\\Roaming";
    const win = try nano.settings.resolvePath(std.testing.allocator, "Acme", "Tool", .windows, .{ .get = Env.get });
    defer std.testing.allocator.free(win);
    try std.testing.expectEqualStrings("C:\\Users\\u\\AppData\\Roaming\\Acme\\Tool\\settings.json", win);
    Env.xdg = "/h/.config2";
    const linux = try nano.settings.resolvePath(std.testing.allocator, "Acme", "Tool", .posix, .{ .get = Env.get });
    defer std.testing.allocator.free(linux);
    try std.testing.expectEqualStrings("/h/.config2/Acme/Tool/settings.json", linux);
    Env.xdg = "";
    const fallback = try nano.settings.resolvePath(std.testing.allocator, "Acme", "Tool", .posix, .{ .get = Env.get });
    defer std.testing.allocator.free(fallback);
    try std.testing.expectEqualStrings("/home/u/.config/Acme/Tool/settings.json", fallback);
}

test "AC-LAYOUT-019 Table 列宽求解" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cols = [_]layout.Column{
        .{ .width = .{ .fixed = 100 } },
        .{ .width = .auto_header },
        .{ .width = .{ .grow = 1 } },
        .{ .width = .{ .grow = 2 } },
    };
    var header = [_]i32{ 0, 80, 0, 0 };
    var out: [4]i32 = undefined;
    layout.solveColumns(arena.allocator(), &cols, &header, 600, true, 0, 1, &out);
    try std.testing.expectEqualSlices(i32, &.{ 100, 80, 140, 280 }, &out);
    // 同一输入重复调用结果一致。
    var out2: [4]i32 = undefined;
    layout.solveColumns(arena.allocator(), &cols, &header, 600, true, 0, 1, &out2);
    try std.testing.expectEqualSlices(i32, &out, &out2);
    // min = 120，宽度 500 → 100/120/93/187。
    var cols2 = cols;
    cols2[1].min = 120;
    var header2 = [_]i32{ 0, 80, 0, 0 };
    layout.solveColumns(arena.allocator(), &cols2, &header2, 500, true, 0, 1, &out);
    try std.testing.expectEqualSlices(i32, &.{ 100, 120, 93, 187 }, &out);
}

test "AC-FRAME-031/AC-APP-005 invalidateAll 只置脏各窗口一次" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var count_a: u32 = 0;
    var count_b: u32 = 0;
    const B = struct {
        fn a(ctx: *anyopaque, u: *ui.Ui) void {
            _ = ctx;
            _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
            u.endColumn();
        }
        fn b(ctx: *anyopaque, u: *ui.Ui) void {
            _ = ctx;
            _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
            u.endColumn();
        }
    };
    const wa = try app.createWindow(.{ .title = "A" }, .{ .build = B.a, .ctx = &count_a });
    const wb = try app.createWindow(.{ .title = "B" }, .{ .build = B.b, .ctx = &count_b });
    wa.build();
    wb.build();
    try std.testing.expectEqual(ui.Dirty.none, wa.ui().dirty);
    try std.testing.expectEqual(ui.Dirty.none, wb.ui().dirty);
    app.invalidateAll(.build);
    try std.testing.expectEqual(ui.Dirty.build, wa.ui().dirty);
    try std.testing.expectEqual(ui.Dirty.build, wb.ui().dirty);
    // 单个窗口失效不传递到另一个。
    wa.build();
    try std.testing.expectEqual(ui.Dirty.none, wa.ui().dirty);
    wa.invalidate(.paint);
    try std.testing.expectEqual(ui.Dirty.paint, wa.ui().dirty);
    try std.testing.expectEqual(ui.Dirty.build, wb.ui().dirty);
}

test "AC-APP-010 窗口位置记录校验与 DPI 换算" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const base = platform.Monitor{ .bounds = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 }, .work_area = .{ .x = 0, .y = 0, .w = 1920, .h = 1040 }, .dpi = 96, .scale = 1 };
    platform.Headless.setMonitors(&.{base});
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var f = WindowFixture{};

    try std.testing.expect(app.resolvePlacement("none") == null);

    app.settings.setWindowPlacement("main", .{ .x = 100, .y = 80, .w = 900, .h = 600, .dpi = 96, .maximized = false });
    try std.testing.expectEqual(platform.RectI{ .x = 100, .y = 80, .w = 900, .h = 600 }, app.resolvePlacement("main").?.normal_rect);

    app.settings.setWindowPlacement("main", .{ .x = 1800, .y = 80, .w = 900, .h = 600, .dpi = 96, .maximized = false });
    const p3 = app.resolvePlacement("main").?;
    try std.testing.expect(p3.normal_rect.x != 1800);
    try std.testing.expectEqual(@as(i32, 900), p3.normal_rect.w);

    app.settings.setWindowPlacement("main", .{ .x = 100, .y = 1030, .w = 900, .h = 600, .dpi = 96, .maximized = false });
    try std.testing.expect(app.resolvePlacement("main").?.normal_rect.y != 1030);

    app.settings.setWindowPlacement("main", .{ .x = 100, .y = 80, .w = 1350, .h = 900, .dpi = 144, .maximized = false });
    const p6 = app.resolvePlacement("main").?;
    try std.testing.expectEqual(@as(i32, 900), p6.normal_rect.w);
    try std.testing.expectEqual(@as(i32, 600), p6.normal_rect.h);
    try std.testing.expectEqual(@as(i32, 100), p6.normal_rect.x);

    app.settings.setWindowPlacement("main", .{ .x = 0, .y = 0, .w = 3000, .h = 2000, .dpi = 96, .maximized = false });
    const p7 = app.resolvePlacement("main").?;
    try std.testing.expectEqual(@as(i32, 1920), p7.normal_rect.w);
    try std.testing.expectEqual(@as(i32, 1040), p7.normal_rect.h);

    app.settings.setWindowPlacement("main", .{ .x = 100, .y = 80, .w = 900, .h = 600, .dpi = 96, .maximized = true });
    const p8 = app.resolvePlacement("main").?;
    try std.testing.expectEqual(platform.WindowState.maximized, p8.state);
    try std.testing.expectEqual(@as(i32, 900), p8.normal_rect.w);

    // createWindow 使用校验后的 placement。
    const w = try app.createWindow(.{ .title = "main", .persist_name = "main" }, f.handlers());
    try std.testing.expectEqual(platform.WindowState.maximized, w.native.placement.state);
    try std.testing.expectEqual(@as(i32, 900), w.native.placement.normal_rect.w);
    w.destroy();
}

test "AC-APP-009 窗口位置保存到设置" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var f = WindowFixture{};
    const w = try app.createWindow(.{ .title = "main", .persist_name = "main", .size = .{ .w = 900, .h = 600 } }, f.handlers());
    app.saveWindowPlacement(w);
    const rec = app.settings.windowPlacement("main").?;
    try std.testing.expectEqual(@as(i64, 900), rec.object.get("w").?.integer);
    try std.testing.expectEqual(@as(i64, 600), rec.object.get("h").?.integer);
    try std.testing.expectEqual(@as(i64, 96), rec.object.get("dpi").?.integer);
    try std.testing.expectEqual(false, rec.object.get("maximized").?.bool);
    try std.testing.expect(app.settings.dirty);
    // 无 persist_name 的窗口不产生记录。
    var f2 = WindowFixture{};
    const w2 = try app.createWindow(.{ .title = "other" }, f2.handlers());
    app.saveWindowPlacement(w2);
    try std.testing.expect(app.settings.windowPlacement("other") == null);
    w2.destroy();
    w.destroy();
}

test "AC-PLAT-009 关闭请求取消/确认与会话结束回答" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    platform.forceHeadless();
    const Sink = struct {
        var closes: usize = 0;
        var session_endings: usize = 0;
        var session_ended: usize = 0;
        fn sink(_: ?*anyopaque, e: platform.Event) void {
            switch (e.data) {
                .close_requested => closes += 1,
                .session_ending => session_endings += 1,
                .session_ended => session_ended += 1,
                else => {},
            }
        }
    };
    const w = try platform.createWindow(.{ .title = "close", .client_size = .{ .w = 320, .h = 240 } });
    // 会话结束：询问阶段回答 false。
    platform.Headless.inject(.{ .session_ending = .{ .logoff = true } });
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 1), Sink.session_endings);
    platform.allowSessionEnd(false);
    try std.testing.expectEqual(@as(?bool, false), platform.Headless.lastSessionAllowed());
    try std.testing.expectEqual(@as(usize, 1), platform.Headless.sessionAnswerCount());
    platform.Headless.inject(.{ .session_ended = .{ .logoff = true } });
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 1), Sink.session_ended);
    try std.testing.expectEqual(@as(usize, 1), platform.Headless.windowCount());

    // 关闭请求：取消后窗口仍在，presentCount 可继续增长。
    platform.Headless.inject(.close_requested);
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 1), Sink.closes);
    w.cancelClose();
    try std.testing.expectEqual(@as(usize, 1), platform.Headless.windowCount());
    platform.present(w);
    try std.testing.expect(platform.Headless.presentCount() > 0);
    // 再次请求并确认：窗口被销毁。
    platform.Headless.inject(.close_requested);
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 2), Sink.closes);
    w.confirmClose();
    try std.testing.expectEqual(@as(usize, 0), platform.Headless.windowCount());
}

test "AC-W-TABLE-009 键盘行导航与横向滚动" {
    var cols: [20]widgets.TableColumn = undefined;
    var ci: usize = 0;
    while (ci < cols.len) : (ci += 1) cols[ci] = .{ .title = "x", .width = .{ .fixed = 100 } };
    var c = try widgets.TableController.init(std.testing.allocator, &cols, 100, .{ .mode = .multi });
    defer c.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    c.layoutColumns(arena.allocator(), 800, 1.0, 7);
    c.correct();
    c.row_sel.focus = c.row_sel.refAt(0);
    _ = c.keyDown(.down, .{}, false, 0);
    try expectSel(c.selectionPtr(), &.{1});
    _ = c.keyDown(.down, .{ .shift = true }, false, 0);
    try expectSel(c.selectionPtr(), &.{ 1, 2 });
    _ = c.keyDown(.a, .{ .ctrl = true }, false, 0);
    try std.testing.expectEqual(@as(usize, 100), c.selection().len());
    const before = c.selection().len();
    const off0 = c.offset_x;
    const right = c.keyDown(.right, .{}, false, 0);
    try std.testing.expect(right.consumed);
    try std.testing.expectEqual(off0 + 22, c.offset_x);
    _ = c.keyDown(.right, .{ .shift = true }, false, 0);
    try std.testing.expectEqual(off0 + 44, c.offset_x);
    _ = c.keyDown(.left, .{}, false, 0);
    try std.testing.expectEqual(off0 + 22, c.offset_x);
    const ctrl = c.keyDown(.right, .{ .ctrl = true }, false, 0);
    try std.testing.expect(!ctrl.consumed);
    try std.testing.expectEqual(off0 + 22, c.offset_x);
    try std.testing.expectEqual(before, c.selection().len());
    c.offset_x = 0;
    const left0 = c.keyDown(.left, .{}, false, 0);
    try std.testing.expect(!left0.consumed);
    try std.testing.expectEqual(@as(f32, 0), c.offset_x);
}

test "AC-W-TABLE-012 表头右键与列隐藏" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    c.opts.header_menu = true;
    G1.layout(&c, 800);
    const sort_before = c.sort();
    const hit = c.headerRightClick(600);
    try std.testing.expectEqual(@as(?u16, 2), hit.header_context.?.column);
    try std.testing.expectEqual(sort_before.column, c.sort().column);
    try std.testing.expectEqual(@as(usize, 0), c.selection().len());
    try std.testing.expectEqual(@as(?u16, null), c.headerRightClick(5000).header_context.?.column);
    c.setColumnHidden(2, true);
    try std.testing.expectEqual(@as(usize, 3), c.displayCount());
    G1.layout(&c, 800);
    try std.testing.expectEqual(@as(f32, 0), c.widths[2]);
    // 显示序仍包含 4 项。
    try std.testing.expectEqual(@as(usize, 4), c.order.len);
    // header_menu = false：无结果。
    var c2 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .header_menu = false });
    defer c2.deinit();
    G1.layout(&c2, 800);
    try std.testing.expect(c2.headerRightClick(600).header_context == null);
    // 行右键带列号。
    _ = c2.pointerPress(8, .right, .{});
    try expectSel(c2.selectionPtr(), &.{8});
    const rc = c2.rowContextMenu(8, 520, .{ .x = 520, .y = 200 }, false);
    try std.testing.expectEqual(@as(?usize, 8), rc.context_menu.?.index);
    try std.testing.expectEqual(@as(?u16, 1), rc.context_menu.?.column);
}

test "AC-W-TABLE-011 表格状态持久化与校验" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    c.user_widths[1] = 120;
    G1.layout(&c, 800);
    c.moveColumn(1, 3);
    _ = c.headerPress(100);
    c.headerRelease(100);
    c.setColumnHidden(2, true);
    c.saveToSettings(&s, "main/files");
    const rec = s.table("main/files").?;
    try std.testing.expectEqual(@as(usize, 4), rec.object.get("widths").?.array.items.len);
    try std.testing.expectEqual(@as(f64, 120), rec.object.get("widths").?.array.items[1].float);
    try std.testing.expectEqual(@as(i64, 2), rec.object.get("order").?.array.items[1].integer);
    try std.testing.expectEqual(true, rec.object.get("hidden").?.array.items[2].bool);
    try std.testing.expectEqual(@as(i64, 0), rec.object.get("sort").?.object.get("col").?.integer);
    try std.testing.expectEqual(true, rec.object.get("sort").?.object.get("asc").?.bool);
    // 重启读入。
    var c2 = try G1.make(std.testing.allocator);
    defer c2.deinit();
    try std.testing.expect(c2.loadFromSettings(&s, "main/files"));
    G1.layout(&c2, 800);
    try std.testing.expectEqual(@as(f32, 120), c2.widths[1]);
    try std.testing.expectEqual(@as(u16, 2), c2.order[1]);
    try std.testing.expect(c2.hidden[2]);
    try std.testing.expectEqual(@as(?u16, 0), c2.sort().column);
    try std.testing.expectEqual(widgets.SortDir.asc, c2.sort().dir);

    // 长度不符 -> 整条忽略。
    const bad_w = [_]f32{ 0, 120, 0 };
    const bad_o = [_]u16{ 0, 1, 2 };
    const bad_h = [_]bool{ false, false, true };
    s.setTable("bad", &bad_w, &bad_o, &bad_h, 0, true);
    var c3 = try G1.make(std.testing.allocator);
    defer c3.deinit();
    try std.testing.expect(!c3.loadFromSettings(&s, "bad"));
    // order 非排列。
    const ok_w = [_]f32{ 0, 0, 0, 0 };
    const bad_order = [_]u16{ 0, 0, 1, 2 };
    const ok_h = [_]bool{ false, false, false, false };
    s.setTable("bad2", &ok_w, &bad_order, &ok_h, null, true);
    try std.testing.expect(!c3.loadFromSettings(&s, "bad2"));
    // sort 列越界。
    const ok_order = [_]u16{ 0, 1, 2, 3 };
    s.setTable("bad3", &ok_w, &ok_order, &ok_h, 7, true);
    try std.testing.expect(!c3.loadFromSettings(&s, "bad3"));
    // 负宽度。
    const neg_w = [_]f32{ 0, -1, 0, 0 };
    s.setTable("bad4", &neg_w, &ok_order, &ok_h, null, true);
    try std.testing.expect(!c3.loadFromSettings(&s, "bad4"));
}

const TStr = struct {
    const A: widgets.TreeNode = @fromBackingInt(1);
    const A1: widgets.TreeNode = @fromBackingInt(2);
    const A2: widgets.TreeNode = @fromBackingInt(3);
    const A2a: widgets.TreeNode = @fromBackingInt(4);
    const A2b: widgets.TreeNode = @fromBackingInt(5);
    const A3: widgets.TreeNode = @fromBackingInt(6);
    const B: widgets.TreeNode = @fromBackingInt(7);
    const B1: widgets.TreeNode = @fromBackingInt(8);
    const C: widgets.TreeNode = @fromBackingInt(9);
    const top = [_]widgets.TreeNode{ A, B, C };
    const a_children = [_]widgets.TreeNode{ A1, A2, A3 };
    const a2_children = [_]widgets.TreeNode{ A2a, A2b };
    const b_children = [_]widgets.TreeNode{B1};
    fn children(node: widgets.TreeNode) []const widgets.TreeNode {
        if (node == .root) return &top;
        if (node == A) return &a_children;
        if (node == A2) return &a2_children;
        if (node == B) return &b_children;
        return &.{};
    }
    fn name(node: widgets.TreeNode) []const u8 {
        return switch (node) {
            A => "A",
            A1 => "A/A1",
            A2 => "A/A2",
            A2a => "A/A2/A2a",
            A2b => "A/A2/A2b",
            A3 => "A/A3",
            B => "B",
            B1 => "B/B1",
            C => "C",
            else => "",
        };
    }
    fn childCount(_: ?*anyopaque, node: widgets.TreeNode) usize {
        return children(node).len;
    }
    fn childAt(_: ?*anyopaque, node: widgets.TreeNode, i: usize) widgets.TreeNode {
        return children(node)[i];
    }
    fn hasChildren(_: ?*anyopaque, node: widgets.TreeNode) bool {
        return children(node).len > 0;
    }
    fn keyOf(_: ?*anyopaque, node: widgets.TreeNode) widgets.ItemKey {
        return ui.Key.str(name(node)).hash;
    }
    fn textOf(_: ?*anyopaque, node: widgets.TreeNode) []const u8 {
        return name(node);
    }
    fn strKey(_: ?*anyopaque, node: widgets.TreeNode) []const u8 {
        return name(node);
    }
    fn model(version: u64) widgets.TreeModel {
        return .{ .child_count = childCount, .child_at = childAt, .has_children = hasChildren, .key_of = keyOf, .text_of = textOf, .str_key_of = strKey, .version = version };
    }
};

test "AC-W-TREE-008 展开集合持久化与初始展开" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    var c = widgets.TreeController.init(std.testing.allocator, TStr.model(0), .{ .mode = .multi });
    defer c.deinit();
    c.correct();
    try std.testing.expectEqual(@as(usize, 3), c.rowsSlice().len);
    _ = c.toggle(0);
    _ = c.toggle(2);
    try std.testing.expectEqual(@as(usize, 8), c.rowsSlice().len);
    widgets.treeSaveToSettings(&c, &s, "main/tree1");
    const rec = s.tree("main/tree1").?;
    try std.testing.expectEqual(@as(usize, 2), rec.array.items.len);
    try std.testing.expectEqualStrings("A", rec.array.items[0].string);
    try std.testing.expectEqualStrings("A/A2", rec.array.items[1].string);

    // 重启读入。
    var c2 = widgets.TreeController.init(std.testing.allocator, TStr.model(0), .{ .mode = .multi });
    defer c2.deinit();
    try std.testing.expectEqual(@as(usize, 2), widgets.treeLoadFromSettings(&c2, &s, "main/tree1"));
    c2.correct();
    try std.testing.expectEqual(@as(usize, 8), c2.rowsSlice().len);
    try std.testing.expect(c2.expanded().contains(ui.Key.str("A/A2").hash));

    // 不存在的键保留在集合中。
    const with_z = [_][]const u8{ "A", "A/A2", "Z" };
    s.setTree("main/tree1", &with_z);
    var c3 = widgets.TreeController.init(std.testing.allocator, TStr.model(0), .{ .mode = .multi });
    defer c3.deinit();
    try std.testing.expectEqual(@as(usize, 3), widgets.treeLoadFromSettings(&c3, &s, "main/tree1"));
    try std.testing.expect(c3.expanded().contains(ui.Key.str("Z").hash));
    c3.correct();
    try std.testing.expectEqual(@as(usize, 8), c3.rowsSlice().len);

    // 无记录时 initially_expanded_depth = 1 展开顶层。
    var c4 = widgets.TreeController.init(std.testing.allocator, TStr.model(0), .{ .mode = .multi, .initially_expanded_depth = 1 });
    defer c4.deinit();
    c4.correct();
    try std.testing.expectEqual(@as(usize, 7), c4.rowsSlice().len);
    try std.testing.expect(c4.expanded().contains(ui.Key.str("A").hash));
    try std.testing.expect(c4.expanded().contains(ui.Key.str("B").hash));
    try std.testing.expect(!c4.expanded().contains(ui.Key.str("A/A2").hash));
}

test "AC-W-TABLE-007 列拖动载荷与插入位置" {
    var c = try G1.make(std.testing.allocator);
    defer c.deinit();
    G1.layout(&c, 800);
    const payload = c.columnDragStart(2).?;
    try std.testing.expectEqual(widgets.table_column_kind, payload.kind);
    try std.testing.expectEqual(@as(u16, 2), payload.data);
    try std.testing.expectEqual(@as(usize, 1), c.columnDropIndex(500));
    c.moveColumn(2, 1);
    try std.testing.expectEqual(@as(u16, 2), c.order[1]);
    try std.testing.expectEqual(@as(u16, 1), c.order[2]);
    // x = 20 → ins 0 → [2,0,1,3]。
    var c2 = try G1.make(std.testing.allocator);
    defer c2.deinit();
    G1.layout(&c2, 800);
    try std.testing.expectEqual(@as(usize, 0), c2.columnDropIndex(20));
    c2.moveColumn(2, 0);
    try std.testing.expectEqual(@as(u16, 2), c2.order[0]);
    // x = 640 → ins 3，位于原位置之后紧邻 → 无操作。
    var c3 = try G1.make(std.testing.allocator);
    defer c3.deinit();
    G1.layout(&c3, 800);
    try std.testing.expectEqual(@as(usize, 3), c3.columnDropIndex(640));
    c3.moveColumn(2, 3);
    try std.testing.expect(!c3.update.columns_reordered);
    // reorder_columns = false。
    var c4 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .reorder_columns = false });
    defer c4.deinit();
    G1.layout(&c4, 800);
    try std.testing.expect(c4.columnDragStart(0) == null);
}

test "AC-W-LIST-014 虚拟节点数与总行数无关" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .row_height = 22 });
    defer c.deinit();
    c.viewport_h = 660;
    const counts = [_]usize{ 10000, 100000, 1000000 };
    var first_last: [3][2]usize = undefined;
    for (counts, 0..) |count, i| {
        c.correct(count);
        c.offset = 22000;
        const r = c.visibleRange(count);
        first_last[i] = .{ r.first, r.last };
        try std.testing.expectEqual(@as(usize, 995), r.first);
        try std.testing.expectEqual(@as(usize, 1034), r.last);
        try std.testing.expectEqual(@as(usize, 40), r.last - r.first + 1);
    }
    try std.testing.expectEqual(first_last[0], first_last[1]);
    try std.testing.expectEqual(first_last[1], first_last[2]);
    c.viewport_h = 330;
    const small = c.visibleRange(1000000);
    try std.testing.expectEqual(@as(usize, 995), small.first);
    try std.testing.expectEqual(@as(usize, 25), small.last - small.first + 1);
}

test "AC-APP-003 回投队列按序执行与退出流程拒绝" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    const Run = struct {
        var next_expected: u32 = 0;
        var executed: u32 = 0;
        const Ctx = struct { seq: u32 };
        fn run(ctx: ?*anyopaque) void {
            const c: *Ctx = @ptrCast(@alignCast(ctx.?));
            std.debug.assert(c.seq == next_expected);
            next_expected += 1;
            executed += 1;
            std.testing.allocator.destroy(c);
        }
    };
    Run.next_expected = 0;
    Run.executed = 0;
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const c = try std.testing.allocator.create(Run.Ctx);
        c.* = .{ .seq = i };
        try std.testing.expect(app.post(.{ .ctx = c, .func = Run.run }));
    }
    _ = app.pump();
    try std.testing.expectEqual(@as(u32, 1000), Run.executed);
    // 退出流程开始后 post 返回 false 且不执行；调用方释放 ctx。
    app.quitting = true;
    const c2 = try std.testing.allocator.create(Run.Ctx);
    c2.* = .{ .seq = 1000 };
    try std.testing.expect(!app.post(.{ .ctx = c2, .func = Run.run }));
    try std.testing.expectEqual(@as(u32, 1000), Run.executed);
    std.testing.allocator.destroy(c2);
    app.quitting = false;
}

test "AC-PLAT-016 鼠标事件注入、捕获与移出客户区" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    platform.forceHeadless();
    const w = try platform.createWindow(.{ .title = "mouse", .client_size = .{ .w = 320, .h = 240 } });
    const Sink = struct {
        var moves: usize = 0;
        var downs: usize = 0;
        var ups: usize = 0;
        var leaves: usize = 0;
        var last_pos: platform.Vec2i = .{};
        fn sink(_: ?*anyopaque, e: platform.Event) void {
            switch (e.data) {
                .mouse_move => |m| {
                    moves += 1;
                    last_pos = m.pos;
                },
                .mouse_button => |b| {
                    if (b.down) {
                        downs += 1;
                    } else ups += 1;
                },
                .mouse_leave => leaves += 1,
                else => {},
            }
        }
    };
    platform.Headless.injectMouseMove(.{ .x = 10, .y = 10 }, .{});
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 1), Sink.moves);
    try std.testing.expectEqual(platform.Vec2i{ .x = 10, .y = 10 }, Sink.last_pos);
    platform.Headless.injectMouseButton(.left, true, .{ .x = 10, .y = 10 }, .{});
    try std.testing.expect(platform.Headless.captured() != null);
    platform.Headless.injectMouseMove(.{ .x = 400, .y = 300 }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = 400, .y = 300 }, .{});
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 1), Sink.downs);
    try std.testing.expectEqual(@as(usize, 1), Sink.ups);
    try std.testing.expect(platform.Headless.captured() == null);
    try std.testing.expectEqual(@as(usize, 1), Sink.leaves);
    try std.testing.expectEqual(@as(usize, 2), Sink.moves);
    w.cancelClose();
}

test "AC-W-TABLE-010 表头冻结与横向偏移同步" {
    var cols: [20]widgets.TableColumn = undefined;
    var ci: usize = 0;
    while (ci < cols.len) : (ci += 1) cols[ci] = .{ .title = "x", .width = .{ .fixed = 100 } };
    var c = try widgets.TableController.init(std.testing.allocator, &cols, 100, .{ .mode = .multi });
    defer c.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    c.layoutColumns(arena.allocator(), 800, 1.0, 7);
    c.setViewport(800, 660);
    const header0 = c.columnSpan(0);
    c.row_sel.offset = 440;
    const header_after_scroll = c.columnSpan(0);
    try std.testing.expectEqual(header0.first_visible, header_after_scroll.first_visible);
    try std.testing.expectEqual(header0.last_visible, header_after_scroll.last_visible);
    const rows = c.rowVisibleRange();
    try std.testing.expectEqual(@as(usize, 15), rows.first);
    // 横向偏移 66：表头与行共用同一偏移来源。
    c.offset_x = 66;
    const header_h = c.columnSpan(c.offset_x);
    try std.testing.expectEqual(@as(usize, 0), header_h.first_visible);
    try std.testing.expectEqual(@as(usize, 8), header_h.last_visible);
    try std.testing.expectEqual(@as(f32, 1200), c.maxOffsetX());
    // 纵滚动不改变表头命中。
    try std.testing.expectEqual(@as(u16, 6), c.headerHit(600).cell.column);
}

test "AC-APP-007 关闭请求可否决" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var f = WindowFixture{};
    const w = try app.createWindow(.{ .title = "doc", .persist_name = "doc" }, f.handlers());
    f.veto = true;
    w.requestClose(.user);
    try std.testing.expectEqual(@as(u32, 1), f.asked);
    try std.testing.expectEqual(nano.app.CloseReason.user, f.last_reason);
    try std.testing.expectEqual(@as(usize, 1), app.managed.items.len);
    try std.testing.expectEqual(@as(u32, 0), f.closed);
    f.veto = false;
    w.requestClose(.user);
    try std.testing.expectEqual(@as(u32, 2), f.asked);
    try std.testing.expectEqual(@as(u32, 1), f.closed);
    try std.testing.expectEqual(@as(usize, 0), app.managed.items.len);
}

test "AC-APP-032 休眠恢复置脏与语言变化重选字符串" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var f1 = WindowFixture{};
    var f2 = WindowFixture{};
    const w1 = try app.createWindow(.{ .title = "a" }, f1.handlers());
    const w2 = try app.createWindow(.{ .title = "b" }, f2.handlers());
    w1.build();
    w2.build();
    app.onPowerResume();
    try std.testing.expectEqual(ui.Dirty.build, w1.ui().dirty);
    try std.testing.expectEqual(ui.Dirty.build, w2.ui().dirty);
    // 未固定字符串表：语言变化后切换到中文并置脏。
    try std.testing.expectEqualStrings("OK", app.strings().ok);
    app.onLocaleChanged("zh-CN");
    try std.testing.expectEqualStrings("确定", app.strings().ok);
    try std.testing.expectEqual(ui.Dirty.build, w1.ui().dirty);
    // 已固定：不再变化。
    app.setStrings(&nano.app.Strings.en);
    app.onLocaleChanged("zh-CN");
    try std.testing.expectEqualStrings("OK", app.strings().ok);
}

test "AC-APP-016/017 命令状态声明、快捷键与调用队列" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    const M = struct {
        var calls: u32 = 0;
        var dirty: bool = false;
        var trigger: bool = false;
        var cmd: input.CommandId = .none;
        fn handler(_: ?*anyopaque) void {
            calls += 1;
        }
        fn build(_: ?*anyopaque, u: *ui.Ui) void {
            _ = u.command(cmd, .{ .enabled = dirty });
            if (trigger) {
                trigger = false;
                u.invokeCommand(cmd);
            }
            _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
            u.endColumn();
        }
    };
    M.calls = 0;
    M.dirty = false;
    M.trigger = false;
    M.cmd = try app.commands.register(.{ .name = "file.save", .title = "保存(&S)", .shortcut = .{ .key = .s, .mods = .{ .ctrl = true } }, .handler = M.handler });
    var cmd_ctx: u8 = 0;
    app.renderOnce(&cmd_ctx, M.build);
    try std.testing.expect(!app.ui_state.commandState(M.cmd).enabled);
    platform.Headless.injectKey(.s, true, false, .{ .ctrl = true });
    platform.Headless.injectKey(.s, false, false, .{ .ctrl = true });
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), M.calls);
    // 模型变为启用：同一命令声明驱动状态；快捷键调用一次。
    M.dirty = true;
    app.ui_state.invalidate(.build);
    app.renderOnce(&cmd_ctx, M.build);
    try std.testing.expect(app.ui_state.commandState(M.cmd).enabled);
    platform.Headless.injectKey(.s, true, false, .{ .ctrl = true });
    platform.Headless.injectKey(.s, false, false, .{ .ctrl = true });
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 1), M.calls);
    // 队列：构建中 invokeCommand，在第一遍后执行并触发第二遍。
    M.trigger = true;
    app.ui_state.invalidate(.build);
    app.renderOnce(&cmd_ctx, M.build);
    try std.testing.expectEqual(@as(u32, 2), M.calls);
    try std.testing.expectEqual(@as(u32, 2), app.ui_state.build_passes);
}

test "AC-APP-012 对话框客户区尺寸与居中" {
    const content = nano.core.Size{ .w = 320, .h = 140 };
    const sz = nano.app.dialogClientSize(content, 12);
    try std.testing.expectEqual(@as(f32, 344), sz.w);
    try std.testing.expectEqual(@as(f32, 164), sz.h);
    const bigger = nano.app.dialogClientSize(.{ .w = 320, .h = 180 }, 12);
    try std.testing.expectEqual(@as(f32, 204), bigger.h);
    const host = platform.RectI{ .x = 100, .y = 100, .w = 800, .h = 600 };
    const work = platform.RectI{ .x = 0, .y = 0, .w = 1920, .h = 1040 };
    const pos = nano.app.centerDialog(host, sz, work);
    try std.testing.expectEqual(@as(i32, 328), pos.x);
    try std.testing.expectEqual(@as(i32, 318), pos.y);
    // 宿主靠近工作区右缘时夹紧。
    const clamp = nano.app.centerDialog(.{ .x = 1800, .y = 100, .w = 400, .h = 600 }, sz, work);
    try std.testing.expectEqual(@as(i32, 1576), clamp.x);
}

test "AC-APP-013 对话框按钮等宽右对齐" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 344, .h = 164 } });
    defer app.deinit();
    const buttons = [_]widgets.DialogButton{
        .{ .label = "保存", .code = 1, .role = .default, .debug_name = "btn_save" },
        .{ .label = "不保存", .code = 2, .debug_name = "btn_dont" },
        .{ .label = "取消", .code = 3, .role = .cancel, .debug_name = "btn_cancel" },
    };
    const B = struct {
        var btns: []const widgets.DialogButton = &.{};
        fn build(_: *anyopaque, u: *ui.Ui) void {
            _ = widgets.beginDialogBody(u, @src(), .{});
            _ = widgets.dialogButtons(u, @src(), btns);
            widgets.endDialogBody(u);
        }
    };
    B.btns = &buttons;
    var ctx: u8 = 0;
    app.renderOnce(&ctx, B.build);
    const n0 = findByName(app.ui_state.current_root, "btn_save") orelse return error.TestUnexpectedResult;
    const n1 = findByName(app.ui_state.current_root, "btn_dont") orelse return error.TestUnexpectedResult;
    const n2 = findByName(app.ui_state.current_root, "btn_cancel") orelse return error.TestUnexpectedResult;
    // 等宽。
    try std.testing.expectEqual(n0.abs.w, n1.abs.w);
    try std.testing.expectEqual(n0.abs.w, n2.abs.w);
    // 声明顺序从左到右。
    try std.testing.expect(n0.abs.x < n1.abs.x and n1.abs.x < n2.abs.x);
    // 右缘距客户区右边缘 12 lpx（窗口 344）。
    const right_lpx: f32 = @as(f32, @floatFromInt(n2.abs.x + n2.abs.w)) / app.ui_state.scale;
    try std.testing.expectApproxEqAbs(@as(f32, 332), right_lpx, 0.5);
    // 间距 8。
    const gap: f32 = @as(f32, @floatFromInt(n1.abs.x - (n0.abs.x + n0.abs.w))) / app.ui_state.scale;
    try std.testing.expectApproxEqAbs(@as(f32, 8), gap, 0.5);
}

test "AC-APP-026 界面状态存取：分隔条/表格/树" {
    var s = nano.settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    s.setSplitter("main/side", "ratio", 0.3);
    const sp = s.splitter("main/side").?;
    try std.testing.expectEqualStrings("ratio", sp.object.get("mode").?.string);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3), sp.object.get("value").?.float, 0.0001);
    const widths = [_]f32{ 0, 120, 0, 0 };
    const order = [_]u16{ 0, 2, 1, 3 };
    const hidden = [_]bool{ false, false, true, false };
    s.setTable("main/files", &widths, &order, &hidden, 0, true);
    try std.testing.expect(s.table("main/files") != null);
    const tree = [_][]const u8{ "A", "A/A2" };
    s.setTree("main/tree1", &tree);
    try std.testing.expect(s.tree("main/tree1") != null);
    try std.testing.expect(s.dirty);
    // 未被引用的旧条目保留。
    s.setSplitter("main/other", "fixed_first", 100);
    try std.testing.expect(s.splitter("main/side") != null);
    try std.testing.expect(s.splitter("main/other") != null);
}

test "AC-APP-011 openDialog 非阻塞与结果回调" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var f = WindowFixture{};
    const host = try app.createWindow(.{ .title = "host" }, f.handlers());
    const Result = struct {
        var calls: u32 = 0;
        var code: u32 = 0;
        fn onResult(_: ?*anyopaque, c: u32) void {
            calls += 1;
            code = c;
        }
    };
    Result.calls = 0;
    const Build = struct {
        fn build(_: *ui.Ui, _: *nano.app.Dialog, _: *anyopaque) void {}
    };
    var ctx: u8 = 0;
    const d = try app.openDialog(host, .{ .title = "save?" }, Build.build, &ctx, Result.onResult);
    // 立即返回；宿主被禁用。
    try std.testing.expect(host.dialog_open);
    try std.testing.expect(d.result() == null);
    try std.testing.expectEqual(@as(usize, 1), app.open_dialogs.items.len);
    d.close(nano.app.DialogCode.ok);
    try std.testing.expectEqual(@as(?u32, nano.app.DialogCode.ok), d.result());
    try std.testing.expectEqual(@as(u32, 0), Result.calls);
    app.processDialogs();
    try std.testing.expectEqual(@as(u32, 1), Result.calls);
    try std.testing.expectEqual(@as(u32, nano.app.DialogCode.ok), Result.code);
    try std.testing.expect(!host.dialog_open);
    try std.testing.expectEqual(@as(usize, 0), app.open_dialogs.items.len);
    // 宿主销毁前关闭的对话框不调用 on_result。
    Result.calls = 0;
    const d2 = try app.openDialog(host, .{ .title = "x" }, Build.build, &ctx, Result.onResult);
    d2.close(nano.app.DialogCode.cancel);
    host.destroy();
    app.processDialogs();
    try std.testing.expectEqual(@as(u32, 0), Result.calls);
    // 已销毁宿主不能再打开。
    try std.testing.expectError(error.OwnerDestroyed, app.openDialog(host, .{ .title = "x" }, Build.build, &ctx, null));
}

test "AC-INPUT-031/032 拖动会话阈值、放置与外部拖出" {
    var s = input.DragSession{};
    s.begin(.fromHash(7), .{ .kind = widgets.list_reorder_kind, .data = 7 }, .{ .x = 10, .y = 10 }, 4);
    try std.testing.expect(s.active and !s.started);
    try std.testing.expect(!s.move(.{ .x = 13, .y = 12 }, .fromHash(8), true));
    try std.testing.expect(s.move(.{ .x = 20, .y = 12 }, .fromHash(8), true));
    try std.testing.expect(s.started);
    const result = s.finish(true).?;
    try std.testing.expect(result.dropped);
    try std.testing.expectEqual(platform.DropEffect.move, result.effect);
    try std.testing.expectEqual(@as(u64, 7), result.payload.?.data);
    // Esc / 取消。
    s.begin(.fromHash(7), .{ .kind = widgets.list_reorder_kind, .data = 7 }, .{ .x = 0, .y = 0 }, 4);
    _ = s.move(.{ .x = 20, .y = 20 }, .fromHash(9), true);
    s.cancel();
    try std.testing.expect(s.finish(true) == null);
    // 外部载荷：离开窗口后转交系统拖出。
    var ext = input.DragSession{};
    ext.begin(.none, .{ .kind = 1, .external = @ptrFromInt(0x1000) }, .{}, 4);
    _ = ext.move(.{ .x = -1, .y = -1 }, .none, false);
    try std.testing.expect(ext.shouldStartExternal(false));
    try std.testing.expect(!ext.shouldStartExternal(true));
}

test "AC-PLAT-051 系统语言变化与休眠恢复事件" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    platform.forceHeadless();
    const Sink = struct {
        var locale: usize = 0;
        var power: usize = 0;
        fn sink(_: ?*anyopaque, e: platform.Event) void {
            switch (e.data) {
                .system_changed => |sc| if (sc.what.locale) {
                    locale += 1;
                },
                .power_resume => power += 1,
                else => {},
            }
        }
    };
    Sink.locale = 0;
    Sink.power = 0;
    platform.Headless.inject(.{ .system_changed = .{ .what = .{ .locale = true } } });
    platform.Headless.injectPowerResume();
    platform.Headless.injectPowerResume();
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 1), Sink.locale);
    try std.testing.expectEqual(@as(usize, 1), Sink.power);
    // 下一轮可以再次产出。
    platform.Headless.injectPowerResume();
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 2), Sink.power);
}

const BigT = struct {
    var child_count_calls: usize = 0;
    var child_at_calls: usize = 0;
    var has_children_calls: usize = 0;
    var key_of_calls: usize = 0;
    var text_of_calls: usize = 0;
    fn reset() void {
        child_count_calls = 0;
        child_at_calls = 0;
        has_children_calls = 0;
        key_of_calls = 0;
        text_of_calls = 0;
    }
    fn childCount(_: ?*anyopaque, node: widgets.TreeNode) usize {
        child_count_calls += 1;
        if (node == .root) return 1000;
        return 1000;
    }
    fn childAt(_: ?*anyopaque, node: widgets.TreeNode, i: usize) widgets.TreeNode {
        child_at_calls += 1;
        if (node == .root) return @fromBackingInt(@as(u64, i + 1));
        return @fromBackingInt(@as(u64, @backingInt(node)) * 1000 + i + 1);
    }
    fn hasChildren(_: ?*anyopaque, node: widgets.TreeNode) bool {
        has_children_calls += 1;
        _ = node;
        return true;
    }
    fn keyOf(_: ?*anyopaque, node: widgets.TreeNode) widgets.ItemKey {
        key_of_calls += 1;
        return @backingInt(node);
    }
    fn textOf(_: ?*anyopaque, _: widgets.TreeNode) []const u8 {
        text_of_calls += 1;
        return "row";
    }
    fn model() widgets.TreeModel {
        return .{ .child_count = childCount, .child_at = childAt, .has_children = hasChildren, .key_of = keyOf, .text_of = textOf };
    }
};

test "AC-W-TREE-010/011 百万行展平缓存的滚动零回调与增量展开" {
    BigT.reset();
    var c = widgets.TreeController.init(std.testing.allocator, BigT.model(), .{ .mode = .multi, .initially_expanded_depth = 1 });
    defer c.deinit();
    c.setViewport(800, 660);
    c.correct();
    // 1000 个顶层 + 每个 1000 个可见子项 = 1,001,000 行。
    try std.testing.expectEqual(@as(usize, 1001000), c.rowsSlice().len);
    BigT.reset();
    c.offset = 22000;
    var frame: usize = 0;
    while (frame < 100) : (frame += 1) {
        c.offset += 22;
        const r = c.visibleRange();
        try std.testing.expect(r.last - r.first + 1 <= 40);
    }
    try std.testing.expectEqual(@as(usize, 0), BigT.child_count_calls);
    try std.testing.expectEqual(@as(usize, 0), BigT.child_at_calls);
    try std.testing.expectEqual(@as(usize, 0), BigT.has_children_calls);
    // 在 50 万附近展开一个折叠子节点：只对其调用一次 child_count、1000 次 child_at。
    const idx = 500000;
    BigT.reset();
    _ = c.toggle(idx);
    try std.testing.expectEqual(@as(usize, 1), BigT.child_count_calls);
    try std.testing.expectEqual(@as(usize, 1000), BigT.child_at_calls);
    try std.testing.expectEqual(@as(usize, 1001000 + 1000), c.rowsSlice().len);
    // 折叠后删除 1000 行且不再调用回调。
    BigT.reset();
    _ = c.toggle(idx);
    try std.testing.expectEqual(@as(usize, 1001000), c.rowsSlice().len);
    try std.testing.expectEqual(@as(usize, 0), BigT.child_at_calls);
}

test "AC-W-TABLE-014 百万行表格的行列虚拟化计量" {
    var cols: [20]widgets.TableColumn = undefined;
    var ci: usize = 0;
    while (ci < cols.len) : (ci += 1) cols[ci] = .{ .title = "x", .width = .{ .fixed = 100 } };
    var c = try widgets.TableController.init(std.testing.allocator, &cols, 1000000, .{ .mode = .multi });
    defer c.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    c.layoutColumns(arena.allocator(), 800, 1.0, 7);
    c.setViewport(800, 660);
    c.correct();
    c.row_sel.offset = 22000;
    const rows = c.rowVisibleRange();
    try std.testing.expectEqual(@as(usize, 995), rows.first);
    try std.testing.expectEqual(@as(usize, 1034), rows.last);
    const created_rows = rows.last - rows.first + 1;
    const span = c.columnSpan(0);
    try std.testing.expectEqual(@as(usize, 7), span.last_visible);
    try std.testing.expectEqual(@as(usize, 9), span.created);
    const cells = created_rows * span.created;
    try std.testing.expect(cells <= 40 * 9);
    // 与总行数无关：1 万行同一偏移下节点数相同。
    var c2 = try widgets.TableController.init(std.testing.allocator, &cols, 10000, .{ .mode = .multi });
    defer c2.deinit();
    c2.layoutColumns(arena.allocator(), 800, 1.0, 7);
    c2.setViewport(800, 660);
    c2.correct();
    c2.row_sel.offset = 22000;
    const rows2 = c2.rowVisibleRange();
    try std.testing.expectEqual(created_rows, rows2.last - rows2.first + 1);
    const span2 = c2.columnSpan(0);
    try std.testing.expectEqual(span.created, span2.created);
}

test "AC-APP-004 工作线程回投完成后恰好一帧" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    const State = struct {
        var done: bool = false;
        var builds: u32 = 0;
        fn build(_: *anyopaque, u: *ui.Ui) void {
            builds += 1;
            _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
            u.endColumn();
        }
        const Ctx = struct { app: *nano.app.App };
        fn worker(ctx: *anyopaque) void {
            const c: *Ctx = @ptrCast(@alignCast(ctx));
            std.Io.sleep(std.testing.io, .{ .nanoseconds = 20 * 1_000_000 }, .awake) catch {};
            _ = c.app.post(.{ .ctx = c.app, .func = doneFn });
        }
        fn doneFn(ctx: ?*anyopaque) void {
            const a: *nano.app.App = @ptrCast(@alignCast(ctx.?));
            done = true;
            a.invalidateAll(.build);
        }
    };
    State.done = false;
    State.builds = 0;
    var ctx: u8 = 0;
    app.renderOnce(&ctx, State.build);
    const before = State.builds;
    var job = State.Ctx{ .app = &app };
    const th = try std.Thread.spawn(.{}, State.worker, .{&job});
    // 工作线程运行期间没有轮询帧。
    try std.testing.expect(!State.done);
    try std.testing.expectEqual(before, State.builds);
    th.join();
    _ = app.pump();
    try std.testing.expect(State.done);
    app.renderOnce(&ctx, State.build);
    try std.testing.expectEqual(before + 1, State.builds);
}

test "AC-APP-020 标准编辑命令路由到焦点控件" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    const M = struct {
        var copies: u32 = 0;
        var pastes: u32 = 0;
        var id: ui.WidgetId = .none;
        fn build(_: *anyopaque, u: *ui.Ui) void {
            id = u.id(@src(), ui.Key.str("edit_target"));
            _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 100, .y = 20 } } } });
            _ = u.interact(id, .{ .sense = .{ .click = true }, .edit = .{ .copy = true, .select_all = true } });
            u.setFocusable(id, true, true);
            if (u.focusedId() != id) u.setFocus(id);
            for (u.events(id)) |ev| switch (ev) {
                .edit_command => |c| switch (c) {
                    .copy => copies += 1,
                    .paste => pastes += 1,
                    else => {},
                },
                else => {},
            };
        }
    };
    M.copies = 0;
    M.pastes = 0;
    var ctx: u8 = 0;
    app.renderOnce(&ctx, M.build);
    // Ctrl+C 命中并投递 edit_command。
    platform.Headless.injectKey(.c, true, false, .{ .ctrl = true });
    platform.Headless.injectKey(.c, false, false, .{ .ctrl = true });
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 1), M.copies);
    // Ctrl+V：未声明 paste 能力 → 被吞掉，不投递。
    platform.Headless.injectKey(.v, true, false, .{ .ctrl = true });
    platform.Headless.injectKey(.v, false, false, .{ .ctrl = true });
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), M.pastes);
    try std.testing.expectEqual(@as(u32, 1), M.copies);
}

// ---------------------------------------------------------------------------
// M5：UIA 适配器
// ---------------------------------------------------------------------------

const UiaListNames = struct {
    const names = [_][]const u8{ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" };
    fn text(_: ?*anyopaque, i: usize) []const u8 {
        return if (i < names.len) names[i] else "row";
    }
};

test "AC-W-LIST-019 列表 UIA 选择、滚动与虚拟化选择集" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .data = .{ .item_text = UiaListNames.text } });
    defer c.deinit();
    c.setViewport(800, 660, 100);
    c.correct(100);
    const uiaList = widgets.UiaList{ .ctrl = &c };
    const root = uiaList.root();
    try std.testing.expectEqual(uia.ControlType.list, root.control_type);
    try std.testing.expect(root.can_select_multiple);
    try std.testing.expect(!root.selection_required);
    const row3 = uiaList.row(3).?;
    try std.testing.expectEqual(uia.ControlType.list_item, row3.control_type);
    try std.testing.expectEqualStrings("Three", row3.name);

    // SelectionItem.Select → {3}。
    _ = uiaList.select(3);
    try expectSel(c.selectionPtr(), &.{3});
    // AddToSelection → {3,5}。
    _ = uiaList.addToSelection(5);
    try expectSel(c.selectionPtr(), &.{ 3, 5 });
    // RemoveFromSelection → {5}。
    _ = uiaList.removeFromSelection(3);
    try expectSel(c.selectionPtr(), &.{5});
    // ScrollIntoView 到行 60：最小位移。
    _ = c.scrollIntoView(0, 100);
    _ = uiaList.scrollIntoView(60);
    try std.testing.expectEqual(@as(f32, 682), c.offset);
    // Invoke → activated 恰一次。
    const inv = uiaList.invoke(5);
    try std.testing.expectEqual(@as(?usize, 5), inv.activated);
    // GetSelection 只含已创建节点：选中行 60、视口回到 0 时不返回它。
    c.selectionPtr().clear();
    try c.selectionPtr().add(3);
    try c.selectionPtr().add(60);
    c.offset = 0;
    const nodes = uiaList.selectionNodes(std.testing.allocator);
    defer std.testing.allocator.free(nodes);
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(@as(?usize, 3), nodes[0].row);

    // single：AddToSelection 等同 Select。
    var s = widgets.ListController.init(std.testing.allocator, .{ .mode = .single, .data = .{ .item_text = UiaListNames.text } });
    defer s.deinit();
    s.correct(100);
    const sui = widgets.UiaList{ .ctrl = &s };
    _ = sui.addToSelection(3);
    try expectSel(s.selectionPtr(), &.{3});
    _ = sui.addToSelection(5);
    try expectSel(s.selectionPtr(), &.{5});
}

const UiaTableCells = struct {
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        _ = row;
        return if (col == 1) "1,024" else "value";
    }
};

test "AC-W-TABLE-016 表格 UIA 网格、表头排序与单元格" {
    var c = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .data = .{ .cell_text = UiaTableCells.cell } });
    defer c.deinit();
    G1.layout(&c, 800);
    c.correct();
    const uiaTable = widgets.UiaTable{ .ctrl = &c };
    const root = uiaTable.root();
    try std.testing.expectEqual(uia.ControlType.data_grid, root.control_type);
    try std.testing.expectEqual(@as(usize, 10), root.row_count);
    try std.testing.expectEqual(@as(usize, 4), root.column_count);
    try std.testing.expect(root.row_major);
    try std.testing.expect(root.can_select_multiple);

    const headers = uiaTable.headers(std.testing.allocator);
    defer std.testing.allocator.free(headers);
    try std.testing.expectEqual(@as(usize, 4), headers.len);
    try std.testing.expectEqualStrings("名称", headers[0].name);
    try std.testing.expectEqual(uia.ControlType.header_item, headers[0].control_type);
    try std.testing.expectEqual(uia.SortDirection.none, headers[0].sort_direction.?);

    // HeaderItem.Invoke("名称") → sort_changed {0, asc}。
    const su = uiaTable.headerInvoke(0).?;
    try std.testing.expectEqual(@as(u16, 0), su.sort_changed.?.column);
    try std.testing.expectEqual(widgets.SortDir.asc, su.sort_changed.?.dir.?);
    const headers2 = uiaTable.headers(std.testing.allocator);
    defer std.testing.allocator.free(headers2);
    try std.testing.expectEqual(uia.SortDirection.ascending, headers2[0].sort_direction.?);
    // 第二次 → descending。
    _ = uiaTable.headerInvoke(0);
    const headers3 = uiaTable.headers(std.testing.allocator);
    defer std.testing.allocator.free(headers3);
    try std.testing.expectEqual(uia.SortDirection.descending, headers3[0].sort_direction.?);
    // 不可排序列无变化。
    try std.testing.expect(uiaTable.headerInvoke(3) == null);

    // GetItem(3,1) → 行 3 的“大小”单元格。
    const cell = uiaTable.cell(3, 1).?;
    try std.testing.expectEqual(uia.ControlType.data_item, cell.control_type);
    try std.testing.expectEqualStrings("1,024", cell.name);
    try std.testing.expectEqual(@as(?usize, 3), cell.row);
    try std.testing.expectEqual(@as(?u16, 1), cell.column);
    try std.testing.expectEqual(@as(u16, 1), cell.row_span);
    try std.testing.expectEqual(@as(u16, 1), cell.column_span);
    try std.testing.expect(uiaTable.cell(10, 1) == null);
    try std.testing.expect(uiaTable.cell(3, 4) == null);
    // 行 SelectionItem/Invoke。
    _ = uiaTable.select(3);
    try expectSel(c.selectionPtr(), &.{3});
    try std.testing.expectEqual(@as(?usize, 3), uiaTable.invoke(3).activated);
}

test "AC-W-TREE-013 树 UIA 展开状态、层级与操作" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var c = widgets.TreeController.init(std.testing.allocator, T1.model(0), T1.opts(.multi));
    defer c.deinit();
    c.correct();
    const uiaTree = widgets.UiaTree{ .ctrl = &c };
    const root = uiaTree.root();
    try std.testing.expectEqual(uia.ControlType.tree, root.control_type);
    try std.testing.expect(root.can_select_multiple);
    const a = uiaTree.row(0).?;
    try std.testing.expectEqual(uia.ControlType.tree_item, a.control_type);
    try std.testing.expectEqualStrings("A", a.name);
    try std.testing.expectEqual(uia.ExpandState.collapsed, a.expand_state.?);
    try std.testing.expectEqual(@as(u16, 1), a.level);

    // Expand() → 下一帧展开并 toggled 一次。
    const up = uiaTree.expand(0).?;
    try std.testing.expectEqual(@as(usize, 1), up.toggled.len);
    try std.testing.expectEqual(uia.ExpandState.expanded, uiaTree.row(0).?.expand_state.?);
    try std.testing.expectEqual(@as(u16, 2), uiaTree.row(2).?.level); // A2
    _ = uiaTree.expand(2).?;
    try std.testing.expectEqual(@as(u16, 3), uiaTree.row(3).?.level); // A2a
    // 叶子 A1 Expand() 被忽略。
    const a1_index = c.indexOfKey(@backingInt(T1.A1)).?;
    try std.testing.expect(uiaTree.expand(a1_index) == null);
    try std.testing.expectEqual(uia.ExpandState.leaf_node, uiaTree.row(a1_index).?.expand_state.?);
    // Collapse() 同理。
    _ = uiaTree.collapse(2).?;
    try std.testing.expectEqual(uia.ExpandState.collapsed, uiaTree.row(2).?.expand_state.?);
    // SelectionItem.Select 于 A2 → {A2}，不改变展开。
    _ = uiaTree.expand(2).?;
    _ = uiaTree.select(2);
    try expectSel(c.selectionPtr(), &.{@backingInt(T1.A2)});
    try std.testing.expectEqual(uia.ExpandState.expanded, uiaTree.row(2).?.expand_state.?);
    // Invoke 叶子 → activated；有子项 → 切换展开。
    const leaf_invoke = uiaTree.invoke(a1_index).?;
    try std.testing.expectEqual(@as(?widgets.TreeNode, T1.A1), leaf_invoke.activated);
    const parent_invoke = uiaTree.invoke(2).?;
    try std.testing.expectEqual(@as(?widgets.TreeNode, null), parent_invoke.activated);
    try std.testing.expectEqual(@as(usize, 1), parent_invoke.toggled.len);
    // 折叠 A。
    _ = uiaTree.collapse(0).?;
    try std.testing.expectEqual(uia.ExpandState.collapsed, uiaTree.row(0).?.expand_state.?);
}

const TooltipRows = struct {
    const rows = [_][]const u8{ "short", "tiny", "ok", "非常长的文件名.txt" };
    fn text(_: ?*anyopaque, i: usize) []const u8 {
        return if (i < rows.len) rows[i] else "";
    }
};

test "AC-W-LIST-021 列表截断提示框与悬停计时" {
    var c = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .data = .{ .item_text = TooltipRows.text } });
    defer c.deinit();
    c.setViewport(120, 220, 10);
    c.correct(10);
    c.pointerHover(3, 0);
    try std.testing.expect(c.tooltip(399, 400, true) == null);
    const tip = c.tooltip(400, 400, true).?;
    try std.testing.expectEqualStrings("非常长的文件名.txt", tip.text);
    try std.testing.expectEqual(@as(usize, 3), tip.index);
    try std.testing.expectEqual(@as(f32, 66), tip.anchor.y);
    try std.testing.expectEqual(@as(f32, 22), tip.anchor.h);
    // 未截断：无提示框。
    try std.testing.expect(c.tooltip(1000, 400, false) == null);
    // 滚动进行中清除提示框。
    _ = c.wheel(-1, 10, .{ .lines = 1 }, .{});
    try std.testing.expect(c.tooltip(1000, 400, true) == null);
    // tooltip_on_truncate = false。
    var c2 = widgets.ListController.init(std.testing.allocator, .{ .mode = .multi, .tooltip_on_truncate = false, .data = .{ .item_text = TooltipRows.text } });
    defer c2.deinit();
    c2.correct(10);
    c2.pointerHover(3, 0);
    try std.testing.expect(c2.tooltip(1000, 400, true) == null);
}

const TableTooltipCells = struct {
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        if (row == 2 and col == 0) return "非常长的文件名称示例.txt";
        return "short";
    }
};

test "AC-W-TABLE-017 单元格与表头截断提示框" {
    var c = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .data = .{ .cell_text = TableTooltipCells.cell } });
    defer c.deinit();
    G1.layout(&c, 800);
    c.setViewport(800, 660);
    c.correct();
    c.pointerHoverCell(2, 0, 0);
    try std.testing.expect(c.cellTooltip(399, 400, true) == null);
    const tip = c.cellTooltip(400, 400, true).?;
    try std.testing.expectEqualStrings("非常长的文件名称示例.txt", tip.text);
    try std.testing.expectEqual(@as(usize, 2), tip.row);
    try std.testing.expectEqual(@as(u16, 0), tip.column);
    try std.testing.expectEqual(@as(f32, 0), tip.anchor.x);
    try std.testing.expectEqual(@as(f32, 44), tip.anchor.y);
    try std.testing.expectEqual(@as(f32, 480), tip.anchor.w);
    // 列宽收窄后锚点跟随。
    c.user_widths[0] = 80;
    G1.layout(&c, 800);
    const narrow = c.cellTooltip(401, 400, true).?;
    try std.testing.expectEqual(@as(f32, 80), narrow.anchor.w);
    // 未截断 / 关闭提示。
    try std.testing.expect(c.cellTooltip(1000, 400, false) == null);
    // 表头标题提示。
    c.clearHover();
    c.pointerHoverHeader(3, 0);
    const ht = c.headerTooltip(400, 400, true).?;
    try std.testing.expectEqualStrings("修改日期", ht.text);
    try std.testing.expectEqual(@as(u16, 3), ht.column);
    try std.testing.expectEqual(@as(f32, 140), ht.anchor.w);
    // 调整列宽进行中不显示。
    _ = c.headerPress(477);
    c.headerDrag(470);
    try std.testing.expect(c.headerTooltip(1000, 400, true) == null);
    try std.testing.expect(c.cellTooltip(1000, 400, true) == null);
    // 滚动清除。
    c.cancelResize();
    c.pointerHoverCell(2, 0, 0);
    _ = c.wheel(-1, .{ .lines = 1 }, .{});
    try std.testing.expect(c.cellTooltip(1000, 400, true) == null);
    // tooltip_on_truncate = false。
    var c2 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .tooltip_on_truncate = false, .data = .{ .cell_text = TableTooltipCells.cell } });
    defer c2.deinit();
    G1.layout(&c2, 800);
    c2.correct();
    c2.pointerHoverCell(2, 0, 0);
    try std.testing.expect(c2.cellTooltip(1000, 400, true) == null);
}

const AutoFitCells = struct {
    var long_row: ?usize = null;
    var empty: bool = false;
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        if (empty) return "";
        if (col == 2 and (long_row == null or row == long_row.?)) return "应用程序扩展";
        return "x";
    }
};

test "AC-W-TABLE-006 双击列边界自适应可见行内容" {
    AutoFitCells.long_row = null;
    AutoFitCells.empty = false;
    var c = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .data = .{ .cell_text = AutoFitCells.cell } });
    defer c.deinit();
    G1.layout(&c, 800);
    c.setViewport(800, 220);
    c.correct();
    const u = c.autoFitColumn(2, 7).?;
    try std.testing.expectEqual(@as(u16, 2), u.column_resized.?.column);
    try std.testing.expectEqual(@as(f32, 58), u.column_resized.?.width);
    try std.testing.expectEqual(@as(f32, 58), c.widths[2]);
    // 双击边界（“类型”右端 [655,660)）。
    var c2 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .data = .{ .cell_text = AutoFitCells.cell } });
    defer c2.deinit();
    G1.layout(&c2, 800);
    c2.setViewport(800, 220);
    c2.correct();
    const dbl = c2.doubleClickBoundary(657, 7).?;
    try std.testing.expectEqual(@as(f32, 58), dbl.column_resized.?.width);
    // cell_text 为空：只取表头自然宽 50。
    AutoFitCells.empty = true;
    var c3 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 10, .{ .mode = .multi, .data = .{ .cell_text = AutoFitCells.cell } });
    defer c3.deinit();
    G1.layout(&c3, 800);
    c3.setViewport(800, 220);
    c3.correct();
    try std.testing.expectEqual(@as(f32, 50), c3.autoFitColumn(2, 7).?.column_resized.?.width);
    AutoFitCells.empty = false;
    // 缓冲行中的长文字不计入；滚入视口后才计入。
    AutoFitCells.long_row = 15;
    var c4 = try widgets.TableController.init(std.testing.allocator, &G1.columns, 20, .{ .mode = .multi, .data = .{ .cell_text = AutoFitCells.cell } });
    defer c4.deinit();
    G1.layout(&c4, 800);
    c4.setViewport(800, 220);
    c4.correct();
    try std.testing.expectEqual(@as(f32, 50), c4.autoFitColumn(2, 7).?.column_resized.?.width);
    c4.row_sel.offset = 330; // 行 15 进入视口。
    c4.user_widths[2] = 0;
    try std.testing.expectEqual(@as(f32, 58), c4.autoFitColumn(2, 7).?.column_resized.?.width);
    AutoFitCells.long_row = null;
    // max = 55 夹紧。
    var cols = G1.columns;
    cols[2].max = 55;
    var c5 = try widgets.TableController.init(std.testing.allocator, &cols, 10, .{ .mode = .multi, .data = .{ .cell_text = AutoFitCells.cell } });
    defer c5.deinit();
    G1.layout(&c5, 800);
    c5.setViewport(800, 220);
    c5.correct();
    try std.testing.expectEqual(@as(f32, 55), c5.autoFitColumn(2, 7).?.column_resized.?.width);
    // 不可调整列无变化。
    var cols2 = G1.columns;
    cols2[3].resizable = false;
    var c6 = try widgets.TableController.init(std.testing.allocator, &cols2, 10, .{ .mode = .multi, .data = .{ .cell_text = AutoFitCells.cell } });
    defer c6.deinit();
    G1.layout(&c6, 800);
    c6.setViewport(800, 220);
    c6.correct();
    try std.testing.expect(c6.autoFitColumn(3, 7) == null);
}

const ListDamageModel = struct {
    sel: widgets.Selection,
    alternate: bool = false,
    fn init(allocator: std.mem.Allocator) ListDamageModel {
        return .{ .sel = widgets.Selection.init(allocator) };
    }
    fn deinit(self: *ListDamageModel) void {
        self.sel.deinit();
    }
};

fn listDamageBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *ListDamageModel = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    var it = widgets.beginList(u, @src(), 100000, .{
        .key = ui.Key.str("damage-list"),
        .debug_name = "damage-list",
        .mode = .multi,
        .selection = &m.sel,
        .alternate_rows = m.alternate,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    while (it.next()) |row| widgets.listLabel(u, @src(), row, "row", .{});
    _ = widgets.endList(u, &it);
    u.endColumn();
}

test "AC-W-LIST-018 列表悬停/选择损伤计量" {
    var m = ListDamageModel.init(std.testing.allocator);
    defer m.deinit();
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 420, .h = 660 } });
    defer app.deinit();
    app.renderOnce(&m, listDamageBuild);
    // 第二帧稳定。
    app.renderOnce(&m, listDamageBuild);
    const list_node = findByName(app.ui_state.current_root, "damage-list") orelse return error.TestUnexpectedResult;
    const row_h: i32 = 22;
    const row_area: i64 = @as(i64, list_node.abs.w) * row_h;
    const frames0 = app.frames;
    // 悬停行 5：仅绘制，不构建。
    const y5 = list_node.abs.y + 5 * row_h + row_h / 2;
    platform.Headless.injectMouseMove(.{ .x = list_node.abs.x + 20, .y = y5 }, .{});
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(app.ui_state.last_damage_area <= row_area);
    // 移出：同样只绘制。
    platform.Headless.injectMouseMove(.{ .x = -5, .y = -5 }, .{});
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(app.ui_state.last_damage_area <= row_area);
    // 单击行 3：选择 {3}，损伤 ≤ 2 行。
    const y3 = list_node.abs.y + 3 * row_h + row_h / 2;
    const x = list_node.abs.x + 20;
    platform.Headless.injectMouseMove(.{ .x = x, .y = y3 }, .{});
    _ = app.step();
    platform.Headless.injectMouseButton(.left, true, .{ .x = x, .y = y3 }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = x, .y = y3 }, .{});
    _ = app.step();
    try expectSel(&m.sel, &.{3});
    try std.testing.expect(app.ui_state.last_damage_area <= row_area * 2);
    // Shift+单击行 7：区间 {3..7}，损伤为变化的 4 行。
    const y7 = list_node.abs.y + 7 * row_h + row_h / 2;
    platform.Headless.injectMouseMove(.{ .x = x, .y = y7 }, .{});
    _ = app.step();
    platform.Headless.injectMouseButton(.left, true, .{ .x = x, .y = y7 }, .{ .shift = true });
    platform.Headless.injectMouseButton(.left, false, .{ .x = x, .y = y7 }, .{ .shift = true });
    _ = app.step();
    try expectSel(&m.sel, &.{ 3, 4, 5, 6, 7 });
    try std.testing.expect(app.ui_state.last_damage_area <= row_area * 5);
    // 相同参数 invalidate(.build)：损伤为空、不提交新帧。
    const frames_before = app.frames;
    app.ui_state.invalidate(.build);
    _ = app.step();
    try std.testing.expectEqual(@as(i64, 0), app.ui_state.last_damage_area);
    try std.testing.expectEqual(frames_before, app.frames);
    _ = frames0;
}

const TableDamageCells = struct {
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        _ = row;
        return if (col == 0) "name" else if (col == 1) "1,024" else if (col == 2) "file" else "2026-11-12";
    }
};

fn tableDamageBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const sel: *widgets.Selection = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    var it = widgets.beginTable(u, @src(), &G1.columns, 12, .{
        .key = ui.Key.str("damage-table"),
        .debug_name = "damage-table",
        .mode = .multi,
        .selection = sel,
        .data = .{ .cell_text = TableDamageCells.cell },
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    while (it.next()) |row| {
        var cells = row.cells();
        while (cells.next()) |cell| widgets.tableCellText(u, @src(), cell, TableDamageCells.cell(null, row.index, cell.column), .{});
    }
    _ = widgets.endTable(u);
    u.endColumn();
}

test "AC-W-TABLE-015 表格悬停/选择损伤计量" {
    var sel = widgets.Selection.init(std.testing.allocator);
    defer sel.deinit();
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 500, .h = 300 } });
    defer app.deinit();
    app.renderOnce(&sel, tableDamageBuild);
    app.renderOnce(&sel, tableDamageBuild);
    const table_node = findByName(app.ui_state.current_root, "damage-table") orelse return error.TestUnexpectedResult;
    const row_h: i32 = 22;
    const row_area: i64 = @as(i64, table_node.abs.w) * row_h;
    // 悬停行 5。
    const y5 = table_node.abs.y + 5 * row_h + row_h / 2;
    platform.Headless.injectMouseMove(.{ .x = table_node.abs.x + 20, .y = y5 }, .{});
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(app.ui_state.last_damage_area <= row_area);
    // 移出。
    platform.Headless.injectMouseMove(.{ .x = -5, .y = -5 }, .{});
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    // 悬停表头（“类型”列附近）。
    platform.Headless.injectMouseMove(.{ .x = table_node.abs.x + 300, .y = table_node.abs.y - 12 }, .{});
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(app.ui_state.last_damage_area <= 200 * 24);
    // 单击行 3。
    const x = table_node.abs.x + 20;
    const y3 = table_node.abs.y + 3 * row_h + row_h / 2;
    platform.Headless.injectMouseMove(.{ .x = x, .y = y3 }, .{});
    _ = app.step();
    platform.Headless.injectMouseButton(.left, true, .{ .x = x, .y = y3 }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = x, .y = y3 }, .{});
    _ = app.step();
    try expectSel(&sel, &.{3});
    try std.testing.expect(app.ui_state.last_damage_area <= row_area * 2);
    // Shift+单击行 7。
    const y7 = table_node.abs.y + 7 * row_h + row_h / 2;
    platform.Headless.injectMouseMove(.{ .x = x, .y = y7 }, .{});
    _ = app.step();
    platform.Headless.injectMouseButton(.left, true, .{ .x = x, .y = y7 }, .{ .shift = true });
    platform.Headless.injectMouseButton(.left, false, .{ .x = x, .y = y7 }, .{ .shift = true });
    _ = app.step();
    try expectSel(&sel, &.{ 3, 4, 5, 6, 7 });
    try std.testing.expect(app.ui_state.last_damage_area <= row_area * 5);
    // 相同 invalidate(.build) → 空损伤、不提交。
    const frames_before = app.frames;
    app.ui_state.invalidate(.build);
    _ = app.step();
    try std.testing.expectEqual(@as(i64, 0), app.ui_state.last_damage_area);
    try std.testing.expectEqual(frames_before, app.frames);
}

const TreeAnimCtx = struct {
    exp: widgets.ExpandedSet,
    fn init(allocator: std.mem.Allocator) TreeAnimCtx {
        return .{ .exp = widgets.ExpandedSet.init(allocator) };
    }
    fn deinit(self: *TreeAnimCtx) void {
        self.exp.deinit();
    }
};

fn treeAnimBuild(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *TreeAnimCtx = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    var it = widgets.beginTree(u, @src(), T1.model(0), .{
        .key = ui.Key.str("anim-tree"),
        .debug_name = "anim-tree",
        .expanded = &m.exp,
        .layout = .{ .main = .{ .grow = 1 }, .cross = .fill },
    });
    while (it.next()) |row| widgets.treeLabel(u, @src(), row, T1.nameOf(row.node), .{});
    _ = widgets.endTree(u);
    u.endColumn();
}

fn doubleClick(w: *platform.Window, x: i32, y: i32) void {
    _ = w;
    platform.Headless.injectMouseMove(.{ .x = x, .y = y }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = x, .y = y }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = x, .y = y }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = x, .y = y }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = x, .y = y }, .{});
}

test "AC-W-TREE-009 树箭头旋转动画、假时钟与关闭动画" {
    T1.loading_b = false;
    T1.b_child_count = 1;
    var m = TreeAnimCtx.init(std.testing.allocator);
    defer m.deinit();
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 220 } });
    defer app.deinit();
    platform.Headless.setMetrics(.{ .client_animation = true });
    app.renderOnce(&m, treeAnimBuild);
    const tree_node = findByName(app.ui_state.current_root, "anim-tree") orelse return error.TestUnexpectedResult;
    const arrow0 = findByName(app.ui_state.current_root, "tree-arrow") orelse return error.TestUnexpectedResult;
    const arrow_id = arrow0.id;
    try std.testing.expectEqual(@as(f32, 0), app.ui_state.animationCurrent(arrow_id, 0).?);
    try std.testing.expect(!app.ui_state.haveActiveAnimations());
    const x = tree_node.abs.x + 20;
    const y = tree_node.abs.y + 11;
    // 展开 A：动画从 0 开始。
    doubleClick(app.window, x, y);
    _ = app.step();
    _ = app.step(); // 展开产生的同帧第二遍布的后续构建遍
    const arrow1 = findByName(app.ui_state.current_root, "tree-arrow") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(arrow_id, arrow1.id);
    try std.testing.expectEqual(@as(f32, 0), app.ui_state.animationCurrent(arrow_id, 0).?);
    try std.testing.expect(app.ui_state.haveActiveAnimations());
    // 60 ms：角度在 (0, 90°) 内，构建遍数 0，损伤 ≤ 箭头位面积。
    platform.Headless.advanceMs(60);
    _ = app.step();
    const mid = app.ui_state.animationCurrent(arrow_id, 0).?;
    try std.testing.expect(mid > 0 and mid < std.math.pi * 0.5);
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(app.ui_state.last_damage_area <= 16 * 22);
    // 120 ms：到达 90°，动画结束。
    platform.Headless.advanceMs(60);
    _ = app.step();
    try std.testing.expectApproxEqAbs(std.math.pi * 0.5, app.ui_state.animationCurrent(arrow_id, 0).?, 0.001);
    try std.testing.expect(!app.ui_state.haveActiveAnimations());
    // 折叠：90° → 0°（先越过系统双击间隔，避免形成三击）。
    platform.Headless.advanceMs(600);
    doubleClick(app.window, x, y);
    _ = app.step();
    try std.testing.expect(app.ui_state.haveActiveAnimations());
    platform.Headless.advanceMs(120);
    _ = app.step();
    try std.testing.expectApproxEqAbs(@as(f32, 0), app.ui_state.animationCurrent(arrow_id, 0).?, 0.001);
    // client_animation = false：同帧到位，无活动动画。
    platform.Headless.setMetrics(.{ .client_animation = false });
    platform.Headless.advanceMs(600);
    doubleClick(app.window, x, y);
    _ = app.step();
    try std.testing.expect(!app.ui_state.haveActiveAnimations());
    try std.testing.expectApproxEqAbs(std.math.pi * 0.5, app.ui_state.animationCurrent(arrow_id, 0).?, 0.001);

    // 滚动进入视野的已展开行：首帧直接为 90°，不登记动画。
    platform.Headless.setMetrics(.{ .client_animation = true });
    var m2 = TreeAnimCtx.init(std.testing.allocator);
    defer m2.deinit();
    m2.exp.set(@backingInt(T1.A), true, null) catch {};
    var app2 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 220 } });
    defer app2.deinit();
    app2.renderOnce(&m2, treeAnimBuild);
    const arrow2 = findByName(app2.ui_state.current_root, "tree-arrow") orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(std.math.pi * 0.5, app2.ui_state.animationCurrent(arrow2.id, 0).?, 0.001);
    try std.testing.expect(!app2.ui_state.haveActiveAnimations());
}

fn fnBody(src_text: []const u8, name: []const u8) ?[]const u8 {
    var buf: [96]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "fn {s}(", .{name}) catch return null;
    const at = std.mem.indexOf(u8, src_text, needle) orelse return null;
    const open = std.mem.indexOfScalarPos(u8, src_text, at, '{') orelse return null;
    var depth: usize = 0;
    var i = open;
    while (i < src_text.len) : (i += 1) {
        if (src_text[i] == '{') depth += 1;
        if (src_text[i] == '}') {
            depth -= 1;
            if (depth == 0) return src_text[open + 1 .. i];
        }
    }
    return null;
}

test "AC-APP-028 示例静态检查与 force-rebuild 画面一致" {
    if (!std.mem.eql(u8, text.backend_name, "fixed")) return error.SkipZigTest;
    // 1) 扫描示例构建函数：不得无条件 invalidate / 用 timer 轮询变更。
    const io = std.testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, "examples", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(std.testing.allocator);
    defer walker.deinit();
    var scanned: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const src_text = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .unlimited);
        defer std.testing.allocator.free(src_text);
        scanned += 1;
        for ([_][]const u8{ "build", "page" }) |fn_name| {
            if (fnBody(src_text, fn_name)) |body| {
                try std.testing.expect(std.mem.indexOf(u8, body, "invalidate(") == null);
                try std.testing.expect(std.mem.indexOf(u8, body, ".timer(") == null);
            }
        }
        // 模型变更方法必须以 changed() 结尾。
        if (std.mem.endsWith(u8, entry.basename, "gallery.zig")) {
            for ([_][]const u8{ "setStatus", "toggleDark", "bumpClicks", "resetAll", "applyBulk" }) |m| {
                const body = fnBody(src_text, m) orelse return error.TestUnexpectedResult;
                try std.testing.expect(std.mem.indexOf(u8, body, "changed()") != null);
            }
        }
    }
    try std.testing.expect(scanned >= 3);

    // 2) 批量变更只调用一次 changed()。
    var m = try gallery.Model.init(std.testing.allocator);
    defer m.deinit();
    const rev = m.revision;
    m.applyBulk(7);
    try std.testing.expectEqual(rev + 1, m.revision);
    for (m.items) |v| try std.testing.expectEqual(@as(u16, 7), v);

    // 3) 同一场景在正常构建与 force-rebuild 下逐帧画面一致。
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 960, .h = 760 }, .title = "app028" });
    defer app.deinit();
    app.renderOnce(&m, gallery.build);
    const normal = try std.testing.allocator.dupe(u8, app.surface.pixels);
    defer std.testing.allocator.free(normal);
    app.ui_state.force_rebuild = true;
    app.renderOnce(&m, gallery.build);
    try std.testing.expectEqualSlices(u8, normal, app.surface.pixels);
    // 第二批：正常模式继续渲染，同一模型状态画面仍一致。
    app.ui_state.force_rebuild = false;
    app.renderOnce(&m, gallery.build);
    try std.testing.expectEqualSlices(u8, normal, app.surface.pixels);
}

const NativeTestCtx = struct {
    app: *nano.app.App,
    build_error: ?anyerror = null,
    got_paths: ?[]const platform.Path = null,
    got_style: ?text.Style = null,
    got_task: ?platform.TaskResult = null,
    calls: u32 = 0,
    fn build(ctx: *anyopaque, u: *ui.Ui) void {
        const c: *NativeTestCtx = @ptrCast(@alignCast(ctx));
        _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
        u.endColumn();
        if (c.build_error == null) {
            c.app.native.openFile(c.app.window, .{}, c, paths_cb) catch |e| {
                c.build_error = e;
            };
        }
    }
    fn paths_cb(ctx: *anyopaque, paths: ?[]const platform.Path) void {
        const c: *NativeTestCtx = @ptrCast(@alignCast(ctx));
        c.got_paths = paths;
        c.calls += 1;
    }
    fn style_cb(ctx: *anyopaque, style: ?text.Style) void {
        const c: *NativeTestCtx = @ptrCast(@alignCast(ctx));
        c.got_style = style;
        c.calls += 1;
    }
    fn task_cb(ctx: *anyopaque, result: platform.TaskResult) void {
        const c: *NativeTestCtx = @ptrCast(@alignCast(ctx));
        c.got_task = result;
        c.calls += 1;
    }
    fn after(ctx: ?*anyopaque) void {
        const c: *NativeTestCtx = @ptrCast(@alignCast(ctx.?));
        c.app.native.openFile(c.app.window, .{ .multi = true }, c, paths_cb) catch {};
        c.app.native.pickFont(c.app.window, .{}, c, style_cb) catch {};
        c.app.native.taskDialog(c.app.window, .{}, c, task_cb) catch {};
    }
};

test "AC-APP-014 原生对话框仅帧后调用、假结果与回调" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    const paths = [_][]const u8{ "C:\\a b\\c.txt", "C:\\d.txt" };
    platform.Headless.setFileDialogResult(&paths);
    platform.Headless.setFontChoice(.{ .family = "Segoe UI", .size_lpx = 12, .weight = 400, .italic = false });
    platform.Headless.setTaskResult(.{ .button = null });
    var ctx = NativeTestCtx{ .app = &app };
    // 构建函数内调用：返回 NotInAfterFrame。
    app.renderOnce(&ctx, NativeTestCtx.build);
    try std.testing.expectEqual(@as(?anyerror, error.NotInAfterFrame), ctx.build_error);
    // 帧后调用：回调收到深拷贝的路径及转换后的字体/任务结果。
    app.ui_state.afterFrame(.{ .ctx = &ctx, .func = NativeTestCtx.after });
    app.ui_state.invalidate(.paint);
    _ = app.step();
    try std.testing.expectEqual(@as(u32, 3), ctx.calls);
    try std.testing.expectEqual(@as(usize, 2), ctx.got_paths.?.len);
    try std.testing.expectEqualStrings("C:\\a b\\c.txt", ctx.got_paths.?[0]);
    try std.testing.expectEqual(@as(f32, 12), ctx.got_style.?.size);
    try std.testing.expectEqual(@as(u16, 400), ctx.got_style.?.weight);
    try std.testing.expect(!ctx.got_style.?.italic);
    try std.testing.expect(ctx.got_task.?.button == null);
    // 回调返回后产生 1 个 build 帧。
    const passes_before = app.ui_state.build_passes;
    _ = app.step();
    try std.testing.expect(app.ui_state.build_passes > passes_before);
}

test "AC-PLAT-036 降级后端通用对话框返回 Unsupported" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    platform.Headless.setFileDialogResult(null);
    platform.Headless.setFontChoice(null);
    platform.Headless.setTaskResult(null);
    try std.testing.expectError(error.Unsupported, platform.dialogs.openFileList(.{}));
    try std.testing.expectError(error.Unsupported, platform.dialogs.pickFolderPath());
    try std.testing.expectError(error.Unsupported, platform.dialogs.pickFontChoice());
    try std.testing.expectError(error.Unsupported, platform.dialogs.taskResult());
    // 非 Windows 后端设置深色标题栏也不支持。
    const w = try platform.createWindow(.{ .title = "p36" });
    try std.testing.expectError(error.Unsupported, w.setDarkTitleBar(true));
}

test "AC-PLAT-039 OLE 拖放目标序列与载荷深拷贝" {
    var target = platform.DropTarget.init(std.testing.allocator);
    defer target.deinit();
    var src_paths = [_][]const u8{ "C:\\a.txt", "C:\\b c.txt" };
    var src_text = [_]u8{ 'h', 'e', 'l', 'l', 'o' };
    try std.testing.expectEqual(platform.DropEffect.none, target.dragEnter(&src_paths, &src_text));
    target.setDropEffect(.copy);
    try std.testing.expectEqual(platform.DropEffect.copy, target.dragOver(.{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(platform.DropEffect.copy, target.dragOver(.{ .x = 20, .y = 10 }));
    const payload = try target.drop(&src_paths, &src_text);
    // Drop 返回后修改源数据，载荷仍保持原值。
    @memset(&src_text, 'x');
    src_paths[0] = "MUTATED";
    try std.testing.expectEqual(@as(usize, 2), payload.paths.len);
    try std.testing.expectEqualStrings("C:\\a.txt", payload.paths[0]);
    try std.testing.expectEqualStrings("C:\\b c.txt", payload.paths[1]);
    try std.testing.expectEqualStrings("hello", payload.text.?);
    // 10 001 个路径只保留 10 000 个。
    const many = try std.testing.allocator.alloc([]const u8, 10001);
    defer std.testing.allocator.free(many);
    for (many, 0..) |*p, i| p.* = try std.fmt.allocPrint(std.testing.allocator, "p{d}", .{i});
    defer for (many) |p| std.testing.allocator.free(p);
    const big = try target.drop(many, null);
    try std.testing.expectEqual(@as(usize, 10000), big.paths.len);
    try std.testing.expect(target.truncated);
}

test "AC-PLAT-049 GLFW 降级矩阵逐行" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const drag_window = try platform.createWindow(.{ .title = "matrix" });
    for (std.enums.values(platform.Capability)) |cap| {
        const expected: platform.Support = switch (cap) {
            .process_init, .window_creation, .close_request, .message_loop, .mouse_key, .clock, .clipboard, .monitors, .gl_context, .vsync => .full,
            .per_window_scale, .placement, .nested_frame, .mouse_capture, .keyboard_text, .ime, .cursor_shape, .metrics, .appearance, .ole_drop, .popup_window => .degraded,
            .dark_title_bar, .session_power, .dialogs, .tray, .context_loss => .unsupported,
        };
        try std.testing.expectEqual(expected, platform.supportFor(cap));
        switch (expected) {
            .unsupported => {
                // 对应能力在降级后端必须有明确的 Unsupported 出口。
                switch (cap) {
                    .dialogs => try std.testing.expectError(error.Unsupported, platform.dialogs.openFileList(.{})),
                    .tray => {},
                    .dark_title_bar, .session_power, .context_loss => {},
                    else => {},
                }
            },
            .degraded => {
                switch (cap) {
                    .ole_drop => try std.testing.expectError(error.Unsupported, platform.startDrag(drag_window, .{}, .{})),
                    else => {},
                }
            },
            .full => {},
        }
    }
}

test "AC-PLAT-030 无头剪贴板换行规范化、自定义格式与序列号" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    try platform.clipboard.setText("a\nb\r\nc\rd");
    const got = (try platform.clipboard.getText(std.testing.allocator)).?;
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("a\nb\nc\nd", got);
    try std.testing.expect(platform.clipboard.hasText());
    const seq0 = platform.clipboard.sequenceNumber();
    const fmt = try platform.clipboard.registerFormat("application/x-nano-test");
    const items = [_]platform.ClipItem{
        .{ .text = "line1\r\nline2" },
        .{ .data = .{ .format = fmt, .bytes = "payload" } },
    };
    try platform.clipboard.setMany(&items);
    try std.testing.expect(platform.clipboard.sequenceNumber() > seq0);
    const text2 = (try platform.clipboard.getText(std.testing.allocator)).?;
    defer std.testing.allocator.free(text2);
    try std.testing.expectEqualStrings("line1\nline2", text2);
    const custom = (try platform.clipboard.getData(fmt, std.testing.allocator)).?;
    defer std.testing.allocator.free(custom);
    try std.testing.expectEqualStrings("payload", custom);
    // 同一名称注册返回同一格式。
    try std.testing.expectEqual(fmt, try platform.clipboard.registerFormat("application/x-nano-test"));
}

const FakeGl = struct {
    var begins: usize = 0;
    var ends: usize = 0;
    var presents: usize = 0;
    var fills: usize = 0;
    var reads: usize = 0;
    var resizes: usize = 0;
    var deinits: usize = 0;
    var last_damage: core.RectI = .{};
    var last_scale: f32 = 0;
    fn begin(_: *anyopaque, damage: core.RectI, scale: f32) void {
        begins += 1;
        last_damage = damage;
        last_scale = scale;
    }
    fn end(_: *anyopaque) void {
        ends += 1;
    }
    fn present(_: *anyopaque) void {
        presents += 1;
    }
    fn resize(_: *anyopaque, _: u32, _: u32, _: f32) void {
        resizes += 1;
    }
    fn read(_: *anyopaque, _: core.RectI, out: []u8) bool {
        reads += 1;
        @memset(out, 0x7f);
        return true;
    }
    fn deinit(_: *anyopaque) void {
        deinits += 1;
    }
    fn fill(_: *anyopaque, _: core.Rect, _: core.Color) void {
        fills += 1;
    }
    fn fillV(_: *anyopaque, _: core.Rect, _: core.Color, _: core.Color) void {}
    fn fillRound(_: *anyopaque, _: core.Rect, _: f32, _: core.Color) void {}
    fn fillRoundV(_: *anyopaque, _: core.Rect, _: f32, _: core.Color, _: core.Color) void {}
    fn strokeRect(_: *anyopaque, _: core.Rect, _: core.Color, _: i32) void {}
    fn strokeRound(_: *anyopaque, _: core.Rect, _: f32, _: core.Color, _: i32) void {}
    fn strokeLine(_: *anyopaque, _: core.Vec2, _: core.Vec2, _: core.Color, _: i32) void {}
    fn pushClip(_: *anyopaque, _: core.Rect) void {}
    fn popClip(_: *anyopaque) void {}
    fn translate(_: *anyopaque, _: f32, _: f32) void {}
    fn popTransform(_: *anyopaque) void {}
};

test "REQ-GFX-004 REQ-GFX-028 GL Surface 生命周期与损伤/呈现路由" {
    FakeGl.begins = 0;
    FakeGl.ends = 0;
    FakeGl.presents = 0;
    FakeGl.fills = 0;
    FakeGl.reads = 0;
    FakeGl.resizes = 0;
    FakeGl.deinits = 0;
    var token: u8 = 0;
    var surface = gfx.Surface.initGl(std.testing.allocator, 100, 80, 1.0, .{
        .ctx = &token,
        .canvas = .{
            .ctx = &token,
            .fill_rect = FakeGl.fill,
            .fill_rect_v = FakeGl.fillV,
            .fill_round_rect = FakeGl.fillRound,
            .fill_round_rect_v = FakeGl.fillRoundV,
            .stroke_rect = FakeGl.strokeRect,
            .stroke_round_rect = FakeGl.strokeRound,
            .stroke_line = FakeGl.strokeLine,
            .push_clip = FakeGl.pushClip,
            .pop_clip = FakeGl.popClip,
            .push_translate = FakeGl.translate,
            .pop_transform = FakeGl.popTransform,
        },
        .begin = FakeGl.begin,
        .end = FakeGl.end,
        .present = FakeGl.present,
        .resize = FakeGl.resize,
        .read = FakeGl.read,
        .deinit = FakeGl.deinit,
    });
    const canvas = surface.beginFrame(.{ .x = 5, .y = 6, .w = 20, .h = 10 }, 1.0);
    canvas.fillRect(.{ .x = 0, .y = 0, .w = 10, .h = 10 }, .{ .r = 1, .g = 2, .b = 3, .a = 255 });
    surface.endFrame();
    surface.present();
    var out: [20 * 10 * 4]u8 = undefined;
    try surface.readPixels(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .target, &out);
    try std.testing.expectEqual(@as(usize, 1), FakeGl.begins);
    try std.testing.expectEqual(@as(usize, 1), FakeGl.ends);
    try std.testing.expectEqual(@as(usize, 1), FakeGl.presents);
    try std.testing.expectEqual(@as(usize, 1), FakeGl.fills);
    try std.testing.expectEqual(@as(usize, 1), FakeGl.reads);
    try std.testing.expectEqual(@as(f32, 1.0), FakeGl.last_scale);
    try std.testing.expectEqual(core.RectI{ .x = 5, .y = 6, .w = 20, .h = 10 }, FakeGl.last_damage);
    surface.resize(.{ .w = 200, .h = 160 });
    try std.testing.expectEqual(@as(usize, 1), FakeGl.resizes);
    surface.deinit();
    try std.testing.expectEqual(@as(usize, 1), FakeGl.deinits);
}

test "AC-GFX-004 GL Surface 内容有效性与 resize/scale 失效" {
    FakeGl.begins = 0;
    FakeGl.presents = 0;
    var token: u8 = 0;
    var surface = gfx.Surface.initGl(std.testing.allocator, 100, 80, 1.0, .{
        .ctx = &token,
        .canvas = .{
            .ctx = &token,
            .fill_rect = FakeGl.fill,
            .fill_rect_v = FakeGl.fillV,
            .fill_round_rect = FakeGl.fillRound,
            .fill_round_rect_v = FakeGl.fillRoundV,
            .stroke_rect = FakeGl.strokeRect,
            .stroke_round_rect = FakeGl.strokeRound,
            .stroke_line = FakeGl.strokeLine,
            .push_clip = FakeGl.pushClip,
            .pop_clip = FakeGl.popClip,
            .push_translate = FakeGl.translate,
            .pop_transform = FakeGl.popTransform,
        },
        .begin = FakeGl.begin,
        .end = FakeGl.end,
        .present = FakeGl.present,
        .read = FakeGl.read,
    });
    const full = core.RectI{ .x = 0, .y = 0, .w = 100, .h = 80 };
    try std.testing.expect(surface.contentValid());
    _ = surface.beginFrame(full, 1.0);
    surface.endFrame();
    surface.present();
    try std.testing.expect(surface.contentValid());
    // invalidateContent / 局部损伤。
    surface.invalidateContent();
    try std.testing.expect(!surface.contentValid());
    _ = surface.beginFrame(full, 1.0);
    surface.endFrame();
    surface.present();
    try std.testing.expect(surface.contentValid());
    // resize 失效。
    surface.resize(.{ .w = 120, .h = 90 });
    try std.testing.expect(!surface.contentValid());
    _ = surface.beginFrame(.{ .x = 0, .y = 0, .w = 120, .h = 90 }, 1.0);
    surface.endFrame();
    surface.present();
    try std.testing.expect(surface.contentValid());
    // scale 变化失效。
    _ = surface.beginFrame(.{ .x = 0, .y = 0, .w = 120, .h = 90 }, 2.0);
    try std.testing.expect(!surface.contentValid());
    surface.endFrame();
    surface.present();
    try std.testing.expect(surface.contentValid());
    surface.deinit();
}

test "AC-TEXT-001 fontstash 后端度量与字形栅格" {
    if (!std.mem.eql(u8, text.backend_name, "fontstash")) return error.SkipZigTest;
    try text.init(std.testing.allocator, .{});
    defer text.deinit();
    const style = text.Style{ .size = 16 };
    const m = text.measure("Hello", style, 1.0, .{});
    try std.testing.expect(m.w > 0 and m.h > 0);
    const fm = text.fontMetrics(style, 1.0);
    try std.testing.expect(fm.ascent > 0 and fm.height > fm.ascent * 0.5);
    // 实际栅格：在白底上绘制文字后应出现非白像素。
    var pixels: [120 * 40 * 4]u8 = @splat(255);
    var canvas = gfx.Canvas.init(std.testing.allocator, &pixels, 120, 40, 1.0);
    defer canvas.deinit();
    const l = text.layout("Hello", style, 1.0, .{});
    text.draw(&canvas, l, .{ .x = 4, .y = 4 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, .{});
    var non_white: usize = 0;
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        if (pixels[i] != 255 or pixels[i + 1] != 255 or pixels[i + 2] != 255) non_white += 1;
    }
    try std.testing.expect(non_white > 20);
}

test "AC-PLAT-032 无头 IME 组字、提交、取消与属性转换" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    platform.forceHeadless();
    const w = try platform.createWindow(.{ .title = "ime" });
    const Sink = struct {
        var events: [16]platform.Data = undefined;
        var texts: [16][32]u8 = undefined;
        var text_len: [16]usize = undefined;
        var n: usize = 0;
        fn sink(_: ?*anyopaque, e: platform.Event) void {
            if (n < events.len) {
                events[n] = e.data;
                text_len[n] = 0;
                switch (e.data) {
                    .ime_update => |u| {
                        const k = @min(u.text.len, texts[n].len);
                        @memcpy(texts[n][0..k], u.text[0..k]);
                        text_len[n] = k;
                    },
                    .ime_commit => |t| {
                        const k = @min(t.len, texts[n].len);
                        @memcpy(texts[n][0..k], t[0..k]);
                        text_len[n] = k;
                    },
                    else => {},
                }
            }
            n += 1;
        }
    };
    Sink.n = 0;
    platform.Headless.injectImeStart();
    platform.Headless.injectImeUpdate("ni", 2);
    platform.Headless.injectImeUpdate("你", 3);
    platform.Headless.injectImeCommit("你");
    platform.Headless.injectImeEnd();
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 5), Sink.n);
    try std.testing.expect(Sink.events[0] == .ime_start);
    try std.testing.expectEqualStrings("ni", Sink.texts[1][0..Sink.text_len[1]]);
    try std.testing.expectEqualStrings("你", Sink.texts[2][0..Sink.text_len[2]]);
    try std.testing.expectEqualStrings("你", Sink.texts[3][0..Sink.text_len[3]]);
    try std.testing.expect(Sink.events[4] == .ime_end);
    try std.testing.expect(!platform.Headless.imeActive());
    // 失焦取消组字：产生 ime_end、无 commit。
    Sink.n = 0;
    const cancel_before = platform.Headless.imeCancelCount();
    platform.Headless.injectImeStart();
    platform.Headless.injectImeUpdate("ni", 2);
    platform.Headless.inject(.{ .focus = .{ .gained = false } });
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(cancel_before + 1, platform.Headless.imeCancelCount());
    var saw_end = false;
    var saw_commit = false;
    for (Sink.events[0..Sink.n]) |e| {
        if (e == .ime_end) saw_end = true;
        if (e == .ime_commit) saw_commit = true;
    }
    try std.testing.expect(saw_end);
    try std.testing.expect(!saw_commit);
    // commitComposition 产生 commit + end；随后禁用不再取消。
    Sink.n = 0;
    platform.Headless.injectImeStart();
    platform.Headless.injectImeUpdate("你", 3);
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    Sink.n = 0;
    w.commitComposition();
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(@as(usize, 2), Sink.n);
    try std.testing.expectEqualStrings("你", Sink.texts[0][0..Sink.text_len[0]]);
    try std.testing.expect(Sink.events[1] == .ime_end);
    const cancel_after = platform.Headless.imeCancelCount();
    w.setImeEnabled(false);
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(cancel_after, platform.Headless.imeCancelCount());
    // 组字期间 VK_PROCESSKEY 不投递。
    Sink.n = 0;
    platform.Headless.injectImeStart();
    platform.Headless.injectKey(.process_key, true, false, .{});
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    var saw_key = false;
    for (Sink.events[0..Sink.n]) |e| if (e == .key) {
        saw_key = true;
    };
    try std.testing.expect(!saw_key);
    platform.Headless.injectImeEnd();
    // UTF-16 属性到 UTF-8 字节区间。
    const text16 = [_]u16{ 'a', 'b', 0x4F60 };
    const attrs = [_]u8{ 0, 0, 2 };
    const segs = try platform.imeSegmentsFromUtf16(std.testing.allocator, &text16, &attrs);
    defer std.testing.allocator.free(segs);
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqual(@as(u32, 0), segs[0].start);
    try std.testing.expectEqual(@as(u32, 2), segs[0].end);
    try std.testing.expectEqual(platform.ImeSegmentStyle.unconverted, segs[0].style);
    try std.testing.expectEqual(@as(u32, 2), segs[1].start);
    try std.testing.expectEqual(@as(u32, 5), segs[1].end);
    try std.testing.expectEqual(platform.ImeSegmentStyle.converted, segs[1].style);
}

test "AC-PLAT-034 无头 IME 光标矩形记录与去重" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const w = try platform.createWindow(.{ .title = "ime-caret" });
    const r1 = platform.RectI{ .x = 10, .y = 20, .w = 2, .h = 18 };
    const ex = platform.RectI{ .x = 0, .y = 30, .w = 120, .h = 20 };
    w.setImeCaretRect(r1, null);
    w.setImeCaretRect(r1, null);
    try std.testing.expectEqual(@as(usize, 1), platform.Headless.imeCaretCalls());
    try std.testing.expectEqual(r1, platform.Headless.imeCaretRect().?);
    try std.testing.expect(platform.Headless.imeCaretExclude() == null);
    w.setImeCaretRect(r1, ex);
    try std.testing.expectEqual(@as(usize, 2), platform.Headless.imeCaretCalls());
    try std.testing.expectEqual(ex, platform.Headless.imeCaretExclude().?);
    const r2 = platform.RectI{ .x = 40, .y = 60, .w = 2, .h = 18 };
    w.setImeCaretRect(r2, null);
    try std.testing.expectEqual(@as(usize, 3), platform.Headless.imeCaretCalls());
    try std.testing.expectEqual(r2, platform.Headless.imeCaretRect().?);
    const enabled0 = platform.Headless.imeEnabledCalls();
    w.setImeEnabled(false);
    w.setImeEnabled(true);
    try std.testing.expectEqual(enabled0 + 2, platform.Headless.imeEnabledCalls());
}

test "REQ-PLAT-064 无头托盘注册、修改、气泡与事件投递" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const w = try platform.createWindow(.{ .title = "tray" });
    try platform.tray.add(w, 7, &.{}, "提示");
    try std.testing.expectEqual(@as(usize, 1), platform.Headless.trayCount());
    try std.testing.expectEqualStrings("提示", platform.Headless.trayTooltip(7).?);
    try platform.tray.modify(7, null, "新提示");
    try std.testing.expectEqualStrings("新提示", platform.Headless.trayTooltip(7).?);
    try platform.tray.balloon(7, "标题", "正文", .info);
    const b = platform.Headless.trayBalloon().?;
    try std.testing.expectEqualStrings("标题", b.title);
    try std.testing.expectEqualStrings("正文", b.text);
    try std.testing.expectEqual(platform.BalloonKind.info, b.kind);
    // 事件投递到 owner 窗口。
    const Sink = struct {
        var got: ?platform.TrayEventKind = null;
        var pos: platform.Vec2i = .{};
        fn sink(_: ?*anyopaque, e: platform.Event) void {
            if (e.data == .tray) {
                got = e.data.tray.kind;
                pos = e.data.tray.screen_pos;
            }
        }
    };
    Sink.got = null;
    platform.Headless.injectTray(7, .double_click, .{ .x = 100, .y = 200 });
    _ = platform.pumpMessages(.{ .func = Sink.sink });
    try std.testing.expectEqual(platform.TrayEventKind.double_click, Sink.got.?);
    try std.testing.expectEqual(platform.Vec2i{ .x = 100, .y = 200 }, Sink.pos);
    platform.tray.remove(7);
    try std.testing.expectEqual(@as(usize, 0), platform.Headless.trayCount());
}

// ---------------------------------------------------------------------------
// M2：帧模型、布局、输入的自动化验收
// ---------------------------------------------------------------------------

const M2Rig = struct {
    win: *platform.Window,
    th: *theme.Theme,
    u: ui.Ui,
    surface: gfx.Surface,

    fn create(w: i32, h: i32, scale: f32) !M2Rig {
        try platform.init(std.testing.allocator);
        const win = try platform.createWindow(.{ .client_size = .{ .w = @floatFromInt(w), .h = @floatFromInt(h) } });
        const th = try std.testing.allocator.create(theme.Theme);
        th.* = theme.Theme.default(.light, platform.appearance(win));
        var u = ui.Ui.init(std.testing.allocator);
        u.setWindow(win);
        u.setTheme(th);
        u.setViewport(w, h, scale);
        const surface = gfx.Surface.init(std.testing.allocator, win) catch |e| {
            std.testing.allocator.destroy(th);
            u.deinit();
            platform.deinit();
            return e;
        };
        return .{ .win = win, .th = th, .u = u, .surface = surface };
    }

    fn destroy(self: *M2Rig) void {
        self.surface.deinit();
        self.u.deinit();
        std.testing.allocator.destroy(self.th);
        platform.deinit();
    }

    fn frame(self: *M2Rig, ctx: anytype, buildFn: *const fn (@TypeOf(ctx), *ui.Ui) void, now: u64) bool {
        self.u.beginFrame(now, true);
        self.u.build(ctx, buildFn);
        self.u.layoutTree();
        const painted = self.u.paint(&self.surface);
        self.u.finishFrame();
        return painted;
    }
};

test "AC-FRAME-005 transient/sticky 状态回收、4096 上限与类型隔离" {
    var rig = try M2Rig.create(200, 120, 1.0);
    defer rig.destroy();
    var m = F5Model{ .write = true };
    try std.testing.expect(rig.frame(&m, f5Build, 0));
    try std.testing.expectEqual(@as(u32, 7), m.seen);
    // transient：不声明一次即回收。
    m.write = false;
    m.declare = false;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f5Build, 16);
    m.declare = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f5Build, 32);
    try std.testing.expectEqual(@as(u32, 0), m.seen);
    // sticky：不声明也保留。
    m = F5Model{ .write = true, .sticky = true };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f5Build, 48);
    m.write = false;
    m.declare = false;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f5Build, 64);
    m.declare = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f5Build, 80);
    try std.testing.expectEqual(@as(u32, 7), m.seen);

    // sticky 上限 4096，回收最早创建者。
    var rig2 = try M2Rig.create(200, 120, 1.0);
    defer rig2.destroy();
    var many = F5Many{ .declare = true };
    _ = rig2.frame(&many, f5ManyBuild, 0);
    try std.testing.expectEqual(@as(usize, 5000), rig2.u.stateSlotCount());
    many.declare = false;
    rig2.u.invalidate(.build);
    _ = rig2.frame(&many, f5ManyBuild, 16);
    try std.testing.expectEqual(@as(usize, 4096), rig2.u.stateSlotCount());
    const id0: core.WidgetId = @fromBackingInt(@intCast(0x600000));
    const id903: core.WidgetId = @fromBackingInt(@intCast(0x600000 + 903));
    const id904: core.WidgetId = @fromBackingInt(@intCast(0x600000 + 904));
    try std.testing.expect(rig2.u.getState(u32, id0) == null);
    try std.testing.expect(rig2.u.getState(u32, id903) == null);
    try std.testing.expect(rig2.u.getState(u32, id904) != null);

    // 同一 ID 的 u32 / f32 槽互不影响。
    const typed_id: core.WidgetId = @fromBackingInt(0x600999);
    const pu = rig2.u.state(u32, typed_id, 0);
    pu.* = 123;
    const pf = rig2.u.state(f32, typed_id, 0);
    pf.* = 1.5;
    try std.testing.expectEqual(@as(u32, 123), pu.*);
    try std.testing.expectEqual(@as(f32, 1.5), pf.*);
}

const F5Model = struct { declare: bool = true, write: bool = false, sticky: bool = false, seen: u32 = 999 };
fn f5Build(ctx: *F5Model, u: *ui.Ui) void {
    if (!ctx.declare) return;
    const id: core.WidgetId = @fromBackingInt(0x5F5001);
    const p = if (ctx.sticky) u.stateSticky(u32, id, 0) else u.state(u32, id, 0);
    if (ctx.write) p.* = 7;
    ctx.seen = p.*;
}

const F5Many = struct { declare: bool = true };
fn f5ManyBuild(ctx: *F5Many, u: *ui.Ui) void {
    if (!ctx.declare) return;
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        const id: core.WidgetId = @fromBackingInt(@intCast(0x600000 + i));
        _ = u.stateSticky(u32, id, 0);
    }
}

test "AC-FRAME-007 动画初值、半程插值、终值与消失后重置" {
    var rig = try M2Rig.create(200, 120, 1.0);
    defer rig.destroy();
    var m = F7Model{};
    const id: core.WidgetId = @fromBackingInt(0x5F7001);
    const spec: ui.AnimSpec = .{ .duration = .fast, .easing = .out, .level = .paint };
    const dur: u64 = rig.th.durationMs(.fast);
    try std.testing.expect(dur > 0);
    rig.u.beginFrame(0, true);
    try std.testing.expectEqual(@as(f32, 0), rig.u.animate(id, 0, 0, spec));
    try std.testing.expectEqual(@as(f32, 0), rig.u.animate(id, 0, 1, spec));
    rig.u.beginFrame(dur / 2, true);
    const mid = rig.u.animate(id, 0, 1, spec);
    try std.testing.expect(mid > 0 and mid < 1);
    rig.u.beginFrame(dur, true);
    try std.testing.expectEqual(@as(f32, 1), rig.u.animate(id, 0, 1, spec));
    // 节点停止声明一次构建后，动画记忆被丢弃，首次调用直接返回目标。
    rig.u.beginFrame(dur + 10, true);
    rig.u.build(&m, f7Build);
    rig.u.finishFrame();
    rig.u.beginFrame(dur + 20, true);
    try std.testing.expectEqual(@as(f32, 0.25), rig.u.animate(id, 0, 0.25, spec));
}
const F7Model = struct {};
fn f7Build(_: *F7Model, _: *ui.Ui) void {}

const F11Model = struct {
    show_a: bool = true,
    show_b: bool = false,
    spacer_w: f32 = 0,
    a_w: f32 = 40,
    a_key: u64 = 1,
    a_outset: f32 = 0,
    hover_seen: bool = false,
};
fn f11Build(ctx: *F11Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(10), .gap = .none });
    const sid: core.WidgetId = @fromBackingInt(0x5F1100);
    _ = u.leaf(sid, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(ctx.spacer_w), .cross = .fixedSize(20), .content = .{ .size = .{ .x = ctx.spacer_w, .y = 20 } } } });
    if (ctx.show_a) {
        const aid: core.WidgetId = @fromBackingInt(0x5F1101);
        const n = u.leaf(aid, .{
            .layout = .{ .kind = .leaf, .main = .fixedSize(ctx.a_w), .cross = .fixedSize(20), .content = .{ .size = .{ .x = ctx.a_w, .y = 20 } } },
            .paint_key = ctx.a_key ^ (@as(u64, @intFromBool(ctx.hover_seen)) << 40),
            .paint_outset = ctx.a_outset,
        });
        n.debug_name = "A";
        const it = u.interact(aid, .{ .sense = .{ .hover = true }, .hover_anim = true });
        ctx.hover_seen = it.hovered;
    }
    if (ctx.show_b) {
        const bid: core.WidgetId = @fromBackingInt(0x5F1102);
        _ = u.leaf(bid, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 40, .y = 20 } } } });
    }
    u.endRow();
}

test "AC-FRAME-011 失效与损伤：空差异、绘制键、位移、增删、绘制外延" {
    var rig = try M2Rig.create(400, 200, 1.0);
    defer rig.destroy();
    var m = F11Model{};
    _ = rig.frame(&m, f11Build, 0);
    const a = rig.u.getNode(@fromBackingInt(0x5F1101)).?;
    const a_rect = a.abs;

    // 场景一：同模型 invalidate(.build)，第二帧只构建不绘制/不提交。
    rig.u.invalidate(.build);
    const presents0 = core.stats.read("frame.presents").?;
    rig.u.beginFrame(16, true);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    const painted1 = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expect(!painted1);
    try std.testing.expectEqual(@as(u32, 1), rig.u.build_passes);
    try std.testing.expectEqual(presents0, core.stats.read("frame.presents").?);

    // 场景二：仅绘制键变化 → 损伤恰为该节点矩形。
    m.a_key = 99;
    rig.u.invalidate(.build);
    rig.u.beginFrame(32, true);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    const dmg2 = rig.u.damage;
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expectEqual(a_rect, dmg2);

    // 场景三：节点右移 10 lpx → 损伤 = 旧 ∪ 新。
    m.spacer_w = 10;
    rig.u.invalidate(.build);
    rig.u.beginFrame(48, true);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    const dmg3 = rig.u.damage;
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    const a_new = rig.u.getNode(@fromBackingInt(0x5F1101)).?.abs;
    const union3 = a_rect.unionRect(a_new);
    try std.testing.expectEqual(union3, dmg3);

    // 场景四：移除节点 → 损伤包含旧矩形；新增 → 包含新矩形。
    m.spacer_w = 0;
    m.show_a = false;
    rig.u.invalidate(.build);
    rig.u.beginFrame(64, true);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    const dmg4 = rig.u.damage;
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expect(m2Contains(dmg4, a_rect));
    m.show_a = true;
    m.a_key = 7;
    rig.u.invalidate(.build);
    rig.u.beginFrame(80, true);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    const dmg5 = rig.u.damage;
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expect(m2Contains(dmg5, rig.u.getNode(@fromBackingInt(0x5F1101)).?.abs));

    // 场景五：绘制外延 2 lpx + 悬停变化 → 布局矩形各边外扩 2。
    m.a_outset = 2;
    rig.u.invalidate(.build);
    rig.u.beginFrame(96, true);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    const base = rig.u.getNode(@fromBackingInt(0x5F1101)).?.abs;
    const cx: i32 = base.x + @divTrunc(base.w, 2);
    const cy: i32 = base.y + @divTrunc(base.h, 2);
    rig.u.beginFrame(112, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 112, .data = .{ .mouse_move = .{ .pos = .{ .x = cx, .y = cy } } } });
    rig.u.invalidate(.build);
    rig.u.build(&m, f11Build);
    rig.u.layoutTree();
    const dmg6 = rig.u.damage;
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expect(m.hover_seen);
    const expanded = core.RectI{ .x = base.x - 2, .y = base.y - 2, .w = base.w + 4, .h = base.h + 4 };
    try std.testing.expectEqual(expanded, dmg6);
}

test "AC-FRAME-013 构建内失效不嵌套且恰好多一帧" {
    var rig = try M2Rig.create(200, 120, 1.0);
    defer rig.destroy();
    var m = F13Model{};
    _ = rig.frame(&m, f13Build, 0);
    try std.testing.expectEqual(@as(u32, 1), m.max_depth);
    try std.testing.expectEqual(@as(u32, 1), m.calls);
    try std.testing.expect(rig.u.needsFrame());
    _ = rig.frame(&m, f13Build, 16);
    try std.testing.expectEqual(@as(u32, 2), m.calls);
    try std.testing.expect(!rig.u.needsFrame());
    _ = rig.frame(&m, f13Build, 32);
    try std.testing.expectEqual(@as(u32, 2), m.calls);
}
const F13Model = struct { calls: u32 = 0, depth: u32 = 0, max_depth: u32 = 0, asked: bool = false };
fn f13Build(ctx: *F13Model, u: *ui.Ui) void {
    ctx.calls += 1;
    ctx.depth += 1;
    if (ctx.depth > ctx.max_depth) ctx.max_depth = ctx.depth;
    if (!ctx.asked) {
        ctx.asked = true;
        u.invalidate(.build);
    }
    ctx.depth -= 1;
}

const F21Model = struct {};
fn f21Build(_: *F21Model, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    const id: core.WidgetId = @fromBackingInt(0x5F2101);
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 200, .y = 100 } } }, .flags = .{ .focusable = true, .tab_stop = true } });
    _ = u.interact(id, .{ .sense = .{ .hover = true, .click = true } });
    u.endColumn();
}

test "AC-FRAME-021 一轮消息内多事件合并为单帧且顺序不变" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    var m = F21Model{};
    _ = rig.frame(&m, f21Build, 0);
    const id: core.WidgetId = @fromBackingInt(0x5F2101);
    rig.u.capturePointer(id);
    rig.u.beginFrame(16, true);
    var i: i32 = 0;
    while (i < 50) : (i += 1) {
        rig.u.dispatch(.{ .window = rig.win, .time_ms = 16, .data = .{ .mouse_move = .{ .pos = .{ .x = 20 + i, .y = 20 } } } });
    }
    rig.u.invalidate(.paint);
    rig.u.invalidate(.paint);
    rig.u.invalidate(.paint);
    rig.u.invalidate(.build);
    rig.u.build(&m, f21Build);
    rig.u.layoutTree();
    try std.testing.expect(rig.u.build_passes >= 1);
    var moves: usize = 0;
    for (rig.u.events(id)) |ev| {
        if (ev == .pointer_move) {
            try std.testing.expectEqual(@as(f32, @floatFromInt(20 + moves)), ev.pointer_move.pos.x);
            moves += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 50), moves);
    const frames0 = core.stats.read("frame.count").?;
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expectEqual(frames0 + 1, core.stats.read("frame.count").?);
}

const F23Model = struct {
    counts: [8]u32 = @splat(0),
    n: u32 = 0,
};
fn f23Paint(ctx: *ui.PaintCtx, node: *const ui.Node) void {
    _ = ctx;
    const p: *u32 = @ptrCast(@alignCast(@constCast(node.props.?)));
    p.* += 1;
}
fn f23GridBuild(ctx: *F23Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(10), .gap = .none });
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        const id: core.WidgetId = @fromBackingInt(@intCast(0x5F2300 + i));
        _ = u.leaf(id, .{
            .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 20, .y = 20 } } },
            .paint = struct {
                fn f(_: *ui.PaintCtx, _: *const ui.Node) void {}
            }.f,
        });
    }
    u.endRow();
    _ = ctx;
}
fn f23WideBuild(ctx: *F23Model, u: *ui.Ui) void {
    _ = u.beginStack(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    const id: core.WidgetId = @fromBackingInt(0x5F23F0);
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(320), .cross = .fixedSize(240), .content = .{ .size = .{ .x = 320, .y = 240 } } } });
    u.endStack();
    _ = ctx;
}
fn f23TreeBuild(ctx: *F23Model, u: *ui.Ui) void {
    const col = u.beginNode(@fromBackingInt(0x5F23C0), .{
        .layout = .{ .kind = .column, .main = .{ .grow = 1 }, .cross = .fill },
        .paint = f23Paint,
        .props = &ctx.counts[0],
    });
    _ = col;
    const row = u.beginNode(@fromBackingInt(0x5F23C1), .{
        .layout = .{ .kind = .row, .main = .{ .grow = 1 }, .cross = .fit },
        .paint = f23Paint,
        .props = &ctx.counts[1],
    });
    _ = row;
    _ = u.leaf(@fromBackingInt(0x5F23C2), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 40, .y = 20 } } }, .paint = f23Paint, .props = &ctx.counts[2] });
    _ = u.leaf(@fromBackingInt(0x5F23C3), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 40, .y = 20 } } }, .paint = f23Paint, .props = &ctx.counts[3] });
    u.endNode();
    u.endNode();
}

test "AC-FRAME-023 损伤矩形合并、超半屏提升与绘制集合裁剪" {
    var rig = try M2Rig.create(400, 300, 1.0);
    defer rig.destroy();
    var m = F23Model{};
    _ = rig.frame(&m, f23GridBuild, 0);
    rig.u.beginFrame(16, true);
    var i: usize = 0;
    var all = core.RectI{ .x = 0, .y = 0, .w = 0, .h = 0 };
    while (i < 12) : (i += 1) {
        const id: core.WidgetId = @fromBackingInt(@intCast(0x5F2300 + i));
        rig.u.invalidateNode(id, .paint);
        all = all.unionRect(rig.u.getPrevNode(id).?.abs);
    }
    try std.testing.expect(m2Contains(rig.u.damage, all));
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();

    // 60% 面积 → 整根。
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f23WideBuild, 32);
    rig.u.beginFrame(48, true);
    rig.u.invalidateNode(@fromBackingInt(0x5F23F0), .paint);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 400, .h = 300 }, rig.u.damage);
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();

    // 仅叶节点绘制脏：叶与相交祖先被绘制，不相交兄弟为 0。
    var rig3 = try M2Rig.create(400, 300, 1.0);
    defer rig3.destroy();
    var m3 = F23Model{};
    _ = rig3.frame(&m3, f23TreeBuild, 0);
    m3.counts = @splat(0);
    rig3.u.beginFrame(16, true);
    rig3.u.invalidateNode(@fromBackingInt(0x5F23C2), .paint);
    _ = rig3.u.paint(&rig3.surface);
    rig3.u.finishFrame();
    try std.testing.expectEqual(@as(u32, 1), m3.counts[0]); // Column
    try std.testing.expectEqual(@as(u32, 1), m3.counts[1]); // Row
    try std.testing.expectEqual(@as(u32, 1), m3.counts[2]); // 目标叶
    try std.testing.expectEqual(@as(u32, 0), m3.counts[3]); // 不相交兄弟
}

const F25Model = struct {};
fn f25Build(_: *F25Model, u: *ui.Ui) void {
    _ = widgets.button(u, @src(), "Hover", .{ .debug_name = "hover", .key = ui.Key.str("hover") });
}

test "AC-FRAME-025 悬停动画每周期一帧且构建遍数为 0" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    var m = F25Model{};
    _ = rig.frame(&m, f25Build, 0);
    const btn = findByName(rig.u.current_root, "hover").?;
    const cx: i32 = btn.abs.x + @divTrunc(btn.abs.w, 2);
    const cy: i32 = btn.abs.y + @divTrunc(btn.abs.h, 2);
    rig.u.beginFrame(0, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 0, .data = .{ .mouse_move = .{ .pos = .{ .x = cx, .y = cy } } } });
    try std.testing.expect(rig.u.haveActiveAnimations());
    const painted0 = rig.u.paint(&rig.surface);
    try std.testing.expect(painted0);
    try std.testing.expectEqual(@as(u32, 0), rig.u.build_passes);
    rig.u.finishFrame();
    var now: u64 = 16;
    var frames: usize = 1;
    while (rig.u.needsFrame() and frames < 100) : (frames += 1) {
        rig.u.beginFrame(now, true);
        rig.u.build(&m, f25Build);
        rig.u.layoutTree();
        const painted = rig.u.paint(&rig.surface);
        try std.testing.expect(painted);
        try std.testing.expectEqual(@as(u32, 0), rig.u.build_passes);
        rig.u.finishFrame();
        now += 16;
    }
    try std.testing.expect(frames > 1 and frames < 100);
    try std.testing.expect(!rig.u.haveActiveAnimations());
    var k: usize = 0;
    while (k < 10) : (k += 1) {
        try std.testing.expect(!rig.u.needsFrame());
        now += 16;
    }
}

test "AC-FRAME-026 系统动画关闭时悬停直接到终态且仅一帧" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    platform.Headless.setMetrics(.{ .client_animation = false });
    var m = F25Model{};
    _ = rig.frame(&m, f25Build, 0);
    const btn = findByName(rig.u.current_root, "hover").?;
    const cx: i32 = btn.abs.x + @divTrunc(btn.abs.w, 2);
    const cy: i32 = btn.abs.y + @divTrunc(btn.abs.h, 2);
    rig.u.beginFrame(0, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 0, .data = .{ .mouse_move = .{ .pos = .{ .x = cx, .y = cy } } } });
    try std.testing.expect(!rig.u.haveActiveAnimations());
    try std.testing.expectEqual(@as(?f32, 1), rig.u.animationCurrent(btn.id, 0));
    const painted = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expect(painted);
    try std.testing.expectEqual(@as(u32, 0), rig.u.build_passes);
    try std.testing.expect(!rig.u.needsFrame());
    try std.testing.expect(!rig.u.paint(&rig.surface));
}

test "AC-LAYOUT-001 grow 权重与余数分配" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var items = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(1) },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(1) },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(1) },
    };
    var out: [3]i32 = undefined;
    const cases = [_]struct { avail: i32, want: [3]i32 }{
        .{ .avail = 300, .want = .{ 100, 100, 100 } },
        .{ .avail = 301, .want = .{ 101, 100, 100 } },
        .{ .avail = 302, .want = .{ 101, 101, 100 } },
        .{ .avail = 303, .want = .{ 101, 101, 101 } },
    };
    for (cases) |c| {
        _ = layout.distribute(arena.allocator(), &items, c.avail, &out);
        try std.testing.expectEqual(c.want, out);
        var sum: i32 = 0;
        for (out) |v| sum += v;
        try std.testing.expectEqual(c.avail, sum);
    }
    var two = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 2048 },
    };
    var out2: [2]i32 = undefined;
    _ = layout.distribute(arena.allocator(), &two, 100, &out2);
    try std.testing.expectEqual([2]i32{ 33, 67 }, out2);
    var halves = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(0.5) },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(0.5) },
    };
    _ = layout.distribute(arena.allocator(), &halves, 7, &out2);
    try std.testing.expectEqual([2]i32{ 4, 3 }, out2);
    var thirds = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(1.0 / 3.0) },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(1.0 / 3.0) },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = layout.quantizeWeight(1.0 / 3.0) },
    };
    _ = layout.distribute(arena.allocator(), &thirds, 301, &out);
    try std.testing.expectEqual([3]i32{ 101, 100, 100 }, out);
}

test "AC-LAYOUT-002 max/min 冻结、leftover 与零权重" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: [3]i32 = undefined;
    var items = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = 50, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
    };
    _ = layout.distribute(arena.allocator(), &items, 300, &out);
    try std.testing.expectEqual([3]i32{ 50, 125, 125 }, out);
    var two = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 200, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
    };
    var out2: [2]i32 = undefined;
    _ = layout.distribute(arena.allocator(), &two, 300, &out2);
    try std.testing.expectEqual([2]i32{ 200, 100 }, out2);
    var mixed = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 150, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = 60, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
    };
    _ = layout.distribute(arena.allocator(), &mixed, 300, &out);
    try std.testing.expectEqual([3]i32{ 150, 60, 90 }, out);
    var capped = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = 40, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = 40, .wq = 1024 },
    };
    const r = layout.distribute(arena.allocator(), &capped, 300, &out2);
    try std.testing.expectEqual([2]i32{ 40, 40 }, out2);
    try std.testing.expectEqual(@as(i32, 220), r.leftover);
    var zero = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 30, .max = layout.unbounded, .wq = 0 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = layout.unbounded, .wq = 1024 },
    };
    _ = layout.distribute(arena.allocator(), &zero, 100, &out2);
    try std.testing.expectEqual(@as(i32, 30), out2[0]);
    try std.testing.expectEqual(@as(i32, 70), out2[1]);
}

test "AC-LAYOUT-003 fit_shrink 收缩、溢出与非收缩项" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: [3]i32 = undefined;
    var items = [_]layout.FlexItem{
        .{ .kind = .shrink, .base = 200, .min = 80, .max = layout.unbounded, .wq = 0 },
        .{ .kind = .shrink, .base = 150, .min = 50, .max = layout.unbounded, .wq = 0 },
        .{ .kind = .fixed, .base = 100, .min = 0, .max = layout.unbounded, .wq = 0 },
    };
    var r = layout.distribute(arena.allocator(), &items, 300, &out);
    try std.testing.expectEqual([3]i32{ 118, 82, 100 }, out);
    try std.testing.expectEqual(@as(i32, 0), r.overflow);
    items[2].base = 250;
    r = layout.distribute(arena.allocator(), &items, 300, &out);
    try std.testing.expectEqual([3]i32{ 80, 50, 250 }, out);
    try std.testing.expectEqual(@as(i32, 80), r.overflow);
    var no_shrink = [_]layout.FlexItem{
        .{ .kind = .fixed, .base = 200, .min = 0, .max = layout.unbounded, .wq = 0 },
        .{ .kind = .fit, .base = 150, .min = 0, .max = layout.unbounded, .wq = 0 },
    };
    var out2: [2]i32 = undefined;
    r = layout.distribute(arena.allocator(), &no_shrink, 300, &out2);
    try std.testing.expectEqual([2]i32{ 200, 150 }, out2);
    try std.testing.expectEqual(@as(i32, 50), r.overflow);
    var grow_fixed = [_]layout.FlexItem{
        .{ .kind = .grow, .base = 0, .min = 80, .max = layout.unbounded, .wq = 1024 },
        .{ .kind = .fixed, .base = 250, .min = 0, .max = layout.unbounded, .wq = 0 },
    };
    r = layout.distribute(arena.allocator(), &grow_fixed, 300, &out2);
    try std.testing.expectEqual([2]i32{ 80, 250 }, out2);
    try std.testing.expectEqual(@as(i32, 30), r.overflow);
}

const LogCapture = struct {
    var warns: usize = 0;
    fn sink(level: core.log.Level, _: []const u8, _: []const u8) void {
        if (level == .warn) warns += 1;
    }
};

test "AC-LAYOUT-004 缩放取整、padding/gap 与 main 范围夹紧" {
    var rig = try M2Rig.create(500, 100, 1.25);
    defer rig.destroy();
    rig.u.beginFrame(0, true);
    _ = rig.u.build(&F4Model{}, f4RowBuild);
    rig.u.layoutTree();
    const a = rig.u.lastRectPx(@fromBackingInt(0x4A01)).?;
    const b = rig.u.lastRectPx(@fromBackingInt(0x4A02)).?;
    const c = rig.u.lastRectPx(@fromBackingInt(0x4A03)).?;
    try std.testing.expectEqual(@as(i32, 13), a.w);
    try std.testing.expectEqual(@as(i32, 1), b.w);
    try std.testing.expectEqual(@as(i32, 0), c.w);
    try std.testing.expectEqual(@as(i32, 10), a.x);
    try std.testing.expectEqual(@as(i32, 33), b.x);
    try std.testing.expectEqual(@as(i32, 44), c.x);
    rig.u.finishFrame();

    var rig2 = try M2Rig.create(400, 100, 1.5);
    defer rig2.destroy();
    _ = rig2.frame(&F4Model{}, f4ContentBuild, 0);
    const w1 = rig2.u.lastRectPx(@fromBackingInt(0x4A10)).?;
    const w2 = rig2.u.lastRectPx(@fromBackingInt(0x4A11)).?;
    try std.testing.expectEqual(@as(i32, 150), w1.w);
    try std.testing.expectEqual(@as(i32, 151), w2.w);

    var rig3 = try M2Rig.create(400, 100, 1.0);
    defer rig3.destroy();
    LogCapture.warns = 0;
    core.log.setSink(LogCapture.sink);
    defer core.log.setSink(null);
    _ = rig3.frame(&F4Model{}, f4ClampBuild, 0);
    try std.testing.expectEqual(@as(i32, 80), rig3.u.lastRectPx(@fromBackingInt(0x4A20)).?.w);
    try std.testing.expectEqual(@as(i32, 80), rig3.u.lastRectPx(@fromBackingInt(0x4A21)).?.w);
    try std.testing.expectEqual(@as(usize, 1), LogCapture.warns);
}
const F4Model = struct {};
fn f4RowBuild(_: *const F4Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .md });
    _ = u.leaf(@fromBackingInt(0x4A01), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(10.5), .cross = .fill } });
    _ = u.leaf(@fromBackingInt(0x4A02), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(0.3), .cross = .fill } });
    _ = u.leaf(@fromBackingInt(0x4A03), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(0), .cross = .fill } });
    u.endRow();
}
fn f4ContentBuild(_: *const F4Model, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fit });
    _ = u.leaf(@fromBackingInt(0x4A10), .{ .layout = .{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = 100.0000001, .y = 10 } } } });
    _ = u.leaf(@fromBackingInt(0x4A11), .{ .layout = .{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = 100.4, .y = 10 } } } });
    u.endColumn();
}
fn f4ClampBuild(_: *const F4Model, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fit });
    _ = u.leaf(@fromBackingInt(0x4A20), .{ .layout = .{ .kind = .leaf, .main = .{ .fixed = 50 }, .main_min = 80, .cross = .fit } });
    _ = u.leaf(@fromBackingInt(0x4A21), .{ .layout = .{ .kind = .leaf, .main = .{ .fixed = 50 }, .main_min = 80, .main_max = 60, .cross = .fit } });
    u.endColumn();
}

fn m2Contains(outer: core.RectI, inner: core.RectI) bool {
    if (inner.isEmpty()) return true;
    return inner.x >= outer.x and inner.y >= outer.y and inner.right() <= outer.right() and inner.bottom() <= outer.bottom();
}

fn hasField(comptime T: type, comptime name: []const u8) bool {
    return @hasField(T, name);
}

test "AC-LAYOUT-029 参数默认值、禁用字段与 spacer" {
    try std.testing.expect(!hasField(layout.Params, "wrap"));
    try std.testing.expect(!hasField(layout.Params, "margin"));
    try std.testing.expect(!hasField(layout.Params, "z_index"));
    try std.testing.expect(!hasField(layout.Params, "baseline"));
    try std.testing.expect(!hasField(layout.Params, "percent"));
    try std.testing.expect(!hasField(layout.ContainerOptions, "wrap"));
    try std.testing.expect(!hasField(layout.ContainerOptions, "margin"));
    try std.testing.expect(!hasField(layout.ContainerOptions, "z_index"));
    const ext_fields = @typeInfo(layout.Extent).@"union".field_names;
    for (ext_fields) |f| try std.testing.expect(!std.mem.eql(u8, f, "percent"));
    const p = layout.Params{};
    try std.testing.expectEqual(layout.Kind.leaf, p.kind);
    try std.testing.expectEqual(std.meta.activeTag(p.main), .fit);
    try std.testing.expectEqual(std.meta.activeTag(p.cross), .fit);
    try std.testing.expectEqual(@as(f32, 0), p.main_min);
    try std.testing.expect(std.math.isInf(p.main_max));
    try std.testing.expectEqual(@as(f32, 0), p.cross_min);
    try std.testing.expect(std.math.isInf(p.cross_max));
    try std.testing.expectEqual(core.Insets{}, p.padding);
    try std.testing.expectEqual(theme.Gap.none, p.gap);
    try std.testing.expectEqual(layout.Justify.start, p.justify);
    try std.testing.expectEqual(layout.Align.start, p.cross_align);
    try std.testing.expectEqual(@as(?layout.Align, null), p.self_align);
    try std.testing.expectEqual(@as(?layout.Align, null), p.self_main_align);
    try std.testing.expectEqual(false, p.form_span);
    try std.testing.expectEqual(core.Vec2{}, p.content.size);
    try std.testing.expectEqual(@as(u64, 0), p.content.key);
    try std.testing.expectEqual(@as(?layout.HeightForWidthFn, null), p.content.hfw);
    try std.testing.expectEqual(@as(?*const anyopaque, null), p.content.hfw_ctx);
    const co = layout.ContainerOptions{};
    try std.testing.expectEqual(@as(?*anyopaque, null), co.key);
    try std.testing.expectEqual(@as(?[]const u8, null), co.debug_name);
    try std.testing.expectEqual(std.meta.activeTag(co.main), .fit);
    try std.testing.expectEqual(std.meta.activeTag(co.cross), .fit);
    try std.testing.expectEqual(@as(f32, 0), co.main_min);
    try std.testing.expect(std.math.isInf(co.main_max));
    try std.testing.expectEqual(@as(f32, 0), co.cross_min);
    try std.testing.expect(std.math.isInf(co.cross_max));
    try std.testing.expectEqual(core.Insets{}, co.padding);
    try std.testing.expectEqual(theme.Gap.none, co.gap);
    try std.testing.expectEqual(layout.Justify.start, co.justify);
    try std.testing.expectEqual(layout.Align.start, co.cross_align);
    try std.testing.expectEqual(@as(?layout.Align, null), co.self_align);
    try std.testing.expectEqual(false, co.clip);
    try std.testing.expectEqual(false, co.hidden);

    var rig = try M2Rig.create(200, 120, 1.0);
    defer rig.destroy();
    var m = F29Model{};
    _ = rig.frame(&m, f29Build, 0);
    const n = rig.u.getNode(m.spacer_id).?;
    try std.testing.expectEqual(std.meta.activeTag(n.layout.main), .grow);
    try std.testing.expectEqual(@as(f32, 2), n.layout.main.grow);
}
const F29Model = struct { spacer_id: core.WidgetId = .none };
fn f29Build(ctx: *F29Model, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    ctx.spacer_id = u.spacer(@src(), 2.0);
    u.endColumn();
}

test "AC-INPUT-024 助记符解析" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = input.parseMnemonic(arena.allocator(), "&File");
    try std.testing.expectEqualStrings("File", a.text);
    try std.testing.expectEqual(@as(u32, 0), a.underline.?.start);
    try std.testing.expectEqual(@as(u32, 1), a.underline.?.len);
    try std.testing.expectEqual(@as(?u21, 'f'), a.key);
    const b = input.parseMnemonic(arena.allocator(), "Save && Exit");
    try std.testing.expectEqualStrings("Save & Exit", b.text);
    try std.testing.expect(b.underline == null and b.key == null);
    const c = input.parseMnemonic(arena.allocator(), "A&&&B");
    try std.testing.expectEqualStrings("A&B", c.text);
    try std.testing.expectEqual(@as(u32, 2), c.underline.?.start);
    try std.testing.expectEqual(@as(?u21, 'b'), c.key);
    const d = input.parseMnemonic(arena.allocator(), "Trailing&");
    try std.testing.expectEqualStrings("Trailing", d.text);
    try std.testing.expect(d.underline == null and d.key == null);
    const e = input.parseMnemonic(arena.allocator(), "&a&b");
    try std.testing.expectEqualStrings("ab", e.text);
    try std.testing.expectEqual(@as(u32, 0), e.underline.?.start);
    try std.testing.expectEqual(@as(?u21, 'a'), e.key);
    const f = input.parseMnemonic(arena.allocator(), "文件(&F)");
    try std.testing.expectEqualStrings("文件(F)", f.text);
    try std.testing.expectEqual(@as(u32, 7), f.underline.?.start);
    try std.testing.expectEqual(@as(u32, 1), f.underline.?.len);
    try std.testing.expectEqual(@as(?u21, 'f'), f.key);
    const g = input.parseMnemonic(arena.allocator(), "&");
    try std.testing.expectEqualStrings("", g.text);
    try std.testing.expect(g.underline == null and g.key == null);
    const h = input.parseMnemonic(arena.allocator(), "&Ä");
    try std.testing.expectEqual(@as(?u21, 0x00E4), h.key);
    const i = input.parseMnemonic(arena.allocator(), "x&é");
    try std.testing.expectEqual(@as(?u21, 0x00E9), i.key);
}

test "AC-TEST-001 fixed 后端无显示环境下的度量一致性" {
    if (!std.mem.eql(u8, text.backend_name, "fixed")) return error.SkipZigTest;
    try text.init(std.testing.allocator, .{});
    defer text.deinit();
    const style = text.Style{ .size = 16 };
    const s = "Hello 你好";
    try std.testing.expectEqual(@as(usize, 8), core.codepointCount(s));
    const a = text.measure(s, style, 1.0, .{});
    const b = text.measure(s, style, 1.0, .{});
    try std.testing.expectEqual(a.w, b.w);
    try std.testing.expectEqual(a.h, b.h);
    try std.testing.expectEqual(@as(f32, 64), a.w);
    try std.testing.expectEqual(@as(f32, 20), a.h);
    const fm = text.fontMetrics(style, 1.0);
    try std.testing.expectEqual(@as(f32, 16), fm.ascent);
    try std.testing.expectEqual(@as(f32, 4), fm.descent);
    try std.testing.expectEqual(@as(f32, 20), fm.height);
    var it: usize = 0;
    var clusters: usize = 0;
    while (it < s.len) {
        const next = text.nextGrapheme(s, it);
        const m = text.measure(s[it..next], style, 1.0, .{});
        try std.testing.expectEqual(@as(f32, 8), m.w);
        clusters += 1;
        it = next;
    }
    try std.testing.expectEqual(@as(usize, 8), clusters);
    try std.testing.expectEqualStrings("fixed", text.backend_name);
}

const L67Model = struct {
    justify: layout.Justify = .start,
    cross_align: layout.Align = .start,
    count: usize = 3,
    grow: bool = false,
    fill: bool = false,
    self_align: ?layout.Align = null,
    child_h: f32 = 15,
    cross_max: f32 = std.math.inf(f32),
    row_w: f32 = 300,
};
fn l67Build(ctx: *L67Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .fixedSize(ctx.row_w), .cross = .fixedSize(40), .justify = ctx.justify, .cross_align = ctx.cross_align });
    var i: usize = 0;
    while (i < ctx.count) : (i += 1) {
        const id: core.WidgetId = @fromBackingInt(@intCast(0x67A0 + i));
        _ = u.leaf(id, .{
            .layout = .{
                .kind = .leaf,
                .main = .fixedSize(50),
                .cross = if (ctx.fill) .fill else .fit,
                .content = .{ .size = .{ .x = 50, .y = ctx.child_h } },
                .self_align = ctx.self_align,
                .cross_max = ctx.cross_max,
            },
        });
    }
    if (ctx.grow) {
        _ = u.leaf(@fromBackingInt(0x67AF), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fit, .content = .{ .size = .{ .x = 0, .y = 15 } } } });
    }
    u.endRow();
}

test "AC-LAYOUT-006 justify 四种模式、余数与 grow 吸收" {
    var rig = try M2Rig.create(400, 100, 1.0);
    defer rig.destroy();
    var m = L67Model{};
    const cases = [_]struct { j: layout.Justify, want: [3]i32 }{
        .{ .j = .start, .want = .{ 0, 50, 100 } },
        .{ .j = .center, .want = .{ 75, 125, 175 } },
        .{ .j = .end, .want = .{ 150, 200, 250 } },
        .{ .j = .space_between, .want = .{ 0, 125, 250 } },
    };
    for (cases) |c| {
        m.justify = c.j;
        rig.u.invalidate(.build);
        _ = rig.frame(&m, l67Build, 0);
        var got: [3]i32 = undefined;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            got[i] = rig.u.lastRectPx(@fromBackingInt(@intCast(0x67A0 + i))).?.x;
        }
        try std.testing.expectEqual(c.want, got);
    }
    // 内部宽 301：space_between 余数给第一个间隙。
    m.justify = .space_between;
    m.row_w = 301;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 16);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(@fromBackingInt(0x67A0)).?.x);
    try std.testing.expectEqual(@as(i32, 126), rig.u.lastRectPx(@fromBackingInt(0x67A1)).?.x);
    try std.testing.expectEqual(@as(i32, 251), rig.u.lastRectPx(@fromBackingInt(0x67A2)).?.x);
    // 单个子项：space_between 等同 start。
    m.count = 1;
    m.row_w = 300;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 32);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(@fromBackingInt(0x67A0)).?.x);
    // 增加 grow 子项：justify 不再影响 fixed 子项位置。
    m.count = 3;
    m.grow = true;
    m.justify = .end;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 48);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(@fromBackingInt(0x67A0)).?.x);
    try std.testing.expectEqual(@as(i32, 50), rig.u.lastRectPx(@fromBackingInt(0x67A1)).?.x);
    try std.testing.expectEqual(@as(i32, 100), rig.u.lastRectPx(@fromBackingInt(0x67A2)).?.x);
}

test "AC-LAYOUT-007 交叉轴对齐、fill、self_align 与溢出" {
    var rig = try M2Rig.create(400, 100, 1.0);
    defer rig.destroy();
    var m = L67Model{ .count = 1, .justify = .start };
    const id: core.WidgetId = @fromBackingInt(0x67A0);
    // start / center / end。
    _ = rig.frame(&m, l67Build, 0);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(id).?.y);
    m.cross_align = .center;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 16);
    try std.testing.expectEqual(@as(i32, 12), rig.u.lastRectPx(id).?.y);
    m.cross_align = .end;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 32);
    try std.testing.expectEqual(@as(i32, 25), rig.u.lastRectPx(id).?.y);
    // 子项 cross = fill：高 40。
    m.cross_align = .start;
    m.fill = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 48);
    try std.testing.expectEqual(@as(i32, 40), rig.u.lastRectPx(id).?.h);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(id).?.y);
    // self_align = end 覆盖容器 center。
    m.fill = false;
    m.cross_align = .center;
    m.self_align = .end;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 64);
    try std.testing.expectEqual(@as(i32, 25), rig.u.lastRectPx(id).?.y);
    // 高 50 的 center/end：溢出向起始侧。
    m.self_align = null;
    m.child_h = 50;
    m.cross_align = .center;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 80);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(id).?.y);
    m.cross_align = .end;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 96);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(id).?.y);
    // cross_max = 30 的 fill 子项在容器 center 下：高 30、y = 5。
    m.child_h = 15;
    m.cross_align = .center;
    m.fill = true;
    m.cross_max = 30;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l67Build, 112);
    try std.testing.expectEqual(@as(i32, 30), rig.u.lastRectPx(id).?.h);
    try std.testing.expectEqual(@as(i32, 5), rig.u.lastRectPx(id).?.y);
}

const I34Model = struct {
    clicked: bool = false,
    wheel: core.Vec2 = .{},
    wheel_events: usize = 0,
    wheel_sum: f32 = 0,
    page_seen: bool = false,
    key_down: usize = 0,
    key_up: usize = 0,
    key_repeat: bool = false,
    key_altgr: bool = false,
    chars: usize = 0,
    last_char: u21 = 0,
    presses: usize = 0,
    releases: usize = 0,
    click_events: usize = 0,
};
fn i34Build(ctx: *I34Model, u: *ui.Ui) void {
    const id: core.WidgetId = @fromBackingInt(0x3401);
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 200, .y = 100 } } }, .flags = .{ .focusable = true, .tab_stop = true } });
    const it = u.interact(id, .{ .sense = .{ .hover = true, .click = true, .wheel = true }, .text_input = true });
    if (u.pass == 1) {
        ctx.clicked = it.clicked;
        ctx.wheel = it.wheel;
        ctx.wheel_events = 0;
        ctx.wheel_sum = 0;
        ctx.key_down = 0;
        ctx.key_up = 0;
        ctx.chars = 0;
        ctx.presses = 0;
        ctx.releases = 0;
        ctx.click_events = 0;
        for (u.events(id)) |ev| switch (ev) {
            .wheel => |w| {
                ctx.wheel_events += 1;
                ctx.wheel_sum += w.delta.y + w.delta.x;
                if (w.page) ctx.page_seen = true;
            },
            .key_down => |k| {
                ctx.key_down += 1;
                ctx.key_repeat = k.repeat;
                ctx.key_altgr = k.mods.altgr;
            },
            .key_up => ctx.key_up += 1,
            .char => |c| {
                ctx.chars += 1;
                ctx.last_char = c;
            },
            .press => ctx.presses += 1,
            .release => ctx.releases += 1,
            .click => ctx.click_events += 1,
            else => {},
        };
    }
    u.setFocus(id);
}

fn i34Forbidden(name: []const u8) bool {
    const banned = [_][]const u8{ "touch", "gesture", "pinch", "swipe", "inertia", "multi_touch", "pan" };
    for (banned) |b| if (std.mem.indexOf(u8, name, b) != null) return true;
    return false;
}

test "AC-INPUT-034 分发坐标、键、文本、滚轮与触摸换算" {
    var rig = try M2Rig.create(300, 200, 1.5);
    defer rig.destroy();
    var m = I34Model{};
    _ = rig.frame(&m, i34Build, 0);
    const id: core.WidgetId = @fromBackingInt(0x3401);
    try std.testing.expectEqual(id, rig.u.focusedId());

    // 坐标：客户区 ppx / scale → 根局部 lpx；screen_pos 保留为 ppx。
    rig.u.beginFrame(16, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 16, .data = .{ .mouse_move = .{ .pos = .{ .x = 150, .y = 90 }, .screen_pos = .{ .x = 500, .y = 600 } } } });
    try std.testing.expectEqual(@as(f32, 100), rig.u.pointer_pos.x);
    try std.testing.expectEqual(@as(f32, 60), rig.u.pointer_pos.y);
    try std.testing.expectEqual(core.Vec2i{ .x = 500, .y = 600 }, rig.u.pointerScreen().?);
    rig.u.finishFrame();

    // 键：down/up 拆分，repeat 与 altgr 透传；文本拆为单码点 char。
    rig.u.beginFrame(32, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 32, .data = .{ .key = .{ .vk = .a, .down = true, .repeat = true, .mods = .{ .altgr = true } } } });
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 32, .data = .{ .key = .{ .vk = .a, .down = false, .mods = .{ .ctrl = true } } } });
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 32, .data = .{ .text = "é" } });
    rig.u.build(&m, i34Build);
    rig.u.layoutTree();
    try std.testing.expectEqual(@as(usize, 1), m.key_down);
    try std.testing.expectEqual(@as(usize, 1), m.key_up);
    try std.testing.expect(m.key_repeat);
    try std.testing.expect(m.key_altgr);
    try std.testing.expectEqual(@as(usize, 1), m.chars);
    try std.testing.expectEqual(@as(u21, 0x00E9), m.last_char);
    rig.u.finishFrame();

    // 滚轮：raw / 120；四次 raw=30 累计 1.0 格；不使用 steps。
    platform.Headless.setMetrics(.{ .wheel_lines = .{ .lines = 3 } });
    rig.u.beginFrame(48, true);
    var k: usize = 0;
    while (k < 4) : (k += 1) {
        rig.u.dispatch(.{ .window = rig.win, .time_ms = 48, .data = .{ .wheel = .{ .axis = .vertical, .raw = 30, .steps = 99, .pos = .{ .x = 150, .y = 90 } } } });
    }
    rig.u.build(&m, i34Build);
    rig.u.layoutTree();
    try std.testing.expectEqual(@as(usize, 4), m.wheel_events);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m.wheel_sum, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m.wheel.y, 0.0001);
    try std.testing.expect(!m.page_seen);
    rig.u.finishFrame();
    rig.u.beginFrame(64, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 64, .data = .{ .wheel = .{ .axis = .vertical, .raw = 240, .steps = 1, .pos = .{ .x = 150, .y = 90 } } } });
    rig.u.build(&m, i34Build);
    rig.u.layoutTree();
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), m.wheel_sum, 0.0001);
    try std.testing.expect(!m.page_seen);
    rig.u.finishFrame();
    // wheel_lines = page → 事件 page = true。
    platform.Headless.setMetrics(.{ .wheel_lines = .page });
    m.page_seen = false;
    rig.u.beginFrame(80, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 80, .data = .{ .wheel = .{ .axis = .vertical, .raw = 120, .steps = 1, .pos = .{ .x = 150, .y = 90 } } } });
    rig.u.build(&m, i34Build);
    rig.u.layoutTree();
    try std.testing.expect(m.page_seen);
    rig.u.finishFrame();

    // 触摸/笔以系统提升后的鼠标消息到达：与左键点击一致。
    platform.Headless.setMetrics(.{});
    m.clicked = false;
    rig.u.beginFrame(96, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 96, .data = .{ .mouse_move = .{ .pos = .{ .x = 30, .y = 30 }, .screen_pos = .{ .x = 1, .y = 2 } } } });
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 96, .data = .{ .mouse_button = .{ .button = .left, .down = true, .pos = .{ .x = 30, .y = 30 } } } });
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 96, .data = .{ .mouse_button = .{ .button = .left, .down = false, .pos = .{ .x = 30, .y = 30 } } } });
    rig.u.build(&m, i34Build);
    rig.u.layoutTree();
    try std.testing.expect(m.clicked);
    try std.testing.expectEqual(@as(usize, 1), m.presses);
    try std.testing.expectEqual(@as(usize, 1), m.releases);
    try std.testing.expectEqual(@as(usize, 1), m.click_events);
    rig.u.finishFrame();

    // 公开事件类型中不存在多点触控 / 手势 / 惯性滚动。
    for (@typeInfo(platform.Data).@"union".field_names) |name| try std.testing.expect(!i34Forbidden(name));
    for (@typeInfo(input.NodeEvent).@"union".field_names) |name| try std.testing.expect(!i34Forbidden(name));
}

const F8Model = struct {
    calls: u32 = 0,
    paints: u32 = 0,
    props_seen: usize = 0,
    value_seen: u32 = 0,
};
const F8Props = struct { model: *F8Model, value: u32 };
fn f8Paint(_: *ui.PaintCtx, node: *const ui.Node) void {
    const p: *const F8Props = @ptrCast(@alignCast(node.props.?));
    p.model.paints += 1;
    p.model.props_seen = @intFromPtr(node.props.?);
    p.model.value_seen = p.value;
}
fn f8Build(ctx: *F8Model, u: *ui.Ui) void {
    ctx.calls += 1;
    const p = u.treeAlloc().create(F8Props) catch @panic("F8 props");
    p.* = .{ .model = ctx, .value = 42 };
    _ = u.leaf(@fromBackingInt(0x8F01), .{
        .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 40, .y = 20 } } },
        .paint = f8Paint,
        .props = p,
        .paint_key = 42,
    });
}

const F8Violation = struct {};
const F8ViolationProps = struct { ui: *ui.Ui };
fn f8ViolationPaint(ctx: *ui.PaintCtx, node: *const ui.Node) void {
    _ = ctx;
    const p: *const F8ViolationProps = @ptrCast(@alignCast(node.props.?));
    p.ui.invalidate(.paint); // REQ-FRAME-018：绘制函数内发出失效必须断言
}
fn f8ViolationBuild(ctx: *F8Violation, u: *ui.Ui) void {
    _ = ctx;
    const p = u.treeAlloc().create(F8ViolationProps) catch @panic("F8 props");
    p.* = .{ .ui = u };
    _ = u.leaf(@fromBackingInt(0x8F11), .{
        .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 40, .y = 20 } } },
        .paint = f8ViolationPaint,
        .props = p,
        .paint_key = 1,
    });
}

test "AC-FRAME-008 纯绘制帧、构建不重入、属性稳定与绘制内失效断言" {
    var rig = try M2Rig.create(120, 80, 1.0);
    var m = F8Model{};
    defer rig.destroy();
    _ = rig.frame(&m, f8Build, 0);
    try std.testing.expectEqual(@as(u32, 1), m.calls);
    try std.testing.expectEqual(@as(u32, 1), m.paints);
    const props0 = m.props_seen;
    try std.testing.expectEqual(@as(u32, 42), m.value_seen);
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        rig.u.invalidateNode(@fromBackingInt(0x8F01), .paint);
        rig.u.beginFrame(@intCast(i * 16), true);
        rig.u.build(&m, f8Build);
        rig.u.layoutTree();
        const painted = rig.u.paint(&rig.surface);
        try std.testing.expect(painted);
        try std.testing.expectEqual(@as(u32, 0), rig.u.build_passes);
        rig.u.finishFrame();
    }
    try std.testing.expectEqual(@as(u32, 1), m.calls);
    try std.testing.expectEqual(@as(u32, 101), m.paints);
    try std.testing.expectEqual(props0, m.props_seen);
    try std.testing.expectEqual(@as(u32, 42), m.value_seen);

    // 调试构建：绘制函数内调用置脏 API 必须中止。用子进程隔离断言。
    if (comptime @import("builtin").os.tag == .linux) {
        const pid = std.os.linux.fork();
        if (pid == 0) {
            const null_fd = std.os.linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
            if (@as(isize, @bitCast(null_fd)) >= 0) {
                _ = std.os.linux.dup2(@intCast(null_fd), 2);
                _ = std.os.linux.close(@intCast(null_fd));
            }
            var child = M2Rig.create(120, 80, 1.0) catch std.os.linux.exit(2);
            var cm = F8Violation{};
            _ = child.frame(&cm, f8ViolationBuild, 0);
            std.os.linux.exit(0);
        }
        var status: i32 = 0;
        _ = std.os.linux.waitpid(@intCast(pid), &status, 0);
        try std.testing.expect(status != 0);
    }
}

test "AC-LAYOUT-005 Row 内宽、gap、fixed/grow 几何与 lastRect 换算" {
    var rig = try M2Rig.create(500, 100, 1.25);
    defer rig.destroy();
    _ = rig.frame(&L5Model{}, l5Build, 0);
    const a = rig.u.lastRectPx(@fromBackingInt(0x5001)).?;
    const b = rig.u.lastRectPx(@fromBackingInt(0x5002)).?;
    const c = rig.u.lastRectPx(@fromBackingInt(0x5003)).?;
    try std.testing.expectEqual(@as(i32, 10), a.x);
    try std.testing.expectEqual(@as(i32, 70), b.x);
    try std.testing.expectEqual(@as(i32, 285), c.x);
    try std.testing.expectEqual(@as(i32, 50), a.w);
    try std.testing.expectEqual(@as(i32, 205), b.w);
    try std.testing.expectEqual(@as(i32, 205), c.w);
    try std.testing.expectEqual(@as(i32, 80), a.h);
    try std.testing.expectEqual(@as(i32, 490), c.x + c.w);
    const al = rig.u.lastRect(@fromBackingInt(0x5001)).?;
    const bl = rig.u.lastRect(@fromBackingInt(0x5002)).?;
    const cl = rig.u.lastRect(@fromBackingInt(0x5003)).?;
    try std.testing.expectApproxEqAbs(@as(f32, 40), al.w, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 164), bl.w, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 164), cl.w, 0.001);

    var rig2 = try M2Rig.create(200, 120, 1.0);
    defer rig2.destroy();
    _ = rig2.frame(&L5Model{}, l5EmptyBuild, 0);
    try std.testing.expectEqual(core.Vec2{ .x = 16, .y = 16 }, rig2.u.minWindowSize());
}
const L5Model = struct {};
fn l5Build(_: *const L5Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .md });
    _ = u.leaf(@fromBackingInt(0x5001), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fill, .content = .{ .size = .{ .x = 40, .y = 0 } } } });
    _ = u.leaf(@fromBackingInt(0x5002), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 0, .y = 0 } } } });
    _ = u.leaf(@fromBackingInt(0x5003), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 0, .y = 0 } } } });
    u.endRow();
}
fn l5EmptyBuild(_: *const L5Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .fit, .cross = .fit, .padding = core.Insets.all(8) });
    u.endRow();
}

const L8Model = struct { order: [3]u8 = @splat(0), n: usize = 0 };
const L8Slot = struct { model: *L8Model, id: u8 };
fn l8Paint(_: *ui.PaintCtx, node: *const ui.Node) void {
    const s: *const L8Slot = @ptrCast(@alignCast(node.props.?));
    if (s.model.n < s.model.order.len) s.model.order[s.model.n] = s.id;
    s.model.n += 1;
}
fn l8Children(u: *ui.Ui, m: *L8Model) void {
    const a = u.treeAlloc().create(L8Slot) catch @panic("L8");
    a.* = .{ .model = m, .id = 1 };
    _ = u.leaf(@fromBackingInt(0x8001), .{
        .layout = .{ .kind = .leaf, .main = .fixedSize(80), .cross = .fixedSize(30), .content = .{ .size = .{ .x = 80, .y = 30 } }, .self_main_align = .end, .self_align = .end },
        .paint = l8Paint,
        .props = a,
    });
    const b = u.treeAlloc().create(L8Slot) catch @panic("L8");
    b.* = .{ .model = m, .id = 2 };
    _ = u.leaf(@fromBackingInt(0x8002), .{
        .layout = .{ .kind = .leaf, .main = .fit_shrink, .cross = .fit, .main_min = 40, .content = .{ .size = .{ .x = 300, .y = 20 } } },
        .paint = l8Paint,
        .props = b,
    });
    const c = u.treeAlloc().create(L8Slot) catch @panic("L8");
    c.* = .{ .model = m, .id = 3 };
    _ = u.leaf(@fromBackingInt(0x8003), .{
        .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 0, .y = 0 } } },
        .paint = l8Paint,
        .props = c,
    });
}
fn l8Build(m: *L8Model, u: *ui.Ui) void {
    _ = u.beginStack(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    l8Children(u, m);
    u.endStack();
}
fn l8NestedBuild(m: *L8Model, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fit });
    _ = u.beginStack(@src(), .{ .main = .fit, .cross = .fit });
    l8Children(u, m);
    u.endStack();
    u.endColumn();
}

test "AC-LAYOUT-008 Stack 对齐、fit_shrink 夹紧、绘制顺序与期望尺寸" {
    var rig = try M2Rig.create(200, 100, 1.0);
    defer rig.destroy();
    var m = L8Model{};
    _ = rig.frame(&m, l8Build, 0);
    const a = rig.u.lastRectPx(@fromBackingInt(0x8001)).?;
    const b = rig.u.lastRectPx(@fromBackingInt(0x8002)).?;
    const c = rig.u.lastRectPx(@fromBackingInt(0x8003)).?;
    try std.testing.expectEqual(core.RectI{ .x = 120, .y = 70, .w = 80, .h = 30 }, a);
    try std.testing.expectEqual(@as(i32, 200), b.w);
    try std.testing.expectEqual(@as(i32, 20), b.h);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 200, .h = 100 }, c);
    // 绘制顺序 A、B、C（C 最后，位于最上）。
    try std.testing.expectEqual(@as(usize, 3), m.n);
    try std.testing.expectEqual([3]u8{ 1, 2, 3 }, m.order);
    m.n = 0;
    rig.u.invalidateNode(@fromBackingInt(0x8001), .paint);
    rig.u.invalidateNode(@fromBackingInt(0x8002), .paint);
    rig.u.invalidateNode(@fromBackingInt(0x8003), .paint);
    rig.u.beginFrame(16, true);
    _ = rig.u.paint(&rig.surface);
    rig.u.finishFrame();
    try std.testing.expectEqual([3]u8{ 1, 2, 3 }, m.order);

    // 无限制（高度无界、宽度大于自然宽）测量：期望尺寸 (300, 30)。
    var rig2 = try M2Rig.create(500, 400, 1.0);
    defer rig2.destroy();
    var m2 = L8Model{};
    _ = rig2.frame(&m2, l8NestedBuild, 0);
    try std.testing.expectEqual(core.Vec2{ .x = 300, .y = 30 }, rig2.u.minWindowSize());
}

test "AC-LAYOUT-010 容器 fit_shrink 按 fit 处理并警告，叶子收缩到 min" {
    var rig = try M2Rig.create(300, 100, 1.0);
    defer rig.destroy();
    LogCapture.warns = 0;
    core.log.setSink(LogCapture.sink);
    defer core.log.setSink(null);
    _ = rig.frame(&L10Model{}, l10ContainerBuild, 0);
    try std.testing.expectEqual(@as(i32, 150), rig.u.lastRectPx(@fromBackingInt(0x1001)).?.w);
    try std.testing.expectEqual(@as(usize, 1), LogCapture.warns);

    var rig2 = try M2Rig.create(300, 100, 1.0);
    defer rig2.destroy();
    LogCapture.warns = 0;
    _ = rig2.frame(&L10Model{}, l10LeafBuild, 0);
    try std.testing.expectEqual(@as(i32, 100), rig2.u.lastRectPx(@fromBackingInt(0x1002)).?.w);
    try std.testing.expectEqual(@as(usize, 0), LogCapture.warns);
}
const L10Model = struct {};
fn l10ContainerBuild(_: *const L10Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .fixedSize(100), .cross = .fixedSize(40) });
    _ = u.beginNode(@fromBackingInt(0x1001), .{ .layout = .{ .kind = .column, .main = .fit_shrink, .cross = .fit } });
    _ = u.leaf(@fromBackingInt(0x1003), .{ .layout = .{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = 150, .y = 20 } } } });
    u.endNode();
    u.endRow();
}
fn l10LeafBuild(_: *const L10Model, u: *ui.Ui) void {
    _ = u.beginRow(@src(), .{ .main = .fixedSize(100), .cross = .fixedSize(40) });
    _ = u.leaf(@fromBackingInt(0x1002), .{ .layout = .{ .kind = .leaf, .main = .fit_shrink, .main_min = 30, .cross = .fit, .content = .{ .size = .{ .x = 150, .y = 20 } } } });
    u.endRow();
}

test "AC-LAYOUT-009 测量缓存：非确定放大命中、确定逐分量相等" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    _ = rig.frame(&L9Model{}, l9Build, 0);
    const col = rig.u.getNode(@fromBackingInt(0x9001)).?;
    const unbounded = layout.Limit{ .w = layout.unbounded, .h = layout.unbounded };

    rig.u.measured_nodes = 0;
    const s1 = rig.u.measureForTest(col, unbounded, .natural);
    try std.testing.expectEqual(@as(i32, 60), s1.h);
    try std.testing.expectEqual(@as(u32, 4), rig.u.measured_nodes);

    rig.u.measured_nodes = 0;
    const s2 = rig.u.measureForTest(col, unbounded, .natural);
    try std.testing.expectEqual(@as(i32, 60), s2.h);
    try std.testing.expectEqual(@as(u32, 0), rig.u.measured_nodes);

    // 非确定 h=100：缓存限制更大且结果 60 可放入 → 命中。
    rig.u.measured_nodes = 0;
    const s3 = rig.u.measureForTest(col, .{ .w = layout.unbounded, .h = 100 }, .natural);
    try std.testing.expectEqual(@as(i32, 60), s3.h);
    try std.testing.expectEqual(@as(u32, 0), rig.u.measured_nodes);

    // 非确定 h=40：结果 60 放不下 → 未命中并重新测量。
    rig.u.measured_nodes = 0;
    _ = rig.u.measureForTest(col, .{ .w = layout.unbounded, .h = 40 }, .natural);
    try std.testing.expect(rig.u.measured_nodes > 0);

    // 确定 h=200：必须逐分量相等才命中；grow 吸收 200-50=150。
    rig.u.measured_nodes = 0;
    const s5 = rig.u.measureForTest(col, .{ .w = layout.unbounded, .h = 200, .definite_h = true }, .natural);
    try std.testing.expectEqual(@as(i32, 200), s5.h);
    try std.testing.expect(rig.u.measured_nodes > 0);
    rig.u.measured_nodes = 0;
    const s6 = rig.u.measureForTest(col, .{ .w = layout.unbounded, .h = 200, .definite_h = true }, .natural);
    try std.testing.expectEqual(@as(i32, 200), s6.h);
    try std.testing.expectEqual(@as(u32, 0), rig.u.measured_nodes);
}
const L9Model = struct {};
fn l9Build(_: *const L9Model, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x9001), .{ .layout = .{ .kind = .column, .main = .fit, .cross = .fit } });
    _ = u.leaf(@fromBackingInt(0x9002), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fit, .content = .{ .size = .{ .x = 10, .y = 20 } } } });
    _ = u.leaf(@fromBackingInt(0x9003), .{ .layout = .{ .kind = .leaf, .main = .fit, .cross = .fit, .content = .{ .size = .{ .x = 10, .y = 30 } } } });
    _ = u.leaf(@fromBackingInt(0x9004), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .main_min = 10, .cross = .fit, .content = .{ .size = .{ .x = 10, .y = 0 } } } });
    u.endNode();
}

const StormCapture = struct {
    var warns: usize = 0;
    var buf: [512]u8 = undefined;
    var len: usize = 0;
    fn sink(level: core.log.Level, _: []const u8, msg: []const u8) void {
        if (level != .warn) return;
        warns += 1;
        const n = @min(msg.len, buf.len);
        @memcpy(buf[0..n], msg[0..n]);
        len = n;
    }
};
const F19Model = struct {};
fn f19Build(_: *F19Model, u: *ui.Ui) void {
    u.requestRebuildAt(@src());
}

test "AC-FRAME-019 requestRebuild 每帧两遍、持续下一帧与第 8 帧风暴警告" {
    var rig = try M2Rig.create(160, 100, 1.0);
    defer rig.destroy();
    var m = F19Model{};
    StormCapture.warns = 0;
    StormCapture.len = 0;
    core.log.setSink(StormCapture.sink);
    defer core.log.setSink(null);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        _ = rig.frame(&m, f19Build, @intCast(i * 16));
        try std.testing.expectEqual(@as(u32, 2), rig.u.build_passes);
        try std.testing.expect(rig.u.needsFrame());
        if (i < 7) try std.testing.expectEqual(@as(usize, 0), StormCapture.warns);
    }
    try std.testing.expectEqual(@as(usize, 1), StormCapture.warns);
    const msg = StormCapture.buf[0..StormCapture.len];
    try std.testing.expect(std.mem.indexOf(u8, msg, "all.zig:") != null);
    // 继续两帧：两遍与下一帧保持，警告不重复。
    var k: usize = 0;
    while (k < 2) : (k += 1) {
        _ = rig.frame(&m, f19Build, @intCast((8 + k) * 16));
        try std.testing.expectEqual(@as(u32, 2), rig.u.build_passes);
        try std.testing.expect(rig.u.needsFrame());
    }
    try std.testing.expectEqual(@as(usize, 1), StormCapture.warns);
}

const F12Model = struct { clicked: u32 = 0, build_now: u64 = 0 };
var f12_paint_now: u64 = 0;
fn f12Paint(ctx: *ui.PaintCtx, node: *const ui.Node) void {
    _ = node;
    f12_paint_now = ctx.now;
}
fn f12Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F12Model = @ptrCast(@alignCast(ctx));
    m.build_now = u.now();
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .sm });
    if (widgets.button(u, @src(), "阶段", .{ .debug_name = "f12b", .key = ui.Key.str("f12b") }).clicked) m.clicked += 1;
    _ = u.leaf(@fromBackingInt(0xF1201), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 20, .y = 20 } } }, .paint = f12Paint });
    u.endColumn();
}

const F12Phases = struct {
    var ui_ptr: ?*ui.Ui = null;
    var phases: [16]ui.FramePhase = undefined;
    var nows: [16]u64 = undefined;
    var n: usize = 0;
    fn reset(u: *ui.Ui) void {
        ui_ptr = u;
        n = 0;
    }
    fn hook(_: ?*anyopaque, phase: ui.FramePhase) void {
        if (n < phases.len) {
            phases[n] = phase;
            nows[n] = ui_ptr.?.now();
            n += 1;
        }
        platform.Headless.advanceMs(7);
    }
};

test "AC-FRAME-012 帧阶段顺序固定且帧内时间戳一致" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app.deinit();
    var m = F12Model{};
    app.renderOnce(&m, f12Build);
    const btn = findByName(app.ui_state.current_root, "f12b") orelse return error.TestUnexpectedResult;
    const cx = btn.abs.x + @divTrunc(btn.abs.w, 2);
    const cy = btn.abs.y + @divTrunc(btn.abs.h, 2);
    platform.Headless.injectMouseMove(.{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = cx, .y = cy }, .{});

    F12Phases.reset(&app.ui_state);
    ui.test_phase_hook = F12Phases.hook;
    ui.test_phase_ctx = null;
    defer {
        ui.test_phase_hook = null;
        ui.test_phase_ctx = null;
    }
    const t0 = platform.nowMs();
    const stepped = app.step();
    try std.testing.expect(stepped);
    try std.testing.expectEqual(@as(u32, 1), m.clicked);
    try std.testing.expectEqual(@as(u32, 2), app.ui_state.build_passes);
    const expected = [_]ui.FramePhase{ .collect, .dispatch, .build, .layout, .damage, .paint, .submit, .finish };
    try std.testing.expectEqual(expected.len, F12Phases.n);
    try std.testing.expectEqualSlices(ui.FramePhase, expected[0..], F12Phases.phases[0..expected.len]);
    const frame_now = F12Phases.nows[0];
    for (F12Phases.nows[0..F12Phases.n]) |n| try std.testing.expectEqual(frame_now, n);
    try std.testing.expectEqual(frame_now, m.build_now);
    try std.testing.expectEqual(frame_now, f12_paint_now);
    // 钩子在每个阶段推进了假时钟，但帧内时间戳保持不变。
    try std.testing.expectEqual(t0 + 7 * expected.len, platform.nowMs());
    try std.testing.expect(frame_now == t0);
}

const F17Model = struct { count: usize = 0 };
fn f17Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F17Model = @ptrCast(@alignCast(ctx));
    const id: core.WidgetId = @fromBackingInt(0xF1701);
    const r = u.lastRect(id);
    const n: usize = if (r) |rect| @max(1, @as(usize, @intFromFloat(@floor(rect.w / 20.0)))) else 1;
    m.count = n;
    _ = u.beginNode(id, .{
        .layout = .{ .kind = .row, .main = .{ .grow = 1 }, .cross = .fill },
        .flags = .{ .layout_feedback = true },
    });
    var i: usize = 0;
    while (i < n) : (i += 1) {
        _ = u.leaf(@fromBackingInt(@intCast(0xF1710 + i)), .{
            .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 20, .y = 20 } } },
        });
    }
    u.endNode();
}

test "AC-FRAME-017 布局反馈首帧两遍、改宽一遍、稳定零遍" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app.deinit();
    var m = F17Model{};
    app.build_ctx = &m;
    app.build_fn = f17Build;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(usize, 12), m.count);
    try std.testing.expectEqual(@as(u32, 2), app.ui_state.build_passes);

    // 宽度改变：起始帧无初始构建，仅布局反馈触发一遍。
    app.window.setClientSize(.{ .w = 300, .h = 160 });
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(usize, 15), m.count);
    try std.testing.expectEqual(@as(u32, 1), app.ui_state.build_passes);

    // 宽度不变：只有绘制帧，构建遍数为 0。
    app.ui_state.invalidate(.paint);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(usize, 15), m.count);
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(!app.ui_state.needsFrame());
}

const L26Model = struct { count: usize = 0, divergent: bool = false, no_last_rect: bool = false, gen: i32 = 0 };
fn l26Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *L26Model = @ptrCast(@alignCast(ctx));
    const id: core.WidgetId = @fromBackingInt(0xF2601);
    var n: usize = 3;
    if (!m.no_last_rect) {
        const r = u.lastRect(id);
        n = if (r) |rect| @max(1, @as(usize, @intFromFloat(@floor(rect.w / 20.0)))) else 1;
        if (m.divergent) n += 1;
    }
    m.count = n;
    if (m.divergent) m.gen += 1;
    const cross: layout.CrossExtent = if (m.divergent)
        .{ .fixed = 20 + @as(f32, @floatFromInt(m.gen)) }
    else
        .fit;
    _ = u.beginNode(id, .{
        .layout = .{ .kind = .row, .main = .{ .grow = 1 }, .cross = cross },
        .flags = .{ .layout_feedback = true },
    });
    var i: usize = 0;
    while (i < n) : (i += 1) {
        _ = u.leaf(@fromBackingInt(@intCast(0xF2610 + i)), .{
            .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 20, .y = 20 } } },
        });
    }
    u.endNode();
}

const L26Phases = struct {
    var phases: [16]ui.FramePhase = undefined;
    var n: usize = 0;
    fn reset() void {
        n = 0;
    }
    fn hook(_: ?*anyopaque, phase: ui.FramePhase) void {
        if (n < phases.len) phases[n] = phase;
        n += 1;
    }
};

test "AC-LAYOUT-026 反馈第二遍只一次、仍发散置构建脏、未调用 lastRect 视为变化" {
    // 收敛：首帧阶段为 build,layout,build,layout,damage...，检查在损伤之前。
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app.deinit();
    var m = L26Model{};
    app.build_ctx = &m;
    app.build_fn = l26Build;
    L26Phases.reset();
    ui.test_phase_hook = L26Phases.hook;
    defer {
        ui.test_phase_hook = null;
        ui.test_phase_ctx = null;
    }
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 2), app.ui_state.build_passes);
    try std.testing.expectEqual(@as(usize, 12), m.count);
    try std.testing.expect(L26Phases.n >= 8);
    try std.testing.expectEqual(ui.FramePhase.build, L26Phases.phases[2]);
    try std.testing.expectEqual(ui.FramePhase.layout, L26Phases.phases[3]);
    try std.testing.expectEqual(ui.FramePhase.build, L26Phases.phases[4]);
    try std.testing.expectEqual(ui.FramePhase.layout, L26Phases.phases[5]);
    try std.testing.expectEqual(ui.FramePhase.damage, L26Phases.phases[6]);
    ui.test_phase_hook = null;

    // 发散：第二遍后仍不同 → 不再第三遍，置构建脏请求下一帧。
    var app2 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app2.deinit();
    var m2 = L26Model{ .divergent = true };
    app2.build_ctx = &m2;
    app2.build_fn = l26Build;
    app2.ui_state.invalidate(.build);
    try std.testing.expect(app2.step());
    try std.testing.expectEqual(@as(u32, 2), app2.ui_state.build_passes);
    try std.testing.expectEqual(@as(usize, 13), m2.count);
    try std.testing.expect(app2.ui_state.needsFrame());
    try std.testing.expect(app2.step());
    try std.testing.expectEqual(@as(u32, 2), app2.ui_state.build_passes);
    try std.testing.expectEqual(@as(usize, 13), m2.count);
    try std.testing.expect(app2.ui_state.needsFrame());

    // 未调用 lastRect：始终视为所见为空 → 每帧都需要额外一遍，但不超过两遍。
    var app3 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app3.deinit();
    var m3 = L26Model{ .no_last_rect = true };
    app3.build_ctx = &m3;
    app3.build_fn = l26Build;
    app3.ui_state.invalidate(.build);
    try std.testing.expect(app3.step());
    try std.testing.expectEqual(@as(u32, 2), app3.ui_state.build_passes);
    try std.testing.expectEqual(@as(usize, 3), m3.count);
    try std.testing.expect(app3.ui_state.needsFrame());
    try std.testing.expect(app3.step());
    try std.testing.expectEqual(@as(u32, 2), app3.ui_state.build_passes);
    try std.testing.expectEqual(@as(usize, 3), m3.count);
}

const F15Model = struct {
    builds: u32 = 0,
    depth: u32 = 0,
    max_depth: u32 = 0,
    clicked: u32 = 0,
    scheduled: bool = false,
    ui: ?*ui.Ui = null,
    commit_before: u64 = 0,
    gen_before: u64 = 0,
    after_ran: u32 = 0,
    after_commit: u64 = 0,
    after_gen: u64 = 0,
    after_dirty_clear: bool = false,
    after_depth: u32 = 0,
};
fn f15After(ctx: ?*anyopaque) void {
    const m: *F15Model = @ptrCast(@alignCast(ctx.?));
    const u = m.ui.?;
    m.after_ran += 1;
    m.after_commit = u.frame_count;
    m.after_gen = u.frameGeneration();
    m.after_dirty_clear = u.dirty == .none;
    m.after_depth = m.depth;
    // 帧后动作中的失效必须进入独立的新帧。
    u.invalidate(.build);
}
fn f15Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F15Model = @ptrCast(@alignCast(ctx));
    m.ui = u;
    m.depth += 1;
    if (m.depth > m.max_depth) m.max_depth = m.depth;
    m.builds += 1;
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8) });
    const r = widgets.button(u, @src(), "after", .{ .debug_name = "f15b", .key = ui.Key.str("f15b") });
    if (r.clicked) {
        m.clicked += 1;
        if (!m.scheduled) {
            m.scheduled = true;
            m.commit_before = u.frame_count;
            m.gen_before = u.frameGeneration();
            u.afterFrame(.{ .ctx = m, .func = f15After });
        }
    }
    u.endColumn();
    m.depth -= 1;
}
fn f15BadBuild(_: *anyopaque, _: *ui.Ui) void {
    _ = platform.messageBox(null, "t", "b", .{});
}

test "AC-FRAME-015 afterFrame 在提交/帧状态清除后执行且失效产生独立帧" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app.deinit();
    var m = F15Model{};
    app.build_ctx = &m;
    app.build_fn = f15Build;
    app.renderOnce(&m, f15Build);
    const btn = findByName(app.ui_state.current_root, "f15b") orelse return error.TestUnexpectedResult;
    const cx = btn.abs.x + @divTrunc(btn.abs.w, 2);
    const cy = btn.abs.y + @divTrunc(btn.abs.h, 2);
    platform.Headless.injectMouseMove(.{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = cx, .y = cy }, .{});
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 1), m.after_ran);
    try std.testing.expectEqual(m.commit_before + 1, m.after_commit);
    try std.testing.expectEqual(m.gen_before + 1, m.after_gen);
    try std.testing.expect(m.after_dirty_clear);
    try std.testing.expectEqual(@as(u32, 0), m.after_depth);
    try std.testing.expectEqual(@as(u32, 1), m.max_depth);
    try std.testing.expect(app.ui_state.needsFrame());
    const builds0 = m.builds;
    try std.testing.expect(app.step());
    try std.testing.expect(m.builds > builds0);
    try std.testing.expectEqual(@as(u32, 1), m.max_depth);
    try std.testing.expectEqual(@as(u32, 1), m.after_ran);

    // 调试构建：构建函数内调用阻塞 messageBox 必须断言中止。
    if (comptime @import("builtin").os.tag == .linux) {
        const pid = std.os.linux.fork();
        if (pid == 0) {
            const null_fd = std.os.linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
            if (@as(isize, @bitCast(null_fd)) >= 0) {
                _ = std.os.linux.dup2(@intCast(null_fd), 2);
                _ = std.os.linux.close(@intCast(null_fd));
            }
            var child = nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 120, .h = 80 } }) catch std.os.linux.exit(2);
            var dummy: u8 = 0;
            child.renderOnce(@ptrCast(&dummy), f15BadBuild);
            std.os.linux.exit(0);
        }
        var status: i32 = 0;
        _ = std.os.linux.waitpid(@intCast(pid), &status, 0);
        try std.testing.expect(status != 0);
    }
}

const ErrCapture = struct {
    var errs: usize = 0;
    var buf: [512]u8 = undefined;
    var len: usize = 0;
    fn sink(level: core.log.Level, _: []const u8, msg: []const u8) void {
        if (level != .err) return;
        errs += 1;
        const n = @min(msg.len, buf.len);
        @memcpy(buf[0..n], msg[0..n]);
        len = n;
    }
};
fn f16Build(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    // 故意遗漏 endColumn。
}

test "AC-FRAME-016 容器不配对：发布路径记录 err 并完成帧，调试构建中止" {
    ui.test_force_soft_unbalanced = true;
    defer ui.test_force_soft_unbalanced = false;
    ErrCapture.errs = 0;
    ErrCapture.len = 0;
    core.log.setSink(ErrCapture.sink);
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 200, .h = 120 } });
    var dummy: u8 = 0;
    app.build_ctx = @ptrCast(&dummy);
    app.build_fn = f16Build;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    core.log.setSink(null);
    app.deinit();
    try std.testing.expectEqual(@as(usize, 1), ErrCapture.errs);
    const msg = ErrCapture.buf[0..ErrCapture.len];
    try std.testing.expect(std.mem.indexOf(u8, msg, "all.zig:") != null);

    // 调试路径：子进程验证断言中止。
    ui.test_force_soft_unbalanced = false;
    if (comptime @import("builtin").os.tag == .linux) {
        const pid = std.os.linux.fork();
        if (pid == 0) {
            const null_fd = std.os.linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
            if (@as(isize, @bitCast(null_fd)) >= 0) {
                _ = std.os.linux.dup2(@intCast(null_fd), 2);
                _ = std.os.linux.close(@intCast(null_fd));
            }
            var child = nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 120, .h = 80 } }) catch std.os.linux.exit(2);
            var d: u8 = 0;
            child.renderOnce(@ptrCast(&d), f16Build);
            std.os.linux.exit(0);
        }
        var status: i32 = 0;
        _ = std.os.linux.waitpid(@intCast(pid), &status, 0);
        try std.testing.expect(status != 0);
    }
}

var f14_counter: u32 = 0;
var f14_text: [32]u8 = undefined;
fn f14BadBuild(_: *anyopaque, u: *ui.Ui) void {
    f14_counter += 1;
    const s = std.fmt.bufPrint(&f14_text, "{d}", .{f14_counter}) catch "?";
    _ = widgets.label(u, @src(), s, .{ .debug_name = "bad-counter" });
}

test "AC-FRAME-014 控件总览幂等校验与构建中自增反例" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 800, .h = 600 } });
    defer app.deinit();
    var model = try gallery.Model.init(std.testing.allocator);
    defer model.deinit();
    app.ui_state.setTheme(&app.theme_state);
    const ctx: *anyopaque = @ptrCast(&model);
    const ok = app.ui_state.checkIdempotence(ctx, gallery.build);
    try std.testing.expectEqual(@as(usize, 0), ok.differences);

    var app2 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 200, .h = 120 } });
    defer app2.deinit();
    f14_counter = 0;
    app2.ui_state.setTheme(&app2.theme_state);
    var dummy: u8 = 0;
    const bad = app2.ui_state.checkIdempotence(@as(*anyopaque, @ptrCast(&dummy)), f14BadBuild);
    try std.testing.expect(bad.differences > 0);
    try std.testing.expect(bad.first_name != null);
    try std.testing.expectEqualStrings("bad-counter", bad.first_name.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.first_file, "all.zig") != null);
}

const L13Model = struct {};
fn l13Layout(u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x1301), .{
        .layout = .{ .kind = .row, .main = .fit, .cross = .fit, .padding = core.Insets.all(12), .gap = .sm },
    });
    _ = u.leaf(@fromBackingInt(0x1302), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(80), .cross = .fixedSize(24), .content = .{ .size = .{ .x = 80, .y = 24 } } } });
    _ = u.leaf(@fromBackingInt(0x1303), .{ .layout = .{ .kind = .leaf, .main = .fit_shrink, .main_min = 40, .cross = .fixedSize(24), .content = .{ .size = .{ .x = 200, .y = 24 } } } });
    _ = u.leaf(@fromBackingInt(0x1304), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .main_min = 0, .cross = .fixedSize(24), .content = .{ .size = .{ .x = 0, .y = 24 } } } });
    _ = u.leaf(@fromBackingInt(0x1305), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(60), .cross = .fixedSize(24), .content = .{ .size = .{ .x = 60, .y = 24 } } } });
    u.endNode();
}
fn l13Build(_: *const L13Model, u: *ui.Ui) void {
    l13Layout(u);
}
fn l13AppBuild(_: *anyopaque, u: *ui.Ui) void {
    l13Layout(u);
}

test "AC-LAYOUT-013 min 模式期望尺寸、缩放与缓存独立" {
    var rig = try M2Rig.create(800, 600, 1.0);
    defer rig.destroy();
    _ = rig.frame(&L13Model{}, l13Build, 0);
    const row = rig.u.getNode(@fromBackingInt(0x1301)).?;
    const unb = layout.Limit{ .w = layout.unbounded, .h = layout.unbounded };
    const mn = rig.u.measureForTest(row, unb, .min);
    try std.testing.expectEqual(@as(i32, 216), mn.w);
    try std.testing.expectEqual(@as(i32, 48), mn.h);
    const nat = rig.u.measureForTest(row, unb, .natural);
    try std.testing.expectEqual(@as(i32, 376), nat.w);
    try std.testing.expectEqual(@as(i32, 48), nat.h);
    // 先 min 后 natural，两种模式缓存互不影响。
    const nat2 = rig.u.measureForTest(row, unb, .natural);
    try std.testing.expectEqual(nat.w, nat2.w);
    try std.testing.expectEqual(nat.h, nat2.h);
    try std.testing.expectEqual(core.Vec2{ .x = 216, .y = 48 }, rig.u.minWindowSize());

    var rig2 = try M2Rig.create(800, 600, 1.5);
    defer rig2.destroy();
    _ = rig2.frame(&L13Model{}, l13Build, 0);
    const row2 = rig2.u.getNode(@fromBackingInt(0x1301)).?;
    const natp = rig2.u.measureForTest(row2, unb, .natural);
    const minp = rig2.u.measureForTest(row2, unb, .min);
    try std.testing.expectEqual(@as(i32, 564), natp.w);
    try std.testing.expectEqual(@as(i32, 72), natp.h);
    try std.testing.expectEqual(@as(i32, 324), minp.w);
    try std.testing.expectEqual(@as(i32, 72), minp.h);
    try std.testing.expectEqual(core.Vec2{ .x = 216, .y = 48 }, rig2.u.minWindowSize());
}

test "AC-LAYOUT-013 WindowOptions.min_size 合并与最小尺寸通知去重" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 400, .h = 300 } });
    defer app.deinit();
    var m = L13Model{};
    app.ui_state.setTheme(&app.theme_state);
    app.renderOnce(&m, l13AppBuild);
    const n0 = platform.Headless.minSizeChanges();
    try std.testing.expect(n0 > 0);
    app.ui_state.invalidate(.layout);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(n0, platform.Headless.minSizeChanges());

    var dummy: u8 = 0;
    const w = try app.createWindow(.{ .title = "min", .min_size = .{ .w = 300, .h = 40 } }, .{ .build = l13AppBuild, .ctx = @ptrCast(&dummy) });
    w.build();
    try std.testing.expectEqual(core.Size{ .w = 300, .h = 48 }, w.minWindowSize());
}

const L14Model = struct {
    axes: layout.ScrollAxes = .vertical,
    bar_v: layout.BarPolicy = .auto,
    bar_h: layout.BarPolicy = .auto,
    off_y: f32 = 0,
    content_w: f32 = 500,
    content_h: f32 = 300,
};
fn l14Build(ctx: *L14Model, u: *ui.Ui) void {
    const s = u.beginScroll(@src(), .{ .main = .fixedSize(200), .cross = .fixedSize(100) }, .{
        .axes = ctx.axes,
        .bar_v = ctx.bar_v,
        .bar_h = ctx.bar_h,
        .offset = .{ .x = 0, .y = ctx.off_y },
    });
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fill });
    _ = u.leaf(@fromBackingInt(0x1402), .{
        .layout = .{
            .kind = .leaf,
            .main = .fixedSize(ctx.content_h),
            .cross = .fixedSize(ctx.content_w),
            .content = .{ .size = .{ .x = ctx.content_w, .y = ctx.content_h } },
        },
    });
    u.endColumn();
    u.endScroll();
    _ = s;
}

test "AC-LAYOUT-014 Scroll 滚动条策略、内容尺寸与双轴角块" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    // scroll 节点由 beginScroll 自动生成 ID；按内容节点反查其父节点。
    var m = L14Model{};
    _ = rig.frame(&m, l14Build, 0);
    const leaf = rig.u.getNode(@fromBackingInt(0x1402)).?;
    const scroll_id = leaf.parent.?.parent.?.id;
    const a = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 188), a.content.x);
    try std.testing.expectEqual(@as(f32, 300), a.content.y);
    try std.testing.expectEqual(@as(f32, 188), a.viewport.w);
    try std.testing.expectEqual(@as(i32, 200), @as(i32, @intFromFloat(a.max_offset.y)));
    try std.testing.expectEqual(core.RectI{ .x = 188, .y = 0, .w = 12, .h = 100 }, a.bar_v.?);
    try std.testing.expect(a.bar_h == null);
    try std.testing.expect(rig.u.lastScrollAxisLimit().?.h >= layout.unbounded);

    // bar_v = never：不占位，滚轮请求偏移仍生效。
    m.bar_v = .never;
    m.off_y = 50;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l14Build, 16);
    const b = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 200), b.content.x);
    try std.testing.expectEqual(@as(f32, 50), b.offset.y);
    try std.testing.expect(b.bar_v == null);

    // bar_v = always 且内容不足：仍占位，max_offset = 0。
    m.bar_v = .always;
    m.off_y = 0;
    m.content_h = 80;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l14Build, 32);
    const c = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 188), c.viewport.w);
    try std.testing.expectEqual(@as(f32, 0), c.max_offset.y);
    try std.testing.expect(c.bar_v != null);

    // 双轴：两条均显示，右下角留 12×12。
    m.axes = .both;
    m.bar_v = .auto;
    m.bar_h = .auto;
    m.content_w = 250;
    m.content_h = 130;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l14Build, 48);
    const d = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 250), d.content.x);
    try std.testing.expectEqual(@as(f32, 130), d.content.y);
    try std.testing.expectEqual(@as(f32, 188), d.viewport.w);
    try std.testing.expectEqual(@as(f32, 88), d.viewport.h);
    try std.testing.expectEqual(core.RectI{ .x = 188, .y = 0, .w = 12, .h = 88 }, d.bar_v.?);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 88, .w = 188, .h = 12 }, d.bar_h.?);
    try std.testing.expectEqual(@as(f32, 42), d.max_offset.y);
    try std.testing.expectEqual(@as(f32, 62), d.max_offset.x);
    try std.testing.expect(rig.u.lastScrollAxisLimit().?.h >= layout.unbounded);
}

fn l15Hfw(_: ?*const anyopaque, w: f32) f32 {
    return @ceil(30000.0 / w);
}
fn l15HfwNonMonotonic(_: ?*const anyopaque, w: f32) f32 {
    if (@abs(w - 200.0) < 0.01) return 101;
    if (@abs(w - 188.0) < 0.01) return 95;
    return @ceil(30000.0 / w);
}
const L15Model = struct {
    axes: layout.ScrollAxes = .vertical,
    use_hfw: bool = true,
    nonmono: bool = false,
    content_w: f32 = 400,
    content_h: f32 = 0,
};
fn l15Build(ctx: *L15Model, u: *ui.Ui) void {
    _ = u.beginScroll(@src(), .{ .main = .fixedSize(200), .cross = .fixedSize(100) }, .{
        .axes = ctx.axes,
        .bar_v = .auto,
        .bar_h = .auto,
    });
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fill });
    _ = u.leaf(@fromBackingInt(0x1502), .{
        .layout = .{
            .kind = .leaf,
            .main = .fit,
            .cross = .fill,
            .content = .{
                .size = .{ .x = ctx.content_w, .y = ctx.content_h },
                .key = 0x1502,
                .hfw = if (ctx.use_hfw) (if (ctx.nonmono) l15HfwNonMonotonic else l15Hfw) else null,
            },
        },
    });
    u.endColumn();
    u.endScroll();
}

test "AC-LAYOUT-015 Scroll 自动滚动条重测与防回退" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    var m = L15Model{};
    _ = rig.frame(&m, l15Build, 0);
    const leaf = rig.u.getNode(@fromBackingInt(0x1502)).?;
    const scroll_id = leaf.parent.?.parent.?.id;
    const a = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 188), a.content.x);
    try std.testing.expectEqual(@as(f32, 160), a.content.y);
    try std.testing.expectEqual(@as(f32, 188), a.viewport.w);
    try std.testing.expectEqual(@as(f32, 100), a.viewport.h);
    try std.testing.expectEqual(@as(f32, 60), a.max_offset.y);
    try std.testing.expectEqual(@as(u64, 1), core.stats.read("layout.scroll_remeasures").?);

    // 非单调夹具：重测后高度 95，但滚动条仍显示且不再重测。
    m.nonmono = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l15Build, 16);
    const b = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 188), b.viewport.w);
    try std.testing.expectEqual(@as(f32, 95), b.content.y);
    try std.testing.expectEqual(@as(f32, 0), b.max_offset.y);
    try std.testing.expect(b.bar_v != null);
    try std.testing.expectEqual(@as(u64, 1), core.stats.read("layout.scroll_remeasures").?);

    // 双轴：两条同时显示，不再重测。
    m = L15Model{ .axes = .both, .use_hfw = false, .content_w = 250, .content_h = 130 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l15Build, 32);
    const c = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 188), c.viewport.w);
    try std.testing.expectEqual(@as(f32, 88), c.viewport.h);
    try std.testing.expect(c.bar_v != null and c.bar_h != null);
    try std.testing.expectEqual(@as(u64, 0), core.stats.read("layout.scroll_remeasures").?);

    // 边界：内容 195×95 不显示任何滚动条。
    m = L15Model{ .axes = .both, .use_hfw = false, .content_w = 195, .content_h = 95 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l15Build, 48);
    const d = rig.u.scrollMetrics(scroll_id).?;
    try std.testing.expectEqual(@as(f32, 200), d.viewport.w);
    try std.testing.expectEqual(@as(f32, 100), d.viewport.h);
    try std.testing.expect(d.bar_v == null and d.bar_h == null);
}

const L16Model = struct {
    content_h: f32 = 160,
    off: f32 = 0,
    anchor_end: bool = false,
    reveal: ?core.Rect = null,
};
fn l16Build(ctx: *L16Model, u: *ui.Ui) void {
    _ = u.beginScroll(@src(), .{ .main = .fixedSize(200), .cross = .fixedSize(100) }, .{
        .axes = .vertical,
        .bar_v = .auto,
        .offset = .{ .x = 0, .y = ctx.off },
        .anchor_end = ctx.anchor_end,
        .reveal = ctx.reveal,
    });
    _ = u.leaf(@fromBackingInt(0x1602), .{
        .layout = .{
            .kind = .leaf,
            .main = .fixedSize(ctx.content_h),
            .cross = .fixedSize(200),
            .content = .{ .size = .{ .x = 200, .y = ctx.content_h } },
        },
    });
    u.endScroll();
}

fn l16Metrics(rig: *M2Rig) layout.ScrollMetrics {
    const leaf = rig.u.getNode(@fromBackingInt(0x1602)).?;
    return rig.u.scrollMetrics(leaf.parent.?.id).?;
}

test "AC-LAYOUT-016 Scroll 偏移夹紧、anchor_end 与 reveal" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    var m = L16Model{};
    const cases = [_]struct { off: f32, want: f32 }{
        .{ .off = 80, .want = 60 },
        .{ .off = -5, .want = 0 },
        .{ .off = std.math.nan(f32), .want = 0 },
        .{ .off = 30, .want = 30 },
    };
    for (cases) |c| {
        rig.u.scroll_states.clearRetainingCapacity();
        m = L16Model{ .off = c.off };
        rig.u.invalidate(.build);
        _ = rig.frame(&m, l16Build, 0);
        const mt = l16Metrics(&rig);
        try std.testing.expectEqual(c.want, mt.offset.y);
        try std.testing.expect(mt.bar_v != null);
    }

    // e：内容变短，偏移随之减小。
    rig.u.scroll_states.clearRetainingCapacity();
    m = L16Model{ .off = 60 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 16);
    try std.testing.expectEqual(@as(f32, 60), l16Metrics(&rig).offset.y);
    m.content_h = 120;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 32);
    try std.testing.expectEqual(@as(f32, 20), l16Metrics(&rig).offset.y);

    // f/g/h：上次在末端时 anchor_end 跟随新末端，否则保持。
    rig.u.scroll_states.clearRetainingCapacity();
    m = L16Model{ .off = 60 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 48);
    m.content_h = 200;
    m.anchor_end = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 64);
    try std.testing.expectEqual(@as(f32, 100), l16Metrics(&rig).offset.y);

    rig.u.scroll_states.clearRetainingCapacity();
    m = L16Model{ .off = 60 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 80);
    m.content_h = 200;
    m.anchor_end = false;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 96);
    try std.testing.expectEqual(@as(f32, 60), l16Metrics(&rig).offset.y);

    rig.u.scroll_states.clearRetainingCapacity();
    m = L16Model{ .off = 30 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 112);
    m.content_h = 200;
    m.anchor_end = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l16Build, 128);
    try std.testing.expectEqual(@as(f32, 30), l16Metrics(&rig).offset.y);

    // i-l：reveal 最小位移。
    const reveal_cases = [_]struct { off: f32, y: f32, h: f32, want: f32 }{
        .{ .off = 0, .y = 150, .h = 20, .want = 70 },
        .{ .off = 80, .y = 150, .h = 20, .want = 80 },
        .{ .off = 80, .y = 20, .h = 40, .want = 20 },
        .{ .off = 0, .y = 40, .h = 160, .want = 40 },
    };
    for (reveal_cases) |c| {
        rig.u.scroll_states.clearRetainingCapacity();
        m = L16Model{ .off = c.off, .content_h = 200, .reveal = .{ .x = 0, .y = c.y, .w = 200, .h = c.h } };
        rig.u.invalidate(.build);
        _ = rig.frame(&m, l16Build, 144);
        try std.testing.expectEqual(c.want, l16Metrics(&rig).offset.y);
    }

    // scale = 1.5：lpx 请求换算为 ppx 后夹紧，并回写 lpx。
    var rig2 = try M2Rig.create(300, 200, 1.5);
    defer rig2.destroy();
    var m2 = L16Model{ .off = 40 };
    rig2.u.invalidate(.build);
    _ = rig2.frame(&m2, l16Build, 0);
    var mt = l16Metrics(&rig2);
    try std.testing.expectEqual(@as(f32, 40), mt.offset.y);
    try std.testing.expectEqual(@as(i32, 60), mt.offset_px.y);
    m2.off = 70;
    rig2.u.invalidate(.build);
    _ = rig2.frame(&m2, l16Build, 16);
    mt = l16Metrics(&rig2);
    try std.testing.expectEqual(@as(f32, 60), mt.offset.y);
    try std.testing.expectEqual(@as(i32, 90), mt.offset_px.y);
    m2.off = mt.offset.y;
    rig2.u.invalidate(.build);
    _ = rig2.frame(&m2, l16Build, 32);
    try std.testing.expectEqual(@as(f32, 60), l16Metrics(&rig2).offset.y);
}

const L17Model = struct {
    width: f32 = 805,
    pos: layout.SplitPos = .{ .ratio = 0.25 },
    min1: f32 = 0,
    min2: f32 = 0,
    split_id: core.WidgetId = .none,
};
fn l17Build(ctx: *L17Model, u: *ui.Ui) void {
    ctx.split_id = u.beginSplitter(@src(), .{ .main = .fixedSize(ctx.width), .cross = .fixedSize(100) }, .{
        .orientation = .horizontal,
        .pos = ctx.pos,
        .min_first = ctx.min1,
        .min_second = ctx.min2,
    });
    _ = u.leaf(@fromBackingInt(0x1701), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(30), .cross = .fill, .content = .{ .size = .{ .x = 30, .y = 10 } } } });
    _ = u.leaf(@fromBackingInt(0x1702), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(30), .cross = .fill, .content = .{ .size = .{ .x = 30, .y = 10 } } } });
    u.endSplitter();
}

test "AC-LAYOUT-017 Splitter 比例、最小尺寸、fixed 位置与窗格填充" {
    var rig = try M2Rig.create(1200, 200, 1.0);
    defer rig.destroy();
    var m = L17Model{};
    _ = rig.frame(&m, l17Build, 0);
    var sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 200), sm.first_px);
    try std.testing.expectEqual(@as(i32, 600), sm.second_px);
    try std.testing.expectEqual(core.RectI{ .x = 200, .y = 0, .w = 5, .h = 100 }, sm.divider);
    try std.testing.expectEqual(@as(i32, 200), rig.u.lastRectPx(@fromBackingInt(0x1701)).?.w);
    try std.testing.expectEqual(@as(i32, 600), rig.u.lastRectPx(@fromBackingInt(0x1702)).?.w);
    try std.testing.expect(rig.u.getNode(@fromBackingInt(0x1701)).?.flags.clip_children);
    try std.testing.expect(rig.u.getNode(@fromBackingInt(0x1702)).?.flags.clip_children);

    m.pos = .{ .ratio = 0.1 };
    m.min1 = 150;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 16);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 150), sm.first_px);
    try std.testing.expectEqual(@as(i32, 650), sm.second_px);

    m.pos = .{ .ratio = 0.9 };
    m.min1 = 0;
    m.min2 = 100;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 32);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 700), sm.first_px);
    try std.testing.expectEqual(@as(i32, 100), sm.second_px);

    m.pos = .{ .fixed_second = 300 };
    m.min2 = 0;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 48);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 500), sm.first_px);
    try std.testing.expectEqual(@as(i32, 300), sm.second_px);

    // avail=100、min 之和 200：按 min 比例 75/25。
    m = L17Model{ .width = 105, .pos = .{ .ratio = 0.5 }, .min1 = 150, .min2 = 50 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 64);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 75), sm.first_px);
    try std.testing.expectEqual(@as(i32, 25), sm.second_px);

    // 期望尺寸主轴 = min_first + splitter_w + min_second。
    m = L17Model{ .min1 = 150, .min2 = 50 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 80);
    const sn = rig.u.getNode(m.split_id).?;
    const ms = rig.u.measureForTest(sn, .{ .w = layout.unbounded, .h = layout.unbounded }, .natural);
    try std.testing.expectEqual(@as(i32, 205), ms.w);

    // scale 1.25：fixed_first(120 lpx) 在 1000 ppx 可用区内取 150 ppx。
    var rig2 = try M2Rig.create(1200, 200, 1.25);
    defer rig2.destroy();
    var m2 = L17Model{ .pos = .{ .fixed_first = 120 } };
    _ = rig2.frame(&m2, l17Build, 0);
    const sm2 = rig2.u.splitMetrics(m2.split_id).?;
    try std.testing.expectEqual(@as(i32, 150), sm2.first_px);
    try std.testing.expectEqual(@as(i32, 850), sm2.second_px);
    try std.testing.expectEqual(@as(i32, 6), sm2.divider.w);
}

test "AC-LAYOUT-018 Splitter 缩放、min 夹紧与 SplitPos 保持" {
    var rig = try M2Rig.create(1200, 200, 1.0);
    defer rig.destroy();
    var m = L17Model{ .width = 805, .pos = .{ .ratio = 0.25 }, .min1 = 100, .min2 = 100 };
    const saved_ratio = m.pos;
    _ = rig.frame(&m, l17Build, 0);
    var sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 200), sm.first_px);
    try std.testing.expectEqual(@as(i32, 600), sm.second_px);

    m.width = 1005;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 16);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 250), sm.first_px);
    try std.testing.expectEqual(@as(i32, 750), sm.second_px);

    m.width = 305;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 32);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 100), sm.first_px);
    try std.testing.expectEqual(@as(i32, 200), sm.second_px);
    try std.testing.expect(std.meta.eql(saved_ratio, m.pos));

    // fixed_first(150)：缩放不改变首选位置。
    m.width = 805;
    m.pos = .{ .fixed_first = 150 };
    const saved_first = m.pos;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 48);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 150), sm.first_px);
    try std.testing.expectEqual(@as(i32, 650), sm.second_px);
    m.width = 1005;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 64);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 150), sm.first_px);
    try std.testing.expectEqual(@as(i32, 850), sm.second_px);
    try std.testing.expect(std.meta.eql(saved_first, m.pos));

    // fixed_second(300)：缩放与缩窄时的 min 夹紧。
    m.width = 805;
    m.pos = .{ .fixed_second = 300 };
    const saved_second = m.pos;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 80);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 500), sm.first_px);
    try std.testing.expectEqual(@as(i32, 300), sm.second_px);
    m.width = 1005;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 96);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 700), sm.first_px);
    try std.testing.expectEqual(@as(i32, 300), sm.second_px);
    m.width = 355;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l17Build, 112);
    sm = rig.u.splitMetrics(m.split_id).?;
    try std.testing.expectEqual(@as(i32, 100), sm.first_px);
    try std.testing.expectEqual(@as(i32, 250), sm.second_px);
    try std.testing.expect(std.meta.eql(saved_second, m.pos));
}

test "AC-LAYOUT-022 placeAnchored 翻转、夹紧、限高与交叉轴翻转" {
    const bounds = core.RectI{ .x = 0, .y = 0, .w = 1000, .h = 800 };
    const below: layout.Placement = .{ .side = .below, .align_ = .start };
    var r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, below, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 100, .y = 124, .w = 200, .h = 300 }, r.rect);
    try std.testing.expectEqual(layout.Side.below, r.side_used);
    try std.testing.expect(!r.clamped);

    r = layout.placeAnchored(.{ .x = 100, .y = 600, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, below, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 100, .y = 300, .w = 200, .h = 300 }, r.rect);
    try std.testing.expectEqual(layout.Side.above, r.side_used);

    r = layout.placeAnchored(.{ .x = 950, .y = 100, .w = 40, .h = 24 }, .{ .w = 200, .h = 300 }, below, 0, bounds);
    try std.testing.expectEqual(@as(i32, 800), r.rect.x);
    try std.testing.expectEqual(@as(i32, 124), r.rect.y);
    try std.testing.expect(r.clamped);

    r = layout.placeAnchored(.{ .x = 100, .y = 380, .w = 80, .h = 24 }, .{ .w = 200, .h = 500 }, below, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 100, .y = 300, .w = 200, .h = 500 }, r.rect);
    try std.testing.expect(r.clamped);

    r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 900 }, below, 0, bounds);
    try std.testing.expectEqual(@as(i32, 800), r.rect.h);
    try std.testing.expectEqual(@as(i32, 0), r.rect.y);
    try std.testing.expect(r.height_limited);

    r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, below, 4, bounds);
    try std.testing.expectEqual(@as(i32, 128), r.rect.y);

    r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, .{ .side = .below, .align_ = .end }, 0, bounds);
    try std.testing.expectEqual(@as(i32, 0), r.rect.x);
    r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, .{ .side = .below, .align_ = .center }, 0, bounds);
    try std.testing.expectEqual(@as(i32, 40), r.rect.x);

    r = layout.placeAnchored(.{ .x = 400, .y = 100, .w = 100, .h = 22 }, .{ .w = 180, .h = 200 }, .{ .side = .right, .align_ = .start }, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 500, .y = 100, .w = 180, .h = 200 }, r.rect);
    try std.testing.expectEqual(layout.Side.right, r.side_used);
    r = layout.placeAnchored(.{ .x = 850, .y = 100, .w = 100, .h = 22 }, .{ .w = 180, .h = 200 }, .{ .side = .right, .align_ = .start }, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 670, .y = 100, .w = 180, .h = 200 }, r.rect);
    try std.testing.expectEqual(layout.Side.left, r.side_used);

    r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 100, .h = 22 }, .{ .w = 280, .h = 50 }, .{ .side = .right, .align_ = .start }, 0, .{ .x = 0, .y = 0, .w = 300, .h = 800 });
    try std.testing.expectEqual(@as(i32, 20), r.rect.x);
    try std.testing.expect(r.clamped);

    // 交叉轴翻转。
    r = layout.placeAnchored(.{ .x = 950, .y = 100, .w = 0, .h = 0 }, .{ .w = 200, .h = 100 }, below, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 800, .y = 100, .w = 200, .h = 100 }, r.rect);
    try std.testing.expect(r.clamped);
    r = layout.placeAnchored(.{ .x = 950, .y = 100, .w = 0, .h = 0 }, .{ .w = 200, .h = 100 }, .{ .side = .below, .align_ = .start, .flip_cross = true }, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 750, .y = 100, .w = 200, .h = 100 }, r.rect);
    try std.testing.expect(!r.clamped);
    r = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 0, .h = 0 }, .{ .w = 200, .h = 100 }, .{ .side = .below, .align_ = .start, .flip_cross = true }, 0, bounds);
    try std.testing.expectEqual(core.RectI{ .x = 100, .y = 100, .w = 200, .h = 100 }, r.rect);

    // 纯函数：重复 1000 次结果一致。
    const first = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, below, 0, bounds);
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const rr = layout.placeAnchored(.{ .x = 100, .y = 100, .w = 80, .h = 24 }, .{ .w = 200, .h = 300 }, below, 0, bounds);
        try std.testing.expectEqual(first, rr);
    }
}

const L33Model = struct { border: u8 = 1, padding: core.Insets = .{} };
fn l33Build(ctx: *const L33Model, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x3301), .{
        .layout = .{
            .kind = .stack,
            .main = .{ .grow = 1 },
            .cross = .fill,
            .padding = ctx.padding,
            .border = ctx.border,
        },
    });
    _ = u.leaf(@fromBackingInt(0x3302), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .cross = .fill, .content = .{ .size = .{ .x = 0, .y = 0 } } } });
    u.endNode();
}

test "AC-LAYOUT-033 border 发丝线内缩" {
    const cases = [_]struct { scale: f32, inset: i32 }{
        .{ .scale = 1.0, .inset = 1 },
        .{ .scale = 1.5, .inset = 1 },
        .{ .scale = 2.0, .inset = 2 },
        .{ .scale = 3.0, .inset = 3 },
    };
    for (cases) |c| {
        var rig = try M2Rig.create(100, 100, c.scale);
        defer rig.destroy();
        _ = rig.frame(&L33Model{}, l33Build, 0);
        const r = rig.u.lastRectPx(@fromBackingInt(0x3302)).?;
        try std.testing.expectEqual(core.RectI{ .x = c.inset, .y = c.inset, .w = 100 - c.inset * 2, .h = 100 - c.inset * 2 }, r);
    }

    // border = 2 @ scale 1.5 → 2 ppx。
    var rig2 = try M2Rig.create(100, 100, 1.5);
    defer rig2.destroy();
    _ = rig2.frame(&L33Model{ .border = 2 }, l33Build, 0);
    const a = rig2.u.lastRectPx(@fromBackingInt(0x3302)).?;
    try std.testing.expectEqual(@as(i32, 2), a.x);
    try std.testing.expectEqual(@as(i32, 96), a.w);

    // border + padding = 4 lpx @ 1.5 → 1 + 6 = 7 ppx。
    var rig3 = try M2Rig.create(100, 100, 1.5);
    defer rig3.destroy();
    _ = rig3.frame(&L33Model{ .border = 1, .padding = core.Insets.all(4) }, l33Build, 0);
    const b = rig3.u.lastRectPx(@fromBackingInt(0x3302)).?;
    try std.testing.expectEqual(@as(i32, 7), b.x);
    try std.testing.expectEqual(@as(i32, 86), b.w);
    try std.testing.expectEqual(@as(i32, 86), b.h);
}

const L20Model = struct {
    width: f32 = 400,
    label_max: f32 = 240,
    start_align: bool = false,
    odd: bool = false,
};
fn l20Leaf(u: *ui.Ui, id: u64, w: f32, h: f32, al: ?layout.Align, span: bool) void {
    _ = u.leaf(@fromBackingInt(@intCast(id)), .{ .layout = .{
        .kind = .leaf,
        .main = .fit,
        .cross = .fit,
        .self_align = al,
        .form_span = span,
        .content = .{ .size = .{ .x = w, .y = h } },
    } });
}
fn l20Build(ctx: *L20Model, u: *ui.Ui) void {
    const al: ?layout.Align = if (ctx.start_align) .start else null;
    _ = u.beginNode(@fromBackingInt(0x2001), .{ .layout = .{
        .kind = .{ .form = .{ .label_max = ctx.label_max, .col_gap = .md } },
        .main = .fixedSize(ctx.width),
        .cross = .fit,
        .gap = .none,
    } });
    l20Leaf(u, 0x2002, 40, 20, al, false);
    l20Leaf(u, 0x2003, 0, 24, al, false);
    l20Leaf(u, 0x2004, 90, 20, al, false);
    l20Leaf(u, 0x2005, 0, 24, al, false);
    if (ctx.odd) {
        l20Leaf(u, 0x2008, 0, 24, al, false);
    } else {
        l20Leaf(u, 0x2006, 60, 20, al, false);
        l20Leaf(u, 0x2007, 0, 24, al, false);
        l20Leaf(u, 0x2009, 400, 30, al, true);
    }
    u.endNode();
}

test "AC-LAYOUT-020 Form 标签列、字段列、span、行高与奇偶配对" {
    var rig = try M2Rig.create(600, 400, 1.0);
    defer rig.destroy();
    var m = L20Model{};
    _ = rig.frame(&m, l20Build, 0);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 2, .w = 90, .h = 20 }, rig.u.lastRectPx(@fromBackingInt(0x2002)).?);
    try std.testing.expectEqual(core.RectI{ .x = 98, .y = 0, .w = 302, .h = 24 }, rig.u.lastRectPx(@fromBackingInt(0x2003)).?);
    try std.testing.expectEqual(@as(i32, 98), rig.u.lastRectPx(@fromBackingInt(0x2005)).?.x);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 72, .w = 400, .h = 30 }, rig.u.lastRectPx(@fromBackingInt(0x2009)).?);

    // label_max = 64 → 64 / 328。
    m.label_max = 64;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l20Build, 16);
    try std.testing.expectEqual(@as(i32, 64), rig.u.lastRectPx(@fromBackingInt(0x2002)).?.w);
    try std.testing.expectEqual(@as(i32, 72), rig.u.lastRectPx(@fromBackingInt(0x2003)).?.x);
    try std.testing.expectEqual(@as(i32, 328), rig.u.lastRectPx(@fromBackingInt(0x2003)).?.w);

    // 内部宽 100 → 标签列上限 50，字段 42。
    m = L20Model{ .width = 100 };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l20Build, 32);
    try std.testing.expectEqual(@as(i32, 50), rig.u.lastRectPx(@fromBackingInt(0x2002)).?.w);
    try std.testing.expectEqual(@as(i32, 58), rig.u.lastRectPx(@fromBackingInt(0x2003)).?.x);
    try std.testing.expectEqual(@as(i32, 42), rig.u.lastRectPx(@fromBackingInt(0x2003)).?.w);

    // 标签与字段 self_align = start → 均为行顶 y = 0。
    m = L20Model{ .start_align = true };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l20Build, 48);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(@fromBackingInt(0x2002)).?.y);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(@fromBackingInt(0x2003)).?.y);

    // 5 个非 span 项：最后一项作为字段，标签列留空。
    m = L20Model{ .odd = true };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l20Build, 64);
    try std.testing.expectEqual(@as(i32, 98), rig.u.lastRectPx(@fromBackingInt(0x2008)).?.x);
}

test "AC-THEME-018 内建图标全部可绘制且位于 16×16 内" {
    var pixels: [16 * 16 * 4]u8 = @splat(0);
    var canvas = gfx.Canvas.init(std.testing.allocator, &pixels, 16, 16, 1.0);
    defer canvas.deinit();
    const t = theme.Theme.default(.light, .{});
    var dctx = theme.DrawCtx{ .canvas = &canvas, .theme = &t, .scale = 1.0 };
    const kinds = std.enums.values(theme.MarkKind);
    try std.testing.expectEqual(@as(usize, 17), kinds.len);
    for (kinds) |kind| {
        @memset(&pixels, 0);
        theme.drawMark(&dctx, kind, .{ .x = 0, .y = 0, .w = 16, .h = 16 }, .text_primary);
        var nonzero: usize = 0;
        var y: usize = 0;
        while (y < 16) : (y += 1) {
            var x: usize = 0;
            while (x < 16) : (x += 1) {
                const o = (y * 16 + x) * 4;
                if (pixels[o + 3] != 0) nonzero += 1;
            }
        }
        try std.testing.expect(nonzero > 0);
    }
}

const L27Snap = struct { id: u64, rect: core.RectI };
fn l27SnapTree(node: ?*ui.Node, out: *std.ArrayListUnmanaged(L27Snap), gpa: std.mem.Allocator) void {
    const n = node orelse return;
    out.append(gpa, .{ .id = n.id.raw(), .rect = n.abs }) catch {};
    var c = n.first_child;
    while (c) |cc| : (c = cc.next) l27SnapTree(cc, out, gpa);
}
fn l27Build(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .sm });
    _ = u.beginRow(@src(), .{ .main = .fixedSize(60), .cross = .fill });
    _ = u.leaf(@fromBackingInt(0x2702), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(100), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 100, .y = 20 } } } });
    _ = u.leaf(@fromBackingInt(0x2703), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(50), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 50, .y = 20 } } } });
    u.endRow();
    _ = u.beginScroll(@src(), .{ .main = .fixedSize(100), .cross = .fill }, .{ .axes = .vertical, .bar_v = .auto });
    _ = u.beginColumn(@src(), .{ .main = .fit, .cross = .fill });
    _ = u.leaf(@fromBackingInt(0x2704), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(200), .cross = .fixedSize(80), .content = .{ .size = .{ .x = 80, .y = 200 } } } });
    u.endColumn();
    u.endScroll();
    _ = u.beginSplitter(@src(), .{ .main = .fixedSize(80), .cross = .fill }, .{ .orientation = .horizontal, .pos = .{ .ratio = 0.5 } });
    _ = u.leaf(@fromBackingInt(0x2705), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fill, .content = .{ .size = .{ .x = 20, .y = 20 } } } });
    _ = u.leaf(@fromBackingInt(0x2706), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fill, .content = .{ .size = .{ .x = 20, .y = 20 } } } });
    u.endSplitter();
    u.endColumn();
}

test "AC-LAYOUT-027 DPI 变化重测与回到 1.0 的矩形一致性" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 800, .h = 600 } });
    defer app.deinit();
    var dummy: u8 = 0;
    app.build_ctx = @ptrCast(&dummy);
    app.build_fn = l27Build;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    const fixed = app.ui_state.getNode(@fromBackingInt(0x2702)).?;
    try std.testing.expectEqual(@as(i32, 100), fixed.abs.w);
    var base: std.ArrayListUnmanaged(L27Snap) = .empty;
    defer base.deinit(std.testing.allocator);
    l27SnapTree(app.ui_state.current_root, &base, std.testing.allocator);

    const scales = [_]struct { dpi: u32, want: i32 }{
        .{ .dpi = 120, .want = 125 },
        .{ .dpi = 144, .want = 150 },
        .{ .dpi = 168, .want = 175 },
        .{ .dpi = 192, .want = 200 },
    };
    for (scales) |s| {
        platform.Headless.setDpi(s.dpi);
        const reused0 = core.stats.read("frame.nodes_measure_reused").?;
        try std.testing.expect(app.step());
        const n = app.ui_state.getNode(@fromBackingInt(0x2702)).?;
        try std.testing.expectEqual(s.want, n.abs.w);
        try std.testing.expectEqual(reused0, core.stats.read("frame.nodes_measure_reused").?);
    }
    platform.Headless.setDpi(96);
    try std.testing.expect(app.step());
    var back: std.ArrayListUnmanaged(L27Snap) = .empty;
    defer back.deinit(std.testing.allocator);
    l27SnapTree(app.ui_state.current_root, &back, std.testing.allocator);
    try std.testing.expectEqual(base.items.len, back.items.len);
    for (base.items, back.items) |a, b| {
        try std.testing.expectEqual(a.id, b.id);
        try std.testing.expectEqual(a.rect, b.rect);
    }
}

const L21Mode = enum { shown, hidden, omitted };
const L21Model = struct { target_rect: bool = false, anchor: bool = true, middle: L21Mode = .shown };
fn l21Leaf(u: *ui.Ui, id: u64, w: f32, hidden: bool) void {
    _ = u.leaf(@fromBackingInt(@intCast(id)), .{
        .layout = .{ .kind = .leaf, .main = .fixedSize(w), .cross = .fixedSize(20), .content = .{ .size = .{ .x = w, .y = 20 } } },
        .flags = .{ .hidden = hidden },
    });
    _ = u.interact(@fromBackingInt(@intCast(id)), .{ .sense = .{ .hover = true, .click = true } });
}
fn l21Build(ctx: *L21Model, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x2101), .{ .layout = .{ .kind = .stack, .main = .fixedSize(200), .cross = .fixedSize(100) } });
    _ = u.beginNode(@fromBackingInt(0x2102), .{ .layout = .{ .kind = .row, .main = .fit, .cross = .fixedSize(20), .gap = .sm } });
    l21Leaf(u, 0x2103, 40, false);
    if (ctx.middle != .omitted) l21Leaf(u, 0x2104, 40, ctx.middle == .hidden);
    l21Leaf(u, 0x2105, 40, false);
    u.endNode();
    if (ctx.anchor) {
        const target: layout.AnchorTarget = if (ctx.target_rect) .{ .rect = .{ .x = 10, .y = 10, .w = 20, .h = 20 } } else .parent;
        _ = u.beginNode(@fromBackingInt(0x2110), .{ .layout = .{ .kind = .{ .anchor = .{
            .target = target,
            .placement = .{ .side = .below, .align_ = .start },
            .gap = .none,
            .bounds = .parent,
        } } } });
        _ = u.leaf(@fromBackingInt(0x2111), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(16), .content = .{ .size = .{ .x = 40, .y = 16 } } } });
        u.endNode();
    }
    u.endNode();
}

test "AC-LAYOUT-021 Anchor 摆放、兄弟不受影响与 hidden/省略子项" {
    var rig = try M2Rig.create(300, 200, 1.0);
    defer rig.destroy();
    var m = L21Model{};
    _ = rig.frame(&m, l21Build, 0);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 84, .w = 40, .h = 16 }, rig.u.lastRectPx(@fromBackingInt(0x2111)).?);
    try std.testing.expectEqual(@as(i32, 20), rig.u.lastRectPx(@fromBackingInt(0x2102)).?.h);
    try std.testing.expectEqual(@as(i32, 0), rig.u.lastRectPx(@fromBackingInt(0x2103)).?.x);
    try std.testing.expectEqual(@as(i32, 44), rig.u.lastRectPx(@fromBackingInt(0x2104)).?.x);
    try std.testing.expectEqual(@as(i32, 88), rig.u.lastRectPx(@fromBackingInt(0x2105)).?.x);

    // Anchor target 显式 rect。
    m.target_rect = true;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l21Build, 16);
    try std.testing.expectEqual(core.RectI{ .x = 10, .y = 30, .w = 40, .h = 16 }, rig.u.lastRectPx(@fromBackingInt(0x2111)).?);

    // hidden 子项占位、不绘制、命中跳过。
    m = L21Model{ .middle = .hidden };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l21Build, 32);
    try std.testing.expectEqual(@as(i32, 44), rig.u.lastRectPx(@fromBackingInt(0x2104)).?.x);
    try std.testing.expectEqual(@as(i32, 88), rig.u.lastRectPx(@fromBackingInt(0x2105)).?.x);
    try std.testing.expect(rig.u.hitTest(.{ .x = 60, .y = 10 }) != @as(core.WidgetId, @fromBackingInt(0x2104)));
    try std.testing.expectEqual(@as(core.WidgetId, @fromBackingInt(0x2105)), rig.u.hitTest(.{ .x = 100, .y = 10 }));

    // 未声明子项：后继兄弟前移，gap 少一个。
    m = L21Model{ .middle = .omitted };
    rig.u.invalidate(.build);
    _ = rig.frame(&m, l21Build, 48);
    try std.testing.expectEqual(@as(i32, 44), rig.u.lastRectPx(@fromBackingInt(0x2105)).?.x);
}

const F20Model = struct { buf: widgets.TextBuf };
fn f20Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F20Model = @ptrCast(@alignCast(ctx));
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(10), .gap = .sm });
    _ = widgets.textInput(u, @src(), &m.buf, .{ .debug_name = "f20text", .key = ui.Key.str("f20text") });
    _ = widgets.button(u, @src(), "One", .{ .debug_name = "f20a", .key = ui.Key.str("f20a") });
    _ = widgets.button(u, @src(), "Two", .{ .debug_name = "f20b", .key = ui.Key.str("f20b") });
    u.endColumn();
}

test "AC-FRAME-020 失效源表的构建/布局/损伤归类" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 320, .h = 240 } });
    defer app.deinit();
    var m = F20Model{ .buf = try widgets.TextBuf.initFrom(std.testing.allocator, "x") };
    defer m.buf.deinit();
    app.build_ctx = &m;
    app.build_fn = f20Build;
    app.renderOnce(&m, f20Build);
    const text_node = findByName(app.ui_state.current_root, "f20text") orelse return error.TestUnexpectedResult;
    const a = findByName(app.ui_state.current_root, "f20a") orelse return error.TestUnexpectedResult;
    const b = findByName(app.ui_state.current_root, "f20b") orelse return error.TestUnexpectedResult;
    const a_rect = a.abs;
    const b_rect = b.abs;
    // 点击聚焦文本框。
    platform.Headless.injectMouseMove(.{ .x = text_node.abs.x + 5, .y = text_node.abs.y + @divTrunc(text_node.abs.h, 2) }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = text_node.abs.x + 5, .y = text_node.abs.y + @divTrunc(text_node.abs.h, 2) }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = text_node.abs.x + 5, .y = text_node.abs.y + @divTrunc(text_node.abs.h, 2) }, .{});
    _ = app.step();

    // ① 键到聚焦文本框：构建 ≥1、布局、损伤非空。
    platform.Headless.injectKey(.a, true, false, .{});
    platform.Headless.injectKey(.a, false, false, .{});
    platform.Headless.injectText("a");
    try std.testing.expect(app.step());
    try std.testing.expect(app.ui_state.build_passes >= 1);
    try std.testing.expect(app.ui_state.frameDidLayout());
    try std.testing.expect(!app.ui_state.lastFrameDamage().isEmpty());

    // ② 两个普通按钮之间移动：构建 0、无布局、损伤包含两者。
    platform.Headless.injectMouseMove(.{ .x = a_rect.x + @divTrunc(a_rect.w, 2), .y = a_rect.y + @divTrunc(a_rect.h, 2) }, .{});
    try std.testing.expect(app.step());
    platform.Headless.injectMouseMove(.{ .x = b_rect.x + @divTrunc(b_rect.w, 2), .y = b_rect.y + @divTrunc(b_rect.h, 2) }, .{});
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(!app.ui_state.frameDidLayout());
    const hover_dmg = app.ui_state.lastFrameDamage();
    try std.testing.expect(m2Contains(hover_dmg, a_rect));
    try std.testing.expect(m2Contains(hover_dmg, b_rect));

    // ③ 空白处移动：目标不变时无帧。
    const blank = core.Vec2i{ .x = 4, .y = 230 };
    platform.Headless.injectMouseMove(blank, .{});
    _ = app.step();
    platform.Headless.injectMouseMove(blank, .{});
    try std.testing.expect(!app.step());

    // ④ 窗口缩放：无构建、有布局、整根损伤。
    app.window.setClientSize(.{ .w = 360, .h = 280 });
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(app.ui_state.frameDidLayout());
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 360, .h = 280 }, app.ui_state.lastFrameDamage());

    // ⑤ 主题切换：构建 ≥1、有布局、整根损伤。
    var appearance = platform.appearance(app.window);
    appearance.apps_dark = !appearance.apps_dark;
    platform.Headless.setAppearance(appearance);
    platform.Headless.inject(.{ .system_changed = .{ .what = .{ .appearance = true } } });
    try std.testing.expect(app.step());
    try std.testing.expect(app.ui_state.build_passes >= 1);
    try std.testing.expect(app.ui_state.frameDidLayout());
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 360, .h = 280 }, app.ui_state.lastFrameDamage());

    // ⑥ 窗口失去激活：无构建、无布局、整根损伤。
    platform.Headless.setActive(false);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expect(!app.ui_state.frameDidLayout());
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 360, .h = 280 }, app.ui_state.lastFrameDamage());
}

fn f1Site(u: *ui.Ui) core.WidgetId {
    return u.id(@src(), null);
}
const F1Model = struct { ids: [7]core.WidgetId = @splat(.none) };
fn f1Build(ctx: *F1Model, u: *ui.Ui) void {
    const src = @src();
    const a = u.id(src, ui.Key.str("a"));
    const b = u.id(src, ui.Key.str("b"));
    u.pushId(ui.Key.str("p1"));
    const c = u.id(src, null);
    u.pushId(ui.Key.str("p2"));
    const d = u.id(src, null);
    u.popId();
    u.popId();
    const e = u.id(src, null);
    u.pushId(ui.Key.str("x1"));
    const f = f1Site(u);
    u.popId();
    u.pushId(ui.Key.str("x2"));
    const g = f1Site(u);
    u.popId();
    ctx.ids = .{ a, b, c, d, e, f, g };
}

test "AC-FRAME-001 ID 唯一性、调用点隔离、pushId 嵌套与构建稳定性" {
    var rig = try M2Rig.create(120, 80, 1.0);
    defer rig.destroy();
    var m = F1Model{};
    _ = rig.frame(&m, f1Build, 0);
    for (m.ids) |id| try std.testing.expect(id != .none);
    var i: usize = 0;
    while (i < m.ids.len) : (i += 1) {
        var j = i + 1;
        while (j < m.ids.len) : (j += 1) try std.testing.expect(m.ids[i] != m.ids[j]);
    }
    const first = m.ids;
    var k: usize = 0;
    while (k < 100) : (k += 1) {
        rig.u.invalidate(.build);
        _ = rig.frame(&m, f1Build, @intCast((k + 1) * 16));
        try std.testing.expectEqual(first, m.ids);
    }
    try std.testing.expectEqual(@as(u64, 1), core.WidgetId.fromHash(0).raw());
}

const F3Model = struct {
    order: [5]u8 = .{ 0, 1, 2, 3, 4 },
    ids: [5]core.WidgetId = @splat(.none),
    seen: [5]u32 = @splat(0),
};
fn f3Build(ctx: *F3Model, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .gap = .xs });
    for (ctx.order) |item| {
        u.pushId(ui.Key.int(item));
        const id = u.id(@src(), null);
        ctx.ids[item] = id;
        const st = u.stateSticky(u32, id, 0);
        ctx.seen[item] = st.*;
        _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fill, .content = .{ .size = .{ .x = 100, .y = 20 } } } });
        u.popId();
    }
    u.endColumn();
}

test "AC-FRAME-003 稳定键状态随数据项、不随位置" {
    var rig = try M2Rig.create(200, 160, 1.0);
    defer rig.destroy();
    var m = F3Model{};
    _ = rig.frame(&m, f3Build, 0);
    const id1 = m.ids[1];
    const id3 = m.ids[3];
    const y1_before = rig.u.lastRectPx(id1).?.y;
    const y3_before = rig.u.lastRectPx(id3).?.y;
    // 修改第 2 项的状态。
    rig.u.getState(u32, id1).?.* = 7;
    // 交换第 2、4 项的顺序后重建。
    m.order[1] = 3;
    m.order[3] = 1;
    rig.u.invalidate(.build);
    _ = rig.frame(&m, f3Build, 16);
    try std.testing.expectEqual(@as(u32, 7), rig.u.getState(u32, id1).?.*);
    try std.testing.expectEqual(@as(u32, 0), rig.u.getState(u32, id3).?.*);
    try std.testing.expectEqual(@as(u32, 7), m.seen[1]);
    try std.testing.expectEqual(@as(u32, 0), m.seen[3]);
    // 位置按新顺序交换，状态仍跟随数据项。
    try std.testing.expectEqual(y3_before, rig.u.lastRectPx(id1).?.y);
    try std.testing.expectEqual(y1_before, rig.u.lastRectPx(id3).?.y);
    try std.testing.expectEqual(id1, m.ids[1]);
    try std.testing.expectEqual(id3, m.ids[3]);
}

fn f4MentionsWidgetId(comptime T: type) bool {
    return T == core.WidgetId;
}
fn f4FnMentionsWidgetId(comptime F: type) bool {
    const info = @typeInfo(F).@"fn";
    if (info.return_type) |rt| {
        if (comptime f4MentionsWidgetId(rt)) return true;
    }
    inline for (info.param_types) |pt| {
        if (comptime pt != null) {
            if (comptime f4MentionsWidgetId(pt.?)) return true;
        }
    }
    return false;
}

test "AC-FRAME-004 设置持久化仅字符串键且无 WidgetId 序列化入口" {
    var s = settings.Settings.init(std.testing.allocator);
    defer s.deinit();
    try s.put("window.main.placement", "{\"x\":1}");
    s.setBool("theme.dark", true);
    s.setTable("table.files", &.{ 100, 200 }, &.{ 0, 1 }, &.{ false, true }, 0, true);
    s.setTree("tree.files", &.{ "a", "b" });
    s.setSplitter("splitter.side", "ratio", 0.5);
    try std.testing.expect(s.root == .object);
    var keys: usize = 0;
    for (s.root.object.keys()) |k| {
        try std.testing.expect(k.len > 0);
        keys += 1;
    }
    try std.testing.expect(keys >= 4);
    try std.testing.expect(settings.storedTable(&s, "table.files") != null);
    try std.testing.expect(settings.storedTree(&s, "tree.files") != null);
    try std.testing.expect(settings.storedSplitter(&s, "splitter.side") != null);
    try std.testing.expect(settings.storedTable(&s, "不存在") == null);

    inline for (@typeInfo(settings.Settings).@"struct".decl_names) |d| {
        const v = @field(settings.Settings, d);
        if (@TypeOf(v) == type) continue;
        if (comptime @typeInfo(@TypeOf(v)) == .@"fn") {
            try std.testing.expect(!comptime f4FnMentionsWidgetId(@TypeOf(v)));
        }
    }
    inline for (@typeInfo(settings).@"struct".decl_names) |d| {
        const v = @field(settings, d);
        if (@TypeOf(v) == type) continue;
        if (comptime @typeInfo(@TypeOf(v)) == .@"fn") {
            try std.testing.expect(!comptime f4FnMentionsWidgetId(@TypeOf(v)));
        }
    }
}

const F2Model = struct {};
fn f2Build(_: *F2Model, u: *ui.Ui) void {
    const id = u.id(@src(), null);
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 20, .y = 20 } } } });
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(20), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 20, .y = 20 } } } });
}

test "AC-FRAME-002 重复无键控件：发布路径一次 err，调试构建中止" {
    ui.test_force_soft_duplicate = true;
    defer ui.test_force_soft_duplicate = false;
    ErrCapture.errs = 0;
    ErrCapture.len = 0;
    core.log.setSink(ErrCapture.sink);
    var rig = try M2Rig.create(100, 100, 1.0);
    defer rig.destroy();
    var m = F2Model{};
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        rig.u.invalidate(.build);
        _ = rig.frame(&m, f2Build, @intCast(i * 16));
    }
    core.log.setSink(null);
    try std.testing.expectEqual(@as(usize, 1), ErrCapture.errs);
    try std.testing.expect(std.mem.indexOf(u8, ErrCapture.buf[0..ErrCapture.len], "all.zig:") != null);
    const first = rig.u.current_root.?.first_child.?;
    const second = first.next.?;
    try std.testing.expectEqual(first.id, second.id);
    try std.testing.expectEqual(@as(usize, 1), rig.u.node_map.count());

    // 调试路径：子进程验证中止。
    ui.test_force_soft_duplicate = false;
    if (comptime @import("builtin").os.tag == .linux) {
        const pid = std.os.linux.fork();
        if (pid == 0) {
            const null_fd = std.os.linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
            if (@as(isize, @bitCast(null_fd)) >= 0) {
                _ = std.os.linux.dup2(@intCast(null_fd), 2);
                _ = std.os.linux.close(@intCast(null_fd));
            }
            var child = nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 100, .h = 80 } }) catch std.os.linux.exit(2);
            var d: u8 = 0;
            child.renderOnce(@ptrCast(&d), @ptrCast(&struct {
                fn f(_: ?*anyopaque, u: *ui.Ui) void {
                    const id = u.id(@src(), null);
                    _ = u.leaf(id, .{});
                    _ = u.leaf(id, .{});
                }
            }.f));
            std.os.linux.exit(0);
        }
        var status: i32 = 0;
        _ = std.os.linux.waitpid(@intCast(pid), &status, 0);
        try std.testing.expect(status != 0);
    }
}

const I1Model = struct { calls: u32 = 0, equal: bool = false, id: core.WidgetId = .none };
fn i1Build(ctx: *I1Model, u: *ui.Ui) void {
    ctx.calls += 1;
    const id: core.WidgetId = @fromBackingInt(0x1101);
    ctx.id = id;
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(100), .cross = .fixedSize(30), .content = .{ .size = .{ .x = 100, .y = 30 } } } });
    const a = u.interact(id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .arrow });
    const b = u.interact(id, .{ .sense = .{ .hover = true, .click = true }, .cursor = .hand });
    ctx.equal = std.meta.eql(a, b);
}

test "AC-INPUT-001 分发不构建、事件顺序与 interact 缓存" {
    var rig = try M2Rig.create(200, 120, 1.0);
    defer rig.destroy();
    var m = I1Model{};
    _ = rig.frame(&m, i1Build, 0);
    try std.testing.expectEqual(@as(u32, 1), m.calls);
    try std.testing.expect(m.equal);
    const node = rig.u.getNode(m.id).?;
    try std.testing.expectEqual(platform.CursorShape.arrow, node.interact_opts.cursor);
    const x = node.abs.x + @divTrunc(node.abs.w, 2);
    const y = node.abs.y + @divTrunc(node.abs.h, 2);

    rig.u.beginFrame(16, true);
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 16, .data = .{ .mouse_move = .{ .pos = .{ .x = x, .y = y } } } });
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 16, .data = .{ .mouse_button = .{ .button = .left, .down = true, .pos = .{ .x = x, .y = y } } } });
    rig.u.dispatch(.{ .window = rig.win, .time_ms = 16, .data = .{ .mouse_button = .{ .button = .left, .down = false, .pos = .{ .x = x, .y = y } } } });
    // 分发阶段不执行构建。
    try std.testing.expectEqual(@as(u32, 1), m.calls);
    const evs = rig.u.events(m.id);
    var saw_press: usize = 0;
    var saw_release: usize = 0;
    var saw_click: usize = 0;
    for (evs, 0..) |ev, i| {
        switch (ev) {
            .press => {
                try std.testing.expectEqual(@as(usize, 0), i);
                saw_press += 1;
            },
            .release => {
                saw_release += 1;
                try std.testing.expect(i == 1);
            },
            .click => {
                saw_click += 1;
                try std.testing.expect(i == 2);
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 1), saw_press);
    try std.testing.expectEqual(@as(usize, 1), saw_release);
    try std.testing.expectEqual(@as(usize, 1), saw_click);
    rig.u.finishFrame();

    // 未经 interact 的节点读取 events 在调试构建断言。
    if (comptime @import("builtin").os.tag == .linux) {
        const pid = std.os.linux.fork();
        if (pid == 0) {
            const null_fd = std.os.linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
            if (@as(isize, @bitCast(null_fd)) >= 0) {
                _ = std.os.linux.dup2(@intCast(null_fd), 2);
                _ = std.os.linux.close(@intCast(null_fd));
            }
            var child = nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 100, .h = 80 } }) catch std.os.linux.exit(2);
            var d: u8 = 0;
            child.renderOnce(@ptrCast(&d), @ptrCast(&struct {
                fn f(_: ?*anyopaque, u: *ui.Ui) void {
                    const id: core.WidgetId = @fromBackingInt(0x1102);
                    _ = u.leaf(id, .{});
                    _ = u.events(id);
                }
            }.f));
            std.os.linux.exit(0);
        }
        var status: i32 = 0;
        _ = std.os.linux.waitpid(@intCast(pid), &status, 0);
        try std.testing.expect(status != 0);
    }
}

const RetainProbe = struct {
    var inits: usize = 0;
    var deinits: usize = 0;
    pub fn init(_: std.mem.Allocator) RetainProbe {
        inits += 1;
        return .{};
    }
    pub fn deinit(_: *RetainProbe) void {
        deinits += 1;
    }
};
fn r6Declare(ctx: *anyopaque, u: *ui.Ui) void {
    const id: core.WidgetId = @fromBackingInt(@intFromPtr(ctx) | 1);
    _ = u.leaf(id, .{});
    _ = u.retained(RetainProbe, id, .transient);
}
fn r6Empty(_: *anyopaque, _: *ui.Ui) void {}
fn r6Subtree(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x6001), .{ .layout = .{ .kind = .column, .main = .{ .grow = 1 }, .cross = .fill } });
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const id: core.WidgetId = @fromBackingInt(@intCast(0x6010 + i));
        _ = u.leaf(id, .{});
        _ = u.retained(RetainProbe, id, .transient);
    }
    u.endNode();
}

test "AC-FRAME-006 retained 回收：transient/forget/forgetSubtree/窗口关闭" {
    var rig = try M2Rig.create(120, 80, 1.0);
    defer rig.destroy();
    var tok: u8 = 0;
    RetainProbe.inits = 0;
    RetainProbe.deinits = 0;
    _ = rig.frame(@as(*anyopaque, @ptrCast(&tok)), r6Declare, 0);
    try std.testing.expectEqual(@as(usize, 1), RetainProbe.inits);
    rig.u.invalidate(.build);
    _ = rig.frame(@as(*anyopaque, @ptrCast(&tok)), r6Empty, 16);
    try std.testing.expectEqual(@as(usize, 1), RetainProbe.deinits);

    RetainProbe.deinits = 0;
    rig.u.invalidate(.build);
    _ = rig.frame(@as(*anyopaque, @ptrCast(&tok)), r6Declare, 32);
    rig.u.forget(@fromBackingInt(@intFromPtr(&tok) | 1));
    try std.testing.expectEqual(@as(usize, 1), RetainProbe.deinits);

    RetainProbe.deinits = 0;
    rig.u.invalidate(.build);
    _ = rig.frame(@as(*anyopaque, @ptrCast(&tok)), r6Subtree, 48);
    rig.u.forgetSubtree(@fromBackingInt(0x6001));
    try std.testing.expectEqual(@as(usize, 3), RetainProbe.deinits);

    RetainProbe.deinits = 0;
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 100, .h = 80 } });
    var tok2: u8 = 0;
    app.renderOnce(@as(*anyopaque, @ptrCast(&tok2)), r6Declare);
    app.deinit();
    try std.testing.expectEqual(@as(usize, 1), RetainProbe.deinits);
}

fn l30aBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x3001), .{ .layout = .{ .kind = .row, .main = .fit, .cross = .fit } });
    _ = u.leaf(@fromBackingInt(0x3002), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .main_min = 30, .cross = .fit, .content = .{ .size = .{ .x = 0, .y = 10 } } } });
    u.endNode();
}
fn l30bBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x3011), .{ .layout = .{ .kind = .row, .main = .fixedSize(300), .cross = .fit } });
    _ = u.leaf(@fromBackingInt(0x3012), .{ .layout = .{ .kind = .leaf, .main = .{ .grow = 1 }, .main_min = 30, .cross = .fit, .content = .{ .size = .{ .x = 0, .y = 10 } } } });
    _ = u.leaf(@fromBackingInt(0x3013), .{ .layout = .{ .kind = .leaf, .main = .fixedSize(50), .cross = .fit, .content = .{ .size = .{ .x = 50, .y = 10 } } } });
    u.endNode();
}
fn l30cBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginNode(@fromBackingInt(0x3020), .{ .layout = .{ .kind = .column, .main = .fit, .cross = .fit } });
    _ = u.beginNode(@fromBackingInt(0x3021), .{ .layout = .{ .kind = .row, .main = .fixedSize(50), .cross = .fill } });
    _ = u.leaf(@fromBackingInt(0x3022), .{ .layout = .{ .kind = .leaf, .main = .fit, .cross = .fill, .content = .{ .size = .{ .x = 10, .y = 20 } } } });
    u.endNode();
    u.endNode();
}

test "AC-LAYOUT-030 grow 无界/确定限制、fill 高度与非法权重" {
    var rig = try M2Rig.create(400, 200, 1.0);
    defer rig.destroy();
    var d: u8 = 0;
    const ctx: *anyopaque = @ptrCast(&d);
    _ = rig.frame(ctx, l30aBuild, 0);
    const row_a = rig.u.getNode(@fromBackingInt(0x3001)).?;
    try std.testing.expectEqual(@as(i32, 30), rig.u.measureForTest(row_a, .{ .w = layout.unbounded, .h = layout.unbounded }, .natural).w);

    rig.u.invalidate(.build);
    _ = rig.frame(ctx, l30bBuild, 16);
    try std.testing.expectEqual(@as(i32, 250), rig.u.lastRectPx(@fromBackingInt(0x3012)).?.w);
    try std.testing.expectEqual(@as(i32, 50), rig.u.lastRectPx(@fromBackingInt(0x3013)).?.w);
    const row_b = rig.u.getNode(@fromBackingInt(0x3011)).?;
    const mb = rig.u.measureForTest(row_b, .{ .w = 300, .h = layout.unbounded, .definite_w = true }, .natural);
    try std.testing.expectEqual(@as(i32, 300), mb.w);

    rig.u.invalidate(.build);
    _ = rig.frame(ctx, l30cBuild, 32);
    const row_c = rig.u.getNode(@fromBackingInt(0x3021)).?;
    try std.testing.expectEqual(@as(i32, 20), rig.u.measureForTest(row_c, .{ .w = layout.unbounded, .h = layout.unbounded }, .natural).h);
    try std.testing.expectEqual(@as(i32, 50), rig.u.lastRectPx(@fromBackingInt(0x3021)).?.h);
    try std.testing.expectEqual(@as(i32, 50), rig.u.lastRectPx(@fromBackingInt(0x3022)).?.h);

    // 非法权重在发布路径取 min；调试构建断言。
    layout.test_force_soft_grow_weight = true;
    defer layout.test_force_soft_grow_weight = false;
    try std.testing.expectEqual(@as(u32, 0), layout.quantizeWeight(0));
    try std.testing.expectEqual(@as(u32, 0), layout.quantizeWeight(-1));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var items = [_]layout.FlexItem{.{ .kind = .grow, .base = 0, .min = 30, .max = layout.unbounded, .wq = 0 }};
    var out: [1]i32 = undefined;
    _ = layout.distribute(arena.allocator(), &items, 100, &out);
    try std.testing.expectEqual(@as(i32, 30), out[0]);
    if (comptime @import("builtin").os.tag == .linux) {
        layout.test_force_soft_grow_weight = false;
        const pid = std.os.linux.fork();
        if (pid == 0) {
            const null_fd = std.os.linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
            if (@as(isize, @bitCast(null_fd)) >= 0) {
                _ = std.os.linux.dup2(@intCast(null_fd), 2);
                _ = std.os.linux.close(@intCast(null_fd));
            }
            _ = layout.quantizeWeight(0);
            std.os.linux.exit(0);
        }
        var status: i32 = 0;
        _ = std.os.linux.waitpid(@intCast(pid), &status, 0);
        try std.testing.expect(status != 0);
    }
}

const F27Model = struct { target: f32 = 0 };
fn f27Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F27Model = @ptrCast(@alignCast(ctx));
    const id: core.WidgetId = @fromBackingInt(0x2701);
    _ = u.leaf(id, .{ .layout = .{ .kind = .leaf, .main = .fixedSize(40), .cross = .fixedSize(20), .content = .{ .size = .{ .x = 40, .y = 20 } } } });
    _ = u.animate(id, 0, m.target, .{ .duration = .slow, .easing = .linear, .level = .paint });
}

test "AC-FRAME-027 最小化期间零帧、恢复首帧整根损伤" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 200, .h = 120 } });
    defer app.deinit();
    var m = F27Model{};
    app.build_ctx = &m;
    app.build_fn = f27Build;
    app.renderOnce(&m, f27Build);
    m.target = 1;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    try std.testing.expect(app.ui_state.haveActiveAnimations());

    app.window.minimize();
    const frames0 = app.frames;
    try std.testing.expect(!app.step());
    try std.testing.expectEqual(frames0, app.frames);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        platform.Headless.advanceMs(500);
        try std.testing.expect(!app.step());
        try std.testing.expectEqual(frames0, app.frames);
    }
    app.window.restore();
    try std.testing.expect(app.step());
    try std.testing.expectEqual(frames0 + 1, app.frames);
    try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 200, .h = 120 }, app.ui_state.lastFrameDamage());
}

test "AC-TEST-002 构建步骤名齐全" {
    const steps = [_][]const u8{ "test", "test-golden", "test-replay", "check-docs", "bench" };
    for (steps) |name| {
        var buf: [64]u8 = undefined;
        const needle = std.fmt.bufPrint(&buf, "b.step(\"{s}\"", .{name}) catch unreachable;
        try std.testing.expect(std.mem.indexOf(u8, build_source.source, needle) != null);
    }
}

test "AC-TEST-016 假时钟/度量注入、测试源码静态扫描与后端选项" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const t0 = platform.nowMs();
    platform.Headless.advanceMs(250);
    try std.testing.expectEqual(t0 + 250, platform.nowMs());
    const t1 = platform.nowMs();
    platform.Headless.vsync(2);
    try std.testing.expect(platform.nowMs() > t1);
    platform.Headless.setMetrics(.{ .double_click_ms = 123, .client_animation = false });
    try std.testing.expectEqual(@as(u32, 123), platform.metrics(null).double_click_ms);
    try std.testing.expect(!platform.metrics(null).client_animation);
    var ap = platform.SystemAppearance{};
    ap.apps_dark = true;
    platform.Headless.setAppearance(ap);
    try std.testing.expect(platform.appearance(null).apps_dark);

    const forbidden = [_][]const u8{ "std." ++ "time.", "nano" ++ "Timestamp", "milli" ++ "Timestamp", "std.crypto." ++ "random", "Open" ++ "Clipboard(" };
    for (forbidden) |tok| {
        try std.testing.expect(std.mem.indexOf(u8, test_source.source, tok) == null);
    }
    inline for (@typeInfo(nano.app.Options).@"struct".field_names) |name| {
        try std.testing.expect(std.mem.indexOf(u8, name, "backend") == null);
    }
    inline for (@typeInfo(ui.Ui).@"struct".field_names) |name| {
        try std.testing.expect(std.mem.indexOf(u8, name, "backend") == null);
    }
    try std.testing.expect(std.mem.eql(u8, text.backend_name, "fixed") or
        std.mem.eql(u8, text.backend_name, "fontstash") or
        std.mem.eql(u8, text.backend_name, "directwrite"));
}

const F28Model = struct { buf: widgets.TextBuf, show: bool = true };
fn f28Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F28Model = @ptrCast(@alignCast(ctx));
    if (!m.show) {
        _ = u.leaf(@fromBackingInt(0xF2802), .{});
        return;
    }
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(10) });
    _ = widgets.textInput(u, @src(), &m.buf, .{ .debug_name = "f28text", .key = ui.Key.str("f28text") });
    u.endColumn();
}

test "AC-FRAME-028 光标闪烁定时器、关闭动画与停止声明" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 120 } });
    defer app.deinit();
    platform.Headless.setMetrics(.{ .caret_blink_ms = 500 });
    var m = F28Model{ .buf = try widgets.TextBuf.initFrom(std.testing.allocator, "abc") };
    defer m.buf.deinit();
    app.build_ctx = &m;
    app.build_fn = f28Build;
    app.renderOnce(&m, f28Build);
    const node = findByName(app.ui_state.current_root, "f28text") orelse return error.TestUnexpectedResult;
    const cx = node.abs.x + @divTrunc(node.abs.w, 2);
    const cy = node.abs.y + @divTrunc(node.abs.h, 2);
    platform.Headless.injectMouseMove(.{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = cx, .y = cy }, .{});
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(usize, 1), app.ui_state.blinkCount());
    const caret = app.ui_state.caretBlinkRect(node.id).?;
    const expanded = core.RectI{ .x = caret.x - 1, .y = caret.y - 1, .w = caret.w + 2, .h = caret.h + 2 };

    const frames0 = app.frames;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        platform.Headless.advanceMs(500);
        try std.testing.expect(app.step());
        try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
        const dmg = app.ui_state.lastFrameDamage();
        try std.testing.expect(m2Contains(expanded, dmg));
    }
    try std.testing.expect(app.frames - frames0 >= 9 and app.frames - frames0 <= 11);

    // 系统关闭闪烁：不再产生定时帧，光标可见。
    platform.Headless.setMetrics(.{ .caret_blink_ms = null });
    platform.Headless.inject(.{ .system_changed = .{ .what = .{ .appearance = true } } });
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(usize, 0), app.ui_state.blinkCount());
    try std.testing.expect(app.ui_state.caretVisible(node.id));
    const frames1 = app.frames;
    i = 0;
    while (i < 10) : (i += 1) {
        platform.Headless.advanceMs(500);
        try std.testing.expect(!app.step());
    }
    try std.testing.expectEqual(frames1, app.frames);

    // 停止声明文本框：定时器归零。
    m.show = false;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(usize, 0), app.ui_state.blinkCount());
}

test "AC-TEST-018 控件总览幂等校验与反例节点定位" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 800, .h = 600 } });
    defer app.deinit();
    var model = try gallery.Model.init(std.testing.allocator);
    defer model.deinit();
    app.ui_state.setTheme(&app.theme_state);
    const ctx: *anyopaque = @ptrCast(&model);
    const ok = app.ui_state.checkIdempotence(ctx, gallery.build);
    try std.testing.expectEqual(@as(usize, 0), ok.differences);

    var app2 = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 200, .h = 120 } });
    defer app2.deinit();
    app2.ui_state.setTheme(&app2.theme_state);
    f14_counter = 0;
    var dummy: u8 = 0;
    const bad = app2.ui_state.checkIdempotence(@as(*anyopaque, @ptrCast(&dummy)), f14BadBuild);
    try std.testing.expect(bad.differences > 0);
    try std.testing.expectEqualStrings("bad-counter", bad.first_name.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.first_file, "all.zig") != null);
}

fn walkGoldenPngs(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, prefix: []const u8, out: *std.ArrayListUnmanaged([]u8)) !void {
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        const path = try std.fs.path.join(gpa, &.{ prefix, e.name });
        if (e.kind == .directory) {
            var sub = try dir.openDir(io, e.name, .{ .iterate = true });
            defer sub.close(io);
            try walkGoldenPngs(gpa, io, sub, path, out);
            gpa.free(path);
        } else if (e.kind == .file and std.mem.endsWith(u8, e.name, ".png")) {
            try out.append(gpa, path);
        } else {
            gpa.free(path);
        }
    }
}

fn goldenSegmentOk(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_')) return false;
    }
    return true;
}

test "AC-TEST-005 金图路径约定与唯一性" {
    const gpa = std.testing.allocator;
    const io = std.Options.debug_io;
    var root = try std.Io.Dir.cwd().openDir(io, "tests/golden", .{ .iterate = true });
    defer root.close(io);
    var paths: std.ArrayListUnmanaged([]u8) = .empty;
    defer {
        for (paths.items) |p| gpa.free(p);
        paths.deinit(gpa);
    }
    try walkGoldenPngs(gpa, io, root, "tests/golden", &paths);
    try std.testing.expect(paths.items.len > 0);
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    for (paths.items) |full| {
        const rel = full["tests/golden/".len..];
        var it = std.mem.splitScalar(u8, rel, '/');
        const backend = it.next() orelse return error.TestUnexpectedResult;
        const theme_seg = it.next() orelse return error.TestUnexpectedResult;
        const scale_seg = it.next() orelse return error.TestUnexpectedResult;
        try std.testing.expect(std.mem.eql(u8, backend, "glfw") or std.mem.eql(u8, backend, "win32"));
        try std.testing.expect(goldenSegmentOk(theme_seg));
        try std.testing.expect(scale_seg.len >= 2 and scale_seg[0] == 's');
        for (scale_seg[1..]) |c| try std.testing.expect(c >= '0' and c <= '9');
        var case_parts: usize = 0;
        while (it.next()) |part| {
            case_parts += 1;
            if (it.peek() == null) {
                try std.testing.expect(std.mem.endsWith(u8, part, ".png"));
                try std.testing.expect(goldenSegmentOk(part[0 .. part.len - 4]));
            } else {
                try std.testing.expect(goldenSegmentOk(part));
            }
        }
        try std.testing.expect(case_parts > 0);
        const gop = try seen.getOrPut(gpa, full);
        try std.testing.expect(!gop.found_existing);
    }
}

test "AC-TEST-025 CI 作业包含自动化层级、文档检查与 Windows 交叉编译" {
    const src = ci_source.source;
    try std.testing.expect(std.mem.indexOf(u8, src, "ubuntu-24.04") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "run: zig build test") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "run: zig build test-golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "run: zig build test-replay") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "zig build check-docs") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "zig build check-docs-unchanged") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "zig build -Dtarget=x86_64-windows-gnu") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "windows-2022") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "Unit tests (Win32 backend)") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "-Dtext-backend=directwrite test") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "Golden tests (Win32 + software surface)") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "Replay tests (Win32 backend)") != null);
}

fn f32Build(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8) });
    _ = widgets.label(u, @src(), "debug", .{ .debug_name = "f32label" });
    u.endColumn();
}

test "AC-FRAME-032 force-rebuild、show-damage、帧统计与节点检视" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 160, .h = 100 } });
    defer app.deinit();
    var d: u8 = 0;
    app.build_ctx = @ptrCast(&d);
    app.build_fn = f32Build;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    // force-rebuild：10 帧均构建且整根损伤。
    app.ui_state.force_rebuild = true;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try std.testing.expect(app.step());
        try std.testing.expect(app.ui_state.build_passes >= 1);
        try std.testing.expectEqual(core.RectI{ .x = 0, .y = 0, .w = 160, .h = 100 }, app.ui_state.lastFrameDamage());
    }
    // 帧统计自洽（单帧增量；保持 force-rebuild 以确保绘制）。
    const painted0 = core.stats.read("frame.nodes_painted").?;
    const reused0 = core.stats.read("frame.nodes_measure_reused").?;
    try std.testing.expect(app.step());
    const painted = core.stats.read("frame.nodes_painted").? - painted0;
    const nodes = core.stats.read("frame.nodes").?;
    const reused = core.stats.read("frame.nodes_measure_reused").? - reused0;
    try std.testing.expect(nodes > 0);
    try std.testing.expect(painted > 0 and painted <= nodes);
    try std.testing.expect(reused <= nodes);

    // show-damage：损伤覆盖层改变像素。
    const px_before = app.surface.pixels[0..4].*;
    app.ui_state.show_damage = true;
    app.ui_state.invalidate(.build);
    try std.testing.expect(app.step());
    const px_after = app.surface.pixels[0..4].*;
    try std.testing.expect(!std.mem.eql(u8, &px_before, &px_after));
    app.ui_state.show_damage = false;
    app.ui_state.force_rebuild = false;

    // 节点检视：F12 打开，输出包含 ID 与调用点。
    const node2 = findByName(app.ui_state.current_root, "f32label") orelse return error.TestUnexpectedResult;
    const cx = node2.abs.x + @divTrunc(node2.abs.w, 2);
    const cy = node2.abs.y + @divTrunc(node2.abs.h, 2);
    platform.Headless.injectMouseMove(.{ .x = cx, .y = cy }, .{});
    platform.Headless.injectKey(.f12, true, false, .{});
    try std.testing.expect(app.step());
    var ibuf: [256]u8 = undefined;
    const info = app.ui_state.inspectionText(node2.id, &ibuf);
    var idbuf: [32]u8 = undefined;
    const idneedle = try std.fmt.bufPrint(&idbuf, "id={d}", .{node2.id.raw()});
    try std.testing.expect(std.mem.indexOf(u8, info, idneedle) != null);
    try std.testing.expect(std.mem.indexOf(u8, info, ".zig:") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "rect=(") != null);
    platform.Headless.injectKey(.f12, false, false, .{});
}

fn tableCols(line: []const u8) usize {
    var n: usize = 0;
    for (line) |c| if (c == '|') {
        n += 1;
    };
    return n;
}

test "AC-TEST-022 人工 AC 与执行记录结构完整" {
    for (acceptance_source.pages) |page| {
        var manual = std.StringHashMapUnmanaged(void).empty;
        defer manual.deinit(std.testing.allocator);
        var lines = std.mem.splitScalar(u8, page, '\n');
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, "| AC-")) continue;
            if (std.mem.indexOf(u8, line, "| 人工 |") == null) continue;
            const p1 = std.mem.indexOfScalarPos(u8, line, 2, '|') orelse continue;
            const id = std.mem.trim(u8, line[2..p1], " ");
            try manual.put(std.testing.allocator, id, {});
        }
        const rec_start = std.mem.indexOf(u8, page, "## 人工项执行记录") orelse return error.TestUnexpectedResult;
        var rec = std.mem.splitScalar(u8, page[rec_start..], '\n');
        var found: usize = 0;
        var in_rows = false;
        while (rec.next()) |line| {
            if (std.mem.startsWith(u8, line, "| 条款 |")) {
                in_rows = true;
                continue;
            }
            if (!in_rows or !std.mem.startsWith(u8, line, "| AC-")) continue;
            try std.testing.expectEqual(@as(usize, 8), tableCols(line));
            const p1 = std.mem.indexOfScalarPos(u8, line, 2, '|') orelse continue;
            const id = std.mem.trim(u8, line[2..p1], " ");
            try std.testing.expect(manual.contains(id));
            found += 1;
        }
        try std.testing.expectEqual(manual.count(), found);
    }
}

test "AC-TEST-009 CI 固定 Mesa 版本并校验实际输出" {
    const src = ci_source.source;
    try std.testing.expect(std.mem.indexOf(u8, src, "MESA_VERSION:") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "MESA_VERSION: \"latest\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, src, "Mesa $MESA_VERSION") != null);
    try std.testing.expect(std.mem.indexOf(u8, src, "gl-version.log") != null);
}

const F18Model = struct {
    clicks: u32 = 0,
    pass1_clicked: ?bool = null,
    pass2_clicked: ?bool = null,
    pass1_hover: ?bool = null,
    pass2_hover: ?bool = null,
};
var f18_text: [16]u8 = undefined;
fn f18Build(ctx: *anyopaque, u: *ui.Ui) void {
    const m: *F18Model = @ptrCast(@alignCast(ctx));
    const txt = std.fmt.bufPrint(&f18_text, "{d}", .{m.clicks}) catch "0";
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(8), .gap = .sm });
    _ = widgets.label(u, @src(), txt, .{ .debug_name = "f18label", .key = ui.Key.str("f18label") });
    const r = widgets.button(u, @src(), "Bump", .{ .debug_name = "f18button", .key = ui.Key.str("f18button") });
    if (u.pass == 1) {
        m.pass1_clicked = r.clicked;
        m.pass1_hover = r.hovered;
    } else if (u.pass == 2) {
        m.pass2_clicked = r.clicked;
        m.pass2_hover = r.hovered;
    }
    if (r.clicked) m.clicks += 1;
    u.endColumn();
}

test "AC-FRAME-018 点击帧两遍、计数一次与同帧标签更新" {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = .{ .w = 240, .h = 160 } });
    defer app.deinit();
    var m = F18Model{};
    app.build_ctx = &m;
    app.build_fn = f18Build;
    app.renderOnce(&m, f18Build);
    const btn = findByName(app.ui_state.current_root, "f18button") orelse return error.TestUnexpectedResult;
    const cx = btn.abs.x + @divTrunc(btn.abs.w, 2);
    const cy = btn.abs.y + @divTrunc(btn.abs.h, 2);
    platform.Headless.injectMouseMove(.{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, true, .{ .x = cx, .y = cy }, .{});
    platform.Headless.injectMouseButton(.left, false, .{ .x = cx, .y = cy }, .{});
    try std.testing.expect(app.step());
    try std.testing.expectEqual(@as(u32, 2), app.ui_state.build_passes);
    try std.testing.expectEqual(@as(u32, 1), m.clicks);
    try std.testing.expectEqual(@as(?bool, true), m.pass1_clicked);
    try std.testing.expectEqual(@as(?bool, false), m.pass2_clicked);
    try std.testing.expectEqual(@as(?bool, true), m.pass1_hover);
    try std.testing.expectEqual(@as(?bool, true), m.pass2_hover);
    const label = findByName(app.ui_state.current_root, "f18label") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(core.hashBytes(0x1a2b3c, "1"), label.layout.content.key);
}
