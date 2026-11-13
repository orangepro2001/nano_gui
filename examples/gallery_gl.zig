//! NanoVG + OpenGL 3.3 的 `gfx.Surface` 后端验证（Linux/Xvfb 使用 Mesa llvmpipe）。
//! 通过持久 FBO 离屏目标渲染三帧，再由 Surface.present 同步到默认帧缓冲。

const std = @import("std");
const nano = @import("nano_gui");
const c = @import("gl_headers");
const core = nano.core;

const W: c_int = 360;
const H: c_int = 220;

const GlCtx = struct {
    nvg: *c.NVGcontext,
    win: *c.GLFWwindow,
    fbo: c.GLuint = 0,
    tex: c.GLuint = 0,
    rb: c.GLuint = 0,
    w: c_int = W,
    h: c_int = H,
};

fn nvgOf(ctx: *anyopaque) *c.NVGcontext {
    return (@as(*GlCtx, @ptrCast(@alignCast(ctx)))).nvg;
}
fn col(cv: core.Color) c.NVGcolor {
    return c.nvgRGBA(cv.r, cv.g, cv.b, cv.a);
}
fn hFill(ctx: *anyopaque, r: core.Rect, color: core.Color) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgRect(n, r.x, r.y, r.w, r.h);
    c.nvgFillColor(n, col(color));
    c.nvgFill(n);
}
fn hFillV(ctx: *anyopaque, r: core.Rect, top: core.Color, bottom: core.Color) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgRect(n, r.x, r.y, r.w, r.h);
    const paint = c.nvgLinearGradient(n, r.x, r.y, r.x, r.y + r.h, col(top), col(bottom));
    c.nvgFillPaint(n, paint);
    c.nvgFill(n);
}
fn hFillRound(ctx: *anyopaque, r: core.Rect, radius: f32, color: core.Color) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgRoundedRect(n, r.x, r.y, r.w, r.h, radius);
    c.nvgFillColor(n, col(color));
    c.nvgFill(n);
}
fn hFillRoundV(ctx: *anyopaque, r: core.Rect, radius: f32, top: core.Color, bottom: core.Color) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgRoundedRect(n, r.x, r.y, r.w, r.h, radius);
    const paint = c.nvgLinearGradient(n, r.x, r.y, r.x, r.y + r.h, col(top), col(bottom));
    c.nvgFillPaint(n, paint);
    c.nvgFill(n);
}
fn hStrokeRect(ctx: *anyopaque, r: core.Rect, color: core.Color, width: i32) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgRect(n, r.x, r.y, r.w, r.h);
    c.nvgStrokeColor(n, col(color));
    c.nvgStrokeWidth(n, @floatFromInt(@max(1, width)));
    c.nvgStroke(n);
}
fn hStrokeRound(ctx: *anyopaque, r: core.Rect, radius: f32, color: core.Color, width: i32) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgRoundedRect(n, r.x, r.y, r.w, r.h, radius);
    c.nvgStrokeColor(n, col(color));
    c.nvgStrokeWidth(n, @floatFromInt(@max(1, width)));
    c.nvgStroke(n);
}
fn hStrokeLine(ctx: *anyopaque, a: core.Vec2, b: core.Vec2, color: core.Color, width: i32) void {
    const n = nvgOf(ctx);
    c.nvgBeginPath(n);
    c.nvgMoveTo(n, a.x, a.y);
    c.nvgLineTo(n, b.x, b.y);
    c.nvgStrokeColor(n, col(color));
    c.nvgStrokeWidth(n, @floatFromInt(@max(1, width)));
    c.nvgStroke(n);
}
fn hPushClip(ctx: *anyopaque, r: core.Rect) void {
    const n = nvgOf(ctx);
    c.nvgSave(n);
    c.nvgScissor(n, r.x, r.y, r.w, r.h);
}
fn hPopClip(ctx: *anyopaque) void {
    c.nvgRestore(nvgOf(ctx));
}
fn hPushTranslate(ctx: *anyopaque, dx: f32, dy: f32) void {
    const n = nvgOf(ctx);
    c.nvgSave(n);
    c.nvgTranslate(n, dx, dy);
}
fn hPopTransform(ctx: *anyopaque) void {
    c.nvgRestore(nvgOf(ctx));
}

fn makeFbo(g: *GlCtx) !void {
    c.glGenFramebuffers().?(1, &g.fbo);
    c.glBindFramebuffer().?(c.GL_FRAMEBUFFER, g.fbo);
    c.glGenTextures(1, &g.tex);
    c.glBindTexture(c.GL_TEXTURE_2D, g.tex);
    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA8, g.w, g.h, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    c.glFramebufferTexture2D().?(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, g.tex, 0);
    c.glGenRenderbuffers().?(1, &g.rb);
    c.glBindRenderbuffer().?(c.GL_RENDERBUFFER, g.rb);
    c.glRenderbufferStorage().?(c.GL_RENDERBUFFER, c.GL_DEPTH24_STENCIL8, g.w, g.h);
    c.glFramebufferRenderbuffer().?(c.GL_FRAMEBUFFER, c.GL_DEPTH_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, g.rb);
    if (c.glCheckFramebufferStatus().?(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
}

fn destroyFbo(g: *GlCtx) void {
    if (g.rb != 0) c.glDeleteRenderbuffers().?(1, &g.rb);
    if (g.tex != 0) c.glDeleteTextures(1, &g.tex);
    if (g.fbo != 0) c.glDeleteFramebuffers().?(1, &g.fbo);
}

fn begin(ctx: *anyopaque, damage: core.RectI, scale: f32) void {
    _ = damage;
    _ = scale;
    const g: *GlCtx = @ptrCast(@alignCast(ctx));
    c.glBindFramebuffer().?(c.GL_FRAMEBUFFER, g.fbo);
    c.glViewport(0, 0, g.w, g.h);
    c.glClearColor(0.925, 0.933, 0.945, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    c.nvgBeginFrame(g.nvg, @floatFromInt(g.w), @floatFromInt(g.h), 1.0);
}
fn end(ctx: *anyopaque) void {
    const g: *GlCtx = @ptrCast(@alignCast(ctx));
    c.nvgEndFrame(g.nvg);
}
fn present(ctx: *anyopaque) void {
    const g: *GlCtx = @ptrCast(@alignCast(ctx));
    c.glBindFramebuffer().?(c.GL_DRAW_FRAMEBUFFER, 0);
    c.glBlitFramebuffer().?(0, 0, g.w, g.h, 0, 0, g.w, g.h, c.GL_COLOR_BUFFER_BIT, c.GL_NEAREST);
    c.glfwSwapBuffers(g.win);
}
fn read(ctx: *anyopaque, rect: core.RectI, out: []u8) bool {
    const g: *GlCtx = @ptrCast(@alignCast(ctx));
    const need: usize = @as(usize, @intCast(rect.w)) * @as(usize, @intCast(rect.h)) * 4;
    if (out.len < need) return false;
    c.glBindFramebuffer().?(c.GL_READ_FRAMEBUFFER, g.fbo);
    c.glReadPixels(rect.x, rect.y, rect.w, rect.h, c.GL_RGBA, c.GL_UNSIGNED_BYTE, out.ptr);
    c.glBindFramebuffer().?(c.GL_READ_FRAMEBUFFER, 0);
    return true;
}
fn deinitGl(ctx: *anyopaque) void {
    const g: *GlCtx = @ptrCast(@alignCast(ctx));
    destroyFbo(g);
}
fn checkGlfw(ok: c_int) !void {
    if (ok == 0) return error.GlfwFailed;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    var out: []const u8 = "artifacts/nanovg-gl3.png";
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--png")) {
            if (args.next()) |p| out = p;
        }
    }

    try checkGlfw(c.glfwInit());
    defer c.glfwTerminate();
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);
    const win = c.glfwCreateWindow(W, H, "nano_gui gfx.Surface NanoVG GL3", null, null) orelse return error.WindowFailed;
    defer c.glfwDestroyWindow(win);
    c.glfwMakeContextCurrent(win);
    c.glfwSwapInterval(1);
    if (c.glewInit() != c.GLEW_OK) return error.GlewFailed;

    const nvg = c.nvgCreateGL3(c.NVG_ANTIALIAS | c.NVG_STENCIL_STROKES) orelse return error.NanoVGFailed;
    defer c.nvgDeleteGL3(nvg);
    _ = c.nvgCreateFont(nvg, "sans", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf");

    var g = GlCtx{ .nvg = nvg, .win = win };
    try makeFbo(&g);
    var surface = nano.gfx.Surface.initGl(gpa, @intCast(W), @intCast(H), 1.0, .{
        .ctx = &g,
        .canvas = .{
            .ctx = &g,
            .fill_rect = hFill,
            .fill_rect_v = hFillV,
            .fill_round_rect = hFillRound,
            .fill_round_rect_v = hFillRoundV,
            .stroke_rect = hStrokeRect,
            .stroke_round_rect = hStrokeRound,
            .stroke_line = hStrokeLine,
            .push_clip = hPushClip,
            .pop_clip = hPopClip,
            .push_translate = hPushTranslate,
            .pop_transform = hPopTransform,
        },
        .begin = begin,
        .end = end,
        .present = present,
        .read = read,
        .deinit = deinitGl,
    });
    defer surface.deinit();

    var frame: usize = 0;
    while (frame < 3) : (frame += 1) {
        const canvas = surface.beginFrame(.{ .x = 0, .y = 0, .w = W, .h = H }, 1.0);
        var th = nano.theme.Theme.default(.light, .{});
        var dctx = nano.theme.DrawCtx{ .canvas = canvas, .theme = &th, .scale = 1.0 };
        nano.theme.drawRaised(&dctx, .{ .x = 20, .y = 20, .w = 200, .h = 80 }, .radius_control, .accent, .{ .hovered = false, .pressed = false, .focused_visible = false, .hover_t = 0, .press_t = 0, .focus_t = 0 });
        nano.theme.drawPanel(&dctx, .{ .x = 20, .y = 120, .w = 320, .h = 70 }, .radius_container);
        nano.theme.drawMark(&dctx, .check, .{ .x = 260, .y = 44, .w = 28, .h = 28 }, .text_primary);
        const style = th.fonts.get(.body);
        const owned = try nano.text.layoutOwned(gpa, "gfx.Surface / NanoVG GL3 / persistent FBO", style, 1.0, .{});
        defer owned.layout.deinit();
        nano.text.draw(canvas, owned.layout, .{ .x = 34, .y = 176 }, th.color(.text_primary), .{});
        surface.endFrame();
        surface.present();
    }
    c.glFinish();

    const n: usize = @as(usize, @intCast(W)) * @as(usize, @intCast(H)) * 4;
    const rgba = try gpa.alloc(u8, n);
    defer gpa.free(rgba);
    try surface.readPixels(.{ .x = 0, .y = 0, .w = W, .h = H }, .target, rgba);
    var y: usize = 0;
    while (y < H / 2) : (y += 1) {
        const a = y * @as(usize, @intCast(W)) * 4;
        const b = (@as(usize, @intCast(H)) - 1 - y) * @as(usize, @intCast(W)) * 4;
        var i: usize = 0;
        while (i < @as(usize, @intCast(W)) * 4) : (i += 1) {
            const tmp = rgba[a + i];
            rgba[a + i] = rgba[b + i];
            rgba[b + i] = tmp;
        }
    }
    const png = try nano.gfx.encodePng(gpa, rgba, @intCast(W), @intCast(H));
    defer gpa.free(png);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = png });
    var buf: [320]u8 = undefined;
    const ver = if (c.glGetString(c.GL_VERSION)) |p| std.mem.span(p) else "unknown";
    const line = try std.fmt.bufPrint(&buf, "gfx-surface-gl3: wrote {s} ({d}x{d}, GL_VERSION={s})\n", .{ out, W, H, ver });
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}
