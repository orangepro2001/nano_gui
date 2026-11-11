//! 布局：尺寸策略、整数求解、专用容器参数与纯函数求解器（07）。
//! 节点树上的测量/排布由 ui 模块驱动，本模块只提供不依赖 ui 的算法。

const std = @import("std");
const core = @import("core.zig");
const theme = @import("theme.zig");

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
    anchor_end: bool = false,
    reveal: ?core.Rect = null,
};

pub const ScrollMetrics = struct {
    offset: core.Vec2,
    offset_px: struct { x: i32, y: i32 },
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
pub const Placement = struct { side: Side = .below, align_: Align = .start };
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
    pub fn childCount(self: *const MeasureCtx) usize {
        _ = self;
        return 0;
    }
    pub fn childParams(self: *const MeasureCtx, index: usize) *const Params {
        _ = self;
        _ = index;
        return undefined;
    }
    pub fn measureChild(self: *MeasureCtx, index: usize, limit: Limit) SizeI {
        _ = self;
        _ = index;
        _ = limit;
        return .{};
    }
    pub fn px(self: *const MeasureCtx, lpx: f32) i32 {
        if (lpx == 0) return 0;
        return @max(1, @as(i32, @intFromFloat(@round(lpx * self.scale))));
    }
};

pub const ArrangeCtx = struct {
    scale: f32,
    pub fn childCount(self: *const ArrangeCtx) usize {
        _ = self;
        return 0;
    }
    pub fn childParams(self: *const ArrangeCtx, index: usize) *const Params {
        _ = self;
        _ = index;
        return undefined;
    }
    pub fn measureChild(self: *ArrangeCtx, index: usize, limit: Limit) SizeI {
        _ = self;
        _ = index;
        _ = limit;
        return .{};
    }
    pub fn placeChild(self: *ArrangeCtx, index: usize, rect: core.RectI) void {
        _ = self;
        _ = index;
        _ = rect;
    }
    pub fn px(self: *const ArrangeCtx, lpx: f32) i32 {
        if (lpx == 0) return 0;
        return @max(1, @as(i32, @intFromFloat(@round(lpx * self.scale))));
    }
};

pub const Params = struct {
    kind: Kind = .leaf,
    main: Extent = .fit,
    cross: CrossExtent = .fit,
    main_min: f32 = 0,
    main_max: f32 = std.math.inf(f32),
    cross_min: f32 = 0,
    cross_max: f32 = std.math.inf(f32),
    padding: core.Insets = .{},
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
    if (!(weight > 0)) return 0;
    const q = @round(weight * 1024.0);
    if (q < 1) return 1;
    if (q > 4_000_000_000.0) return 4_000_000_000;
    return @intFromFloat(q);
}

/// 最大余数法（REQ-LAYOUT-015）。
pub fn apportion(total: i32, weights: []const u64, out: []i32) void {
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
    var used: [128]bool = @splat(false);
    while (remainder > 0) {
        var best: ?usize = null;
        var best_rem: u64 = 0;
        for (weights, 0..) |w, i| {
            if (i >= out.len or i >= used.len) break;
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
pub fn distribute(items: []const FlexItem, avail: i32, out: []i32) DistributeResult {
    std.debug.assert(out.len == items.len);
    if (items.len == 0) return .{ .overflow = 0, .leftover = @max(0, avail) };
    var non_grow_sum: i64 = 0;
    var grow_min_sum: i64 = 0;
    var b: [128]i32 = undefined;
    for (items, 0..) |it, i| {
        if (i >= b.len) break;
        if (it.kind == .grow) {
            b[i] = it.min;
            grow_min_sum += it.min;
        } else {
            b[i] = clamp(it.base, it.min, it.max);
            non_grow_sum += b[i];
        }
    }
    for (items, 0..) |_, i| {
        if (i >= b.len) break;
        out[i] = b[i];
    }
    const overflow_i: i64 = non_grow_sum + grow_min_sum - avail;
    if (overflow_i > 0) {
        // grow 一律取 min（已如此），再收缩 fit_shrink。
        var total_slack: i64 = 0;
        for (items, 0..) |it, i| {
            if (i >= b.len) break;
            if (it.kind == .shrink) total_slack += @max(0, b[i] - it.min);
        }
        var take: i64 = @min(overflow_i, total_slack);
        const remain_overflow: i32 = @intCast(@max(0, overflow_i - take));
        if (take > 0) {
            var weights: [128]u64 = undefined;
            var red: [128]i32 = undefined;
            var n: usize = 0;
            for (items, 0..) |it, i| {
                if (i >= b.len) break;
                if (it.kind == .shrink) {
                    weights[n] = @intCast(@max(0, b[i] - it.min));
                    red[0] = 0;
                    n += 1;
                }
            }
            var reds: [128]i32 = @splat(0);
            apportion(@intCast(take), weights[0..n], reds[0..n]);
            var k: usize = 0;
            for (items, 0..) |it, i| {
                if (i >= b.len) break;
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

    // 冻结法分配 grow。
    var remaining: i64 = @as(i64, avail) - non_grow_sum;
    var active: [128]bool = @splat(false);
    for (items, 0..) |it, i| {
        if (i >= b.len) break;
        if (it.kind == .grow) {
            if (it.wq == 0) {
                out[i] = it.min;
            } else {
                active[i] = true;
            }
        }
    }
    var guard: usize = 0;
    while (guard <= items.len) : (guard += 1) {
        var wsum: u64 = 0;
        var count: usize = 0;
        for (items, 0..) |it, i| {
            if (i >= b.len) break;
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
        var ideal: [128]i64 = undefined;
        for (items, 0..) |it, i| {
            if (i >= b.len) break;
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
            var weights: [128]u64 = undefined;
            var shares: [128]i32 = undefined;
            var n: usize = 0;
            for (items, 0..) |it, i| {
                if (i >= b.len) break;
                if (active[i]) {
                    weights[n] = it.wq;
                    n += 1;
                }
            }
            apportion(@intCast(@max(0, remaining)), weights[0..n], shares[0..n]);
            var k: usize = 0;
            for (items, 0..) |it, i| {
                if (i >= b.len) break;
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
            if (i >= b.len) break;
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

pub fn solveColumns(cols: []const Column, header_widths: []const i32, inner_w: i32, definite: bool, gap: i32, scale: f32, out: []i32) void {
    std.debug.assert(out.len == cols.len);
    if (cols.len == 0) return;
    var items: [64]FlexItem = undefined;
    for (cols, 0..) |c, i| {
        if (i >= items.len) break;
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
    var res: [64]i32 = undefined;
    _ = distribute(items[0..cols.len], avail, res[0..cols.len]);
    for (res[0..cols.len], 0..) |v, i| {
        if (i < out.len) out[i] = v;
    }
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
    const tryPlace = struct {
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
    if (!tryPlace.fits(anchor, .{ .w = w, .h = h }, placement.side, placement.align_, gap, bounds)) {
        if (tryPlace.fits(anchor, .{ .w = w, .h = h }, flip, placement.align_, gap, bounds)) {
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
    const p = tryPlace.pos(anchor, .{ .w = w, .h = h }, chosen, placement.align_, gap);
    x = p.x;
    y = p.y;
    var clamped = false;
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
    var out: [3]i32 = undefined;
    apportion(300, &.{ 1024, 1024, 1024 }, &out);
    try std.testing.expectEqualSlices(i32, &.{ 100, 100, 100 }, &out);

    var items = [3]FlexItem{
        .{ .kind = .grow, .base = 0, .min = 0, .max = unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = unbounded, .wq = 1024 },
        .{ .kind = .grow, .base = 0, .min = 0, .max = unbounded, .wq = 1024 },
    };
    var res: [3]i32 = undefined;
    var r = distribute(&items, 300, &res);
    try std.testing.expectEqualSlices(i32, &.{ 100, 100, 100 }, &res);
    try std.testing.expectEqual(@as(i32, 0), r.overflow);

    r = distribute(&items, 301, &res);
    try std.testing.expectEqualSlices(i32, &.{ 101, 100, 100 }, &res);

    items[0].max = 50;
    r = distribute(&items, 300, &res);
    try std.testing.expectEqualSlices(i32, &.{ 50, 125, 125 }, &res);
}

test "distribute shrink" {
    var items = [3]FlexItem{
        .{ .kind = .shrink, .base = 200, .min = 80, .max = unbounded, .wq = 0 },
        .{ .kind = .shrink, .base = 150, .min = 50, .max = unbounded, .wq = 0 },
        .{ .kind = .fixed, .base = 100, .min = 0, .max = unbounded, .wq = 0 },
    };
    var res: [3]i32 = undefined;
    const r = distribute(&items, 300, &res);
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
