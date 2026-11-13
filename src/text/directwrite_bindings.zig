//! DirectWrite 与 GDI 位图外部绑定（REQ-ARCH-003、REQ-CONV-018、REQ-CONV-019）。

pub const GUID = @import("std").os.windows.GUID;

pub const DWRITE_FACTORY_TYPE_SHARED: u32 = 0;
pub const IID_IDWRITE_FACTORY = GUID{
    .Data1 = 0xb859ee5a,
    .Data2 = 0xd838,
    .Data3 = 0x4b5b,
    .Data4 = .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 },
};

pub const TextMetrics = extern struct {
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

pub const IDWriteTextLayout = extern struct {
    vtbl: *const Vtbl,
    pub const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        before_draw: [55]*const fn () callconv(.winapi) void,
        Draw: *const fn (*anyopaque, ?*anyopaque, *anyopaque, f32, f32) callconv(.winapi) i32,
        GetLineMetrics: *const fn () callconv(.winapi) void,
        GetMetrics: *const fn (*anyopaque, *TextMetrics) callconv(.winapi) i32,
        after_metrics: [6]*const fn () callconv(.winapi) void,
    };
};

pub const IDWriteTextFormat = extern struct {
    vtbl: *const Vtbl,
    pub const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        rest: [24]*const fn () callconv(.winapi) void,
    };
};

pub const GlyphRun = extern struct {
    fontFace: *anyopaque,
    fontSize: f32,
    glyphCount: u32,
    glyphIndices: [*]const u16,
    glyphAdvances: [*]const f32,
    glyphOffsets: *const anyopaque,
    isSideways: i32,
    bidiLevel: u32,
};

pub const GlyphRunDescription = extern struct {
    localeName: [*:0]const u16,
    string: [*]const u16,
    stringLength: u32,
    clusterMap: [*]const u16,
    textPosition: u32,
    textLength: u32,
};

pub const Rect = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
pub const Matrix = extern struct { m11: f32 = 1, m12: f32 = 0, m21: f32 = 0, m22: f32 = 1, dx: f32 = 0, dy: f32 = 0 };

pub const GlyphRunAnalysis = extern struct {
    vtbl: *const Vtbl,
    pub const Vtbl = extern struct {
        QueryInterface: *const fn () callconv(.winapi) void,
        AddRef: *const fn () callconv(.winapi) void,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetAlphaTextureBounds: *const fn (*anyopaque, u32, *Rect) callconv(.winapi) i32,
        CreateAlphaTexture: *const fn (*anyopaque, u32, *const Rect, [*]u8, u32) callconv(.winapi) i32,
    };
};

pub const IDWriteGdiInterop = extern struct {
    vtbl: *const Vtbl,
    pub const Vtbl = extern struct {
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

pub const IDWriteBitmapRenderTarget = extern struct {
    vtbl: *const Vtbl,
    pub const Vtbl = extern struct {
        QueryInterface: *const fn () callconv(.winapi) void,
        AddRef: *const fn () callconv(.winapi) void,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        DrawGlyphRun: *const fn (*anyopaque, f32, f32, u32, *const GlyphRun, ?*anyopaque, u32, ?*Rect) callconv(.winapi) i32,
        GetMemoryDC: *const fn (*anyopaque) callconv(.winapi) ?*anyopaque,
        GetPixelsPerDip: *const fn (*anyopaque) f32,
        SetPixelsPerDip: *const fn (*anyopaque, f32) callconv(.winapi) void,
        GetCurrentTransform: *const fn () callconv(.winapi) void,
        SetCurrentTransform: *const fn () callconv(.winapi) void,
        GetSize: *const fn (*anyopaque, *Rect) callconv(.winapi) i32,
        Resize: *const fn () callconv(.winapi) void,
    };
};

pub const IDWriteFactory = extern struct {
    vtbl: *const Vtbl,
    pub const Vtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
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
        CreateGlyphRunAnalysis: *const fn (*anyopaque, *const GlyphRun, f32, ?*const Matrix, u32, u32, f32, f32, *?*GlyphRunAnalysis) callconv(.winapi) i32,
    };
};

pub const BitmapInfoHeader = extern struct {
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

pub const BitmapInfo = extern struct { bmiHeader: BitmapInfoHeader = .{}, bmiColors: [1]u32 = .{0} };

pub extern "dwrite" fn DWriteCreateFactory(factory_type: u32, iid: *const GUID, factory: *?*IDWriteFactory) callconv(.winapi) i32;
pub extern "user32" fn GetDC(hwnd: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn ReleaseDC(hwnd: ?*anyopaque, dc: ?*anyopaque) callconv(.winapi) i32;
pub extern "gdi32" fn CreateCompatibleDC(hdc: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn DeleteDC(hdc: ?*anyopaque) callconv(.winapi) i32;
pub extern "gdi32" fn GetCurrentObject(hdc: ?*anyopaque, ty: u32) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn GetDIBits(hdc: ?*anyopaque, bmp: ?*anyopaque, start: u32, lines: u32, bits: ?*anyopaque, bmi: *const BitmapInfo, usage: u32) callconv(.winapi) i32;
pub extern "gdi32" fn GdiFlush() callconv(.winapi) i32;
pub extern "gdi32" fn GetBitmapBits(bmp: ?*anyopaque, count: i32, bits: ?*anyopaque) callconv(.winapi) i32;
pub extern "gdi32" fn CreateDIBSection(dc: ?*anyopaque, bmi: *const BitmapInfo, usage: u32, bits: *?*anyopaque, section: ?*anyopaque, offset: u32) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn SelectObject(dc: ?*anyopaque, obj: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn BitBlt(dst: ?*anyopaque, x: i32, y: i32, w: i32, h: i32, src: ?*anyopaque, sx: i32, sy: i32, rop: u32) callconv(.winapi) i32;
pub extern "gdi32" fn DeleteObject(obj: ?*anyopaque) callconv(.winapi) i32;
