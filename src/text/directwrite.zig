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
        SetPixelsPerDip: *const fn () callconv(.winapi) void,
        GetCurrentTransform: *const fn () callconv(.winapi) void,
        SetCurrentTransform: *const fn () callconv(.winapi) void,
        GetSize: *const fn (*anyopaque, *Rect) callconv(.winapi) i32,
        Resize: *const fn () callconv(.winapi) void,
    };
};

const TextRenderer = extern struct {
    vtbl: *const Vtbl,
    target: *IDWriteBitmapRenderTarget,
    color: u32 = 0xFFFFFF,
    rparams: ?*anyopaque = null,
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
    const hr = r.target.vtbl.DrawGlyphRun(r.target, x, y, mode, run, r.rparams, r.color, null);
    return hr;
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
    var metrics: TextMetrics = .{};
    if (layout.?.vtbl.GetMetrics(layout.?, &metrics) < 0) return error.DirectWriteFailed;
    const w: u32 = @intFromFloat(@max(1, @ceil(metrics.width) + 4));
    const h: u32 = @intFromFloat(@max(1, @ceil(metrics.height) + 4));
    var gdi: ?*IDWriteGdiInterop = null;
    if (f.vtbl.GetGdiInterop(f, &gdi) < 0 or gdi == null) return error.DirectWriteFailed;
    defer _ = gdi.?.vtbl.Release(gdi.?);
    const screen_dc = GetDC(null) orelse return error.DirectWriteFailed;
    defer _ = ReleaseDC(null, screen_dc);
    var target: ?*IDWriteBitmapRenderTarget = null;
    if (gdi.?.vtbl.CreateBitmapRenderTarget(gdi.?, screen_dc, w, h, &target) < 0 or target == null) return error.DirectWriteFailed;
    target.?.vtbl.SetPixelsPerDip(target.?, 1.0);
    defer _ = target.?.vtbl.Release(target.?);
    var rparams: ?*anyopaque = null;
    const create_rp = @as(*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32, @ptrCast(f.vtbl.pre_text_format[6]));
    _ = create_rp(f, &rparams);
    const text_color: u32 = @as(u32, color.r) | (@as(u32, color.g) << 8) | (@as(u32, color.b) << 16);
    var renderer = TextRenderer{ .vtbl = &renderer_vtbl, .target = target.?, .color = text_color, .rparams = rparams };
    renderer.target = target.?;
    const draw_hr = layout.?.vtbl.Draw(layout.?, null, @ptrCast(&renderer), 2.0, 2.0);
    std.debug.print("dwrite layout draw hr=0x{x}\n", .{@as(u32, @bitCast(draw_hr))});
    if (draw_hr < 0) return error.DirectWriteFailed;
    const memdc = target.?.vtbl.GetMemoryDC(target.?) orelse return error.DirectWriteFailed;
    var bmi = BitmapInfo{};
    bmi.bmiHeader.biWidth = @intCast(w);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(h));
    const dst_dc = CreateCompatibleDC(null) orelse return error.DirectWriteFailed;
    defer _ = DeleteDC(dst_dc);
    var raw_bits: ?*anyopaque = null;
    const dib = CreateDIBSection(dst_dc, &bmi, 0, &raw_bits, null, 0) orelse return error.DirectWriteFailed;
    defer _ = DeleteObject(dib);
    const old = SelectObject(dst_dc, dib);
    defer _ = SelectObject(dst_dc, old);
    _ = GdiFlush();
    _ = BitBlt(dst_dc, 0, 0, @intCast(w), @intCast(h), memdc, 0, 0, 0x00CC0020);
    const bits = @as([*]u8, @ptrCast(raw_bits orelse return error.DirectWriteFailed))[0 .. @as(usize, w) * h * 4];
    // target 为 BGRA；按 alpha 混合到 Canvas 的 RGBA。
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            const o = (@as(usize, y) * w + x) * 4;
            const rgb_nonzero = bits[o] != 0 or bits[o + 1] != 0 or bits[o + 2] != 0;
            if (!rgb_nonzero) continue;
            const a = if (bits[o + 3] == 0) 255 else bits[o + 3];
            const px = core.Color{ .r = bits[o + 2], .g = bits[o + 1], .b = bits[o], .a = a };
            canvas.blitPixel(origin.x + @as(f32, @floatFromInt(x)), origin.y + @as(f32, @floatFromInt(y)), px);
        }
    }
}
