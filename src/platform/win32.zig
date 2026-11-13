//! Win32 一等后端实现（REQ-ARCH-003、REQ-ARCH-004）。
//! 仅 `src/platform/win32*.zig` 允许引用 Win32 符号。

const std = @import("std");
const core = @import("../core.zig");
const plat = @import("../platform.zig");
const w32 = @import("win32_bindings.zig");
const uia = @import("uia.zig");

const DataObjectImpl = struct {
    vtbl: *const w32.IDATAOBJECTVTBL,
    refs: u32 = 1,
    files: []const plat.Path = &.{},
    text: ?[]const u8 = null,
};

const DropTargetImpl = struct {
    vtbl: *const w32.IDROPTARGETVTBL,
    window: *plat.Window,
    refs: u32 = 1,
};

var w32_class_registered: bool = false;
var w32_instance: ?w32.HINSTANCE = null;
var w32_thread_id: u32 = 0;
var w32_qpc_freq: i64 = 0;

fn asHwnd(raw: ?*anyopaque) ?w32.HWND {
    const p = raw orelse return null;
    return @ptrCast(@alignCast(p));
}

pub fn init() void {
    if (w32_class_registered) return;
    _ = w32.OleInitialize(null);
    w32_instance = w32.GetModuleHandleW(null);
    w32_thread_id = w32.GetCurrentThreadId();
    _ = w32.QueryPerformanceFrequency(&w32_qpc_freq);
    const cls = std.unicode.utf8ToUtf16LeStringLiteral("nano_gui_win32");
    const wc = w32.WNDCLASSW{ .lpfnWndProc = w32Proc, .hInstance = w32_instance, .lpszClassName = cls };
    _ = w32.RegisterClassW(&wc);
    w32_class_registered = true;
}

pub fn wake() void {
    _ = w32.PostThreadMessageW(w32_thread_id, 0, 0, 0);
}

pub fn setTitle(w: *plat.Window, title: []const u8) void {
    if (asHwnd(w.hwnd)) |h| {
        const z = std.unicode.utf8ToUtf16LeAllocZ(plat.headlessGpa(), title) catch return;
        defer plat.headlessGpa().free(z);
        _ = w32.SetWindowTextW(h, z.ptr);
    }
}

pub fn showWindow(w: *plat.Window, cmd: i32) void {
    if (asHwnd(w.hwnd)) |h| _ = w32.ShowWindow(h, cmd);
}

pub fn destroyWindow(w: *plat.Window) void {
    if (w.hdc) |dc| {
        if (w.hglrc) |rc| {
            if (w.gl_deinit_fn) |df| df(dc, rc);
        }
        if (asHwnd(w.hwnd)) |h| _ = w32.ReleaseDC(h, dc);
        w.hglrc = null;
        w.hdc = null;
        w.gl_ready = false;
    }
    winUnregisterDropTarget(w);
    if (asHwnd(w.hwnd)) |h| {
        _ = w32.DestroyWindow(h);
        w.hwnd = null;
    }
}

pub fn destroyIcon(hicon: *anyopaque) void {
    _ = w32.DestroyIcon(hicon);
}

pub fn processCpuTimeMs() u64 {
    var c: w32.FILETIME = .{};
    var e: w32.FILETIME = .{};
    var k: w32.FILETIME = .{};
    var u: w32.FILETIME = .{};
    if (w32.GetProcessTimes(w32.GetCurrentProcess(), &c, &e, &k, &u) != 0) {
        const kt = (@as(u64, k.dwHighDateTime) << 32) | k.dwLowDateTime;
        const ut = (@as(u64, u.dwHighDateTime) << 32) | u.dwLowDateTime;
        return (kt + ut) / 10_000;
    }
    return 0;
}

fn w32Find(hwnd: w32.HWND) ?*plat.Window {
    for (plat.windowsSlice()) |w| {
        if (asHwnd(w.hwnd)) |h| if (h == hwnd) return w;
    }
    return null;
}

fn w32Push(w: *plat.Window, data: plat.Data) void {
    plat.pushBackendEvent(w, nowMs(), data);
}

fn w32Mods() plat.Mods {
    return .{
        .shift = (@as(u16, @bitCast(w32.GetKeyState(0x10))) & 0x8000) != 0,
        .ctrl = (@as(u16, @bitCast(w32.GetKeyState(0x11))) & 0x8000) != 0,
        .alt = (@as(u16, @bitCast(w32.GetKeyState(0x12))) & 0x8000) != 0,
        .win = ((@as(u16, @bitCast(w32.GetKeyState(0x5B))) | @as(u16, @bitCast(w32.GetKeyState(0x5C)))) & 0x8000) != 0,
    };
}

const wm_tray_callback: u32 = 0x8001;

fn fillWide(dst: []u16, text: []const u8) void {
    var i: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |cp| {
        if (i >= dst.len - 1) break;
        dst[i] = @intCast(cp);
        i += 1;
    }
    dst[i] = 0;
}

fn winDropQueryInterface(this: *anyopaque, riid: *const w32.GUID, ppv: *?*anyopaque) callconv(.winapi) i32 {
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    if (std.mem.eql(u8, std.mem.asBytes(riid), std.mem.asBytes(&w32.IID_IDROPTARGET)) or
        std.mem.eql(u8, std.mem.asBytes(riid), std.mem.asBytes(&w32.IID_IUNKNOWN)))
    {
        dt.refs += 1;
        ppv.* = this;
        return 0;
    }
    ppv.* = null;
    return @bitCast(@as(u32, 0x80004002));
}
fn winDropAddRef(this: *anyopaque) callconv(.winapi) u32 {
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    dt.refs += 1;
    return dt.refs;
}
fn winDropRelease(this: *anyopaque) callconv(.winapi) u32 {
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    if (dt.refs > 0) dt.refs -= 1;
    return dt.refs;
}
fn winDropFormats(obj: ?*w32.IDATAOBJECT) plat.DropFormats {
    var out = plat.DropFormats{};
    const o = obj orelse return out;
    var f1 = w32.FORMATETC{ .cfFormat = @intCast(w32.CF_HDROP) };
    var f2 = w32.FORMATETC{ .cfFormat = @intCast(w32.CF_UNICODETEXT) };
    out.files = o.vtbl.QueryGetData(@ptrCast(o), &f1) == 0;
    out.text = o.vtbl.QueryGetData(@ptrCast(o), &f2) == 0;
    return out;
}
fn winClientPos(window: *plat.Window, pt: w32.POINTL) plat.Vec2i {
    var p = w32.POINT{ .x = pt.x, .y = pt.y };
    if (asHwnd(window.hwnd)) |h| _ = w32.ScreenToClient(h, &p);
    return .{ .x = p.x, .y = p.y };
}
fn winDragEnter(this: *anyopaque, data: ?*w32.IDATAOBJECT, keys: u32, pt: w32.POINTL, effect: *u32) callconv(.winapi) i32 {
    _ = keys;
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    w32Push(dt.window, .{ .drag_enter = .{ .formats = winDropFormats(data), .pos = winClientPos(dt.window, pt), .effects_allowed = .{ .copy = true, .move = true, .link = true } } });
    effect.* = 0;
    return 0;
}
fn winDragOver(this: *anyopaque, keys: u32, pt: w32.POINTL, effect: *u32) callconv(.winapi) i32 {
    _ = keys;
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    w32Push(dt.window, .{ .drag_over = .{ .pos = winClientPos(dt.window, pt), .mods = .{} } });
    effect.* = switch (dt.window.drop_effect) {
        .none => 0,
        .copy => 1,
        .move => 2,
        .link => 4,
    };
    return 0;
}
fn winDragLeave(this: *anyopaque) callconv(.winapi) i32 {
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    w32Push(dt.window, .drag_leave);
    return 0;
}
fn winReadDrop(data: ?*w32.IDATAOBJECT, pos: plat.Vec2i) plat.DropData {
    const gpa = plat.headlessGpa();
    var out = plat.DropData{ .allocator = gpa };
    const o = data orelse return out;
    var files = std.ArrayListUnmanaged(plat.Path).empty;
    var fmt = w32.FORMATETC{ .cfFormat = @intCast(w32.CF_HDROP) };
    var med = w32.STGMEDIUM{};
    if (o.vtbl.GetData(@ptrCast(o), &fmt, &med) == 0) {
        const count = w32.DragQueryFileW(med.hGlobal, 0xFFFFFFFF, undefined, 0);
        const limit = @min(count, 10_000);
        var i: u32 = 0;
        while (i < limit) : (i += 1) {
            const n = w32.DragQueryFileW(med.hGlobal, i, undefined, 0);
            const buf = gpa.alloc(u16, n + 1) catch break;
            defer gpa.free(buf);
            _ = w32.DragQueryFileW(med.hGlobal, i, buf.ptr, n + 1);
            const utf8 = std.unicode.utf16LeToUtf8Alloc(gpa, buf[0..n]) catch continue;
            files.append(gpa, utf8) catch {
                gpa.free(utf8);
                break;
            };
        }
        w32.ReleaseStgMedium(&med);
    }
    if (files.items.len > 0) out.files = files.toOwnedSlice(gpa) catch &.{};
    var fmt2 = w32.FORMATETC{ .cfFormat = @intCast(w32.CF_UNICODETEXT) };
    var med2 = w32.STGMEDIUM{};
    if (o.vtbl.GetData(@ptrCast(o), &fmt2, &med2) == 0) {
        const lock = w32.GlobalLock(med2.hGlobal);
        if (lock) |p| {
            const wptr: [*:0]const u16 = @ptrCast(@alignCast(p));
            const slice = std.mem.sliceTo(wptr, 0);
            out.text = std.unicode.utf16LeToUtf8Alloc(gpa, slice) catch null;
            _ = w32.GlobalUnlock(med2.hGlobal);
        }
        w32.ReleaseStgMedium(&med2);
    }
    _ = pos;
    return out;
}
fn winDrop(this: *anyopaque, data: ?*w32.IDATAOBJECT, keys: u32, pt: w32.POINTL, effect: *u32) callconv(.winapi) i32 {
    _ = keys;
    const dt: *DropTargetImpl = @ptrCast(@alignCast(this));
    const payload = winReadDrop(data, winClientPos(dt.window, pt));
    w32Push(dt.window, .{ .drop = .{ .data = payload, .pos = winClientPos(dt.window, pt) } });
    effect.* = switch (dt.window.drop_effect) {
        .none => 0,
        .copy => 1,
        .move => 2,
        .link => 4,
    };
    return 0;
}

fn dObjQueryInterface(this: *anyopaque, riid: *const w32.GUID, ppv: *?*anyopaque) callconv(.winapi) i32 {
    const o: *DataObjectImpl = @ptrCast(@alignCast(this));
    if (std.mem.eql(u8, std.mem.asBytes(riid), std.mem.asBytes(&w32.IID_IDATAOBJECT)) or
        std.mem.eql(u8, std.mem.asBytes(riid), std.mem.asBytes(&w32.IID_IUNKNOWN)))
    {
        o.refs += 1;
        ppv.* = this;
        return 0;
    }
    ppv.* = null;
    return @bitCast(@as(u32, 0x80004002));
}
fn dObjAddRef(this: *anyopaque) callconv(.winapi) u32 {
    const o: *DataObjectImpl = @ptrCast(@alignCast(this));
    o.refs += 1;
    return o.refs;
}
fn dObjRelease(this: *anyopaque) callconv(.winapi) u32 {
    const o: *DataObjectImpl = @ptrCast(@alignCast(this));
    if (o.refs > 0) o.refs -= 1;
    return o.refs;
}
fn dObjGetData(this: *anyopaque, fmt: *const w32.FORMATETC, medium: *w32.STGMEDIUM) callconv(.winapi) i32 {
    const o: *DataObjectImpl = @ptrCast(@alignCast(this));
    const gpa = plat.headlessGpa();
    medium.* = .{ .tymed = 1 };
    if (fmt.cfFormat == w32.CF_UNICODETEXT) {
        const t = o.text orelse return @bitCast(@as(u32, 0x80040064));
        const wide = std.unicode.utf8ToUtf16LeAllocZ(gpa, t) catch return @bitCast(@as(u32, 0x8007000E));
        defer gpa.free(wide);
        const bytes = wide.len * 2;
        const mem = w32.GlobalAlloc(w32.GMEM_MOVEABLE, bytes) orelse return @bitCast(@as(u32, 0x8007000E));
        const lock = w32.GlobalLock(mem) orelse {
            _ = w32.GlobalFree(mem);
            return @bitCast(@as(u32, 0x8007000E));
        };
        @memcpy(@as([*]u8, @ptrCast(lock))[0..bytes], std.mem.sliceAsBytes(wide));
        _ = w32.GlobalUnlock(mem);
        medium.hGlobal = mem;
        return 0;
    }
    if (fmt.cfFormat == w32.CF_HDROP) {
        if (o.files.len == 0) return @bitCast(@as(u32, 0x80040064));
        var total: usize = @sizeOf(w32.DROPFILES);
        for (o.files) |f| total += (std.unicode.utf8CountCodepoints(f) catch f.len) * 2 + 2;
        total += 2;
        const mem = w32.GlobalAlloc(w32.GMEM_MOVEABLE, total) orelse return @bitCast(@as(u32, 0x8007000E));
        const lock = w32.GlobalLock(mem) orelse {
            _ = w32.GlobalFree(mem);
            return @bitCast(@as(u32, 0x8007000E));
        };
        const bytes: [*]u8 = @ptrCast(lock);
        @memset(bytes[0..total], 0);
        const header: *w32.DROPFILES = @ptrCast(@alignCast(bytes));
        header.* = .{};
        var pos: usize = @sizeOf(w32.DROPFILES);
        for (o.files) |f| {
            const wide = std.unicode.utf8ToUtf16LeAllocZ(gpa, f) catch continue;
            defer gpa.free(wide);
            const n = wide.len * 2;
            @memcpy(bytes[pos .. pos + n], std.mem.sliceAsBytes(wide));
            pos += n;
        }
        _ = w32.GlobalUnlock(mem);
        medium.hGlobal = mem;
        return 0;
    }
    return @bitCast(@as(u32, 0x80040064));
}
fn dObjQueryGetData(this: *anyopaque, fmt: *const w32.FORMATETC) callconv(.winapi) i32 {
    const o: *DataObjectImpl = @ptrCast(@alignCast(this));
    if (fmt.cfFormat == w32.CF_UNICODETEXT and o.text != null) return 0;
    if (fmt.cfFormat == w32.CF_HDROP and o.files.len > 0) return 0;
    return @bitCast(@as(u32, 0x80040064));
}
fn dObjNotImpl() callconv(.winapi) i32 {
    return @bitCast(@as(u32, 0x80004001));
}
const data_vtbl = w32.IDATAOBJECTVTBL{
    .QueryInterface = dObjQueryInterface,
    .AddRef = dObjAddRef,
    .Release = dObjRelease,
    .GetData = dObjGetData,
    .GetDataHere = &dObjNotImpl,
    .QueryGetData = dObjQueryGetData,
    .GetCanonicalFormatEtc = &dObjNotImpl,
    .SetData = &dObjNotImpl,
    .EnumFormatEtc = &dObjNotImpl,
    .DAdvise = &dObjNotImpl,
    .DUnadvise = &dObjNotImpl,
    .EnumDAdvise = &dObjNotImpl,
};

fn dropSrcQueryInterface(this: *anyopaque, riid: *const w32.GUID, ppv: *?*anyopaque) callconv(.winapi) i32 {
    if (std.mem.eql(u8, std.mem.asBytes(riid), std.mem.asBytes(&w32.IID_IDROPSOURCE)) or
        std.mem.eql(u8, std.mem.asBytes(riid), std.mem.asBytes(&w32.IID_IUNKNOWN)))
    {
        ppv.* = this;
        return 0;
    }
    ppv.* = null;
    return @bitCast(@as(u32, 0x80004002));
}
fn dropSrcAddRef(_: *anyopaque) callconv(.winapi) u32 {
    return 1;
}
fn dropSrcRelease(_: *anyopaque) callconv(.winapi) u32 {
    return 1;
}
fn dropSrcQueryContinueDrag(_: *anyopaque, escape: i32, _: u32) callconv(.winapi) i32 {
    if (escape != 0 and (w32.GetKeyState(0x1B) & 0x8000) != 0) return 0x00040101;
    return 0;
}
fn dropSrcGiveFeedback(_: *anyopaque, _: u32) callconv(.winapi) i32 {
    return 0x00040102;
}
const drop_src_vtbl = w32.IDROPSOURCEVTBL{
    .QueryInterface = dropSrcQueryInterface,
    .AddRef = dropSrcAddRef,
    .Release = dropSrcRelease,
    .QueryContinueDrag = dropSrcQueryContinueDrag,
    .GiveFeedback = dropSrcGiveFeedback,
};

const drop_vtbl = w32.IDROPTARGETVTBL{
    .QueryInterface = winDropQueryInterface,
    .AddRef = winDropAddRef,
    .Release = winDropRelease,
    .DragEnter = winDragEnter,
    .DragOver = winDragOver,
    .DragLeave = winDragLeave,
    .Drop = winDrop,
};

fn winRegisterDropTarget(w: *plat.Window) void {
    const hwnd = asHwnd(w.hwnd) orelse return;
    const dt = plat.headlessGpa().create(DropTargetImpl) catch return;
    dt.* = .{ .vtbl = &drop_vtbl, .window = w };
    if (w32.RegisterDragDrop(hwnd, @ptrCast(dt)) != 0) {
        plat.headlessGpa().destroy(dt);
        return;
    }
    w.drop_target = dt;
}
fn winUnregisterDropTarget(w: *plat.Window) void {
    if (w.drop_target) |raw| {
        if (asHwnd(w.hwnd)) |h| _ = w32.RevokeDragDrop(h);
        const dt: *DropTargetImpl = @ptrCast(@alignCast(raw));
        plat.headlessGpa().destroy(dt);
        w.drop_target = null;
    }
}

pub fn startDrag(w: *plat.Window, data: plat.DragData, allowed: plat.DropEffects) !plat.DropEffect {
    const hwnd = asHwnd(w.hwnd) orelse return error.Unsupported;
    var obj = DataObjectImpl{ .vtbl = &data_vtbl, .files = data.files, .text = data.text };
    const src = w32.IDROPSOURCE{ .vtbl = &drop_src_vtbl };
    var allowed_bits: u32 = 0;
    if (allowed.copy) allowed_bits |= 1;
    if (allowed.move) allowed_bits |= 2;
    if (allowed.link) allowed_bits |= 4;
    var effect: u32 = 0;
    const hr = w32.DoDragDrop(hwnd, @ptrCast(&obj), @ptrCast(&src), allowed_bits, &effect);
    if (hr != 0 and hr != 0x00040100) return error.PlatformFailed;
    return switch (effect) {
        1 => .copy,
        2 => .move,
        4 => .link,
        else => .none,
    };
}

fn winIconFromSet(icon: plat.IconSet) ?*anyopaque {
    if (icon.len == 0) return null;
    const desired: u32 = @intCast(@max(16, w32.GetSystemMetrics(w32.SM_CXSMICON)));
    var best: ?plat.IconPixels = null;
    for (icon) |p| {
        if (p.w == 0 or p.h == 0 or p.rgba.len < @as(usize, p.w) * p.h * 4) continue;
        if (best == null or (@as(i64, p.w) - @as(i64, desired)) < (@as(i64, best.?.w) - @as(i64, desired))) best = p;
    }
    const p = best orelse return null;
    var bmi = w32.BITMAPINFO{};
    bmi.bmiHeader.biWidth = @intCast(p.w);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(p.h));
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const color = w32.CreateDIBSection(null, &bmi, 0, &bits, null, 0) orelse return null;
    const dst: [*]u8 = @ptrCast(bits orelse {
        _ = w32.DeleteObject(color);
        return null;
    });
    var i: usize = 0;
    while (i < @as(usize, p.w) * p.h) : (i += 1) {
        const o = i * 4;
        const a: u32 = p.rgba[o + 3];
        dst[o] = @intCast((@as(u32, p.rgba[o + 2]) * a) / 255);
        dst[o + 1] = @intCast((@as(u32, p.rgba[o + 1]) * a) / 255);
        dst[o + 2] = @intCast((@as(u32, p.rgba[o]) * a) / 255);
        dst[o + 3] = @intCast(a);
    }
    const mask = w32.CreateBitmap(@intCast(p.w), @intCast(p.h), 1, 1, null) orelse {
        _ = w32.DeleteObject(color);
        return null;
    };
    var info = w32.ICONINFO{ .hbmColor = color, .hbmMask = mask };
    const hicon = w32.CreateIconIndirect(&info);
    _ = w32.DeleteObject(color);
    _ = w32.DeleteObject(mask);
    return hicon;
}

pub fn trayAdd(owner: *plat.Window, id: u32, icon: plat.IconSet, tooltip: []const u8) !void {
    const hwnd = asHwnd(owner.hwnd) orelse return error.PlatformFailed;
    plat.ensureTaskbarCreatedMsg(w32.RegisterWindowMessageW(std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated")));
    const hicon = winIconFromSet(icon) orelse w32.LoadIconW(null, 32512);
    var data = w32.NOTIFYICONDATAW{
        .hWnd = hwnd,
        .uID = id,
        .uFlags = w32.NIF_MESSAGE | w32.NIF_ICON | w32.NIF_TIP,
        .uCallbackMessage = wm_tray_callback,
        .hIcon = hicon,
    };
    fillWide(&data.szTip, tooltip);
    if (w32.SHELL_NOTIFY_ICON_W(w32.NIM_ADD, &data) == 0) return error.PlatformFailed;
    data.uVersion = w32.NOTIFYICON_VERSION_4;
    _ = w32.SHELL_NOTIFY_ICON_W(w32.NIM_SETVERSION, &data);
    try plat.appendWinTrayEntry(id, owner, hicon, tooltip);
}

pub fn trayModify(id: u32, icon: ?plat.IconSet, tooltip: ?[]const u8) !void {
    const e = plat.findWinTrayEntry(id) orelse return error.PlatformFailed;
    var data = w32.NOTIFYICONDATAW{ .hWnd = asHwnd(e.owner.hwnd), .uID = id };
    if (icon) |set| {
        if (winIconFromSet(set)) |h| {
            if (e.hicon) |old| _ = w32.DestroyIcon(old);
            e.hicon = h;
            data.uFlags |= w32.NIF_ICON;
            data.hIcon = h;
        }
    }
    if (tooltip) |t| {
        data.uFlags |= w32.NIF_TIP;
        fillWide(&data.szTip, t);
        try plat.updateWinTrayTooltip(e, t);
    }
    if (w32.SHELL_NOTIFY_ICON_W(w32.NIM_MODIFY, &data) == 0) return error.PlatformFailed;
}

pub fn trayBalloon(id: u32, title: []const u8, text: []const u8, kind: plat.BalloonKind) !void {
    const e = plat.findWinTrayEntry(id) orelse return error.PlatformFailed;
    var data = w32.NOTIFYICONDATAW{ .hWnd = asHwnd(e.owner.hwnd), .uID = id, .uFlags = w32.NIF_INFO };
    fillWide(&data.szInfo, text);
    fillWide(&data.szInfoTitle, title);
    data.dwInfoFlags = switch (kind) {
        .none => 0,
        .info => 1,
        .warning => 2,
        .@"error" => 3,
    };
    _ = w32.SHELL_NOTIFY_ICON_W(w32.NIM_MODIFY, &data);
}

pub fn trayRemove(id: u32) void {
    if (plat.findWinTrayEntry(id)) |e| {
        var data = w32.NOTIFYICONDATAW{ .hWnd = asHwnd(e.owner.hwnd), .uID = id };
        _ = w32.SHELL_NOTIFY_ICON_W(w32.NIM_DELETE, &data);
        if (e.hicon) |h| _ = w32.DestroyIcon(h);
        plat.removeWinTrayEntry(id);
    }
}

fn winTrayReAddAll() void {
    for (plat.winTrayEntriesSlice()) |e| {
        var data = w32.NOTIFYICONDATAW{
            .hWnd = asHwnd(e.owner.hwnd),
            .uID = e.id,
            .uFlags = w32.NIF_MESSAGE | w32.NIF_ICON | w32.NIF_TIP,
            .uCallbackMessage = wm_tray_callback,
            .hIcon = e.hicon,
        };
        fillWide(&data.szTip, e.tooltip);
        _ = w32.SHELL_NOTIFY_ICON_W(w32.NIM_ADD, &data);
    }
}

pub fn setImeCaret(w: *plat.Window, caret: plat.RectI, exclude: ?plat.RectI) void {
    const hwnd = asHwnd(w.hwnd) orelse return;
    const ctx = w32.ImmGetContext(hwnd) orelse return;
    defer _ = w32.ImmReleaseContext(hwnd, ctx);
    var cf = w32.COMPOSITIONFORM{ .dwStyle = w32.CFS_POINT, .ptCurrentPos = .{ .x = caret.x, .y = caret.y + caret.h } };
    _ = w32.ImmSetCompositionWindow(ctx, &cf);
    var cand = w32.CANDIDATEFORM{ .dwStyle = w32.CFS_CANDIDATEPOS, .ptCurrentPos = .{ .x = caret.x, .y = caret.y + caret.h } };
    if (exclude) |r| {
        cand.dwStyle = w32.CFS_EXCLUDE;
        cand.rcArea = .{ .left = r.x, .top = r.y, .right = r.x + r.w, .bottom = r.y + r.h };
    }
    _ = w32.ImmSetCandidateWindow(ctx, &cand);
}

pub fn setImeEnabled(w: *plat.Window, enabled: bool) void {
    const hwnd = asHwnd(w.hwnd) orelse return;
    if (enabled) {
        if (w.ime_saved_context != null) {
            _ = w32.ImmAssociateContext(hwnd, w.ime_saved_context);
            w.ime_saved_context = null;
        }
    } else {
        const prev = w32.ImmAssociateContext(hwnd, null);
        if (prev) |p| w.ime_saved_context = p;
    }
}

pub fn commitComposition(w: *plat.Window) void {
    const hwnd = asHwnd(w.hwnd) orelse return;
    const ctx = w32.ImmGetContext(hwnd) orelse return;
    defer _ = w32.ImmReleaseContext(hwnd, ctx);
    _ = w32.ImmNotifyIME(ctx, w32.CPS_COMPLETE, 0, 0);
}

pub fn clipboardGetText(allocator: std.mem.Allocator) !?[]u8 {
    if (w32.OpenClipboard(null) == 0) return error.ClipboardBusy;
    defer _ = w32.CloseClipboard();
    if (w32.IsClipboardFormatAvailable(w32.CF_UNICODETEXT) == 0) return null;
    const handle = w32.GetClipboardData(w32.CF_UNICODETEXT) orelse return null;
    const locked = w32.GlobalLock(handle) orelse return error.ClipboardLockFailed;
    defer _ = w32.GlobalUnlock(handle);
    const ptr: [*:0]const u16 = @ptrCast(@alignCast(locked));
    const slice = std.mem.sliceTo(ptr, 0);
    return try std.unicode.utf16LeToUtf8Alloc(allocator, slice);
}

pub fn clipboardSetText(text: []const u8) !void {
    const gpa = plat.headlessGpa();
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(gpa, text);
    defer gpa.free(wide);
    if (w32.OpenClipboard(null) == 0) return error.ClipboardBusy;
    defer _ = w32.CloseClipboard();
    if (w32.EmptyClipboard() == 0) return error.ClipboardFailed;
    const bytes = wide.len * @sizeOf(u16);
    const mem = w32.GlobalAlloc(w32.GMEM_MOVEABLE, bytes) orelse return error.OutOfMemory;
    const locked = w32.GlobalLock(mem) orelse {
        _ = w32.GlobalFree(mem);
        return error.ClipboardLockFailed;
    };
    @memcpy(@as([*]u8, @ptrCast(locked))[0..bytes], std.mem.sliceAsBytes(wide));
    _ = w32.GlobalUnlock(mem);
    if (w32.SetClipboardData(w32.CF_UNICODETEXT, mem) == null) {
        _ = w32.GlobalFree(mem);
        return error.ClipboardFailed;
    }
}

pub fn clipboardHasText() bool {
    return w32.IsClipboardFormatAvailable(w32.CF_UNICODETEXT) != 0;
}

pub fn clipboardSeq() u32 {
    return w32.GetClipboardSequenceNumber();
}

pub fn fileDialog(opts: plat.FileDialogOptions, save: bool) !?[]const plat.Path {
    plat.clearDialogPaths();
    const gpa = plat.headlessGpa();
    var file_buf: [32768]u16 = undefined;
    @memset(&file_buf, 0);
    if (opts.initial_name) |name| {
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(gpa, name);
        defer gpa.free(wide);
        const n = @min(wide.len, file_buf.len - 1);
        @memcpy(file_buf[0..n], wide[0..n]);
    }
    const title = if (opts.title.len > 0) try std.unicode.utf8ToUtf16LeAllocZ(gpa, opts.title) else null;
    defer if (title) |t| gpa.free(t);
    const dir = if (opts.initial_dir) |d| try std.unicode.utf8ToUtf16LeAllocZ(gpa, d) else null;
    defer if (dir) |d| gpa.free(d);
    var ofn = w32.OPENFILENAMEW{
        .lpstrFile = &file_buf,
        .nMaxFile = file_buf.len,
        .lpstrTitle = if (title) |t| t.ptr else null,
        .lpstrInitialDir = if (dir) |d| d.ptr else null,
        .Flags = 0x00080000 | 0x00001000 | 0x00000800,
    };
    if (!save and opts.multi) ofn.Flags |= 0x00000200;
    const ok = if (save) w32.GetSaveFileNameW(&ofn) else w32.GetOpenFileNameW(&ofn);
    if (ok == 0) return null;
    const total = std.mem.indexOfScalar(u16, &file_buf, 0) orelse return null;
    if (save or !opts.multi or file_buf[total + 1] == 0) {
        try plat.addDialogPathUtf16(file_buf[0..total]);
    } else {
        const d = file_buf[0..total];
        var i = total + 1;
        while (i < file_buf.len and file_buf[i] != 0) {
            var j = i;
            while (j < file_buf.len and file_buf[j] != 0) j += 1;
            const name = file_buf[i..j];
            var joined = std.ArrayListUnmanaged(u16).empty;
            defer joined.deinit(gpa);
            try joined.appendSlice(gpa, d);
            try joined.append(gpa, '\\');
            try joined.appendSlice(gpa, name);
            try plat.addDialogPathUtf16(joined.items);
            i = j + 1;
        }
    }
    return plat.dialogPathsSlice();
}

pub fn pickFolder(opts: plat.FileDialogOptions) !?plat.Path {
    plat.clearDialogPaths();
    const gpa = plat.headlessGpa();
    var display: [260]u16 = @splat(0);
    const title = if (opts.title.len > 0) try std.unicode.utf8ToUtf16LeAllocZ(gpa, opts.title) else null;
    defer if (title) |t| gpa.free(t);
    var bi = w32.BROWSEINFOW{
        .pszDisplayName = &display,
        .lpszTitle = if (title) |t| t.ptr else null,
        .ulFlags = 0x00000040,
    };
    const pidl = w32.SHBrowseForFolderW(&bi) orelse return null;
    defer w32.CoTaskMemFree(pidl);
    var path: [32768]u16 = undefined;
    @memset(&path, 0);
    if (w32.SHGetPathFromIDListW(pidl, &path) == 0) return null;
    const total = std.mem.indexOfScalar(u16, &path, 0) orelse return null;
    try plat.addDialogPathUtf16(path[0..total]);
    return plat.dialogPathsSlice()[0];
}

pub fn pickColor(initial: core.Color) ?core.Color {
    var customs: [16]u32 = @splat(0);
    var cc = w32.CHOOSECOLORW{
        .rgbResult = (@as(u32, initial.r) | (@as(u32, initial.g) << 8) | (@as(u32, initial.b) << 16)),
        .lpCustColors = &customs,
        .Flags = 0x00000001,
    };
    if (w32.ChooseColorW(&cc) == 0) return null;
    const rgb = cc.rgbResult;
    return .{ .r = @truncate(rgb), .g = @truncate(rgb >> 8), .b = @truncate(rgb >> 16), .a = 255 };
}

fn w32Proc(hwnd: w32.HWND, msg: u32, wp: usize, lp: isize) callconv(.winapi) isize {
    const w = w32Find(hwnd) orelse return w32.DefWindowProcW(hwnd, msg, wp, lp);
    const gpa = plat.headlessGpa();
    if (msg == wm_tray_callback) {
        const raw_bits: usize = @bitCast(lp);
        const ev: u32 = @truncate(raw_bits & 0xFFFF);
        const id: u32 = @truncate(raw_bits >> 16);
        var pt = w32.POINT{};
        _ = w32.GetCursorPos(&pt);
        const kind: ?plat.TrayEventKind = switch (ev) {
            0x0202 => .click,
            0x0203 => .double_click,
            0x0205 => .context_menu,
            0x0405 => .balloon_clicked,
            else => null,
        };
        if (kind) |k| w32Push(w, .{ .tray = .{ .id = id, .kind = k, .screen_pos = .{ .x = pt.x, .y = pt.y } } });
        return 0;
    }
    if (plat.taskbarCreatedMsg() != 0 and msg == plat.taskbarCreatedMsg()) {
        winTrayReAddAll();
        return 0;
    }
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
            const steps = plat.accumulateWheel(&w.wheel_acc[@backingInt(plat.Axis.vertical)], raw);
            w32Push(w, .{ .wheel = .{ .axis = .vertical, .raw = raw, .steps = steps, .pos = .{ .x = pt.x, .y = pt.y }, .mods = w32Mods() } });
        },
        w32.WM_KEYDOWN, w32.WM_SYSKEYDOWN, w32.WM_KEYUP, w32.WM_SYSKEYUP => {
            const down = msg == w32.WM_KEYDOWN or msg == w32.WM_SYSKEYDOWN;
            const vk: u16 = @truncate(wp & 0xFFFF);
            const lp_u: usize = @bitCast(lp);
            if (std.enums.fromInt(plat.VirtualKey, vk)) |key| {
                w32Push(w, .{ .key = .{ .vk = key, .scancode = @truncate(lp_u), .down = down, .repeat = ((lp_u >> 30) & 1) != 0, .mods = w32Mods(), .extended = ((lp_u >> 24) & 1) != 0 } });
            }
        },
        w32.WM_CHAR => {
            const cp: u21 = @intCast(@as(u16, @truncate(wp & 0xFFFF)));
            if (cp >= 0x20 and cp != 0x7F) {
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &buf) catch 0;
                if (n > 0) {
                    const copy = gpa.dupe(u8, buf[0..n]) catch return 0;
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
        w32.WM_IME_SETCONTEXT => {
            const new_lp = lp & ~@as(isize, 1);
            return w32.DefWindowProcW(hwnd, msg, wp, new_lp);
        },
        w32.WM_IME_STARTCOMPOSITION => {
            plat.setHeadlessImeActive(true);
            w32Push(w, .ime_start);
        },
        w32.WM_IME_ENDCOMPOSITION => {
            plat.setHeadlessImeActive(false);
            w32Push(w, .ime_end);
        },
        w32.WM_IME_COMPOSITION => {
            const flags: u32 = @intCast(lp);
            if (flags & w32.GCS_RESULTSTR != 0) {
                const ctx = w32.ImmGetContext(hwnd);
                if (ctx) |c| {
                    const n = w32.ImmGetCompositionStringW(c, w32.GCS_RESULTSTR, null, 0);
                    if (n > 0) {
                        const buf = gpa.alloc(u16, @intCast(@divTrunc(n, 2))) catch return 0;
                        defer gpa.free(buf);
                        _ = w32.ImmGetCompositionStringW(c, w32.GCS_RESULTSTR, buf.ptr, @intCast(n));
                        const utf8 = std.unicode.utf16LeToUtf8Alloc(gpa, buf) catch null;
                        if (utf8) |t| w32Push(w, .{ .ime_commit = t });
                    }
                    _ = w32.ImmReleaseContext(hwnd, c);
                }
            } else if (flags & w32.GCS_COMPSTR != 0) {
                const ctx = w32.ImmGetContext(hwnd);
                if (ctx) |c| {
                    const n = w32.ImmGetCompositionStringW(c, w32.GCS_COMPSTR, null, 0);
                    if (n > 0) {
                        const u16_len: usize = @intCast(@divTrunc(n, 2));
                        const buf = gpa.alloc(u16, u16_len) catch return 0;
                        defer gpa.free(buf);
                        _ = w32.ImmGetCompositionStringW(c, w32.GCS_COMPSTR, buf.ptr, @intCast(n));
                        const utf8 = std.unicode.utf16LeToUtf8Alloc(gpa, buf) catch null;
                        if (utf8) |t| {
                            var segs: []plat.ImeSegment = &.{};
                            if (flags & w32.GCS_COMPATTR != 0) {
                                const an = w32.ImmGetCompositionStringW(c, w32.GCS_COMPATTR, null, 0);
                                if (an > 0) {
                                    const abuf = gpa.alloc(u8, @intCast(an)) catch @as([]u8, &.{});
                                    defer if (abuf.len > 0) gpa.free(abuf);
                                    if (abuf.len == buf.len) {
                                        _ = w32.ImmGetCompositionStringW(c, w32.GCS_COMPATTR, abuf.ptr, @intCast(an));
                                        segs = plat.imeSegmentsFromUtf16(gpa, buf, abuf) catch &.{};
                                    }
                                }
                            }
                            const cpos_raw = w32.ImmGetCompositionStringW(c, w32.GCS_CURSORPOS, null, 0);
                            const cpos: usize = if (cpos_raw >= 0) blk: {
                                const cu16: usize = @min(@as(usize, @intCast(cpos_raw)), buf.len);
                                const pref = std.unicode.utf16LeToUtf8Alloc(gpa, buf[0..cu16]) catch null;
                                defer if (pref) |p| gpa.free(p);
                                break :blk if (pref) |p| p.len else t.len;
                            } else t.len;
                            w32Push(w, .{ .ime_update = .{ .text = t, .cursor = cpos, .segments = segs } });
                        }
                    }
                    _ = w32.ImmReleaseContext(hwnd, c);
                }
            }
        },
        w32.WM_GETOBJECT => {
            if (uia.handleGetObject(lp)) return 0;
        },
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

pub fn createWindow(opts: plat.WindowOptions) !*plat.Window {
    init();
    const gpa = plat.headlessGpa();
    const w = try gpa.create(plat.Window);
    w.* = .{
        .id = plat.allocWindowId(),
        .title = opts.title,
        .client = .{ .w = @intFromFloat(@round(opts.client_size.w)), .h = @intFromFloat(@round(opts.client_size.h)) },
        .visible = !opts.hidden,
        .dpi = 96,
    };
    var r = w32.RECT{ .left = 0, .top = 0, .right = w.client.w, .bottom = w.client.h };
    _ = w32.AdjustWindowRectEx(&r, 0x00CF0000, 0, 0);
    const title_z = try std.unicode.utf8ToUtf16LeAllocZ(gpa, opts.title);
    defer gpa.free(title_z);
    const cls = std.unicode.utf8ToUtf16LeStringLiteral("nano_gui_win32");
    const hwnd = w32.CreateWindowExW(0, cls, title_z.ptr, 0x00CF0000, w32.CW_USEDEFAULT, w32.CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, null, null, w32_instance, null) orelse return error.CreateWindowFailed;
    w.hwnd = @ptrCast(hwnd);
    const dc = w32.GetDC(hwnd);
    if (dc) |d| {
        var pfd = w32.PIXELFORMATDESCRIPTOR{
            .dwFlags = w32.PFD_DRAW_TO_WINDOW | w32.PFD_SUPPORT_OPENGL | w32.PFD_DOUBLEBUFFER,
        };
        const fmt = w32.ChoosePixelFormat(d, &pfd);
        if (fmt != 0 and w32.SetPixelFormat(d, fmt, &pfd) != 0) {
            w.hdc = d;
        } else {
            _ = w32.ReleaseDC(hwnd, d);
        }
    }
    winRegisterDropTarget(w);
    const dpi = w32.GetDpiForWindow(hwnd);
    if (dpi != 0) {
        w.dpi = dpi;
        w.scale_value = @as(f32, @floatFromInt(dpi)) / 96.0;
    }
    try plat.appendWindow(w);
    if (!opts.hidden) {
        _ = w32.ShowWindow(hwnd, w32.SW_SHOW);
        _ = w32.UpdateWindow(hwnd);
    }
    return w;
}

pub fn pump() usize {
    var msg: w32.MSG = .{};
    var n: usize = 0;
    while (w32.PeekMessageW(&msg, null, 0, 0, w32.PM_REMOVE) != 0) {
        _ = w32.TranslateMessage(&msg);
        _ = w32.DispatchMessageW(&msg);
        n += 1;
    }
    return n;
}

pub fn wait(timeout_ms: ?u32) plat.WaitResult {
    const ms: u32 = if (timeout_ms) |v| v else 0xFFFFFFFF;
    const r = w32.MsgWaitForMultipleObjectsEx(0, null, ms, w32.QS_ALLINPUT, w32.MWMO_INPUTAVAILABLE);
    if (r == 0) return .message;
    if (r == 258) return .timeout;
    return .idle;
}

pub fn nowMs() u64 {
    var c: i64 = 0;
    _ = w32.QueryPerformanceCounter(&c);
    if (w32_qpc_freq == 0) return @intCast(@divTrunc(c, 1000));
    return @intCast(@divTrunc(c * 1000, w32_qpc_freq));
}

pub fn present(w: *plat.Window) void {
    const hwnd = asHwnd(w.hwnd) orelse return;
    if (w.present_rgba.len == 0 or w.present_w == 0 or w.present_h == 0) return;
    if (w.nanovg_surface) return;
    if (w.gl_ready) {
        const dc = w.hdc orelse return;
        const rc = w.hglrc orelse return;
        const pf = w.gl_present_fn orelse return;
        if (pf(dc, rc, w.present_w, w.present_h, w.present_rgba)) _ = w32.SwapBuffers(dc);
        return;
    }
    const dc = w32.GetDC(hwnd) orelse return;
    defer _ = w32.ReleaseDC(hwnd, dc);
    var bmi = w32.BITMAPINFO{};
    bmi.bmiHeader.biWidth = @intCast(w.present_w);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(w.present_h));
    var buf = plat.headlessGpa().alloc(u8, w.present_rgba.len) catch return;
    defer plat.headlessGpa().free(buf);
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
