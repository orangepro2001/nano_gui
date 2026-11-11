//! DirectWrite 后端的编译期验证骨架（ADR 0003）。
//!
//! 该文件只在 Windows 目标编译；它建立 DWrite 工厂，固定后端入口、GUID 与
//! HRESULT 约定。完整排版/字形栅格在当前 Linux 环境无法运行验证，因此文字
//! 度量仍由 fixed 后端提供，DirectWrite 的接入点保持显式而非伪装成已完成。

const std = @import("std");
const win = std.os.windows;

pub const FACTORY_TYPE_SHARED: u32 = 0;
pub const IID_IDWriteFactory = win.GUID{
    .Data1 = 0xb859ee5a,
    .Data2 = 0xd838,
    .Data3 = 0x4b5b,
    .Data4 = .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 },
};

extern "dwrite" fn DWriteCreateFactory(factory_type: u32, iid: *const win.GUID, factory: *?*anyopaque) callconv(.winapi) i32;

var factory: ?*anyopaque = null;
var tried: bool = false;

pub fn ensureFactory() bool {
    if (tried) return factory != null;
    tried = true;
    var f: ?*anyopaque = null;
    const hr = DWriteCreateFactory(FACTORY_TYPE_SHARED, &IID_IDWriteFactory, &f);
    if (hr >= 0) factory = f;
    return factory != null;
}

pub fn isAvailable() bool {
    return ensureFactory();
}
