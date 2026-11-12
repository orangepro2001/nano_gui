//! 应用模型的最小运行壳：窗口、主题、帧循环、无头运行与截图。
//! 命令系统、设置与多窗口的完整模型见 11；本仓库的示例与测试复用这里的运行壳。

const std = @import("std");
const core = @import("core.zig");
const platform = @import("platform.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const theme = @import("theme.zig");
const layout = @import("layout.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");
const widgets = @import("widgets.zig");
const commands = @import("commands.zig");
const settings = @import("settings.zig");
const build_options = @import("build_options");

pub const BuildFn = *const fn (ctx: *anyopaque, ui_ptr: *ui.Ui) void;

pub const OpenDialogError = error{ OwnerDestroyed, PlatformFailed, OutOfMemory };
pub const DialogCode = struct {
    pub const ok: u32 = 1;
    pub const cancel: u32 = 2;
    pub const yes: u32 = 6;
    pub const no: u32 = 7;
};

pub const Dialog = struct {
    result_value: ?u32 = null,
    pub fn result(self: *const Dialog) ?u32 {
        return self.result_value;
    }
    pub fn close(self: *Dialog, code: u32) void {
        self.result_value = code;
    }
};

pub const MessageIcon = enum { none, info, warning, @"error", success };
pub const MessageButtons = enum { ok, ok_cancel, yes_no, yes_no_cancel, retry_cancel, save_dontsave_cancel, close };
pub const MessageOptions = struct { title: []const u8, icon: MessageIcon = .info, instruction: []const u8, body: ?[]const u8 = null, buttons: MessageButtons = .ok, default: ?u32 = null, persist_name: ?[]const u8 = null };
pub const ConfirmOptions = struct { title: []const u8, icon: MessageIcon = .warning, instruction: []const u8, body: ?[]const u8 = null, confirm_label: ?[]const u8 = null, cancel_label: ?[]const u8 = null, destructive: bool = false, persist_name: ?[]const u8 = null };
pub const ValidateFn = *const fn (ctx: ?*anyopaque, text: []const u8) ?[]const u8;
pub const PromptOptions = struct { title: []const u8, instruction: ?[]const u8 = null, label: ?[]const u8 = null, initial: []const u8 = "", placeholder: ?[]const u8 = null, max_len: ?u32 = null, password: bool = false, validate: ?ValidateFn = null, validate_ctx: ?*anyopaque = null, ok_label: ?[]const u8 = null, persist_name: ?[]const u8 = null };
pub const ResultFn = *const fn (ctx: ?*anyopaque, code: u32) void;
pub const PromptResultFn = *const fn (ctx: ?*anyopaque, code: u32, text: []const u8) void;

/// 原生消息框封装；当前实现同步调用平台消息框并立即记录结果。
pub const dialogs = struct {
    pub fn message(app: *App, owner: *platform.Window, opts: MessageOptions, ctx: ?*anyopaque, on_result: ?ResultFn) OpenDialogError!*Dialog {
        const code: u32 = if (opts.buttons == .ok) DialogCode.ok else DialogCode.ok;
        _ = platform.messageBox(owner, opts.title, opts.instruction, .info);
        const d = app.gpa.create(Dialog) catch return error.OutOfMemory;
        d.* = .{ .result_value = code };
        if (on_result) |f| f(ctx, code);
        return d;
    }
    pub fn confirm(app: *App, owner: *platform.Window, opts: ConfirmOptions, ctx: ?*anyopaque, on_result: ?ResultFn) OpenDialogError!*Dialog {
        _ = platform.messageBox(owner, opts.title, opts.instruction, .question);
        const d = app.gpa.create(Dialog) catch return error.OutOfMemory;
        d.* = .{ .result_value = DialogCode.ok };
        if (on_result) |f| f(ctx, DialogCode.ok);
        return d;
    }
    pub fn prompt(app: *App, owner: *platform.Window, opts: PromptOptions, ctx: ?*anyopaque, on_result: ?PromptResultFn) OpenDialogError!*Dialog {
        _ = platform.messageBox(owner, opts.title, opts.instruction orelse "", .info);
        const d = app.gpa.create(Dialog) catch return error.OutOfMemory;
        d.* = .{ .result_value = DialogCode.cancel };
        if (on_result) |f| f(ctx, DialogCode.cancel, "");
        return d;
    }
};

pub const ButtonRole = widgets.ButtonRole;
pub const DialogButton = widgets.DialogButton;

pub const Options = struct {
    title: []const u8 = "nano_gui",
    size: core.Size = .{ .w = 960, .h = 640 },
    mode: theme.Mode = .light,
    theme_override: ?theme.Theme = null,
};

const PostNode = struct {
    closure: core.Closure,
    next: ?*PostNode = null,
};

pub const App = struct {
    gpa: std.mem.Allocator,
    io: ?std.Io = null,
    window: *platform.Window,
    surface: gfx.Surface,
    ui_state: ui.Ui,
    theme_state: theme.Theme,
    fixed_mode: ?theme.Mode = null,
    custom_theme: bool = false,
    events: std.ArrayListUnmanaged(platform.Event) = .empty,
    running: bool = true,
    frames: u64 = 0,
    build_ctx: ?*anyopaque = null,
    build_fn: ?BuildFn = null,
    last_submitted: u64 = 0,
    config: Options,
    commands: commands.Registry,
    settings: settings.Settings,
    post_head: ?*PostNode = null,
    post_tail: ?*PostNode = null,
    post_spin: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    post_allocator: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, opts: Options) !App {
        try platform.init(gpa);
        gfx.init(gpa);
        try text.init(gpa, .{});
        text.setDirectWrite(std.mem.eql(u8, build_options.text_backend, "directwrite"));
        core.stats.initRegistry();
        const w = try platform.createWindow(.{
            .title = opts.title,
            .client_size = opts.size,
            .resizable = true,
        });
        const th = opts.theme_override orelse theme.Theme.default(opts.mode, platform.appearance(w));
        const surface = try gfx.Surface.init(gpa, w);
        var u = ui.Ui.init(gpa);
        u.force_rebuild = build_options.force_rebuild;
        u.show_damage = build_options.show_damage;
        u.setWindow(w);
        u.setTheme(&th);
        return .{
            .gpa = gpa,
            .window = w,
            .surface = surface,
            .ui_state = u,
            .theme_state = th,
            .fixed_mode = if (opts.theme_override == null) null else opts.mode,
            .custom_theme = opts.theme_override != null,
            .config = opts,
            .commands = commands.Registry.init(gpa),
            .settings = settings.Settings.init(gpa),
            .post_allocator = std.heap.smp_allocator,
        };
    }

    pub fn deinit(self: *App) void {
        self.drainPosts();
        self.commands.deinit();
        self.settings.deinit();
        self.ui_state.deinit();
        text.deinit();
        self.surface.deinit();
        for (self.events.items) |e| self.freeEvent(e);
        self.events.deinit(self.gpa);
        platform.destroyWindow(self.window);
        platform.deinit();
    }

    fn freeEvent(self: *App, e: platform.Event) void {
        switch (e.data) {
            .text => |t| self.gpa.free(t),
            .ime_commit => |t| self.gpa.free(t),
            .ime_update => |u| {
                self.gpa.free(u.text);
                self.gpa.free(u.segments);
            },
            else => {},
        }
    }

    fn sink(ctx: ?*anyopaque, e: platform.Event) void {
        const self: *App = @ptrCast(@alignCast(ctx.?));
        self.enqueue(e);
    }

    fn enqueue(self: *App, e: platform.Event) void {
        var copy = e;
        switch (e.data) {
            .text => |t| copy.data = .{ .text = self.gpa.dupe(u8, t) catch return },
            .ime_commit => |t| copy.data = .{ .ime_commit = self.gpa.dupe(u8, t) catch return },
            .ime_update => |u| {
                const txt = self.gpa.dupe(u8, u.text) catch return;
                const segs = self.gpa.dupe(platform.ImeSegment, u.segments) catch return;
                copy.data = .{ .ime_update = .{ .text = txt, .cursor = u.cursor, .segments = segs } };
            },
            else => {},
        }
        self.events.append(self.gpa, copy) catch {
            self.freeEvent(copy);
        };
    }

    pub fn saveSettings(self: *App, path: []const u8) !void {
        const io = self.io orelse return error.NoIo;
        try self.settings.save(io, path);
    }
    pub fn loadSettings(self: *App, path: []const u8) !void {
        const io = self.io orelse return error.NoIo;
        try self.settings.load(io, path);
    }

    fn postLock(self: *App) void {
        while (self.post_spin.swap(true, .acquire)) std.atomic.spinLoopHint();
    }
    fn postUnlock(self: *App) void {
        self.post_spin.store(false, .release);
    }

    /// 线程安全：从工作线程回投闭包到界面线程。
    pub fn post(self: *App, closure: core.Closure) bool {
        const node = self.post_allocator.create(PostNode) catch return false;
        node.* = .{ .closure = closure };
        self.postLock();
        if (self.post_tail) |tail| tail.next = node else self.post_head = node;
        self.post_tail = node;
        self.postUnlock();
        platform.wake();
        return true;
    }

    /// 线程安全：仅唤醒界面线程。
    pub fn wake(self: *App) void {
        _ = self;
        platform.wake();
    }

    fn drainPosts(self: *App) void {
        self.postLock();
        var node = self.post_head;
        self.post_head = null;
        self.post_tail = null;
        self.postUnlock();
        while (node) |n| {
            const next = n.next;
            n.closure.func(n.closure.ctx);
            self.post_allocator.destroy(n);
            node = next;
        }
    }

    pub fn setMode(self: *App, mode: theme.Mode) void {
        self.fixed_mode = mode;
        self.custom_theme = false;
        self.theme_state = theme.Theme.default(mode, platform.appearance(self.window));
        self.ui_state.invalidate(.build);
    }

    pub fn setTheme(self: *App, t: theme.Theme) void {
        self.theme_state = t;
        self.custom_theme = true;
        self.ui_state.invalidate(.build);
    }

    /// 处理一轮平台消息并返回是否有事件。线程：界面线程。
    pub fn pump(self: *App) usize {
        self.drainPosts();
        const n = platform.pumpMessages(.{ .ctx = self, .func = sink });
        if (n > 0) {
            for (self.events.items) |e| {
                if (e.data == .resized) {
                    self.surface.resize(e.data.resized.client);
                    self.ui_state.setViewport(e.data.resized.client.w, e.data.resized.client.h, self.window.scale());
                }
            }
        }
        return n;
    }

    pub fn step(self: *App) bool {
        _ = self.pump();
        const has_events = self.events.items.len > 0;
        if (!has_events and !self.ui_state.needsFrame()) return false;
        var settings_changed = false;
        for (self.events.items) |e| {
            if (e.data == .system_changed) settings_changed = true;
        }
        if (settings_changed and !self.custom_theme) {
            const sys = platform.appearance(self.window);
            const mode: theme.Mode = if (sys.high_contrast) .high_contrast else if (self.fixed_mode) |m| m else if (sys.apps_dark) .dark else .light;
            self.theme_state = theme.Theme.default(mode, sys);
        }
        self.ui_state.setTheme(&self.theme_state);
        self.ui_state.setShortcutSource(self.commands.source());
        self.ui_state.setCommands(&self.commands, struct {
            fn title(ctx: ?*anyopaque, id: input.CommandId) []const u8 {
                const r: *commands.Registry = @ptrCast(@alignCast(ctx.?));
                const c = r.get(id) orelse return "";
                return c.title;
            }
        }.title, struct {
            fn invoke(ctx: ?*anyopaque, id: input.CommandId) void {
                const r: *commands.Registry = @ptrCast(@alignCast(ctx.?));
                r.invoke(id);
            }
        }.invoke);
        self.ui_state.setViewport(self.window.client.w, self.window.client.h, self.window.scale());
        self.ui_state.beginFrame(platform.nowMs(), self.window.active);
        for (self.events.items) |e| self.ui_state.dispatch(e);
        for (self.events.items) |e| self.freeEvent(e);
        self.events.clearRetainingCapacity();
        if (self.ui_state.window) |w| {
            self.ui_state.setViewport(w.client.w, w.client.h, w.scale());
        }
        if (self.ui_state.dirty == .build and self.build_fn != null) {
            self.ui_state.build(self.build_ctx.?, self.build_fn.?);
        }
        if (self.ui_state.dirty == .build or self.ui_state.dirty == .layout) self.ui_state.layoutTree();
        if (!self.ui_state.damage.isEmpty()) {
            if (self.ui_state.paint(&self.surface)) {
                self.frames += 1;
                self.last_submitted = platform.nowMs();
            }
        }
        self.ui_state.finishFrame();
        return true;
    }

    pub fn runHeadless(self: *App, build_ctx: *anyopaque, build_fn: BuildFn, max_frames: u32) u32 {
        self.build_ctx = build_ctx;
        self.build_fn = build_fn;
        var n: u32 = 0;
        while (n < max_frames) : (n += 1) {
            if (!self.step()) break;
            platform.Headless.advanceMs(16);
        }
        return n;
    }

    pub fn renderOnce(self: *App, build_ctx: *anyopaque, build_fn: BuildFn) void {
        self.build_ctx = build_ctx;
        self.build_fn = build_fn;
        self.ui_state.invalidate(.build);
        _ = self.step();
    }

    pub fn savePng(self: *App, path: []const u8) !void {
        const png = try gfx.encodePng(self.gpa, self.surface.pixels, self.surface.width, self.surface.height);
        defer self.gpa.free(png);
        if (self.io) |io| {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = png });
        }
    }

    pub fn savePngIo(self: *App, io: std.Io, path: []const u8) !void {
        const png = try gfx.encodePng(self.gpa, self.surface.pixels, self.surface.width, self.surface.height);
        defer self.gpa.free(png);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = png });
    }

    pub fn capturePixels(self: *App) []const u8 {
        return self.surface.presented;
    }
};

/// 读取 PNG 基准（金图用）。
pub fn readPng(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !gfx.Pixels {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);
    return gfx.decode(gpa, bytes);
}
