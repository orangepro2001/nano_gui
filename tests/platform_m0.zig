//! M0 platform 无头后端验收测试（AC-PLAT-*）。
const std = @import("std");
const nano = @import("nano_gui");
const core = nano.core;
const platform = nano.platform;
const ui = nano.ui;
const widgets = nano.widgets;

const Headless = platform.Headless;

/// 事件记录器：作为 `EventSink` 使用，复制 `text` 载荷（投递后平台会释放原件），
/// 并在 `system_changed` 投递时抓取此刻的外观快照（验证 REQ-PLAT-046）。
const Collector = struct {
    const Rec = struct {
        data: platform.Data,
        text: ?[]u8 = null,
        appearance_at_delivery: ?platform.SystemAppearance = null,
    };

    list: std.ArrayListUnmanaged(Rec) = .empty,

    fn deinit(self: *Collector) void {
        self.clear();
        self.list.deinit(std.testing.allocator);
    }

    fn clear(self: *Collector) void {
        for (self.list.items) |r| if (r.text) |t| std.testing.allocator.free(t);
        self.list.clearRetainingCapacity();
    }

    fn sink(ctx: ?*anyopaque, e: platform.Event) void {
        const self: *Collector = @ptrCast(@alignCast(ctx.?));
        var rec = Rec{ .data = e.data };
        switch (e.data) {
            .text => |t| rec.text = std.testing.allocator.dupe(u8, t) catch @panic("oom"),
            .system_changed => rec.appearance_at_delivery = platform.appearance(e.window),
            else => {},
        }
        self.list.append(std.testing.allocator, rec) catch @panic("oom");
    }

    /// 取空平台事件队列并记录。
    fn pump(self: *Collector) usize {
        return platform.pumpMessages(.{ .ctx = self, .func = sink });
    }

    fn count(self: *const Collector, comptime tag: std.meta.Tag(platform.Data)) usize {
        var n: usize = 0;
        for (self.list.items) |r| if (r.data == tag) {
            n += 1;
        };
        return n;
    }
};

fn staticBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill, .padding = core.Insets.all(10) });
    _ = widgets.button(u, @src(), "按钮", .{ .debug_name = "b" });
    u.endColumn();
}

fn startApp(size: core.Size) !nano.app.App {
    var app = try nano.app.App.init(std.testing.allocator, .{ .size = size });
    errdefer app.deinit();
    var dummy: u8 = 0;
    app.renderOnce(&dummy, staticBuild);
    // 推进到稳定态：不再有待处理的帧。
    var guard: usize = 0;
    while (app.step()) : (guard += 1) if (guard > 8) break;
    return app;
}

var static_ctx: u8 = 0;

// ---------------------------------------------------------------------------
// AC-PLAT-003
// ---------------------------------------------------------------------------

fn pathUtf8(a: std.mem.Allocator, prefix: []const u8, n: usize) ![]u8 {
    const buf = try a.alloc(u8, prefix.len + n);
    @memcpy(buf[0..prefix.len], prefix);
    @memset(buf[prefix.len..], 'a');
    return buf;
}

test "AC-PLAT-003 字符串转换：BMP 外往返、孤立代理项、空串、32767 单元与长路径" {
    const a = std.testing.allocator;

    // BMP 外字符往返相等。
    const sample = "a😀中\u{10FFFF}z";
    const wide = try platform.utf8ToUtf16Alloc(a, sample);
    defer a.free(wide);
    try std.testing.expectEqual(@as(usize, 1 + 2 + 1 + 2 + 1), wide.len);
    const back = try platform.utf16ToUtf8Alloc(a, wide);
    defer a.free(back);
    try std.testing.expectEqualStrings(sample, back);

    // 孤立代理项（高、低、末尾高）转为 U+FFFD。
    const lone = [_]u16{ 'a', 0xD83D, 'b', 0xDE00, 0xD83D };
    const fixed = try platform.utf16ToUtf8Alloc(a, &lone);
    defer a.free(fixed);
    try std.testing.expectEqualStrings("a\u{FFFD}b\u{FFFD}\u{FFFD}", fixed);

    // 空串为空。
    const e8 = try platform.utf16ToUtf8Alloc(a, &.{});
    defer a.free(e8);
    try std.testing.expectEqual(@as(usize, 0), e8.len);
    const e16 = try platform.utf8ToUtf16Alloc(a, "");
    defer a.free(e16);
    try std.testing.expectEqual(@as(usize, 0), e16.len);
    const ep = try platform.pathToWide(a, "", .prefix);
    defer a.free(ep);
    try std.testing.expectEqual(@as(usize, 0), ep.len);

    // 32 767 个 UTF-16 单元：转换无越界且往返相等。
    const big = try a.alloc(u16, platform.max_extended_path_units);
    defer a.free(big);
    @memset(big, 'x');
    const big8 = try platform.utf16ToUtf8Alloc(a, big);
    defer a.free(big8);
    try std.testing.expectEqual(platform.max_extended_path_units, big8.len);
    const big16 = try platform.utf8ToUtf16Alloc(a, big8);
    defer a.free(big16);
    try std.testing.expectEqualSlices(u16, big, big16);

    // 路径函数：短路径原样；超长路径按调用点要求加前缀或 PathTooLong。
    const short = try platform.pathToWide(a, "C:\\dir\\file.txt", .prefix);
    defer a.free(short);
    try std.testing.expectEqual(@as(usize, 15), short.len);
    try std.testing.expectEqual(@as(u16, 0), short[short.len]);

    const long_n = platform.max_path_units + 40;
    const long_path = try pathUtf8(a, "C:\\", long_n);
    defer a.free(long_path);
    const prefixed = try platform.pathToWide(a, long_path, .prefix);
    defer a.free(prefixed);
    const verbatim = std.unicode.utf8ToUtf16LeStringLiteral("\\\\?\\");
    try std.testing.expect(std.mem.startsWith(u16, prefixed, verbatim));
    try std.testing.expectEqual(long_path.len + verbatim.len, prefixed.len);
    try std.testing.expectError(error.PathTooLong, platform.pathToWide(a, long_path, .reject));

    const unc = try pathUtf8(a, "//srv/share/", long_n);
    defer a.free(unc);
    const unc_w = try platform.pathToWide(a, unc, .prefix);
    defer a.free(unc_w);
    try std.testing.expect(std.mem.startsWith(u16, unc_w, std.unicode.utf8ToUtf16LeStringLiteral("\\\\?\\UNC\\srv\\share\\")));

    // 相对长路径无法加前缀。
    const rel = try pathUtf8(a, "", long_n);
    defer a.free(rel);
    try std.testing.expectError(error.PathTooLong, platform.pathToWide(a, rel, .prefix));

    // 32 767 单元的路径：加前缀后超过上限（及 reject）均为 PathTooLong，且无越界。
    const max_path = try pathUtf8(a, "C:\\", platform.max_extended_path_units - 3);
    defer a.free(max_path);
    try std.testing.expectError(error.PathTooLong, platform.pathToWide(a, max_path, .prefix));
    try std.testing.expectError(error.PathTooLong, platform.pathToWide(a, max_path, .reject));
    // 恰好容得下前缀的边界。
    const edge = try pathUtf8(a, "C:\\", platform.max_extended_path_units - verbatim.len - 3);
    defer a.free(edge);
    const edge_w = try platform.pathToWide(a, edge, .prefix);
    defer a.free(edge_w);
    try std.testing.expectEqual(platform.max_extended_path_units, edge_w.len);
}

// ---------------------------------------------------------------------------
// AC-PLAT-006
// ---------------------------------------------------------------------------

test "AC-PLAT-006 DPI 换算、dpi_changed/resized 事件与最小尺寸钳制" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();

    Headless.setDpi(144);
    const w = try platform.createWindow(.{
        .client_size = .{ .w = 800, .h = 600 },
        .min_client_size = .{ .w = 320, .h = 200 },
    });
    try std.testing.expectEqual(core.Size2i{ .w = 1200, .h = 900 }, w.clientSize());
    try std.testing.expectEqual(@as(f32, 1.5), w.scale());

    // 最小尺寸换算后钳制：100×100 lpx → 320×200 lpx = 480×300 ppx。
    w.setClientSize(.{ .w = 100, .h = 100 });
    try std.testing.expectEqual(core.Size2i{ .w = 480, .h = 300 }, w.clientSize());
    w.setClientSize(.{ .w = 800, .h = 600 });
    try std.testing.expectEqual(core.Size2i{ .w = 1200, .h = 900 }, w.clientSize());
    _ = col.pump();
    col.clear();

    Headless.setDpi(96);
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 1), col.count(.dpi_changed));
    try std.testing.expectEqual(@as(usize, 1), col.count(.resized));
    for (col.list.items) |r| switch (r.data) {
        .dpi_changed => |d| {
            try std.testing.expectEqual(@as(u32, 96), d.dpi);
            try std.testing.expectEqual(@as(f32, 1.0), d.scale);
        },
        .resized => |rz| try std.testing.expectEqual(core.Size2i{ .w = 800, .h = 600 }, rz.client),
        else => {},
    };
    try std.testing.expectEqual(core.Size2i{ .w = 800, .h = 600 }, w.clientSize());
    try std.testing.expectEqual(@as(f32, 1.0), w.scale());

    // setMinClientSize 之后在 96 DPI 下同样钳制。
    w.setMinClientSize(.{ .w = 320, .h = 200 });
    w.setClientSize(.{ .w = 100, .h = 100 });
    try std.testing.expectEqual(core.Size2i{ .w = 320, .h = 200 }, w.clientSize());
    _ = col.pump();
}

// ---------------------------------------------------------------------------
// AC-PLAT-011
// ---------------------------------------------------------------------------

test "AC-PLAT-011 不可见时不呈现，恢复可见后首帧损伤为整根" {
    var app = try startApp(.{ .w = 360, .h = 280 });
    defer app.deinit();
    const w = app.window;
    const client = core.RectI{ .x = 0, .y = 0, .w = w.client.w, .h = w.client.h };

    // 平台层事件：visibility{false}、visibility{true}。
    var col = Collector{};
    defer col.deinit();
    Headless.setVisible(false);
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 1), col.count(.visibility));
    try std.testing.expect(!col.list.items[0].data.visibility.visible);
    col.clear();
    Headless.setVisible(true);
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 1), col.count(.visibility));
    try std.testing.expect(col.list.items[0].data.visibility.visible);

    // 上层行为：不可见期间推进 5 秒并触发模型失效，不得呈现。
    Headless.setVisible(false);
    try std.testing.expect(!w.canPresent());
    const presents0 = Headless.presentCount();
    const stat_presents0 = core.stats.read("frame.presents").?;
    Headless.advanceMs(5 * std.time.ms_per_s);
    app.ui_state.invalidate(.build);
    try std.testing.expect(!app.step());
    try std.testing.expectEqual(presents0, Headless.presentCount());
    try std.testing.expectEqual(stat_presents0, core.stats.read("frame.presents").?);

    // 恢复可见：收到 visibility{true}（由 App 消费），首帧损伤为整根。
    Headless.setVisible(true);
    try std.testing.expect(w.canPresent());
    try std.testing.expect(app.step());
    try std.testing.expectEqual(presents0 + 1, Headless.presentCount());
    try std.testing.expectEqual(client, app.ui_state.lastFrameDamage());
}

// ---------------------------------------------------------------------------
// AC-PLAT-012
// ---------------------------------------------------------------------------

test "AC-PLAT-012 waitMessages 超时、跨线程 wake、合并与 idle" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();

    // (4) 无事件无唤醒：idle（不推进时钟）。
    const t0 = platform.nowMs();
    try std.testing.expectEqual(platform.WaitResult.idle, platform.waitMessages(null));
    try std.testing.expectEqual(t0, platform.nowMs());

    // (1) 无事件：timeout，假时钟前进 100。
    try std.testing.expectEqual(platform.WaitResult.timeout, platform.waitMessages(100));
    try std.testing.expectEqual(t0 + 100, platform.nowMs());

    // (2) 另一线程 wake 后 waitMessages(null) 返回 woken。
    const Waker = struct {
        fn run() void {
            platform.wake();
        }
    };
    const th = try std.Thread.spawn(.{}, Waker.run, .{});
    th.join();
    try std.testing.expectEqual(platform.WaitResult.woken, platform.waitMessages(null));

    // (3) 连续 1000 次 wake 只需一次 waitMessages 即可清空。
    var k: usize = 0;
    while (k < 1000) : (k += 1) platform.wake();
    try std.testing.expectEqual(platform.WaitResult.woken, platform.waitMessages(null));
    try std.testing.expectEqual(platform.WaitResult.idle, platform.waitMessages(null));

    // 有待处理事件时返回 message。
    Headless.injectMouseMove(.{ .x = 1, .y = 1 }, .{});
    try std.testing.expectEqual(platform.WaitResult.message, platform.waitMessages(null));
    var col = Collector{};
    defer col.deinit();
    _ = col.pump();
    try std.testing.expectEqual(platform.WaitResult.idle, platform.waitMessages(null));
}

// ---------------------------------------------------------------------------
// AC-PLAT-014
// ---------------------------------------------------------------------------

const FrameLog = struct {
    var reasons: [32]platform.FrameReason = undefined;
    var depths: [32]u32 = undefined;
    var n: usize = 0;
    var reenter_result: ?anyerror = null;
    var reenter_owner: ?*platform.Window = null;

    fn reset() void {
        n = 0;
        reenter_result = null;
        reenter_owner = null;
    }

    fn record(reason: platform.FrameReason) void {
        reasons[n] = reason;
        depths[n] = Headless.frameDepth();
        n += 1;
    }

    fn cb(_: *platform.Window, reason: platform.FrameReason) void {
        record(reason);
    }

    fn noop(_: ?*anyopaque) void {}

    /// 故意在帧回调内启动嵌套模态循环：必须被拒绝（帧不得重入）。
    fn cbReenter(w: *platform.Window, reason: platform.FrameReason) void {
        record(reason);
        if (reenter_owner) |o| {
            _ = w;
            Headless.simulateNestedModal(o, null, noop) catch |e| {
                reenter_result = e;
            };
        }
    }

    fn modalBody(ctx: ?*anyopaque) void {
        const owner: *platform.Window = @ptrCast(@alignCast(ctx.?));
        // 帧后动作启动嵌套循环时，没有任何帧在运行。
        record_depth_at_entry = Headless.frameDepth();
        Headless.simulateNestedFrame(owner, .paint);
        Headless.simulateNestedFrame(owner, .size);
        Headless.simulateNestedFrame(owner, .timer);
        Headless.simulateNestedFrame(owner, .nested_modal);
        // 模态期间 owner 被禁用：输入不分发。
        Headless.injectMouseMove(.{ .x = 7, .y = 7 }, .{});
        Headless.injectKey(.a, true, false, .{});
    }
    var record_depth_at_entry: u32 = 99;
};

test "AC-PLAT-014 嵌套模态循环内由窗口过程驱动帧：reason 序列、计时器与帧不重入" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();
    const w = try platform.createWindow(.{});
    platform.setFrameCallback(w, null, FrameLog.cb);
    FrameLog.reset();

    // 拖动边框：Enter → 两次 timer → 同步 size 帧 → Exit。
    try std.testing.expectEqual(@as(u32, 0), Headless.timerCount(w));
    Headless.simulateEnterSizeMove(w);
    try std.testing.expectEqual(@as(u32, 1), Headless.timerCount(w));
    // 周期不大于 ceil(1000 / 刷新率)。
    try std.testing.expect(Headless.timerPeriodMs(w) <= platform.framePeriodMs(platform.monitorFromWindow(w).refresh_hz));
    Headless.simulateTimer(w);
    Headless.simulateTimer(w);
    Headless.resizeWindow(w, 900, 700);
    Headless.simulateExitSizeMove(w);
    try std.testing.expectEqual(@as(usize, 3), FrameLog.n);
    try std.testing.expectEqual(platform.FrameReason.timer, FrameLog.reasons[0]);
    try std.testing.expectEqual(platform.FrameReason.timer, FrameLog.reasons[1]);
    try std.testing.expectEqual(platform.FrameReason.size, FrameLog.reasons[2]);
    try std.testing.expectEqual(@as(u32, 0), Headless.timerCount(w));
    // 退出后计时器不再触发帧。
    Headless.simulateTimer(w);
    try std.testing.expectEqual(@as(usize, 3), FrameLog.n);
    try std.testing.expectEqual(@as(u64, 3), Headless.frameCallCount());
    // 每次帧回调深度恒为 1。
    for (FrameLog.depths[0..FrameLog.n]) |d| try std.testing.expectEqual(@as(u32, 1), d);
    try std.testing.expectEqual(@as(u32, 0), Headless.frameDepth());
    _ = col.pump();
    col.clear();

    // 帧后动作启动嵌套循环（对话框桩）。
    FrameLog.reset();
    FrameLog.record_depth_at_entry = 99;
    try Headless.simulateNestedModal(w, w, FrameLog.modalBody);
    try std.testing.expectEqual(@as(u32, 0), FrameLog.record_depth_at_entry);
    try std.testing.expectEqual(@as(usize, 4), FrameLog.n);
    const allowed = [_]platform.FrameReason{ .paint, .size, .timer, .nested_modal };
    for (FrameLog.reasons[0..FrameLog.n], allowed) |got, want| try std.testing.expectEqual(want, got);
    // 嵌套帧的深度恒为 1，从不为 2。
    for (FrameLog.depths[0..FrameLog.n]) |d| try std.testing.expectEqual(@as(u32, 1), d);
    try std.testing.expectEqual(@as(u32, 0), Headless.frameDepth());
    // 模态期间注入的输入事件未被分发到被禁用的 owner。
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 0), col.count(.mouse_move));
    try std.testing.expectEqual(@as(usize, 0), col.count(.key));
    // 模态结束后输入恢复。
    Headless.injectMouseMove(.{ .x = 8, .y = 8 }, .{});
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 1), col.count(.mouse_move));

    // 若在帧回调内启动嵌套循环，则被拒绝（帧后动作必须在帧收尾后运行）。
    FrameLog.reset();
    FrameLog.reenter_owner = w;
    platform.setFrameCallback(w, null, FrameLog.cbReenter);
    Headless.resizeWindow(w, 800, 600);
    try std.testing.expect(FrameLog.reenter_result != null);
    try std.testing.expectEqual(@as(anyerror, error.FrameReentry), FrameLog.reenter_result.?);
    _ = col.pump();
}

// ---------------------------------------------------------------------------
// AC-PLAT-015
// ---------------------------------------------------------------------------

test "AC-PLAT-015 repaint 事件：paint 级损伤恰为该矩形、整个客户区提交；render_lost 整根" {
    var app = try startApp(.{ .w = 360, .h = 280 });
    defer app.deinit();
    const w = app.window;
    const client = core.RectI{ .x = 0, .y = 0, .w = w.client.w, .h = w.client.h };
    const rect = core.RectI{ .x = 10, .y = 10, .w = 100, .h = 50 };

    const presents0 = Headless.presentCount();
    const stat_presents0 = core.stats.read("frame.presents").?;
    Headless.inject(.{ .repaint = .{ .rect = rect } });
    try std.testing.expect(app.step());
    try std.testing.expectEqual(rect, app.ui_state.lastFrameDamage());
    try std.testing.expectEqual(@as(u32, 0), app.ui_state.build_passes);
    try std.testing.expectEqual(@as(u64, 1), core.stats.read("frame.presents").? - stat_presents0);
    try std.testing.expectEqual(presents0 + 1, Headless.presentCount());
    // 提交拷贝的是整个客户区而非仅无效区。
    try std.testing.expectEqual(client, Headless.lastPresentSource());

    // 整窗 render_lost 后下一帧损伤为整根。
    Headless.inject(.render_lost);
    try std.testing.expect(app.step());
    try std.testing.expectEqual(client, app.ui_state.lastFrameDamage());
}

// ---------------------------------------------------------------------------
// AC-PLAT-017
// ---------------------------------------------------------------------------

test "AC-PLAT-017 滚轮累加器：steps 序列、raw 保留、水平轴独立" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();
    _ = try platform.createWindow(.{});

    const raws = [_]i32{ 40, 40, 40, 120, -60, -60, -60 };
    const want_steps = [_]i32{ 0, 0, 1, 1, 0, -1, 0 };
    for (raws) |r| Headless.injectWheelRaw(.vertical, r, .{ .x = 5, .y = 5 }, .{});
    _ = col.pump();
    try std.testing.expectEqual(raws.len, col.list.items.len);
    for (col.list.items, raws, want_steps) |rec, raw, steps| {
        const wh = rec.data.wheel;
        try std.testing.expectEqual(platform.Axis.vertical, wh.axis);
        try std.testing.expectEqual(raw, wh.raw);
        try std.testing.expectEqual(steps, wh.steps);
    }
    col.clear();

    // 水平轴累加器独立于垂直轴（此刻垂直轴余数为 -60）。
    Headless.injectWheelRaw(.horizontal, 60, .{ .x = 5, .y = 5 }, .{});
    Headless.injectWheelRaw(.horizontal, 60, .{ .x = 5, .y = 5 }, .{});
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 2), col.list.items.len);
    try std.testing.expectEqual(@as(i32, 0), col.list.items[0].data.wheel.steps);
    try std.testing.expectEqual(@as(i32, 1), col.list.items[1].data.wheel.steps);
    try std.testing.expectEqual(platform.Axis.horizontal, col.list.items[1].data.wheel.axis);
    col.clear();

    // 整格便捷入口：+1 格 = raw 120、steps 1。
    Headless.injectWheel(1.0, .{ .x = 0, .y = 0 }, .{});
    _ = col.pump();
    try std.testing.expectEqual(@as(i32, 120), col.list.items[0].data.wheel.raw);
    try std.testing.expectEqual(@as(i32, 1), col.list.items[0].data.wheel.steps);
}

// ---------------------------------------------------------------------------
// AC-PLAT-019
// ---------------------------------------------------------------------------

const LogCount = struct {
    var debug_platform: usize = 0;
    fn sink(level: core.log.Level, tag: []const u8, _: []const u8) void {
        if (level == .debug and std.mem.eql(u8, tag, "platform")) debug_platform += 1;
    }
};

test "AC-PLAT-019 键盘事件字段、VK_PROCESSKEY 过滤与 WM_CHAR 文本合并" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();
    _ = try platform.createWindow(.{});
    LogCount.debug_platform = 0;
    core.log.setSink(LogCount.sink);
    defer core.log.setSink(null);

    const shift = platform.Mods{ .shift = true };
    Headless.injectKey(.a, true, false, shift);
    Headless.injectKey(.a, false, false, shift);
    Headless.injectKey(.a, true, true, .{}); // 自动重复
    Headless.injectKey(.process_key, true, false, .{}); // VK_PROCESSKEY
    const chars = [_]u16{ 0xD83D, 0xDE00, 0xD83D, 0x0009, 0x001B, 0x4E2D };
    for (chars) |c| Headless.injectChar(c);
    _ = col.pump();

    var keys: usize = 0;
    var texts: [4][]const u8 = undefined;
    var ntext: usize = 0;
    for (col.list.items) |r| switch (r.data) {
        .key => |k| {
            try std.testing.expect(k.vk != .process_key);
            switch (keys) {
                0 => {
                    try std.testing.expectEqual(platform.VirtualKey.a, k.vk);
                    try std.testing.expect(k.down and !k.repeat and k.mods.shift);
                },
                1 => try std.testing.expect(!k.down and !k.repeat and k.mods.shift),
                2 => try std.testing.expect(k.down and k.repeat and !k.mods.shift),
                else => return error.TestUnexpectedResult,
            }
            keys += 1;
        },
        .text => {
            texts[ntext] = r.text.?;
            ntext += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 3), keys);
    try std.testing.expectEqual(@as(usize, 2), ntext);
    try std.testing.expectEqualStrings("😀", texts[0]);
    try std.testing.expectEqual(@as(usize, 4), texts[0].len);
    try std.testing.expectEqualStrings("中", texts[1]);
    // 孤立代理项丢弃并恰好记 1 条 debug 日志。
    try std.testing.expectEqual(@as(usize, 1), LogCount.debug_platform);
}

// ---------------------------------------------------------------------------
// AC-PLAT-022
// ---------------------------------------------------------------------------

test "AC-PLAT-022 最小化：resized 0×0 恰一个、不可呈现、上层不构建/布局/绘制" {
    var app = try startApp(.{ .w = 360, .h = 280 });
    defer app.deinit();
    const w = app.window;

    // 上层帧统计。
    const frames0 = core.stats.read("frame.count").?;
    const presents0 = core.stats.read("frame.presents").?;
    const painted0 = core.stats.read("frame.nodes_painted").?;
    const builds0 = core.stats.read("frame.build_passes").?;
    const frame_count0 = app.ui_state.frame_count;

    Headless.resize(0, 0);
    w.minimize();
    try std.testing.expect(!w.canPresent());
    try std.testing.expect(!app.step());
    try std.testing.expectEqual(frames0, core.stats.read("frame.count").?);
    try std.testing.expectEqual(presents0, core.stats.read("frame.presents").?);
    try std.testing.expectEqual(painted0, core.stats.read("frame.nodes_painted").?);
    try std.testing.expectEqual(builds0, core.stats.read("frame.build_passes").?);
    try std.testing.expectEqual(frame_count0, app.ui_state.frame_count);
    try std.testing.expect(!app.ui_state.frameDidLayout());

    // 事件层面：先 resize(0×0) 再 minimized，恰产生 1 个 resized{0×0, minimized}。
    w.restore();
    var col = Collector{};
    defer col.deinit();
    _ = col.pump();
    col.clear();
    Headless.resize(0, 0);
    w.minimize();
    _ = col.pump();
    var n_min: usize = 0;
    for (col.list.items) |r| switch (r.data) {
        .resized => |rz| if (rz.state == .minimized) {
            try std.testing.expectEqual(core.Size2i{ .w = 0, .h = 0 }, rz.client);
            n_min += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), n_min);
    try std.testing.expect(!w.canPresent());

    // 仅调用 minimize 同样恰产生 1 个；还原后恢复逻辑尺寸。
    w.restore();
    try std.testing.expectEqual(core.Size2i{ .w = 360, .h = 280 }, w.clientSize());
    _ = col.pump();
    col.clear();
    w.minimize();
    _ = col.pump();
    n_min = 0;
    for (col.list.items) |r| switch (r.data) {
        .resized => |rz| if (rz.state == .minimized and rz.client.w == 0 and rz.client.h == 0) {
            n_min += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), n_min);
    w.restore();
    _ = col.pump();
}

// ---------------------------------------------------------------------------
// AC-PLAT-023
// ---------------------------------------------------------------------------

test "AC-PLAT-023 指针形状记录与去重、键入时隐藏指针" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();
    const w = try platform.createWindow(.{});

    // 形状依次为 arrow、ibeam、hand（头部为按钮/文本框/链接悬停所需形状，REQ-THEME-032）。
    const seq = [_]platform.CursorShape{ .arrow, .ibeam, .hand };
    for (seq) |shape| {
        w.setCursor(shape);
        try std.testing.expectEqual(shape, Headless.cursorShape());
    }
    // 同一位置连续 100 次相同形状：系统应用次数仍为 3。
    var i: usize = 0;
    while (i < 100) : (i += 1) w.setCursor(.hand);
    try std.testing.expectEqual(platform.CursorShape.hand, Headless.cursorShape());
    try std.testing.expectEqual(@as(u64, 3), Headless.cursorApplyCount());

    // SPI_GETMOUSEVANISH 为假：text 事件不隐藏指针。
    Headless.setMouseVanish(false);
    Headless.injectText("x");
    try std.testing.expect(!Headless.pointerHidden());

    // 为真：text 事件后隐藏；坐标不变的移动不恢复；坐标变化的移动恢复。
    Headless.setMouseVanish(true);
    Headless.injectMouseMove(.{ .x = 5, .y = 5 }, .{});
    try std.testing.expect(!Headless.pointerHidden());
    Headless.injectText("a");
    try std.testing.expect(Headless.pointerHidden());
    Headless.injectMouseMove(.{ .x = 5, .y = 5 }, .{});
    try std.testing.expect(Headless.pointerHidden());
    Headless.injectMouseMove(.{ .x = 6, .y = 5 }, .{});
    try std.testing.expect(!Headless.pointerHidden());
    // 经 WM_CHAR 产出的 text 同样隐藏；失去焦点恢复。
    Headless.injectChar('b');
    try std.testing.expect(Headless.pointerHidden());
    Headless.setActive(false);
    try std.testing.expect(!Headless.pointerHidden());
    // 隐藏/恢复不产生 SetCursor 调用。
    try std.testing.expectEqual(@as(u64, 3), Headless.cursorApplyCount());
    _ = col.pump();
}

// ---------------------------------------------------------------------------
// AC-PLAT-024
// ---------------------------------------------------------------------------

/// 系统时钟 API 的标记（出现在 `platform` 之外即违规）。
const clock_api_markers = [_][]const u8{
    "std.time.Instant",
    "std.time.Timer",
    "std.time.milliTimestamp",
    "std.time.nanoTimestamp",
    "std.time.timestamp",
    "Timestamp.now",
    "std.Io.Clock",
    "clock_gettime",
    "GetTickCount",
    "QueryPerformanceCounter",
    "GetSystemTime",
    "timeGetTime",
};

fn referencesSystemClock(source: []const u8) bool {
    for (clock_api_markers) |m| if (std.mem.indexOf(u8, source, m) != null) return true;
    return false;
}

test "AC-PLAT-024 单调时钟、假时钟注入、发布构建拒绝注入与 platform 之外不读系统时钟" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();

    // (1) 真实 nowMs 连续 1000 次单调不减。
    var prev = platform.realNowMs();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const now = platform.realNowMs();
        try std.testing.expect(now >= prev);
        prev = now;
    }

    // (2) 假时钟：advanceMs(250) 恰增 250；自定义时钟注入后 nowMs 返回注入值，取消后恢复。
    try platform.setClock(null);
    const t0 = platform.nowMs();
    Headless.advanceMs(250);
    try std.testing.expectEqual(t0 + 250, platform.nowMs());
    const Fake = struct {
        var value: u64 = 4242;
        fn now(_: *anyopaque) u64 {
            return value;
        }
    };
    var dummy: u8 = 0;
    try platform.setClock(.{ .ctx = &dummy, .now_ms = Fake.now });
    try std.testing.expectEqual(@as(u64, 4242), platform.nowMs());
    try platform.setClock(null);
    try std.testing.expectEqual(t0 + 250, platform.nowMs());
    // 发布构建（非测试构建）的 Win32 后端：注入被拒绝；无头与测试构建允许。
    try std.testing.expect(!platform.clockInjectionAllowed(true, false));
    try std.testing.expect(platform.clockInjectionAllowed(true, true));
    try std.testing.expect(platform.clockInjectionAllowed(false, false));

    // (3) 扫描 src/ 除 platform 外的 Zig 代码：不得引用系统时钟 API。
    try std.testing.expect(referencesSystemClock("const t = std.time.milliTimestamp();"));
    try std.testing.expect(referencesSystemClock("_ = QueryPerformanceCounter(&c);"));
    try std.testing.expect(!referencesSystemClock("const ms = platform.nowMs();"));

    const io = std.testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(std.testing.allocator);
    defer walker.deinit();
    var scanned: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (std.mem.eql(u8, entry.path, "platform.zig") or std.mem.startsWith(u8, entry.path, "platform/") or std.mem.startsWith(u8, entry.path, "platform\\")) continue;
        const text = try dir.readFileAlloc(io, entry.path, std.testing.allocator, .unlimited);
        defer std.testing.allocator.free(text);
        scanned += 1;
        if (referencesSystemClock(text)) {
            std.debug.print("AC-PLAT-024：{s} 引用了系统时钟 API\n", .{entry.path});
            return error.SystemClockReferenced;
        }
    }
    try std.testing.expect(scanned > 0);
}

// ---------------------------------------------------------------------------
// AC-PLAT-025
// ---------------------------------------------------------------------------

test "AC-PLAT-025 无头默认度量与外观、缓存读取无系统调用、消息字体换算" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    const w = try platform.createWindow(.{});

    const m = platform.metrics(w);
    try std.testing.expectEqual(@as(u32, 500), m.double_click_ms);
    try std.testing.expectEqual(core.Size2i{ .w = 4, .h = 4 }, m.double_click_size);
    try std.testing.expectEqual(core.Size2i{ .w = 4, .h = 4 }, m.drag_size);
    try std.testing.expectEqual(platform.ScrollAmount{ .lines = 3 }, m.wheel_lines);
    try std.testing.expectEqual(platform.ScrollAmount{ .lines = 3 }, m.wheel_chars);
    try std.testing.expectEqual(@as(u32, 400), m.menu_show_delay_ms);
    try std.testing.expectEqual(@as(u32, 400), m.hover_time_ms);
    try std.testing.expectEqual(core.Size2i{ .w = 4, .h = 4 }, m.hover_size);
    try std.testing.expectEqual(@as(?u32, 530), m.caret_blink_ms);
    try std.testing.expectEqual(@as(u32, 500), m.key_repeat_delay_ms);
    try std.testing.expectEqual(@as(u32, 33), m.key_repeat_interval_ms);
    try std.testing.expect(!m.keyboard_cues);
    try std.testing.expect(m.client_animation);
    try std.testing.expect(m.menu_animation);
    try std.testing.expect(m.menu_fade);

    const a = platform.appearance(w);
    try std.testing.expect(!a.apps_dark);
    try std.testing.expectEqual(core.Color{ .r = 0x2F, .g = 0x6E, .b = 0xDF, .a = 255 }, a.accent);
    try std.testing.expect(!a.high_contrast);
    try std.testing.expectEqualStrings("NanoTestSans", a.message_font.family);
    try std.testing.expectEqual(@as(f32, 12), a.message_font.size_lpx);
    try std.testing.expectEqual(@as(u16, 400), a.message_font.weight);
    try std.testing.expect(!a.message_font.italic);
    try std.testing.expectEqual(@as(f32, 1.0), a.text_scale);
    try std.testing.expectEqual(m, a.metrics);
    const white = core.Color{ .r = 255, .g = 255, .b = 255 };
    const black = core.Color{ .r = 0, .g = 0, .b = 0 };
    try std.testing.expectEqual(white, a.sys_colors.get(.window));
    try std.testing.expectEqual(black, a.sys_colors.get(.window_text));
    try std.testing.expectEqual(core.Color{ .r = 240, .g = 240, .b = 240 }, a.sys_colors.get(.btn_face));
    try std.testing.expectEqual(black, a.sys_colors.get(.btn_text));
    try std.testing.expectEqual(core.Color{ .r = 109, .g = 109, .b = 109 }, a.sys_colors.get(.gray_text));
    try std.testing.expectEqual(core.Color{ .r = 0, .g = 120, .b = 215 }, a.sys_colors.get(.highlight));
    try std.testing.expectEqual(white, a.sys_colors.get(.highlight_text));
    try std.testing.expectEqual(core.Color{ .r = 0, .g = 102, .b = 204 }, a.sys_colors.get(.hotlight));

    // 帧内读取返回缓存：连续 10 000 次后端系统调用计数为 0。
    const queries0 = Headless.systemQueryCount();
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        const mm = platform.metrics(w);
        const aa = platform.appearance(w);
        std.mem.doNotOptimizeAway(mm);
        std.mem.doNotOptimizeAway(aa);
    }
    try std.testing.expectEqual(queries0, Headless.systemQueryCount());

    // message_font.size_lpx 换算：LOGFONT.lfHeight = -16 @96 DPI、-24 @144 DPI 均为 16。
    try std.testing.expectEqual(@as(f32, 16), platform.messageFontSizeLpx(-16, 96, 0));
    try std.testing.expectEqual(@as(f32, 16), platform.messageFontSizeLpx(-24, 144, 0));
    // 正值为单元高度：减去内部行距后换算。
    try std.testing.expectEqual(@as(f32, 16), platform.messageFontSizeLpx(20, 96, 4));
}

// ---------------------------------------------------------------------------
// AC-PLAT-028
// ---------------------------------------------------------------------------

test "AC-PLAT-028 外观变化：每次恰一个 system_changed、先更新缓存后投递、同轮合并" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();
    const w = try platform.createWindow(.{});

    var cur = platform.appearance(w);
    // 四类变化各一次。
    const Mut = struct {
        fn dark(a: *platform.SystemAppearance) void {
            a.apps_dark = !a.apps_dark;
        }
        fn accent(a: *platform.SystemAppearance) void {
            a.accent = .{ .r = 200, .g = 30, .b = 60, .a = 255 };
        }
        fn contrast(a: *platform.SystemAppearance) void {
            a.high_contrast = !a.high_contrast;
        }
        fn colors(a: *platform.SystemAppearance) void {
            a.sys_colors.set(.window, .{ .r = 10, .g = 20, .b = 30 });
        }
    };
    const muts = [_]*const fn (*platform.SystemAppearance) void{ Mut.dark, Mut.accent, Mut.contrast, Mut.colors };
    for (muts) |mutate| {
        mutate(&cur);
        Headless.setAppearance(cur);
        _ = col.pump();
        try std.testing.expectEqual(@as(usize, 1), col.list.items.len);
        const rec = col.list.items[0];
        try std.testing.expect(rec.data.system_changed.what.appearance);
        // 事件被投递时 appearance(w) 已为新值。
        const seen = rec.appearance_at_delivery.?;
        try std.testing.expectEqual(cur.apps_dark, seen.apps_dark);
        try std.testing.expectEqual(cur.accent, seen.accent);
        try std.testing.expectEqual(cur.high_contrast, seen.high_contrast);
        try std.testing.expectEqual(cur.sys_colors.get(.window), seen.sys_colors.get(.window));
        col.clear();
    }

    // 同一轮注入 3 次变化合并为 1 个事件，投递时为最后一次的值。
    Mut.dark(&cur);
    Headless.setAppearance(cur);
    Mut.contrast(&cur);
    Headless.setAppearance(cur);
    Mut.accent(&cur);
    cur.accent.r +%= 1;
    Headless.setAppearance(cur);
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 1), col.list.items.len);
    try std.testing.expect(col.list.items[0].data.system_changed.what.appearance);
    try std.testing.expectEqual(cur.accent, col.list.items[0].appearance_at_delivery.?.accent);
    try std.testing.expectEqual(cur.apps_dark, col.list.items[0].appearance_at_delivery.?.apps_dark);
}

// ---------------------------------------------------------------------------
// AC-PLAT-041
// ---------------------------------------------------------------------------

test "AC-PLAT-041 多显示器桩：monitors、monitorFromPoint、刷新率回退" {
    try platform.init(std.testing.allocator);
    defer platform.deinit();
    var col = Collector{};
    defer col.deinit();
    _ = try platform.createWindow(.{});

    const primary = platform.Monitor{
        .handle = 1,
        .bounds = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 },
        .work_area = .{ .x = 0, .y = 0, .w = 1920, .h = 1040 },
        .dpi = 96,
        .refresh_hz = 60,
        .primary = true,
    };
    const secondary = platform.Monitor{
        .handle = 2,
        .bounds = .{ .x = -3840, .y = 0, .w = 3840, .h = 2160 },
        .work_area = .{ .x = -3840, .y = 0, .w = 3840, .h = 2120 },
        .dpi = 144,
        .refresh_hz = 120,
        .primary = false,
    };
    Headless.setMonitors(&.{ primary, secondary });
    const ms = platform.monitors();
    try std.testing.expectEqual(@as(usize, 2), ms.len);
    try std.testing.expect(ms[1].bounds.x < 0);
    try std.testing.expectEqual(@as(f32, 1.5), ms[1].scale);
    try std.testing.expectEqual(@as(u32, 120), ms[1].refresh_hz);
    try std.testing.expect(!ms[1].primary);
    try std.testing.expectEqual(@as(f32, 1.0), ms[0].scale);
    try std.testing.expectEqual(@as(u32, 60), ms[0].refresh_hz);
    try std.testing.expect(ms[0].primary);

    // 点在显示器内。
    try std.testing.expectEqual(@as(u64, 1), platform.monitorFromPoint(.{ .x = 100, .y = 100 }).handle);
    try std.testing.expectEqual(@as(u64, 2), platform.monitorFromPoint(.{ .x = -100, .y = 100 }).handle);
    // 点在两屏之外：返回最近者。
    try std.testing.expectEqual(@as(u64, 2), platform.monitorFromPoint(.{ .x = -5000, .y = 300 }).handle);
    try std.testing.expectEqual(@as(u64, 1), platform.monitorFromPoint(.{ .x = 3000, .y = 500 }).handle);
    try std.testing.expectEqual(@as(u64, 1), platform.monitorFromPoint(.{ .x = 500, .y = 1400 }).handle);

    // 取不到刷新率（0）时为 60。
    var no_hz = secondary;
    no_hz.refresh_hz = 0;
    Headless.setMonitors(&.{ primary, no_hz });
    try std.testing.expectEqual(@as(u32, 60), platform.monitors()[1].refresh_hz);

    // 显示器配置变化产出 system_changed{display}（同一轮合并为一个）。
    _ = col.pump();
    try std.testing.expectEqual(@as(usize, 1), col.count(.system_changed));
    try std.testing.expect(col.list.items[0].data.system_changed.what.display);
}
