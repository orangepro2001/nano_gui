//! DirectWrite 文本后端（Windows）。
//!
//! 提供真实的 DWrite 工厂、文本格式与 `IDWriteTextLayout::GetMetrics` 度量；
//! `text.zig` 仍以 fixed 后端作为跨平台确定性测试后端，Windows 应用可显式调用
//! `measure`（后续接入字形栅格与排版缓存）。

const std = @import("std");
const core = @import("../core.zig");
const gfx = @import("../gfx.zig");
const dw = @import("directwrite_bindings.zig");

const TextRenderer = extern struct {
    vtbl: *const Vtbl,
    factory: *dw.IDWriteFactory,
    canvas: *gfx.Canvas,
    origin_x: f32,
    origin_y: f32,
    color: [4]u8,
    const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const dw.GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        IsPixelSnappingDisabled: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) i32,
        GetCurrentTransform: *const fn (*anyopaque, ?*anyopaque, *anyopaque) callconv(.winapi) i32,
        GetPixelsPerDip: *const fn (*anyopaque, ?*anyopaque, *f32) callconv(.winapi) i32,
        DrawGlyphRun: *const fn (*anyopaque, ?*anyopaque, f32, f32, u32, *const dw.GlyphRun, *const dw.GlyphRunDescription, ?*anyopaque) callconv(.winapi) i32,
        DrawUnderline: *const fn () callconv(.winapi) void,
        DrawStrikethrough: *const fn () callconv(.winapi) void,
        DrawInlineObject: *const fn () callconv(.winapi) void,
    };
};

var factory: ?*dw.IDWriteFactory = null;
var tried: bool = false;

/// 确保 DirectWrite 工厂已创建；不可用时返回 false。线程：界面线程。
pub fn ensureFactory() bool {
    if (tried) return factory != null;
    tried = true;
    var f: ?*dw.IDWriteFactory = null;
    const hr = dw.DWriteCreateFactory(dw.DWRITE_FACTORY_TYPE_SHARED, &dw.IID_IDWRITE_FACTORY, &f);
    if (hr >= 0) factory = f;
    return factory != null;
}

/// 返回 DirectWrite 后端是否可用。线程：界面线程。
pub fn isAvailable() bool {
    return ensureFactory();
}

/// DirectWrite 文本测量结果。
pub const Measurement = struct { width: f32, height: f32, lines: u32 };

/// 使用 DirectWrite 测量 UTF-8 文本；尺寸单位为 lpx（96 DPI 的 DIP）。线程：界面线程。
pub fn measure(allocator: std.mem.Allocator, text: []const u8, size_lpx: f32, weight: u16, family: []const u8) !Measurement {
    if (!ensureFactory()) return error.DirectWriteUnavailable;
    const f = factory orelse return error.DirectWriteUnavailable;
    const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, text);
    defer allocator.free(wide);
    const family_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, family);
    defer allocator.free(family_z);
    var fmt: ?*dw.IDWriteTextFormat = null;
    const locale = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
    const hr1 = f.vtbl.CreateTextFormat(f, family_z.ptr, null, weight, 0, 5, size_lpx, locale, &fmt);
    if (hr1 < 0 or fmt == null) return error.DirectWriteFailed;
    defer _ = fmt.?.vtbl.Release(fmt.?);
    var layout: ?*dw.IDWriteTextLayout = null;
    const hr2 = f.vtbl.CreateTextLayout(f, wide.ptr, @intCast(wide.len), fmt.?, 1.0e7, 1.0e7, &layout);
    if (hr2 < 0 or layout == null) return error.DirectWriteFailed;
    defer _ = layout.?.vtbl.Release(layout.?);
    var metrics: dw.TextMetrics = .{};
    const hr3 = layout.?.vtbl.GetMetrics(layout.?, &metrics);
    if (hr3 < 0) return error.DirectWriteFailed;
    return .{ .width = metrics.width, .height = metrics.height, .lines = metrics.lineCount };
}

/// 仅验工厂可用；用于 Windows 启动自检。线程：界面线程。
pub fn selfTest() bool {
    return ensureFactory();
}

fn cbQuery(_: *anyopaque, _: *const dw.GUID, _: *?*anyopaque) callconv(.winapi) i32 {
    return @bitCast(@as(u32, 0x80004002));
}
fn cbAddRef(_: *anyopaque) callconv(.winapi) u32 {
    return 1;
}
fn cbRelease(_: *anyopaque) callconv(.winapi) u32 {
    return 1;
}
fn cbSnap(_: *anyopaque, _: ?*anyopaque, disabled: *i32) callconv(.winapi) i32 {
    disabled.* = 1;
    return 0;
}
fn cbTransform(_: *anyopaque, _: ?*anyopaque, _: *anyopaque) callconv(.winapi) i32 {
    return 0;
}
fn cbPixels(_: *anyopaque, _: ?*anyopaque, ppd: *f32) callconv(.winapi) i32 {
    ppd.* = 1.0;
    return 0;
}
fn cbGlyphRun(this: *anyopaque, _: ?*anyopaque, x: f32, y: f32, mode: u32, run: *const dw.GlyphRun, _: *const dw.GlyphRunDescription, _: ?*anyopaque) callconv(.winapi) i32 {
    const r: *TextRenderer = @ptrCast(@alignCast(this));
    _ = mode;
    var analysis: ?*dw.GlyphRunAnalysis = null;
    const gh = r.factory.vtbl.CreateGlyphRunAnalysis(r.factory, run, 1.0, null, 1, 0, 0, 0, &analysis);
    if (gh < 0 or analysis == null) return 0;
    defer _ = analysis.?.vtbl.Release(analysis.?);
    var bounds = dw.Rect{};
    if (analysis.?.vtbl.GetAlphaTextureBounds(analysis.?, 0, &bounds) < 0) return 0;
    const bw: i32 = bounds.right - bounds.left;
    const bh: i32 = bounds.bottom - bounds.top;
    if (bw <= 0 or bh <= 0) return 0;
    const n: usize = @intCast(bw * bh);
    const alpha = std.heap.smp_allocator.alloc(u8, n) catch return 0;
    defer std.heap.smp_allocator.free(alpha);
    if (analysis.?.vtbl.CreateAlphaTexture(analysis.?, 0, &bounds, alpha.ptr, @intCast(n)) < 0) return 0;
    var yy: i32 = 0;
    while (yy < bh) : (yy += 1) {
        var xx: i32 = 0;
        while (xx < bw) : (xx += 1) {
            const a = alpha[@intCast(yy * bw + xx)];
            if (a == 0) continue;
            const c = core.Color{ .r = r.color[0], .g = r.color[1], .b = r.color[2], .a = a };
            r.canvas.blitPixel(r.origin_x + x + @as(f32, @floatFromInt(bounds.left + xx)), r.origin_y + y + @as(f32, @floatFromInt(bounds.top + yy)), c);
        }
    }
    return 0;
}
fn cbUnderline() callconv(.winapi) void {}
fn cbStrike() callconv(.winapi) void {}
fn cbInline() callconv(.winapi) void {}

const renderer_vtbl = TextRenderer.Vtbl{
    .QueryInterface = cbQuery,
    .AddRef = cbAddRef,
    .Release = cbRelease,
    .IsPixelSnappingDisabled = cbSnap,
    .GetCurrentTransform = cbTransform,
    .GetPixelsPerDip = cbPixels,
    .DrawGlyphRun = cbGlyphRun,
    .DrawUnderline = cbUnderline,
    .DrawStrikethrough = cbStrike,
    .DrawInlineObject = cbInline,
};

/// 用 DirectWrite/GDI 兼容位图渲染文字，并混合到 Canvas。线程：界面线程。
pub fn draw(allocator: std.mem.Allocator, canvas: *gfx.Canvas, text: []const u8, size_lpx: f32, weight: u16, family: []const u8, origin: core.Vec2, color: core.Color) !void {
    if (!ensureFactory()) return error.DirectWriteUnavailable;
    const f = factory orelse return error.DirectWriteUnavailable;
    const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, text);
    defer allocator.free(wide);
    const family_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, family);
    defer allocator.free(family_z);
    var fmt: ?*dw.IDWriteTextFormat = null;
    const locale = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
    if (f.vtbl.CreateTextFormat(f, family_z.ptr, null, weight, 0, 5, size_lpx, locale, &fmt) < 0 or fmt == null) return error.DirectWriteFailed;
    defer _ = fmt.?.vtbl.Release(fmt.?);
    var layout: ?*dw.IDWriteTextLayout = null;
    if (f.vtbl.CreateTextLayout(f, wide.ptr, @intCast(wide.len), fmt.?, 1.0e7, 1.0e7, &layout) < 0 or layout == null) return error.DirectWriteFailed;
    defer _ = layout.?.vtbl.Release(layout.?);
    var renderer = TextRenderer{ .vtbl = &renderer_vtbl, .factory = f, .canvas = canvas, .origin_x = origin.x, .origin_y = origin.y, .color = .{ color.r, color.g, color.b, color.a } };
    if (layout.?.vtbl.Draw(layout.?, null, @ptrCast(&renderer), 0, 0) < 0) return error.DirectWriteFailed;
}
