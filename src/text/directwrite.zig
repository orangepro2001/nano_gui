//! DirectWrite 文本后端（Windows）。
//!
//! 提供真实的 DWrite 工厂、文本格式与 `IDWriteTextLayout::GetMetrics` 度量；
//! `text.zig` 仍以 fixed 后端作为跨平台确定性测试后端，Windows 应用可显式调用
//! `measure`（后续接入字形栅格与排版缓存）。

const std = @import("std");
const winapi = std.os.windows;
const core = @import("../core.zig");
const gfx = @import("../gfx.zig");

pub const FACTORY_TYPE_SHARED: u32 = 0;
pub const IID_IDWriteFactory = winapi.GUID{
    .Data1 = 0xb859ee5a,
    .Data2 = 0xd838,
    .Data3 = 0x4b5b,
    .Data4 = .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 },
};

const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const winapi.GUID, *?*anyopaque) callconv(.winapi) i32,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
};
const IUnknown = extern struct { vtbl: *const IUnknownVtbl };

const TextMetrics = extern struct {
    left: f32 = 0,
    top: f32 = 0,
    width: f32 = 0,
    widthIncludingTrailingWhitespace: f32 = 0,
    height: f32 = 0,
    layoutWidth: f32 = 0,
    layoutHeight: f32 = 0,
    maxBidiReorderingDepth: u32 = 0,
    lineCount: u32 = 0,
};

const IDWriteTextLayout = extern struct {
    vtbl: *const Vtbl,
    const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winapi.GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        /// IDWriteTextFormat 的 25 个方法 + layout 的 Set*/Get*/Draw/GetLineMetrics 等，
        /// 直到 GetMetrics 之前的全部槽位（顺序以 dwrite.h 为准）。
        before_draw: [55]*const fn () callconv(.winapi) void,
        Draw: *const fn (*anyopaque, ?*anyopaque, *anyopaque, f32, f32) callconv(.winapi) i32,
        GetLineMetrics: *const fn () callconv(.winapi) void,
        GetMetrics: *const fn (*anyopaque, *TextMetrics) callconv(.winapi) i32,
        after_metrics: [6]*const fn () callconv(.winapi) void,
    };
};

const IDWriteTextFormat = extern struct {
    vtbl: *const Vtbl,
    const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winapi.GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        rest: [24]*const fn () callconv(.winapi) void,
    };
};

const GlyphRun = extern struct {
    fontFace: *anyopaque,
    fontSize: f32,
    glyphCount: u32,
    glyphIndices: [*]const u16,
    glyphAdvances: [*]const f32,
    glyphOffsets: *const anyopaque,
    isSideways: i32,
    bidiLevel: u32,
};
const GlyphRunDescription = extern struct {
    localeName: [*:0]const u16,
    string: [*]const u16,
    stringLength: u32,
    clusterMap: [*]const u16,
    textPosition: u32,
    textLength: u32,
};
const Rect = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };

const Matrix = extern struct { m11: f32 = 1, m12: f32 = 0, m21: f32 = 0, m22: f32 = 1, dx: f32 = 0, dy: f32 = 0 };
const GlyphRunAnalysis = extern struct {
    vtbl: *const Vtbl,
    const Vtbl = extern struct {
        QueryInterface: *const fn () callconv(.winapi) void,
        AddRef: *const fn () callconv(.winapi) void,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetAlphaTextureBounds: *const fn (*anyopaque, u32, *Rect) callconv(.winapi) i32,
        CreateAlphaTexture: *const fn (*anyopaque, u32, *const Rect, [*]u8, u32) callconv(.winapi) i32,
    };
};

const IDWriteGdiInterop = extern struct {
    vtbl: *const Vtbl,
    const Vtbl = extern struct {
        QueryInterface: *const fn () callconv(.winapi) void,
        AddRef: *const fn () callconv(.winapi) void,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        CreateFontFromLOGFONT: *const fn () callconv(.winapi) void,
        ConvertFontToLOGFONT: *const fn () callconv(.winapi) void,
        ConvertFontFaceToLOGFONT: *const fn () callconv(.winapi) void,
        CreateFontFaceFromHdc: *const fn () callconv(.winapi) void,
        CreateBitmapRenderTarget: *const fn (*anyopaque, ?*anyopaque, u32, u32, *?*IDWriteBitmapRenderTarget) callconv(.winapi) i32,
    };
};

const IDWriteBitmapRenderTarget = extern struct {
    vtbl: *const Vtbl,
    const Vtbl = extern struct {
        QueryInterface: *const fn () callconv(.winapi) void,
        AddRef: *const fn () callconv(.winapi) void,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        DrawGlyphRun: *const fn (*anyopaque, f32, f32, u32, *const GlyphRun, ?*anyopaque, u32, ?*Rect) callconv(.winapi) i32,
        GetMemoryDC: *const fn (*anyopaque) callconv(.winapi) ?*anyopaque,
        GetPixelsPerDip: *const fn (*anyopaque) callconv(.winapi) f32,
        SetPixelsPerDip: *const fn (*anyopaque, f32) callconv(.winapi) void,
        GetCurrentTransform: *const fn () callconv(.winapi) void,
        SetCurrentTransform: *const fn () callconv(.winapi) void,
        GetSize: *const fn (*anyopaque, *Rect) callconv(.winapi) i32,
        Resize: *const fn () callconv(.winapi) void,
    };
};

const TextRenderer = extern struct {
    vtbl: *const Vtbl,
    factory: *IDWriteFactory,
    canvas: *gfx.Canvas,
    origin_x: f32,
    origin_y: f32,
    color: [4]u8,
    const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winapi.GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        IsPixelSnappingDisabled: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) i32,
        GetCurrentTransform: *const fn (*anyopaque, ?*anyopaque, *anyopaque) callconv(.winapi) i32,
        GetPixelsPerDip: *const fn (*anyopaque, ?*anyopaque, *f32) callconv(.winapi) i32,
        DrawGlyphRun: *const fn (*anyopaque, ?*anyopaque, f32, f32, u32, *const GlyphRun, *const GlyphRunDescription, ?*anyopaque) callconv(.winapi) i32,
        DrawUnderline: *const fn () callconv(.winapi) void,
        DrawStrikethrough: *const fn () callconv(.winapi) void,
        DrawInlineObject: *const fn () callconv(.winapi) void,
    };
};

const IDWriteFactory = extern struct {
    vtbl: *const Vtbl,
    const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winapi.GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetSystemFontCollection: *const fn () callconv(.winapi) void,
        pre_text_format: [11]*const fn () callconv(.winapi) void,
        CreateTextFormat: *const fn (*anyopaque, [*:0]const u16, ?*anyopaque, u32, u32, u32, f32, [*:0]const u16, *?*IDWriteTextFormat) callconv(.winapi) i32,
        CreateTypography: *const fn () callconv(.winapi) void,
        GetGdiInterop: *const fn (*anyopaque, *?*IDWriteGdiInterop) callconv(.winapi) i32,
        CreateTextLayout: *const fn (*anyopaque, [*]const u16, u32, *IDWriteTextFormat, f32, f32, *?*IDWriteTextLayout) callconv(.winapi) i32,
        CreateGdiCompatibleTextLayout: *const fn () callconv(.winapi) void,
        CreateEllipsisTrimmingSign: *const fn () callconv(.winapi) void,
        CreateTextAnalyzer: *const fn () callconv(.winapi) void,
        CreateNumberSubstitution: *const fn () callconv(.winapi) void,
        CreateGlyphRunAnalysis: *const fn (*anyopaque, *const GlyphRun, f32, *const Matrix, u32, u32, f32, f32, *?*GlyphRunAnalysis) callconv(.winapi) i32,
    };
};

extern "dwrite" fn DWriteCreateFactory(factory_type: u32, iid: *const winapi.GUID, factory: *?*IDWriteFactory) callconv(.winapi) i32;

var factory: ?*IDWriteFactory = null;
var tried: bool = false;

pub fn ensureFactory() bool {
    if (tried) return factory != null;
    tried = true;
    var f: ?*IDWriteFactory = null;
    const hr = DWriteCreateFactory(FACTORY_TYPE_SHARED, &IID_IDWriteFactory, &f);
    if (hr >= 0) factory = f;
    return factory != null;
}

pub fn isAvailable() bool {
    return ensureFactory();
}

pub const Measurement = struct { width: f32, height: f32, lines: u32 };

/// 使用 DirectWrite 测量 UTF-8 文本；尺寸单位为 lpx（96 DPI 的 DIP）。
pub fn measure(allocator: std.mem.Allocator, text: []const u8, size_lpx: f32, weight: u16, family: []const u8) !Measurement {
    if (!ensureFactory()) return error.DirectWriteUnavailable;
    const f = factory orelse return error.DirectWriteUnavailable;
    const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, text);
    defer allocator.free(wide);
    const family_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, family);
    defer allocator.free(family_z);
    var fmt: ?*IDWriteTextFormat = null;
    const locale = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
    const hr1 = f.vtbl.CreateTextFormat(f, family_z.ptr, null, weight, 0, 5, size_lpx, locale, &fmt);
    if (hr1 < 0 or fmt == null) return error.DirectWriteFailed;
    defer _ = fmt.?.vtbl.Release(fmt.?);
    var layout: ?*IDWriteTextLayout = null;
    const hr2 = f.vtbl.CreateTextLayout(f, wide.ptr, @intCast(wide.len), fmt.?, 1.0e7, 1.0e7, &layout);
    if (hr2 < 0 or layout == null) return error.DirectWriteFailed;
    defer _ = layout.?.vtbl.Release(layout.?);
    var metrics: TextMetrics = .{};
    const hr3 = layout.?.vtbl.GetMetrics(layout.?, &metrics);
    if (hr3 < 0) return error.DirectWriteFailed;
    return .{ .width = metrics.width, .height = metrics.height, .lines = metrics.lineCount };
}

/// 仅验工厂可用；用于 Windows 启动自检。
pub fn selfTest() bool {
    return ensureFactory();
}

fn cbQuery(_: *anyopaque, _: *const winapi.GUID, _: *?*anyopaque) callconv(.winapi) i32 {
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
fn cbGlyphRun(this: *anyopaque, _: ?*anyopaque, x: f32, y: f32, mode: u32, run: *const GlyphRun, _: *const GlyphRunDescription, _: ?*anyopaque) callconv(.winapi) i32 {
    const r: *TextRenderer = @ptrCast(@alignCast(this));
    var m = Matrix{};
    var analysis: ?*GlyphRunAnalysis = null;
    const gh = r.factory.vtbl.CreateGlyphRunAnalysis(r.factory, run, 1.0, &m, mode, 0, 0, 0, &analysis);
    std.debug.print("dw analysis hr=0x{x} ptr={}\n", .{ @as(u32, @bitCast(gh)), analysis != null });
    if (gh < 0 or analysis == null) return 0;
    defer _ = analysis.?.vtbl.Release(analysis.?);
    var bounds = Rect{};
    const bh0 = analysis.?.vtbl.GetAlphaTextureBounds(analysis.?, 0, &bounds);
    std.debug.print("dw bounds hr=0x{x} {d},{d},{d},{d}\n", .{ @as(u32, @bitCast(bh0)), bounds.left, bounds.top, bounds.right, bounds.bottom });
    if (bh0 < 0) return 0;
    const bw: i32 = bounds.right - bounds.left;
    const bh: i32 = bounds.bottom - bounds.top;
    if (bw <= 0 or bh <= 0) return 0;
    const n: usize = @intCast(bw * bh);
    const alpha = std.heap.smp_allocator.alloc(u8, n) catch return 0;
    defer std.heap.smp_allocator.free(alpha);
    const th = analysis.?.vtbl.CreateAlphaTexture(analysis.?, 0, &bounds, alpha.ptr, @intCast(n));
    std.debug.print("dw texture hr=0x{x} n={d}\n", .{ @as(u32, @bitCast(th)), n });
    if (th < 0) return 0;
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

extern "user32" fn GetDC(hwnd: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn ReleaseDC(hwnd: ?*anyopaque, dc: ?*anyopaque) callconv(.winapi) i32;
extern "gdi32" fn CreateCompatibleDC(hdc: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn DeleteDC(hdc: ?*anyopaque) callconv(.winapi) i32;
extern "gdi32" fn GetCurrentObject(hdc: ?*anyopaque, ty: u32) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn GetDIBits(hdc: ?*anyopaque, bmp: ?*anyopaque, start: u32, lines: u32, bits: ?*anyopaque, bmi: *const BitmapInfo, usage: u32) callconv(.winapi) i32;
extern "gdi32" fn GdiFlush() callconv(.winapi) i32;
extern "gdi32" fn GetBitmapBits(bmp: ?*anyopaque, count: i32, bits: ?*anyopaque) callconv(.winapi) i32;
extern "gdi32" fn CreateDIBSection(dc: ?*anyopaque, bmi: *const BitmapInfo, usage: u32, bits: *?*anyopaque, section: ?*anyopaque, offset: u32) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn SelectObject(dc: ?*anyopaque, obj: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn BitBlt(dst: ?*anyopaque, x: i32, y: i32, w: i32, h: i32, src: ?*anyopaque, sx: i32, sy: i32, rop: u32) callconv(.winapi) i32;
extern "gdi32" fn DeleteObject(obj: ?*anyopaque) callconv(.winapi) i32;

const BitmapInfoHeader = extern struct {
    biSize: u32 = @sizeOf(BitmapInfoHeader),
    biWidth: i32 = 0,
    biHeight: i32 = 0,
    biPlanes: u16 = 1,
    biBitCount: u16 = 32,
    biCompression: u32 = 0,
    biSizeImage: u32 = 0,
    biXPelsPerMeter: i32 = 0,
    biYPelsPerMeter: i32 = 0,
    biClrUsed: u32 = 0,
    biClrImportant: u32 = 0,
};
const BitmapInfo = extern struct { bmiHeader: BitmapInfoHeader = .{}, bmiColors: [1]u32 = .{0} };

/// 用 DirectWrite/GDI 兼容位图渲染文字，并混合到 Canvas。
pub fn draw(allocator: std.mem.Allocator, canvas: *gfx.Canvas, text: []const u8, size_lpx: f32, weight: u16, family: []const u8, origin: core.Vec2, color: core.Color) !void {
    if (!ensureFactory()) return error.DirectWriteUnavailable;
    const f = factory orelse return error.DirectWriteUnavailable;
    const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, text);
    defer allocator.free(wide);
    const family_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, family);
    defer allocator.free(family_z);
    var fmt: ?*IDWriteTextFormat = null;
    const locale = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
    if (f.vtbl.CreateTextFormat(f, family_z.ptr, null, weight, 0, 5, size_lpx, locale, &fmt) < 0 or fmt == null) return error.DirectWriteFailed;
    defer _ = fmt.?.vtbl.Release(fmt.?);
    var layout: ?*IDWriteTextLayout = null;
    if (f.vtbl.CreateTextLayout(f, wide.ptr, @intCast(wide.len), fmt.?, 1.0e7, 1.0e7, &layout) < 0 or layout == null) return error.DirectWriteFailed;
    defer _ = layout.?.vtbl.Release(layout.?);
    var renderer = TextRenderer{ .vtbl = &renderer_vtbl, .factory = f, .canvas = canvas, .origin_x = origin.x, .origin_y = origin.y, .color = .{ color.r, color.g, color.b, color.a } };
    if (layout.?.vtbl.Draw(layout.?, null, @ptrCast(&renderer), 0, 0) < 0) return error.DirectWriteFailed;
}
