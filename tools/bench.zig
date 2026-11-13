//! 基准对照表（12 第 3、4 节）：按 REQ-PERF-038 的冻结场景名建场景注册表，
//! 按第 3.2 节预算表逐条判定。未实现或测量对象不是参考界面 G 的项一律“未测”，
//! 不得显示为达标（REQ-PERF-006）。所有数据来自 core.stats（REQ-PERF-005）。

const std = @import("std");
const builtin = @import("builtin");
const nano = @import("nano_gui");
const gallery = @import("gallery");
const bench_paths = @import("bench_paths");
const core = nano.core;
const ui = nano.ui;
const w = nano.widgets;
const gfx = nano.gfx;
const text = nano.text;
const platform = nano.platform;

// ---- 接口草案（12 第 4 节） ----

pub const Judge = enum { hard_both, hard_w_trend_l, trend_both };
pub const Unit = enum { ms, mb, bytes, count, calls, ratio };
pub const Stat = enum { p99, max, run_delta, every_sample_zero, single_read, per_run_each };
pub const Combine = enum { single, sum, difference, equal_across_runs };

pub const Budget = struct {
    req: []const u8,
    name: []const u8,
    limit: ?f64,
    unit: Unit,
    stat: Stat,
    judge: Judge,
    sources: []const []const u8,
    combine: Combine = .single,
};

pub const BenchError = error{ ScenarioUnknown, SetupFailed, SampleMissing, NotReleaseBuild };

pub const BenchResult = struct {
    budget: *const Budget,
    measured: f64 = 0,
    /// 对 trend_both 的项恒为 true，仅记录。
    pass: bool = false,
    /// 非空表示未测，内容为原因（含“未实现（…）”“测量对象不是 G（nodes=N）”）。
    untested: ?[]const u8 = null,
};

// ---- 预算表（第 3.2 节，数值、单位、统计类型、判定类别照抄文档） ----

const budgets = [_]Budget{
    .{ .req = "REQ-PERF-010", .name = "空闲帧数（60 s）", .limit = 0, .unit = .count, .stat = .run_delta, .judge = .hard_both, .sources = &.{"frame.count"} },
    .{ .req = "REQ-PERF-010", .name = "空闲进程 CPU 时间（60 s）", .limit = 10, .unit = .ms, .stat = .run_delta, .judge = .hard_w_trend_l, .sources = &.{} },
    .{ .req = "REQ-PERF-011", .name = "冷启动 time.startup", .limit = 100, .unit = .ms, .stat = .per_run_each, .judge = .hard_w_trend_l, .sources = &.{"time.startup"} },
    .{ .req = "REQ-PERF-011", .name = "冷启动框架自身部分", .limit = 40, .unit = .ms, .stat = .per_run_each, .judge = .hard_both, .sources = &.{ "time.startup", "time.gl_context" }, .combine = .difference },
    .{ .req = "REQ-PERF-012", .name = "G 构建遍 P99", .limit = 1.0, .unit = .ms, .stat = .p99, .judge = .hard_both, .sources = &.{"time.build"} },
    .{ .req = "REQ-PERF-013", .name = "G 全量布局 P99", .limit = 0.5, .unit = .ms, .stat = .p99, .judge = .hard_both, .sources = &.{"time.layout"} },
    .{ .req = "REQ-PERF-014", .name = "G 增量布局 P99", .limit = 0.1, .unit = .ms, .stat = .p99, .judge = .hard_both, .sources = &.{"time.layout"} },
    .{ .req = "REQ-PERF-015", .name = "G 整根绘制 P99", .limit = 2.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.paint"} },
    .{ .req = "REQ-PERF-016", .name = "G 完整帧 CPU P99", .limit = 4.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    .{ .req = "REQ-PERF-017", .name = "悬停纯绘制帧 P99", .limit = 0.3, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    .{ .req = "REQ-PERF-018", .name = "光标闪烁纯绘制帧 P99", .limit = 0.1, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    .{ .req = "REQ-PERF-019", .name = "输入到提交 P99", .limit = 4.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.input_to_present"} },
    .{ .req = "REQ-PERF-020", .name = "10 万行虚拟列表滚动 P99", .limit = 2.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    // 三次运行的 frame.nodes 必须完全相等：measured 为三次读数的极差，上限 0。
    .{ .req = "REQ-PERF-021", .name = "虚拟列表节点数跨规模极差", .limit = 0, .unit = .count, .stat = .single_read, .judge = .hard_both, .sources = &.{"frame.nodes"}, .combine = .equal_across_runs },
    .{ .req = "REQ-PERF-022", .name = "100 万行表格滚动 P99", .limit = 3.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    .{ .req = "REQ-PERF-023", .name = "文本编辑区单次按键 P99", .limit = 2.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    .{ .req = "REQ-PERF-024", .name = "10 MB 文本载入", .limit = 200, .unit = .ms, .stat = .per_run_each, .judge = .hard_w_trend_l, .sources = &.{"time.text_load"} },
    .{ .req = "REQ-PERF-025", .name = "4K 缩放帧 P99", .limit = 8.0, .unit = .ms, .stat = .p99, .judge = .hard_w_trend_l, .sources = &.{"time.frame_cpu"} },
    .{ .req = "REQ-PERF-026", .name = "稳态每帧持久分配增量", .limit = 0, .unit = .count, .stat = .every_sample_zero, .judge = .hard_both, .sources = &.{ "alloc.persistent.count", "alloc.state.count", "alloc.frame.grow_count" } },
    .{ .req = "REQ-PERF-027", .name = "框架自身内存最大值", .limit = 8, .unit = .mb, .stat = .max, .judge = .hard_both, .sources = &.{ "alloc.persistent.bytes", "alloc.arena.bytes" }, .combine = .sum },
    .{ .req = "REQ-PERF-028", .name = "字形图集占用最大值", .limit = 16, .unit = .mb, .stat = .max, .judge = .hard_both, .sources = &.{"cache.glyph_atlas.bytes"} },
    .{ .req = "REQ-PERF-029", .name = "排版缓存占用最大值", .limit = 8, .unit = .mb, .stat = .max, .judge = .hard_both, .sources = &.{"cache.text_layout.bytes"} },
    .{ .req = "REQ-PERF-030", .name = "图像缓存占用最大值", .limit = 64, .unit = .mb, .stat = .max, .judge = .hard_both, .sources = &.{"cache.image.bytes"} },
    .{ .req = "REQ-PERF-031", .name = "最小窗口示例体积（ReleaseSmall）", .limit = 1.5, .unit = .mb, .stat = .single_read, .judge = .hard_both, .sources = &.{} },
    .{ .req = "REQ-PERF-032", .name = "G 可执行文件体积（ReleaseSmall）", .limit = 3, .unit = .mb, .stat = .single_read, .judge = .hard_both, .sources = &.{} },
    .{ .req = "REQ-PERF-033", .name = "GL 绘制调用 P99（仅记录）", .limit = null, .unit = .calls, .stat = .p99, .judge = .trend_both, .sources = &.{"frame.gl_draw_calls"} },
    .{ .req = "REQ-PERF-036", .name = "构建遍 P99 增长（1 万至 100 万行）", .limit = 1.5, .unit = .ratio, .stat = .p99, .judge = .hard_both, .sources = &.{"time.build"} },
};

// ---- 场景注册表（REQ-PERF-038 的 19 个冻结场景名） ----

const Driver = enum {
    idle,
    cold,
    g_build,
    g_layout_full,
    g_layout_inc,
    g_paint_full,
    g_frame,
    g_steady,
    hover,
    caret,
    input,
    vlist_100k,
    vlist_scale,
    table_1m,
    text_key,
    text_load,
    resize_4k,
    cache_limit,
    size_check,
};

const Scene = struct {
    name: []const u8,
    reqs: []const []const u8,
    needs_g: bool,
    driver: Driver,
};

const scenes = [_]Scene{
    .{ .name = "S-IDLE", .reqs = &.{"REQ-PERF-010"}, .needs_g = true, .driver = .idle },
    .{ .name = "S-COLD", .reqs = &.{"REQ-PERF-011"}, .needs_g = true, .driver = .cold },
    .{ .name = "S-G-BUILD", .reqs = &.{"REQ-PERF-012"}, .needs_g = true, .driver = .g_build },
    .{ .name = "S-G-LAYOUT-FULL", .reqs = &.{"REQ-PERF-013"}, .needs_g = true, .driver = .g_layout_full },
    .{ .name = "S-G-LAYOUT-INC", .reqs = &.{"REQ-PERF-014"}, .needs_g = true, .driver = .g_layout_inc },
    .{ .name = "S-G-PAINT-FULL", .reqs = &.{"REQ-PERF-015"}, .needs_g = true, .driver = .g_paint_full },
    .{ .name = "S-G-FRAME", .reqs = &.{ "REQ-PERF-016", "REQ-PERF-033" }, .needs_g = true, .driver = .g_frame },
    .{ .name = "S-G-STEADY", .reqs = &.{ "REQ-PERF-026", "REQ-PERF-027" }, .needs_g = true, .driver = .g_steady },
    .{ .name = "S-HOVER", .reqs = &.{"REQ-PERF-017"}, .needs_g = true, .driver = .hover },
    .{ .name = "S-CARET", .reqs = &.{"REQ-PERF-018"}, .needs_g = true, .driver = .caret },
    .{ .name = "S-INPUT", .reqs = &.{"REQ-PERF-019"}, .needs_g = true, .driver = .input },
    .{ .name = "S-VLIST-100K", .reqs = &.{"REQ-PERF-020"}, .needs_g = false, .driver = .vlist_100k },
    .{ .name = "S-VLIST-SCALE", .reqs = &.{ "REQ-PERF-021", "REQ-PERF-036" }, .needs_g = false, .driver = .vlist_scale },
    .{ .name = "S-TABLE-1M", .reqs = &.{"REQ-PERF-022"}, .needs_g = false, .driver = .table_1m },
    .{ .name = "S-TEXT-KEY", .reqs = &.{"REQ-PERF-023"}, .needs_g = false, .driver = .text_key },
    .{ .name = "S-TEXT-LOAD", .reqs = &.{"REQ-PERF-024"}, .needs_g = false, .driver = .text_load },
    .{ .name = "S-RESIZE-4K", .reqs = &.{"REQ-PERF-025"}, .needs_g = true, .driver = .resize_4k },
    .{ .name = "S-CACHE-LIMIT", .reqs = &.{ "REQ-PERF-028", "REQ-PERF-029", "REQ-PERF-030" }, .needs_g = false, .driver = .cache_limit },
    .{ .name = "S-SIZE", .reqs = &.{ "REQ-PERF-031", "REQ-PERF-032" }, .needs_g = true, .driver = .size_check },
};

// ---- 时钟注入与统计工具 ----

var g_io: std.Io = undefined;
var full_idle: bool = false;

fn clockNs() u64 {
    const t = std.Io.Timestamp.now(g_io, .awake);
    return @intCast(t.nanoseconds);
}

const warmup_frames = 10;
const sample_frames = 1000;

/// 最近秩法 P99：升序第 ceil(0.99 n) 个样本（REQ-PERF-004）。
fn p99(samples: []u64) f64 {
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    const rank = (samples.len * 99 + 99) / 100;
    return @floatFromInt(samples[rank - 1]);
}

fn budgetFor(req: []const u8, nth: usize) ?*const Budget {
    var k: usize = 0;
    for (&budgets) |*b| {
        if (std.mem.eql(u8, b.req, req)) {
            if (k == nth) return b;
            k += 1;
        }
    }
    return null;
}

fn setUntested(r: *BenchResult, why: []const u8) void {
    r.untested = why;
    r.pass = false;
}

fn setValue(r: *BenchResult, v: f64) void {
    r.measured = v;
    r.untested = null;
    r.pass = if (r.budget.limit) |l| v <= l else true;
}

// ---- G 探测与场景驱动 ----

var defer_free: std.ArrayList([]const u8) = .empty;

fn storeOwned(gpa: std.mem.Allocator, str: ?[]u8) []const u8 {
    const owned = str orelse return "（原因文案分配失败）";
    defer_free.append(gpa, owned) catch {
        gpa.free(owned);
        return "（原因文案登记失败）";
    };
    return owned;
}

fn firstUninstrumented(sources: []const []const u8) ?[]const u8 {
    for (sources) |nm| {
        if (!core.stats.isInstrumented(nm)) return nm;
    }
    return null;
}

var probe_nodes_cache: ?u32 = null;

fn startGallery(gpa: std.mem.Allocator, m: *gallery.Model) !nano.app.App {
    var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 1920, .h = 1080 } });
    errdefer app.deinit();
    app.io = g_io;
    app.renderOnce(m, gallery.build);
    app.ui_state.invalidate(.paint);
    _ = app.step();
    return app;
}

fn probeNodes(gpa: std.mem.Allocator) !u32 {
    if (probe_nodes_cache) |n| return n;
    var m = try gallery.Model.init(gpa);
    defer m.deinit();
    var app = try startGallery(gpa, &m);
    defer app.deinit();
    const n: u32 = @intCast(core.stats.read("frame.nodes") orelse 0);
    probe_nodes_cache = n;
    return n;
}

fn discardSamples(name: []const u8) void {
    var tmp: [256]u64 = undefined;
    while (core.stats.drainSamples(name, &tmp) > 0) {}
}

fn drainP99(gpa: std.mem.Allocator, name: []const u8) !?f64 {
    const buf = try gpa.alloc(u64, core.stats.max_samples);
    defer gpa.free(buf);
    const n = core.stats.drainSamples(name, buf);
    if (n < sample_frames) return null;
    return p99(buf[n - sample_frames .. n]) / 1.0e6;
}

fn findDebugNodeCenter(node: ?*ui.Node, name: []const u8) ?core.Vec2i {
    const n = node orelse return null;
    if (n.debug_name) |dn| {
        if (std.mem.eql(u8, dn, name)) {
            return .{ .x = n.abs.x + @divTrunc(n.abs.w, 2), .y = n.abs.y + @divTrunc(n.abs.h, 2) };
        }
    }
    var c = n.first_child;
    while (c) |cc| : (c = cc.next) {
        if (findDebugNodeCenter(cc, name)) |pos| return pos;
    }
    return null;
}

// ---- 专项场景构造 ----

const VListCtx = struct {
    count: usize,
    var bufs: [8][32]u8 = undefined;
    var bi: usize = 0;
    fn itemText(_: ?*anyopaque, idx: usize) []const u8 {
        bi = (bi + 1) % bufs.len;
        return std.fmt.bufPrint(&bufs[bi], "VList row #{d}", .{idx + 1}) catch "row";
    }
    fn build(raw: *anyopaque, u: *ui.Ui) void {
        const self: *VListCtx = @ptrCast(@alignCast(raw));
        _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
        var it = w.beginList(u, @src(), self.count, .{ .debug_name = "bench-vlist", .data = .{ .ctx = null, .item_text = itemText }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
        while (it.next()) |row| w.listLabel(u, @src(), row, itemText(null, row.index), .{});
        _ = w.endList(u, &it);
        u.endColumn();
    }
};

const Table1MCtx = struct {
    var cols_20: [20]w.TableColumn = undefined;
    var cols_init: bool = false;
    var bufs: [8][24]u8 = undefined;
    var bi: usize = 0;
    fn initCols() void {
        if (cols_init) return;
        cols_init = true;
        for (&cols_20, 0..) |*c, i| {
            c.* = .{ .title = if (i == 0) "ID" else "Col", .width = .{ .fixed = 60 } };
        }
    }
    fn cell(_: ?*anyopaque, row: usize, col: u16) []const u8 {
        bi = (bi + 1) % bufs.len;
        return std.fmt.bufPrint(&bufs[bi], "{d}:{d}", .{ row, col }) catch "0";
    }
    fn build(_: *anyopaque, u: *ui.Ui) void {
        initCols();
        _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
        var tbl = w.beginTable(u, @src(), &cols_20, 1_000_000, .{ .debug_name = "bench-table-1m", .data = .{ .ctx = null, .cell_text = cell }, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
        while (tbl.next()) |row| {
            var cells = row.cells();
            while (cells.next()) |c| w.tableCellText(u, @src(), c, cell(null, row.index, c.column), .{});
        }
        _ = w.endTable(u);
        u.endColumn();
    }
};

const TextBenchCtx = struct {
    handle: w.TextAreaHandle = .{ .id = .none },
    fn build(raw: *anyopaque, u: *ui.Ui) void {
        const self: *TextBenchCtx = @ptrCast(@alignCast(raw));
        _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
        const r = w.textArea(u, @src(), .{ .debug_name = "bench-ta", .mono = true, .layout = .{ .main = .{ .grow = 1 }, .cross = .fill } });
        self.handle = r.handle;
        u.endColumn();
    }
};

fn build10MbText(gpa: std.mem.Allocator) ![]u8 {
    // 200,000 行 × 52 字节 ≈ 10.4 MB（REQ-PERF-023/024）。
    const line = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM\n";
    const lines: usize = 200_000;
    const buf = try gpa.alloc(u8, lines * line.len);
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        @memcpy(buf[i * line.len .. (i + 1) * line.len], line);
    }
    return buf;
}

fn minimalHelloBuild(_: *anyopaque, u: *ui.Ui) void {
    _ = u.beginColumn(@src(), .{ .main = .{ .grow = 1 }, .cross = .fill });
    _ = w.label(u, @src(), "hello", .{});
    _ = w.button(u, @src(), "ok", .{});
    u.endColumn();
}

fn runDriver(gpa: std.mem.Allocator, scene: *const Scene, out: []BenchResult) !void {
    core.stats.setClock(clockNs);
    defer core.stats.setClock(null);

    switch (scene.driver) {
        .idle => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            const f0 = core.stats.read("frame.count").?;
            const cpu0 = platform.processCpuTimeMs();
            const wait_ms: u64 = if (full_idle) 60_000 else 200;
            const start_ns = clockNs();
            while ((clockNs() - start_ns) / 1_000_000 < wait_ms) {
                _ = app.step();
                std.Io.sleep(g_io, .fromMilliseconds(10), .awake) catch {};
            }
            const df = core.stats.read("frame.count").? - f0;
            const dcpu = platform.processCpuTimeMs() -| cpu0;
            setValue(&out[0], @floatFromInt(df));
            setValue(&out[1], @floatFromInt(dcpu));
        },
        .cold => {
            discardSamples("time.startup");
            discardSamples("time.gl_context");
            var max_startup: f64 = 0;
            var max_self: f64 = 0;
            var k: usize = 0;
            while (k < 10) : (k += 1) {
                var m = try gallery.Model.init(gpa);
                defer m.deinit();
                var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 1280, .h = 800 } });
                app.io = g_io;
                app.renderOnce(&m, gallery.build);
                var s_buf: [16]u64 = undefined;
                var g_buf: [16]u64 = undefined;
                const sn = core.stats.drainSamples("time.startup", &s_buf);
                const gn = core.stats.drainSamples("time.gl_context", &g_buf);
                app.deinit();
                if (sn > 0 and gn > 0) {
                    const st_ms = @as(f64, @floatFromInt(s_buf[sn - 1])) / 1.0e6;
                    const gl_ms = @as(f64, @floatFromInt(g_buf[gn - 1])) / 1.0e6;
                    max_startup = @max(max_startup, st_ms);
                    max_self = @max(max_self, @max(0, st_ms - gl_ms));
                }
            }
            // 同时冷启动最小示例一次验证。
            var dummy: u8 = 0;
            var app0 = try nano.app.App.init(gpa, .{ .size = .{ .w = 320, .h = 200 } });
            app0.renderOnce(&dummy, minimalHelloBuild);
            app0.deinit();
            setValue(&out[0], max_startup);
            setValue(&out[1], max_self);
        },
        .g_build => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.build");
                app.ui_state.invalidate(.build);
                _ = app.step();
            }
            if (try drainP99(gpa, "time.build")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.build 样本不足 1000");
        },
        .g_layout_full => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.layout");
                platform.Headless.resize(if (i % 2 == 0) 1920 else 1921, 1080);
                _ = app.step();
            }
            if (try drainP99(gpa, "time.layout")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.layout 样本不足 1000");
        },
        .g_layout_inc => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.layout");
                m.var_text_toggle = !m.var_text_toggle;
                app.ui_state.invalidate(.build);
                _ = app.step();
            }
            if (try drainP99(gpa, "time.layout")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.layout 样本不足 1000");
        },
        .g_paint_full => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.paint");
                app.ui_state.invalidateRect(0, .{ .x = 0, .y = 0, .w = 1920, .h = 1080 });
                _ = app.step();
            }
            if (try drainP99(gpa, "time.paint")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.paint 样本不足 1000");
        },
        .g_frame => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            const calls = try gpa.alloc(u64, sample_frames);
            defer gpa.free(calls);
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                m.checked = !m.checked;
                app.ui_state.invalidate(.build);
                const before = core.stats.read("frame.gl_draw_calls") orelse 0;
                _ = app.step();
                if (i >= warmup_frames) calls[i - warmup_frames] = (core.stats.read("frame.gl_draw_calls") orelse 0) - before;
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000");
            setValue(&out[1], p99(calls));
        },
        .g_steady => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            var max_delta: u64 = 0;
            var max_bytes: u64 = 0;
            var last_da: u64 = 0;
            var last_db: u64 = 0;
            var last_dc: u64 = 0;
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                const a = core.stats.read("alloc.persistent.count").?;
                const b = core.stats.read("alloc.state.count").?;
                const c = core.stats.read("alloc.frame.grow_count").?;
                app.ui_state.invalidate(.build);
                _ = app.step();
                if (i < warmup_frames) continue;
                const da = core.stats.read("alloc.persistent.count").? - a;
                const db = core.stats.read("alloc.state.count").? - b;
                const dc = core.stats.read("alloc.frame.grow_count").? - c;
                if (da + db + dc > max_delta) {
                    last_da = da;
                    last_db = db;
                    last_dc = dc;
                }
                max_delta = @max(max_delta, da + db + dc);
                max_bytes = @max(max_bytes, core.stats.read("alloc.persistent.bytes").? + core.stats.read("alloc.arena.bytes").?);
            }
            if (max_delta > 0 or max_bytes > 0) std.debug.print("S-G-STEADY: persistent_delta={d} p_bytes={d} a_bytes={d} sum={d}\n", .{ max_delta, core.stats.read("alloc.persistent.bytes").?, core.stats.read("alloc.arena.bytes").?, max_bytes });
            setValue(&out[0], @floatFromInt(max_delta));
            setValue(&out[1], @as(f64, @floatFromInt(max_bytes)) / 1048576.0);
        },
        .hover => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            const p1 = findDebugNodeCenter(app.ui_state.current_root, "primary-button") orelse core.Vec2i{ .x = 120, .y = 180 };
            const p2 = findDebugNodeCenter(app.ui_state.current_root, "secondary-button") orelse core.Vec2i{ .x = 220, .y = 180 };
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                const pt = if (i % 2 == 0) p1 else p2;
                platform.Headless.injectMouseMove(pt, .{});
                _ = app.step();
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000");
        },
        .caret => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            if (findDebugNodeCenter(app.ui_state.current_root, "toolbar-search") orelse findDebugNodeCenter(app.ui_state.current_root, "name-input")) |np| {
                platform.Headless.injectMouseButton(.left, true, np, .{});
                _ = app.step();
                platform.Headless.injectMouseButton(.left, false, np, .{});
                _ = app.step();
            }
            const blink: u64 = platform.metrics(app.window).caret_blink_ms orelse 530;
            var i: usize = 0;
            while (i < warmup_frames + sample_frames + 4) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                platform.Headless.advanceMs(blink);
                _ = app.step();
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else {
                std.debug.print("S-CARET debug: blinks={d} focus={d}\n", .{ app.ui_state.blinkCount(), app.ui_state.focusedId().raw() });
                setUntested(&out[0], "time.frame_cpu 样本不足 1000");
            }
        },
        .input => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            const p1 = findDebugNodeCenter(app.ui_state.current_root, "primary-button") orelse core.Vec2i{ .x = 120, .y = 180 };
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.input_to_present");
                platform.Headless.injectMouseButton(.left, true, p1, .{});
                _ = app.step();
                platform.Headless.injectMouseButton(.left, false, p1, .{});
                _ = app.step();
            }
            if (try drainP99(gpa, "time.input_to_present")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.input_to_present 样本不足 1000");
        },
        .vlist_100k => {
            var vctx = VListCtx{ .count = 100_000 };
            var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 600, .h = 600 } });
            defer app.deinit();
            app.renderOnce(&vctx, VListCtx.build);
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                platform.Headless.injectWheel(if (i % 2 == 0) -1.0 else 1.0, .{ .x = 200, .y = 200 }, .{});
                _ = app.step();
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000");
        },
        .vlist_scale => {
            const counts = [_]usize{ 10_000, 100_000, 1_000_000 };
            var nodes: [3]u64 = undefined;
            var build_p99: [3]f64 = undefined;
            for (counts, 0..) |cnt, ci| {
                var vctx = VListCtx{ .count = cnt };
                var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 600, .h = 600 } });
                defer app.deinit();
                app.renderOnce(&vctx, VListCtx.build);
                _ = app.step();
                nodes[ci] = core.stats.read("frame.nodes").?;
                var i: usize = 0;
                while (i < warmup_frames + sample_frames) : (i += 1) {
                    if (i == warmup_frames) discardSamples("time.build");
                    app.ui_state.invalidate(.build);
                    _ = app.step();
                }
                build_p99[ci] = (try drainP99(gpa, "time.build")) orelse 0;
            }
            const min_n = @min(nodes[0], @min(nodes[1], nodes[2]));
            const max_n = @max(nodes[0], @max(nodes[1], nodes[2]));
            setValue(&out[0], @floatFromInt(max_n - min_n));
            const ratio = if (build_p99[0] > 0) build_p99[2] / build_p99[0] else 1.0;
            setValue(&out[1], ratio);
        },
        .table_1m => {
            var dummy: u8 = 0;
            var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 1280, .h = 720 } });
            defer app.deinit();
            app.renderOnce(&dummy, Table1MCtx.build);
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                platform.Headless.injectWheel(if (i % 2 == 0) -1.0 else 1.0, .{ .x = 300, .y = 300 }, .{});
                _ = app.step();
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000");
        },
        .text_key => {
            const big = try build10MbText(gpa);
            defer gpa.free(big);
            var tctx = TextBenchCtx{};
            var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 800, .h = 600 } });
            defer app.deinit();
            app.renderOnce(&tctx, TextBenchCtx.build);
            _ = try w.textAreaLoad(&app.ui_state, tctx.handle, big);
            if (findDebugNodeCenter(app.ui_state.current_root, "bench-ta")) |tp| {
                platform.Headless.injectMouseButton(.left, true, tp, .{});
                _ = app.step();
                platform.Headless.injectMouseButton(.left, false, tp, .{});
                _ = app.step();
            }
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                if (i % 2 == 0) {
                    platform.Headless.injectText("x");
                } else {
                    platform.Headless.injectKey(.backspace, true, false, .{});
                    platform.Headless.injectKey(.backspace, false, false, .{});
                }
                _ = app.step();
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000");
        },
        .text_load => {
            const big = try build10MbText(gpa);
            defer gpa.free(big);
            var tctx = TextBenchCtx{};
            var app = try nano.app.App.init(gpa, .{ .size = .{ .w = 800, .h = 600 } });
            defer app.deinit();
            app.renderOnce(&tctx, TextBenchCtx.build);
            discardSamples("time.text_load");
            var max_ms: f64 = 0;
            var k: usize = 0;
            while (k < 10) : (k += 1) {
                _ = try w.textAreaLoad(&app.ui_state, tctx.handle, big);
                var buf: [4]u64 = undefined;
                const n = core.stats.drainSamples("time.text_load", &buf);
                if (n > 0) max_ms = @max(max_ms, @as(f64, @floatFromInt(buf[n - 1])) / 1.0e6);
            }
            setValue(&out[0], max_ms);
        },
        .resize_4k => {
            var m = try gallery.Model.init(gpa);
            defer m.deinit();
            var app = try startGallery(gpa, &m);
            defer app.deinit();
            var i: usize = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                platform.Headless.resize(if (i % 2 == 0) 3840 else 3839, 2160);
                _ = app.step();
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000");
        },
        .cache_limit => {
            try text.init(gpa, .{});
            defer text.deinit();
            gfx.init(gpa);
            defer gfx.deinit();
            var max_atlas: u64 = 0;
            var max_layout: u64 = 0;
            var max_img: u64 = 0;
            var sbuf: [64]u8 = undefined;
            var i: usize = 0;
            while (i < 5000) : (i += 1) {
                text.beginBuild();
                const s = std.fmt.bufPrint(&sbuf, "cache-stress-item-{d}", .{i}) catch "item";
                _ = text.layout(s, .{ .size = 14 }, 1.0, .{});
                text.trimCache();
                if (i < 80) {
                    const pix_buf = try gpa.alloc(u8, 128 * 128 * 4);
                    @memset(pix_buf, @truncate(i));
                    const k = gfx.ImageKey.fromPath(s);
                    _ = gfx.images.insert(k, .{ .width = 128, .height = 128, .rgba = pix_buf, .allocator = gpa }, .{}) catch gpa.free(pix_buf);
                }
                max_atlas = @max(max_atlas, core.stats.read("cache.glyph_atlas.bytes").?);
                max_layout = @max(max_layout, core.stats.read("cache.text_layout.bytes").?);
                max_img = @max(max_img, core.stats.read("cache.image.bytes").?);
            }
            setValue(&out[0], @as(f64, @floatFromInt(max_atlas)) / 1048576.0);
            setValue(&out[1], @as(f64, @floatFromInt(max_layout)) / 1048576.0);
            setValue(&out[2], @as(f64, @floatFromInt(max_img)) / 1048576.0);
        },
        .size_check => {
            const st_hello = std.Io.Dir.cwd().statFile(g_io, bench_paths.hello_small, .{}) catch return error.SetupFailed;
            const st_gal = std.Io.Dir.cwd().statFile(g_io, bench_paths.gallery_small, .{}) catch return error.SetupFailed;
            setValue(&out[0], @as(f64, @floatFromInt(st_hello.size)) / 1048576.0);
            setValue(&out[1], @as(f64, @floatFromInt(st_gal.size)) / 1048576.0);
        },
    }

    for (out) |*r| {
        if (firstUninstrumented(r.budget.sources)) |nm| {
            setUntested(r, storeOwned(gpa, std.fmt.allocPrint(gpa, "{s} 未埋点", .{nm}) catch null));
        }
    }
}

pub fn runScenario(allocator: std.mem.Allocator, name: []const u8) BenchError![]BenchResult {
    if (builtin.mode != .fast and builtin.mode != .small) return error.NotReleaseBuild;
    var scene: ?*const Scene = null;
    for (&scenes) |*s| {
        if (std.mem.eql(u8, s.name, name)) scene = s;
    }
    const sc = scene orelse return error.ScenarioUnknown;

    var list: std.ArrayList(BenchResult) = .empty;
    errdefer list.deinit(allocator);
    for (sc.reqs) |req| {
        var nth: usize = 0;
        while (budgetFor(req, nth)) |b| : (nth += 1) {
            list.append(allocator, .{ .budget = b }) catch return error.SetupFailed;
        }
    }
    const out = list.toOwnedSlice(allocator) catch return error.SetupFailed;
    errdefer allocator.free(out);

    if (sc.needs_g) {
        const n = probeNodes(allocator) catch return error.SetupFailed;
        if (n < 1400 or n > 1600) {
            const why = storeOwned(allocator, std.fmt.allocPrint(allocator, "测量对象不是 G（nodes={d}）", .{n}) catch null);
            for (out) |*r| setUntested(r, why);
            return out;
        }
    }
    runDriver(allocator, sc, out) catch return error.SetupFailed;
    return out;
}

// ---- 输出 ----

fn isHard(b: *const Budget, on_w: bool) bool {
    if (b.limit == null) return false;
    return switch (b.judge) {
        .hard_both => true,
        .hard_w_trend_l => on_w,
        .trend_both => false,
    };
}

fn unitName(u: Unit) []const u8 {
    return @tagName(u);
}

pub fn printTable(writer: anytype, results: []const BenchResult) !bool {
    const on_w = builtin.os.tag == .windows;
    var ok = true;
    try writer.print("{s:<14} {s:<34} {s:>12} {s:>14}  {s}\n", .{ "项", "预算项", "预算", "实测", "结果" });
    for (results) |r| {
        const b = r.budget;
        const hard = isHard(b, on_w);
        var lim_buf: [48]u8 = undefined;
        const lim = if (b.limit) |l|
            try std.fmt.bufPrint(&lim_buf, "<= {d:.2} {s}", .{ l, unitName(b.unit) })
        else
            "无门槛";
        var val_buf: [48]u8 = undefined;
        var verdict: []const u8 = undefined;
        var val: []const u8 = "-";
        if (r.untested) |why| {
            verdict = if (hard) "未测（硬性，不达标）" else "未测";
            try writer.print("{s:<14} {s:<34} {s:>12} {s:>14}  {s}：{s}\n", .{ b.req, b.name, lim, val, verdict, why });
            if (hard) ok = false;
            continue;
        }
        val = try std.fmt.bufPrint(&val_buf, "{d:.3} {s}", .{ r.measured, unitName(b.unit) });
        if (b.limit == null) {
            verdict = "仅记录";
        } else if (r.pass) {
            verdict = if (hard) "达标" else "达标（趋势）";
        } else {
            verdict = if (hard) "超标" else "超标（趋势，仅记录）";
            if (hard) ok = false;
        }
        try writer.print("{s:<14} {s:<34} {s:>12} {s:>14}  {s}\n", .{ b.req, b.name, lim, val, verdict });
    }
    return ok;
}

fn printScenes(writer: anytype) !void {
    try writer.print("场景清单（REQ-PERF-038，共 {d} 个）\n", .{scenes.len});
    for (&scenes) |*s| {
        try writer.print("  {s:<16} 已实现\n", .{s.name});
    }
}

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    var out_buf: [32768]u8 = undefined;
    var wr: std.Io.Writer = .fixed(&out_buf);

    if (builtin.mode != .fast and builtin.mode != .small) {
        try wr.print("bench: 调试构建不适用预算（构建模式 {s}；请使用 -Doptimize=ReleaseFast，REQ-PERF-009）\n", .{@tagName(builtin.mode)});
        try std.Io.File.stderr().writeStreamingAll(init.io, wr.buffered());
        std.process.exit(2);
    }

    var only_scene: ?[]const u8 = null;
    var verbose = false;
    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer arg_it.deinit();
    while (arg_it.next()) |a| {
        if (std.mem.eql(u8, a, "--full-idle")) full_idle = true;
        if (std.mem.eql(u8, a, "--verbose")) verbose = true;
        if (std.mem.startsWith(u8, a, "--scenario=")) only_scene = a["--scenario=".len..];
    }

    nano.platform.forceHeadless();
    var pa = core.PersistentAllocator.init();
    defer _ = pa.deinit();
    const gpa = pa.allocator();
    const on_w = builtin.os.tag == .windows;

    try wr.print("bench: 环境 {s}；构建 {s}；CPU {s}；GPU 无头（无）；缩放 100%（无头）\n", .{
        if (on_w) "W" else "L（Linux 无头）",
        @tagName(builtin.mode),
        builtin.cpu.model.name,
    });
    if (!on_w) try wr.writeAll("bench: 未在 W 验证（REQ-PERF-008）；L 上绘制/帧耗时类仅为趋势\n");
    try wr.print("bench: 统计口径 预热 {d} 帧丢弃 + 采样 {d} 帧（REQ-PERF-004）\n\n", .{ warmup_frames, sample_frames });

    var all: [budgets.len]BenchResult = undefined;
    for (&budgets, 0..) |*b, i| all[i] = .{ .budget = b, .untested = "REQ-PERF-038 的冻结场景未承载本项" };
    for (&scenes) |*s| {
        if (only_scene) |os| if (!std.mem.eql(u8, s.name, os)) continue;
        const t0 = clockNs();
        const rs = runScenario(gpa, s.name) catch |e| {
            for (s.reqs) |req| {
                for (&all) |*r| {
                    if (std.mem.eql(u8, r.budget.req, req)) setUntested(r, @errorName(e));
                }
            }
            continue;
        };
        if (verbose) std.debug.print("bench: {s} -> {d:.1} ms\n", .{ s.name, @as(f64, @floatFromInt(clockNs() - t0)) / 1.0e6 });
        defer gpa.free(rs);
        for (rs) |r| {
            for (&all) |*slot| {
                if (slot.budget == r.budget) slot.* = r;
            }
        }
    }

    defer {
        for (defer_free.items) |str| gpa.free(str);
        defer_free.deinit(gpa);
    }
    const ok = try printTable(&wr, &all);
    try wr.writeAll("\n");
    try printScenes(&wr);
    try wr.print("\nbench: {s}\n", .{if (ok) "全部硬性项达标" else "存在硬性项超标或未测"});
    try std.Io.File.stdout().writeStreamingAll(init.io, wr.buffered());
    if (!ok) std.process.exit(1);
}
