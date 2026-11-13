//! 文字：样式、度量、排版、绘制与编辑位置运算。
//!
//! 本仓库的默认后端是 `fixed`：度量完全由 REQ-TEXT-038 的公式决定，不读取任何系统
//! 字体，因此单元测试、回放与金图在不同机器上逐字节一致。Windows 上同一接口由
//! DirectWrite 后端实现（ADR 0003），接口不变。

const std = @import("std");
const core = @import("core.zig");
const gfx = @import("gfx.zig");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const build_options = @import("build_options");
const fons_backend = @import("text/fontstash.zig");

const enable_fontstash = std.mem.eql(u8, build_options.text_backend, "fontstash");

var backend_allocator: ?std.mem.Allocator = null;
var use_directwrite: bool = false;

pub fn setDirectWrite(enabled: bool) void {
    if (comptime builtin.os.tag != .windows) {
        use_directwrite = false;
        return;
    }
    use_directwrite = enabled;
    if (enabled) _ = directwrite.ensureFactory();
}

// 排版缓存（REQ-TEXT-013/014）：按键哈希索引，LRU 淘汰；
// 条目记录最后触达的构建代，淘汰只选 last_gen < 当前代 - 1 的条目。
/// 仅供测试：强制所有键得到相同哈希，以验证碰撞时按原文比对。
pub var test_hash_override: ?u64 = null;

const CacheKey = struct {
    style: Style,
    max_width_ppx: i32,
    has_max_width: bool,
    wrap: Wrap,
    ellipsis: Ellipsis,
    max_lines: u32,
    newlines: Newlines,
    tab_width: u8,
    line_height_ppx: i32,
    has_line_height: bool,
    @"align": Align,
    scale_milli: i32,

    fn make(style: Style, scale: f32, opts: LayoutOptions) CacheKey {
        return .{
            .style = style,
            .max_width_ppx = if (opts.max_width) |w| @intFromFloat(@round(w * scale)) else 0,
            .has_max_width = opts.max_width != null,
            .wrap = opts.wrap,
            .ellipsis = opts.ellipsis,
            .max_lines = opts.max_lines orelse 0,
            .newlines = opts.newlines,
            .tab_width = opts.tab_width,
            .line_height_ppx = if (opts.line_height) |h| @intFromFloat(@round(h * scale)) else 0,
            .has_line_height = opts.line_height != null,
            .@"align" = opts.@"align",
            .scale_milli = @intFromFloat(@round(scale * 1000)),
        };
    }

    fn eql(a: CacheKey, b: CacheKey) bool {
        return a.style.family == b.style.family and a.style.size == b.style.size and
            a.style.weight == b.style.weight and a.style.italic == b.style.italic and
            a.max_width_ppx == b.max_width_ppx and a.has_max_width == b.has_max_width and
            a.wrap == b.wrap and a.ellipsis == b.ellipsis and a.max_lines == b.max_lines and
            a.newlines == b.newlines and a.tab_width == b.tab_width and
            a.line_height_ppx == b.line_height_ppx and a.has_line_height == b.has_line_height and
            a.@"align" == b.@"align" and a.scale_milli == b.scale_milli;
    }

    fn hash(k: CacheKey, text: []const u8) u64 {
        if (test_hash_override) |o| return o;
        var h = std.hash.Wyhash.init(0);
        h.update(text);
        h.update(std.mem.asBytes(&@backingInt(k.style.family)));
        h.update(std.mem.asBytes(&k.style.size));
        h.update(std.mem.asBytes(&k.style.weight));
        h.update(std.mem.asBytes(&k.style.italic));
        h.update(std.mem.asBytes(&k.max_width_ppx));
        h.update(std.mem.asBytes(&k.has_max_width));
        h.update(std.mem.asBytes(&@backingInt(k.wrap)));
        h.update(std.mem.asBytes(&@backingInt(k.ellipsis)));
        h.update(std.mem.asBytes(&k.max_lines));
        h.update(std.mem.asBytes(&@backingInt(k.newlines)));
        h.update(std.mem.asBytes(&k.tab_width));
        h.update(std.mem.asBytes(&k.line_height_ppx));
        h.update(std.mem.asBytes(&k.has_line_height));
        h.update(std.mem.asBytes(&@backingInt(k.@"align")));
        h.update(std.mem.asBytes(&k.scale_milli));
        return h.final();
    }
};

const CacheEntry = struct {
    key: CacheKey,
    hash: u64,
    src_text: []u8, // 原文完整副本（命中时逐字节比对）
    layout: *Layout,
    bytes: usize,
    last_gen: u64,
    chain: ?*CacheEntry = null, // 同哈希链
    prev: ?*CacheEntry = null, // LRU 链：head 最新，tail 最旧
    next: ?*CacheEntry = null,
};

var cache_map: std.AutoHashMapUnmanaged(u64, *CacheEntry) = .empty;
var cache_head: ?*CacheEntry = null;
var cache_tail: ?*CacheEntry = null;
var cache_entries: usize = 0;
var cache_bytes: usize = 0;
var cache_gen: u64 = 1;
var cache_max_entries: usize = 4096;
var cache_max_bytes: usize = 8 * 1024 * 1024;

fn lruUnlink(e: *CacheEntry) void {
    if (e.prev) |p| p.next = e.next else cache_head = e.next;
    if (e.next) |n| n.prev = e.prev else cache_tail = e.prev;
    e.prev = null;
    e.next = null;
}

fn lruPushFront(e: *CacheEntry) void {
    e.prev = null;
    e.next = cache_head;
    if (cache_head) |h| h.prev = e;
    cache_head = e;
    if (cache_tail == null) cache_tail = e;
}

/// 排版缓存当前占用（与埋点 cache.text_layout.entries/bytes 同源）。
/// 编程错误断言（REQ-CONV-013）：使用排版接口前必须先调用 text.init（REQ-ARCH-011）。
/// 不用 assert 后接 `.?`：发布构建中 assert 被移除，`.?` 会变成未定义行为。
fn requireInit(src: std.builtin.SourceLocation) std.mem.Allocator {
    if (backend_allocator) |a| return a;
    std.debug.panic("nano_gui: 违反 REQ-ARCH-011：调用 text 接口前未调用 text.init（调用点 {s}:{d}）", .{ src.file, src.line });
}

/// 内存耗尽属于不可恢复的环境错误（REQ-ARCH-017、REQ-ARCH-018），经 platform.fatal 退出。
fn outOfMemory() noreturn {
    platform.fatal("nano_gui", "文字排版缓存分配失败：内存耗尽");
}

pub fn cacheStats() struct { entries: usize, bytes: usize } {
    return .{ .entries = cache_entries, .bytes = cache_bytes };
}

fn cacheReport() void {
    core.stats.gauge("cache.text_layout.entries").* = cache_entries;
    core.stats.gauge("cache.text_layout.bytes").* = cache_bytes;
}

fn cacheRemove(e: *CacheEntry) void {
    lruUnlink(e);
    // 从哈希链摘除。
    if (cache_map.get(e.hash)) |head| {
        if (head == e) {
            if (e.chain) |c| cache_map.putAssumeCapacity(e.hash, c) else _ = cache_map.remove(e.hash);
        } else {
            var cur = head;
            while (cur.chain) |n| : (cur = n) {
                if (n == e) {
                    cur.chain = e.chain;
                    break;
                }
            }
        }
    }
    cache_entries -= 1;
    cache_bytes -= e.bytes;
    const alloc = e.layout.allocator;
    alloc.free(e.src_text);
    e.layout.deinit();
    alloc.destroy(e);
}

/// 淘汰超限条目；只淘汰最后触达代 < 当前代 - 1 的条目（REQ-TEXT-014）。
fn cacheEvict() void {
    while (cache_entries > cache_max_entries or cache_bytes > cache_max_bytes) {
        const t = cache_tail orelse return;
        if (t.last_gen + 1 >= cache_gen) return; // 最旧的都受保护：允许暂时超限
        cacheRemove(t);
    }
}

fn cacheClear() void {
    while (cache_tail) |t| cacheRemove(t);
    if (backend_allocator) |a| cache_map.deinit(a);
    cache_map = .empty;
    cacheReport();
}

pub const backend_name: []const u8 = build_options.text_backend;
pub const directwrite = @import("text/directwrite.zig");

pub const Family = enum(u16) { ui, mono, _ };

var custom_families: std.ArrayListUnmanaged([]u8) = .empty;
var atlas_pages: u32 = 0;
var atlas_rgba_pages: u32 = 0;
var atlas_used_ppx: u64 = 0;
var atlas_raster_count: u64 = 0;
var atlas_shape_count: u64 = 0;

/// 注册自定义字体族名（框架复制名称；REQ-TEXT-001）。线程：界面线程。
pub fn registerFamily(name: []const u8) error{OutOfMemory}!Family {
    const alloc = backend_allocator orelse std.heap.smp_allocator;
    for (custom_families.items, 0..) |existing, i| {
        if (std.mem.eql(u8, existing, name)) return @fromBackingInt(@intCast(@as(u16, @intCast(i + 2))));
    }
    const copy = try alloc.dupe(u8, name);
    errdefer alloc.free(copy);
    try custom_families.append(alloc, copy);
    return @fromBackingInt(@intCast(@as(u16, @intCast(custom_families.items.len + 1))));
}

/// 解析字体族对应的系统字体族名（REQ-TEXT-001）。线程：界面线程。
pub fn resolvedFamily(f: Family) []const u8 {
    return switch (f) {
        .ui => "Segoe UI",
        .mono => "Cascadia Mono",
        _ => {
            const idx = @backingInt(f);
            if (idx >= 2 and idx - 2 < custom_families.items.len) {
                return custom_families.items[idx - 2];
            }
            return "Segoe UI";
        },
    };
}

pub const Style = struct {
    family: Family = .ui,
    size: f32 = 12,
    weight: u16 = 400,
    italic: bool = false,
};

pub const Wrap = enum { none, word, anywhere };
pub const Align = enum { left, center, right };
pub const Ellipsis = enum { none, end };
pub const Newlines = enum { break_lines, as_space };

pub const LayoutOptions = struct {
    max_width: ?f32 = null,
    wrap: Wrap = .none,
    @"align": Align = .left,
    ellipsis: Ellipsis = .none,
    max_lines: ?u32 = null,
    newlines: Newlines = .break_lines,
    tab_width: u8 = 4,
    line_height: ?f32 = null,
};

pub const FontMetrics = struct { ascent: f32, descent: f32, line_gap: f32, height: f32 };

pub const Caret = struct { offset: u32, affinity: Affinity = .downstream };
pub const Affinity = enum { upstream, downstream };
pub const Range = struct { start: u32, end: u32 };
pub const CaretRect = struct { x: f32, y: f32, h: f32 };
pub const Edge = enum { leading, trailing };

pub const HitResult = struct {
    caret: Caret,
    cluster_start: u32,
    edge: Edge,
    line: u32,
    inside: bool,
};

pub const SelectionOpts = struct { extend_line_breaks: bool = false };

pub const Line = struct {
    start: u32,
    end: u32,
    width: f32,
    y: f32,
};

pub const Layout = struct {
    text: []const u8,
    style: Style,
    scale: f32,
    size: core.Size,
    truncated: bool,
    text_len: u32,
    opts: LayoutOptions,
    lines_buf: []Line,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Layout) void {
        self.allocator.free(self.lines_buf);
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    pub fn lineCount(self: *const Layout) u32 {
        return @intCast(self.lines_buf.len);
    }

    pub fn lineOf(self: *const Layout, c: Caret) u32 {
        for (self.lines_buf, 0..) |line, i| {
            if (c.offset <= line.end) return @intCast(i);
        }
        return @intCast(self.lines_buf.len - 1);
    }

    pub fn lineRange(self: *const Layout, line: u32) Range {
        const i = @min(line, self.lines_buf.len - 1);
        return .{ .start = self.lines_buf[i].start, .end = self.lines_buf[i].end };
    }

    pub fn lineRect(self: *const Layout, line: u32) core.Rect {
        const i = @min(line, self.lines_buf.len - 1);
        return .{ .x = 0, .y = self.lines_buf[i].y, .w = self.size.w, .h = lineHeight(self.style, self.opts, self.scale) };
    }

    pub fn lineStart(self: *const Layout, c: Caret) Caret {
        return .{ .offset = self.lines_buf[self.lineOf(c)].start };
    }

    pub fn lineEnd(self: *const Layout, c: Caret) Caret {
        return .{ .offset = self.lines_buf[self.lineOf(c)].end };
    }

    pub fn hitTest(self: *const Layout, point: core.Vec2) HitResult {
        var li: u32 = 0;
        if (self.lines_buf.len > 1) {
            li = @intFromFloat(std.math.clamp(@floor(point.y / lineHeight(self.style, self.opts, self.scale)), 0, @as(f32, @floatFromInt(self.lines_buf.len - 1))));
        }
        const line = self.lines_buf[li];
        const adv = advance(self.style, self.scale);
        // rel 为相对本行文字起点的 x（已减去对齐偏移）。
        const rel = point.x - self.alignOffset(line.width);
        var offset = line.start;
        var edge: Edge = .leading;
        var cluster_start = line.start;
        var x: f32 = 0;
        var cur = line.start;
        while (cur < line.end) {
            const next: u32 = @intCast(nextGrapheme(self.text, cur));
            const w = adv * @as(f32, @floatFromInt(core.codepointCount(self.text[cur..next])));
            cluster_start = cur;
            // 前半取起始边界（leading）；中点及之后取末尾边界（trailing）。
            if (rel < x + w * 0.5) {
                offset = cur;
                edge = .leading;
                break;
            }
            offset = next;
            edge = .trailing;
            if (rel < x + w) break;
            x += w;
            cur = next;
        }
        // 软换行处：行末 trailing 边界得 upstream。
        var affinity: Affinity = .downstream;
        if (edge == .trailing and offset == line.end and li + 1 < self.lines_buf.len and self.lines_buf[li + 1].start == offset) {
            affinity = .upstream;
        }
        return .{
            .caret = .{ .offset = @min(offset, self.text_len), .affinity = affinity },
            .cluster_start = cluster_start,
            .edge = edge,
            .line = li,
            .inside = point.x >= 0 and point.y >= 0 and point.x <= self.size.w and point.y <= self.size.h,
        };
    }

    pub fn caretRect(self: *const Layout, c: Caret) CaretRect {
        const li = self.lineOf(c);
        const line = self.lines_buf[li];
        const adv = advance(self.style, self.scale);
        var x: f32 = 0;
        var offset = line.start;
        while (offset < c.offset and offset < line.end) {
            const next = nextGrapheme(self.text, offset);
            x += adv * @as(f32, @floatFromInt(core.codepointCount(self.text[offset..next])));
            offset = next;
        }
        return .{
            .x = self.alignOffset(line.width) + x,
            .y = line.y,
            .h = lineHeight(self.style, self.opts, self.scale),
        };
    }

    pub fn selectionRects(self: *const Layout, start: u32, end: u32, opts: SelectionOpts, out: *std.ArrayListUnmanaged(core.Rect)) void {
        _ = opts;
        if (start >= end) return;
        const a = self.caretRect(.{ .offset = start });
        const b = self.caretRect(.{ .offset = end });
        if (self.lineOf(.{ .offset = start }) == self.lineOf(.{ .offset = end })) {
            out.append(self.allocator, .{ .x = a.x, .y = a.y, .w = b.x - a.x, .h = a.h }) catch {};
        } else {
            const adv = advance(self.style, self.scale);
            out.append(self.allocator, .{ .x = a.x, .y = a.y, .w = @max(adv, self.size.w - a.x), .h = a.h }) catch {};
            out.append(self.allocator, .{ .x = 0, .y = b.y, .w = b.x, .h = b.h }) catch {};
        }
    }

    pub fn moveHorizontal(self: *const Layout, c: Caret, dir: anytype) Caret {
        if (dir == .left) {
            if (c.offset == 0) return c;
            return .{ .offset = @intCast(prevGrapheme(self.text, c.offset)) };
        }
        if (c.offset >= self.text_len) return c;
        return .{ .offset = @intCast(nextGrapheme(self.text, c.offset)) };
    }

    pub fn moveVertical(self: *const Layout, c: Caret, dir: anytype, goal_x: ?f32) struct { caret: Caret, goal_x: f32 } {
        const li = self.lineOf(c);
        const cur = self.caretRect(c);
        const gx = goal_x orelse cur.x;
        var target: u32 = li;
        if (dir == .up and li > 0) target = li - 1;
        if (dir == .down and li + 1 < self.lines_buf.len) target = li + 1;
        const line = self.lines_buf[target];
        const adv = advance(self.style, self.scale);
        var offset = line.start;
        var x: f32 = 0;
        var best: u32 = line.start;
        var best_d: f32 = 1e30;
        while (offset <= line.end) {
            const d = @abs(x - gx + self.alignOffset(line.width));
            if (d < best_d) {
                best_d = d;
                best = offset;
            }
            if (offset >= line.end) break;
            const next = nextGrapheme(self.text, offset);
            x += adv * @as(f32, @floatFromInt(core.codepointCount(self.text[offset..next])));
            offset = next;
        }
        return .{ .caret = .{ .offset = best }, .goal_x = gx };
    }

    pub fn imeRects(self: *const Layout, comp: Composition) struct { caret: CaretRect, target: ?core.Rect } {
        const r = self.caretRect(.{ .offset = @min(comp.start + comp.cursor, self.text_len) });
        var target: ?core.Rect = null;
        for (comp.segments) |seg| {
            if (seg.style == .target_converted or seg.style == .target_unconverted) {
                const s = @min(comp.start + seg.start, self.text_len);
                const e = @min(comp.start + seg.end, self.text_len);
                if (e > s) {
                    const a = self.caretRect(.{ .offset = s });
                    const b = self.caretRect(.{ .offset = e });
                    target = .{ .x = a.x, .y = a.y, .w = @max(1.0, b.x - a.x), .h = a.h };
                    break;
                }
            }
        }
        return .{ .caret = r, .target = target };
    }

    fn alignOffset(self: *const Layout, line_w: f32) f32 {
        // REQ-TEXT-017：max_width 为空时 x_offset = 0。
        if (self.opts.max_width == null) return 0;
        return switch (self.opts.@"align") {
            .left => 0,
            .center => @floor((self.size.w - line_w) * 0.5),
            .right => self.size.w - line_w,
        };
    }
};

pub const OwnedLayout = struct {
    layout: *Layout,
    pub fn deinit(self: *OwnedLayout) void {
        self.layout.deinit();
    }
};

/// 返回缓存中的排版结果（REQ-TEXT-013）。指针自获取起至下下次构建完成前有效（REQ-TEXT-014）。
pub fn layout(text: []const u8, style: Style, scale: f32, opts: LayoutOptions) *const Layout {
    const key = CacheKey.make(style, scale, opts);
    const h = key.hash(text);
    var cur = cache_map.get(h);
    while (cur) |e| : (cur = e.chain) {
        if (e.key.eql(key) and std.mem.eql(u8, e.src_text, text)) {
            e.last_gen = cache_gen;
            lruUnlink(e);
            lruPushFront(e);
            core.stats.counter("cache.text_layout.hits").* += 1;
            return e.layout;
        }
    }
    core.stats.counter("cache.text_layout.misses").* += 1;
    const alloc = requireInit(@src());
    const owned = layoutOwned(alloc, text, style, scale, opts) catch outOfMemory();
    const entry = alloc.create(CacheEntry) catch outOfMemory();
    const copy = alloc.dupe(u8, text) catch outOfMemory();
    const l = owned.layout;
    entry.* = .{
        .key = key,
        .hash = h,
        .src_text = copy,
        .layout = l,
        .bytes = @sizeOf(CacheEntry) + @sizeOf(Layout) + copy.len + l.text.len + l.lines_buf.len * @sizeOf(Line),
        .last_gen = cache_gen,
    };
    const gop = cache_map.getOrPut(alloc, h) catch outOfMemory();
    entry.chain = if (gop.found_existing) gop.value_ptr.* else null;
    gop.value_ptr.* = entry;
    lruPushFront(entry);
    cache_entries += 1;
    cache_bytes += entry.bytes;
    cacheReport();
    return l;
}

pub fn layoutOwned(allocator: std.mem.Allocator, text_in: []const u8, style: Style, scale: f32, opts: LayoutOptions) error{OutOfMemory}!OwnedLayout {
    const effective = opts;
    if (effective.newlines == .as_space) {
        // 单行控件：换行与制表符按空格处理。
    }
    var normalized = std.ArrayListUnmanaged(u8).empty;
    for (text_in) |c| {
        if ((c == '\n' or c == '\t') and effective.newlines == .as_space) {
            try normalized.append(allocator, ' ');
        } else {
            try normalized.append(allocator, c);
        }
    }
    const text = try normalized.toOwnedSlice(allocator);
    errdefer allocator.free(text);

    const lh = lineHeight(style, effective, scale);
    const adv = advance(style, scale);
    var lines = std.ArrayListUnmanaged(Line).empty;
    errdefer lines.deinit(allocator);

    var line_start: u32 = 0;
    var line_index: u32 = 0;
    var max_w: f32 = 0;
    var i: u32 = 0;
    var truncated = false;
    while (i <= text.len) : (i += 1) {
        const at_end = i == text.len;
        const at_nl = !at_end and text[i] == '\n';
        if (!at_end and !at_nl) continue;
        var end = i;
        var line_w = advanceOf(text[line_start..end], style, scale);
        if (effective.max_width) |mw| {
            if (line_w > mw and effective.ellipsis == .end) {
                truncated = true;
                var cut = end;
                while (cut > line_start and advanceOf(text[line_start..cut], style, scale) + adv > mw) {
                    cut = @intCast(prevGrapheme(text, cut));
                }
                end = cut;
                line_w = advanceOf(text[line_start..end], style, scale) + adv;
            }
        }
        const y = @as(f32, @floatFromInt(line_index)) * lh;
        lines.append(allocator, .{
            .start = line_start,
            .end = end,
            .width = line_w,
            .y = y,
        }) catch |e| {
            lines.deinit(allocator);
            return e;
        };
        max_w = @max(max_w, line_w);
        line_index += 1;
        if (at_end) break;
        line_start = i + 1;
        if (effective.max_lines) |ml| {
            if (line_index >= ml) break;
        }
    }
    if (lines.items.len == 0) {
        lines.append(allocator, .{ .start = 0, .end = 0, .width = 0, .y = 0 }) catch |e| {
            lines.deinit(allocator);
            return e;
        };
    }
    const layout_ptr = try allocator.create(Layout);
    layout_ptr.* = .{
        .text = text,
        .style = style,
        .scale = scale,
        .size = .{ .w = max_w, .h = @as(f32, @floatFromInt(lines.items.len)) * lh },
        .truncated = truncated,
        .text_len = @intCast(text.len),
        .opts = effective,
        .lines_buf = try lines.toOwnedSlice(allocator),
        .allocator = allocator,
    };
    atlas_shape_count += 1;
    return .{ .layout = layout_ptr };
}

pub fn measure(text_in: []const u8, style: Style, scale: f32, opts: LayoutOptions) core.Size {
    var effective = opts;
    effective.max_width = null;
    if (!isInitialized()) {
        const l = layoutOwned(std.heap.smp_allocator, text_in, style, scale, effective) catch return .{};
        defer l.layout.deinit();
        return l.layout.size;
    }
    return layout(text_in, style, scale, effective).size;
}

pub fn isTruncated(text: []const u8, style: Style, scale: f32, max_width: f32) bool {
    return measure(text, style, scale, .{}).w > max_width;
}

pub fn fontMetrics(style: Style, scale: f32) FontMetrics {
    if (enable_fontstash and fons_backend.isReady()) {
        const m = fons_backend.vertMetrics(style.size * scale);
        return .{ .ascent = m.ascent, .descent = m.descent, .line_gap = 0, .height = m.lineh };
    }
    const size = style.size * scale;
    return .{ .ascent = size, .descent = size * 0.25, .line_gap = 0, .height = @ceil(size * 1.25) };
}

pub fn baselineInBox(box_h: f32, style: Style, line_height_opt: ?f32, scale: f32) f32 {
    const lh = line_height_opt orelse fontMetrics(style, scale).height;
    return @round((box_h - lh) * 0.5 + fontMetrics(style, scale).ascent);
}

pub fn advance(style: Style, scale: f32) f32 {
    // REQ-TEXT-038：固定度量后端的前进宽度 = round(0.5 × 字号)。
    return @max(1, @round(style.size * scale * 0.5));
}

fn advanceOf(text: []const u8, style: Style, scale: f32) f32 {
    if (enable_fontstash and fons_backend.isReady()) {
        const w = fons_backend.textWidth(style.size * scale, text);
        if (w > 0) return w;
    }
    return advance(style, scale) * @as(f32, @floatFromInt(core.codepointCount(text)));
}

fn lineHeight(style: Style, opts: LayoutOptions, scale: f32) f32 {
    return opts.line_height orelse fontMetrics(style, scale).height;
}

pub fn nextGrapheme(s: []const u8, offset: usize) usize {
    if (offset >= s.len) return s.len;
    const r = core.nextCodepoint(s, offset);
    return @min(s.len, offset + @max(1, r.len));
}

pub fn prevGrapheme(s: []const u8, offset: usize) usize {
    if (offset == 0) return 0;
    var i = offset - 1;
    while (i > 0 and (s[i] & 0xC0) == 0x80) i -= 1;
    return i;
}

pub fn isGraphemeBoundary(s: []const u8, offset: usize) bool {
    if (offset == 0 or offset >= s.len) return true;
    return (s[offset] & 0xC0) != 0x80;
}

pub fn nextWord(s: []const u8, offset: usize) usize {
    var i = offset;
    while (i < s.len and s[i] != ' ') i += 1;
    while (i < s.len and s[i] == ' ') i += 1;
    return i;
}

pub fn prevWord(s: []const u8, offset: usize) usize {
    var i = offset;
    while (i > 0 and s[i - 1] == ' ') i -= 1;
    while (i > 0 and s[i - 1] != ' ') i -= 1;
    return i;
}

pub fn wordRange(s: []const u8, offset: usize) Range {
    var start = offset;
    while (start > 0 and s[start - 1] != ' ') start -= 1;
    var end = offset;
    while (end < s.len and s[end] != ' ') end += 1;
    return .{ .start = @intCast(start), .end = @intCast(end) };
}

pub const ColorSpan = struct { start: u32, end: u32, color: core.Color };
pub const DrawOptions = struct { spans: []const ColorSpan = &.{}, line_range: ?Range = null };

pub fn draw(canvas: *gfx.Canvas, l: *const Layout, origin: core.Vec2, color: core.Color, opts: DrawOptions) void {
    if (enable_fontstash and fons_backend.isReady()) {
        for (l.lines_buf, 0..) |line, li| {
            if (opts.line_range) |r| if (li < r.start or li > r.end) continue;
            const xoff = switch (l.opts.@"align") {
                .left => 0,
                .center => @floor((l.size.w - line.width) * 0.5),
                .right => l.size.w - line.width,
            };
            const x = (origin.x + xoff) * l.scale;
            const y = (origin.y + line.y) * l.scale;
            fons_backend.drawLine(canvas, l.style.size * l.scale, x, y, l.text[line.start..line.end], color);
        }
        return;
    }
    if (use_directwrite and builtin.os.tag == .windows) {
        directwrite.draw(l.allocator, canvas, l.text, l.style.size, l.style.weight, resolvedFamily(l.style.family), origin, color) catch {};
        return;
    }
    const adv = advance(l.style, l.scale);
    const glyph_w = @max(1, @min(adv, @round(l.style.size * l.scale * 0.66)));
    const glyph_h = @max(1, @round(l.style.size * l.scale));
    for (l.lines_buf, 0..) |line, li| {
        if (opts.line_range) |r| {
            if (li < r.start or li > r.end) continue;
        }
        var x = origin.x + switch (l.opts.@"align") {
            .left => 0,
            .center => @floor((l.size.w - line.width) * 0.5),
            .right => l.size.w - line.width,
        };
        var byte = line.start;
        while (byte < line.end) {
            const r = core.nextCodepoint(l.text, byte);
            const cw = adv;
            var c = color;
            for (opts.spans) |sp| {
                if (byte >= sp.start and byte < sp.end) c = sp.color;
            }
            if (r.cp != ' ') {
                drawGlyph(canvas, x, origin.y + line.y, glyph_w, glyph_h, r.cp, c);
                atlas_raster_count += 1;
            }
            x += cw;
            byte += @intCast(@max(1, r.len));
        }
    }
}

fn drawGlyph(canvas: *gfx.Canvas, x: f32, y: f32, w: f32, h: f32, cp: u21, color: core.Color) void {
    if (cp >= 32 and cp <= 126) {
        const glyph = font8x8[cp - 32];
        var row: usize = 0;
        while (row < 8) : (row += 1) {
            const bits = glyph[row];
            var col: usize = 0;
            while (col < 8) : (col += 1) {
                if (bits & (@as(u8, 1) << @intCast(col)) == 0) continue;
                const rx = x + w * @as(f32, @floatFromInt(col)) / 8.0;
                const ry = y + h * @as(f32, @floatFromInt(row)) / 8.0;
                const rw = w / 8.0;
                const rh = h / 8.0;
                canvas.fillRect(.{ .x = rx, .y = ry, .w = rw + 0.35, .h = rh + 0.35 }, color);
            }
        }
        return;
    }
    // 非拉丁字形：绘制一个占位方框，保证宽度与行高确定，且不会出现半个字形。
    const rr = @min(w, h) * 0.18;
    canvas.strokeRoundRect(.{ .x = x + w * 0.1, .y = y + h * 0.1, .w = w * 0.8, .h = h * 0.8 }, rr, color, 1);
    canvas.fillRect(.{ .x = x + w * 0.3, .y = y + h * 0.42, .w = w * 0.4, .h = @max(1, h * 0.08) }, color);
}

pub const Composition = struct {
    start: u32,
    len: u32,
    cursor: u32,
    segments: []const platform.ImeSegment,
};

pub const CompositionStyle = struct {
    underline: core.Color,
    target_underline: core.Color,
    error_underline: core.Color,
    target_bg: ?core.Color = null,
};

/// 绘制输入法组字下划线与目标子句背景（REQ-TEXT-039）。线程：界面线程。
pub fn drawComposition(canvas: *gfx.Canvas, l: *const Layout, origin: core.Vec2, comp: Composition, style: CompositionStyle) void {
    if (comp.len == 0) return;
    const hairline: f32 = @max(1.0, @floor(l.scale)) / l.scale;
    const fm = fontMetrics(l.style, l.scale);
    const ppx_size = l.style.size * l.scale;
    const ul_off = @max(1.0, @round(0.1 * ppx_size)) / l.scale;
    const ul_y_off = fm.ascent + ul_off;

    for (comp.segments) |seg| {
        const s_off = @min(comp.start + seg.start, l.text_len);
        const e_off = @min(comp.start + seg.end, l.text_len);
        if (e_off <= s_off) continue;
        const line_s = l.lineOf(.{ .offset = s_off });
        const line_e = l.lineOf(.{ .offset = e_off });
        var li = line_s;
        while (li <= line_e) : (li += 1) {
            const lr = l.lineRange(li);
            const seg_s = @max(s_off, lr.start);
            const seg_e = @min(e_off, lr.end);
            if (seg_e <= seg_s) continue;
            const c0 = l.caretRect(.{ .offset = seg_s });
            const c1 = l.caretRect(.{ .offset = seg_e });
            const x0 = origin.x + c0.x;
            const w = @max(hairline, c1.x - c0.x);
            const y0 = origin.y + l.lines_buf[li].y;
            if ((seg.style == .target_converted or seg.style == .target_unconverted) and style.target_bg != null) {
                canvas.fillRect(.{ .x = x0, .y = y0, .w = w, .h = c0.h }, style.target_bg.?);
            }
            const col = switch (seg.style) {
                .target_converted, .target_unconverted => style.target_underline,
                .@"error" => style.error_underline,
                .unconverted, .converted => style.underline,
            };
            const thick = switch (seg.style) {
                .target_converted, .target_unconverted, .@"error" => hairline * 2.0,
                .unconverted, .converted => hairline,
            };
            const dotted = seg.style == .unconverted or seg.style == .target_unconverted;
            const uy = y0 + ul_y_off;
            if (!dotted) {
                canvas.fillRect(.{ .x = x0, .y = uy, .w = w, .h = thick }, col);
            } else {
                var dx: f32 = 0;
                while (dx < w) : (dx += hairline * 2.0) {
                    const dw = @min(hairline, w - dx);
                    canvas.fillRect(.{ .x = x0 + dx, .y = uy, .w = dw, .h = thick }, col);
                }
            }
        }
    }
}

pub fn isInitialized() bool {
    return backend_allocator != null;
}

pub fn init(allocator: std.mem.Allocator, config: Config) error{OutOfMemory}!void {
    cacheClear(); // 重新初始化时丢弃旧缓存
    backend_allocator = allocator;
    cache_max_entries = config.layout_cache_entries;
    cache_max_bytes = config.layout_cache_bytes;
    if (builtin.os.tag == .windows) {
        _ = @import("text/directwrite.zig").ensureFactory();
    }
    if (enable_fontstash) {
        fons_backend.init() catch return error.OutOfMemory;
    }
}
pub fn deinit() void {
    cacheClear();
    if (backend_allocator) |a| {
        for (custom_families.items) |name| a.free(name);
        custom_families.deinit(a);
        custom_families = .empty;
    }
    if (comptime enable_fontstash) {
        fons_backend.deinit();
    }
    atlas_pages = 0;
    atlas_rgba_pages = 0;
    atlas_used_ppx = 0;
    core.stats.gauge("cache.glyph_atlas.bytes").* = 0;
    backend_allocator = null;
}
pub fn beginBuild() void {
    // 新的构建代；构建期间不淘汰，收敛由 trimCache 在构建完成后执行（REQ-TEXT-014）。
    cache_gen += 1;
    std.debug.assert(backend_allocator != null); // 必须先 text.init（REQ-ARCH-011）
}
pub fn onSettingsChanged() void {
    // DPI、字体设置、主题字体令牌变化时整体清空（REQ-TEXT-013）。
    cacheClear();
}
/// 每次构建完成后调用：按 REQ-TEXT-014 淘汰超限且未受保护的条目。
pub fn trimCache() void {
    cacheEvict();
    cacheReport();
}

pub const Config = struct {
    layout_cache_entries: u32 = 4096,
    layout_cache_bytes: usize = 8 * 1024 * 1024,
    atlas_page_size: u32 = 1024,
    atlas_max_pages: u32 = 16,
};

pub const testing = struct {
    pub const DrawRecord = struct { layout: *const Layout, origin: core.Vec2, color: core.Color };
    var records: [128]DrawRecord = undefined;
    var count: usize = 0;
    pub fn drawLog() []const DrawRecord {
        return records[0..count];
    }
    pub fn record(l: *const Layout, origin: core.Vec2, color: core.Color) void {
        if (count < records.len) {
            records[count] = .{ .layout = l, .origin = origin, .color = color };
            count += 1;
        }
    }
    pub fn reset() void {
        count = 0;
    }
    pub fn atlasStats() struct { pages: u32, rgba_pages: u32, used_ppx: u64, raster_count: u64, shape_count: u64 } {
        return .{
            .pages = atlas_pages,
            .rgba_pages = atlas_rgba_pages,
            .used_ppx = atlas_used_ppx,
            .raster_count = atlas_raster_count,
            .shape_count = atlas_shape_count,
        };
    }
};

// 8x8 基本拉丁字形，公有领域 VGA 字体（见 docs 05 的确定性要求）。
const font8x8: [95][8]u8 = .{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    .{ 0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00 },
    .{ 0x36, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    .{ 0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00 },
    .{ 0x0C, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x0C, 0x00 },
    .{ 0x00, 0x63, 0x33, 0x18, 0x0C, 0x66, 0x63, 0x00 },
    .{ 0x1C, 0x36, 0x1C, 0x6E, 0x3B, 0x33, 0x6E, 0x00 },
    .{ 0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00 },
    .{ 0x18, 0x0C, 0x06, 0x06, 0x06, 0x0C, 0x18, 0x00 },
    .{ 0x06, 0x0C, 0x18, 0x18, 0x18, 0x0C, 0x06, 0x00 },
    .{ 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00 },
    .{ 0x00, 0x0C, 0x0C, 0x3F, 0x0C, 0x0C, 0x00, 0x00 },
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x06 },
    .{ 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00 },
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00 },
    .{ 0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00 },
    .{ 0x3E, 0x63, 0x73, 0x7B, 0x6F, 0x67, 0x3E, 0x00 },
    .{ 0x0C, 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x00 },
    .{ 0x1E, 0x33, 0x30, 0x1C, 0x06, 0x33, 0x3F, 0x00 },
    .{ 0x1E, 0x33, 0x30, 0x1C, 0x30, 0x33, 0x1E, 0x00 },
    .{ 0x38, 0x3C, 0x36, 0x33, 0x7F, 0x30, 0x78, 0x00 },
    .{ 0x3F, 0x03, 0x1F, 0x30, 0x30, 0x33, 0x1E, 0x00 },
    .{ 0x1C, 0x06, 0x03, 0x1F, 0x33, 0x33, 0x1E, 0x00 },
    .{ 0x3F, 0x33, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x00 },
    .{ 0x1E, 0x33, 0x33, 0x1E, 0x33, 0x33, 0x1E, 0x00 },
    .{ 0x1E, 0x33, 0x33, 0x3E, 0x30, 0x18, 0x0E, 0x00 },
    .{ 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x00 },
    .{ 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x06 },
    .{ 0x18, 0x0C, 0x06, 0x03, 0x06, 0x0C, 0x18, 0x00 },
    .{ 0x00, 0x00, 0x3F, 0x00, 0x00, 0x3F, 0x00, 0x00 },
    .{ 0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00 },
    .{ 0x1E, 0x33, 0x30, 0x18, 0x0C, 0x00, 0x0C, 0x00 },
    .{ 0x3E, 0x63, 0x7B, 0x7B, 0x7B, 0x03, 0x1E, 0x00 },
    .{ 0x0C, 0x1E, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x00 },
    .{ 0x3F, 0x66, 0x66, 0x3E, 0x66, 0x66, 0x3F, 0x00 },
    .{ 0x3C, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3C, 0x00 },
    .{ 0x1F, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1F, 0x00 },
    .{ 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x46, 0x7F, 0x00 },
    .{ 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x06, 0x0F, 0x00 },
    .{ 0x3C, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7C, 0x00 },
    .{ 0x33, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x00 },
    .{ 0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00 },
    .{ 0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E, 0x00 },
    .{ 0x67, 0x66, 0x36, 0x1E, 0x36, 0x66, 0x67, 0x00 },
    .{ 0x0F, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7F, 0x00 },
    .{ 0x63, 0x77, 0x7F, 0x7F, 0x6B, 0x63, 0x63, 0x00 },
    .{ 0x63, 0x67, 0x6F, 0x7B, 0x73, 0x63, 0x63, 0x00 },
    .{ 0x1C, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1C, 0x00 },
    .{ 0x3F, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x0F, 0x00 },
    .{ 0x1E, 0x33, 0x33, 0x33, 0x3B, 0x1E, 0x38, 0x00 },
    .{ 0x3F, 0x66, 0x66, 0x3E, 0x36, 0x66, 0x67, 0x00 },
    .{ 0x1E, 0x33, 0x07, 0x0E, 0x38, 0x33, 0x1E, 0x00 },
    .{ 0x3F, 0x2D, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00 },
    .{ 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3F, 0x00 },
    .{ 0x33, 0x33, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00 },
    .{ 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00 },
    .{ 0x63, 0x63, 0x36, 0x1C, 0x1C, 0x36, 0x63, 0x00 },
    .{ 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x0C, 0x1E, 0x00 },
    .{ 0x7F, 0x63, 0x31, 0x18, 0x4C, 0x66, 0x7F, 0x00 },
    .{ 0x1E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x1E, 0x00 },
    .{ 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00 },
    .{ 0x1E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1E, 0x00 },
    .{ 0x08, 0x1C, 0x36, 0x63, 0x00, 0x00, 0x00, 0x00 },
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF },
    .{ 0x0C, 0x0C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 },
    .{ 0x00, 0x00, 0x1E, 0x30, 0x3E, 0x33, 0x6E, 0x00 },
    .{ 0x07, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x3B, 0x00 },
    .{ 0x00, 0x00, 0x1E, 0x33, 0x03, 0x33, 0x1E, 0x00 },
    .{ 0x38, 0x30, 0x30, 0x3E, 0x33, 0x33, 0x6E, 0x00 },
    .{ 0x00, 0x00, 0x1E, 0x33, 0x3F, 0x03, 0x1E, 0x00 },
    .{ 0x1C, 0x36, 0x06, 0x0F, 0x06, 0x06, 0x0F, 0x00 },
    .{ 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x1F },
    .{ 0x07, 0x06, 0x36, 0x6E, 0x66, 0x66, 0x67, 0x00 },
    .{ 0x0C, 0x00, 0x0E, 0x0C, 0x0C, 0x0C, 0x1E, 0x00 },
    .{ 0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E },
    .{ 0x07, 0x06, 0x66, 0x36, 0x1E, 0x36, 0x67, 0x00 },
    .{ 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00 },
    .{ 0x00, 0x00, 0x33, 0x7F, 0x7F, 0x6B, 0x63, 0x00 },
    .{ 0x00, 0x00, 0x1F, 0x33, 0x33, 0x33, 0x33, 0x00 },
    .{ 0x00, 0x00, 0x1E, 0x33, 0x33, 0x33, 0x1E, 0x00 },
    .{ 0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F },
    .{ 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x78 },
    .{ 0x00, 0x00, 0x3B, 0x6E, 0x66, 0x06, 0x0F, 0x00 },
    .{ 0x00, 0x00, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x00 },
    .{ 0x08, 0x0C, 0x3E, 0x0C, 0x0C, 0x2C, 0x18, 0x00 },
    .{ 0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6E, 0x00 },
    .{ 0x00, 0x00, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00 },
    .{ 0x00, 0x00, 0x63, 0x6B, 0x7F, 0x7F, 0x36, 0x00 },
    .{ 0x00, 0x00, 0x63, 0x36, 0x1C, 0x36, 0x63, 0x00 },
    .{ 0x00, 0x00, 0x33, 0x33, 0x33, 0x3E, 0x30, 0x1F },
    .{ 0x00, 0x00, 0x3F, 0x19, 0x0C, 0x26, 0x3F, 0x00 },
    .{ 0x38, 0x0C, 0x0C, 0x07, 0x0C, 0x0C, 0x38, 0x00 },
    .{ 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00 },
    .{ 0x07, 0x0C, 0x0C, 0x38, 0x0C, 0x0C, 0x07, 0x00 },
    .{ 0x6E, 0x3B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
};

test "fixed metrics match REQ-TEXT-038" {
    const style = Style{ .size = 16 };
    const m = measure("Hello 你好", style, 1.0, .{});
    try std.testing.expectEqual(@as(f32, 64), m.w);
    try std.testing.expectEqual(@as(f32, 20), m.h);
    const fm = fontMetrics(style, 1.0);
    try std.testing.expectEqual(@as(f32, 16), fm.ascent);
    try std.testing.expectEqual(@as(f32, 4), fm.descent);
    try std.testing.expectEqual(@as(f32, 20), fm.height);
}

test "grapheme navigation" {
    const s = "aé你";
    try std.testing.expectEqual(@as(usize, 1), nextGrapheme(s, 0));
    try std.testing.expectEqual(@as(usize, 3), nextGrapheme(s, 1));
    try std.testing.expectEqual(@as(usize, 3), prevGrapheme(s, 6));
}
