//! DirectWrite 文本后端（Windows）。
//!
//! 提供真实的 DWrite 工厂、文本格式与 `IDWriteTextLayout::GetMetrics` 度量；
//! `text.zig` 仍以 fixed 后端作为跨平台确定性测试后端，Windows 应用可显式调用
//! `measure`（后续接入字形栅格与排版缓存）。

const std = @import("std");
const winapi = std.os.windows;

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
        before_metrics: [57]*const fn () callconv(.winapi) void,
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
        GetGdiInterop: *const fn () callconv(.winapi) void,
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
