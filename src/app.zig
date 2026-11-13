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
pub const commands = @import("app/commands.zig");
pub const settings = @import("app/settings.zig");
const build_options = @import("build_options");

// ---------------------------------------------------------------------------
// 应用标识、内建字符串与命令行（REQ-APP-001、042、043）
// ---------------------------------------------------------------------------

pub const AppId = struct { vendor: []const u8, name: []const u8 };
pub const AppIdError = error{InvalidAppId};

fn validAppIdPart(part: []const u8) bool {
    if (part.len == 0 or part.len > 64) return false;
    if (part[part.len - 1] == ' ' or part[part.len - 1] == '.') return false;
    for (part) |c| {
        if (c < 0x20 or c == 0x7F) return false;
        if (c == '/' or c == '\\' or c == ':' or c == '<' or c == '>' or c == '"' or c == '|' or c == '?' or c == '*') return false;
    }
    // Windows 保留设备名（不区分大小写，含扩展名前的基名）。
    const dot = std.mem.indexOfScalar(u8, part, '.') orelse part.len;
    const base = part[0..dot];
    const reserved = [_][]const u8{ "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9" };
    for (reserved) |r| {
        if (std.ascii.eqlIgnoreCase(base, r)) return false;
    }
    return true;
}

pub fn validateAppId(id: AppId) AppIdError!void {
    if (!validAppIdPart(id.vendor) or !validAppIdPart(id.name)) return error.InvalidAppId;
}

pub const KeyNames = struct {
    ctrl: []const u8 = "Ctrl",
    alt: []const u8 = "Alt",
    shift: []const u8 = "Shift",
    win: []const u8 = "Win",
    enter: []const u8 = "Enter",
    esc: []const u8 = "Esc",
    del: []const u8 = "Del",
    ins: []const u8 = "Ins",
    home: []const u8 = "Home",
    end: []const u8 = "End",
    pg_up: []const u8 = "PgUp",
    pg_dn: []const u8 = "PgDn",
    space: []const u8 = "Space",
    tab: []const u8 = "Tab",
    backspace: []const u8 = "Backspace",
    left: []const u8 = "Left",
    up: []const u8 = "Up",
    right: []const u8 = "Right",
    down: []const u8 = "Down",
    menu: []const u8 = "Menu",
    function_prefix: []const u8 = "F",
};

pub const Strings = struct {
    ok: []const u8,
    cancel: []const u8,
    yes: []const u8,
    no: []const u8,
    retry: []const u8,
    close: []const u8,
    apply: []const u8,
    save: []const u8,
    dont_save: []const u8,
    edit_undo: []const u8,
    edit_redo: []const u8,
    edit_cut: []const u8,
    edit_copy: []const u8,
    edit_paste: []const u8,
    edit_delete: []const u8,
    edit_select_all: []const u8,
    truncated_tooltip_prefix: []const u8,
    clear: []const u8,
    severity_info: []const u8,
    severity_warning: []const u8,
    severity_error: []const u8,
    key_names: KeyNames,

    pub const zh_cn = Strings{
        .ok = "确定",
        .cancel = "取消",
        .yes = "是",
        .no = "否",
        .retry = "重试",
        .close = "关闭",
        .apply = "应用",
        .save = "保存",
        .dont_save = "不保存",
        .edit_undo = "撤销",
        .edit_redo = "重做",
        .edit_cut = "剪切",
        .edit_copy = "复制",
        .edit_paste = "粘贴",
        .edit_delete = "删除",
        .edit_select_all = "全选",
        .truncated_tooltip_prefix = "完整文本：",
        .clear = "清除",
        .severity_info = "信息",
        .severity_warning = "警告",
        .severity_error = "错误",
        .key_names = .{},
    };

    pub const en = Strings{
        .ok = "OK",
        .cancel = "Cancel",
        .yes = "Yes",
        .no = "No",
        .retry = "Retry",
        .close = "Close",
        .apply = "Apply",
        .save = "Save",
        .dont_save = "Don't Save",
        .edit_undo = "Undo",
        .edit_redo = "Redo",
        .edit_cut = "Cut",
        .edit_copy = "Copy",
        .edit_paste = "Paste",
        .edit_delete = "Delete",
        .edit_select_all = "Select All",
        .truncated_tooltip_prefix = "Full text: ",
        .clear = "Clear",
        .severity_info = "Information",
        .severity_warning = "Warning",
        .severity_error = "Error",
        .key_names = .{},
    };
};

/// 系统界面语言首项选择字符串表（REQ-APP-042）。
pub fn stringsForLocale(locale: []const u8) *const Strings {
    if (std.mem.startsWith(u8, locale, "zh-Hans") or std.mem.startsWith(u8, locale, "zh-CN") or
        std.mem.startsWith(u8, locale, "zh-SG") or std.mem.startsWith(u8, locale, "zh_CN") or
        std.mem.startsWith(u8, locale, "zh_SG"))
    {
        return &Strings.zh_cn;
    }
    return &Strings.en;
}

/// 按 Windows CommandLineToArgvW 的引号/反斜杠规则拆分命令行（REQ-APP-043）。
pub const Args = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn deinit(self: *Args) void {
        for (self.items.items) |a| self.allocator.free(a);
        self.items.deinit(self.allocator);
    }
    pub fn slice(self: *const Args) []const []const u8 {
        return @ptrCast(self.items.items);
    }
};

pub fn parseCommandLine(allocator: std.mem.Allocator, line: []const u8) !Args {
    var out = Args{ .allocator = allocator };
    errdefer out.deinit();
    var i: usize = 0;
    while (i < line.len) {
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
        if (i >= line.len) break;
        var buf = std.ArrayListUnmanaged(u8).empty;
        defer buf.deinit(allocator);
        var in_quotes = false;
        while (i < line.len) {
            const c = line[i];
            if (c == '\\') {
                var n: usize = 0;
                while (i < line.len and line[i] == '\\') : (i += 1) n += 1;
                if (i < line.len and line[i] == '"') {
                    var k: usize = 0;
                    while (k < n / 2) : (k += 1) try buf.append(allocator, '\\');
                    if (n % 2 == 1) {
                        try buf.append(allocator, '"');
                        i += 1;
                    } else if (i < line.len and line[i] == '"') {
                        in_quotes = !in_quotes;
                        i += 1;
                    }
                } else {
                    var k: usize = 0;
                    while (k < n) : (k += 1) try buf.append(allocator, '\\');
                }
                continue;
            }
            if (c == '"') {
                in_quotes = !in_quotes;
                i += 1;
                continue;
            }
            if (!in_quotes and (c == ' ' or c == '\t')) break;
            try buf.append(allocator, c);
            i += 1;
        }
        const owned = try allocator.dupe(u8, buf.items);
        try out.items.append(allocator, owned);
    }
    return out;
}

pub const BuildFn = *const fn (ctx: *anyopaque, ui_ptr: *ui.Ui) void;
const WindowUi = ui.Ui;
const Dirty = ui.Dirty;

pub const ExitPolicy = enum { when_last_window_closes, explicit };
pub const CloseReason = enum { user, app_quit, session_end, owner_closed };
pub const CloseDecision = enum { allow, veto };
pub const CreateWindowError = error{ DuplicatePersistName, PlatformFailed, OutOfMemory };

pub const WindowOptions = struct {
    title: []const u8,
    size: core.Size = .{ .w = 900, .h = 600 },
    min_size: ?core.Size = null,
    persist_name: ?[]const u8 = null,
    resizable: bool = true,
    visible: bool = true,
    owner: ?*ManagedWindow = null,
};

pub const WindowHandlers = struct {
    build: BuildFn,
    ctx: *anyopaque,
    on_close_request: ?*const fn (ctx: *anyopaque, reason: CloseReason) CloseDecision = null,
    on_closed: ?*const fn (ctx: *anyopaque) void = null,
};

pub const OpenDialogError = error{ OwnerDestroyed, PlatformFailed, OutOfMemory };
pub const DialogCode = struct {
    pub const ok: u32 = 1;
    pub const cancel: u32 = 2;
    pub const yes: u32 = 6;
    pub const no: u32 = 7;
};

pub const DialogOptions = struct {
    title: []const u8,
    size: ?core.Size = null,
    resizable: bool = false,
    persist_name: ?[]const u8 = null,
};
pub const DialogBuildFn = *const fn (ui_ptr: *ui.Ui, dlg: *Dialog, ctx: *anyopaque) void;

pub const Dialog = struct {
    result_value: ?u32 = null,
    closed: bool = false,
    host_window: ?*ManagedWindow = null,
    on_result: ?*const fn (ctx: ?*anyopaque, code: u32) void = null,
    result_ctx: ?*anyopaque = null,
    pub fn result(self: *const Dialog) ?u32 {
        return self.result_value;
    }
    pub fn close(self: *Dialog, code: u32) void {
        if (self.closed) return;
        self.result_value = code;
        self.closed = true;
    }
    pub fn host(self: *const Dialog) *ManagedWindow {
        return self.host_window.?;
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

pub const NativePathsCb = *const fn (ctx: *anyopaque, paths: ?[]const platform.Path) void;
pub const NativePathCb = *const fn (ctx: *anyopaque, path: ?platform.Path) void;
pub const NativeStyleCb = *const fn (ctx: *anyopaque, style: ?text.Style) void;
pub const NativeTaskCb = *const fn (ctx: *anyopaque, result: platform.TaskResult) void;

pub const NativeDialogs = struct {
    app: ?*App = null,

    pub const Error = error{ NotInAfterFrame, Unsupported, PlatformFailed };

    fn checkedApp(self: *NativeDialogs) Error!*App {
        const a = self.app orelse return error.NotInAfterFrame;
        if (a.ui_state.building or !a.ui_state.running_after_frame) return error.NotInAfterFrame;
        return a;
    }

    pub fn openFile(self: *NativeDialogs, owner: *platform.Window, opts: platform.FileDialogOptions, ctx: *anyopaque, cb: NativePathsCb) Error!void {
        _ = owner;
        const a = try self.checkedApp();
        const paths = platform.dialogs.openFileList(opts) catch |e| switch (e) {
            error.Unsupported => return error.Unsupported,
        };
        cb(ctx, paths);
        a.invalidateAll(.build);
    }

    pub fn saveFile(self: *NativeDialogs, owner: *platform.Window, opts: platform.FileDialogOptions, ctx: *anyopaque, cb: NativePathCb) Error!void {
        _ = owner;
        const a = try self.checkedApp();
        const path = platform.dialogs.saveFilePath(opts) catch |e| switch (e) {
            error.Unsupported => return error.Unsupported,
        };
        cb(ctx, path);
        a.invalidateAll(.build);
    }

    pub fn pickFolder(self: *NativeDialogs, owner: *platform.Window, opts: platform.FileDialogOptions, ctx: *anyopaque, cb: NativePathCb) Error!void {
        return self.saveFile(owner, opts, ctx, cb);
    }

    pub fn pickColor(self: *NativeDialogs, owner: *platform.Window, initial: core.Color, ctx: *anyopaque, cb: *const fn (ctx: *anyopaque, color: ?core.Color) void) Error!void {
        _ = owner;
        const a = try self.checkedApp();
        const color = platform.dialogs.pickColorChoice(initial) catch |e| switch (e) {
            error.Unsupported => return error.Unsupported,
        };
        cb(ctx, color);
        a.invalidateAll(.build);
    }

    pub fn pickFont(self: *NativeDialogs, owner: *platform.Window, initial: text.Style, ctx: *anyopaque, cb: NativeStyleCb) Error!void {
        _ = owner;
        _ = initial;
        const a = try self.checkedApp();
        const f = platform.dialogs.pickFontChoice() catch |e| switch (e) {
            error.Unsupported => return error.Unsupported,
        };
        cb(ctx, text.Style{ .family = .ui, .size = f.size_lpx, .weight = f.weight, .italic = f.italic });
        a.invalidateAll(.build);
    }

    pub fn taskDialog(self: *NativeDialogs, owner: *platform.Window, opts: platform.TaskDialogOptions, ctx: *anyopaque, cb: NativeTaskCb) Error!void {
        _ = owner;
        _ = opts;
        const a = try self.checkedApp();
        const r = platform.dialogs.taskResult() catch |e| switch (e) {
            error.Unsupported => return error.Unsupported,
        };
        cb(ctx, r);
        a.invalidateAll(.build);
    }
};

pub const ButtonRole = widgets.ButtonRole;
pub const DialogButton = widgets.DialogButton;

pub const Options = struct {
    title: []const u8 = "nano_gui",
    size: core.Size = .{ .w = 960, .h = 640 },
    mode: theme.Mode = .light,
    theme_override: ?theme.Theme = null,
    id: ?AppId = null,
    strings: ?*const Strings = null,
    command_line: ?[]const u8 = null,
    argv: []const []const u8 = &.{},
    exit_policy: ExitPolicy = .when_last_window_closes,
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
    strings_state: *const Strings = &Strings.en,
    strings_fixed: bool = false,
    args_state: Args,
    app_id: ?AppId = null,
    managed: std.ArrayListUnmanaged(*ManagedWindow) = .empty,
    quit_code: i32 = 0,
    quitting: bool = false,
    exit_policy: ExitPolicy = .when_last_window_closes,
    session_allowed: ?bool = null,
    open_dialogs: std.ArrayListUnmanaged(*Dialog) = .empty,
    native: NativeDialogs = .{},

    /// 创建应用并把调用线程登记为界面线程（REQ-ARCH-007）。线程：界面线程。
    pub fn init(gpa: std.mem.Allocator, opts: Options) !App {
        core.thread.markUiThread();
        core.stats.initRegistry();
        core.stats.timerBegin("time.startup");
        errdefer core.stats.timerEnd("time.startup");
        if (opts.id) |id| try validateAppId(id);
        try platform.init(gpa);
        gfx.init(gpa);
        try text.init(gpa, .{});
        text.setDirectWrite(std.mem.eql(u8, build_options.text_backend, "directwrite"));
        core.stats.timerBegin("time.gl_context");
        const w = try platform.createWindow(.{
            .title = opts.title,
            .client_size = opts.size,
            .resizable = true,
        });
        const th = opts.theme_override orelse theme.Theme.default(opts.mode, platform.appearance(w));
        const surface = try gfx.Surface.initForWindow(gpa, w);
        core.stats.timerEnd("time.gl_context");
        var u = ui.Ui.init(gpa);
        u.force_rebuild = build_options.force_rebuild;
        u.show_damage = build_options.show_damage;
        u.setWindow(w);
        u.setTheme(&th);
        var args_state = Args{ .allocator = gpa };
        if (opts.command_line) |line| {
            args_state = try parseCommandLine(gpa, line);
        } else if (opts.argv.len > 0) {
            for (opts.argv) |a| {
                const copy = try gpa.dupe(u8, a);
                try args_state.items.append(gpa, copy);
            }
        }
        const strings_ptr = opts.strings orelse stringsForLocale("en-US");
        var self = App{
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
            .strings_state = strings_ptr,
            .strings_fixed = opts.strings != null,
            .args_state = args_state,
            .app_id = opts.id,
            .exit_policy = opts.exit_policy,
        };
        self.registerStandardCommands();
        core.stats.timerEnd("time.startup");
        return self;
    }

    fn registerStandardCommands(self: *App) void {
        const specs = [_]struct { name: []const u8, title: []const u8, shortcut: ?input.Chord }{
            .{ .name = "edit.undo", .title = self.strings_state.edit_undo, .shortcut = .{ .key = .z, .mods = .{ .ctrl = true } } },
            .{ .name = "edit.redo", .title = self.strings_state.edit_redo, .shortcut = .{ .key = .y, .mods = .{ .ctrl = true } } },
            .{ .name = "edit.cut", .title = self.strings_state.edit_cut, .shortcut = .{ .key = .x, .mods = .{ .ctrl = true } } },
            .{ .name = "edit.copy", .title = self.strings_state.edit_copy, .shortcut = .{ .key = .c, .mods = .{ .ctrl = true } } },
            .{ .name = "edit.paste", .title = self.strings_state.edit_paste, .shortcut = .{ .key = .v, .mods = .{ .ctrl = true } } },
            .{ .name = "edit.delete", .title = self.strings_state.edit_delete, .shortcut = null },
            .{ .name = "edit.select_all", .title = self.strings_state.edit_select_all, .shortcut = .{ .key = .a, .mods = .{ .ctrl = true } } },
        };
        for (specs) |s| {
            _ = self.commands.register(.{ .name = s.name, .title = s.title, .shortcut = s.shortcut }) catch {};
        }
    }

    pub fn args(self: *const App) []const []const u8 {
        return self.args_state.slice();
    }

    pub fn setStrings(self: *App, table: *const Strings) void {
        self.strings_state = table;
        self.strings_fixed = true;
        self.ui_state.invalidate(.build);
    }

    pub fn strings(self: *const App) *const Strings {
        return self.strings_state;
    }

    pub fn deinit(self: *App) void {
        while (self.open_dialogs.items.len > 0) {
            const d = self.open_dialogs.items[self.open_dialogs.items.len - 1];
            _ = self.open_dialogs.pop();
            self.gpa.destroy(d);
        }
        while (self.managed.items.len > 0) self.destroyManaged(self.managed.items[self.managed.items.len - 1]);
        self.open_dialogs.deinit(self.gpa);
        self.managed.deinit(self.gpa);
        self.drainPosts();
        self.args_state.deinit();
        self.commands.deinit();
        self.settings.deinit();
        self.ui_state.deinit();
        text.deinit();
        self.surface.deinit();
        gfx.deinit();
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
            .drop => |d| {
                var data = d.data;
                data.deinit();
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

    /// 线程安全（REQ-ARCH-008、REQ-ARCH-010）：从工作线程回投闭包到界面线程；
    /// 队列无界、多生产者单消费者，闭包按入队顺序在界面线程的 `pump` 中执行。
    pub fn post(self: *App, closure: core.Closure) bool {
        if (self.quitting) return false;
        const node = self.post_allocator.create(PostNode) catch return false;
        node.* = .{ .closure = closure };
        self.postLock();
        if (self.post_tail) |tail| tail.next = node else self.post_head = node;
        self.post_tail = node;
        self.postUnlock();
        platform.wake();
        return true;
    }

    /// 线程安全（REQ-ARCH-008）：仅唤醒界面线程。
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
        core.thread.assertUiThread("App.setMode", @src());
        self.fixed_mode = mode;
        self.custom_theme = false;
        self.theme_state = theme.Theme.default(mode, platform.appearance(self.window));
        self.ui_state.invalidate(.build);
    }

    pub fn setTheme(self: *App, t: theme.Theme) void {
        core.thread.assertUiThread("App.setTheme", @src());
        self.theme_state = t;
        self.custom_theme = true;
        self.ui_state.invalidate(.build);
    }

    /// 处理一轮平台消息并返回是否有事件。线程：界面线程。
    pub fn pump(self: *App) usize {
        core.thread.assertUiThread("App.pump", @src());
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

    fn shortcutSource(self: *App) input.ShortcutSource {
        return .{
            .ctx = self,
            .lookup = struct {
                fn lookup(ctx: *anyopaque, chord: input.Chord) ?input.ShortcutHit {
                    const a: *App = @ptrCast(@alignCast(ctx));
                    return a.commands.lookupChord(chord);
                }
            }.lookup,
            .invoke = struct {
                fn invoke(ctx: *anyopaque, id: input.CommandId) void {
                    const a: *App = @ptrCast(@alignCast(ctx));
                    a.invokeAction(id);
                }
            }.invoke,
        };
    }

    fn invokeAction(self: *App, id: input.CommandId) void {
        const c = self.commands.get(id) orelse return;
        if (std.mem.startsWith(u8, c.name, "edit.")) {
            const cmd: ?input.EditCommand = if (std.mem.eql(u8, c.name, "edit.undo")) .undo else if (std.mem.eql(u8, c.name, "edit.redo")) .redo else if (std.mem.eql(u8, c.name, "edit.cut")) .cut else if (std.mem.eql(u8, c.name, "edit.copy")) .copy else if (std.mem.eql(u8, c.name, "edit.paste")) .paste else if (std.mem.eql(u8, c.name, "edit.delete")) .delete else if (std.mem.eql(u8, c.name, "edit.select_all")) .select_all else null;
            if (cmd) |e| {
                if (self.ui_state.editCommand(e)) return;
                return;
            }
        }
        self.commands.invoke(id);
    }

    pub fn step(self: *App) bool {
        core.thread.assertUiThread("App.step", @src());
        self.native.app = self;
        _ = self.pump();
        // 最小化/不可呈现期间不推进帧或动画（REQ-FRAME-049）。
        if (!self.window.canPresent()) {
            for (self.events.items) |e| self.freeEvent(e);
            self.events.clearRetainingCapacity();
            self.ui_state.frame_did_layout = false;
            self.ui_state.repaint_all = true;
            return false;
        }
        const has_events = self.events.items.len > 0;
        const due_blink = self.ui_state.hasDueBlink(platform.nowMs());
        if (!has_events and !self.ui_state.needsFrame() and !due_blink and !self.ui_state.force_rebuild) return false;
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
        self.ui_state.setShortcutSource(self.shortcutSource());
        self.ui_state.setCommands(self, struct {
            fn title(ctx: ?*anyopaque, id: input.CommandId) []const u8 {
                const self_ptr: *App = @ptrCast(@alignCast(ctx.?));
                const c = self_ptr.commands.get(id) orelse return "";
                return c.title;
            }
        }.title, struct {
            fn invoke(ctx: ?*anyopaque, id: input.CommandId) void {
                const self_ptr: *App = @ptrCast(@alignCast(ctx.?));
                self_ptr.invokeAction(id);
            }
        }.invoke);
        self.ui_state.setViewport(self.window.client.w, self.window.client.h, self.window.scale());
        core.stats.timerBegin("time.frame_cpu");
        if (has_events) core.stats.timerBegin("time.input_to_present");
        core.stats.timerBegin("time.collect");
        self.ui_state.beginFrame(platform.nowMs(), self.window.active);
        core.stats.timerEnd("time.collect");
        ui.notePhase(.collect);
        core.stats.timerBegin("time.dispatch");
        for (self.events.items) |e| self.ui_state.dispatch(e);
        core.stats.timerEnd("time.dispatch");
        ui.notePhase(.dispatch);
        for (self.events.items) |e| self.freeEvent(e);
        self.events.clearRetainingCapacity();
        if (self.ui_state.window) |w| {
            self.ui_state.setViewport(w.client.w, w.client.h, w.scale());
        }
        // 仅产生事件而没有任何失效的轮次不构成帧（REQ-FRAME-037）。
        if (self.ui_state.dirty == .none and !self.ui_state.needsFrame() and self.ui_state.damage.isEmpty()) {
            core.stats.timerEnd("time.frame_cpu");
            if (has_events) core.stats.timerEnd("time.input_to_present");
            return false;
        }
        if (self.ui_state.dirty == .build and self.build_fn != null) {
            self.ui_state.build(self.build_ctx.?, self.build_fn.?);
        }
        ui.notePhase(.build);
        const did_layout = self.ui_state.dirty == .build or self.ui_state.dirty == .layout;
        if (did_layout) self.ui_state.arrangeTree();
        ui.notePhase(.layout);
        if (did_layout and self.ui_state.needsLayoutFeedbackRebuild()) {
            if (self.build_fn) |bf| {
                ui.notePhase(.build);
                self.ui_state.rebuildForLayoutFeedback(self.build_ctx.?, bf);
                self.ui_state.arrangeTree();
                ui.notePhase(.layout);
                // 第二遍后仍不收敛：以当前结果完成本帧并请求下一帧（REQ-FRAME-032）。
                if (self.ui_state.needsLayoutFeedbackRebuild()) self.ui_state.carry_dirty = .build;
            }
        }
        if (did_layout or self.ui_state.dirty == .paint) self.ui_state.computeLayoutDamage();
        if (settings_changed or self.ui_state.repaint_all) {
            self.ui_state.damage = .{ .x = 0, .y = 0, .w = self.window.client.w, .h = self.window.client.h };
            self.ui_state.repaint_all = false;
        }
        if (self.ui_state.dirty == .paint and self.ui_state.damage.isEmpty()) {
            self.ui_state.damage = .{ .x = 0, .y = 0, .w = self.window.client.w, .h = self.window.client.h };
        }
        if (did_layout) {
            const ms = self.ui_state.minWindowSize();
            platform.setMinSize(self.window, .{ .w = ms.x, .h = ms.y });
        }
        ui.notePhase(.damage);
        // 表面内容失效（resize/scale/上下文丢失）时必须整根重绘（REQ-GFX-004）。
        if (!self.surface.contentValid()) {
            self.ui_state.damage = .{ .x = 0, .y = 0, .w = self.window.client.w, .h = self.window.client.h };
        }
        var presented = false;
        if (!self.ui_state.damage.isEmpty()) {
            const painted = self.ui_state.paint(&self.surface);
            ui.notePhase(.paint);
            if (painted) {
                presented = true;
                ui.notePhase(.submit);
                self.frames += 1;
                self.last_submitted = platform.nowMs();
            }
        }
        if (!presented) {
            core.stats.timerEnd("time.frame_cpu");
            if (has_events) core.stats.timerEnd("time.input_to_present");
        }
        self.ui_state.finishFrame();
        ui.notePhase(.finish);
        self.processDialogs();
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

    // ---- 应用内模态对话框（REQ-APP-016 至 019） ----

    pub fn openDialog(self: *App, owner: *ManagedWindow, opts: DialogOptions, build: DialogBuildFn, ctx: *anyopaque, on_result: ?*const fn (ctx: ?*anyopaque, code: u32) void) OpenDialogError!*Dialog {
        if (owner.closed) return error.OwnerDestroyed;
        const d = self.gpa.create(Dialog) catch return error.OutOfMemory;
        d.* = .{
            .host_window = owner,
            .on_result = on_result,
            .result_ctx = if (on_result != null) ctx else null,
        };
        owner.dialog_open = true;
        owner.dialog_build = build;
        owner.dialog_ctx = ctx;
        owner.dialog_options = opts;
        self.open_dialogs.append(self.gpa, d) catch {
            self.gpa.destroy(d);
            return error.OutOfMemory;
        };
        owner.invalidate(.build);
        return d;
    }

    /// 帧提交后处理已关闭的对话框（REQ-APP-018）。
    pub fn processDialogs(self: *App) void {
        var i: usize = 0;
        while (i < self.open_dialogs.items.len) {
            const d = self.open_dialogs.items[i];
            if (!d.closed or d.result_value == null) {
                i += 1;
                continue;
            }
            _ = self.open_dialogs.orderedRemove(i);
            if (d.host_window) |h| {
                h.dialog_open = false;
                h.dialog_build = null;
                h.invalidate(.build);
            }
            if (d.on_result) |cb| cb(d.result_ctx.?, d.result_value.?);
            self.gpa.destroy(d);
        }
    }

    // ---- 多窗口与应用生命周期（REQ-APP-002 至 013） ----

    pub fn createWindow(self: *App, opts: WindowOptions, handlers: WindowHandlers) CreateWindowError!*ManagedWindow {
        core.thread.assertUiThread("App.createWindow", @src());
        if (opts.persist_name) |pn| {
            for (self.managed.items) |w| {
                if (w.persist_name) |existing| {
                    if (std.mem.eql(u8, existing, pn)) return error.DuplicatePersistName;
                }
            }
        }
        const title = try self.gpa.dupe(u8, opts.title);
        errdefer self.gpa.free(title);
        const pn = if (opts.persist_name) |p| try self.gpa.dupe(u8, p) else null;
        errdefer if (pn) |p| self.gpa.free(p);
        const placement = if (opts.persist_name) |pname| self.resolvePlacement(pname) else null;
        const native = platform.createWindow(.{
            .title = title,
            .client_size = opts.size,
            .resizable = opts.resizable,
            .min_client_size = opts.min_size orelse .{ .w = 0, .h = 0 },
            .owner = if (opts.owner) |o| o.native else null,
            .hidden = !opts.visible,
            .placement = placement,
            .state = if (placement) |p| p.state else .normal,
        }) catch return error.PlatformFailed;
        var u = ui.Ui.init(self.gpa);
        u.setWindow(native);
        u.setTheme(&self.theme_state);
        u.setViewport(native.client.w, native.client.h, native.scale());
        const w = self.gpa.create(ManagedWindow) catch return error.OutOfMemory;
        w.* = .{
            .app = self,
            .native = native,
            .ui_state = u,
            .handlers = handlers,
            .title = title,
            .persist_name = pn,
            .min_size = opts.min_size,
            .visible = opts.visible,
            .owner = opts.owner,
        };
        self.managed.append(self.gpa, w) catch return error.OutOfMemory;
        return w;
    }

    /// 使所有窗口失效。线程：界面线程（非线程安全，调试构建断言）。
    pub fn invalidateAll(self: *App, level: ui.Dirty) void {
        core.thread.assertUiThread("App.invalidateAll", @src());
        for (self.managed.items) |w| w.ui_state.invalidate(level);
        self.ui_state.invalidate(level);
    }

    fn destroyManaged(self: *App, w: *ManagedWindow) void {
        if (w.closed) return;
        var di: usize = 0;
        while (di < self.open_dialogs.items.len) {
            const d = self.open_dialogs.items[di];
            if (d.host_window == w) {
                _ = self.open_dialogs.orderedRemove(di);
                self.gpa.destroy(d);
            } else di += 1;
        }
        w.closed = true;
        for (self.managed.items, 0..) |item, i| {
            if (item == w) {
                _ = self.managed.swapRemove(i);
                break;
            }
        }
        if (w.persist_name) |pn| self.saveWindowPlacementNamed(w, pn);
        w.ui_state.deinit();
        platform.destroyWindow(w.native);
        if (w.handlers.on_closed) |cb| cb(w.handlers.ctx);
        if (w.owner) |o| _ = o;
        self.gpa.free(w.title);
        if (w.persist_name) |p| self.gpa.free(p);
        self.gpa.destroy(w);
        if (self.managed.items.len == 0 and self.exit_policy == .when_last_window_closes and !self.quitting) {
            self.quit_code = 0;
            self.quitting = true;
        }
    }

    /// 从设置读取并校验窗口位置（REQ-APP-015）。字段缺失或类型错误时整条忽略。
    pub fn resolvePlacement(self: *App, name: []const u8) ?platform.WindowPlacement {
        const v = self.settings.windowPlacement(name) orelse return null;
        if (v != .object) return null;
        const obj = v.object;
        const x = intField(obj, "x") orelse return null;
        const y = intField(obj, "y") orelse return null;
        const w = intField(obj, "w") orelse return null;
        const h = intField(obj, "h") orelse return null;
        if (w <= 0 or h <= 0) return null;
        const dpi_v = intField(obj, "dpi") orelse 96;
        if (dpi_v <= 0) return null;
        const max_v = obj.get("maximized") orelse return null;
        if (max_v != .bool) return null;
        const raw = platform.WindowPlacement{
            .normal_rect = .{ .x = @intCast(x), .y = @intCast(y), .w = @intCast(w), .h = @intCast(h) },
            .state = if (max_v.bool) .maximized else .normal,
            .dpi = @intCast(dpi_v),
        };
        return platform.validatePlacement(raw);
    }

    fn intField(obj: std.json.ObjectMap, key: []const u8) ?i64 {
        const v = obj.get(key) orelse return null;
        if (v != .integer) return null;
        return v.integer;
    }

    pub fn saveWindowPlacement(self: *App, w: *ManagedWindow) void {
        if (w.persist_name) |pn| self.saveWindowPlacementNamed(w, pn);
    }

    fn saveWindowPlacementNamed(self: *App, w: *ManagedWindow, name: []const u8) void {
        const p = w.native.getPlacement();
        self.settings.setWindowPlacement(name, .{
            .x = p.normal_rect.x,
            .y = p.normal_rect.y,
            .w = p.normal_rect.w,
            .h = p.normal_rect.h,
            .dpi = p.dpi,
            .maximized = w.native.minimized == false and w.native.placement.state == .maximized,
        });
        if (self.io) |io| self.settings.flush(io);
    }

    /// 两阶段退出（REQ-APP-004）。
    pub fn quit(self: *App, code: i32) void {
        core.thread.assertUiThread("App.quit", @src());
        if (self.quitting) return;
        const saved = self.quit_code;
        self.quit_code = code;
        var i = self.managed.items.len;
        while (i > 0) {
            i -= 1;
            if (!self.askClose(self.managed.items[i], .app_quit)) {
                self.quit_code = saved;
                return;
            }
        }
        while (self.managed.items.len > 0) self.destroyManaged(self.managed.items[self.managed.items.len - 1]);
        self.quit_code = code;
        self.quitting = true;
    }

    fn askClose(_: *App, w: *ManagedWindow, reason: CloseReason) bool {
        if (w.handlers.on_close_request) |cb| {
            return cb(w.handlers.ctx, reason) == .allow;
        }
        return true;
    }

    /// 会话结束询问阶段（REQ-APP-044）：只询问、不销毁。
    pub fn onSessionEnding(self: *App, logoff: bool) void {
        _ = logoff;
        var allowed = true;
        var i = self.managed.items.len;
        while (i > 0) {
            i -= 1;
            if (!self.askClose(self.managed.items[i], .session_end)) {
                allowed = false;
                break;
            }
        }
        self.session_allowed = allowed;
        platform.allowSessionEnd(allowed);
    }

    pub fn onSessionEnded(self: *App) void {
        if (self.io) |io| self.settings.flush(io);
    }

    /// 休眠恢复：每个窗口置 build 脏并整根重绘（REQ-APP-045）。
    pub fn onPowerResume(self: *App) void {
        for (self.managed.items) |w| {
            w.ui_state.invalidate(.build);
            const sc = w.native.scale();
            w.ui_state.invalidateRect(0, .{ .x = 0, .y = 0, .w = @as(f32, @floatFromInt(w.native.client.w)) / sc, .h = @as(f32, @floatFromInt(w.native.client.h)) / sc });
        }
        self.ui_state.invalidate(.build);
    }

    /// 系统界面语言变化：未固定的字符串表重新选择（REQ-APP-042）。
    pub fn onLocaleChanged(self: *App, locale: []const u8) void {
        if (self.strings_fixed) return;
        self.strings_state = stringsForLocale(locale);
        self.invalidateAll(.build);
    }
};

pub const ManagedWindow = struct {
    app: *App,
    native: *platform.Window,
    ui_state: WindowUi,
    handlers: WindowHandlers,
    title: []const u8,
    persist_name: ?[]const u8 = null,
    min_size: ?core.Size = null,
    visible: bool = true,
    owner: ?*ManagedWindow = null,
    closed: bool = false,
    dialog_open: bool = false,
    dialog_build: ?DialogBuildFn = null,
    dialog_ctx: ?*anyopaque = null,
    dialog_options: DialogOptions = .{ .title = "" },

    pub fn ui(self: *ManagedWindow) *WindowUi {
        return &self.ui_state;
    }
    pub fn scale(self: *const ManagedWindow) f32 {
        return self.native.scale();
    }
    pub fn show(self: *ManagedWindow) void {
        core.thread.assertUiThread("ManagedWindow.show", @src());
        self.visible = true;
        self.native.show();
        self.ui_state.invalidate(.build);
    }
    pub fn hide(self: *ManagedWindow) void {
        core.thread.assertUiThread("ManagedWindow.hide", @src());
        self.visible = false;
        self.native.hide();
    }
    pub fn setTitle(self: *ManagedWindow, title: []const u8) void {
        core.thread.assertUiThread("ManagedWindow.setTitle", @src());
        const copy = self.app.gpa.dupe(u8, title) catch return;
        self.app.gpa.free(self.title);
        self.title = copy;
        self.native.setTitle(self.title);
    }
    const InvalidateJob = struct {
        window: *ManagedWindow,
        level: Dirty,
        alloc: std.mem.Allocator,

        fn run(ctx: ?*anyopaque) void {
            const job: *InvalidateJob = @ptrCast(@alignCast(ctx.?));
            const alloc = job.alloc;
            if (!job.window.closed) job.window.ui_state.invalidate(job.level);
            alloc.destroy(job);
        }
    };

    /// 线程安全（REQ-ARCH-008）：在界面线程上直接失效；在其他线程上等价于回投一次失效，
    /// 窗口须在回投执行前仍然存活。
    pub fn invalidate(self: *ManagedWindow, level: Dirty) void {
        if (core.thread.isUiThread()) {
            self.ui_state.invalidate(level);
            return;
        }
        const alloc = self.app.post_allocator;
        const job = alloc.create(InvalidateJob) catch return;
        job.* = .{ .window = self, .level = level, .alloc = alloc };
        if (!self.app.post(.{ .ctx = job, .func = InvalidateJob.run })) alloc.destroy(job);
    }
    pub fn build(self: *ManagedWindow) void {
        core.thread.assertUiThread("ManagedWindow.build", @src());
        if (self.closed) return;
        self.ui_state.setViewport(self.native.client.w, self.native.client.h, self.native.scale());
        self.ui_state.beginFrame(platform.nowMs(), self.native.active);
        self.ui_state.build(self.handlers.ctx, self.handlers.build);
        self.ui_state.layoutTree();
        var ms = self.ui_state.minWindowSize();
        if (self.min_size) |m| ms = .{ .x = @max(ms.x, m.w), .y = @max(ms.y, m.h) };
        platform.setMinSize(self.native, .{ .w = ms.x, .h = ms.y });
        self.ui_state.finishFrame();
    }
    pub fn minWindowSize(self: *ManagedWindow) core.Size {
        const root = self.ui_state.minWindowSize();
        var w = root.x;
        var h = root.y;
        if (self.min_size) |m| {
            w = @max(w, m.w);
            h = @max(h, m.h);
        }
        return .{ .w = w, .h = h };
    }
    pub fn requestClose(self: *ManagedWindow, reason: CloseReason) void {
        core.thread.assertUiThread("ManagedWindow.requestClose", @src());
        if (self.closed) return;
        if (self.app.askClose(self, reason)) {
            if (reason == .user) self.app.destroyManaged(self) else self.app.destroyManaged(self);
        }
    }
    pub fn destroy(self: *ManagedWindow) void {
        core.thread.assertUiThread("ManagedWindow.destroy", @src());
        self.app.destroyManaged(self);
    }
};

/// 读取 PNG 基准（金图用）。
pub fn readPng(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !gfx.Pixels {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);
    return gfx.decode(gpa, bytes);
}

// ---------------------------------------------------------------------------
// 应用内对话框几何（REQ-APP-019）
// ---------------------------------------------------------------------------

/// 客户区尺寸 = 内容期望尺寸 + 2 × pad_dialog。
pub fn dialogClientSize(content: core.Size, pad: f32) core.Size {
    return .{ .w = content.w + 2 * pad, .h = content.h + 2 * pad };
}

/// 以宿主矩形为中心并夹紧到工作区（REQ-APP-019）。
pub fn centerDialog(host: core.RectI, size: core.Size, work: core.RectI) core.Vec2i {
    const w: i32 = @intFromFloat(@round(size.w));
    const h: i32 = @intFromFloat(@round(size.h));
    var x = host.x + @divTrunc(host.w - w, 2);
    var y = host.y + @divTrunc(host.h - h, 2);
    x = std.math.clamp(x, work.x, work.x + @max(0, work.w - w));
    y = std.math.clamp(y, work.y, work.y + @max(0, work.h - h));
    return .{ .x = x, .y = y };
}
