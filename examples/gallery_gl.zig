//! NanoVG + OpenGL 3.3 渲染验证（Linux/Xvfb 使用 Mesa llvmpipe）。
//! 该示例是 GL3 后端的首个真实路径：创建 GLFW 上下文、NanoVG GL3 上下文，
//! 绘制圆角矩形/圆形/文字并读回像素写 PNG。

const std = @import("std");
const nano = @import("nano_gui");
const c = @import("gl_headers");

const W: c_int = 360;
const H: c_int = 220;

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
    const win = c.glfwCreateWindow(W, H, "nano_gui NanoVG GL3", null, null) orelse return error.WindowFailed;
    defer c.glfwDestroyWindow(win);
    c.glfwMakeContextCurrent(win);
    c.glfwSwapInterval(1);
    if (c.glewInit() != c.GLEW_OK) return error.GlewFailed;

    const nvg = c.nvgCreateGL3(c.NVG_ANTIALIAS | c.NVG_STENCIL_STROKES) orelse return error.NanoVGFailed;
    defer c.nvgDeleteGL3(nvg);
    _ = c.nvgCreateFont(nvg, "sans", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf");

    var frame: usize = 0;
    while (frame < 3) : (frame += 1) {
        c.glViewport(0, 0, W, H);
        c.glClearColor(0.925, 0.933, 0.945, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        c.nvgBeginFrame(nvg, @floatFromInt(W), @floatFromInt(H), 1.0);
        c.nvgBeginPath(nvg);
        c.nvgRoundedRect(nvg, 20, 20, 200, 80, 6);
        c.nvgFillColor(nvg, c.nvgRGBA(47, 110, 223, 255));
        c.nvgFill(nvg);
        c.nvgBeginPath(nvg);
        c.nvgCircle(nvg, 300, 60, 30);
        c.nvgFillColor(nvg, c.nvgRGBA(31, 89, 198, 255));
        c.nvgFill(nvg);
        c.nvgBeginPath(nvg);
        c.nvgRoundedRect(nvg, 20, 120, 320, 70, 5);
        c.nvgFillColor(nvg, c.nvgRGBA(249, 250, 251, 255));
        c.nvgFill(nvg);
        c.nvgStrokeColor(nvg, c.nvgRGBA(154, 161, 171, 255));
        c.nvgStrokeWidth(nvg, 1.0);
        c.nvgStroke(nvg);

        c.nvgFontFace(nvg, "sans");
        c.nvgFontSize(nvg, 18);
        c.nvgTextAlign(nvg, c.NVG_ALIGN_LEFT | c.NVG_ALIGN_MIDDLE);
        c.nvgFillColor(nvg, c.nvgRGBA(27, 31, 36, 255));
        const msg = "NanoVG GL3 / OpenGL 3.3";
        _ = c.nvgText(nvg, 34, 155, msg.ptr, null);
        c.nvgEndFrame(nvg);
        c.glfwSwapBuffers(win);
    }

    const n: usize = @as(usize, @intCast(W)) * @as(usize, @intCast(H)) * 4;
    const rgba = try gpa.alloc(u8, n);
    defer gpa.free(rgba);
    c.glReadPixels(0, 0, W, H, c.GL_RGBA, c.GL_UNSIGNED_BYTE, rgba.ptr);
    // OpenGL 原点在左下，PNG 需要从上到下。
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
    var buf: [256]u8 = undefined;
    const ver = if (c.glGetString(c.GL_VERSION)) |p| std.mem.span(p) else "unknown";
    const line = try std.fmt.bufPrint(&buf, "nanovg-gl3: wrote {s} ({d}x{d}, GL_VERSION={s})\n", .{ out, W, H, ver });
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}
