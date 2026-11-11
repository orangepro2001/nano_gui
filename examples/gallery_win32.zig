//! Win32 原生窗口宿主（交叉编译验证路径）。
//!
//! 该示例使用 Win32 User32/GDI 创建真实顶层窗口，并把 `App` 的软件 Surface 以
//! 32bpp DIB 呈现；输入事件经 Win32 消息转成平台事件。Linux 上没有 Windows
//! 运行时，因此本文件由 `zig build -Dtarget=x86_64-windows-gnu` 做交叉编译验证。

const std = @import("std");
const nano = @import("nano_gui");
const gallery = @import("gallery.zig");
const platform = nano.platform;

const win = std.os.windows;
const HWND = win.HWND;
const HINSTANCE = win.HINSTANCE;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;

const WM_DESTROY: u32 = 0x0002;
const WM_CLOSE: u32 = 0x0010;
const WM_PAINT: u32 = 0x000F;
const WM_SIZE: u32 = 0x0005;
const WM_MOUSEMOVE: u32 = 0x0200;
const WM_LBUTTONDOWN: u32 = 0x0201;
const WM_LBUTTONUP: u32 = 0x0202;
const WM_RBUTTONDOWN: u32 = 0x0204;
const WM_RBUTTONUP: u32 = 0x0205;
const WM_MBUTTONDOWN: u32 = 0x0207;
const WM_MBUTTONUP: u32 = 0x0208;
const WM_MOUSEWHEEL: u32 = 0x020A;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_CHAR: u32 = 0x0102;
const WM_TIMER: u32 = 0x0113;

const CS_HREDRAW: u32 = 0x0002;
const CS_VREDRAW: u32 = 0x0001;
const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: i32 = 5;

const WNDCLASSW = extern struct {
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT = undefined,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16 = undefined,
};
const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
const MSG = extern struct {
    hwnd: ?HWND = null,
    message: u32 = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: u32 = 0,
    pt: POINT = .{},
    lPrivate: u32 = 0,
};
const BITMAPINFOHEADER = extern struct {
    biSize: u32 = @sizeOf(BITMAPINFOHEADER),
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
const BITMAPINFO = extern struct { bmiHeader: BITMAPINFOHEADER = .{}, bmiColors: [1]u32 = .{0} };

extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
extern "user32" fn RegisterClassW(c: *const WNDCLASSW) callconv(.winapi) u16;
extern "user32" fn CreateWindowExW(ex: u32, class: [*:0]const u16, title: [*:0]const u16, style: u32, x: i32, y: i32, w: i32, h: i32, parent: ?HWND, menu: ?*anyopaque, inst: ?HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?HWND;
extern "user32" fn DefWindowProcW(h: HWND, m: u32, w: WPARAM, l: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn ShowWindow(h: HWND, cmd: i32) callconv(.winapi) i32;
extern "user32" fn UpdateWindow(h: HWND) callconv(.winapi) i32;
extern "user32" fn GetClientRect(h: HWND, r: *RECT) callconv(.winapi) i32;
extern "user32" fn GetMessageW(m: *MSG, h: ?HWND, min: u32, max: u32) callconv(.winapi) i32;
extern "user32" fn TranslateMessage(m: *const MSG) callconv(.winapi) i32;
extern "user32" fn DispatchMessageW(m: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn PostQuitMessage(code: i32) callconv(.winapi) void;
extern "user32" fn PeekMessageW(m: *MSG, h: ?HWND, min: u32, max: u32, remove: u32) callconv(.winapi) i32;
extern "user32" fn BeginPaint(h: HWND, ps: *PAINTSTRUCT) callconv(.winapi) ?*anyopaque;
extern "user32" fn EndPaint(h: HWND, ps: *const PAINTSTRUCT) callconv(.winapi) i32;
extern "user32" fn GetDC(h: HWND) callconv(.winapi) ?*anyopaque;
extern "user32" fn ReleaseDC(h: HWND, dc: ?*anyopaque) callconv(.winapi) i32;
extern "user32" fn SetTimer(h: ?HWND, id: usize, ms: u32, cb: ?*anyopaque) callconv(.winapi) usize;
extern "gdi32" fn ChoosePixelFormat(dc: ?*anyopaque, pfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
extern "gdi32" fn SetPixelFormat(dc: ?*anyopaque, fmt: i32, pfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
extern "gdi32" fn SwapBuffers(dc: ?*anyopaque) callconv(.winapi) i32;
extern "opengl32" fn wglCreateContext(dc: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "opengl32" fn wglMakeCurrent(dc: ?*anyopaque, ctx: ?*anyopaque) callconv(.winapi) i32;
extern "opengl32" fn glClearColor(r: f32, g: f32, b: f32, a: f32) callconv(.winapi) void;
extern "opengl32" fn glClear(mask: u32) callconv(.winapi) void;
extern "opengl32" fn glViewport(x: i32, y: i32, w: i32, h: i32) callconv(.winapi) void;
extern "opengl32" fn glGetString(name: u32) callconv(.winapi) ?[*:0]const u8;
extern "gdi32" fn SetDIBitsToDevice(dc: ?*anyopaque, x: i32, y: i32, w: u32, h: u32, src_x: i32, src_y: i32, start: u32, lines: u32, bits: *const anyopaque, bmi: *const BITMAPINFO, usage: u32) callconv(.winapi) i32;

const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: u16 = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: u16 = 1,
    dwFlags: u32 = 0x00000004 | 0x00000020 | 0x00000001, // DOUBLEBUFFER | DRAW_TO_WINDOW | SUPPORT_OPENGL
    iPixelType: u8 = 0,
    cColorBits: u8 = 32,
    cRedBits: u8 = 0,
    cRedShift: u8 = 0,
    cGreenBits: u8 = 0,
    cGreenShift: u8 = 0,
    cBlueBits: u8 = 0,
    cBlueShift: u8 = 0,
    cAlphaBits: u8 = 8,
    cAlphaShift: u8 = 0,
    cAccumBits: u8 = 0,
    cAccumRedBits: u8 = 0,
    cAccumGreenBits: u8 = 0,
    cAccumBlueBits: u8 = 0,
    cAccumAlphaBits: u8 = 0,
    cDepthBits: u8 = 24,
    cStencilBits: u8 = 8,
    cAuxBuffers: u8 = 0,
    iLayerType: u8 = 0,
    bReserved: u8 = 0,
    dwLayerMask: u32 = 0,
    dwVisibleMask: u32 = 0,
    dwDamageMask: u32 = 0,
};

const PAINTSTRUCT = extern struct {
    hdc: ?*anyopaque = null,
    fErase: i32 = 0,
    rcPaint: RECT = .{},
    fRestore: i32 = 0,
    fIncUpdate: i32 = 0,
    rgbReserved: [32]u8 = @splat(0),
};

var app_ptr: ?*nano.app.App = null;
var hwnd_ptr: ?HWND = null;
var pixel_buf: ?[]u8 = null;
var gl_context: ?*anyopaque = null;

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("nano_gui_win32");

fn loword(l: LPARAM) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(l))))));
}
fn hiword(l: LPARAM) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(l)) >> 16))));
}

fn blit(hwnd: HWND) void {
    const app = app_ptr orelse return;
    const w = app.surface.width;
    const h = app.surface.height;
    if (w == 0 or h == 0) return;
    const need: usize = @as(usize, w) * h * 4;
    if (pixel_buf == null or pixel_buf.?.len != need) {
        if (pixel_buf) |p| std.heap.page_allocator.free(p);
        pixel_buf = std.heap.page_allocator.alloc(u8, need) catch return;
    }
    const dst = pixel_buf.?;
    var i: usize = 0;
    while (i < @as(usize, w) * h) : (i += 1) {
        const o = i * 4;
        dst[o] = app.surface.pixels[o + 2];
        dst[o + 1] = app.surface.pixels[o + 1];
        dst[o + 2] = app.surface.pixels[o];
        dst[o + 3] = 0;
    }
    const dc = GetDC(hwnd) orelse return;
    defer _ = ReleaseDC(hwnd, dc);
    var bmi = BITMAPINFO{};
    bmi.bmiHeader.biWidth = @intCast(w);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(h));
    _ = SetDIBitsToDevice(dc, 0, 0, w, h, 0, 0, 0, h, dst.ptr, &bmi, 0);
}

fn wndProc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    const app = app_ptr;
    switch (msg) {
        WM_MOUSEMOVE => if (app) |a| {
            _ = a;
            platform.Headless.injectMouseMove(.{ .x = loword(lparam), .y = hiword(lparam) }, .{});
        },
        WM_LBUTTONDOWN, WM_LBUTTONUP => if (app != null) {
            platform.Headless.injectMouseButton(.left, msg == WM_LBUTTONDOWN, .{ .x = loword(lparam), .y = hiword(lparam) }, .{});
        },
        WM_RBUTTONDOWN, WM_RBUTTONUP => if (app != null) {
            platform.Headless.injectMouseButton(.right, msg == WM_RBUTTONDOWN, .{ .x = loword(lparam), .y = hiword(lparam) }, .{});
        },
        WM_MBUTTONDOWN, WM_MBUTTONUP => if (app != null) {
            platform.Headless.injectMouseButton(.middle, msg == WM_MBUTTONDOWN, .{ .x = loword(lparam), .y = hiword(lparam) }, .{});
        },
        WM_MOUSEWHEEL => if (app != null) {
            const delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
            platform.Headless.injectWheel(@as(f32, @floatFromInt(delta)) / 120.0, .{ .x = 0, .y = 0 }, .{});
        },
        WM_KEYDOWN => if (app != null) {
            const vk: u16 = @truncate(wparam);
            if (vk < 0x100) platform.Headless.injectKey(@fromBackingInt(@intCast(vk)), true, ((lparam >> 30) & 1) != 0, .{});
        },
        WM_KEYUP => if (app != null) {
            const vk: u16 = @truncate(wparam);
            if (vk < 0x100) platform.Headless.injectKey(@fromBackingInt(@intCast(vk)), false, false, .{});
        },
        WM_CHAR => if (app != null) {
            const cp: u21 = @intCast(wparam & 0xFFFF);
            if (cp >= 0x20 and cp != 0x7F) {
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &buf) catch 0;
                if (n > 0) platform.Headless.injectText(buf[0..n]);
            }
        },
        WM_SIZE => if (app) |a| {
            var r: RECT = .{};
            _ = GetClientRect(hwnd, &r);
            a.window.setClientSize(.{ .w = @floatFromInt(r.right - r.left), .h = @floatFromInt(r.bottom - r.top) });
            _ = a.step();
            blit(hwnd);
        },
        WM_PAINT => {
            var ps: PAINTSTRUCT = .{};
            _ = BeginPaint(hwnd, &ps);
            if (app) |a| {
                _ = a.step();
                if (gl_context != null) {
                    glViewport(0, 0, @intCast(a.surface.width), @intCast(a.surface.height));
                    glClearColor(0.12, 0.12, 0.14, 1.0);
                    glClear(0x00004000); // GL_COLOR_BUFFER_BIT
                }
                blit(hwnd);
            }
            _ = EndPaint(hwnd, &ps);
            return 0;
        },
        WM_TIMER => if (app) |a| {
            _ = a.step();
            blit(hwnd);
        },
        WM_CLOSE => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

extern "user32" fn DestroyWindow(h: HWND) callconv(.winapi) i32;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var gl_info = false;
    {
        var a = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
        defer a.deinit();
        _ = a.next();
        while (a.next()) |arg| {
            if (std.mem.eql(u8, arg, "--gl-info")) gl_info = true;
        }
    }
    var model = try gallery.Model.init(gpa);
    defer model.deinit();
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Widget Gallery", .size = .{ .w = 960, .h = 620 } });
    defer app.deinit();
    app.io = init.io;
    app_ptr = &app;

    const inst = GetModuleHandleW(null);
    const wc = WNDCLASSW{
        .style = CS_HREDRAW | CS_VREDRAW,
        .lpfnWndProc = wndProc,
        .hInstance = inst,
        .lpszClassName = class_name,
    };
    _ = RegisterClassW(&wc);
    const hwnd = CreateWindowExW(0, class_name, std.unicode.utf8ToUtf16LeStringLiteral("nano_gui Widget Gallery"), WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 960, 620, null, null, inst, null) orelse return error.CreateWindowFailed;
    hwnd_ptr = hwnd;
    _ = ShowWindow(hwnd, SW_SHOW);
    _ = UpdateWindow(hwnd);
    _ = SetTimer(hwnd, 1, 16, null);

    // OpenGL 上下文路径（ADR 0002）：像素格式 + WGL 上下文；NanoVG 的 C 源码
    // vendoring 尚未在此仓库存在，因此当前呈现仍由软件 Surface/GDI 完成。
    const dc = GetDC(hwnd);
    if (dc) |d| {
        var pfd = PIXELFORMATDESCRIPTOR{};
        const fmt = ChoosePixelFormat(d, &pfd);
        if (fmt != 0 and SetPixelFormat(d, fmt, &pfd) != 0) {
            gl_context = wglCreateContext(d);
            if (gl_context != null) _ = wglMakeCurrent(d, gl_context);
        }
        _ = ReleaseDC(hwnd, d);
    }

    if (gl_info) {
        if (gl_context != null) {
            const ver = glGetString(0x1F02) orelse "unknown";
            const vendor = glGetString(0x1F00) orelse "unknown";
            const renderer = glGetString(0x1F01) orelse "unknown";
            std.debug.print("GL_VERSION={s}\nGL_VENDOR={s}\nGL_RENDERER={s}\n", .{ ver, vendor, renderer });
        } else {
            std.debug.print("GL_VERSION=unavailable\n", .{});
        }
        return;
    }

    app.renderOnce(&model, gallery.build);
    blit(hwnd);

    var msg: MSG = .{};
    while (GetMessageW(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }
}
