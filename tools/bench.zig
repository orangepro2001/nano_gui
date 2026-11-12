//! 基准对照表（12 第 3、4 节）：按 REQ-PERF-038 的冻结场景名建场景注册表，
//! 按第 3.2 节预算表逐条判定。未实现或测量对象不是参考界面 G 的项一律“未测”，
//! 不得显示为达标（REQ-PERF-006）。所有数据来自 core.stats（REQ-PERF-005）。

const std = @import("std");
const builtin = @import("builtin");
const nano = @import("nano_gui");
const gallery = @import("gallery");
const core = nano.core;

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

const Driver = enum { none, g_build, g_frame, g_steady };

const Scene = struct {
    name: []const u8,
    /// 本场景的被测预算（按 REQ 编号）。
    reqs: []const []const u8,
    /// 是否以参考界面 G 为测量对象（需先核对 frame.nodes，REQ-PERF-003）。
    needs_g: bool,
    driver: Driver,
    /// driver == .none 时的未实现原因。
    reason: []const u8 = "",
};

const scenes = [_]Scene{
    .{ .name = "S-IDLE", .reqs = &.{"REQ-PERF-010"}, .needs_g = true, .driver = .none, .reason = "需 60 秒静置与平台进程 CPU 时间读数，platform 尚未提供" },
    .{ .name = "S-COLD", .reqs = &.{"REQ-PERF-011"}, .needs_g = true, .driver = .none, .reason = "需进程级冷启动驱动，且 time.startup / time.gl_context 尚未在入口埋点" },
    .{ .name = "S-G-BUILD", .reqs = &.{"REQ-PERF-012"}, .needs_g = true, .driver = .g_build },
    .{ .name = "S-G-LAYOUT-FULL", .reqs = &.{"REQ-PERF-013"}, .needs_g = true, .driver = .none, .reason = "需经 13 的回放运行器驱动 resize，bench 尚未接入" },
    .{ .name = "S-G-LAYOUT-INC", .reqs = &.{"REQ-PERF-014"}, .needs_g = true, .driver = .none, .reason = "需含文本长度可变叶节点的 G 构造" },
    .{ .name = "S-G-PAINT-FULL", .reqs = &.{"REQ-PERF-015"}, .needs_g = true, .driver = .none, .reason = "整窗口 invalidateRect 驱动尚未实现" },
    .{ .name = "S-G-FRAME", .reqs = &.{ "REQ-PERF-016", "REQ-PERF-033" }, .needs_g = true, .driver = .g_frame },
    .{ .name = "S-G-STEADY", .reqs = &.{ "REQ-PERF-026", "REQ-PERF-027" }, .needs_g = true, .driver = .g_steady },
    .{ .name = "S-HOVER", .reqs = &.{"REQ-PERF-017"}, .needs_g = true, .driver = .none, .reason = "需回放脚本驱动 move，bench 尚未接入回放运行器" },
    .{ .name = "S-CARET", .reqs = &.{"REQ-PERF-018"}, .needs_g = true, .driver = .none, .reason = "需回放脚本驱动 advance 与聚焦文本框，bench 尚未接入回放运行器" },
    .{ .name = "S-INPUT", .reqs = &.{"REQ-PERF-019"}, .needs_g = true, .driver = .none, .reason = "需回放脚本驱动 down/up，且 time.input_to_present 尚未埋点" },
    .{ .name = "S-VLIST-100K", .reqs = &.{"REQ-PERF-020"}, .needs_g = false, .driver = .none, .reason = "10 万行虚拟列表场景构造与回放驱动尚未实现" },
    .{ .name = "S-VLIST-SCALE", .reqs = &.{ "REQ-PERF-021", "REQ-PERF-035", "REQ-PERF-036" }, .needs_g = false, .driver = .none, .reason = "1 万/100 万两档比值尚未实现；1 万/10 万/100 万行虚拟列表场景构造尚未实现" },
    .{ .name = "S-TABLE-1M", .reqs = &.{"REQ-PERF-022"}, .needs_g = false, .driver = .none, .reason = "100 万行 x 20 列表格场景尚未实现" },
    .{ .name = "S-TEXT-KEY", .reqs = &.{"REQ-PERF-023"}, .needs_g = false, .driver = .none, .reason = "10 MB 文本编辑区构造与按键回放驱动尚未实现" },
    .{ .name = "S-TEXT-LOAD", .reqs = &.{"REQ-PERF-024"}, .needs_g = false, .driver = .none, .reason = "10 MB 文本载入驱动尚未实现，time.text_load 尚未埋点" },
    .{ .name = "S-RESIZE-4K", .reqs = &.{"REQ-PERF-025"}, .needs_g = true, .driver = .none, .reason = "需回放脚本驱动 4K 缩放，bench 尚未接入回放运行器" },
    .{ .name = "S-CACHE-LIMIT", .reqs = &.{ "REQ-PERF-028", "REQ-PERF-029", "REQ-PERF-030" }, .needs_g = false, .driver = .none, .reason = "持续写入字形、排版与图像内容的驱动尚未实现" },
    .{ .name = "S-SIZE", .reqs = &.{ "REQ-PERF-031", "REQ-PERF-032" }, .needs_g = true, .driver = .none, .reason = "最小窗口示例与 G 的 ReleaseSmall 产物未在构建中登记，bench 无法读取" },
};

// ---- 时钟注入与统计工具 ----

var g_io: std.Io = undefined;

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

/// runScenario 分配的原因字符串，main 结束前统一释放。
var defer_free: std.ArrayList([]const u8) = .empty;

/// 接管 allocPrint 的结果以便统一释放；分配失败或登记失败时退回静态文案。
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

/// 在 1920x1080 下构建测量对象并读取稳定帧的 frame.nodes。
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

/// 丢弃某计时器已积累的全部样本（预热）。
fn discardSamples(name: []const u8) void {
    var tmp: [256]u64 = undefined;
    while (core.stats.drainSamples(name, &tmp) > 0) {}
}

fn drainP99(gpa: std.mem.Allocator, name: []const u8) !?f64 {
    const buf = try gpa.alloc(u64, core.stats.max_samples);
    defer gpa.free(buf);
    const n = core.stats.drainSamples(name, buf);
    if (n < sample_frames) return null;
    // 取最近 1000 个样本。
    return p99(buf[n - sample_frames .. n]) / 1.0e6;
}

fn runDriver(gpa: std.mem.Allocator, scene: *const Scene, out: []BenchResult) !void {
    var m = try gallery.Model.init(gpa);
    defer m.deinit();
    var app = try startGallery(gpa, &m);
    defer app.deinit();
    core.stats.setClock(clockNs);
    defer core.stats.setClock(null);

    var i: usize = 0;
    switch (scene.driver) {
        .none => unreachable,
        .g_build => {
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.build");
                app.ui_state.invalidate(.build);
                _ = app.step();
            }
            if (try drainP99(gpa, "time.build")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.build 样本不足 1000，计时点尚未埋入构建遍");
        },
        .g_frame => {
            const calls = try gpa.alloc(u64, sample_frames);
            defer gpa.free(calls);
            while (i < warmup_frames + sample_frames) : (i += 1) {
                if (i == warmup_frames) discardSamples("time.frame_cpu");
                m.checked = !m.checked;
                app.ui_state.invalidate(.build);
                const before = core.stats.read("frame.gl_draw_calls") orelse 0;
                _ = app.step();
                if (i >= warmup_frames) calls[i - warmup_frames] = (core.stats.read("frame.gl_draw_calls") orelse 0) - before;
            }
            if (try drainP99(gpa, "time.frame_cpu")) |v| setValue(&out[0], v) else setUntested(&out[0], "time.frame_cpu 样本不足 1000，计时点尚未埋入帧循环");
            setValue(&out[1], p99(calls));
        },
        .g_steady => {
            var max_delta: u64 = 0;
            var max_bytes: u64 = 0;
            while (i < warmup_frames + sample_frames) : (i += 1) {
                const a = core.stats.read("alloc.persistent.count").?;
                const b = core.stats.read("alloc.state.count").?;
                const c = core.stats.read("alloc.frame.grow_count").?;
                app.ui_state.invalidate(.build);
                _ = app.step();
                if (i < warmup_frames) continue;
                max_delta = @max(max_delta, (core.stats.read("alloc.persistent.count").? - a) + (core.stats.read("alloc.state.count").? - b) + (core.stats.read("alloc.frame.grow_count").? - c));
                max_bytes = @max(max_bytes, core.stats.read("alloc.persistent.bytes").? + core.stats.read("alloc.arena.bytes").?);
            }
            setValue(&out[0], @floatFromInt(max_delta));
            setValue(&out[1], @as(f64, @floatFromInt(max_bytes)) / 1048576.0);
        },
    }
    // 数据源从未被使用点写入时读数恒为 0，不得据此判达标，一律判未测。
    for (out) |*r| {
        if (firstUninstrumented(r.budget.sources)) |nm| {
            setUntested(r, storeOwned(gpa, std.fmt.allocPrint(gpa, "{s} 未埋点", .{nm}) catch null));
        }
    }
}

/// 运行一个基准场景，返回该场景各被测预算的结果（调用方释放）。
/// 非发布构建返回 NotReleaseBuild（REQ-PERF-009）。
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
    if (sc.driver == .none) {
        const why = storeOwned(allocator, std.fmt.allocPrint(allocator, "未实现（{s}）", .{sc.reason}) catch null);
        for (out) |*r| setUntested(r, why);
        return out;
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

/// 输出对照表；返回 true 表示全部硬性项达标（未测的硬性项视为不达标）。
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
        if (s.driver == .none) {
            try writer.print("  {s:<16} 未实现（{s}）\n", .{ s.name, s.reason });
        } else {
            try writer.print("  {s:<16} 已实现（仅当测量对象为 G 时有效）\n", .{s.name});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    var out_buf: [32768]u8 = undefined;
    var w: std.Io.Writer = .fixed(&out_buf);

    if (builtin.mode != .fast and builtin.mode != .small) {
        try w.print("bench: 调试构建不适用预算（构建模式 {s}；请使用 -Doptimize=ReleaseFast，REQ-PERF-009）\n", .{@tagName(builtin.mode)});
        try std.Io.File.stderr().writeStreamingAll(init.io, w.buffered());
        std.process.exit(2);
    }

    nano.platform.forceHeadless();
    const gpa = init.gpa;
    const on_w = builtin.os.tag == .windows;

    try w.print("bench: 环境 {s}；构建 {s}；CPU {s}；GPU 无头（无）；缩放 100%（无头）\n", .{
        if (on_w) "W" else "L（Linux 无头）",
        @tagName(builtin.mode),
        builtin.cpu.model.name,
    });
    if (!on_w) try w.writeAll("bench: 未在 W 验证（REQ-PERF-008）；L 上绘制/帧耗时类仅为趋势\n");
    try w.print("bench: 统计口径 预热 {d} 帧丢弃 + 采样 {d} 帧（REQ-PERF-004）\n\n", .{ warmup_frames, sample_frames });

    var all: [budgets.len]BenchResult = undefined;
    for (&budgets, 0..) |*b, i| all[i] = .{ .budget = b, .untested = "REQ-PERF-038 的冻结场景未承载本项" };
    for (&scenes) |*s| {
        const rs = runScenario(gpa, s.name) catch |e| {
            for (s.reqs) |req| {
                for (&all) |*r| {
                    if (std.mem.eql(u8, r.budget.req, req)) setUntested(r, @errorName(e));
                }
            }
            continue;
        };
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
    const ok = try printTable(&w, &all);
    try w.writeAll("\n");
    try printScenes(&w);
    try w.print("\nbench: {s}\n", .{if (ok) "全部硬性项达标" else "存在硬性项超标或未测"});
    try std.Io.File.stdout().writeStreamingAll(init.io, w.buffered());
    if (!ok) std.process.exit(1);
}
