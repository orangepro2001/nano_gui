//! OpenGL / WGL Win32 外部绑定（REQ-ARCH-003、REQ-CONV-018）。
//! 仅 `src/gfx/` 下允许引用 GL 符号。

const opengl_cc: @import("std").builtin.CallingConvention = if (@import("builtin").cpu.arch == .x86) .x86_stdcall else .c;

pub const gl_color_buffer_bit: u32 = 0x00004000;
pub const gl_unpack_alignment: u32 = 0x0CF5;
pub const gl_rgba: u32 = 0x1908;
pub const gl_unsigned_byte: u32 = 0x1401;

pub const wgl_create_context = @extern(*const fn (dc: ?*anyopaque) callconv(opengl_cc) ?*anyopaque, .{ .name = "wglCreateContext", .library_name = "opengl32" });
pub const wgl_make_current = @extern(*const fn (dc: ?*anyopaque, rc: ?*anyopaque) callconv(opengl_cc) i32, .{ .name = "wglMakeCurrent", .library_name = "opengl32" });
pub const wgl_delete_context = @extern(*const fn (rc: ?*anyopaque) callconv(opengl_cc) i32, .{ .name = "wglDeleteContext", .library_name = "opengl32" });
pub const gl_viewport = @extern(*const fn (x: i32, y: i32, w: i32, h: i32) callconv(opengl_cc) void, .{ .name = "glViewport", .library_name = "opengl32" });
pub const gl_clear_color = @extern(*const fn (r: f32, g: f32, b: f32, a: f32) callconv(opengl_cc) void, .{ .name = "glClearColor", .library_name = "opengl32" });
pub const gl_clear = @extern(*const fn (mask: u32) callconv(opengl_cc) void, .{ .name = "glClear", .library_name = "opengl32" });
pub const gl_raster_pos_2i = @extern(*const fn (x: i32, y: i32) callconv(opengl_cc) void, .{ .name = "glRasterPos2i", .library_name = "opengl32" });
pub const gl_pixel_zoom = @extern(*const fn (x: f32, y: f32) callconv(opengl_cc) void, .{ .name = "glPixelZoom", .library_name = "opengl32" });
pub const gl_draw_pixels = @extern(*const fn (w: i32, h: i32, format: u32, typ: u32, data: ?*const anyopaque) callconv(opengl_cc) void, .{ .name = "glDrawPixels", .library_name = "opengl32" });
pub const gl_pixel_storei = @extern(*const fn (pname: u32, param: i32) callconv(opengl_cc) void, .{ .name = "glPixelStorei", .library_name = "opengl32" });
