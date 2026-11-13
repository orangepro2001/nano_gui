//! 平台层（编译期后端）。
//!
//! Linux/测试宿主使用 `headless` 后端：它提供完整的窗口/事件/时钟/系统度量注入点，
//! 也是回放与金图测试的唯一入口（REQ-TEST-020）。Windows 目标编译期选择 `win32`
//! 命名空间；本仓库在无 Windows SDK 的环境中给出同一接口的声明式实现，运行期能力
//! 以 `error.Unsupported` 明确报告，不静默改变业务语义。

const std = @import("std");
const core = @import("core.zig");
const builtin = @import("builtin");

pub const backend_name: []const u8 = if (builtin.os.tag == .windows) "win32" else "headless";
const is_windows = builtin.os.tag == .windows;
const win32 = if (is_windows) @import("platform/win32.zig") else struct {};

pub const CursorShape = enum {
    arrow,
    ibeam,
    hand,
    cross,
    size_we,
    size_ns,
    size_nwse,
    size_nesw,
    size_all,
    not_allowed,
    wait,
    progress,
    hidden,
};

pub const MouseButton = enum { left, right, middle, x1, x2 };

pub const Mods = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    win: bool = false,
    altgr: bool = false,

    pub fn eql(a: Mods, b: Mods) bool {
        return a.shift == b.shift and a.ctrl == b.ctrl and a.alt == b.alt and
            a.win == b.win and a.altgr == b.altgr;
    }
};

/// 虚拟键码的唯一定义（REQ-PLAT-031）。数值与 Win32 VK_* 对齐。
pub const VirtualKey = enum(u16) {
    none = 0,
    lbutton = 0x01,
    rbutton = 0x02,
    cancel = 0x03,
    mbutton = 0x04,
    xbutton1 = 0x05,
    xbutton2 = 0x06,
    backspace = 0x08,
    tab = 0x09,
    clear = 0x0C,
    enter = 0x0D,
    shift = 0x10,
    ctrl = 0x11,
    alt = 0x12,
    pause = 0x13,
    caps_lock = 0x14,
    escape = 0x1B,
    space = 0x20,
    page_up = 0x21,
    page_down = 0x22,
    end = 0x23,
    home = 0x24,
    left = 0x25,
    up = 0x26,
    right = 0x27,
    down = 0x28,
    print_screen = 0x2C,
    insert = 0x2D,
    delete = 0x2E,
    n0 = 0x30,
    n1 = 0x31,
    n2 = 0x32,
    n3 = 0x33,
    n4 = 0x34,
    n5 = 0x35,
    n6 = 0x36,
    n7 = 0x37,
    n8 = 0x38,
    n9 = 0x39,
    a = 0x41,
    b = 0x42,
    c = 0x43,
    d = 0x44,
    e = 0x45,
    f = 0x46,
    g = 0x47,
    h = 0x48,
    i = 0x49,
    j = 0x4A,
    k = 0x4B,
    l = 0x4C,
    m = 0x4D,
    n = 0x4E,
    o = 0x4F,
    p = 0x50,
    q = 0x51,
    r = 0x52,
    s = 0x53,
    t = 0x54,
    u = 0x55,
    v = 0x56,
    w = 0x57,
    x = 0x58,
    y = 0x59,
    z = 0x5A,
    lwin = 0x5B,
    rwin = 0x5C,
    apps = 0x5D,
    sleep = 0x5F,
    np0 = 0x60,
    np1 = 0x61,
    np2 = 0x62,
    np3 = 0x63,
    np4 = 0x64,
    np5 = 0x65,
    np6 = 0x66,
    np7 = 0x67,
    np8 = 0x68,
    np9 = 0x69,
    np_mul = 0x6A,
    np_add = 0x6B,
    np_sub = 0x6D,
    np_decimal = 0x6E,
    np_div = 0x6F,
    f1 = 0x70,
    f2 = 0x71,
    f3 = 0x72,
    f4 = 0x73,
    f5 = 0x74,
    f6 = 0x75,
    f7 = 0x76,
    f8 = 0x77,
    f9 = 0x78,
    f10 = 0x79,
    f11 = 0x7A,
    f12 = 0x7B,
    f13 = 0x7C,
    f14 = 0x7D,
    f15 = 0x7E,
    f16 = 0x7F,
    f17 = 0x80,
    f18 = 0x81,
    f19 = 0x82,
    f20 = 0x83,
    f21 = 0x84,
    f22 = 0x85,
    f23 = 0x86,
    f24 = 0x87,
    num_lock = 0x90,
    scroll_lock = 0x91,
    lshift = 0xA0,
    rshift = 0xA1,
    lctrl = 0xA2,
    rctrl = 0xA3,
    lalt = 0xA4,
    ralt = 0xA5,
    oem_1 = 0xBA,
    oem_plus = 0xBB,
    oem_comma = 0xBC,
    oem_minus = 0xBD,
    oem_period = 0xBE,
    oem_2 = 0xBF,
    oem_3 = 0xC0,
    oem_4 = 0xDB,
    oem_5 = 0xDC,
    oem_6 = 0xDD,
    oem_7 = 0xDE,
    oem_8 = 0xDF,
    oem_102 = 0xE2,
    browser_back = 0xA6,
    browser_forward = 0xA7,
    browser_refresh = 0xA8,
    browser_stop = 0xA9,
    browser_search = 0xAA,
    browser_favorites = 0xAB,
    browser_home = 0xAC,
    volume_mute = 0xAD,
    volume_down = 0xAE,
    volume_up = 0xAF,
    media_next = 0xB0,
    media_prev = 0xB1,
    media_stop = 0xB2,
    media_play_pause = 0xB3,
    launch_mail = 0xB4,
    launch_media = 0xB5,
    launch_app1 = 0xB6,
    launch_app2 = 0xB7,
    process_key = 0xE5,
};

pub const ScrollAmount = union(enum) {
    lines: u32,
    page,
};

pub const Size2i = core.Size2i;
pub const RectI = core.RectI;
pub const Vec2i = core.Vec2i;

pub const SystemMetrics = struct {
    double_click_ms: u32 = 500,
    double_click_size: Size2i = .{ .w = 4, .h = 4 },
    drag_size: Size2i = .{ .w = 4, .h = 4 },
    wheel_lines: ScrollAmount = .{ .lines = 3 },
    wheel_chars: ScrollAmount = .{ .lines = 3 },
    key_repeat_delay_ms: u32 = 500,
    key_repeat_interval_ms: u32 = 33,
    menu_show_delay_ms: u32 = 400,
    hover_time_ms: u32 = 400,
    hover_size: Size2i = .{ .w = 4, .h = 4 },
    caret_blink_ms: ?u32 = 530,
    keyboard_cues: bool = false,
    client_animation: bool = true,
    menu_animation: bool = true,
    menu_fade: bool = true,
};

pub const SysColor = enum {
    window,
    window_text,
    btn_face,
    btn_text,
    gray_text,
    highlight,
    highlight_text,
    hotlight,
    btn_highlight,
    btn_shadow,
    menu,
    menu_text,
    active_caption,
    inactive_caption,
    info_bk,
    info_text,
};

pub const SysColors = struct {
    map: std.EnumArray(SysColor, core.Color) = .initFill(.{ .r = 240, .g = 240, .b = 240 }),

    pub fn get(self: *const SysColors, c: SysColor) core.Color {
        return self.map.get(c);
    }
    pub fn set(self: *SysColors, c: SysColor, color: core.Color) void {
        self.map.set(c, color);
    }
    pub fn initDefault() SysColors {
        var s = SysColors{};
        s.set(.window, .{ .r = 255, .g = 255, .b = 255 });
        s.set(.window_text, .{ .r = 0, .g = 0, .b = 0 });
        s.set(.btn_face, .{ .r = 240, .g = 240, .b = 240 });
        s.set(.btn_text, .{ .r = 0, .g = 0, .b = 0 });
        s.set(.gray_text, .{ .r = 109, .g = 109, .b = 109 });
        s.set(.highlight, .{ .r = 0, .g = 120, .b = 215 });
        s.set(.highlight_text, .{ .r = 255, .g = 255, .b = 255 });
        s.set(.hotlight, .{ .r = 0, .g = 102, .b = 204 });
        s.set(.menu, .{ .r = 249, .g = 250, .b = 251 });
        s.set(.menu_text, .{ .r = 27, .g = 31, .b = 36 });
        return s;
    }
};

/// 无头/GLFW 后端的测试字体族名（REQ-PLAT-084、REQ-TEXT-037）。
pub const headless_font_family: []const u8 = "NanoTestSans";

pub const MessageFont = struct {
    family: []const u8 = "Segoe UI",
    size_lpx: f32 = 12,
    weight: u16 = 400,
    italic: bool = false,
};

pub const SystemAppearance = struct {
    apps_dark: bool = false,
    accent: core.Color = core.Color.fromHex(0x2F6EDF, 255),
    high_contrast: bool = false,
    sys_colors: SysColors = SysColors.initDefault(),
    message_font: MessageFont = .{},
    text_scale: f32 = 1.0,
    metrics: SystemMetrics = .{},
};

pub const SettingsChanged = packed struct {
    appearance: bool = false,
    metrics: bool = false,
    font: bool = false,
    display: bool = false,
    locale: bool = false,
    all: bool = false,
};

pub const ImeSegmentStyle = enum {
    unconverted,
    converted,
    target_converted,
    target_unconverted,
    @"error",
};

pub const ImeSegment = struct {
    start: u32,
    end: u32,
    style: ImeSegmentStyle,
};

pub const Axis = enum { vertical, horizontal };

pub const DismissReason = enum {
    outside_click,
    deactivated,
    host_moved,
    host_resized,
    host_hidden,
    cancel_mode,
    capture_lost,
    dpi_changed,
};

pub const DropEffect = enum { none, copy, move, link };
pub const DropEffects = packed struct { copy: bool = false, move: bool = false, link: bool = false };
pub const DropFormats = packed struct { files: bool = false, text: bool = false };
pub const Path = []const u8;
pub const DataObject = struct { files: []const Path = &.{}, text: ?[]const u8 = null, custom: []const u8 = &.{} };
pub const DragData = DataObject;
pub const DropData = struct {
    allocator: std.mem.Allocator,
    files: []Path = &.{},
    text: ?[]u8 = null,
    pub fn deinit(self: *DropData) void {
        for (self.files) |f| self.allocator.free(f);
        if (self.files.len > 0) self.allocator.free(self.files);
        if (self.text) |t| self.allocator.free(t);
        self.* = .{ .allocator = self.allocator };
    }
};
pub const TrayEventKind = enum { click, double_click, context_menu, balloon_clicked };
pub const BalloonKind = enum { none, info, warning, @"error" };
pub const IconPixels = struct { w: u32, h: u32, rgba: []const u8 };
pub const IconSet = []const IconPixels;

pub const Data = union(enum) {
    mouse_move: struct {
        pos: Vec2i,
        mods: Mods = .{},
        screen_pos: ?Vec2i = null,
        via_popup_capture: bool = false,
    },
    mouse_button: struct {
        button: MouseButton,
        down: bool,
        pos: Vec2i,
        mods: Mods = .{},
        screen_pos: ?Vec2i = null,
        via_popup_capture: bool = false,
    },
    mouse_leave,
    capture_lost,
    wheel: struct {
        axis: Axis,
        raw: i32,
        steps: i32,
        pos: Vec2i,
        mods: Mods = .{},
        screen_pos: ?Vec2i = null,
        via_popup_capture: bool = false,
    },
    key: struct {
        vk: VirtualKey,
        scancode: u16 = 0,
        down: bool,
        repeat: bool = false,
        mods: Mods = .{},
        extended: bool = false,
    },
    text: []const u8,
    ime_start,
    ime_update: struct { text: []const u8, cursor: usize, segments: []const ImeSegment },
    ime_commit: []const u8,
    ime_end,
    focus: struct { gained: bool },
    activate: struct { active: bool, by_click: bool = false },
    resized: struct { client: Size2i, state: WindowState = .normal },
    moved: struct { pos: Vec2i },
    dpi_changed: struct { dpi: u32, scale: f32 },
    repaint: struct { rect: RectI },
    visibility: struct { visible: bool },
    close_requested,
    session_ending: struct { logoff: bool },
    session_ended: struct { logoff: bool },
    system_changed: struct { what: SettingsChanged },
    popup_dismiss: struct { reason: DismissReason },
    drag_enter: struct { formats: DropFormats, pos: Vec2i, effects_allowed: DropEffects },
    drag_over: struct { pos: Vec2i, mods: Mods },
    drag_leave,
    drop: struct { data: DropData, pos: Vec2i },
    tray: struct { id: u32, kind: TrayEventKind, screen_pos: Vec2i },
    power_resume,
    render_lost,
};

pub const Event = struct {
    window: *Window,
    time_ms: u64,
    data: Data,
};

pub const EventSink = struct {
    ctx: ?*anyopaque = null,
    func: *const fn (ctx: ?*anyopaque, event: Event) void,
};

pub const WindowState = enum { normal, minimized, maximized };

pub const WindowOptions = struct {
    title: []const u8 = "",
    client_size: core.Size = .{ .w = 800, .h = 600 },
    position: ?Vec2i = null,
    resizable: bool = true,
    min_client_size: core.Size = .{ .w = 0, .h = 0 },
    owner: ?*Window = null,
    state: WindowState = .normal,
    hidden: bool = false,
    placement: ?WindowPlacement = null,
};

pub const PopupWindowKind = enum { menu, dropdown, tooltip };

pub const PopupWindowSpec = struct {
    rect: RectI = .{},
    kind: PopupWindowKind = .menu,
    shadow: bool = true,
};

pub const WindowPlacement = struct {
    normal_rect: RectI = .{},
    state: WindowState = .normal,
    dpi: u32 = 96,
};

pub const Window = struct {
    id: u32,
    title: []const u8 = "",
    client: Size2i = .{ .w = 800, .h = 600 },
    min_client_size: core.Size = .{ .w = 0, .h = 0 },
    scale_value: f32 = 1.0,
    dpi: u32 = 96,
    visible: bool = true,
    active: bool = true,
    minimized: bool = false,
    popup: bool = false,
    popup_kind: PopupWindowKind = .menu,
    owner: ?*Window = null,
    placement: WindowPlacement = .{},
    ime_saved_context: ?*anyopaque = null,
    drop_target: ?*anyopaque = null,
    drop_effect: DropEffect = .none,
    hdc: ?*anyopaque = null,
    hglrc: ?*anyopaque = null,
    gl_ready: bool = false,
    nanovg_surface: bool = false,
    gl_deinit_fn: ?*const fn (dc: *anyopaque, rc: *anyopaque) void = null,
    gl_present_fn: ?*const fn (dc: *anyopaque, rc: *anyopaque, w: u32, h: u32, rgba: []const u8) bool = null,
    cursor: CursorShape = .arrow,
    /// 已实际应用到系统的形状；`null` 表示尚未应用过（REQ-PLAT-037 去重用）。
    cursor_applied: ?CursorShape = null,
    capture: bool = false,
    /// 客户区逻辑尺寸（lpx）；DPI 变化时据此重算物理尺寸（REQ-PLAT-010）。
    size_lpx: core.Size = .{ .w = 800, .h = 600 },
    /// 窗口位置（屏幕 ppx）。
    position: Vec2i = .{ .x = 0, .y = 0 },
    /// 每轴滚轮累加器（REQ-PLAT-029）：下标为 `@intFromEnum(Axis)`。
    wheel_acc: [2]i32 = .{ 0, 0 },
    /// 系统嵌套模态循环的周期计时器是否在运行（REQ-PLAT-022）。
    modal_timer_active: bool = false,
    /// 是否处于由对话框/拖放产生的嵌套模态循环中且为被禁用的 owner（REQ-PLAT-025）。
    modal_disabled: bool = false,
    hwnd: ?*anyopaque = null,
    present_rgba: []const u8 = &.{},
    present_w: u32 = 0,
    present_h: u32 = 0,
    presented: []u8 = &.{},
    present_count: u64 = 0,
    frame_callback: ?*const fn (w: *Window, reason: FrameReason) void = null,
    frame_ctx: ?*anyopaque = null,
    user: ?*anyopaque = null,

    pub fn scale(self: *const Window) f32 {
        return self.scale_value;
    }
    pub fn canPresent(self: *const Window) bool {
        return self.visible and !self.minimized and self.client.w > 0 and self.client.h > 0;
    }
    pub fn makeCurrent(self: *Window) void {
        _ = self;
    }
    pub fn swapBuffers(self: *Window) void {
        self.present_count += 1;
    }
    pub fn setSwapInterval(self: *Window, n: i32) void {
        _ = self;
        _ = n;
    }
    pub fn setTitle(self: *Window, title: []const u8) void {
        self.title = title;
        if (is_windows and !HeadlessState.force_headless) win32.setTitle(self, title);
    }
    /// 当前客户区物理尺寸（ppx；最小化时为 0×0）。线程：界面线程。REQ-PLAT-012。
    pub fn clientSize(self: *const Window) Size2i {
        return self.client;
    }
    /// 设置客户区逻辑尺寸（lpx）：先按最小客户区钳制，再按当前 scale 换算为 ppx（REQ-PLAT-012、REQ-PLAT-013）。线程：界面线程。
    pub fn setClientSize(self: *Window, size: core.Size) void {
        self.size_lpx = .{ .w = @max(size.w, self.min_client_size.w), .h = @max(size.h, self.min_client_size.h) };
        self.applyScaledClient();
        pushResize(self);
    }
    /// 按逻辑尺寸与当前 scale 重算物理客户区；最小化时保持 0×0。
    fn applyScaledClient(self: *Window) void {
        if (self.minimized) return;
        self.client = .{ .w = lpxToPpx(self.size_lpx.w, self.scale_value), .h = lpxToPpx(self.size_lpx.h, self.scale_value) };
    }
    pub fn setPosition(self: *Window, p: Vec2i) void {
        self.position = p;
    }
    pub fn show(self: *Window) void {
        self.visible = true;
        if (is_windows and !HeadlessState.force_headless) win32.showWindow(self, 5);
        pushVisibility(self);
    }
    pub fn hide(self: *Window) void {
        self.visible = false;
        if (is_windows and !HeadlessState.force_headless) win32.showWindow(self, 0);
        pushVisibility(self);
    }
    pub fn minimize(self: *Window) void {
        if (self.minimized) return;
        self.minimized = true;
        self.visible = true;
        if (is_windows and !HeadlessState.force_headless) {
            win32.showWindow(self, 6);
        } else {
            // 无头：最小化即客户区 0×0 且 state = minimized（REQ-PLAT-035）。
            self.client = .{ .w = 0, .h = 0 };
            pushResize(self);
        }
        pushVisibility(self);
    }
    pub fn maximize(self: *Window) void {
        self.minimized = false;
    }
    pub fn restore(self: *Window) void {
        const was_minimized = self.minimized;
        self.minimized = false;
        self.visible = true;
        if (is_windows and !HeadlessState.force_headless) {
            win32.showWindow(self, 9);
        } else if (was_minimized) {
            self.applyScaledClient();
            pushResize(self);
        }
        pushVisibility(self);
    }
    /// 设置最小客户区（lpx）；之后的 `setClientSize` 以它钳制（REQ-PLAT-013）。线程：界面线程。
    pub fn setMinClientSize(self: *Window, size: core.Size) void {
        self.min_client_size = size;
    }
    pub fn setIcon(self: *Window, icon: anytype) void {
        _ = self;
        _ = icon;
    }
    /// 设置客户区指针形状；与已应用的形状相同时不产生系统调用（REQ-PLAT-036、REQ-PLAT-037）。线程：界面线程。
    pub fn setCursor(self: *Window, shape: CursorShape) void {
        self.cursor = shape;
        HeadlessState.cursor = shape;
        if (self.cursor_applied) |applied| if (applied == shape) return;
        self.cursor_applied = shape;
        HeadlessState.cursor_apply_count += 1;
    }
    pub fn setDarkTitleBar(self: *Window, dark: bool) !void {
        _ = self;
        _ = dark;
        if (builtin.os.tag != .windows) return error.Unsupported;
    }
    pub fn requestAttention(self: *Window) void {
        _ = self;
    }
    pub fn bringToFront(self: *Window) void {
        _ = self;
    }
    pub fn setCapture(self: *Window, on: bool) void {
        self.capture = on;
        if (on) HeadlessState.captured_window = self else if (HeadlessState.captured_window == self) HeadlessState.captured_window = null;
    }
    pub fn confirmClose(self: *Window) void {
        destroyWindow(self);
    }
    pub fn cancelClose(self: *Window) void {
        _ = self;
    }
    pub fn setImeCaretRect(self: *Window, caret: RectI, exclude: ?RectI) void {
        if (is_windows and !HeadlessState.force_headless) {
            win32.setImeCaret(self, caret, exclude);
            return;
        }
        if (HeadlessState.ime_caret_rect != null and rectEql(HeadlessState.ime_caret_rect.?, caret) and
            ((HeadlessState.ime_caret_exclude == null and exclude == null) or
                (HeadlessState.ime_caret_exclude != null and exclude != null and rectEql(HeadlessState.ime_caret_exclude.?, exclude.?)))) return;
        HeadlessState.ime_caret_rect = caret;
        HeadlessState.ime_caret_exclude = exclude;
        HeadlessState.ime_caret_calls += 1;
    }
    pub fn setImeEnabled(self: *Window, enabled: bool) void {
        if (is_windows and !HeadlessState.force_headless) {
            win32.setImeEnabled(self, enabled);
            return;
        }
        HeadlessState.ime_enabled_calls += 1;
        HeadlessState.ime_enabled = enabled;
        if (!enabled and HeadlessState.ime_active) headlessCancelComposition();
    }
    pub fn commitComposition(self: *Window) void {
        if (is_windows and !HeadlessState.force_headless) {
            win32.commitComposition(self);
            return;
        }
        if (!HeadlessState.ime_active) return;
        const copy = HeadlessState.gpa.dupe(u8, HeadlessState.ime_text.items) catch return;
        HeadlessState.ime_commit_count += 1;
        HeadlessState.ime_active = false;
        pushHeadlessImeEvent(.{ .ime_commit = copy });
        pushHeadlessImeEvent(.ime_end);
    }
    pub fn setDropEffect(self: *Window, effect: DropEffect) void {
        self.drop_effect = effect;
    }
    pub fn getPlacement(self: *const Window) WindowPlacement {
        return .{ .normal_rect = .{ .x = 0, .y = 0, .w = self.client.w, .h = self.client.h }, .state = if (self.minimized) .minimized else .normal, .dpi = self.dpi };
    }
};

pub const FrameReason = enum { size, paint, timer, nested_modal };

/// 96 DPI 对应 scale = 1.0（REQ-PLAT-010）。
const default_dpi: u32 = 96;
/// `WHEEL_DELTA`：滚轮一格的原始增量（REQ-PLAT-029）。
const wheel_delta: i32 = 120;
/// 一秒的毫秒数。
const ms_per_s: u64 = std.time.ms_per_s;

/// 逻辑像素换算为物理像素（四舍五入）。
fn lpxToPpx(v: f32, scale_value: f32) i32 {
    return @intFromFloat(@round(v * scale_value));
}

/// 当前是否走 Win32 原生后端（非无头）。
fn isNative() bool {
    return is_windows and !HeadlessState.force_headless;
}

/// 无头/GLFW 后端的默认外观（REQ-PLAT-084）；Win32 后端沿用结构体默认值。
fn defaultAppearance() SystemAppearance {
    var a = SystemAppearance{};
    if (!is_windows) a.message_font.family = headless_font_family;
    return a;
}

const HeadlessState = struct {
    var gpa: std.mem.Allocator = std.heap.smp_allocator;
    var force_headless: bool = false;
    var initialized: bool = false;
    var windows: std.ArrayListUnmanaged(*Window) = .empty;
    var events: std.ArrayListUnmanaged(Event) = .empty;
    var now_ms: u64 = 0;
    var wake_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
    var next_id: u32 = 1;
    var cursor: CursorShape = .arrow;
    var captured_window: ?*Window = null;
    var clipboard_text: std.ArrayListUnmanaged(u8) = .empty;
    var metrics: SystemMetrics = .{};
    var appearance: SystemAppearance = defaultAppearance();
    var present_count: u64 = 0;
    var advance_frames: u64 = 0;
    var vsync_cycles: u64 = 0;
    var scale: f32 = 1.0;
    var dpi: u32 = default_dpi;
    var frame_depth: u32 = 0;
    var frame_calls: u64 = 0;
    var cursor_apply_count: u64 = 0;
    var mouse_vanish: bool = false;
    var pointer_hidden: bool = false;
    var last_mouse_pos: ?Vec2i = null;
    var system_query_count: u64 = 0;
    var pending_high_surrogate: ?u16 = null;
    var present_src: RectI = .{};
    var session_allowed: ?bool = null;
    var session_answers: usize = 0;
    var power_pending: bool = false;
    var file_dialog_paths: ?[]const []const u8 = null;
    var font_choice: ?FontChoice = null;
    var task_result: ?TaskResult = null;
    var dialog_paths: std.ArrayListUnmanaged([]u8) = .empty;
    var clipboard_seq: u32 = 0;
    var clipboard_custom: std.AutoHashMapUnmanaged(u32, []u8) = .empty;
    var clipboard_formats: std.ArrayListUnmanaged(struct { id: u32, name: []u8 }) = .empty;
    var next_format_id: u32 = 1;
    var ime_active: bool = false;
    var ime_enabled: bool = true;
    var ime_text: std.ArrayListUnmanaged(u8) = .empty;
    var ime_caret_rect: ?RectI = null;
    var ime_caret_exclude: ?RectI = null;
    var ime_caret_calls: usize = 0;
    var ime_cancel_count: usize = 0;
    var ime_commit_count: usize = 0;
    var ime_enabled_calls: usize = 0;
    var min_size_changes: usize = 0;
    var tray_entries: std.ArrayListUnmanaged(struct { id: u32, owner: *Window, tooltip: []u8 }) = .empty;
    var tray_last_balloon: ?struct { id: u32, title: []u8, text: []u8, kind: BalloonKind } = null;
    var win_tray_entries: std.ArrayListUnmanaged(WinTrayEntry) = .empty;
    var taskbar_created_msg: u32 = 0;
};

pub const WinTrayEntry = struct { id: u32, owner: *Window, hicon: ?*anyopaque, tooltip: []u8 };

pub fn headlessGpa() std.mem.Allocator {
    return HeadlessState.gpa;
}
pub fn windowsSlice() []const *Window {
    return HeadlessState.windows.items;
}
pub fn pushBackendEvent(w: *Window, time_ms: u64, data: Data) void {
    HeadlessState.events.append(HeadlessState.gpa, .{ .window = w, .time_ms = time_ms, .data = data }) catch {};
    HeadlessState.wake_flag.store(true, .release);
}
pub fn allocWindowId() u32 {
    const id = HeadlessState.next_id;
    HeadlessState.next_id += 1;
    return id;
}
pub fn appendWindow(w: *Window) !void {
    try HeadlessState.windows.append(HeadlessState.gpa, w);
}
pub fn setHeadlessImeActive(v: bool) void {
    HeadlessState.ime_active = v;
}
pub fn ensureTaskbarCreatedMsg(msg: u32) void {
    if (HeadlessState.taskbar_created_msg == 0) HeadlessState.taskbar_created_msg = msg;
}
pub fn taskbarCreatedMsg() u32 {
    return HeadlessState.taskbar_created_msg;
}
pub fn appendWinTrayEntry(id: u32, owner: *Window, hicon: ?*anyopaque, tooltip: []const u8) !void {
    const copy = try HeadlessState.gpa.dupe(u8, tooltip);
    HeadlessState.win_tray_entries.append(HeadlessState.gpa, .{ .id = id, .owner = owner, .hicon = hicon, .tooltip = copy }) catch |err| {
        HeadlessState.gpa.free(copy);
        return err;
    };
}
pub fn findWinTrayEntry(id: u32) ?*WinTrayEntry {
    for (HeadlessState.win_tray_entries.items) |*e| if (e.id == id) return e;
    return null;
}
pub fn updateWinTrayTooltip(e: *WinTrayEntry, tooltip: []const u8) !void {
    const copy = try HeadlessState.gpa.dupe(u8, tooltip);
    HeadlessState.gpa.free(e.tooltip);
    e.tooltip = copy;
}
pub fn removeWinTrayEntry(id: u32) void {
    var i: usize = 0;
    while (i < HeadlessState.win_tray_entries.items.len) {
        if (HeadlessState.win_tray_entries.items[i].id == id) {
            HeadlessState.gpa.free(HeadlessState.win_tray_entries.items[i].tooltip);
            _ = HeadlessState.win_tray_entries.swapRemove(i);
            return;
        }
        i += 1;
    }
}
pub fn winTrayEntriesSlice() []const WinTrayEntry {
    return HeadlessState.win_tray_entries.items;
}
pub fn dialogPathsSlice() []const Path {
    return HeadlessState.dialog_paths.items;
}

pub const Headless = struct {
    pub fn injectMouseMove(pos: Vec2i, mods: Mods) void {
        // 鼠标移动（坐标变化）使"键入时隐藏"的指针恢复（REQ-PLAT-037）。
        if (HeadlessState.last_mouse_pos == null or HeadlessState.last_mouse_pos.?.x != pos.x or HeadlessState.last_mouse_pos.?.y != pos.y) {
            HeadlessState.pointer_hidden = false;
        }
        HeadlessState.last_mouse_pos = pos;
        injectWindow(headlessRoot(), .{ .mouse_move = .{ .pos = pos, .mods = mods } });
    }
    pub fn injectMouseButton(button: MouseButton, down: bool, pos: Vec2i, mods: Mods) void {
        const w = headlessRoot();
        injectWindow(w, .{ .mouse_button = .{ .button = button, .down = down, .pos = pos, .mods = mods } });
        if (down and button == .left) {
            HeadlessState.captured_window = w;
            w.capture = true;
        } else if (!down and button == .left) {
            HeadlessState.captured_window = null;
            w.capture = false;
            const inside = pos.x >= 0 and pos.y >= 0 and pos.x < w.client.w and pos.y < w.client.h;
            if (!inside) injectWindow(w, .mouse_leave);
        }
    }
    pub fn injectWheel(dy: f32, pos: Vec2i, mods: Mods) void {
        const raw: i32 = @intFromFloat(@round(dy * @as(f32, @floatFromInt(wheel_delta))));
        injectWheelRaw(.vertical, raw, pos, mods);
    }
    /// 注入一个滚轮原始增量（1/120 格为单位）；`steps` 由该窗口该轴的累加器给出（REQ-PLAT-029）。线程：界面线程。
    pub fn injectWheelRaw(axis: Axis, raw: i32, pos: Vec2i, mods: Mods) void {
        const w = headlessRoot();
        const steps = accumulateWheel(&w.wheel_acc[@backingInt(axis)], raw);
        injectWindow(w, .{ .wheel = .{ .axis = axis, .raw = raw, .steps = steps, .pos = pos, .mods = mods } });
    }
    pub fn injectKey(vk: VirtualKey, down: bool, repeat: bool, mods: Mods) void {
        inject(.{ .key = .{ .vk = vk, .down = down, .repeat = repeat, .mods = mods } });
    }
    pub fn injectText(text: []const u8) void {
        const copy = HeadlessState.gpa.dupe(u8, text) catch return;
        noteTextEvent();
        injectWindow(headlessRoot(), .{ .text = copy });
    }
    /// 模拟一条 `WM_CHAR`（一个 UTF-16 单元）：代理对合并、孤立代理项丢弃并记一条 debug 日志、
    /// 控制字符不产生 `text` 事件（REQ-PLAT-032）。线程：界面线程。
    pub fn injectChar(unit: u16) void {
        const pending = HeadlessState.pending_high_surrogate;
        HeadlessState.pending_high_surrogate = null;
        if (isHighSurrogate(unit)) {
            if (pending) |p| logLoneSurrogate(p);
            HeadlessState.pending_high_surrogate = unit;
            return;
        }
        if (isLowSurrogate(unit)) {
            if (pending) |p| {
                const cp: u21 = @intCast(0x10000 + ((@as(u32, p) - 0xD800) << 10) + (@as(u32, unit) - 0xDC00));
                emitCodepoint(cp);
            } else logLoneSurrogate(unit);
            return;
        }
        if (pending) |p| logLoneSurrogate(p);
        if (unit < 0x20 or unit == 0x7F) return;
        emitCodepoint(unit);
    }
    /// 设置系统"键入时隐藏指针"（`SPI_GETMOUSEVANISH`）桩值（REQ-PLAT-037）。
    pub fn setMouseVanish(on: bool) void {
        HeadlessState.mouse_vanish = on;
    }
    /// 指针当前是否因"键入时隐藏"而被隐藏。
    pub fn pointerHidden() bool {
        return HeadlessState.pointer_hidden;
    }
    /// 实际应用形状到系统的次数（相同形状重复设置不计，REQ-PLAT-037）。
    pub fn cursorApplyCount() u64 {
        return HeadlessState.cursor_apply_count;
    }
    /// 后端读取系统度量/外观的次数（初始化与 `system_changed` 重读计数；帧内读取不计，REQ-PLAT-040）。
    pub fn systemQueryCount() u64 {
        return HeadlessState.system_query_count;
    }
    pub fn injectImeStart() void {
        HeadlessState.ime_active = true;
        HeadlessState.ime_text.clearRetainingCapacity();
        injectWindow(headlessRoot(), .ime_start);
    }
    pub fn injectImeUpdate(text: []const u8, cursor: usize) void {
        const copy = HeadlessState.gpa.dupe(u8, text) catch return;
        HeadlessState.ime_text.clearRetainingCapacity();
        HeadlessState.ime_text.appendSlice(HeadlessState.gpa, text) catch {};
        HeadlessState.ime_active = true;
        injectWindow(headlessRoot(), .{ .ime_update = .{ .text = copy, .cursor = cursor, .segments = &.{} } });
    }
    pub fn injectImeCommit(text: []const u8) void {
        const copy = HeadlessState.gpa.dupe(u8, text) catch return;
        injectWindow(headlessRoot(), .{ .ime_commit = copy });
    }
    pub fn injectImeEnd() void {
        HeadlessState.ime_active = false;
        injectWindow(headlessRoot(), .ime_end);
    }
    pub fn injectImeCancel() void {
        headlessCancelComposition();
    }
    pub fn inject(event: Data) void {
        switch (event) {
            .focus => |f| if (!f.gained) headlessCancelComposition(),
            // `VK_PROCESSKEY` 的按键事件不得交给上层（REQ-PLAT-031）。
            .key => |k| if (k.vk == .process_key) return,
            else => {},
        }
        injectWindow(headlessRoot(), event);
    }
    pub fn imeCaretRect() ?RectI {
        return HeadlessState.ime_caret_rect;
    }
    pub fn imeCaretExclude() ?RectI {
        return HeadlessState.ime_caret_exclude;
    }
    pub fn imeCaretCalls() usize {
        return HeadlessState.ime_caret_calls;
    }
    pub fn imeCancelCount() usize {
        return HeadlessState.ime_cancel_count;
    }
    pub fn imeCommitCount() usize {
        return HeadlessState.ime_commit_count;
    }
    pub fn imeEnabledCalls() usize {
        return HeadlessState.ime_enabled_calls;
    }
    pub fn minSizeChanges() usize {
        return HeadlessState.min_size_changes;
    }
    pub fn imeActive() bool {
        return HeadlessState.ime_active;
    }
    pub fn injectTray(id: u32, kind: TrayEventKind, pos: Vec2i) void {
        var owner = headlessRoot();
        for (HeadlessState.tray_entries.items) |e| if (e.id == id) {
            owner = e.owner;
        };
        injectWindow(owner, .{ .tray = .{ .id = id, .kind = kind, .screen_pos = pos } });
    }
    pub fn trayCount() usize {
        return HeadlessState.tray_entries.items.len;
    }
    pub fn trayTooltip(id: u32) ?[]const u8 {
        for (HeadlessState.tray_entries.items) |e| if (e.id == id) return e.tooltip;
        return null;
    }
    pub fn trayBalloon() ?struct { id: u32, title: []const u8, text: []const u8, kind: BalloonKind } {
        if (HeadlessState.tray_last_balloon) |b| return .{ .id = b.id, .title = b.title, .text = b.text, .kind = b.kind };
        return null;
    }
    /// 两个系统恢复通知合并为一个事件（REQ-PLAT-088）。
    pub fn injectPowerResume() void {
        if (HeadlessState.power_pending) return;
        HeadlessState.power_pending = true;
        injectWindow(headlessRoot(), .power_resume);
    }
    pub fn resize(w: i32, h: i32) void {
        resizeWindow(headlessRoot(), w, h);
    }
    /// 把指定窗口客户区设为 `w×h` ppx 并同步调用帧回调（`.size`）；0×0 即最小化（REQ-PLAT-022、REQ-PLAT-035）。线程：界面线程。
    pub fn resizeWindow(win: *Window, w: i32, h: i32) void {
        if (w == 0 and h == 0) {
            win.minimized = true;
            win.client = .{ .w = 0, .h = 0 };
        } else {
            win.minimized = false;
            win.client = .{ .w = w, .h = h };
            win.size_lpx = .{ .w = @as(f32, @floatFromInt(w)) / win.scale_value, .h = @as(f32, @floatFromInt(h)) / win.scale_value };
        }
        pushResize(win);
    }
    /// 进入系统拖动/缩放循环：建立周期计时器（REQ-PLAT-022 第 3 条）。线程：界面线程。
    pub fn simulateEnterSizeMove(win: *Window) void {
        win.modal_timer_active = true;
    }
    /// 退出系统拖动/缩放循环：销毁计时器（REQ-PLAT-022 第 3 条）。线程：界面线程。
    pub fn simulateExitSizeMove(win: *Window) void {
        win.modal_timer_active = false;
    }
    /// 模拟 `WM_TIMER`：计时器在运行时同步调用帧回调（`.timer`）。线程：界面线程。
    pub fn simulateTimer(win: *Window) void {
        if (!win.modal_timer_active) return;
        runFrame(win, .timer);
    }
    /// 模拟 `WM_PAINT`：产出 `repaint` 事件并同步调用帧回调（`.paint`，REQ-PLAT-022、REQ-PLAT-024）。线程：界面线程。
    pub fn simulatePaint(win: *Window, rect: RectI) void {
        injectWindow(win, .{ .repaint = .{ .rect = rect } });
        runFrame(win, .paint);
    }
    /// 窗口的模态计时器计数（0 或 1）。
    pub fn timerCount(win: *const Window) u32 {
        return if (win.modal_timer_active) 1 else 0;
    }
    /// 模态计时器周期（ms）：`ceil(1000 / 刷新率)`，刷新率取窗口所在显示器（REQ-PLAT-022、REQ-PLAT-021）。
    pub fn timerPeriodMs(win: *Window) u32 {
        return framePeriodMs(monitorFromWindow(win).refresh_hz);
    }
    /// 当前帧回调的嵌套调用深度（回调外为 0）。
    pub fn frameDepth() u32 {
        return HeadlessState.frame_depth;
    }
    /// 帧回调被调用的总次数。
    pub fn frameCallCount() u64 {
        return HeadlessState.frame_calls;
    }
    /// 在帧后动作中启动对话框/拖放产生的嵌套模态循环（`reason = .nested_modal`，REQ-PLAT-025）：
    /// 若此刻有帧在运行（深度不为 0）返回 `error.FrameReentry`；循环期间 owner 被禁用，输入事件不分发给它。
    /// 线程：界面线程。
    pub fn simulateNestedModal(owner: *Window, ctx: ?*anyopaque, body: *const fn (ctx: ?*anyopaque) void) error{FrameReentry}!void {
        if (HeadlessState.frame_depth != 0) return error.FrameReentry;
        owner.modal_disabled = true;
        defer owner.modal_disabled = false;
        body(ctx);
    }
    /// 嵌套模态循环内由 `WM_PAINT/WM_SIZE/WM_TIMER` 驱动一帧（REQ-PLAT-025）。线程：界面线程。
    pub fn simulateNestedFrame(owner: *Window, reason: FrameReason) void {
        runFrame(owner, reason);
    }
    /// 最近一次提交（`present`）所拷贝的源矩形（REQ-PLAT-024：整个客户区）。
    pub fn lastPresentSource() RectI {
        return HeadlessState.present_src;
    }
    pub fn setVisible(on: bool) void {
        headlessRoot().visible = on;
        pushVisibility(headlessRoot());
    }
    pub fn setActive(on: bool) void {
        if (!on) HeadlessState.pointer_hidden = false;
        headlessRoot().active = on;
        const e = Event{ .window = headlessRoot(), .time_ms = HeadlessState.now_ms, .data = .{ .activate = .{ .active = on } } };
        HeadlessState.events.append(HeadlessState.gpa, e) catch {};
        const f = Event{ .window = headlessRoot(), .time_ms = HeadlessState.now_ms, .data = .{ .focus = .{ .gained = on } } };
        HeadlessState.events.append(HeadlessState.gpa, f) catch {};
    }
    /// 设置 DPI：此后新建窗口采用该 DPI；已有的首个窗口立即切换，产出 `dpi_changed` 与按逻辑尺寸重算的 `resized`
    /// （REQ-PLAT-010、REQ-PLAT-012）。线程：界面线程。
    pub fn setDpi(dpi: u32) void {
        HeadlessState.dpi = dpi;
        HeadlessState.scale = @as(f32, @floatFromInt(dpi)) / @as(f32, @floatFromInt(default_dpi));
        if (HeadlessState.windows.items.len == 0) return;
        setWindowDpi(HeadlessState.windows.items[0], dpi);
    }
    /// 设置指定窗口的 DPI（见 `setDpi`）。线程：界面线程。
    pub fn setWindowDpi(win: *Window, dpi: u32) void {
        win.dpi = dpi;
        win.scale_value = @as(f32, @floatFromInt(dpi)) / @as(f32, @floatFromInt(default_dpi));
        const e = Event{ .window = win, .time_ms = HeadlessState.now_ms, .data = .{ .dpi_changed = .{ .dpi = dpi, .scale = win.scale_value } } };
        HeadlessState.events.append(HeadlessState.gpa, e) catch {};
        win.applyScaledClient();
        pushResize(win);
    }
    /// 注入系统度量变化：缓存先更新，再产出（同一轮合并的）`system_changed{metrics}`（REQ-PLAT-045、REQ-PLAT-046）。线程：界面线程。
    pub fn setMetrics(m: SystemMetrics) void {
        HeadlessState.metrics = m;
        HeadlessState.appearance.metrics = m;
        HeadlessState.system_query_count += 1;
        pushSystemChanged(.{ .metrics = true });
    }
    /// 注入系统外观变化：缓存先更新，再按差异产出 `system_changed`（深浅/强调色/高对比度/系统颜色为 `appearance`，
    /// 消息字体与文本大小为 `font`，度量为 `metrics`；无差异时按 `appearance`）。同一轮多次注入合并为一个事件。线程：界面线程。
    pub fn setAppearance(a: SystemAppearance) void {
        const old = HeadlessState.appearance;
        var what = SettingsChanged{};
        what.appearance = old.apps_dark != a.apps_dark or !std.meta.eql(old.accent, a.accent) or
            old.high_contrast != a.high_contrast or !std.meta.eql(old.sys_colors.map.values, a.sys_colors.map.values);
        what.font = !messageFontEql(old.message_font, a.message_font) or old.text_scale != a.text_scale;
        what.metrics = !std.meta.eql(old.metrics, a.metrics);
        if (!what.appearance and !what.font and !what.metrics) what.appearance = true;
        HeadlessState.appearance = a;
        HeadlessState.metrics = a.metrics;
        HeadlessState.system_query_count += 1;
        pushSystemChanged(what);
    }
    /// 测试夹具可替换显示器配置（REQ-PLAT-014、AC-PLAT-008）。
    /// 取不到刷新率（0）时按 60 Hz；`scale` 由 `dpi` 推出；变化时产出 `system_changed{display}`（REQ-PLAT-066）。线程：界面线程。
    pub fn setMonitors(list: []const Monitor) void {
        if (list.len == 0) return;
        const n = @min(list.len, max_monitors);
        for (list[0..n], 0..) |m, i| {
            monitors_buf[i] = m;
            if (m.refresh_hz == 0) monitors_buf[i].refresh_hz = fallback_refresh_hz;
            if (m.dpi != 0) monitors_buf[i].scale = @as(f32, @floatFromInt(m.dpi)) / @as(f32, @floatFromInt(default_dpi));
        }
        monitors_len = n;
        pushSystemChanged(.{ .display = true });
    }
    pub fn advanceMs(ms: u64) void {
        HeadlessState.now_ms += ms;
    }
    /// 推进 n 个垂直同步周期；每周期 1000 / refresh_hz ms，按累计取整（REQ-PLAT-086、REQ-TEST-016）。
    pub fn vsync(n: u32) void {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            HeadlessState.now_ms += peekVsyncPeriodMs();
            completeVsyncCycle();
        }
    }
    /// 下一个垂直同步周期的时长（ms）：第 k 周期为 floor((k+1)·1000/hz) − floor(k·1000/hz)，长期平均精确等于 1000/hz。
    pub fn peekVsyncPeriodMs() u64 {
        const hz: u64 = if (monitors_buf[0].refresh_hz > 0) monitors_buf[0].refresh_hz else fallback_refresh_hz;
        const k = HeadlessState.vsync_cycles;
        return (k + 1) * 1000 / hz - k * 1000 / hz;
    }
    /// 记一次垂直同步周期结束（不推进时钟）；供已自行推进时钟的回放运行器使用。
    pub fn completeVsyncCycle() void {
        HeadlessState.vsync_cycles += 1;
        HeadlessState.advance_frames += 1;
    }
    pub fn presentCount() u64 {
        return HeadlessState.present_count;
    }
    pub fn lastSessionAllowed() ?bool {
        return HeadlessState.session_allowed;
    }
    pub fn sessionAnswerCount() usize {
        return HeadlessState.session_answers;
    }
    pub fn windowCount() usize {
        return HeadlessState.windows.items.len;
    }
    pub fn setFileDialogResult(paths: ?[]const []const u8) void {
        HeadlessState.file_dialog_paths = paths;
    }
    pub fn setFontChoice(f: ?FontChoice) void {
        HeadlessState.font_choice = f;
    }
    pub fn setTaskResult(t: ?TaskResult) void {
        HeadlessState.task_result = t;
    }
    pub fn cursorShape() CursorShape {
        return HeadlessState.cursor;
    }
    pub fn captured() ?*Window {
        return HeadlessState.captured_window;
    }
    pub fn popupRects() []const RectI {
        return &.{};
    }
    pub fn nowMs() u64 {
        return HeadlessState.now_ms;
    }
    pub fn frameCount() u64 {
        return HeadlessState.advance_frames;
    }
};

fn headlessRoot() *Window {
    if (HeadlessState.windows.items.len == 0) {
        const w = createWindow(.{}) catch @panic("headless window creation failed");
        return w;
    }
    return HeadlessState.windows.items[0];
}

fn isInputEvent(data: Data) bool {
    return switch (data) {
        .mouse_move, .mouse_button, .wheel, .key, .text => true,
        else => false,
    };
}

fn messageFontEql(a: MessageFont, b: MessageFont) bool {
    return std.mem.eql(u8, a.family, b.family) and a.size_lpx == b.size_lpx and a.weight == b.weight and a.italic == b.italic;
}

fn mergeSettings(a: SettingsChanged, b: SettingsChanged) SettingsChanged {
    const Bits = @typeInfo(SettingsChanged).@"struct".backing_integer.?;
    return @bitCast(@as(Bits, @bitCast(a)) | @as(Bits, @bitCast(b)));
}

/// 产出 `system_changed`；队列中已有尚未投递的同类事件时合并为一个（位或，REQ-PLAT-045）。
fn pushSystemChanged(what: SettingsChanged) void {
    if (HeadlessState.windows.items.len == 0) return;
    injectWindow(HeadlessState.windows.items[0], .{ .system_changed = .{ .what = what } });
}

/// 一个滚轮累加器吸收 `raw`，返回本次产生的整数格数（向零取整，余数保留；方向反转先清零，REQ-PLAT-029）。线程：界面线程。
pub fn accumulateWheel(acc: *i32, raw: i32) i32 {
    if (raw != 0 and acc.* != 0 and (acc.* < 0) != (raw < 0)) acc.* = 0;
    acc.* += raw;
    const steps = @divTrunc(acc.*, wheel_delta);
    acc.* -= steps * wheel_delta;
    return steps;
}

/// 等待一帧所用的周期（ms）：`ceil(1000 / 刷新率)`，刷新率为 0 时按 60 Hz（REQ-PLAT-021）。线程安全。
pub fn framePeriodMs(refresh_hz: u32) u32 {
    const hz: u32 = if (refresh_hz == 0) fallback_refresh_hz else refresh_hz;
    return @intCast((ms_per_s + hz - 1) / hz);
}

fn isHighSurrogate(u: u16) bool {
    return u >= 0xD800 and u <= 0xDBFF;
}

fn isLowSurrogate(u: u16) bool {
    return u >= 0xDC00 and u <= 0xDFFF;
}

fn logLoneSurrogate(u: u16) void {
    core.log.scoped(.platform).debug("丢弃孤立代理项 U+{X:0>4}", .{u});
}

/// 产出 `text` 事件前的平台层副作用："键入时隐藏"指针（REQ-PLAT-037）。
fn noteTextEvent() void {
    if (HeadlessState.mouse_vanish) HeadlessState.pointer_hidden = true;
}

fn emitCodepoint(cp: u21) void {
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return;
    const copy = HeadlessState.gpa.dupe(u8, buf[0..n]) catch return;
    noteTextEvent();
    injectWindow(headlessRoot(), .{ .text = copy });
}

/// 同步调用窗口的帧回调并维护调用深度（REQ-PLAT-022）。
fn runFrame(win: *Window, reason: FrameReason) void {
    const cb = win.frame_callback orelse return;
    HeadlessState.frame_depth += 1;
    HeadlessState.frame_calls += 1;
    defer HeadlessState.frame_depth -= 1;
    cb(win, reason);
}

fn injectWindow(win: *Window, data: Data) void {
    // 嵌套模态循环期间，输入事件不分发到被禁用的 owner（REQ-PLAT-025）。
    if (win.modal_disabled and isInputEvent(data)) return;
    if (data == .system_changed) {
        for (HeadlessState.events.items) |*pending| {
            if (pending.data == .system_changed) {
                pending.data.system_changed.what = mergeSettings(pending.data.system_changed.what, data.system_changed.what);
                return;
            }
        }
    }
    const e = Event{ .window = win, .time_ms = HeadlessState.now_ms, .data = data };
    HeadlessState.events.append(HeadlessState.gpa, e) catch {};
    HeadlessState.wake_flag.store(true, .release);
}

fn pushResize(win: *Window) void {
    const e = Event{ .window = win, .time_ms = HeadlessState.now_ms, .data = .{ .resized = .{ .client = win.client, .state = if (win.minimized) .minimized else .normal } } };
    HeadlessState.events.append(HeadlessState.gpa, e) catch {};
    runFrame(win, .size);
}

fn pushVisibility(win: *Window) void {
    const e = Event{ .window = win, .time_ms = HeadlessState.now_ms, .data = .{ .visibility = .{ .visible = win.visible and !win.minimized } } };
    HeadlessState.events.append(HeadlessState.gpa, e) catch {};
}

/// 测试夹具/回放运行器可强制使用 headless 后端（REQ-TEST-020）。
pub fn forceHeadless() void {
    HeadlessState.force_headless = true;
}

pub fn init(allocator: std.mem.Allocator) !void {
    if (HeadlessState.initialized) return;
    if (is_windows and !HeadlessState.force_headless) win32.init();
    HeadlessState.gpa = allocator;
    HeadlessState.initialized = true;
    HeadlessState.metrics = .{};
    HeadlessState.appearance = defaultAppearance();
    HeadlessState.appearance.metrics = HeadlessState.metrics;
    HeadlessState.now_ms = 0;
    HeadlessState.wake_flag.store(false, .release);
    HeadlessState.scale = 1.0;
    HeadlessState.dpi = default_dpi;
    HeadlessState.frame_depth = 0;
    HeadlessState.frame_calls = 0;
    HeadlessState.cursor = .arrow;
    HeadlessState.cursor_apply_count = 0;
    HeadlessState.mouse_vanish = false;
    HeadlessState.pointer_hidden = false;
    HeadlessState.last_mouse_pos = null;
    HeadlessState.pending_high_surrogate = null;
    HeadlessState.captured_window = null;
    HeadlessState.present_src = .{};
    HeadlessState.present_count = 0;
    HeadlessState.vsync_cycles = 0;
    HeadlessState.advance_frames = 0;
    HeadlessState.system_query_count = 1; // 初始化时一次性读取系统度量与外观（REQ-PLAT-040）。
    injected_clock = null;
    monitors_buf = default_monitors;
    monitors_len = 1;
    HeadlessState.dialog_paths = .empty;
    HeadlessState.clipboard_seq = 0;
    HeadlessState.clipboard_custom = .empty;
    HeadlessState.clipboard_formats = .empty;
    HeadlessState.next_format_id = 1;
    HeadlessState.ime_active = false;
    HeadlessState.ime_enabled = true;
    HeadlessState.ime_text = .empty;
    HeadlessState.ime_caret_rect = null;
    HeadlessState.ime_caret_exclude = null;
    HeadlessState.ime_caret_calls = 0;
    HeadlessState.ime_cancel_count = 0;
    HeadlessState.ime_commit_count = 0;
    HeadlessState.ime_enabled_calls = 0;
    HeadlessState.min_size_changes = 0;
    HeadlessState.tray_entries = .empty;
    HeadlessState.tray_last_balloon = null;
    HeadlessState.win_tray_entries = .empty;
    HeadlessState.taskbar_created_msg = 0;
    HeadlessState.file_dialog_paths = null;
    HeadlessState.font_choice = null;
    HeadlessState.task_result = null;
    HeadlessState.session_answers = 0;
    HeadlessState.session_allowed = null;
}

pub fn deinit() void {
    if (!HeadlessState.initialized) return;
    HeadlessState.initialized = false;
    // 测试注入项不得泄漏到后续会话。
    injected_clock = null;
    monitors_buf = default_monitors;
    monitors_len = 1;
    HeadlessState.captured_window = null;
    for (HeadlessState.windows.items) |w| HeadlessState.gpa.destroy(w);
    HeadlessState.windows.deinit(HeadlessState.gpa);
    HeadlessState.windows = .empty;
    HeadlessState.events.deinit(HeadlessState.gpa);
    HeadlessState.events = .empty;
    HeadlessState.clipboard_text.deinit(HeadlessState.gpa);
    HeadlessState.clipboard_text = .empty;
    clearDialogPaths();
    HeadlessState.dialog_paths.deinit(HeadlessState.gpa);
    var cit = HeadlessState.clipboard_custom.valueIterator();
    while (cit.next()) |v| HeadlessState.gpa.free(v.*);
    HeadlessState.clipboard_custom.deinit(HeadlessState.gpa);
    for (HeadlessState.clipboard_formats.items) |f| HeadlessState.gpa.free(f.name);
    HeadlessState.clipboard_formats.deinit(HeadlessState.gpa);
    HeadlessState.ime_text.deinit(HeadlessState.gpa);
    for (HeadlessState.tray_entries.items) |e| HeadlessState.gpa.free(e.tooltip);
    HeadlessState.tray_entries.deinit(HeadlessState.gpa);
    if (HeadlessState.tray_last_balloon) |b| {
        HeadlessState.gpa.free(b.title);
        HeadlessState.gpa.free(b.text);
    }
    if (comptime is_windows) {
        for (HeadlessState.win_tray_entries.items) |e| {
            HeadlessState.gpa.free(e.tooltip);
            if (e.hicon) |h| win32.destroyIcon(h);
        }
    }
    HeadlessState.win_tray_entries.deinit(HeadlessState.gpa);
}

pub fn createWindow(opts: WindowOptions) !*Window {
    if (is_windows and !HeadlessState.force_headless) return win32.createWindow(opts);
    const w = try HeadlessState.gpa.create(Window);
    const clamped_lpx = core.Size{
        .w = @max(opts.client_size.w, opts.min_client_size.w),
        .h = @max(opts.client_size.h, opts.min_client_size.h),
    };
    const scaled_client = Size2i{
        .w = lpxToPpx(clamped_lpx.w, HeadlessState.scale),
        .h = lpxToPpx(clamped_lpx.h, HeadlessState.scale),
    };
    w.* = .{
        .id = HeadlessState.next_id,
        .title = opts.title,
        .client = scaled_client,
        .size_lpx = clamped_lpx,
        .min_client_size = opts.min_client_size,
        .scale_value = HeadlessState.scale,
        .dpi = @intFromFloat(HeadlessState.scale * 96.0),
        .visible = !opts.hidden,
        .placement = opts.placement orelse .{
            .normal_rect = .{ .x = 0, .y = 0, .w = scaled_client.w, .h = scaled_client.h },
            .state = opts.state,
            .dpi = @intFromFloat(HeadlessState.scale * 96.0),
        },
    };
    HeadlessState.next_id += 1;
    try HeadlessState.windows.append(HeadlessState.gpa, w);
    return w;
}

pub fn createPopup(owner: *Window, spec: PopupWindowSpec) !*Window {
    const w = try createWindow(.{
        .title = "",
        .client_size = .{ .w = @floatFromInt(spec.rect.w), .h = @floatFromInt(spec.rect.h) },
        .position = .{ .x = spec.rect.x, .y = spec.rect.y },
        .owner = owner,
        .hidden = true,
    });
    w.popup = true;
    w.popup_kind = spec.kind;
    w.owner = owner;
    return w;
}

pub fn destroyWindow(w: *Window) void {
    if (is_windows and !HeadlessState.force_headless) win32.destroyWindow(w);
    for (HeadlessState.windows.items, 0..) |item, i| {
        if (item == w) {
            _ = HeadlessState.windows.orderedRemove(i);
            if (HeadlessState.captured_window == w) HeadlessState.captured_window = null;
            HeadlessState.gpa.destroy(w);
            return;
        }
    }
}

pub fn destroyPopup(w: *Window) void {
    destroyWindow(w);
}

pub fn setFrameCallback(w: *Window, ctx: ?*anyopaque, cb: *const fn (w: *Window, reason: FrameReason) void) void {
    w.frame_ctx = ctx;
    w.frame_callback = cb;
}

pub fn pumpMessages(sink: EventSink) usize {
    HeadlessState.power_pending = false;
    if (is_windows and !HeadlessState.force_headless) _ = win32.pump();
    var n: usize = 0;
    while (HeadlessState.events.items.len > 0) {
        const e = HeadlessState.events.orderedRemove(0);
        sink.func(sink.ctx, e);
        switch (e.data) {
            .text => |t| HeadlessState.gpa.free(t),
            .ime_commit => |t| HeadlessState.gpa.free(t),
            .ime_update => |u| {
                HeadlessState.gpa.free(u.text);
                HeadlessState.gpa.free(u.segments);
            },
            else => {},
        }
        n += 1;
    }
    _ = HeadlessState.wake_flag.swap(false, .acq_rel);
    return n;
}

pub const WaitResult = enum { message, woken, timeout, idle };

pub fn waitMessages(timeout_ms: ?u32) WaitResult {
    if (is_windows and !HeadlessState.force_headless) return win32.wait(timeout_ms);
    if (HeadlessState.events.items.len > 0) return .message;
    if (HeadlessState.wake_flag.swap(false, .acq_rel)) return .woken;
    if (timeout_ms) |ms| {
        // 无头/假时钟：超时立即到达并推进注入时钟（AC-PLAT-012）。
        if (injected_clock == null) HeadlessState.now_ms +%= ms;
        return .timeout;
    }
    return .idle;
}

pub fn wake() void {
    HeadlessState.wake_flag.store(true, .release);
    if (is_windows and !HeadlessState.force_headless) win32.wake();
}

/// 平台单调时钟（ms，起点任意；注入的假时钟优先，无头默认为假时钟）。线程：界面线程。REQ-PLAT-038、REQ-PLAT-039。
pub fn nowMs() u64 {
    if (injected_clock) |clock| return clock.now_ms(clock.ctx);
    if (is_windows and !HeadlessState.force_headless) return win32.nowMs();
    return HeadlessState.now_ms;
}

/// 真实单调时钟（ms）：Win32 为 `QueryPerformanceCounter`，Linux 宿主为 `CLOCK_MONOTONIC`；与假时钟无关。
/// 线程安全。REQ-PLAT-038。
pub fn realNowMs() u64 {
    switch (builtin.os.tag) {
        .windows => return win32.nowMs(),
        .linux => {
            var ts: std.os.linux.timespec = undefined;
            _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
            const ns_per_ms: u64 = std.time.ns_per_ms;
            return @as(u64, @intCast(ts.sec)) * ms_per_s + @as(u64, @intCast(ts.nsec)) / ns_per_ms;
        },
        else => @compileError("不支持的宿主：仅 Windows 与 Linux（开发宿主）"),
    }
}

/// 时钟注入是否被允许：只允许无头模式或测试构建，发布构建的 Win32 后端不允许（REQ-PLAT-039）。
pub fn clockInjectionAllowed(native_win32: bool, test_build: bool) bool {
    return !native_win32 or test_build;
}

pub const Clock = struct {
    ctx: *anyopaque,
    now_ms: *const fn (*anyopaque) u64,
};

var injected_clock: ?Clock = null;

/// 注入（或用 `null` 取消）时钟；发布构建的 Win32 后端返回 `error.Unsupported`（REQ-PLAT-039）。线程：界面线程。
pub fn setClock(clock: ?Clock) !void {
    if (!clockInjectionAllowed(isNative(), builtin.is_test)) return error.Unsupported;
    injected_clock = clock;
}

/// 通知平台层最小客户区（lpx）；仅值变化时记录一次。
pub fn setMinSize(w: *Window, size: core.Size) void {
    if (w.min_client_size.w == size.w and w.min_client_size.h == size.h) return;
    w.min_client_size = size;
    HeadlessState.min_size_changes += 1;
}

pub fn metrics(_: ?*Window) SystemMetrics {
    return HeadlessState.metrics;
}

pub fn appearance(_: ?*Window) SystemAppearance {
    return HeadlessState.appearance;
}

/// 全部显示器（虚拟屏幕物理像素）。线程：界面线程。REQ-PLAT-066。
pub fn monitors() []const Monitor {
    return monitors_buf[0..monitors_len];
}

pub const Monitor = struct {
    handle: u64 = 1,
    bounds: RectI = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 },
    work_area: RectI = .{ .x = 0, .y = 0, .w = 1920, .h = 1040 },
    dpi: u32 = 96,
    scale: f32 = 1,
    refresh_hz: u32 = 60,
    primary: bool = true,
};

/// 无头后端可容纳的桩显示器数量上限。
const max_monitors = 8;
/// 无法取得刷新率时采用的值（REQ-PLAT-066、REQ-PLAT-021）。
const fallback_refresh_hz: u32 = 60;
const default_monitors: [max_monitors]Monitor = @splat(.{});
var monitors_buf: [max_monitors]Monitor = default_monitors;
var monitors_len: usize = 1;

fn initMonitors() void {
    _ = &monitors_buf;
}

/// 点到矩形的平方距离（点在矩形内为 0）。
fn pointRectDistSq(p: Vec2i, r: RectI) i64 {
    const dx: i64 = @max(@max(r.x - p.x, 0), p.x - (r.x + r.w - 1));
    const dy: i64 = @max(@max(r.y - p.y, 0), p.y - (r.y + r.h - 1));
    return dx * dx + dy * dy;
}

/// 返回包含该点的显示器；点在所有显示器之外时返回最近者（REQ-PLAT-066）。线程：界面线程。
pub fn monitorFromPoint(p: Vec2i) *const Monitor {
    var best: usize = 0;
    var best_d: i64 = std.math.maxInt(i64);
    for (monitors_buf[0..monitors_len], 0..) |m, i| {
        const d = pointRectDistSq(p, m.bounds);
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return &monitors_buf[best];
}

/// 返回窗口中心点所在（或最近）的显示器（REQ-PLAT-066）。线程：界面线程。
pub fn monitorFromWindow(w: *Window) *const Monitor {
    return monitorFromPoint(.{ .x = w.position.x + @divTrunc(w.client.w, 2), .y = w.position.y + @divTrunc(w.client.h, 2) });
}

pub fn validatePlacement(p: WindowPlacement) WindowPlacement {
    const caption_h: i32 = 23;
    const min_caption_w: i32 = 30;
    var out = p;
    var target: ?*const Monitor = null;
    var valid = false;
    for (monitors_buf[0..monitors_len]) |*m| {
        const wa = m.work_area;
        const ix = @max(p.normal_rect.x, wa.x);
        const iy = @max(p.normal_rect.y, wa.y);
        const ix2 = @min(p.normal_rect.x +| p.normal_rect.w, wa.x + wa.w);
        const iy2 = @min(p.normal_rect.y +| p.normal_rect.h, wa.y + wa.h);
        const iw = @max(0, ix2 - ix);
        const ih = @max(0, iy2 - iy);
        const area = @as(i64, @max(0, p.normal_rect.w)) * @max(0, p.normal_rect.h);
        const inter = @as(i64, iw) * ih;
        const enough_area = area > 0 and inter * 4 >= area;
        const title_y = p.normal_rect.y;
        const title_in = title_y >= wa.y and title_y + caption_h <= wa.y + wa.h and
            ix2 - ix >= min_caption_w;
        if (enough_area and title_in) {
            valid = true;
            target = m;
            break;
        }
        if (target == null) target = m;
    }
    const mon = target orelse {
        out.dpi = 96;
        return out;
    };
    const cur_dpi = mon.dpi;
    const saved_dpi: u32 = if (p.dpi == 0) 96 else p.dpi;
    var w: i32 = p.normal_rect.w;
    var h: i32 = p.normal_rect.h;
    if (cur_dpi != saved_dpi) {
        w = @intFromFloat(@round(@as(f64, @floatFromInt(p.normal_rect.w)) * @as(f64, @floatFromInt(cur_dpi)) / @as(f64, @floatFromInt(saved_dpi))));
        h = @intFromFloat(@round(@as(f64, @floatFromInt(p.normal_rect.h)) * @as(f64, @floatFromInt(cur_dpi)) / @as(f64, @floatFromInt(saved_dpi))));
    }
    w = std.math.clamp(w, 1, mon.work_area.w);
    h = std.math.clamp(h, 1, mon.work_area.h);
    if (valid) {
        out.normal_rect = .{
            .x = std.math.clamp(p.normal_rect.x, mon.work_area.x, mon.work_area.x + mon.work_area.w - w),
            .y = std.math.clamp(p.normal_rect.y, mon.work_area.y, mon.work_area.y + mon.work_area.h - h),
            .w = w,
            .h = h,
        };
    } else {
        out.normal_rect = .{
            .x = mon.work_area.x + 40,
            .y = mon.work_area.y + 40,
            .w = w,
            .h = h,
        };
    }
    out.dpi = cur_dpi;
    return out;
}

pub fn allowSessionEnd(allowed: bool) void {
    HeadlessState.session_allowed = allowed;
    HeadlessState.session_answers += 1;
}

pub fn present(w: *Window) void {
    HeadlessState.present_count += 1;
    // 提交拷贝的是整个渲染目标（即整个客户区），而非仅无效区（REQ-PLAT-024、REQ-GFX-005）。
    HeadlessState.present_src = .{ .x = 0, .y = 0, .w = @intCast(w.present_w), .h = @intCast(w.present_h) };
    if (is_windows and !HeadlessState.force_headless) win32.present(w);
}

/// UTF-16 转 UTF-8（REQ-PLAT-005）：孤立代理项转为 U+FFFD；调用方释放返回值。线程安全。
pub fn utf16ToUtf8Alloc(allocator: std.mem.Allocator, text: []const u16) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const u = text[i];
        var cp: u21 = u;
        if (isHighSurrogate(u) and i + 1 < text.len and isLowSurrogate(text[i + 1])) {
            cp = @intCast(0x10000 + ((@as(u32, u) - 0xD800) << 10) + (@as(u32, text[i + 1]) - 0xDC00));
            i += 1;
        } else if (isHighSurrogate(u) or isLowSurrogate(u)) {
            cp = replacement_char;
        }
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &buf) catch unreachable;
        try out.appendSlice(allocator, buf[0..n]);
    }
    return out.toOwnedSlice(allocator);
}

/// U+FFFD 替换字符。
pub const replacement_char: u21 = 0xFFFD;

/// UTF-8 转 UTF-16（REQ-PLAT-005）：非法字节序列每字节转为 U+FFFD；调用方释放返回值。线程安全。
pub fn utf8ToUtf16Alloc(allocator: std.mem.Allocator, text: []const u8) ![]u16 {
    var out = std.ArrayListUnmanaged(u16).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            try out.append(allocator, replacement_char);
            i += 1;
            continue;
        };
        if (i + len > text.len) {
            try out.append(allocator, replacement_char);
            i += 1;
            continue;
        }
        const cp = std.unicode.utf8Decode(text[i .. i + len]) catch {
            try out.append(allocator, replacement_char);
            i += 1;
            continue;
        };
        i += len;
        if (cp >= 0x10000) {
            const v: u32 = cp - 0x10000;
            try out.append(allocator, @intCast(0xD800 + (v >> 10)));
            try out.append(allocator, @intCast(0xDC00 + (v & 0x3FF)));
        } else {
            try out.append(allocator, @intCast(cp));
        }
    }
    return out.toOwnedSlice(allocator);
}

/// 长路径处理方式：由调用点选择（REQ-PLAT-005）。
pub const LongPathMode = enum {
    /// 超过 260 个单元时加 `\\?\` 前缀（仅限绝对路径）。
    prefix,
    /// 超过 260 个单元时返回 `error.PathTooLong`。
    reject,
};

/// 传统路径长度上限（`MAX_PATH`，单元）。
pub const max_path_units: usize = 260;
/// 扩展长度路径的总长度上限（单元，含前缀）。
pub const max_extended_path_units: usize = 32767;

/// 把 UTF-8 路径转为以 0 结尾的 UTF-16 路径（REQ-PLAT-005）。超过 `max_path_units` 时按 `mode`
/// 加 `\\?\` 前缀（UNC 为 `\\?\UNC\`，并把 `/` 换为 `\`）或返回 `error.PathTooLong`；
/// 加前缀后总长超过 `max_extended_path_units` 或路径不是绝对路径同样返回 `error.PathTooLong`。调用方释放返回值。线程安全。
pub fn pathToWide(allocator: std.mem.Allocator, utf8: []const u8, mode: LongPathMode) ![:0]u16 {
    const wide = try utf8ToUtf16Alloc(allocator, utf8);
    defer allocator.free(wide);
    if (wide.len <= max_path_units) return dupeWideZ(allocator, wide);
    if (mode == .reject) return error.PathTooLong;
    const ext_prefix = std.unicode.utf8ToUtf16LeStringLiteral("\\\\?\\");
    const unc_prefix = std.unicode.utf8ToUtf16LeStringLiteral("\\\\?\\UNC\\");
    const sep = std.unicode.utf8ToUtf16LeStringLiteral("\\");
    if (std.mem.startsWith(u16, wide, ext_prefix)) {
        if (wide.len > max_extended_path_units) return error.PathTooLong;
        return dupeWideZ(allocator, wide);
    }
    var head: []const u16 = undefined;
    var rest: []const u16 = undefined;
    const is_unc = wide.len >= 2 and isSeparator(wide[0]) and isSeparator(wide[1]);
    const is_drive = wide.len >= 3 and wide[1] == ':' and isSeparator(wide[2]) and
        ((wide[0] >= 'A' and wide[0] <= 'Z') or (wide[0] >= 'a' and wide[0] <= 'z'));
    if (is_unc) {
        head = unc_prefix;
        rest = wide[2..];
    } else if (is_drive) {
        head = ext_prefix;
        rest = wide;
    } else return error.PathTooLong;
    if (head.len + rest.len > max_extended_path_units) return error.PathTooLong;
    var out = try allocator.allocSentinel(u16, head.len + rest.len, 0);
    @memcpy(out[0..head.len], head);
    for (rest, 0..) |c, i| out[head.len + i] = if (c == '/') sep[0] else c;
    return out;
}

fn dupeWideZ(allocator: std.mem.Allocator, wide: []const u16) ![:0]u16 {
    const out = try allocator.allocSentinel(u16, wide.len, 0);
    @memcpy(out, wide);
    return out;
}

fn isSeparator(u: u16) bool {
    return u == '\\' or u == '/';
}

/// 由 `LOGFONT.lfHeight` 与取值所用 DPI 换算消息字体字号（lpx，REQ-PLAT-043）：
/// 负值为字符高度；正值为单元高度，须减去内部行距 `internal_leading`（ppx）得字符高度。线程安全。
pub fn messageFontSizeLpx(lf_height: i32, dpi: u32, internal_leading: i32) f32 {
    const char_height: i32 = if (lf_height < 0) -lf_height else lf_height - internal_leading;
    return @as(f32, @floatFromInt(char_height)) * @as(f32, @floatFromInt(default_dpi)) / @as(f32, @floatFromInt(dpi));
}

pub const FormatId = u32;
pub const ClipItem = union(enum) {
    text: []const u8,
    data: struct { format: FormatId, bytes: []const u8 },
};

fn rectEql(a: RectI, b: RectI) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

fn pushHeadlessImeEvent(data: Data) void {
    const w = headlessRoot();
    injectWindow(w, data);
}

fn headlessCancelComposition() void {
    if (!HeadlessState.ime_active) return;
    HeadlessState.ime_active = false;
    HeadlessState.ime_cancel_count += 1;
    HeadlessState.ime_text.clearRetainingCapacity();
    pushHeadlessImeEvent(.ime_end);
}

pub const ImeAttr = enum(u8) { input = 0, target_converted = 1, converted = 2, target_unconverted = 3, input_error = 4, fixed_converted = 5 };

/// 把 UTF-16 组字串与逐单元属性转换为 UTF-8 字节区间的段落（REQ-PLAT-052）。
pub fn imeSegmentsFromUtf16(allocator: std.mem.Allocator, text: []const u16, attrs: []const u8) ![]ImeSegment {
    var out = std.ArrayListUnmanaged(ImeSegment).empty;
    errdefer out.deinit(allocator);
    if (text.len == 0) return out.toOwnedSlice(allocator);
    var byte_pos: usize = 0;
    var run_start: usize = 0;
    var run_style = styleOfAttr(attrs[0]);
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        const style = if (i < text.len) styleOfAttr(attrs[i]) else run_style;
        if (i == text.len or style != run_style) {
            try out.append(allocator, .{ .start = @intCast(run_start), .end = @intCast(byte_pos), .style = run_style });
            run_start = byte_pos;
            run_style = style;
        }
        if (i < text.len) {
            var buf: [4]u8 = undefined;
            const cp: u21 = if (text[i] >= 0xD800 and text[i] <= 0xDBFF and i + 1 < text.len and text[i + 1] >= 0xDC00 and text[i + 1] <= 0xDFFF)
                @intCast(0x10000 + (@as(u32, text[i] - 0xD800) << 10) + (text[i + 1] - 0xDC00))
            else if (text[i] >= 0xD800 and text[i] <= 0xDFFF) 0xFFFD else @intCast(text[i]);
            const n = std.unicode.utf8Encode(cp, &buf) catch 1;
            byte_pos += n;
            if (cp >= 0x10000) i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn styleOfAttr(a: u8) ImeSegmentStyle {
    return switch (a) {
        1 => .target_converted,
        2 => .converted,
        3 => .target_unconverted,
        4 => .@"error",
        else => .unconverted,
    };
}

pub const clipboard = struct {
    fn normalizeLf(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out = std.ArrayListUnmanaged(u8).empty;
        errdefer out.deinit(allocator);
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            if (text[i] == '\r') {
                if (i + 1 < text.len and text[i + 1] == '\n') i += 1;
                try out.append(allocator, '\n');
            } else try out.append(allocator, text[i]);
        }
        return out.toOwnedSlice(allocator);
    }

    fn toCrLf(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out = std.ArrayListUnmanaged(u8).empty;
        errdefer out.deinit(allocator);
        for (text) |c| {
            if (c == '\n') try out.append(allocator, '\r');
            try out.append(allocator, c);
        }
        return out.toOwnedSlice(allocator);
    }

    pub fn getText(allocator: std.mem.Allocator) !?[]u8 {
        if (is_windows and !HeadlessState.force_headless) {
            const wide = try win32.clipboardGetText(allocator);
            if (wide == null) return null;
            defer allocator.free(wide.?);
            return try normalizeLf(allocator, wide.?);
        }
        if (HeadlessState.clipboard_text.items.len == 0) return null;
        return try normalizeLf(allocator, HeadlessState.clipboard_text.items);
    }

    pub fn setText(text: []const u8) !void {
        const normalized = try normalizeLf(HeadlessState.gpa, text);
        defer HeadlessState.gpa.free(normalized);
        if (is_windows and !HeadlessState.force_headless) {
            const crlf = try toCrLf(HeadlessState.gpa, normalized);
            defer HeadlessState.gpa.free(crlf);
            return win32.clipboardSetText(crlf);
        }
        HeadlessState.clipboard_text.clearRetainingCapacity();
        try HeadlessState.clipboard_text.appendSlice(HeadlessState.gpa, normalized);
        HeadlessState.clipboard_seq +%= 1;
    }

    pub fn registerFormat(name: []const u8) !FormatId {
        for (HeadlessState.clipboard_formats.items) |f| {
            if (std.mem.eql(u8, f.name, name)) return f.id;
        }
        const id = HeadlessState.next_format_id;
        HeadlessState.next_format_id += 1;
        const copy = try HeadlessState.gpa.dupe(u8, name);
        try HeadlessState.clipboard_formats.append(HeadlessState.gpa, .{ .id = id, .name = copy });
        return id;
    }

    fn setDataLocked(format: FormatId, bytes: []const u8) !void {
        const copy = try HeadlessState.gpa.dupe(u8, bytes);
        const gop = try HeadlessState.clipboard_custom.getOrPut(HeadlessState.gpa, format);
        if (gop.found_existing) HeadlessState.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = copy;
    }

    pub fn getData(format: FormatId, allocator: std.mem.Allocator) !?[]u8 {
        const v = HeadlessState.clipboard_custom.get(format) orelse return null;
        return try allocator.dupe(u8, v);
    }

    pub fn setData(format: FormatId, bytes: []const u8) !void {
        try setDataLocked(format, bytes);
        HeadlessState.clipboard_seq +%= 1;
    }

    /// 同一次写入中组合文本与自定义格式。
    pub fn setMany(items: []const ClipItem) !void {
        for (items) |item| switch (item) {
            .text => |t| try setText(t),
            .data => |d| try setDataLocked(d.format, d.bytes),
        };
        HeadlessState.clipboard_seq +%= 1;
    }

    pub fn hasText() bool {
        if (is_windows and !HeadlessState.force_headless) return win32.clipboardHasText();
        return HeadlessState.clipboard_text.items.len > 0;
    }

    pub fn sequenceNumber() u32 {
        if (is_windows and !HeadlessState.force_headless) return win32.clipboardSeq();
        return HeadlessState.clipboard_seq;
    }
};

pub const FileDialogOptions = struct {
    title: []const u8 = "",
    multi: bool = false,
    filters: []const []const u8 = &.{},
    initial_dir: ?[]const u8 = null,
    initial_name: ?[]const u8 = null,
};
pub const FontChoice = struct {
    family: []const u8 = "Segoe UI",
    size_lpx: f32 = 12,
    weight: u16 = 400,
    italic: bool = false,
};
pub const TaskDialogOptions = struct {
    title: []const u8 = "",
    instruction: []const u8 = "",
    body: ?[]const u8 = null,
    buttons: []const []const u8 = &.{},
    default_button: ?u32 = null,
    checkbox: ?[]const u8 = null,
};
pub const TaskResult = struct {
    button: ?u32 = null,
    checkbox_checked: bool = false,
};

pub const DropPayload = struct {
    paths: []const []const u8 = &.{},
    text: ?[]const u8 = null,
};

pub const DropTarget = struct {
    allocator: std.mem.Allocator,
    effect: DropEffect = .none,
    paths: std.ArrayListUnmanaged([]u8) = .empty,
    text: ?[]u8 = null,
    out: ?[]const []const u8 = null,
    truncated: bool = false,

    pub fn init(allocator: std.mem.Allocator) DropTarget {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *DropTarget) void {
        for (self.paths.items) |p| self.allocator.free(p);
        self.paths.deinit(self.allocator);
        if (self.text) |t| self.allocator.free(t);
        if (self.out) |o| self.allocator.free(o);
    }
    /// IDropTarget::DragEnter：数据被接受前返回 none。
    pub fn dragEnter(_: *DropTarget, _: []const []const u8, _: ?[]const u8) DropEffect {
        return .none;
    }
    /// IDropTarget::DragOver：返回上层本帧声明的效果。
    pub fn dragOver(self: *const DropTarget, _: Vec2i) DropEffect {
        return self.effect;
    }
    pub fn setDropEffect(self: *DropTarget, effect: DropEffect) void {
        self.effect = effect;
    }
    /// IDropTarget::Drop：在返回前深拷贝路径与文本。
    pub fn drop(self: *DropTarget, paths: []const []const u8, text: ?[]const u8) !DropPayload {
        for (self.paths.items) |p| self.allocator.free(p);
        self.paths.clearRetainingCapacity();
        if (self.text) |t| self.allocator.free(t);
        self.text = null;
        if (self.out) |o| self.allocator.free(o);
        self.out = null;
        const limit = @min(paths.len, 10_000);
        self.truncated = paths.len > 10_000;
        for (paths[0..limit]) |p| {
            const copy = try self.allocator.dupe(u8, p);
            try self.paths.append(self.allocator, copy);
        }
        if (text) |t| self.text = try self.allocator.dupe(u8, t);
        const out_paths = try self.allocator.alloc([]const u8, self.paths.items.len);
        for (self.paths.items, 0..) |p, i| out_paths[i] = p;
        self.out = out_paths;
        return .{ .paths = out_paths, .text = self.text };
    }
};

pub fn clearDialogPaths() void {
    for (HeadlessState.dialog_paths.items) |p| HeadlessState.gpa.free(p);
    HeadlessState.dialog_paths.clearRetainingCapacity();
}

pub fn addDialogPathUtf16(slice: []const u16) !void {
    const utf8 = try std.unicode.utf16LeToUtf8Alloc(HeadlessState.gpa, slice);
    try HeadlessState.dialog_paths.append(HeadlessState.gpa, utf8);
}

pub const dialogs = struct {
    pub fn openFileList(opts: FileDialogOptions) !?[]const Path {
        if (is_windows and !HeadlessState.force_headless) return win32.fileDialog(opts, false);
        if (HeadlessState.file_dialog_paths) |paths| return paths;
        return error.Unsupported;
    }
    pub fn saveFilePath(opts: FileDialogOptions) !?Path {
        if (is_windows and !HeadlessState.force_headless) {
            const paths = try win32.fileDialog(opts, true);
            return if (paths != null and paths.?.len > 0) paths.?[0] else null;
        }
        if (HeadlessState.file_dialog_paths) |paths| {
            return if (paths.len > 0) paths[0] else null;
        }
        return error.Unsupported;
    }

    pub fn pickFolderPath() !?Path {
        if (is_windows and !HeadlessState.force_headless) return win32.pickFolder(.{});
        if (HeadlessState.file_dialog_paths) |paths| {
            return if (paths.len > 0) paths[0] else null;
        }
        return error.Unsupported;
    }

    pub fn pickColorChoice(initial: core.Color) !?core.Color {
        if (is_windows and !HeadlessState.force_headless) return win32.pickColor(initial);
        return error.Unsupported;
    }
    pub fn pickFontChoice() !FontChoice {
        if (HeadlessState.font_choice) |f| return f;
        return error.Unsupported;
    }
    pub fn taskResult() !TaskResult {
        if (HeadlessState.task_result) |t| return t;
        return error.Unsupported;
    }
    pub fn openFile(_: ?*Window, _: anytype) !?[]const u8 {
        return error.Unsupported;
    }
    pub fn saveFile(_: ?*Window, _: anytype) !?[]const u8 {
        return error.Unsupported;
    }
    pub fn pickFolder(_: ?*Window, _: anytype) !?[]const u8 {
        return error.Unsupported;
    }
    pub fn pickColor(_: ?*Window, _: core.Color) !?core.Color {
        return error.Unsupported;
    }
    pub fn pickFont(_: ?*Window, _: anytype) !?anyopaque {
        return error.Unsupported;
    }
    pub fn taskDialog(_: ?*Window, _: anytype) !u32 {
        return error.Unsupported;
    }
};

var in_build: bool = false;

/// 由 `ui` 在构建期内设置；用于断言帧内阻塞调用（REQ-FRAME-027）。
pub fn setInBuild(v: bool) void {
    in_build = v;
}

pub fn messageBox(_: ?*Window, title: []const u8, text: []const u8, _: anytype) u32 {
    std.debug.assert(!in_build); // 构建函数内不得调用阻塞对话框
    std.debug.print("{s}: {s}\n", .{ title, text });
    return 1;
}

pub fn fatal(title: []const u8, text: []const u8) noreturn {
    std.debug.print("fatal: {s}: {s}\n", .{ title, text });
    std.process.exit(1);
}

pub const uia = @import("platform/uia.zig");

/// 返回当前进程累计 CPU 时间（毫秒），供 `S-IDLE` 预算测量使用（REQ-PERF-010）。线程：线程安全。
pub fn processCpuTimeMs() u64 {
    if (comptime builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        const rc = std.os.linux.clock_gettime(.PROCESS_CPUTIME_ID, &ts);
        if (rc == 0) {
            const sec_ms: u64 = @intCast(@max(0, ts.sec));
            const nsec_ms: u64 = @intCast(@max(0, @divTrunc(ts.nsec, 1_000_000)));
            return sec_ms * 1000 + nsec_ms;
        }
        return 0;
    } else if (comptime is_windows) {
        return win32.processCpuTimeMs();
    }
    return 0;
}

pub const tray = struct {
    pub const Error = error{ Unsupported, PlatformFailed, OutOfMemory };

    pub fn add(owner: *Window, id: u32, icon: IconSet, tooltip: []const u8) Error!void {
        if (comptime is_windows) {
            if (!HeadlessState.force_headless) return win32.trayAdd(owner, id, icon, tooltip);
        }
        const copy = HeadlessState.gpa.dupe(u8, tooltip) catch return error.OutOfMemory;
        for (HeadlessState.tray_entries.items) |*e| {
            if (e.id == id) {
                HeadlessState.gpa.free(e.tooltip);
                e.* = .{ .id = id, .owner = owner, .tooltip = copy };
                return;
            }
        }
        HeadlessState.tray_entries.append(HeadlessState.gpa, .{ .id = id, .owner = owner, .tooltip = copy }) catch return error.OutOfMemory;
    }

    pub fn modify(id: u32, icon: ?IconSet, tooltip: ?[]const u8) Error!void {
        if (comptime is_windows) {
            if (!HeadlessState.force_headless) return win32.trayModify(id, icon, tooltip);
        }
        for (HeadlessState.tray_entries.items) |*e| {
            if (e.id != id) continue;
            if (tooltip) |t| {
                const copy = HeadlessState.gpa.dupe(u8, t) catch return error.OutOfMemory;
                HeadlessState.gpa.free(e.tooltip);
                e.tooltip = copy;
            }
            return;
        }
        return error.PlatformFailed;
    }

    pub fn balloon(id: u32, title: []const u8, text: []const u8, kind: BalloonKind) Error!void {
        if (comptime is_windows) {
            if (!HeadlessState.force_headless) return win32.trayBalloon(id, title, text, kind);
        }
        const tcopy = HeadlessState.gpa.dupe(u8, title) catch return error.OutOfMemory;
        const bcopy = HeadlessState.gpa.dupe(u8, text) catch {
            HeadlessState.gpa.free(tcopy);
            return error.OutOfMemory;
        };
        if (HeadlessState.tray_last_balloon) |old| {
            HeadlessState.gpa.free(old.title);
            HeadlessState.gpa.free(old.text);
        }
        HeadlessState.tray_last_balloon = .{ .id = id, .title = tcopy, .text = bcopy, .kind = kind };
        return;
    }

    pub fn remove(id: u32) void {
        if (comptime is_windows) {
            if (!HeadlessState.force_headless) {
                win32.trayRemove(id);
                return;
            }
        }
        var i: usize = 0;
        while (i < HeadlessState.tray_entries.items.len) {
            if (HeadlessState.tray_entries.items[i].id == id) {
                HeadlessState.gpa.free(HeadlessState.tray_entries.items[i].tooltip);
                _ = HeadlessState.tray_entries.swapRemove(i);
                return;
            }
            i += 1;
        }
    }
};

pub fn startDrag(w: *Window, data: DragData, allowed: DropEffects) !DropEffect {
    if (!is_windows or HeadlessState.force_headless) return error.Unsupported;
    return win32.startDrag(w, data, allowed);
}

pub fn headless() type {
    return Headless;
}

test "headless event injection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try init(std.testing.allocator);
    defer deinit();
    const w = try createWindow(.{ .title = "t" });
    try std.testing.expectEqual(@as(i32, 800), w.client.w);
    Headless.injectMouseMove(.{ .x = 3, .y = 4 }, .{});
    const S = struct {
        var got: usize = 0;
        fn sink(_: ?*anyopaque, e: Event) void {
            if (e.data == .mouse_move) got += 1;
        }
    };
    S.got = 0;
    _ = pumpMessages(.{ .func = S.sink });
    try std.testing.expectEqual(@as(usize, 1), S.got);
}

// ---------------------------------------------------------------------------
// GLFW/无头降级矩阵（REQ-PLAT-083、REQ-PLAT-084）
// ---------------------------------------------------------------------------

pub const Capability = enum {
    process_init,
    window_creation,
    per_window_scale,
    dark_title_bar,
    placement,
    close_request,
    session_power,
    message_loop,
    nested_frame,
    mouse_key,
    mouse_capture,
    keyboard_text,
    ime,
    cursor_shape,
    clock,
    metrics,
    appearance,
    clipboard,
    dialogs,
    ole_drop,
    tray,
    monitors,
    popup_window,
    gl_context,
    vsync,
    context_loss,
};

pub const Support = enum { full, degraded, unsupported };

pub fn supportFor(cap: Capability) Support {
    return switch (cap) {
        .process_init, .window_creation, .close_request, .message_loop, .mouse_key, .clock, .clipboard, .monitors, .gl_context, .vsync => .full,
        .per_window_scale, .placement, .nested_frame, .mouse_capture, .keyboard_text, .ime, .cursor_shape, .metrics, .appearance, .ole_drop, .popup_window => .degraded,
        .dark_title_bar, .session_power, .dialogs, .tray, .context_loss => .unsupported,
    };
}
