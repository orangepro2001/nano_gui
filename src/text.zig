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

var backend_allocator: ?std.mem.Allocator = null;
var layout_cache: [32]?*Layout = @splat(null);
var layout_cache_idx: usize = 0;

pub const backend_name: []const u8 = "fixed";
pub const directwrite = @import("text/directwrite.zig");

pub const Family = enum(u16) { ui, mono, _ };
pub fn registerFamily(_: []const u8) error{OutOfMemory}!Family {
    return .ui;
}
pub fn resolvedFamily(f: Family) []const u8 {
    return switch (f) {
        .ui => "Segoe UI",
        .mono => "Cascadia Mono",
        else => "Segoe UI",
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
        const rel = @max(0, point.x - self.alignOffset(line.width));
        var offset = line.start;
        var x: f32 = 0;
        while (offset < line.end) {
            const next = nextGrapheme(self.text, offset);
            const w = adv * @as(f32, @floatFromInt(core.codepointCount(self.text[offset..next])));
            if (point.x < rel + x + w * 0.5) break;
            x += w;
            offset = next;
        }
        return .{
            .caret = .{ .offset = @min(offset, self.text_len) },
            .cluster_start = offset,
            .edge = .leading,
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
        const r = self.caretRect(.{ .offset = comp.start + comp.cursor });
        return .{ .caret = r, .target = null };
    }

    fn alignOffset(self: *const Layout, line_w: f32) f32 {
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

/// 返回的 *const Layout 在下次调用前有效；供直接测量使用。
pub fn layout(text: []const u8, style: Style, scale: f32, opts: LayoutOptions) *const Layout {
    const slot = layout_cache_idx % layout_cache.len;
    if (layout_cache[slot]) |old| old.deinit();
    const alloc = backend_allocator orelse std.heap.smp_allocator;
    const owned = layoutOwned(alloc, text, style, scale, opts) catch unreachable;
    layout_cache[slot] = owned.layout;
    layout_cache_idx += 1;
    return layout_cache[slot].?;
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
    return .{ .layout = layout_ptr };
}

pub fn measure(text: []const u8, style: Style, scale: f32, opts: LayoutOptions) core.Size {
    var effective = opts;
    effective.max_width = null;
    const l = layoutOwned(std.heap.smp_allocator, text, style, scale, effective) catch return .{};
    defer l.layout.deinit();
    return l.layout.size;
}

pub fn isTruncated(text: []const u8, style: Style, scale: f32, max_width: f32) bool {
    return measure(text, style, scale, .{}).w > max_width;
}

pub fn fontMetrics(style: Style, scale: f32) FontMetrics {
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
            const cw = adv * @as(f32, @floatFromInt(@max(@as(usize, 1), r.len)));
            var c = color;
            for (opts.spans) |sp| {
                if (byte >= sp.start and byte < sp.end) c = sp.color;
            }
            if (r.cp != ' ') {
                drawGlyph(canvas, x, origin.y + line.y, glyph_w, glyph_h, r.cp, c);
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

pub fn drawComposition(canvas: *gfx.Canvas, l: *const Layout, origin: core.Vec2, comp: Composition, style: CompositionStyle) void {
    _ = l;
    _ = origin;
    _ = comp;
    _ = style;
    _ = canvas;
}

pub fn init(allocator: std.mem.Allocator, _: Config) error{OutOfMemory}!void {
    backend_allocator = allocator;
    if (builtin.os.tag == .windows) {
        _ = @import("text/directwrite.zig").ensureFactory();
    }
}
pub fn deinit() void {
    for (&layout_cache) |*slot| {
        if (slot.*) |l| {
            l.deinit();
            slot.* = null;
        }
    }
    layout_cache_idx = 0;
    backend_allocator = null;
}
pub fn beginBuild() void {
    const S = struct {
        var ready: bool = false;
    };
    if (!S.ready) {
        S.ready = true;
        if (backend_allocator == null) init(std.heap.smp_allocator, .{}) catch {};
    }
}
pub fn onSettingsChanged() void {}
pub fn trimCache() void {}

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
    pub fn atlasStats() struct { pages: u32, used_ppx: u64, raster_count: u64, shape_count: u64 } {
        return .{ .pages = 0, .used_ppx = 0, .raster_count = 0, .shape_count = 0 };
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
