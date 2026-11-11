//! 真实原生窗口宿主（Linux 开发宿主，X11 + 软件呈现）。
//!
//! 框架的 `platform` 保持编译期后端抽象；本文件在示例层展示“真实窗口 + 输入 +
//! 呈现”的完整路径：X11 负责窗口/键盘/鼠标，App 的软件 Surface 负责像素。
//! 无显示服务器时仍可用 `zig build run-gallery` 输出 PNG；在 Xvfb/X11 下可交互。
//!
//! 运行：zig build run-gallery-window
//! 无头验证：xvfb-run -a zig-out/bin/gallery_window --frames 5 --png /tmp/g.png

const std = @import("std");
const nano = @import("nano_gui");
const gallery = @import("gallery.zig");
const platform = nano.platform;
const core = nano.core;

const c = @import("x11");

const RealClock = struct {
    io: std.Io,
    fn now(ctx: *anyopaque) u64 {
        const self: *RealClock = @ptrCast(@alignCast(ctx));
        const ts = std.Io.Timestamp.now(self.io, .awake);
        return @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_ms));
    }
};

const Host = struct {
    display: *c.Display,
    window: c.Window,
    gc: c.GC,
    screen: c_int,
    visual: *c.Visual,
    depth: c_int,
    image: ?*c.XImage = null,
    image_data: ?[*]u8 = null,
    width: u32 = 0,
    height: u32 = 0,
    popup_win: c.Window = 0,
    popup_image: ?*c.XImage = null,
    popup_data: ?[*]u8 = null,
    popup_w: u32 = 0,
    popup_h: u32 = 0,
    popup_x: i32 = 0,
    popup_y: i32 = 0,
    wm_delete: c.Atom,
    scale: f32 = 1.0,
    running: bool = true,
    cursor: c.Cursor = 0,

    fn init(allocator: std.mem.Allocator, w: u32, h: u32, title: []const u8) !Host {
        _ = allocator;
        const dpy = c.XOpenDisplay(null) orelse return error.NoDisplay;
        const screen = c.DefaultScreen(dpy);
        const root = c.RootWindow(dpy, screen);
        const visual = c.DefaultVisual(dpy, screen);
        const depth = c.DefaultDepth(dpy, screen);
        const win = c.XCreateSimpleWindow(dpy, root, 0, 0, w, h, 0, 0, 0);
        _ = c.XStoreName(dpy, win, title.ptr);
        var size_hints = c.XSizeHints{
            .flags = c.PMinSize,
            .min_width = 400,
            .min_height = 260,
        };
        _ = c.XSetWMNormalHints(dpy, win, &size_hints);
        var host = Host{
            .display = dpy,
            .window = win,
            .gc = c.XCreateGC(dpy, win, 0, null),
            .screen = screen,
            .visual = visual,
            .depth = depth,
            .wm_delete = c.XInternAtom(dpy, "WM_DELETE_WINDOW", c.False),
        };
        _ = c.XSetWMProtocols(dpy, win, &host.wm_delete, 1);
        _ = c.XSelectInput(dpy, win, c.ExposureMask | c.StructureNotifyMask | c.PointerMotionMask |
            c.ButtonPressMask | c.ButtonReleaseMask | c.KeyPressMask | c.KeyReleaseMask |
            c.LeaveWindowMask | c.FocusChangeMask);
        host.cursor = c.XCreateFontCursor(dpy, c.XC_left_ptr);
        _ = c.XDefineCursor(dpy, win, host.cursor);
        _ = c.XMapWindow(dpy, win);
        try host.ensureImage(w, h);
        return host;
    }

    fn ensureImage(self: *Host, w: u32, h: u32) !void {
        if (self.image) |img| {
            if (img.f.destroy_image) |df| _ = df(img);
            self.image = null;
            self.image_data = null;
        }
        const data = try std.heap.c_allocator.alloc(u8, @as(usize, w) * h * 4);
        const img = c.XCreateImage(self.display, self.visual, @intCast(self.depth), c.ZPixmap, 0, @ptrCast(data.ptr), w, h, 32, 0) orelse return error.XImage;
        self.image = img;
        self.image_data = data.ptr;
        self.width = w;
        self.height = h;
    }

    fn deinit(self: *Host) void {
        self.destroyPopup();
        if (self.image) |img| {
            if (img.f.destroy_image) |df| _ = df(img);
        }
        _ = c.XFreeGC(self.display, self.gc);
        _ = c.XDestroyWindow(self.display, self.window);
        _ = c.XCloseDisplay(self.display);
    }

    fn destroyPopup(self: *Host) void {
        if (self.popup_image) |img| {
            if (img.f.destroy_image) |df| _ = df(img);
            self.popup_image = null;
            self.popup_data = null;
        }
        if (self.popup_win != 0) {
            _ = c.XDestroyWindow(self.display, self.popup_win);
            self.popup_win = 0;
        }
    }

    fn syncPopup(self: *Host, app: *nano.app.App) void {
        const rect = app.ui_state.popup_rect orelse {
            self.destroyPopup();
            return;
        };
        const w: u32 = @intCast(@max(1, rect.w));
        const h: u32 = @intCast(@max(1, rect.h));
        if (self.popup_win == 0 or self.popup_w != w or self.popup_h != h) {
            self.destroyPopup();
            var attrs = std.mem.zeroes(c.XSetWindowAttributes);
            attrs.override_redirect = c.True;
            attrs.background_pixel = 0xffffff;
            const win = c.XCreateWindow(self.display, c.RootWindow(self.display, self.screen), rect.x, rect.y, w, h, 0, @intCast(self.depth), c.InputOutput, self.visual, c.CWOverrideRedirect | c.CWBackPixel, &attrs);
            if (win == 0) return;
            self.popup_win = win;
            self.popup_w = w;
            self.popup_h = h;
            _ = c.XSelectInput(self.display, win, c.ExposureMask | c.PointerMotionMask | c.ButtonPressMask | c.ButtonReleaseMask | c.LeaveWindowMask);
            const data = std.heap.c_allocator.alloc(u8, @as(usize, w) * h * 4) catch return;
            const img = c.XCreateImage(self.display, self.visual, @intCast(self.depth), c.ZPixmap, 0, @ptrCast(data.ptr), w, h, 32, 0) orelse return;
            self.popup_image = img;
            self.popup_data = data.ptr;
            _ = c.XMapRaised(self.display, win);
        } else {
            _ = c.XMoveWindow(self.display, self.popup_win, rect.x, rect.y);
        }
        self.popup_x = rect.x;
        self.popup_y = rect.y;
        const data = self.popup_data orelse return;
        var y: u32 = 0;
        while (y < h) : (y += 1) {
            var x: u32 = 0;
            while (x < w) : (x += 1) {
                const sx: usize = @intCast(@as(i64, @intCast(rect.x)) + x);
                const sy: usize = @intCast(@as(i64, @intCast(rect.y)) + y);
                var px: u32 = 0;
                if (sx < app.surface.width and sy < app.surface.height) {
                    const o = (sy * app.surface.width + sx) * 4;
                    px = (@as(u32, app.surface.pixels[o]) << 16) | (@as(u32, app.surface.pixels[o + 1]) << 8) | app.surface.pixels[o + 2];
                }
                const oo = (@as(usize, y) * w + x) * 4;
                std.mem.writeInt(u32, data[oo .. oo + 4][0..4], px, .little);
            }
        }
        if (self.popup_image) |img| {
            _ = c.XPutImage(self.display, self.popup_win, self.gc, img, 0, 0, 0, 0, w, h);
            _ = c.XFlush(self.display);
        }
    }

    fn blit(self: *Host, pixels: []const u8, w: u32, h: u32) void {
        if (w != self.width or h != self.height) self.ensureImage(w, h) catch return;
        const data = self.image_data orelse return;
        const masks = c.Visual;
        _ = masks;
        var i: usize = 0;
        while (i < @as(usize, w) * h) : (i += 1) {
            const o = i * 4;
            const r: u32 = pixels[o];
            const g: u32 = pixels[o + 1];
            const b: u32 = pixels[o + 2];
            const px: u32 = (r << 16) | (g << 8) | b;
            std.mem.writeInt(u32, data[o .. o + 4][0..4], px, .little);
        }
        const img = self.image orelse return;
        _ = c.XPutImage(self.display, self.window, self.gc, img, 0, 0, 0, 0, w, h);
        _ = c.XFlush(self.display);
    }

    fn keyFromKeysym(ks: c.KeySym) ?platform.VirtualKey {
        return switch (ks) {
            c.XK_Return, c.XK_KP_Enter => .enter,
            c.XK_BackSpace => .backspace,
            c.XK_Tab => .tab,
            c.XK_Escape => .escape,
            c.XK_space => .space,
            c.XK_Left => .left,
            c.XK_Right => .right,
            c.XK_Up => .up,
            c.XK_Down => .down,
            c.XK_Home => .home,
            c.XK_End => .end,
            c.XK_Page_Up => .page_up,
            c.XK_Page_Down => .page_down,
            c.XK_Insert => .insert,
            c.XK_Delete => .delete,
            c.XK_Shift_L => .lshift,
            c.XK_Shift_R => .rshift,
            c.XK_Control_L => .lctrl,
            c.XK_Control_R => .rctrl,
            c.XK_Alt_L => .lalt,
            c.XK_Alt_R => .ralt,
            c.XK_Super_L => .lwin,
            c.XK_Super_R => .rwin,
            c.XK_F1 => .f1,
            c.XK_F2 => .f2,
            c.XK_F3 => .f3,
            c.XK_F4 => .f4,
            c.XK_F5 => .f5,
            c.XK_F6 => .f6,
            c.XK_F7 => .f7,
            c.XK_F8 => .f8,
            c.XK_F9 => .f9,
            c.XK_F10 => .f10,
            c.XK_F11 => .f11,
            c.XK_F12 => .f12,
            else => blk: {
                if (ks >= c.XK_a and ks <= c.XK_z) break :blk @fromBackingInt(@intCast(0x41 + (ks - c.XK_a)));
                if (ks >= c.XK_A and ks <= c.XK_Z) break :blk @fromBackingInt(@intCast(0x41 + (ks - c.XK_A)));
                if (ks >= c.XK_0 and ks <= c.XK_9) break :blk @fromBackingInt(@intCast(0x30 + (ks - c.XK_0)));
                break :blk null;
            },
        };
    }

    fn modsFromState(state: c_uint) platform.Mods {
        return .{
            .shift = (state & c.ShiftMask) != 0,
            .ctrl = (state & c.ControlMask) != 0,
            .alt = (state & c.Mod1Mask) != 0,
            .win = (state & c.Mod4Mask) != 0,
        };
    }

    fn handle(self: *Host, app: *nano.app.App, ev: *c.XEvent, ox: i32, oy: i32) void {
        switch (ev.type) {
            c.Expose => {
                app.ui_state.invalidate(.paint);
            },
            c.ConfigureNotify => {
                const w = @max(1, ev.xconfigure.width);
                const h = @max(1, ev.xconfigure.height);
                if (@as(u32, @intCast(w)) != self.width or @as(u32, @intCast(h)) != self.height) {
                    app.window.setClientSize(.{ .w = @floatFromInt(w), .h = @floatFromInt(h) });
                }
            },
            c.MotionNotify => {
                platform.Headless.injectMouseMove(.{ .x = ev.xmotion.x + ox, .y = ev.xmotion.y + oy }, modsFromState(ev.xmotion.state));
            },
            c.ButtonPress, c.ButtonRelease => {
                const down = ev.type == c.ButtonPress;
                const pos = core.Vec2i{ .x = ev.xbutton.x + ox, .y = ev.xbutton.y + oy };
                switch (ev.xbutton.button) {
                    c.Button1 => platform.Headless.injectMouseButton(.left, down, pos, modsFromState(ev.xbutton.state)),
                    c.Button2 => platform.Headless.injectMouseButton(.middle, down, pos, modsFromState(ev.xbutton.state)),
                    c.Button3 => platform.Headless.injectMouseButton(.right, down, pos, modsFromState(ev.xbutton.state)),
                    c.Button4 => if (down) platform.Headless.injectWheel(-1, pos, modsFromState(ev.xbutton.state)),
                    c.Button5 => if (down) platform.Headless.injectWheel(1, pos, modsFromState(ev.xbutton.state)),
                    else => {},
                }
            },
            c.KeyPress, c.KeyRelease => {
                const down = ev.type == c.KeyPress;
                const ks = c.XLookupKeysym(&ev.xkey, 0);
                const mods = modsFromState(ev.xkey.state);
                if (keyFromKeysym(ks)) |vk| {
                    platform.Headless.injectKey(vk, down, false, mods);
                }
                if (down and !mods.ctrl and !mods.alt and ks >= 0x20 and ks <= 0x7e) {
                    var buf = [1]u8{@intCast(ks)};
                    if (ks >= c.XK_A and ks <= c.XK_Z) buf[0] = @intCast('a' + (ks - c.XK_A));
                    platform.Headless.injectText(&buf);
                }
            },
            c.LeaveNotify => platform.Headless.inject(.mouse_leave),
            c.FocusIn => platform.Headless.setActive(true),
            c.FocusOut => platform.Headless.setActive(false),
            c.ClientMessage => {
                if (@as(c.Atom, @intCast(ev.xclient.data.l[0])) == self.wm_delete) self.running = false;
            },
            c.DestroyNotify => self.running = false,
            else => {},
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var model = try gallery.Model.init(gpa);
    defer model.deinit();
    var app = try nano.app.App.init(gpa, .{ .title = "nano_gui Widget Gallery", .size = .{ .w = 960, .h = 620 } });
    defer app.deinit();
    app.io = init.io;
    app.build_ctx = &model;
    app.build_fn = gallery.build;

    var host = Host.init(gpa, 960, 620, "nano_gui Widget Gallery") catch |e| {
        std.debug.print("gallery_window: 无法打开 X11 显示：{t}\n", .{e});
        std.process.exit(2);
    };
    defer host.deinit();

    var clock_ctx = RealClock{ .io = init.io };
    try platform.setClock(.{ .ctx = &clock_ctx, .now_ms = RealClock.now });

    // 解析 --frames / --png，便于 Xvfb 下的自动化验证。
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    var frames: ?u32 = null;
    var seconds: ?f32 = null;
    var png: ?[]const u8 = null;
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--frames")) {
            if (args.next()) |v| frames = std.fmt.parseInt(u32, v, 10) catch null;
        } else if (std.mem.eql(u8, a, "--seconds")) {
            if (args.next()) |v| seconds = std.fmt.parseFloat(f32, v) catch null;
        } else if (std.mem.eql(u8, a, "--png")) {
            png = args.next();
        } else if (std.mem.startsWith(u8, a, "--png=")) {
            png = a[6..];
        }
    }

    app.renderOnce(&model, gallery.build);
    host.blit(app.surface.pixels, app.surface.width, app.surface.height);
    host.syncPopup(&app);

    var count: u32 = 0;
    const started = std.Io.Timestamp.now(init.io, .awake);
    var ev: c.XEvent = undefined;
    while (host.running) {
        while (c.XPending(host.display) > 0) {
            _ = c.XNextEvent(host.display, &ev);
            const ox: i32 = if (host.popup_win != 0 and ev.xany.window == host.popup_win) host.popup_x else 0;
            const oy: i32 = if (host.popup_win != 0 and ev.xany.window == host.popup_win) host.popup_y else 0;
            host.handle(&app, &ev, ox, oy);
        }
        if (!host.running) break;
        if (app.step()) {
            host.blit(app.surface.pixels, app.surface.width, app.surface.height);
            host.syncPopup(&app);
        }
        count += 1;
        if (seconds) |limit| {
            const now = std.Io.Timestamp.now(init.io, .awake);
            const elapsed = @as(f64, @floatFromInt(now.nanoseconds - started.nanoseconds)) / @as(f64, std.time.ns_per_s);
            if (elapsed >= limit) break;
        }
        if (frames) |limit| {
            if (count >= limit) break;
        } else if (seconds == null and !app.ui_state.needsFrame()) {
            _ = c.XNextEvent(host.display, &ev);
            const ox: i32 = if (host.popup_win != 0 and ev.xany.window == host.popup_win) host.popup_x else 0;
            const oy: i32 = if (host.popup_win != 0 and ev.xany.window == host.popup_win) host.popup_y else 0;
            host.handle(&app, &ev, ox, oy);
        }
    }
    if (png) |p| try app.savePngIo(init.io, p);
    var buf: [128]u8 = undefined;
    const out = try std.fmt.bufPrint(&buf, "gallery_window: frames={d} nodes={d} clicks={d} passes={d} damage={d}\n", .{ app.frames, app.ui_state.node_count, model.clicks, app.ui_state.build_passes, app.ui_state.last_damage_area });
    try std.Io.File.stdout().writeStreamingAll(init.io, out);
}
