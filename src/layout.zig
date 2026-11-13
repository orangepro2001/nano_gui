//! 布局：尺寸策略、整数求解、专用容器参数与纯函数求解器（07）。
//! 节点树上的测量/排布由 ui 模块驱动，本模块只提供不依赖 ui 的算法。

const std = @import("std");
const core = @import("core.zig");
const theme = @import("theme.zig");
const builtin = @import("builtin");

/// 测试：强制走“发布构建”的非法 grow 权重恢复路径。
pub var test_force_soft_grow_weight: bool = false;

pub const unbounded: i32 = 1 << 28;

pub const Align = enum { start, center, end };
pub const Justify = enum { start, center, end, space_between };

pub const Extent = union(enum) {
    fixed: f32,
    fit,
    fit_shrink,
    grow: f32,

    pub fn fixedSize(v: f32) Extent {
        return .{ .fixed = v };
    }
};

pub const CrossExtent = union(enum) {
    fixed: f32,
    fit,
    fill,

    pub fn fixedSize(v: f32) CrossExtent {
        return .{ .fixed = v };
    }
};

pub const HeightForWidthFn = *const fn (ctx: ?*const anyopaque, width_lpx: f32) f32;

pub const Content = struct {
    size: core.Vec2 = .{ .x = 0, .y = 0 },
    key: u64 = 0,
    hfw: ?HeightForWidthFn = null,
    hfw_ctx: ?*const anyopaque = null,
};

pub const SizeI = core.Size2i;
pub const Limit = struct { w: i32, h: i32, definite_w: bool = false, definite_h: bool = false };
pub const MeasureMode = enum { natural, min };

pub const BarPolicy = enum { auto, always, never };
pub const ScrollAxes = enum { vertical, horizontal, both };
pub const ScrollParams = struct {
    axes: ScrollAxes = .vertical,
    bar_v: BarPolicy = .auto,
    bar_h: BarPolicy = .auto,
    offset: core.Vec2 = .{ .x = 0, .y = 0 },
    offset_px: ?[2]i64 = null,
    virtual_extent_px: ?[2]i64 = null,
    anchor_end: bool = false,
    reveal: ?core.Rect = null,
};

pub const ScrollMetrics = struct {
    offset: core.Vec2,
    offset_px: struct { x: i32, y: i32 },
    content_px: [2]i64 = .{ 0, 0 },
    viewport_px: [2]i32 = .{ 0, 0 },
    max_offset: core.Vec2,
    viewport: core.Rect,
    content: core.Vec2,
    bar_v: ?core.RectI,
    bar_h: ?core.RectI,
};

pub const Orientation = enum { horizontal, vertical };
pub const SplitPos = union(enum) {
    ratio: f32,
    fixed_first: f32,
    fixed_second: f32,
};
pub const SplitterParams = struct {
    orientation: Orientation = .horizontal,
    pos: SplitPos = .{ .ratio = 0.5 },
    min_first: f32 = 0,
    min_second: f32 = 0,
};
pub const SplitMetrics = struct { first_px: i32, second_px: i32, divider: core.RectI };

pub const ColumnWidth = union(enum) { fixed: f32, grow: f32, auto_header };
pub const Column = struct { width: ColumnWidth, min: f32 = 0, max: f32 = std.math.inf(f32) };
pub const TableParams = struct {
    columns: []const Column = &.{},
    header_rows: u8 = 1,
    col_gap: theme.Gap = .none,
};
pub const FormParams = struct { label_max: f32 = 240, col_gap: theme.Gap = .md };

pub const Side = enum { below, above, right, left };
pub const Placement = struct { side: Side = .below, align_: Align = .start, flip_cross: bool = false };
pub const AnchorTarget = union(enum) { parent, rect: core.Rect };
pub const AnchorBounds = enum { parent, root };
pub const AnchorParams = struct {
    target: AnchorTarget = .parent,
    placement: Placement = .{},
    gap: theme.Gap = .none,
    bounds: AnchorBounds = .parent,
};
pub const PlaceResult = struct { rect: core.RectI, side_used: Side, clamped: bool, height_limited: bool };

pub const Kind = union(enum) {
    leaf,
    row,
    column,
    stack,
    scroll: ScrollParams,
    splitter: SplitterParams,
    table: TableParams,
    table_row,
    form: FormParams,
    anchor: AnchorParams,
    custom: CustomLayout,
};

pub const CustomLayout = struct {
    key: u64,
    measure: *const fn (ctx: *MeasureCtx, mode: MeasureMode, limit: Limit) SizeI,
    arrange: *const fn (ctx: *ArrangeCtx, rect: core.RectI) void,
};

pub const MeasureCtx = struct {
    scale: f32,
    ctx: ?*anyopaque = null,
    child_count_fn: ?*const fn (ctx: *anyopaque) usize = null,
    child_params_fn: ?*const fn (ctx: *anyopaque, index: usize) *const Params = null,
    measure_child_fn: ?*const fn (ctx: *anyopaque, index: usize, limit: Limit) SizeI = null,

    pub fn childCount(self: *const MeasureCtx) usize {
        if (self.ctx) |c| if (self.child_count_fn) |f| return f(c);
        return 0;
    }
    pub fn childParams(self: *const MeasureCtx, index: usize) *const Params {
        if (self.ctx) |c| if (self.child_params_fn) |f| return f(c, index);
        return &default_params;
    }
    pub fn measureChild(self: *MeasureCtx, index: usize, limit: Limit) SizeI {
        if (self.ctx) |c| if (self.measure_child_fn) |f| return f(c, index, limit);
        return .{};
    }
    pub fn px(self: *const MeasureCtx, lpx: f32) i32 {
        if (lpx == 0) return 0;
        return @max(1, @as(i32, @intFromFloat(@round(lpx * self.scale))));
    }
};

pub const ArrangeCtx = struct {
    scale: f32,
    ctx: ?*anyopaque = null,
    child_count_fn: ?*const fn (ctx: *anyopaque) usize = null,
    child_params_fn: ?*const fn (ctx: *anyopaque, index: usize) *const Params = null,
    measure_child_fn: ?*const fn (ctx: *anyopaque, index: usize, limit: Limit) SizeI = null,
    place_child_fn: ?*const fn (ctx: *anyopaque, index: usize, rect: core.RectI) void = null,

    pub fn childCount(self: *const ArrangeCtx) usize {
        if (self.ctx) |c| if (self.child_count_fn) |f| return f(c);
        return 0;
    }
    pub fn childParams(self: *const ArrangeCtx, index: usize) *const Params {
        if (self.ctx) |c| if (self.child_params_fn) |f| return f(c, index);
        return &default_params;
    }
    pub fn measureChild(self: *ArrangeCtx, index: usize, limit: Limit) SizeI {
        if (self.ctx) |c| if (self.measure_child_fn) |f| return f(c, index, limit);
        return .{};
    }
    pub fn placeChild(self: *ArrangeCtx, index: usize, rect: core.RectI) void {
        if (self.ctx) |c| if (self.place_child_fn) |f| f(c, index, rect);
    }
    pub fn px(self: *const ArrangeCtx, lpx: f32) i32 {
        if (lpx == 0) return 0;
        return @max(1, @as(i32, @intFromFloat(@round(lpx * self.scale))));
    }
};

const default_params = Params{};

pub const Params = struct {
    kind: Kind = .leaf,
    main: Extent = .fit,
    cross: CrossExtent = .fit,
    main_min: f32 = 0,
    main_max: f32 = std.math.inf(f32),
    cross_min: f32 = 0,
    cross_max: f32 = std.math.inf(f32),
    padding: core.Insets = .{},
    /// 发丝线边框数；内容区额外内缩 border × hairline（REQ-LAYOUT-056）。
    border: u8 = 0,
    /// 仅虚拟化容器子项：相对视口的位置（ppx；REQ-LAYOUT-054）。
    virtual_pos_px: ?[2]i32 = null,
    gap: theme.Gap = .none,
    justify: Justify = .start,
    cross_align: Align = .start,
    self_align: ?Align = null,
    self_main_align: ?Align = null,
    form_span: bool = false,
    content: Content = .{},
};

pub const ContainerOptions = struct {
    key: ?*anyopaque = null,
    debug_name: ?[]const u8 = null,
    main: Extent = .fit,
    cross: CrossExtent = .fit,
    main_min: f32 = 0,
    main_max: f32 = std.math.inf(f32),
    cross_min: f32 = 0,
    cross_max: f32 = std.math.inf(f32),
    padding: core.Insets = .{},
    /// 发丝线边框数；内容区额外内缩 border × hairline（REQ-LAYOUT-056）。
    border: u8 = 0,
    gap: theme.Gap = .none,
    justify: Justify = .start,
    cross_align: Align = .start,
    self_align: ?Align = null,
    clip: bool = false,
    hidden: bool = false,
};

pub const ItemOptions = struct {
    main: ?Extent = null,
    cross: ?CrossExtent = null,
    main_min: ?f32 = null,
    main_max: ?f32 = null,
    cross_min: ?f32 = null,
    cross_max: ?f32 = null,
    self_align: ?Align = null,
    hidden: bool = false,
};

pub fn quantizeWeight(weight: f32) u32 {
    if (!(weight > 0)) {
        if (builtin.optimize == .debug and !test_force_soft_grow_weight) {
            std.debug.panic("grow 权重必须大于 0（REQ-LAYOUT-030）", .{});
        }
        return 0;
    }
    const q = @round(weight * 1024.0);
    if (q < 1) return 1;
    if (q > 4_000_000_000.0) return 4_000_000_000;
    return @intFromFloat(q);
}

/// 最大余数法（REQ-LAYOUT-015）。
pub fn apportion(scratch: std.mem.Allocator, total: i32, weights: []const u64, out: []i32) void {
    var wsum: u64 = 0;
    for (weights) |w| wsum += w;
    if (out.len == 0) return;
    if (total <= 0 or wsum == 0) {
        for (out) |*o| o.* = 0;
        return;
    }
    var sum: i64 = 0;
    for (weights, 0..) |w, i| {
        if (i >= out.len) break;
        const share = @divTrunc(@as(i64, total) * @as(i64, @intCast(@min(w, @as(u64, std.math.maxInt(i64))))), @as(i64, @intCast(wsum)));
        out[i] = @intCast(share);
        sum += share;
    }
    var remainder: i64 = @as(i64, total) - sum;
    if (remainder <= 0) return;
    var used_stack: [32]bool = undefined;
    const used: []bool = if (out.len <= 32) used_stack[0..out.len] else (scratch.alloc(bool, out.len) catch @panic("nano_gui: layout scratch exhausted"));
    @memset(used, false);
    while (remainder > 0) {
        var best: ?usize = null;
        var best_rem: u64 = 0;
        for (weights, 0..) |w, i| {
            if (i >= out.len) break;
            if (used[i]) continue;
            const rem: u64 = (@as(u64, @intCast(total)) * w) % wsum;
            if (best == null or rem > best_rem) {
                best_rem = rem;
                best = i;
            }
        }
        const bi = best orelse break;
        out[bi] += 1;
        used[bi] = true;
        remainder -= 1;
    }
}

pub const FlexKind = enum { fixed, fit, shrink, grow };
pub const FlexItem = struct { kind: FlexKind, base: i32, min: i32, max: i32, wq: u32 };
pub const DistributeResult = struct { overflow: i32, leftover: i32 };

fn clamp(v: i32, lo: i32, hi: i32) i32 {
    if (hi < lo) return lo;
    return std.math.clamp(v, lo, hi);
}

/// 线性容器主轴分配（REQ-LAYOUT-016 至 REQ-LAYOUT-019）。
pub fn distribute(scratch: std.mem.Allocator, items: []const FlexItem, avail: i32, out: []i32) DistributeResult {
    std.debug.assert(out.len == items.len); // 调用方须提供与 items 等长的输出缓冲（REQ-LAYOUT-016）
    if (items.len == 0) return .{ .overflow = 0, .leftover = @max(0, avail) };
    var non_grow_sum: i64 = 0;
    var grow_min_sum: i64 = 0;
    var has_grow = false;
    // 临时数组均取自栈或调用方给的帧竞技场，不设子项数上限（REQ-ARCH-011）。
    const n_items = items.len;
    var b_stack: [32]i32 = undefined;
    var w_stack: [32]u64 = undefined;
    var s_stack: [32]i32 = undefined;
    var f_stack: [32]bool = undefined;
    var i_stack: [32]i64 = undefined;
    const b: []i32 = if (n_items <= 32) b_stack[0..n_items] else (scratch.alloc(i32, n_items) catch @panic("nano_gui: layout scratch exhausted"));
    for (items, 0..) |it, i| {
        if (it.kind == .grow) {
            has_grow = true;
            b[i] = it.min;
            grow_min_sum += it.min;
        } else {
            b[i] = clamp(it.base, it.min, it.max);
            non_grow_sum += b[i];
        }
        out[i] = b[i];
    }
    const overflow_i: i64 = non_grow_sum + grow_min_sum - avail;
    if (!has_grow and overflow_i <= 0) {
        return .{ .overflow = 0, .leftover = @intCast(@min(@as(i64, std.math.maxInt(i32)), -overflow_i)) };
    }
    const weights: []u64 = if (n_items <= 32) w_stack[0..n_items] else (scratch.alloc(u64, n_items) catch @panic("nano_gui: layout scratch exhausted"));
    const shares: []i32 = if (n_items <= 32) s_stack[0..n_items] else (scratch.alloc(i32, n_items) catch @panic("nano_gui: layout scratch exhausted"));
    const flags: []bool = if (n_items <= 32) f_stack[0..n_items] else (scratch.alloc(bool, n_items) catch @panic("nano_gui: layout scratch exhausted"));
    const ideal: []i64 = if (n_items <= 32) i_stack[0..n_items] else (scratch.alloc(i64, n_items) catch @panic("nano_gui: layout scratch exhausted"));
    if (overflow_i > 0) {
        // grow 一律取 min（已如此），再收缩 fit_shrink。
        var total_slack: i64 = 0;
        for (items, 0..) |it, i| {
            if (it.kind == .shrink) total_slack += @max(0, b[i] - it.min);
        }
        var take: i64 = @min(overflow_i, total_slack);
        const remain_overflow: i32 = @intCast(@max(0, overflow_i - take));
        if (take > 0) {
            var n: usize = 0;
            for (items, 0..) |it, i| {
                if (it.kind == .shrink) {
                    weights[n] = @intCast(@max(0, b[i] - it.min));
                    n += 1;
                }
            }
            const reds = shares;
            @memset(reds, 0);
            apportion(scratch, @intCast(take), weights[0..n], reds[0..n]);
            var k: usize = 0;
            for (items, 0..) |it, i| {
                if (it.kind == .shrink) {
                    const r: i32 = @min(reds[k], b[i] - it.min);
                    out[i] = b[i] - r;
                    take -= r;
                    k += 1;
                }
            }
            // 取整余量继续从仍有 slack 的项扣。
            var j: usize = 0;
            while (take > 0 and j < items.len) : (j += 1) {
                if (items[j].kind == .shrink) {
                    const r: i32 = @min(@as(i32, @intCast(take)), out[j] - items[j].min);
                    out[j] -= r;
                    take -= r;
                }
            }
        }
        return .{ .overflow = remain_overflow, .leftover = 0 };
    }

    // 冻结法分配 grow。零权重 grow 项取其 min，须先从可分配量中扣除。
    var zero_grow_min: i64 = 0;
    const active = flags;
    @memset(active, false);
    for (items, 0..) |it, i| {
        if (it.kind == .grow) {
            if (it.wq == 0) {
                out[i] = it.min;
                zero_grow_min += it.min;
            } else {
                active[i] = true;
            }
        }
    }
    var remaining: i64 = @as(i64, avail) - non_grow_sum - zero_grow_min;
    var guard: usize = 0;
    while (guard <= items.len) : (guard += 1) {
        var wsum: u64 = 0;
        var count: usize = 0;
        for (items, 0..) |it, i| {
            if (active[i]) {
                wsum += it.wq;
                count += 1;
            }
        }
        if (count == 0 or wsum == 0) break;
        var violated = false;
        var vsum: i64 = 0;
        var any_low = false;
        var any_high = false;
        for (items, 0..) |it, i| {
            if (!active[i]) continue;
            ideal[i] = @divTrunc(remaining * @as(i64, it.wq), @as(i64, @intCast(wsum)));
            if (ideal[i] < it.min) {
                violated = true;
                any_low = true;
                vsum += it.min - ideal[i];
            } else if (ideal[i] > it.max) {
                violated = true;
                any_high = true;
                vsum += it.max - ideal[i];
            }
        }
        if (!violated) {
            var n: usize = 0;
            for (items, 0..) |it, i| {
                if (active[i]) {
                    weights[n] = it.wq;
                    n += 1;
                }
            }
            apportion(scratch, @intCast(@max(0, remaining)), weights[0..n], shares[0..n]);
            var k: usize = 0;
            for (items, 0..) |it, i| {
                if (active[i]) {
                    out[i] = clamp(shares[k], it.min, it.max);
                    k += 1;
                }
            }
            break;
        }
        var freeze_low = any_low and (!any_high or vsum >= 0);
        if (vsum < 0) freeze_low = false;
        for (items, 0..) |it, i| {
            if (!active[i]) continue;
            if ((freeze_low and ideal[i] < it.min) or (!freeze_low and ideal[i] > it.max) or (vsum == 0)) {
                const val = if (ideal[i] < it.min) it.min else it.max;
                out[i] = clamp(val, it.min, it.max);
                remaining -= out[i];
                active[i] = false;
            }
        }
    }
    var total: i64 = 0;
    for (out) |v| total += v;
    return .{ .overflow = 0, .leftover = @intCast(@max(0, @as(i64, avail) - total)) };
}

pub fn solveColumns(scratch: std.mem.Allocator, cols: []const Column, header_widths: []const i32, inner_w: i32, definite: bool, gap: i32, scale: f32, out: []i32) void {
    std.debug.assert(out.len == cols.len); // 调用方须提供与列定义等长的输出缓冲
    if (cols.len == 0) return;
    const items = scratch.alloc(FlexItem, cols.len) catch @panic("nano_gui: layout scratch exhausted");
    for (cols, 0..) |c, i| {
        const min = pxValue(c.min, scale);
        const max = if (c.max == std.math.inf(f32)) unbounded else pxValue(c.max, scale);
        switch (c.width) {
            .fixed => |v| items[i] = .{ .kind = .fixed, .base = pxValue(v, scale), .min = min, .max = max, .wq = 0 },
            .grow => |w| items[i] = .{ .kind = .grow, .base = 0, .min = min, .max = max, .wq = quantizeWeight(w) },
            .auto_header => {
                const hw = if (i < header_widths.len) header_widths[i] else 0;
                items[i] = .{ .kind = .fit, .base = hw, .min = min, .max = max, .wq = 0 };
            },
        }
    }
    const gaps: i32 = if (cols.len > 1) gap * @as(i32, @intCast(cols.len - 1)) else 0;
    const avail = if (definite) @max(0, inner_w - gaps) else unbounded;
    _ = distribute(scratch, items, avail, out);
}

fn pxValue(v: f32, scale: f32) i32 {
    if (v == 0) return 0;
    if (v == std.math.inf(f32)) return unbounded;
    return @max(1, @as(i32, @intFromFloat(@round(v * scale))));
}

/// 锚定/弹出层摆放（REQ-LAYOUT-043），纯函数。
pub fn placeAnchored(anchor: core.RectI, size_in: SizeI, placement: Placement, gap: i32, bounds: core.RectI) PlaceResult {
    var w: i32 = @max(0, size_in.w);
    var h: i32 = @max(0, size_in.h);
    w = @min(w, bounds.w);
    var height_limited = false;
    if (h > bounds.h) {
        h = bounds.h;
        height_limited = true;
    }
    var x: i32 = 0;
    var y: i32 = 0;
    const TryPlace = struct {
        fn pos(a: core.RectI, sz: SizeI, s: Side, al: Align, g: i32) struct { x: i32, y: i32 } {
            var px_: i32 = 0;
            var py_: i32 = 0;
            switch (s) {
                .below => {
                    py_ = a.bottom() + g;
                    px_ = switch (al) {
                        .start => a.x,
                        .center => a.x + @divFloor(a.w - sz.w, 2),
                        .end => a.right() - sz.w,
                    };
                },
                .above => {
                    py_ = a.y - g - sz.h;
                    px_ = switch (al) {
                        .start => a.x,
                        .center => a.x + @divFloor(a.w - sz.w, 2),
                        .end => a.right() - sz.w,
                    };
                },
                .right => {
                    px_ = a.right() + g;
                    py_ = switch (al) {
                        .start => a.y,
                        .center => a.y + @divFloor(a.h - sz.h, 2),
                        .end => a.bottom() - sz.h,
                    };
                },
                .left => {
                    px_ = a.x - g - sz.w;
                    py_ = switch (al) {
                        .start => a.y,
                        .center => a.y + @divFloor(a.h - sz.h, 2),
                        .end => a.bottom() - sz.h,
                    };
                },
            }
            return .{ .x = px_, .y = py_ };
        }
        fn fits(a: core.RectI, sz: SizeI, s: Side, al: Align, g: i32, b: core.RectI) bool {
            const p = pos(a, sz, s, al, g);
            return switch (s) {
                .below, .above => p.y >= b.y and p.y + sz.h <= b.bottom(),
                .right, .left => p.x >= b.x and p.x + sz.w <= b.right(),
            };
        }
    };
    const flip: Side = switch (placement.side) {
        .below => .above,
        .above => .below,
        .right => .left,
        .left => .right,
    };
    var chosen = placement.side;
    if (!TryPlace.fits(anchor, .{ .w = w, .h = h }, placement.side, placement.align_, gap, bounds)) {
        if (TryPlace.fits(anchor, .{ .w = w, .h = h }, flip, placement.align_, gap, bounds)) {
            chosen = flip;
        } else {
            const below_space = bounds.bottom() - anchor.bottom() - gap;
            const above_space = anchor.y - bounds.y - gap;
            const right_space = bounds.right() - anchor.right() - gap;
            const left_space = anchor.x - bounds.x - gap;
            chosen = switch (placement.side) {
                .below, .above => if (below_space >= above_space) .below else .above,
                .right, .left => if (right_space >= left_space) .right else .left,
            };
        }
    }
    const p = TryPlace.pos(anchor, .{ .w = w, .h = h }, chosen, placement.align_, gap);
    x = p.x;
    y = p.y;
    var clamped = false;
    // 交叉轴翻转：below/above 横向越界时改为右缘对齐锚点（REQ-LAYOUT-043）。
    if (placement.flip_cross and (chosen == .below or chosen == .above)) {
        const cx = anchor.right() - w;
        if ((x < bounds.x or x + w > bounds.right()) and cx >= bounds.x and cx + w <= bounds.right()) x = cx;
    }
    switch (chosen) {
        .below, .above => {
            const nx = std.math.clamp(x, bounds.x, @max(bounds.x, bounds.right() - w));
            if (nx != x) clamped = true;
            x = nx;
            const ny = std.math.clamp(y, bounds.y, @max(bounds.y, bounds.bottom() - h));
            if (ny != y) clamped = true;
            y = ny;
        },
        .right, .left => {
            const ny = std.math.clamp(y, bounds.y, @max(bounds.y, bounds.bottom() - h));
            if (ny != y) clamped = true;
            y = ny;
            const nx = std.math.clamp(x, bounds.x, @max(bounds.x, bounds.right() - w));
            if (nx != x) clamped = true;
            x = nx;
        },
    }
    return .{ .rect = .{ .x = x, .y = y, .w = w, .h = h }, .side_used = chosen, .clamped = clamped, .height_limited = height_limited };
}

test "apportion and distribute basics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var out: [3]i32 = undefined;
    apportion(arena.allocator(), 300, &.{ 1024, 1024, 1024 }, &out);
    try std.testing.expectEqualSlices(i32, &.{ 100, 100, 100 }, &out);

    var items = [3]FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = unbounded, .wq = 1024 },
    };
    var res: [3]i32 = undefined;
    var r = distribute(arena.allocator(), &items, 300, &res);
    try std.testing.expectEqualSlices(i32, &.{ 100, 100, 100 }, &res);
    try std.testing.expectEqual(@as(i32, 0), r.overflow);

    r = distribute(arena.allocator(), &items, 301, &res);
    try std.testing.expectEqualSlices(i32, &.{ 101, 100, 100 }, &res);

    items[0].max = 50;
    r = distribute(arena.allocator(), &items, 300, &res);
    try std.testing.expectEqualSlices(i32, &.{ 50, 125, 125 }, &res);
}

test "distribute shrink" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var items = [3]FlexItem{
        .{ .kind = .shrink, .base = 200, .min = 80, .max = unbounded, .wq = 0 },
        .{ .kind = .shrink, .base = 150, .min = 50, .max = unbounded, .wq = 0 },
        .{ .kind = .fixed, .base = 100, .min = 0, .max = unbounded, .wq = 0 },
    };
    var res: [3]i32 = undefined;
    const r = distribute(arena.allocator(), &items, 300, &res);
    try std.testing.expectEqualSlices(i32, &.{ 118, 82, 100 }, &res);
    try std.testing.expectEqual(@as(i32, 0), r.overflow);
}

test "place anchored flips" {
    const anchor = core.RectI{ .x = 100, .y = 900, .w = 40, .h = 20 };
    const bounds = core.RectI{ .x = 0, .y = 0, .w = 200, .h = 1000 };
    const r = placeAnchored(anchor, .{ .w = 100, .h = 200 }, .{ .side = .below }, 0, bounds);
    try std.testing.expectEqual(Side.above, r.side_used);
    try std.testing.expectEqual(@as(i32, 700), r.rect.y);
}
