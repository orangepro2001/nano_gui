//! Win32 API 绑定声明（REQ-CONV-018、REQ-CONV-019）。
//! 仅包含外部函数、Win32 结构体与 Win32 常量，不含带函数体的包装函数。

pub const HWND = @import("std").os.windows.HWND;
pub const HINSTANCE = @import("std").os.windows.HINSTANCE;

pub const WM_DESTROY: u32 = 0x0002;
pub const WM_SIZE: u32 = 0x0005;
pub const WM_ACTIVATE: u32 = 0x0006;
pub const WM_SETFOCUS: u32 = 0x0007;
pub const WM_KILLFOCUS: u32 = 0x0008;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_CLOSE: u32 = 0x0010;
pub const WM_ERASEBKGND: u32 = 0x0014;
pub const WM_ACTIVATEAPP: u32 = 0x001C;
pub const WM_SETCURSOR: u32 = 0x0020;
pub const WM_GETMINMAXINFO: u32 = 0x0024;
pub const WM_GETOBJECT: u32 = 0x003D;
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;
pub const WM_CHAR: u32 = 0x0102;
pub const WM_SYSKEYDOWN: u32 = 0x0104;
pub const WM_SYSKEYUP: u32 = 0x0105;
pub const WM_IME_STARTCOMPOSITION: u32 = 0x010D;
pub const WM_IME_ENDCOMPOSITION: u32 = 0x010E;
pub const WM_IME_COMPOSITION: u32 = 0x010F;
pub const WM_TIMER: u32 = 0x0113;
pub const WM_MOUSEMOVE: u32 = 0x0200;
pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;
pub const WM_RBUTTONDOWN: u32 = 0x0204;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_MBUTTONDOWN: u32 = 0x0207;
pub const WM_MBUTTONUP: u32 = 0x0208;
pub const WM_MOUSEWHEEL: u32 = 0x020A;
pub const WM_IME_SETCONTEXT: u32 = 0x0281;
pub const WM_DPICHANGED: u32 = 0x02E0;
pub const WM_USER: u32 = 0x0400;

pub const PM_REMOVE: u32 = 1;
pub const QS_ALLINPUT: u32 = 0x04FF;
pub const MWMO_INPUTAVAILABLE: u32 = 0x0004;
pub const CW_USEDEFAULT: i32 = -2147483648;
pub const CF_UNICODETEXT: u32 = 13;
pub const CF_HDROP: u32 = 15;
pub const GMEM_MOVEABLE: u32 = 0x0002;

pub const SW_HIDE: i32 = 0;
pub const SW_SHOW: i32 = 5;
pub const SW_MINIMIZE: i32 = 6;
pub const SW_RESTORE: i32 = 9;

pub const GCS_COMPSTR: u32 = 0x0008;
pub const GCS_COMPATTR: u32 = 0x0010;
pub const GCS_CURSORPOS: u32 = 0x0080;
pub const GCS_RESULTSTR: u32 = 0x0800;
pub const CFS_POINT: u32 = 1;
pub const CFS_EXCLUDE: u32 = 0x0020;
pub const CFS_CANDIDATEPOS: u32 = 0x0040;
pub const CPS_COMPLETE: u32 = 0x0015;

pub const NIM_ADD: u32 = 0;
pub const NIM_MODIFY: u32 = 1;
pub const NIM_DELETE: u32 = 2;
pub const NIM_SETVERSION: u32 = 4;
pub const NOTIFYICON_VERSION_4: u32 = 4;
pub const NIF_MESSAGE: u32 = 1;
pub const NIF_ICON: u32 = 2;
pub const NIF_TIP: u32 = 4;
pub const NIF_INFO: u32 = 0x10;
pub const SM_CXSMICON: i32 = 49;

pub const PFD_DOUBLEBUFFER: u32 = 0x00000001;
pub const PFD_DRAW_TO_WINDOW: u32 = 0x00000004;
pub const PFD_SUPPORT_OPENGL: u32 = 0x00000020;

pub const GUID = extern struct { data1: u32 = 0, data2: u16 = 0, data3: u16 = 0, data4: [8]u8 = @splat(0) };
pub const IID_IDROPTARGET = GUID{ .data1 = 0x00000122, .data2 = 0, .data3 = 0, .data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };
pub const IID_IDATAOBJECT = GUID{ .data1 = 0x0000010E, .data2 = 0, .data3 = 0, .data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };
pub const IID_IDROPSOURCE = GUID{ .data1 = 0x00000121, .data2 = 0, .data3 = 0, .data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };
pub const IID_IUNKNOWN = GUID{ .data1 = 0, .data2 = 0, .data3 = 0, .data4 = .{ 0xC0, 0, 0, 0, 0, 0, 0, 0x46 } };

pub const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
pub const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
pub const POINTL = extern struct { x: i32 = 0, y: i32 = 0 };
pub const FILETIME = extern struct { dwLowDateTime: u32 = 0, dwHighDateTime: u32 = 0 };
pub const MINMAXINFO = extern struct { ptReserved: POINT = .{}, ptMaxSize: POINT = .{}, ptMaxPosition: POINT = .{}, ptMinTrackSize: POINT = .{}, ptMaxTrackSize: POINT = .{} };

pub const MSG = extern struct {
    hwnd: ?HWND = null,
    message: u32 = 0,
    wParam: usize = 0,
    lParam: isize = 0,
    time: u32 = 0,
    pt: POINT = .{},
    lPrivate: u32 = 0,
};

pub const WNDCLASSW = extern struct {
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, usize, isize) callconv(.winapi) isize = undefined,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16 = undefined,
};

pub const PAINTSTRUCT = extern struct {
    hdc: ?*anyopaque = null,
    fErase: i32 = 0,
    rcPaint: RECT = .{},
    fRestore: i32 = 0,
    fIncUpdate: i32 = 0,
    rgbReserved: [32]u8 = @splat(0),
};

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: u16 = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: u16 = 1,
    dwFlags: u32 = 0,
    iPixelType: u8 = 0,
    cColorBits: u8 = 32,
    cRedBits: u8 = 0,
    cRedShift: u8 = 0,
    cGreenBits: u8 = 0,
    cGreenShift: u8 = 0,
    cBlueBits: u8 = 0,
    cBlueShift: u8 = 0,
    cAlphaBits: u8 = 8,
    cAlphaShift: u8 = 0,
    cAccumBits: u8 = 0,
    cAccumRedBits: u8 = 0,
    cAccumGreenBits: u8 = 0,
    cAccumBlueBits: u8 = 0,
    cAccumAlphaBits: u8 = 0,
    cDepthBits: u8 = 24,
    cStencilBits: u8 = 8,
    cAuxBuffers: u8 = 0,
    iLayerType: u8 = 0,
    bReserved: u8 = 0,
    dwLayerMask: u32 = 0,
    dwVisibleMask: u32 = 0,
    dwDamageMask: u32 = 0,
};

pub const BITMAPINFOHEADER = extern struct {
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

pub const BITMAPINFO = extern struct { bmiHeader: BITMAPINFOHEADER = .{}, bmiColors: [1]u32 = .{0} };

pub const ICONINFO = extern struct {
    fIcon: i32 = 1,
    xHotspot: u32 = 0,
    yHotspot: u32 = 0,
    hbmMask: ?*anyopaque = null,
    hbmColor: ?*anyopaque = null,
};

pub const NOTIFYICONDATAW = extern struct {
    cbSize: u32 = @sizeOf(NOTIFYICONDATAW),
    hWnd: ?HWND = null,
    uID: u32 = 0,
    uFlags: u32 = 0,
    uCallbackMessage: u32 = 0,
    hIcon: ?*anyopaque = null,
    szTip: [128]u16 = @splat(0),
    dwState: u32 = 0,
    dwStateMask: u32 = 0,
    szInfo: [256]u16 = @splat(0),
    uVersion: u32 = 0,
    szInfoTitle: [64]u16 = @splat(0),
    dwInfoFlags: u32 = 0,
    guidItem: GUID = .{},
    hBalloonIcon: ?*anyopaque = null,
};

pub const COMPOSITIONFORM = extern struct {
    dwStyle: u32 = 1,
    ptCurrentPos: POINT = .{},
    rcArea: RECT = .{},
};

pub const CANDIDATEFORM = extern struct {
    dwIndex: u32 = 0,
    dwStyle: u32 = 0,
    ptCurrentPos: POINT = .{},
    rcArea: RECT = .{},
};

pub const FORMATETC = extern struct {
    cfFormat: u16 = 0,
    ptd: ?*anyopaque = null,
    dwAspect: u32 = 1,
    lindex: i32 = -1,
    tymed: u32 = 1,
};

pub const STGMEDIUM = extern struct {
    tymed: u32 = 1,
    hGlobal: ?*anyopaque = null,
    pUnkForRelease: ?*anyopaque = null,
};

pub const DROPFILES = extern struct {
    pFiles: u32 = 20,
    pt: POINTL = .{},
    fNC: i32 = 0,
    fWide: i32 = 1,
};

pub const IDATAOBJECTVTBL = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
    GetData: *const fn (*anyopaque, *const FORMATETC, *STGMEDIUM) callconv(.winapi) i32,
    GetDataHere: *const anyopaque,
    QueryGetData: *const fn (*anyopaque, *const FORMATETC) callconv(.winapi) i32,
    GetCanonicalFormatEtc: *const anyopaque,
    SetData: *const anyopaque,
    EnumFormatEtc: *const anyopaque,
    DAdvise: *const anyopaque,
    DUnadvise: *const anyopaque,
    EnumDAdvise: *const anyopaque,
};
pub const IDATAOBJECT = extern struct { vtbl: *const IDATAOBJECTVTBL };

pub const IDROPSOURCEVTBL = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
    QueryContinueDrag: *const fn (*anyopaque, i32, u32) callconv(.winapi) i32,
    GiveFeedback: *const fn (*anyopaque, u32) callconv(.winapi) i32,
};
pub const IDROPSOURCE = extern struct { vtbl: *const IDROPSOURCEVTBL };

pub const IDROPTARGETVTBL = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
    DragEnter: *const fn (*anyopaque, ?*IDATAOBJECT, u32, POINTL, *u32) callconv(.winapi) i32,
    DragOver: *const fn (*anyopaque, u32, POINTL, *u32) callconv(.winapi) i32,
    DragLeave: *const fn (*anyopaque) callconv(.winapi) i32,
    Drop: *const fn (*anyopaque, ?*IDATAOBJECT, u32, POINTL, *u32) callconv(.winapi) i32,
};

pub const OPENFILENAMEW = extern struct {
    lStructSize: u32 = @sizeOf(OPENFILENAMEW),
    hwndOwner: ?HWND = null,
    hInstance: ?HINSTANCE = null,
    lpstrFilter: ?[*:0]const u16 = null,
    lpstrCustomFilter: ?[*]u16 = null,
    nMaxCustFilter: u32 = 0,
    nFilterIndex: u32 = 0,
    lpstrFile: [*]u16 = undefined,
    nMaxFile: u32 = 0,
    lpstrFileTitle: ?[*]u16 = null,
    nMaxFileTitle: u32 = 0,
    lpstrInitialDir: ?[*:0]const u16 = null,
    lpstrTitle: ?[*:0]const u16 = null,
    Flags: u32 = 0,
    nFileOffset: u16 = 0,
    nFileExtension: u16 = 0,
    lpstrDefExt: ?[*:0]const u16 = null,
    lCustData: isize = 0,
    lpfnHook: ?*anyopaque = null,
    lpTemplateName: ?[*:0]const u16 = null,
    pvReserved: ?*anyopaque = null,
    dwReserved: u32 = 0,
    FlagsEx: u32 = 0,
};

pub const BROWSEINFOW = extern struct {
    hwndOwner: ?HWND = null,
    pidlRoot: ?*anyopaque = null,
    pszDisplayName: [*]u16 = undefined,
    lpszTitle: ?[*:0]const u16 = null,
    ulFlags: u32 = 0,
    lpfn: ?*anyopaque = null,
    lParam: isize = 0,
    iImage: i32 = 0,
};

pub const CHOOSECOLORW = extern struct {
    lStructSize: u32 = @sizeOf(CHOOSECOLORW),
    hwndOwner: ?HWND = null,
    hInstance: ?HINSTANCE = null,
    rgbResult: u32 = 0,
    lpCustColors: *[16]u32 = undefined,
    Flags: u32 = 0,
    lCustData: isize = 0,
    lpfnHook: ?*anyopaque = null,
    lpTemplateName: ?[*:0]const u16 = null,
};

pub extern "kernel32" fn GetCurrentProcess() callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn GetProcessTimes(proc: ?*anyopaque, c: *FILETIME, e: *FILETIME, k: *FILETIME, u: *FILETIME) callconv(.winapi) i32;
pub extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
pub extern "kernel32" fn QueryPerformanceCounter(v: *i64) callconv(.winapi) i32;
pub extern "kernel32" fn QueryPerformanceFrequency(v: *i64) callconv(.winapi) i32;
pub extern "kernel32" fn GlobalAlloc(flags: u32, bytes: usize) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn GlobalLock(mem: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(mem: ?*anyopaque) callconv(.winapi) i32;
pub extern "kernel32" fn GlobalFree(mem: ?*anyopaque) callconv(.winapi) ?*anyopaque;

pub extern "user32" fn RegisterClassW(c: *const WNDCLASSW) callconv(.winapi) u16;
pub extern "user32" fn CreateWindowExW(ex: u32, class: [*:0]const u16, title: [*:0]const u16, style: u32, x: i32, y: i32, w: i32, h: i32, parent: ?HWND, menu: ?*anyopaque, inst: ?HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?HWND;
pub extern "user32" fn DefWindowProcW(h: HWND, m: u32, w: usize, l: isize) callconv(.winapi) isize;
pub extern "user32" fn DestroyWindow(h: HWND) callconv(.winapi) i32;
pub extern "user32" fn ShowWindow(h: HWND, cmd: i32) callconv(.winapi) i32;
pub extern "user32" fn UpdateWindow(h: HWND) callconv(.winapi) i32;
pub extern "user32" fn GetClientRect(h: HWND, r: *RECT) callconv(.winapi) i32;
pub extern "user32" fn GetWindowRect(h: HWND, r: *RECT) callconv(.winapi) i32;
pub extern "user32" fn AdjustWindowRectEx(r: *RECT, style: u32, menu: i32, ex: u32) callconv(.winapi) i32;
pub extern "user32" fn GetDpiForWindow(h: HWND) callconv(.winapi) u32;
pub extern "user32" fn PeekMessageW(m: *MSG, h: ?HWND, min: u32, max: u32, remove: u32) callconv(.winapi) i32;
pub extern "user32" fn TranslateMessage(m: *const MSG) callconv(.winapi) i32;
pub extern "user32" fn DispatchMessageW(m: *const MSG) callconv(.winapi) isize;
pub extern "user32" fn MsgWaitForMultipleObjectsEx(count: u32, handles: ?*const anyopaque, ms: u32, wake: u32, flags: u32) callconv(.winapi) u32;
pub extern "user32" fn PostThreadMessageW(id: u32, msg: u32, w: usize, l: isize) callconv(.winapi) i32;
pub extern "user32" fn GetKeyState(vk: i32) callconv(.winapi) i16;
pub extern "user32" fn ScreenToClient(h: HWND, p: *POINT) callconv(.winapi) i32;
pub extern "user32" fn BeginPaint(h: HWND, ps: *PAINTSTRUCT) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn EndPaint(h: HWND, ps: *const PAINTSTRUCT) callconv(.winapi) i32;
pub extern "user32" fn SetWindowTextW(h: HWND, text: [*:0]const u16) callconv(.winapi) i32;
pub extern "user32" fn GetDC(h: HWND) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn ReleaseDC(h: HWND, dc: ?*anyopaque) callconv(.winapi) i32;
pub extern "user32" fn SetCursor(c: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn LoadCursorW(inst: ?HINSTANCE, name: usize) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn OpenClipboard(h: ?HWND) callconv(.winapi) i32;
pub extern "user32" fn CloseClipboard() callconv(.winapi) i32;
pub extern "user32" fn EmptyClipboard() callconv(.winapi) i32;
pub extern "user32" fn GetClipboardData(format: u32) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn SetClipboardData(format: u32, mem: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn IsClipboardFormatAvailable(format: u32) callconv(.winapi) i32;
pub extern "user32" fn GetClipboardSequenceNumber() callconv(.winapi) u32;
pub extern "user32" fn RegisterWindowMessageW(name: [*:0]const u16) callconv(.winapi) u32;
pub extern "user32" fn DestroyIcon(icon: ?*anyopaque) callconv(.winapi) i32;
pub extern "user32" fn GetCursorPos(p: *POINT) callconv(.winapi) i32;
pub extern "user32" fn LoadIconW(inst: ?HINSTANCE, name: usize) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn GetSystemMetrics(index: i32) callconv(.winapi) i32;

pub extern "comdlg32" fn GetOpenFileNameW(ofn: *OPENFILENAMEW) callconv(.winapi) i32;
pub extern "comdlg32" fn GetSaveFileNameW(ofn: *OPENFILENAMEW) callconv(.winapi) i32;
pub extern "comdlg32" fn ChooseColorW(cc: *CHOOSECOLORW) callconv(.winapi) i32;

pub extern "shell32" fn SHBrowseForFolderW(bi: *BROWSEINFOW) callconv(.winapi) ?*anyopaque;
pub extern "shell32" fn SHGetPathFromIDListW(pidl: *const anyopaque, path: [*]u16) callconv(.winapi) i32;
pub const SHELL_NOTIFY_ICON_W = @extern(*const fn (u32, *NOTIFYICONDATAW) callconv(.winapi) i32, .{ .name = "Shell_NotifyIconW", .library_name = "shell32" });
pub extern "shell32" fn DragQueryFileW(hdrop: ?*anyopaque, index: u32, buf: [*]u16, len: u32) callconv(.winapi) u32;
pub extern "shell32" fn RegisterDragDrop(hwnd: HWND, target: *anyopaque) callconv(.winapi) i32;
pub extern "shell32" fn RevokeDragDrop(hwnd: HWND) callconv(.winapi) i32;

pub extern "ole32" fn CoTaskMemFree(p: ?*anyopaque) callconv(.winapi) void;
pub extern "ole32" fn OleInitialize(reserved: ?*anyopaque) callconv(.winapi) i32;
pub extern "ole32" fn ReleaseStgMedium(medium: *STGMEDIUM) callconv(.winapi) void;
pub extern "ole32" fn DoDragDrop(hwnd: HWND, data: *anyopaque, source: *anyopaque, allowed: u32, effect: *u32) callconv(.winapi) i32;

pub extern "imm32" fn ImmGetContext(h: HWND) callconv(.winapi) ?*anyopaque;
pub extern "imm32" fn ImmReleaseContext(h: HWND, ctx: ?*anyopaque) callconv(.winapi) i32;
pub extern "imm32" fn ImmSetCompositionWindow(ctx: ?*anyopaque, form: *const COMPOSITIONFORM) callconv(.winapi) i32;
pub extern "imm32" fn ImmSetCandidateWindow(ctx: ?*anyopaque, form: *const CANDIDATEFORM) callconv(.winapi) i32;
pub extern "imm32" fn ImmNotifyIME(ctx: ?*anyopaque, action: u32, index: u32, value: u32) callconv(.winapi) i32;
pub extern "imm32" fn ImmAssociateContext(h: HWND, ctx: ?*anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "imm32" fn ImmGetCompositionStringW(ctx: ?*anyopaque, index: u32, buf: ?*anyopaque, len: u32) callconv(.winapi) i32;

pub extern "user32" fn CreateIconIndirect(info: *ICONINFO) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn CreateDIBSection(dc: ?*anyopaque, bmi: *const BITMAPINFO, usage: u32, bits: *?*anyopaque, section: ?*anyopaque, offset: u32) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn CreateBitmap(w: i32, h: i32, planes: u32, bpp: u32, bits: ?*const anyopaque) callconv(.winapi) ?*anyopaque;
pub extern "gdi32" fn DeleteObject(obj: ?*anyopaque) callconv(.winapi) i32;
pub extern "gdi32" fn ChoosePixelFormat(dc: ?*anyopaque, pfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
pub extern "gdi32" fn SetPixelFormat(dc: ?*anyopaque, format: i32, pfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
pub extern "gdi32" fn SwapBuffers(dc: ?*anyopaque) callconv(.winapi) i32;
pub extern "gdi32" fn SetDIBitsToDevice(dc: ?*anyopaque, x: i32, y: i32, w: u32, h: u32, sx: i32, sy: i32, start: u32, lines: u32, bits: *const anyopaque, bmi: *const BITMAPINFO, usage: u32) callconv(.winapi) i32;
