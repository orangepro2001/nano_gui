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
const winapi = std.os.windows;

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
    wheel_chars: ScrollAmount = .{ .lines = 1 },
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
    scale_value: f32 = 1.0,
    dpi: u32 = 96,
    visible: bool = true,
    active: bool = true,
    minimized: bool = false,
    popup: bool = false,
    popup_kind: PopupWindowKind = .menu,
    owner: ?*Window = null,
    cursor: CursorShape = .arrow,
    capture: bool = false,
    hwnd: ?winapi.HWND = null,
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
        if (comptime is_windows) {
            if (self.hwnd) |h| {
                const z = std.unicode.utf8ToUtf16LeAllocZ(headless_state.gpa, title) catch return;
                defer headless_state.gpa.free(z);
                _ = w32.SetWindowTextW(h, z.ptr);
            }
        }
    }
    pub fn setClientSize(self: *Window, size: core.Size) void {
        self.client = .{ .w = @intFromFloat(@round(size.w * self.scale_value)), .h = @intFromFloat(@round(size.h * self.scale_value)) };
        pushResize(self);
    }
    pub fn setPosition(self: *Window, p: Vec2i) void {
        _ = self;
        _ = p;
    }
    pub fn show(self: *Window) void {
        self.visible = true;
        if (comptime is_windows) {
            if (self.hwnd) |h| _ = w32.ShowWindow(h, 5);
        }
        pushVisibility(self);
    }
    pub fn hide(self: *Window) void {
        self.visible = false;
        if (comptime is_windows) {
            if (self.hwnd) |h| _ = w32.ShowWindow(h, 0);
        }
        pushVisibility(self);
    }
    pub fn minimize(self: *Window) void {
        self.minimized = true;
        self.visible = true;
        if (comptime is_windows) {
            if (self.hwnd) |h| _ = w32.ShowWindow(h, 6);
        }
        pushVisibility(self);
    }
    pub fn maximize(self: *Window) void {
        self.minimized = false;
    }
    pub fn restore(self: *Window) void {
        self.minimized = false;
        self.visible = true;
        if (comptime is_windows) {
            if (self.hwnd) |h| _ = w32.ShowWindow(h, 9);
        }
        pushVisibility(self);
    }
    pub fn setMinClientSize(self: *Window, size: core.Size) void {
        _ = self;
        _ = size;
    }
    pub fn setIcon(self: *Window, icon: anytype) void {
        _ = self;
        _ = icon;
    }
    pub fn setCursor(self: *Window, shape: CursorShape) void {
        self.cursor = shape;
        headless_state.cursor = shape;
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
        if (on) headless_state.captured_window = self else if (headless_state.captured_window == self) headless_state.captured_window = null;
    }
    pub fn confirmClose(self: *Window) void {
        destroyWindow(self);
    }
    pub fn cancelClose(self: *Window) void {
        _ = self;
    }
    pub fn setImeCaretRect(self: *Window, caret: RectI, exclude: ?RectI) void {
        _ = self;
        _ = caret;
        _ = exclude;
    }
    pub fn setImeEnabled(self: *Window, enabled: bool) void {
        _ = self;
        _ = enabled;
    }
    pub fn commitComposition(self: *Window) void {
        _ = self;
    }
    pub fn setDropEffect(self: *Window, effect: DropEffect) void {
        _ = self;
        _ = effect;
    }
    pub fn getPlacement(self: *const Window) WindowPlacement {
        return .{ .normal_rect = .{ .x = 0, .y = 0, .w = self.client.w, .h = self.client.h }, .state = if (self.minimized) .minimized else .normal, .dpi = self.dpi };
    }
};

pub const FrameReason = enum { size, paint, timer, nested_modal };

const headless_state = struct {
    var gpa: std.mem.Allocator = std.heap.smp_allocator;
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
    var appearance: SystemAppearance = .{};
    var present_count: u64 = 0;
    var advance_frames: u64 = 0;
    var scale: f32 = 1.0;
};

pub const Headless = struct {
    pub fn injectMouseMove(pos: Vec2i, mods: Mods) void {
        injectWindow(headlessRoot(), .{ .mouse_move = .{ .pos = pos, .mods = mods } });
    }
    pub fn injectMouseButton(button: MouseButton, down: bool, pos: Vec2i, mods: Mods) void {
        injectWindow(headlessRoot(), .{ .mouse_button = .{ .button = button, .down = down, .pos = pos, .mods = mods } });
    }
    pub fn injectWheel(dy: f32, pos: Vec2i, mods: Mods) void {
        const raw: i32 = @intFromFloat(@round(dy * 120.0));
        injectWindow(headlessRoot(), .{ .wheel = .{ .axis = .vertical, .raw = raw, .steps = @divTrunc(raw, 120), .pos = pos, .mods = mods } });
    }
    pub fn injectKey(vk: VirtualKey, down: bool, repeat: bool, mods: Mods) void {
        injectWindow(headlessRoot(), .{ .key = .{ .vk = vk, .down = down, .repeat = repeat, .mods = mods } });
    }
    pub fn injectText(text: []const u8) void {
        const copy = headless_state.gpa.dupe(u8, text) catch return;
        injectWindow(headlessRoot(), .{ .text = copy });
    }
    pub fn injectImeStart() void {
        injectWindow(headlessRoot(), .ime_start);
    }
    pub fn injectImeUpdate(text: []const u8, cursor: usize) void {
        const copy = headless_state.gpa.dupe(u8, text) catch return;
        injectWindow(headlessRoot(), .{ .ime_update = .{ .text = copy, .cursor = cursor, .segments = &.{} } });
    }
    pub fn injectImeCommit(text: []const u8) void {
        const copy = headless_state.gpa.dupe(u8, text) catch return;
        injectWindow(headlessRoot(), .{ .ime_commit = copy });
    }
    pub fn injectImeEnd() void {
        injectWindow(headlessRoot(), .ime_end);
    }
    pub fn injectImeCancel() void {
        injectWindow(headlessRoot(), .ime_end);
    }
    pub fn inject(event: Data) void {
        injectWindow(headlessRoot(), event);
    }
    pub fn resize(w: i32, h: i32) void {
        const win = headlessRoot();
        win.client = .{ .w = w, .h = h };
        pushResize(win);
    }
    pub fn setVisible(on: bool) void {
        headlessRoot().visible = on;
        pushVisibility(headlessRoot());
    }
    pub fn setActive(on: bool) void {
        headlessRoot().active = on;
        const e = Event{ .window = headlessRoot(), .time_ms = headless_state.now_ms, .data = .{ .activate = .{ .active = on } } };
        headless_state.events.append(headless_state.gpa, e) catch {};
        const f = Event{ .window = headlessRoot(), .time_ms = headless_state.now_ms, .data = .{ .focus = .{ .gained = on } } };
        headless_state.events.append(headless_state.gpa, f) catch {};
    }
    pub fn setDpi(dpi: u32) void {
        const win = headlessRoot();
        win.dpi = dpi;
        win.scale_value = @as(f32, @floatFromInt(dpi)) / 96.0;
        const e = Event{ .window = win, .time_ms = headless_state.now_ms, .data = .{ .dpi_changed = .{ .dpi = dpi, .scale = win.scale_value } } };
        headless_state.events.append(headless_state.gpa, e) catch {};
    }
    pub fn setMetrics(m: SystemMetrics) void {
        headless_state.metrics = m;
        headless_state.appearance.metrics = m;
    }
    pub fn setAppearance(a: SystemAppearance) void {
        headless_state.appearance = a;
        headless_state.metrics = a.metrics;
    }
    pub fn advanceMs(ms: u64) void {
        headless_state.now_ms += ms;
    }
    pub fn vsync(n: u32) void {
        headless_state.advance_frames += n;
        headless_state.now_ms += @as(u64, n) * 16;
    }
    pub fn presentCount() u64 {
        return headless_state.present_count;
    }
    pub fn cursorShape() CursorShape {
        return headless_state.cursor;
    }
    pub fn captured() ?*Window {
        return headless_state.captured_window;
    }
    pub fn popupRects() []const RectI {
        return &.{};
    }
    pub fn nowMs() u64 {
        return headless_state.now_ms;
    }
    pub fn frameCount() u64 {
        return headless_state.advance_frames;
    }
};

fn headlessRoot() *Window {
    if (headless_state.windows.items.len == 0) {
        const w = createWindow(.{}) catch @panic("headless window creation failed");
        return w;
    }
    return headless_state.windows.items[0];
}

fn injectWindow(win: *Window, data: Data) void {
    const e = Event{ .window = win, .time_ms = headless_state.now_ms, .data = data };
    headless_state.events.append(headless_state.gpa, e) catch {};
    headless_state.wake_flag.store(true, .release);
}

fn pushResize(win: *Window) void {
    const e = Event{ .window = win, .time_ms = headless_state.now_ms, .data = .{ .resized = .{ .client = win.client, .state = if (win.minimized) .minimized else .normal } } };
    headless_state.events.append(headless_state.gpa, e) catch {};
    if (win.frame_callback) |cb| cb(win, .size);
}

fn pushVisibility(win: *Window) void {
    const e = Event{ .window = win, .time_ms = headless_state.now_ms, .data = .{ .visibility = .{ .visible = win.visible and !win.minimized } } };
    headless_state.events.append(headless_state.gpa, e) catch {};
}

pub fn init(allocator: std.mem.Allocator) !void {
    if (headless_state.initialized) return;
    if (comptime is_windows) w32Init();
    headless_state.gpa = allocator;
    headless_state.initialized = true;
    headless_state.metrics = .{};
    headless_state.appearance = .{};
    headless_state.appearance.metrics = headless_state.metrics;
}

pub fn deinit() void {
    if (!headless_state.initialized) return;
    headless_state.initialized = false;
    for (headless_state.windows.items) |w| headless_state.gpa.destroy(w);
    headless_state.windows.deinit(headless_state.gpa);
    headless_state.windows = .empty;
    headless_state.events.deinit(headless_state.gpa);
    headless_state.events = .empty;
    headless_state.clipboard_text.deinit(headless_state.gpa);
    headless_state.clipboard_text = .empty;
}

pub fn createWindow(opts: WindowOptions) !*Window {
    if (comptime is_windows) return w32CreateWindow(opts);
    const w = try headless_state.gpa.create(Window);
    w.* = .{
        .id = headless_state.next_id,
        .title = opts.title,
        .client = .{
            .w = @intFromFloat(@round(opts.client_size.w)),
            .h = @intFromFloat(@round(opts.client_size.h)),
        },
        .scale_value = headless_state.scale,
        .dpi = @intFromFloat(headless_state.scale * 96.0),
        .visible = !opts.hidden,
    };
    headless_state.next_id += 1;
    try headless_state.windows.append(headless_state.gpa, w);
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
    if (comptime is_windows) {
        if (w.hwnd) |h| {
            _ = w32.DestroyWindow(h);
            w.hwnd = null;
        }
    }
    for (headless_state.windows.items, 0..) |item, i| {
        if (item == w) {
            _ = headless_state.windows.orderedRemove(i);
            if (headless_state.captured_window == w) headless_state.captured_window = null;
            headless_state.gpa.destroy(w);
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
    if (comptime is_windows) _ = w32Pump();
    var n: usize = 0;
    while (headless_state.events.items.len > 0) {
        const e = headless_state.events.orderedRemove(0);
        sink.func(sink.ctx, e);
        switch (e.data) {
            .text => |t| headless_state.gpa.free(t),
            .ime_commit => |t| headless_state.gpa.free(t),
            .ime_update => |u| {
                headless_state.gpa.free(u.text);
                headless_state.gpa.free(u.segments);
            },
            else => {},
        }
        n += 1;
    }
    _ = headless_state.wake_flag.swap(false, .acq_rel);
    return n;
}

pub const WaitResult = enum { message, woken, timeout, idle };

pub fn waitMessages(timeout_ms: ?u32) WaitResult {
    if (comptime is_windows) return w32Wait(timeout_ms);
    if (headless_state.events.items.len > 0) return .message;
    if (headless_state.wake_flag.swap(false, .acq_rel)) return .woken;
    if (timeout_ms) |ms| {
        // 无头/假时钟：超时立即到达并推进注入时钟（AC-PLAT-012）。
        if (injected_clock == null) headless_state.now_ms +%= ms;
        return .timeout;
    }
    return .idle;
}

pub fn wake() void {
    headless_state.wake_flag.store(true, .release);
    if (comptime is_windows) _ = w32.PostThreadMessageW(w32_thread_id, 0, 0, 0);
}

pub fn nowMs() u64 {
    if (injected_clock) |clock| return clock.now_ms(clock.ctx);
    if (comptime is_windows) return w32Now();
    return headless_state.now_ms;
}

pub const Clock = struct {
    ctx: *anyopaque,
    now_ms: *const fn (*anyopaque) u64,
};

var injected_clock: ?Clock = null;

pub fn setClock(clock: ?Clock) !void {
    injected_clock = clock;
}

pub fn metrics(_: ?*Window) SystemMetrics {
    return headless_state.metrics;
}

pub fn appearance(_: ?*Window) SystemAppearance {
    return headless_state.appearance;
}

pub fn monitors() []const Monitor {
    return headless_state.monitors[0..];
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

var monitors_buf: [1]Monitor = .{.{}};

fn initMonitors() void {
    headless_state.monitors = monitors_buf[0..];
}

pub fn monitorFromPoint(_: Vec2i) *const Monitor {
    return &monitors_buf[0];
}

pub fn monitorFromWindow(_: *Window) *const Monitor {
    return &monitors_buf[0];
}

pub fn validatePlacement(p: WindowPlacement) WindowPlacement {
    var out = p;
    out.normal_rect = .{
        .x = std.math.clamp(p.normal_rect.x, 0, 1920 - 200),
        .y = std.math.clamp(p.normal_rect.y, 0, 1040 - 100),
        .w = std.math.clamp(p.normal_rect.w, 200, 1920),
        .h = std.math.clamp(p.normal_rect.h, 100, 1040),
    };
    out.dpi = 96;
    return out;
}

pub fn allowSessionEnd(_: bool) void {}

pub fn present(w: *Window) void {
    headless_state.present_count += 1;
    if (comptime is_windows) w32Present(w);
}

pub const clipboard = struct {
    pub fn getText(allocator: std.mem.Allocator) !?[]u8 {
        if (headless_state.clipboard_text.items.len == 0) return null;
        return try allocator.dupe(u8, headless_state.clipboard_text.items);
    }
    pub fn setText(text: []const u8) !void {
        headless_state.clipboard_text.clearRetainingCapacity();
        try headless_state.clipboard_text.appendSlice(headless_state.gpa, text);
    }
    pub fn hasText() bool {
        return headless_state.clipboard_text.items.len > 0;
    }
    pub fn sequenceNumber() u32 {
        return @intCast(headless_state.clipboard_text.items.len);
    }
};

pub const dialogs = struct {
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

pub fn messageBox(_: ?*Window, title: []const u8, text: []const u8, _: anytype) u32 {
    std.debug.print("{s}: {s}\n", .{ title, text });
    return 1;
}

pub fn fatal(title: []const u8, text: []const u8) noreturn {
    std.debug.print("fatal: {s}: {s}\n", .{ title, text });
    std.process.exit(1);
}

pub const uia = struct {
    pub fn isEnabled() bool {
        return false;
    }
};

pub const tray = struct {
    pub fn add(_: anytype) !u32 {
        return error.Unsupported;
    }
    pub fn remove(_: u32) void {}
};

pub fn startDrag(_: *Window, _: anytype, _: anytype) !DropEffect {
    return error.Unsupported;
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
// Win32 一等后端（编译期选择；Linux 构建不进入这些分支）
// ---------------------------------------------------------------------------

const w32 = struct {
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
    const WM_SYSKEYDOWN: u32 = 0x0104;
    const WM_SYSKEYUP: u32 = 0x0105;
    const WM_CHAR: u32 = 0x0102;
    const WM_SETFOCUS: u32 = 0x0007;
    const WM_KILLFOCUS: u32 = 0x0008;
    const WM_ACTIVATE: u32 = 0x0006;
    const WM_ACTIVATEAPP: u32 = 0x001C;
    const WM_DPICHANGED: u32 = 0x02E0;
    const WM_GETMINMAXINFO: u32 = 0x0024;
    const WM_SETCURSOR: u32 = 0x0020;
    const WM_ERASEBKGND: u32 = 0x0014;
    const WM_TIMER: u32 = 0x0113;
    const PM_REMOVE: u32 = 1;
    const QS_ALLINPUT: u32 = 0x04FF;
    const MWMO_INPUTAVAILABLE: u32 = 0x0004;
    const CW_USEDEFAULT: i32 = -2147483648;

    const WNDCLASSW = extern struct {
        style: u32 = 0,
        lpfnWndProc: *const fn (winapi.HWND, u32, usize, isize) callconv(.winapi) isize = undefined,
        cbClsExtra: i32 = 0,
        cbWndExtra: i32 = 0,
        hInstance: ?winapi.HINSTANCE = null,
        hIcon: ?*anyopaque = null,
        hCursor: ?*anyopaque = null,
        hbrBackground: ?*anyopaque = null,
        lpszMenuName: ?[*:0]const u16 = null,
        lpszClassName: [*:0]const u16 = undefined,
    };
    const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
    const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
    const MSG = extern struct {
        hwnd: ?winapi.HWND = null,
        message: u32 = 0,
        wParam: usize = 0,
        lParam: isize = 0,
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
    const PAINTSTRUCT = extern struct {
        hdc: ?*anyopaque = null,
        fErase: i32 = 0,
        rcPaint: RECT = .{},
        fRestore: i32 = 0,
        fIncUpdate: i32 = 0,
        rgbReserved: [32]u8 = @splat(0),
    };
    const MINMAXINFO = extern struct { ptReserved: POINT = .{}, ptMaxSize: POINT = .{}, ptMaxPosition: POINT = .{}, ptMinTrackSize: POINT = .{}, ptMaxTrackSize: POINT = .{} };

    extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?winapi.HINSTANCE;
    extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
    extern "kernel32" fn QueryPerformanceCounter(v: *i64) callconv(.winapi) i32;
    extern "kernel32" fn QueryPerformanceFrequency(v: *i64) callconv(.winapi) i32;
    extern "user32" fn RegisterClassW(c: *const WNDCLASSW) callconv(.winapi) u16;
    extern "user32" fn CreateWindowExW(ex: u32, class: [*:0]const u16, title: [*:0]const u16, style: u32, x: i32, y: i32, w: i32, h: i32, parent: ?winapi.HWND, menu: ?*anyopaque, inst: ?winapi.HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?winapi.HWND;
    extern "user32" fn DefWindowProcW(h: winapi.HWND, m: u32, w: usize, l: isize) callconv(.winapi) isize;
    extern "user32" fn DestroyWindow(h: winapi.HWND) callconv(.winapi) i32;
    extern "user32" fn ShowWindow(h: winapi.HWND, cmd: i32) callconv(.winapi) i32;
    extern "user32" fn UpdateWindow(h: winapi.HWND) callconv(.winapi) i32;
    extern "user32" fn GetClientRect(h: winapi.HWND, r: *RECT) callconv(.winapi) i32;
    extern "user32" fn GetWindowRect(h: winapi.HWND, r: *RECT) callconv(.winapi) i32;
    extern "user32" fn AdjustWindowRectEx(r: *RECT, style: u32, menu: i32, ex: u32) callconv(.winapi) i32;
    extern "user32" fn GetDpiForWindow(h: winapi.HWND) callconv(.winapi) u32;
    extern "user32" fn PeekMessageW(m: *MSG, h: ?winapi.HWND, min: u32, max: u32, remove: u32) callconv(.winapi) i32;
    extern "user32" fn TranslateMessage(m: *const MSG) callconv(.winapi) i32;
    extern "user32" fn DispatchMessageW(m: *const MSG) callconv(.winapi) isize;
    extern "user32" fn MsgWaitForMultipleObjectsEx(count: u32, handles: ?*const anyopaque, ms: u32, wake: u32, flags: u32) callconv(.winapi) u32;
    extern "user32" fn PostThreadMessageW(id: u32, msg: u32, w: usize, l: isize) callconv(.winapi) i32;
    extern "user32" fn GetKeyState(vk: i32) callconv(.winapi) i16;
    extern "user32" fn ScreenToClient(h: winapi.HWND, p: *POINT) callconv(.winapi) i32;
    extern "user32" fn BeginPaint(h: winapi.HWND, ps: *PAINTSTRUCT) callconv(.winapi) ?*anyopaque;
    extern "user32" fn EndPaint(h: winapi.HWND, ps: *const PAINTSTRUCT) callconv(.winapi) i32;
    extern "user32" fn SetWindowTextW(h: winapi.HWND, text: [*:0]const u16) callconv(.winapi) i32;
    extern "user32" fn GetDC(h: winapi.HWND) callconv(.winapi) ?*anyopaque;
    extern "user32" fn ReleaseDC(h: winapi.HWND, dc: ?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn SetCursor(c: ?*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "user32" fn LoadCursorW(inst: ?winapi.HINSTANCE, name: usize) callconv(.winapi) ?*anyopaque;
    extern "gdi32" fn SetDIBitsToDevice(dc: ?*anyopaque, x: i32, y: i32, w: u32, h: u32, sx: i32, sy: i32, start: u32, lines: u32, bits: *const anyopaque, bmi: *const BITMAPINFO, usage: u32) callconv(.winapi) i32;
};

var w32_class_registered: bool = false;
var w32_instance: ?winapi.HINSTANCE = null;
var w32_thread_id: u32 = 0;
var w32_qpc_freq: i64 = 0;

fn w32Init() void {
    if (w32_class_registered) return;
    w32_instance = w32.GetModuleHandleW(null);
    w32_thread_id = w32.GetCurrentThreadId();
    _ = w32.QueryPerformanceFrequency(&w32_qpc_freq);
    const cls = std.unicode.utf8ToUtf16LeStringLiteral("nano_gui_win32");
    const wc = w32.WNDCLASSW{ .lpfnWndProc = w32Proc, .hInstance = w32_instance, .lpszClassName = cls };
    _ = w32.RegisterClassW(&wc);
    w32_class_registered = true;
}

fn w32Find(hwnd: winapi.HWND) ?*Window {
    for (headless_state.windows.items) |w| {
        if (w.hwnd) |h| if (h == hwnd) return w;
    }
    return null;
}

fn w32Push(w: *Window, data: Data) void {
    const e = Event{ .window = w, .time_ms = nowMs(), .data = data };
    headless_state.events.append(headless_state.gpa, e) catch {};
}

fn w32Mods() Mods {
    return .{
        .shift = (@as(u16, @bitCast(w32.GetKeyState(0x10))) & 0x8000) != 0,
        .ctrl = (@as(u16, @bitCast(w32.GetKeyState(0x11))) & 0x8000) != 0,
        .alt = (@as(u16, @bitCast(w32.GetKeyState(0x12))) & 0x8000) != 0,
        .win = ((@as(u16, @bitCast(w32.GetKeyState(0x5B))) | @as(u16, @bitCast(w32.GetKeyState(0x5C)))) & 0x8000) != 0,
    };
}

fn w32Proc(hwnd: winapi.HWND, msg: u32, wp: usize, lp: isize) callconv(.winapi) isize {
    const w = w32Find(hwnd) orelse return w32.DefWindowProcW(hwnd, msg, wp, lp);
    const x: i32 = @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lp))))));
    const y: i32 = @as(i16, @bitCast(@as(u16, @truncate((@as(usize, @bitCast(lp)) >> 16)))));
    switch (msg) {
        w32.WM_MOUSEMOVE => w32Push(w, .{ .mouse_move = .{ .pos = .{ .x = x, .y = y }, .mods = w32Mods() } }),
        w32.WM_LBUTTONDOWN, w32.WM_LBUTTONUP => w32Push(w, .{ .mouse_button = .{ .button = .left, .down = msg == w32.WM_LBUTTONDOWN, .pos = .{ .x = x, .y = y }, .mods = w32Mods() } }),
        w32.WM_RBUTTONDOWN, w32.WM_RBUTTONUP => w32Push(w, .{ .mouse_button = .{ .button = .right, .down = msg == w32.WM_RBUTTONDOWN, .pos = .{ .x = x, .y = y }, .mods = w32Mods() } }),
        w32.WM_MBUTTONDOWN, w32.WM_MBUTTONUP => w32Push(w, .{ .mouse_button = .{ .button = .middle, .down = msg == w32.WM_MBUTTONDOWN, .pos = .{ .x = x, .y = y }, .mods = w32Mods() } }),
        w32.WM_MOUSEWHEEL => {
            var pt = w32.POINT{ .x = x, .y = y };
            _ = w32.ScreenToClient(hwnd, &pt);
            const raw: i16 = @bitCast(@as(u16, @truncate((wp >> 16))));
            w32Push(w, .{ .wheel = .{ .axis = .vertical, .raw = raw, .steps = @divTrunc(raw, 120), .pos = .{ .x = pt.x, .y = pt.y }, .mods = w32Mods() } });
        },
        w32.WM_KEYDOWN, w32.WM_SYSKEYDOWN, w32.WM_KEYUP, w32.WM_SYSKEYUP => {
            const down = msg == w32.WM_KEYDOWN or msg == w32.WM_SYSKEYDOWN;
            const vk: u16 = @truncate(wp & 0xFFFF);
            const lp_u: usize = @bitCast(lp);
            if (std.enums.fromInt(VirtualKey, vk)) |key| {
                w32Push(w, .{ .key = .{ .vk = key, .scancode = @truncate(lp_u), .down = down, .repeat = ((lp_u >> 30) & 1) != 0, .mods = w32Mods(), .extended = ((lp_u >> 24) & 1) != 0 } });
            }
        },
        w32.WM_CHAR => {
            const cp: u21 = @intCast(@as(u16, @truncate(wp & 0xFFFF)));
            if (cp >= 0x20 and cp != 0x7F) {
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &buf) catch 0;
                if (n > 0) {
                    const copy = headless_state.gpa.dupe(u8, buf[0..n]) catch return 0;
                    w32Push(w, .{ .text = copy });
                }
            }
        },
        w32.WM_SETFOCUS => w32Push(w, .{ .focus = .{ .gained = true } }),
        w32.WM_KILLFOCUS => w32Push(w, .{ .focus = .{ .gained = false } }),
        w32.WM_ACTIVATE => w32Push(w, .{ .activate = .{ .active = (wp & 0xFFFF) != 0, .by_click = (wp >> 16) == 2 } }),
        w32.WM_SIZE => {
            var r: w32.RECT = .{};
            _ = w32.GetClientRect(hwnd, &r);
            w.client = .{ .w = r.right - r.left, .h = r.bottom - r.top };
            w32Push(w, .{ .resized = .{ .client = w.client, .state = if (r.right - r.left == 0) .minimized else .normal } });
            if (w.frame_callback) |cb| cb(w, .size);
        },
        w32.WM_DPICHANGED => {
            const dpi: u32 = @truncate(wp & 0xFFFF);
            w.dpi = dpi;
            w.scale_value = @as(f32, @floatFromInt(dpi)) / 96.0;
            w32Push(w, .{ .dpi_changed = .{ .dpi = dpi, .scale = w.scale_value } });
        },
        w32.WM_PAINT => {
            var ps: w32.PAINTSTRUCT = .{};
            _ = w32.BeginPaint(hwnd, &ps);
            w32Push(w, .{ .repaint = .{ .rect = .{ .x = 0, .y = 0, .w = w.client.w, .h = w.client.h } } });
            _ = w32.EndPaint(hwnd, &ps);
            return 0;
        },
        w32.WM_ERASEBKGND => return 1,
        w32.WM_CLOSE => {
            w32Push(w, .close_requested);
            return 0;
        },
        w32.WM_DESTROY => {
            w32Push(w, .{ .visibility = .{ .visible = false } });
        },
        w32.WM_GETMINMAXINFO => {},
        else => {},
    }
    return w32.DefWindowProcW(hwnd, msg, wp, lp);
}

fn w32CreateWindow(opts: WindowOptions) !*Window {
    w32Init();
    const w = try headless_state.gpa.create(Window);
    w.* = .{
        .id = headless_state.next_id,
        .title = opts.title,
        .client = .{ .w = @intFromFloat(@round(opts.client_size.w)), .h = @intFromFloat(@round(opts.client_size.h)) },
        .visible = !opts.hidden,
        .dpi = 96,
    };
    headless_state.next_id += 1;
    var r = w32.RECT{ .left = 0, .top = 0, .right = w.client.w, .bottom = w.client.h };
    _ = w32.AdjustWindowRectEx(&r, 0x00CF0000, 0, 0);
    const title_z = try std.unicode.utf8ToUtf16LeAllocZ(headless_state.gpa, opts.title);
    defer headless_state.gpa.free(title_z);
    const cls = std.unicode.utf8ToUtf16LeStringLiteral("nano_gui_win32");
    const hwnd = w32.CreateWindowExW(0, cls, title_z.ptr, 0x00CF0000, w32.CW_USEDEFAULT, w32.CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, null, null, w32_instance, null) orelse return error.CreateWindowFailed;
    w.hwnd = hwnd;
    const dpi = w32.GetDpiForWindow(hwnd);
    if (dpi != 0) {
        w.dpi = dpi;
        w.scale_value = @as(f32, @floatFromInt(dpi)) / 96.0;
    }
    try headless_state.windows.append(headless_state.gpa, w);
    if (!opts.hidden) {
        _ = w32.ShowWindow(hwnd, 5);
        _ = w32.UpdateWindow(hwnd);
    }
    return w;
}

fn w32Pump() usize {
    var msg: w32.MSG = .{};
    var n: usize = 0;
    while (w32.PeekMessageW(&msg, null, 0, 0, w32.PM_REMOVE) != 0) {
        _ = w32.TranslateMessage(&msg);
        _ = w32.DispatchMessageW(&msg);
        n += 1;
    }
    return n;
}

fn w32Wait(timeout_ms: ?u32) WaitResult {
    const ms: u32 = if (timeout_ms) |v| v else 0xFFFFFFFF;
    const r = w32.MsgWaitForMultipleObjectsEx(0, null, ms, w32.QS_ALLINPUT, w32.MWMO_INPUTAVAILABLE);
    if (r == 0) return .message;
    if (r == 258) return .timeout;
    return .idle;
}

fn w32Now() u64 {
    var c: i64 = 0;
    _ = w32.QueryPerformanceCounter(&c);
    if (w32_qpc_freq == 0) return @intCast(@divTrunc(c, 1000));
    return @intCast(@divTrunc(c * 1000, w32_qpc_freq));
}

fn w32Present(w: *Window) void {
    const hwnd = w.hwnd orelse return;
    if (w.present_rgba.len == 0 or w.present_w == 0 or w.present_h == 0) return;
    const dc = w32.GetDC(hwnd) orelse return;
    defer _ = w32.ReleaseDC(hwnd, dc);
    var bmi = w32.BITMAPINFO{};
    bmi.bmiHeader.biWidth = @intCast(w.present_w);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(w.present_h));
    var buf = headless_state.gpa.alloc(u8, w.present_rgba.len) catch return;
    defer headless_state.gpa.free(buf);
    var i: usize = 0;
    while (i < w.present_rgba.len / 4) : (i += 1) {
        const o = i * 4;
        buf[o] = w.present_rgba[o + 2];
        buf[o + 1] = w.present_rgba[o + 1];
        buf[o + 2] = w.present_rgba[o];
        buf[o + 3] = 0;
    }
    _ = w32.SetDIBitsToDevice(dc, 0, 0, w.present_w, w.present_h, 0, 0, 0, w.present_h, buf.ptr, &bmi, 0);
}
