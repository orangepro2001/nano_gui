//! UI Automation 提供者骨架（M6）。
//!
//! 与平台无关的部分先固定：控件角色、模式、名称/值来源与节点遍历接口。
//! Win32 后端在 `WM_GETOBJECT` 时把该提供者桥接到 UIA COM；当前 Linux 宿主
//! 使用同一接口做单元测试与调试快照。

const std = @import("std");
const core = @import("core.zig");

pub const ControlType = enum {
    button,
    checkbox,
    radio_button,
    switch_,
    slider,
    progress,
    edit,
    text,
    list,
    list_item,
    tree,
    tree_item,
    table,
    data_grid,
    menu,
    menu_item,
    dialog,
    tooltip,
    custom,
};

pub const Pattern = enum {
    invoke,
    toggle,
    value,
    selection,
    selection_item,
    scroll,
    scroll_item,
    expand_collapse,
    grid,
    table,
    range_value,
    text,
};

pub const Node = struct {
    id: core.WidgetId,
    control_type: ControlType = .custom,
    name: []const u8 = "",
    value: []const u8 = "",
    enabled: bool = true,
    focused: bool = false,
    selected: bool = false,
    expanded: ?bool = null,
    patterns: []const Pattern = &.{},
    parent: core.WidgetId = .none,
};

pub const Provider = struct {
    ctx: *anyopaque,
    root: *const fn (ctx: *anyopaque) Node,
    children: *const fn (ctx: *anyopaque, id: core.WidgetId, out: *std.ArrayListUnmanaged(Node)) void,
    invoke: ?*const fn (ctx: *anyopaque, id: core.WidgetId) void = null,
    setValue: ?*const fn (ctx: *anyopaque, id: core.WidgetId, text: []const u8) bool = null,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    provider: ?Provider = null,
    enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Registry) void {
        self.* = undefined;
    }
    pub fn set(self: *Registry, provider: ?Provider) void {
        self.provider = provider;
        self.enabled = provider != null;
    }
    pub fn isEnabled(self: *const Registry) bool {
        return self.enabled;
    }
    pub fn roleName(t: ControlType) []const u8 {
        return @tagName(t);
    }
    pub fn patternName(p: Pattern) []const u8 {
        return @tagName(p);
    }
};

test "uia role/pattern names are stable" {
    try std.testing.expectEqualStrings("button", Registry.roleName(.button));
    try std.testing.expectEqualStrings("invoke", Registry.patternName(.invoke));
}
