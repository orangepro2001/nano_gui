//! fontstash 字体光栅后端（REQ-ARCH-003）。
//! 仅 `src/text/` 下允许引用 fontstash 符号。

const std = @import("std");
const core = @import("../core.zig");
const gfx = @import("../gfx.zig");
const fons = @import("fontstash");
const dejavu = @import("dejavu");

pub const Backend = struct {
    ctx: ?*fons.FONScontext = null,
    w: c_int = 512,
    h: c_int = 512,
    draw_canvas: ?*gfx.Canvas = null,
    draw_color: core.Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
};

var state: Backend = .{};

pub fn init() !void {
    if (state.ctx != null) return;
    var params = fons.FONSparams{
        .width = 512,
        .height = 512,
        .flags = @intCast(fons.FONS_ZERO_TOPLEFT),
        .userPtr = null,
        .renderCreate = renderCreate,
        .renderResize = renderResize,
        .renderUpdate = renderUpdate,
        .renderDraw = renderDraw,
        .renderDelete = renderDelete,
    };
    const ctx = fons.fonsCreateInternal(&params) orelse return error.OutOfMemory;
    state.ctx = ctx;
    const font = dejavu.data;
    _ = fons.fonsAddFontMem(ctx, "sans", @constCast(font.ptr), font.len, 0, 0);
}

pub fn deinit() void {
    if (state.ctx) |ctx| fons.fonsDeleteInternal(ctx);
    state.ctx = null;
}

pub fn isReady() bool {
    return state.ctx != null;
}

pub fn setStyle(size_px: f32) void {
    const ctx = state.ctx orelse return;
    _ = fons.fonsSetFont(ctx, 0);
    fons.fonsSetSize(ctx, size_px);
    fons.fonsSetAlign(ctx, fons.FONS_ALIGN_LEFT | fons.FONS_ALIGN_TOP);
}

pub fn textWidth(size_px: f32, slice: []const u8) f32 {
    const ctx = state.ctx orelse return 0;
    setStyle(size_px);
    var bounds: [4]f32 = undefined;
    return fons.fonsTextBounds(ctx, 0, 0, slice.ptr, slice.ptr + slice.len, &bounds);
}

pub fn vertMetrics(size_px: f32) struct { ascent: f32, descent: f32, lineh: f32 } {
    const ctx = state.ctx orelse return .{ .ascent = size_px, .descent = size_px * 0.25, .lineh = @ceil(size_px * 1.25) };
    setStyle(size_px);
    var asc: f32 = 0;
    var desc: f32 = 0;
    var lineh: f32 = 0;
    fons.fonsVertMetrics(ctx, &asc, &desc, &lineh);
    return .{ .ascent = @abs(asc), .descent = @abs(desc), .lineh = @ceil(lineh) };
}

pub fn drawLine(canvas: *gfx.Canvas, size_px: f32, x: f32, y: f32, slice: []const u8, color: core.Color) void {
    const ctx = state.ctx orelse return;
    setStyle(size_px);
    state.draw_canvas = canvas;
    state.draw_color = color;
    defer state.draw_canvas = null;
    _ = fons.fonsDrawText(ctx, x, y, slice.ptr, slice.ptr + slice.len);
}

fn renderCreate(_: ?*anyopaque, w: c_int, h: c_int) callconv(.c) c_int {
    state.w = w;
    state.h = h;
    return 1;
}
fn renderResize(_: ?*anyopaque, w: c_int, h: c_int) callconv(.c) c_int {
    return renderCreate(null, w, h);
}
fn renderUpdate(_: ?*anyopaque, _: [*c]c_int, _: [*c]const u8) callconv(.c) void {}
fn renderDraw(_: ?*anyopaque, verts: [*c]const f32, tcoords: [*c]const f32, colors: [*c]const c_uint, nverts: c_int) callconv(.c) void {
    _ = colors;
    const canvas = state.draw_canvas orelse return;
    const ctx = state.ctx orelse return;
    var aw: c_int = 0;
    var ah: c_int = 0;
    const atlas_ptr = fons.fonsGetTextureData(ctx, &aw, &ah) orelse return;
    const atlas: [*]const u8 = @ptrCast(atlas_ptr);
    if (nverts < 4) return;
    var i: c_int = 0;
    while (i + 3 < nverts) : (i += 4) {
        var minx: f32 = verts[@intCast(i * 2)];
        var maxx = minx;
        var miny: f32 = verts[@intCast(i * 2 + 1)];
        var maxy = miny;
        var mins: f32 = tcoords[@intCast(i * 2)];
        var maxs = mins;
        var mint: f32 = tcoords[@intCast(i * 2 + 1)];
        var maxt = mint;
        var k: c_int = 1;
        while (k < 4) : (k += 1) {
            const idx: usize = @intCast((i + k) * 2);
            minx = @min(minx, verts[idx]);
            maxx = @max(maxx, verts[idx]);
            miny = @min(miny, verts[idx + 1]);
            maxy = @max(maxy, verts[idx + 1]);
            mins = @min(mins, tcoords[idx]);
            maxs = @max(maxs, tcoords[idx]);
            mint = @min(mint, tcoords[idx + 1]);
            maxt = @max(maxt, tcoords[idx + 1]);
        }
        const dw: i32 = @intFromFloat(@ceil(maxx - minx));
        const dh: i32 = @intFromFloat(@ceil(maxy - miny));
        const awf = @as(f32, @floatFromInt(aw));
        const ahf = @as(f32, @floatFromInt(ah));
        const sx0 = mins * awf;
        const sy0 = mint * ahf;
        const sw = @max(1.0, (maxs - mins) * awf);
        const sh = @max(1.0, (maxt - mint) * ahf);
        var yy: i32 = 0;
        while (yy < dh) : (yy += 1) {
            var xx: i32 = 0;
            while (xx < dw) : (xx += 1) {
                const sx: usize = @intFromFloat(@floor(sx0 + @as(f32, @floatFromInt(xx)) * sw / @as(f32, @floatFromInt(@max(1, dw)))));
                const sy: usize = @intFromFloat(@floor(sy0 + @as(f32, @floatFromInt(yy)) * sh / @as(f32, @floatFromInt(@max(1, dh)))));
                if (sx >= @as(usize, @intCast(aw)) or sy >= @as(usize, @intCast(ah))) continue;
                const a = atlas[sy * @as(usize, @intCast(aw)) + sx];
                if (a == 0) continue;
                canvas.blendPixel(@as(i32, @intFromFloat(@floor(minx))) + xx, @as(i32, @intFromFloat(@floor(miny))) + yy, state.draw_color, @as(f32, @floatFromInt(a)) / 255.0);
            }
        }
    }
}
fn renderDelete(_: ?*anyopaque) callconv(.c) void {}
