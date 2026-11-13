//! NanoVG/GL 后端表面桥接（M1/Windows 生产路径；REQ-ARCH-003）。
//! 仅 `src/gfx/` 下允许出现 NanoVG 与 GL 符号。

const std = @import("std");
const builtin = @import("builtin");
const core = @import("../core.zig");
const platform = @import("../platform.zig");
const gl_win = if (builtin.os.tag == .windows) @import("gl_bindings.zig") else struct {};

const nvg_win = if (builtin.os.tag == .windows) @import("nanovg_win32") else struct {};

pub const GlHooks = struct {
    ctx: *anyopaque,
    fill_rect: *const fn (ctx: *anyopaque, r: core.Rect, color: core.Color) void,
    fill_rect_v: *const fn (ctx: *anyopaque, r: core.Rect, top: core.Color, bottom: core.Color) void,
    fill_round_rect: *const fn (ctx: *anyopaque, r: core.Rect, radius: f32, color: core.Color) void,
    fill_round_rect_v: *const fn (ctx: *anyopaque, r: core.Rect, radius: f32, top: core.Color, bottom: core.Color) void,
    stroke_rect: *const fn (ctx: *anyopaque, r: core.Rect, color: core.Color, width: i32) void,
    stroke_round_rect: *const fn (ctx: *anyopaque, r: core.Rect, radius: f32, color: core.Color, width: i32) void,
    stroke_line: *const fn (ctx: *anyopaque, a: core.Vec2, b: core.Vec2, color: core.Color, width: i32) void,
    push_clip: *const fn (ctx: *anyopaque, r: core.Rect) void,
    pop_clip: *const fn (ctx: *anyopaque) void,
    push_translate: *const fn (ctx: *anyopaque, dx: f32, dy: f32) void,
    pop_transform: *const fn (ctx: *anyopaque) void,
};

pub const GlSurface = struct {
    ctx: *anyopaque,
    canvas: GlHooks,
    begin: *const fn (ctx: *anyopaque, damage: core.RectI, scale: f32) void,
    end: *const fn (ctx: *anyopaque) void,
    present: *const fn (ctx: *anyopaque) void,
    resize: ?*const fn (ctx: *anyopaque, w: u32, h: u32, scale: f32) void = null,
    read: ?*const fn (ctx: *anyopaque, rect: core.RectI, out: []u8) bool = null,
    deinit: ?*const fn (ctx: *anyopaque) void = null,
};

/// 尝试为 Windows 窗口初始化 NanoVG/GL3 表面；失败或非 Windows 返回 null。线程：界面线程。
pub fn tryInitWin32Surface(window: *platform.Window) ?GlSurface {
    if (comptime builtin.os.tag != .windows) return null;
    if (window.hdc) |dc| {
        if (window.hglrc == null) {
            if (gl_win.wgl_create_context(dc)) |rc| {
                if (gl_win.wgl_make_current(dc, rc) != 0) {
                    window.hglrc = rc;
                    window.gl_ready = true;
                    window.gl_deinit_fn = deinitWin32Gl;
                    window.gl_present_fn = presentWin32Gl;
                } else {
                    _ = gl_win.wgl_delete_context(rc);
                }
            }
        }
    }
    if (window.hdc == null or nvg_win.nvg_win32_init(window.hdc.?, window.client.w, window.client.h) == 0) return null;
    window.nanovg_surface = true;
    return .{
        .ctx = window,
        .canvas = .{
            .ctx = window,
            .fill_rect = winFill,
            .fill_rect_v = winFillV,
            .fill_round_rect = winFillRound,
            .fill_round_rect_v = winFillRoundV,
            .stroke_rect = winStrokeRect,
            .stroke_round_rect = winStrokeRound,
            .stroke_line = winStrokeLine,
            .push_clip = winPushClip,
            .pop_clip = winPopClip,
            .push_translate = winTranslate,
            .pop_transform = winPopTransform,
        },
        .begin = winBegin,
        .end = winEnd,
        .present = winPresent,
        .resize = winResize,
        .deinit = winDeinit,
    };
}

fn deinitWin32Gl(dc: *anyopaque, rc: *anyopaque) void {
    if (comptime builtin.os.tag != .windows) return;
    _ = gl_win.wgl_make_current(dc, null);
    _ = gl_win.wgl_delete_context(rc);
}
fn presentWin32Gl(dc: *anyopaque, rc: *anyopaque, w: u32, h: u32, rgba: []const u8) bool {
    if (comptime builtin.os.tag != .windows) return false;
    if (gl_win.wgl_make_current(dc, rc) == 0) return false;
    gl_win.gl_viewport(0, 0, @intCast(w), @intCast(h));
    gl_win.gl_clear_color(0.925, 0.933, 0.945, 1.0);
    gl_win.gl_clear(gl_win.gl_color_buffer_bit);
    gl_win.gl_pixel_storei(gl_win.gl_unpack_alignment, 1);
    gl_win.gl_raster_pos_2i(0, @intCast(h - 1));
    gl_win.gl_pixel_zoom(1, -1);
    gl_win.gl_draw_pixels(@intCast(w), @intCast(h), gl_win.gl_rgba, gl_win.gl_unsigned_byte, rgba.ptr);
    return true;
}

fn winWin(ctx: *anyopaque) *platform.Window {
    return @ptrCast(@alignCast(ctx));
}
fn winFill(ctx: *anyopaque, r: core.Rect, c: core.Color) void {
    _ = ctx;
    nvg_win.nvg_win32_fill(r.x, r.y, r.w, r.h, c.r, c.g, c.b, c.a);
}
fn winFillV(ctx: *anyopaque, r: core.Rect, t: core.Color, b: core.Color) void {
    _ = ctx;
    nvg_win.nvg_win32_fill_v(r.x, r.y, r.w, r.h, t.r, t.g, t.b, t.a, b.r, b.g, b.b, b.a);
}
fn winFillRound(ctx: *anyopaque, r: core.Rect, rad: f32, c: core.Color) void {
    _ = ctx;
    nvg_win.nvg_win32_fill_round(r.x, r.y, r.w, r.h, rad, c.r, c.g, c.b, c.a);
}
fn winFillRoundV(ctx: *anyopaque, r: core.Rect, rad: f32, t: core.Color, b: core.Color) void {
    _ = ctx;
    nvg_win.nvg_win32_fill_round_v(r.x, r.y, r.w, r.h, rad, t.r, t.g, t.b, t.a, b.r, b.g, b.b, b.a);
}
fn winStrokeRect(ctx: *anyopaque, r: core.Rect, c: core.Color, width: i32) void {
    _ = ctx;
    nvg_win.nvg_win32_stroke_rect(r.x, r.y, r.w, r.h, c.r, c.g, c.b, c.a, width);
}
fn winStrokeRound(ctx: *anyopaque, r: core.Rect, rad: f32, c: core.Color, width: i32) void {
    _ = ctx;
    nvg_win.nvg_win32_stroke_round(r.x, r.y, r.w, r.h, rad, c.r, c.g, c.b, c.a, width);
}
fn winStrokeLine(ctx: *anyopaque, a: core.Vec2, b: core.Vec2, c: core.Color, width: i32) void {
    _ = ctx;
    nvg_win.nvg_win32_stroke_line(a.x, a.y, b.x, b.y, c.r, c.g, c.b, c.a, width);
}
fn winPushClip(ctx: *anyopaque, r: core.Rect) void {
    _ = ctx;
    nvg_win.nvg_win32_push_clip(r.x, r.y, r.w, r.h);
}
fn winPopClip(ctx: *anyopaque) void {
    _ = ctx;
    nvg_win.nvg_win32_pop();
}
fn winTranslate(ctx: *anyopaque, dx: f32, dy: f32) void {
    _ = ctx;
    nvg_win.nvg_win32_translate(dx, dy);
}
fn winPopTransform(ctx: *anyopaque) void {
    _ = ctx;
    nvg_win.nvg_win32_pop();
}
fn winBegin(ctx: *anyopaque, _: core.RectI, _: f32) void {
    const w = winWin(ctx);
    nvg_win.nvg_win32_begin(w.client.w, w.client.h);
}
fn winEnd(ctx: *anyopaque) void {
    _ = ctx;
    nvg_win.nvg_win32_end();
}
fn winPresent(ctx: *anyopaque) void {
    const w = winWin(ctx);
    nvg_win.nvg_win32_present(w.client.w, w.client.h);
}
fn winResize(ctx: *anyopaque, nw: u32, nh: u32, _: f32) void {
    _ = ctx;
    _ = nvg_win.nvg_win32_resize(@intCast(nw), @intCast(nh));
}
fn winDeinit(ctx: *anyopaque) void {
    const w = winWin(ctx);
    nvg_win.nvg_win32_shutdown();
    w.nanovg_surface = false;
}
